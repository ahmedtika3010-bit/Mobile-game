/** Memory end to end: two clients; one remembers the board, the other does not. */
import { Client, type Room } from 'colyseus.js';
import type { MatchSummary, MemoryView, RoomView } from '@sahra/shared';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma } from '../src/db';
import { MEMORY_TIMING, PROFILES } from '../src/games/memory';
import { ROOM_TIMING } from '../src/rooms/GameRoom';
import { startServer } from '../src/server';
import { Api, resetDb, waitFor } from './helpers';

let server: Awaited<ReturnType<typeof startServer>>;
let api: Api;
let wsUrl: string;

beforeAll(async () => {
  Object.assign(ROOM_TIMING, { privateCountdownMs: 200, resultsHoldMs: 500 });
  Object.assign(MEMORY_TIMING, { leadMs: 50, gapMs: 50, revealMs: 50 });
  Object.assign(PROFILES.easy, { cardsShowMs: 150, spotShowMs: 150, stepMs: 30 });
  server = await startServer(0);
  api = new Api(`http://localhost:${server.port}`);
  wsUrl = `ws://localhost:${server.port}`;
});
afterAll(async () => {
  await server.close();
  await prisma.$disconnect();
});
beforeEach(resetDb);

function autoplay(room: Room, remembers: boolean) {
  const views: RoomView<MemoryView>[] = [];
  let summary: MatchSummary | undefined;
  const seen: Record<number, { grid: string[] | null; sequence: number[] | null }> = {};
  const sent = new Set<string>();
  room.onMessage('view', (v: RoomView<MemoryView>) => {
    views.push(v);
    const g = v.game;
    const r = g?.round;
    if (!g || !r) return;
    if (g.stage === 'show') seen[r.round] = { grid: r.grid, sequence: r.sequence };
    if (g.stage !== 'answer' || g.youDone || sent.has(`${r.round}`)) return;
    sent.add(`${r.round}`);
    const mem = seen[r.round]!;
    const send = (action: object) => setTimeout(() => room.send('action', { action }), Math.max(0, r.answerAt - Date.now()) + 30);
    if (r.mode === 'sequence') send({ kind: 'sequence', round: r.round, items: remembers ? mem.sequence : [] });
    else if (r.mode === 'spot') {
      const cell = remembers ? r.changedGrid!.findIndex((e, i) => e !== mem.grid![i]) : 0;
      send({ kind: 'pick', round: r.round, cell });
    } else {
      r.targets!.forEach((t, i) =>
        setTimeout(() => room.send('action', { action: { kind: 'pick', round: r.round, cell: remembers ? mem.grid!.indexOf(t) : 0 } }), Math.max(0, r.answerAt - Date.now()) + 30 + i * 20),
      );
    }
  });
  room.onMessage('matchSummary', (m: { summary: MatchSummary }) => (summary = m.summary));
  ['error', 'quickChat'].forEach((m) => room.onMessage(m, () => {}));
  return { views, summary: () => summary, last: () => views[views.length - 1] };
}

describe('memory match', () => {
  it('plays a mixed private match end to end', async () => {
    const ps = await Promise.all(['ma', 'mb'].map((n) => api.player(n)));
    const ticket = async (token: string) => (await api.call('POST', '/matchmaking/ticket', { gameId: 'memory', mode: 'private' }, token)).body;
    const t0 = await ticket(ps[0]!.token);
    const r0 = await new Client(wsUrl).create('game', { ...t0.options, ticket: t0.ticket, config: { mode: 'mixed', difficulty: 'easy', rounds: 3 } });
    const a0 = autoplay(r0, true);
    const code = (await waitFor(() => a0.last()?.code, 5_000, 'code'))!;
    const { roomId } = (await api.call('GET', `/rooms/by-code/${code}`, undefined, ps[1]!.token)).body;
    const t1 = await ticket(ps[1]!.token);
    const a1 = autoplay(await new Client(wsUrl).joinById(roomId, { ticket: t1.ticket }), false);
    await waitFor(() => a0.last()?.players.length === 2, 5_000, 'both seated');
    r0.send('start');
    await waitFor(() => a0.last()?.game?.final && a1.last()?.game?.final, 30_000, 'finished');
    const ranking = a0.last()!.game!.final!.ranking;
    expect(ranking.find((r) => r.playerId === ps[0]!.id)).toMatchObject({ place: 1, correct: 3 });
    // The board never appears in a view during the answer stage.
    for (const v of a1.views) if (v.game?.stage === 'answer') expect(v.game.round!.grid ?? v.game.round!.sequence).toBeNull();
    await waitFor(() => a0.summary() && a1.summary(), 10_000, 'summaries');
  });
});
