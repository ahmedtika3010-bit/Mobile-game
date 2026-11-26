/** Who Among Us end to end: three clients, anonymous votes, small flat rewards. */
import { Client, type Room } from 'colyseus.js';
import type { MatchSummary, RoomView, WhoView } from '@sahra/shared';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma } from '../src/db';
import { WHO_TIMING } from '../src/games/who';
import { ROOM_TIMING } from '../src/rooms/GameRoom';
import { startServer } from '../src/server';
import { Api, resetDb, waitFor } from './helpers';

let server: Awaited<ReturnType<typeof startServer>>;
let api: Api;
let wsUrl: string;

beforeAll(async () => {
  Object.assign(ROOM_TIMING, { privateCountdownMs: 200, resultsHoldMs: 500 });
  Object.assign(WHO_TIMING, { revealMs: 50 });
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
    data: Array.from({ length: 8 }, (_, i) => ({
      gameId: 'who',
      category: 'funny',
      difficulty: 'medium',
      status: 'approved' as const,
      payload: { text: `مين فينا سؤال تجربة ${i}؟` },
    })),
  });
});

function autoplay(room: Room, me: string, ids: string[]) {
  const views: RoomView<WhoView>[] = [];
  let summary: MatchSummary | undefined;
  room.onMessage('view', (v: RoomView<WhoView>) => {
    views.push(v);
    const g = v.game;
    if (g?.stage === 'vote' && g.yourChoice === null) {
      room.send('action', { action: { kind: 'vote', question: g.index, target: ids.find((p) => p !== me)! } });
    }
  });
  room.onMessage('matchSummary', (m: { summary: MatchSummary }) => (summary = m.summary));
  ['error', 'quickChat'].forEach((m) => room.onMessage(m, () => {}));
  return { views, summary: () => summary, last: () => views[views.length - 1] };
}

describe('who match', () => {
  it('plays a private match end to end', async () => {
    const ps = await Promise.all(['wa', 'wb', 'wc'].map((n) => api.player(n)));
    const ids = ps.map((p) => p.id);
    const ticket = async (token: string) => (await api.call('POST', '/matchmaking/ticket', { gameId: 'who', mode: 'private' }, token)).body;
    const t0 = await ticket(ps[0]!.token);
    const r0 = await new Client(wsUrl).create('game', { ...t0.options, ticket: t0.ticket, config: { questionCount: 5 } });
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
    await waitFor(() => clients.every((c) => c.last()?.game?.final), 20_000, 'finished');
    const f = a0.last()!.game!.final!;
    expect(f.questions).toBe(5);
    expect(f.votesCast).toBe(15);
    expect(Object.keys(f.titles)).toHaveLength(3);
    // Other players' choices never appear in anyone's view.
    for (const c of clients) for (const v of c.views) if (v.game?.stage === 'vote') expect(v.game.reveal).toBeNull();
    await waitFor(() => clients.every((c) => c.summary()), 10_000, 'summaries');
    for (const c of clients) {
      expect(c.summary()!.xp).toBeLessThanOrEqual(40);
      expect(c.summary()!.rating).toBeNull();
    }
  });
});
