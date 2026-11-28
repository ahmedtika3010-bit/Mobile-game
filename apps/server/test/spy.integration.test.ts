/**
 * Spy end to end: a private room of three real clients plays a full match
 * through the generic room, and the result is saved and rewarded.
 */
import { Client, type Room } from 'colyseus.js';
import type { MatchSummary, RoomView, SpyView } from '@sahra/shared';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma } from '../src/db';
import { SPY_TIMING } from '../src/games/spy';
import { ROOM_TIMING } from '../src/rooms/GameRoom';
import { startServer } from '../src/server';
import { Api, resetDb, waitFor } from './helpers';

let server: Awaited<ReturnType<typeof startServer>>;
let api: Api;
let wsUrl: string;

beforeAll(async () => {
  Object.assign(ROOM_TIMING, { privateCountdownMs: 200, resultsHoldMs: 500 });
  Object.assign(SPY_TIMING, { rolesMs: 100, showAnswerMs: 50 });
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
  await prisma.contentItem.create({
    data: {
      gameId: 'spy',
      category: 'food',
      difficulty: 'medium',
      status: 'approved',
      payload: { words: ['كشري', 'فول', 'طعمية', 'بيتزا', 'محشي', 'كنافة', 'سمك', 'برجر', 'سلطة'], questions: ['هل سخن؟', 'هل حلو؟', 'هل غالي؟', 'هل صحي؟', 'هل بالإيد؟', 'هل بالمعلقة؟'] },
    },
  });
});

/** A scripted player: acts on its own turn, and the citizens all vote for player `blame`. */
function autoplay(room: Room, me: string, players: () => string[], blame: () => string) {
  const views: RoomView<SpyView>[] = [];
  let summary: MatchSummary | undefined;
  room.onMessage('view', (v: RoomView<SpyView>) => {
    views.push(v);
    const g = v.game;
    if (!g) return;
    const others = players().filter((p) => p !== me);
    if (g.stage === 'ask' && g.turn?.asker === me && g.turn.questionOptions) {
      room.send('action', { action: { kind: 'ask', turn: g.turn.index, question: 0, target: others[0] } });
    } else if (g.stage === 'answer' && g.turn?.target === me && g.turn.answer === null) {
      room.send('action', { action: { kind: 'answer', turn: g.turn.index, answer: 1 } });
    } else if (g.stage === 'discuss' && !g.youReady) {
      room.send('action', { action: { kind: 'readyToVote' } });
    } else if (g.stage === 'vote' && !g.yourVote) {
      const target = blame() === me ? others[0]! : blame();
      room.send('action', { action: { kind: 'vote', target } });
    } else if (g.stage === 'guess' && g.guesser === me && g.guessOptions) {
      room.send('action', { action: { kind: 'guess', choice: 0 } });
    }
  });
  room.onMessage('matchSummary', (m: { summary: MatchSummary }) => (summary = m.summary));
  room.onMessage('error', () => {});
  room.onMessage('quickChat', () => {});
  return { views, summary: () => summary, last: () => views[views.length - 1] };
}

describe('spy match', () => {
  it('plays a private match end to end without leaking roles', async () => {
    const ps = await Promise.all(['sa', 'sb', 'sc'].map((n) => api.player(n)));
    const ids = ps.map((p) => p.id);
    let spyId = '';
    const ticket = async (token: string) => (await api.call('POST', '/matchmaking/ticket', { gameId: 'spy', mode: 'private' }, token)).body;

    const t0 = await ticket(ps[0]!.token);
    const r0 = await new Client(wsUrl).create('game', { ...t0.options, ticket: t0.ticket });
    const a0 = autoplay(r0, ids[0]!, () => ids, () => spyId);
    const code = (await waitFor(() => a0.last()?.code, 5_000, 'code'))!;
    const { roomId } = (await api.call('GET', `/rooms/by-code/${code}`, undefined, ps[1]!.token)).body;
    const rest = [];
    for (const i of [1, 2]) {
      const t = await ticket(ps[i]!.token);
      const r = await new Client(wsUrl).joinById(roomId, { ticket: t.ticket });
      rest.push(autoplay(r, ids[i]!, () => ids, () => spyId));
    }
    const clients = [a0, ...rest];
    await waitFor(() => a0.last()?.players.length === 3, 5_000, 'all seated');
    r0.send('start');

    // Exactly one client learns it is the spy, and that client never sees the word.
    await waitFor(() => clients.every((c) => c.last()?.game?.role), 5_000, 'roles');
    const roles = clients.map((c) => c.last()!.game!.role);
    expect(roles.filter((r) => r === 'spy')).toHaveLength(1);
    spyId = ids[roles.indexOf('spy')]!;
    const spyClient = clients[roles.indexOf('spy')]!;

    await waitFor(() => clients.every((c) => c.last()?.game?.stage === 'finished'), 20_000, 'finished');
    const final = a0.last()!.game!.final!;
    expect(final.spies).toEqual([spyId]);
    expect(final.accused).toBe(spyId);
    expect(['caught', 'caught_but_guessed']).toContain(final.reason);
    expect(spyClient.views.filter((v) => v.game && v.game.stage !== 'finished').every((v) => v.game!.word === null)).toBe(true);
    expect(a0.last()!.game!.history).toHaveLength(3);

    await waitFor(() => clients.every((c) => c.summary()), 10_000, 'summaries');
    const match = await prisma.match.findFirstOrThrow({ where: { gameId: 'spy' }, include: { players: true } });
    expect(match.players).toHaveLength(3);
    expect(match.endedAt).not.toBeNull();
  });

  it('has no practice mode or ranked queue yet', async () => {
    const p = await api.player('solo-spy');
    expect((await api.call('POST', '/matchmaking/ticket', { gameId: 'spy', mode: 'practice' }, p.token)).status).toBe(400);
    expect((await api.call('POST', '/matchmaking/ticket', { gameId: 'spy', mode: 'ranked' }, p.token)).status).toBe(400);
  });
});
