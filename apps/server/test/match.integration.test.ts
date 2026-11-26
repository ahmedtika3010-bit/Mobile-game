/**
 * End-to-end: real HTTP + WebSocket server, real Postgres, real Colyseus
 * clients. Covers sign-in, onboarding, matchmaking, a full quiz match,
 * a disconnect + reconnect, persistence, rewards, ratings, and no double-grant.
 */
import { Client, type Room } from 'colyseus.js';
import type { MatchSummary, QuizView, RoomView } from '@sahra/shared';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma } from '../src/db';
import { QUIZ_TIMING } from '../src/games/quiz';
import { finalizeMatch } from '../src/rooms/finalize';
import { ROOM_TIMING } from '../src/rooms/GameRoom';
import { startServer } from '../src/server';
import { Api, resetDb, seedApprovedQuiz, sleep, waitFor } from './helpers';

let server: Awaited<ReturnType<typeof startServer>>;
let api: Api;
let wsUrl: string;

beforeAll(async () => {
  Object.assign(ROOM_TIMING, { publicCountdownMs: 300, fullRoomCountdownMs: 200, privateCountdownMs: 200, resultsHoldMs: 500 });
  Object.assign(QUIZ_TIMING, { revealLeadMs: 100, revealStageMs: 150 });
  server = await startServer(0);
  api = new Api(`http://localhost:${server.port}`);
  wsUrl = `ws://localhost:${server.port}`;
});

afterAll(async () => {
  await server.close();
  await prisma.$disconnect();
});

beforeEach(async () => {
  await resetDb();
  await seedApprovedQuiz(12);
});

interface Tracked {
  room: Room;
  views: RoomView<QuizView>[];
  summary?: MatchSummary;
  errors: { code: string }[];
  last(): RoomView<QuizView> | undefined;
}

function track(room: Room): Tracked {
  const t: Tracked = {
    room,
    views: [],
    errors: [],
    last() {
      return this.views[this.views.length - 1];
    },
  };
  room.onMessage('view', (v: RoomView<QuizView>) => t.views.push(v));
  room.onMessage('matchSummary', (m: { summary: MatchSummary }) => (t.summary = m.summary));
  room.onMessage('error', (e: { code: string }) => t.errors.push(e));
  room.onMessage('pong', () => {});
  room.onMessage('quickChat', () => {});
  return t;
}

async function joinQuick(token: string, mode: 'casual' | 'ranked') {
  const t = await api.call('POST', '/matchmaking/ticket', { gameId: 'quiz', mode }, token);
  expect(t.status).toBe(200);
  const room = await new Client(wsUrl).joinOrCreate('game', { ...t.body.options, ticket: t.body.ticket });
  return track(room);
}

/** Answers the current question with the correct choice if `correct`, otherwise a wrong one. */
async function answerCurrent(t: Tracked, correct: boolean) {
  const v = await waitFor(() => {
    const l = t.last();
    if (t.views.some((x) => x.game?.stage === 'finished')) throw new Error('finished');
    return l?.game?.stage === 'question' && l.game.yourChoice === null && l.game.question ? l : null;
  }, 15_000, 'question');
  const q = v.game!.question!;
  await sleep(Math.max(0, q.revealAt - v.serverNow) + 20);
  // The correct answer is unknown to clients: in tests we know the seed content has "صح" correct.
  const correctIdx = q.choices.indexOf('صح');
  const choice = correct ? correctIdx : (correctIdx + 1) % q.choices.length;
  t.room.send('action', { action: { kind: 'answer', questionIndex: q.index, choice } });
  return q.index;
}

describe('quiz vertical slice', () => {
  it('rejects unauthenticated and under-age players', async () => {
    const noTicket = new Client(wsUrl).joinOrCreate('game', { gameId: 'quiz', mode: 'casual', ageBucket: 'adult' });
    await expect(noTicket).rejects.toBeTruthy();

    const kid = await api.player('kid', '2016-01-01');
    expect(kid.profile.status).toBe(403);
    const ticket = await api.call('POST', '/matchmaking/ticket', { gameId: 'quiz', mode: 'casual' }, kid.token);
    expect(ticket.status).toBe(403);
  });

  it('never exposes date of birth', async () => {
    const p = await api.player('dob-check', '1990-02-03');
    const me = await api.call('GET', '/me', undefined, p.token);
    expect(JSON.stringify(me.body)).not.toContain('1990');
    expect(me.body.user.ageBand).toBe('adult');
  });

  it('plays a full ranked match with a disconnect and reconnect, then pays exactly once', async () => {
    const [a, b, c] = await Promise.all([api.player('alice'), api.player('bob'), api.player('carol')]);
    const ta = await joinQuick(a.token, 'ranked');
    const tb = await joinQuick(b.token, 'ranked');
    const tc = await joinQuick(c.token, 'ranked');
    expect(new Set([ta.room.roomId, tb.room.roomId, tc.room.roomId]).size).toBe(1);

    await waitFor(() => ta.last()?.phase === 'playing', 10_000, 'match start');
    expect(ta.last()!.commMode).toBe('normal');

    // Q1: everyone answers; alice and bob correct, carol wrong.
    await Promise.all([answerCurrent(ta, true), answerCurrent(tb, true), answerCurrent(tc, false)]);

    // Carol's connection drops (not a consented leave) and comes back within the window.
    const token = tc.room.reconnectionToken;
    tc.room.connection.close();
    await waitFor(() => ta.last()?.players.find((p) => p.playerId === c.id)?.connected === false, 5_000, 'carol shown disconnected');
    // The room keeps going without her: alice and bob answer Q2.
    await Promise.all([answerCurrent(ta, true), answerCurrent(tb, false)]);
    const reconnected = track(await new Client(wsUrl).reconnect(token));
    await waitFor(() => reconnected.last()?.players.find((p) => p.playerId === c.id)?.connected === true, 5_000, 'carol back');
    expect(reconnected.last()!.game).not.toBeNull();

    // Remaining questions.
    const finished = () => ta.views.some((v) => v.game?.stage === 'finished');
    while (!finished()) {
      await Promise.allSettled([answerCurrent(ta, true), answerCurrent(tb, true), answerCurrent(reconnected, true)]);
    }

    const sa = await waitFor(() => ta.summary, 10_000, 'alice summary');
    await waitFor(() => reconnected.summary, 10_000, 'carol summary');
    expect(sa.xp).toBeGreaterThan(0);
    expect(sa.coins).toBeGreaterThan(0);
    expect(sa.rating).not.toBeNull();
    expect(sa.rating!.provisional).toBe(true);

    const match = await prisma.match.findFirstOrThrow({ include: { players: true } });
    expect(match.state).toBe('completed');
    expect(match.mode).toBe('ranked');
    const alice = match.players.find((p) => p.userId === a.id)!;
    expect(alice.place).toBe(1);
    expect(await prisma.matchEvent.count({ where: { matchId: match.id, kind: 'reconnected' } })).toBe(1);

    const walletBefore = await api.call('GET', '/me/wallet', undefined, a.token);
    // Running finalize again (e.g. after a crash/retry) must not pay twice.
    await finalizeMatch({
      matchId: match.id, gameId: 'quiz', mode: 'ranked', players: [a.id, b.id, c.id], leftEarly: [], log: [],
      results: { ranking: [{ playerId: a.id, score: 999, place: 1, correct: 10 }], performance: {} },
    });
    const walletAfter = await api.call('GET', '/me/wallet', undefined, a.token);
    expect(walletAfter.body).toEqual(walletBefore.body);
    expect(await prisma.ratingChange.count({ where: { matchId: match.id } })).toBe(3);

    await Promise.all([ta.room.leave(), tb.room.leave(), reconnected.room.leave()]);
  });

  it('puts a mixed-age private room in Safe Mode and keeps it there', async () => {
    const host = await api.player('host-adult', '1990-01-01');
    const teen = await api.player('teen', '2011-06-01');
    const tHost = await api.call('POST', '/matchmaking/ticket', { gameId: 'quiz', mode: 'private' }, host.token);
    const hostRoom = track(await new Client(wsUrl).create('game', { ...tHost.body.options, ticket: tHost.body.ticket }));
    const code = (await waitFor(() => hostRoom.last()?.code, 5_000, 'code'))!;
    expect(hostRoom.last()!.commMode).toBe('normal');

    const lookup = await api.call('GET', `/rooms/by-code/${code}`, undefined, teen.token);
    expect(lookup.status).toBe(200);
    const tTeen = await api.call('POST', '/matchmaking/ticket', { gameId: 'quiz', mode: 'private' }, teen.token);
    const teenRoom = track(await new Client(wsUrl).joinById(lookup.body.roomId, { ticket: tTeen.body.ticket }));
    await waitFor(() => hostRoom.last()?.commMode === 'safe', 5_000, 'safe mode');

    await teenRoom.room.leave();
    await waitFor(() => hostRoom.last()?.players.length === 1, 5_000, 'teen left');
    expect(hostRoom.last()!.commMode).toBe('safe'); // never switches back automatically
    await hostRoom.room.leave();
  });

  it('does not match adults and minors in public queues', async () => {
    const adult = await api.player('adult-q', '1990-01-01');
    const teen = await api.player('teen-q', '2010-01-01');
    const ra = await joinQuick(adult.token, 'casual');
    const rt = await joinQuick(teen.token, 'casual');
    expect(ra.room.roomId).not.toBe(rt.room.roomId);
    // A forged age bucket is rejected by the room.
    const t = await api.call('POST', '/matchmaking/ticket', { gameId: 'quiz', mode: 'casual' }, teen.token);
    await expect(
      new Client(wsUrl).joinById(ra.room.roomId, { ...t.body.options, ageBucket: 'adult', ticket: t.body.ticket }),
    ).rejects.toBeTruthy();
    await Promise.all([ra.room.leave(), rt.room.leave()]);
  });

  it('critical reports restrict the reported account immediately and reach the admin queue', async () => {
    const owner = await api.player('owner');
    await prisma.adminRole.create({ data: { userId: owner.id, role: 'owner' } });
    const reporter = await api.player('reporter');
    const bad = await api.player('bad-actor');

    const r = await api.call('POST', '/safety/reports', { reportedUserId: bad.id, reason: 'child_safety' }, reporter.token);
    expect(r.status).toBe(201);
    expect((await prisma.user.findUniqueOrThrow({ where: { id: bad.id } })).status).toBe('restricted');
    const ticket = await api.call('POST', '/matchmaking/ticket', { gameId: 'quiz', mode: 'casual' }, bad.token);
    expect(ticket.status).toBe(403);

    expect((await api.call('GET', '/admin/reports', undefined, reporter.token)).status).toBe(403);
    const queue = await api.call('GET', '/admin/reports', undefined, owner.token);
    expect(queue.body.reports).toHaveLength(1);
    const resolved = await api.call('POST', `/admin/reports/${r.body.reportId}/resolve`, { action: 'suspension', days: 7 }, owner.token);
    expect(resolved.status).toBe(200);
    expect(await prisma.auditLog.count({ where: { action: 'report_suspension' } })).toBe(1);
    expect((await api.call('GET', '/me', undefined, bad.token)).status).toBe(403);
  });

  it('imports CSV content as drafts that need human approval before play', async () => {
    const owner = await api.player('editor');
    await prisma.adminRole.create({ data: { userId: owner.id, role: 'content_editor' } });
    const csv = [
      'category,difficulty,prompt,choice1,choice2,choice3,choice4,correct,explanation,fact_as_of,expires_at',
      'geography,easy,ما عاصمة مصر؟,القاهرة,الإسكندرية,أسوان,طنطا,1,,,',
      'geography,easy,سؤال ناقص,واحد,,,,3,,,',
    ].join('\n');
    const res = await api.call('POST', '/admin/content/import?fileName=t.csv', csv, owner.token, 'text/csv');
    expect(res.status).toBe(201);
    expect(res.body.imported).toBe(1);
    expect(res.body.errors).toHaveLength(1);
    const item = await prisma.contentItem.findFirstOrThrow({ where: { category: 'geography' } });
    expect(item.status).toBe('draft');
    const approve = await api.call('POST', `/admin/content/${item.id}/review`, { decision: 'approved' }, owner.token);
    expect(approve.body.item.status).toBe('approved');
  });
});
