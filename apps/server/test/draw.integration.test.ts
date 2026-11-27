/** Draw and Guess end to end: strokes stream to the guesser, guesses score, reports keep the drawing. */
import { Client, type Room } from 'colyseus.js';
import type { DrawView, MatchSummary, RoomView, StreamChunk } from '@sahra/shared';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma } from '../src/db';
import { DRAW_TIMING } from '../src/games/draw';
import { ROOM_TIMING } from '../src/rooms/GameRoom';
import { startServer } from '../src/server';
import { Api, resetDb, waitFor } from './helpers';

let server: Awaited<ReturnType<typeof startServer>>;
let api: Api;
let wsUrl: string;

beforeAll(async () => {
  Object.assign(ROOM_TIMING, { privateCountdownMs: 200, resultsHoldMs: 500 });
  Object.assign(DRAW_TIMING, { chooseMs: 2_000, revealMs: 100, shortRevealMs: 100 });
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
  const words = ['شمس', 'قمر', 'بيت', 'كتاب', 'سمكة', 'وردة'];
  await prisma.contentItem.createMany({
    data: (['easy', 'medium', 'hard'] as const).flatMap((difficulty, d) =>
      words.map((w) => ({
        gameId: 'draw',
        category: 'objects',
        difficulty,
        status: 'approved' as const,
        payload: { word: `${w}${d}`, accepted: [] },
      })),
    ),
  });
});

/** Shared between the two players so the test's guesser can "recognize" the drawing. */
const secrets = new Map<number, string>();

function autoplay(room: Room) {
  const views: RoomView<DrawView>[] = [];
  const canvas = { key: '', items: [] as unknown[], gaps: 0 };
  let summary: MatchSummary | undefined;
  const done = new Set<string>();
  room.onMessage('stream', (c: StreamChunk) => {
    if (c.key !== canvas.key) {
      canvas.key = c.key;
      canvas.items = [];
    }
    if (c.from !== canvas.items.length) canvas.gaps++;
    canvas.items.push(...c.items);
    const v = views[views.length - 1];
    if (v) act(v);
  });
  room.onMessage('view', (v: RoomView<DrawView>) => {
    views.push(v);
    act(v);
  });
  function act(v: RoomView<DrawView>) {
    const t = v.game?.turn;
    if (!t) return;
    const me = v.you;
    if (t.drawer === me) {
      if (v.game!.stage === 'choose' && !done.has(`c${t.turn}`)) {
        done.add(`c${t.turn}`);
        room.send('action', { action: { kind: 'choose', turn: t.turn, choice: 0 } });
      }
      if (v.game!.stage === 'draw' && t.word && !done.has(`d${t.turn}`)) {
        done.add(`d${t.turn}`);
        secrets.set(t.turn, t.word);
        room.send('action', { action: { kind: 'draw', turn: t.turn, ops: [{ t: 'b', c: 0, w: 1, p: [100, 100, 200, 200] }, { t: 'p', p: [300, 250, 400, 300] }] } });
      }
    } else if (v.game!.stage === 'draw' && !t.youGuessed && canvas.items.length >= 2 && secrets.has(t.turn) && !done.has(`g${t.turn}`)) {
      done.add(`g${t.turn}`);
      room.send('action', { action: { kind: 'guess', turn: t.turn, text: 'غلط' } });
      setTimeout(() => room.send('action', { action: { kind: 'guess', turn: t.turn, text: secrets.get(t.turn) } }), 700);
    }
  }
  room.onMessage('matchSummary', (m: { summary: MatchSummary }) => (summary = m.summary));
  ['error', 'quickChat'].forEach((m) => room.onMessage(m, () => {}));
  return { views, canvas, summary: () => summary, last: () => views[views.length - 1] };
}

describe('draw and guess match', () => {
  it('keeps the game for adults outside practice until its Safe Mode is tested', async () => {
    const teen = await api.player('teen', '2011-03-03');
    const casual = await api.call('POST', '/matchmaking/ticket', { gameId: 'draw', mode: 'private' }, teen.token);
    expect(casual).toMatchObject({ status: 403, body: { error: 'safe_mode_unavailable' } });
    const practice = await api.call('POST', '/matchmaking/ticket', { gameId: 'draw', mode: 'practice' }, teen.token);
    expect(practice.status).toBe(200);
  });

  it('plays a private match end to end and attaches the drawing to a report made during it', async () => {
    const ps = await Promise.all(['da', 'db'].map((n) => api.player(n)));
    const ticket = async (token: string) => (await api.call('POST', '/matchmaking/ticket', { gameId: 'draw', mode: 'private' }, token)).body;
    const t0 = await ticket(ps[0]!.token);
    const r0 = await new Client(wsUrl).create('game', { ...t0.options, ticket: t0.ticket, config: { rounds: 1, drawSeconds: 60 } });
    const a0 = autoplay(r0);
    const code = (await waitFor(() => a0.last()?.code, 5_000, 'code'))!;
    const { roomId } = (await api.call('GET', `/rooms/by-code/${code}`, undefined, ps[1]!.token)).body;
    const t1 = await ticket(ps[1]!.token);
    const a1 = autoplay(await new Client(wsUrl).joinById(roomId, { ticket: t1.ticket }));
    await waitFor(() => a0.last()?.players.length === 2, 5_000, 'both seated');
    r0.send('start');

    // During the first turn, the guesser reports the drawer (the match id is in the view).
    const first = await waitFor(() => [a0, a1].find((a) => a.last()?.game?.stage === 'draw' && a.last()?.game?.turn?.drawer !== a.last()?.you), 10_000, 'drawing');
    const view = first.last()!;
    expect(view.matchId).toBeTruthy();
    const reporter = ps.find((p) => p.id === view.you)!;
    const drawer = ps.find((p) => p.id !== view.you)!;
    await waitFor(() => first.canvas.items.length >= 2, 5_000, 'strokes streamed');
    const rep = await api.call('POST', '/safety/reports', { reportedUserId: drawer.id, reason: 'other', matchId: view.matchId }, reporter.token);
    expect(rep.status).toBe(201);

    await waitFor(() => a0.last()?.game?.final && a1.last()?.game?.final, 20_000, 'finished');
    const ranking = a0.last()!.game!.final!.ranking;
    expect(ranking).toHaveLength(2);
    // Each player guessed once (100 easy points at most) and drew once.
    for (const r of ranking) expect(r.correct).toBe(1);
    // The wrong guess never reached the other player.
    for (const a of [a0, a1]) for (const v of a.views) {
      const t = v.game?.turn;
      if (t && t.drawer === v.you) expect(t.yourGuesses).toEqual([]);
    }
    expect(a0.canvas.gaps + a1.canvas.gaps).toBe(0);
    await waitFor(() => a0.summary() && a1.summary(), 10_000, 'summaries');
    const saved = await prisma.report.findUniqueOrThrow({ where: { id: rep.body.reportId } });
    const evidence = saved.evidence as { kind: string; data: { action: { kind: string } } }[];
    expect(evidence.some((e) => e.kind === 'action' && e.data.action.kind === 'draw')).toBe(true);
  });
});
