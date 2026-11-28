/** Game Night end to end: one room, a playlist game, a vote with a tie, the summary. */
import { Client, type Room } from 'colyseus.js';
import type { NightView, RoomView } from '@sahra/shared';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma } from '../src/db';
import { QUIZ_TIMING } from '../src/games/quiz';
import { ROOM_TIMING } from '../src/rooms/GameRoom';
import { startServer } from '../src/server';
import { Api, resetDb, seedApprovedQuiz, waitFor } from './helpers';
import { NIGHT_LIMITS } from '@sahra/shared';

let server: Awaited<ReturnType<typeof startServer>>;
let api: Api;
let wsUrl: string;

beforeAll(async () => {
  Object.assign(ROOM_TIMING, { privateCountdownMs: 200, resultsHoldMs: 300 });
  Object.assign(QUIZ_TIMING, { revealLeadMs: 50, revealStageMs: 80 });
  Object.assign(NIGHT_LIMITS, { voteMs: 1500, tieMs: 1500, nextGameMs: 200 });
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

type V = RoomView<{ stage: string; question?: { index: number; revealAt: number; choices: string[] }; yourChoice: number | null }> & { night: NightView };

/** Tracks views and answers every quiz question as soon as it shows. */
function play(room: Room) {
  const views: V[] = [];
  const errors: string[] = [];
  const answered = new Set<string>();
  room.onMessage('view', (v: V) => {
    views.push(v);
    const q = v.game?.question;
    const key = `${v.matchId}-${q?.index}`;
    if (v.phase === 'playing' && v.game?.stage === 'question' && q && v.game.yourChoice === null && !answered.has(key)) {
      answered.add(key);
      setTimeout(() => room.send('action', { action: { kind: 'answer', questionIndex: q.index, choice: 0 } }), Math.max(0, q.revealAt - v.serverNow) + 10);
    }
  });
  room.onMessage('error', (e: { code: string }) => errors.push(e.code));
  ['matchSummary', 'quickChat', 'pong', 'stream'].forEach((m) => room.onMessage(m, () => {}));
  return { room, views, errors, last: () => views[views.length - 1]! };
}

describe('game night', () => {
  it('is private only', async () => {
    const a = await api.player('na');
    expect((await api.call('POST', '/matchmaking/ticket', { gameId: 'night', mode: 'casual' }, a.token)).status).toBe(400);
  });

  it('plays a playlist game, votes, breaks a tie by the host, and ends with a summary', async () => {
    const [a, b] = await Promise.all([api.player('na'), api.player('nb')]);
    const ticket = async (token: string) => (await api.call('POST', '/matchmaking/ticket', { gameId: 'night', mode: 'private' }, token)).body;
    const ta = await ticket(a.token);
    const A = play(await new Client(wsUrl).create('game', { ...ta.options, ticket: ta.ticket }));
    const code = (await waitFor(() => A.last()?.code, 5_000, 'code'))!;
    const byCode = (await api.call('GET', `/rooms/by-code/${code}`, undefined, b.token)).body;
    expect(byCode.gameId).toBe('night');
    // A ticket for a single game cannot open a Game Night room.
    const wrong = (await api.call('POST', '/matchmaking/ticket', { gameId: 'quiz', mode: 'private' }, b.token)).body;
    await expect(new Client(wsUrl).joinById(byCode.roomId, { ticket: wrong.ticket })).rejects.toBeTruthy();
    const tb = await ticket(b.token);
    const B = play(await new Client(wsUrl).joinById(byCode.roomId, { ticket: tb.ticket }));
    await waitFor(() => A.last()?.players.length === 2, 5_000, 'both in');
    expect(A.last().night.eligible).toContain('quiz');
    expect(A.last().night.eligible).not.toContain('spy');

    // Only the host can start or queue games.
    B.room.send('start');
    await waitFor(() => B.errors.includes('not_host'), 3_000, 'not host');
    A.room.send('nightPlaylist', { games: ['quiz'] });
    await waitFor(() => A.last()?.night.playlist[0] === 'quiz', 3_000, 'playlist');
    A.room.send('start');
    await waitFor(() => A.last()?.night.next === 'quiz' || A.last()?.phase === 'playing', 3_000, 'next up');

    // The quiz plays out, then everyone votes for the next game.
    await waitFor(() => A.last()?.phase === 'vote', 30_000, 'vote');
    const n = A.last().night;
    expect(n.played).toHaveLength(1);
    expect(n.played[0]!.gameId).toBe('quiz');
    expect(n.standings).toHaveLength(2);
    expect(n.vote!.options.map((o) => o.gameId)).toEqual(n.eligible);

    A.room.send('nightVote', { gameId: 'stop' });
    await waitFor(() => A.last()?.night.vote?.yourVote === 'stop', 3_000, 'a voted');
    expect(B.last().night.vote!.yourVote).toBeNull();
    B.room.send('nightVote', { gameId: 'memory' });
    // Everyone voted: closes early with a tie for the host to settle.
    const tie = await waitFor(() => A.last()?.night.vote?.tie, 3_000, 'tie');
    expect([...tie].sort()).toEqual(['memory', 'stop']);
    B.room.send('nightPick', { gameId: 'stop' }); // not the host: ignored
    A.room.send('nightPick', { gameId: 'memory' });
    await waitFor(() => A.last()?.night.next === 'memory', 3_000, 'host picked');
    expect(A.last().gameId).toBe('memory');

    // The host ends the night before the next game starts.
    A.room.send('nightEnd');
    const sum = await waitFor(() => B.last()?.phase === 'summary' && B.last().night.summary, 3_000, 'summary');
    expect(sum.played).toHaveLength(1);
    expect(sum.standings.map((s) => s.playerId).sort()).toEqual([a.id, b.id].sort());
    expect(sum.titles.length).toBe(2);
    // A new night starts clean in the same room.
    A.room.send('nightNew');
    await waitFor(() => A.last()?.phase === 'lobby' && A.last().night.played.length === 0, 3_000, 'new night');
    // The quiz match was saved as a normal private match.
    expect(await prisma.match.count({ where: { gameId: 'quiz', mode: 'private' } })).toBe(1);
  });
});
