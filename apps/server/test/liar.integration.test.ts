/**
 * Liar end to end: a private room of three real clients plays two rounds,
 * the odd question never reaches the others, and the match is saved.
 */
import { Client, type Room } from 'colyseus.js';
import type { LiarView, MatchSummary, RoomView } from '@sahra/shared';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma } from '../src/db';
import { LIAR_TIMING } from '../src/games/liar';
import { ROOM_TIMING } from '../src/rooms/GameRoom';
import { startServer } from '../src/server';
import { Api, resetDb, waitFor } from './helpers';

let server: Awaited<ReturnType<typeof startServer>>;
let api: Api;
let wsUrl: string;

beforeAll(async () => {
  Object.assign(ROOM_TIMING, { privateCountdownMs: 200, resultsHoldMs: 500 });
  Object.assign(LIAR_TIMING, { roundEndMs: 100 });
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
  await prisma.contentItem.createMany({
    data: [0, 1, 2, 3].map((i) => ({
      gameId: 'liar',
      category: 'daily',
      difficulty: 'easy',
      status: 'approved' as const,
      payload: { main: `MAIN-${i} كام ساعة؟`, odd: `ODD-${i} كام مرة؟`, options: ['0', '1', '2', '3'] },
    })),
  });
});

function autoplay(room: Room, me: string, players: string[]) {
  const views: RoomView<LiarView>[] = [];
  let summary: MatchSummary | undefined;
  room.onMessage('view', (v: RoomView<LiarView>) => {
    views.push(v);
    const g = v.game;
    if (!g) return;
    const other = players.find((p) => p !== me)!;
    if (g.stage === 'answer' && g.yourAnswer === null) room.send('action', { action: { kind: 'answer', round: g.round, choice: 0 } });
    else if (g.stage === 'discuss' && !g.youReady) room.send('action', { action: { kind: 'readyToVote' } });
    else if (g.stage === 'vote' && !g.yourVote) room.send('action', { action: { kind: 'vote', target: other } });
  });
  room.onMessage('matchSummary', (m: { summary: MatchSummary }) => (summary = m.summary));
  ['error', 'quickChat'].forEach((m) => room.onMessage(m, () => {}));
  return { views, summary: () => summary, last: () => views[views.length - 1] };
}

describe('liar match', () => {
  it('plays a private match end to end without leaking the odd question', async () => {
    const ps = await Promise.all(['la', 'lb', 'lc'].map((n) => api.player(n)));
    const ids = ps.map((p) => p.id);
    const ticket = async (token: string) => (await api.call('POST', '/matchmaking/ticket', { gameId: 'liar', mode: 'private' }, token)).body;
    const t0 = await ticket(ps[0]!.token);
    const r0 = await new Client(wsUrl).create('game', { ...t0.options, ticket: t0.ticket, config: { rounds: 2, difficulty: 'easy' } });
    const a0 = autoplay(r0, ids[0]!, ids);
    const code = (await waitFor(() => a0.last()?.code, 5_000, 'code'))!;
    const { roomId } = (await api.call('GET', `/rooms/by-code/${code}`, undefined, ps[1]!.token)).body;
    const rest = [];
    for (const i of [1, 2]) {
      const t = await ticket(ps[i]!.token);
      rest.push(autoplay(await new Client(wsUrl).joinById(roomId, { ticket: t.ticket }), ids[i]!, ids));
    }
    const clients = [a0, ...rest];
    await waitFor(() => a0.last()?.players.length === 3, 5_000, 'all seated');
    r0.send('start');
    await waitFor(() => clients.every((c) => c.last()?.game?.stage === 'finished'), 20_000, 'finished');
    const final = a0.last()!.game!.final!;
    expect(final.rounds).toHaveLength(2);
    // Before each round ended, only that round's liar ever saw the odd question.
    for (const [i, c] of clients.entries()) {
      for (const v of c.views) {
        const g = v.game;
        if (!g || g.stage === 'roundEnd' || g.stage === 'finished') continue;
        const liarThisRound = final.rounds[g.round - 1]!.liar === ids[i];
        if (!liarThisRound) expect(JSON.stringify(g)).not.toContain('ODD-');
        if (liarThisRound && g.stage === 'answer') expect(JSON.stringify(g)).not.toContain('MAIN-');
      }
    }
    await waitFor(() => clients.every((c) => c.summary()), 10_000, 'summaries');
    const match = await prisma.match.findFirstOrThrow({ where: { gameId: 'liar' }, include: { players: true } });
    expect(match.players).toHaveLength(3);
    expect(match.endedAt).not.toBeNull();
  });
});
