/** Acting and Guessing end to end: moves and cards reach the guesser, guesses score, wrong ones stay private. */
import { Client, type Room } from 'colyseus.js';
import type { ActView, MatchSummary, RoomView } from '@sahra/shared';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma } from '../src/db';
import { ACT_TIMING } from '../src/games/acting';
import { ROOM_TIMING } from '../src/rooms/GameRoom';
import { startServer } from '../src/server';
import { Api, resetDb, waitFor } from './helpers';

let server: Awaited<ReturnType<typeof startServer>>;
let api: Api;
let wsUrl: string;

beforeAll(async () => {
  Object.assign(ROOM_TIMING, { privateCountdownMs: 200, resultsHoldMs: 500 });
  Object.assign(ACT_TIMING, { chooseMs: 2_000, revealMs: 100, shortRevealMs: 100 });
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
  const words = ['أسد', 'قطر', 'بحر', 'فيل', 'طبيب', 'سوق'];
  await prisma.contentItem.createMany({
    data: (['easy', 'medium', 'hard'] as const).flatMap((difficulty, d) =>
      words.map((w) => ({
        gameId: 'acting',
        category: 'animals',
        difficulty,
        status: 'approved' as const,
        payload: { word: `${w}${d}`, accepted: [], moves: ['big', 'loud'], cards: ['كارت أول للتجربة', 'كارت تاني للتجربة'] },
      })),
    ),
  });
});

const secrets = new Map<number, string>();

function autoplay(room: Room) {
  const views: RoomView<ActView>[] = [];
  let summary: MatchSummary | undefined;
  const done = new Set<string>();
  room.onMessage('view', (v: RoomView<ActView>) => {
    views.push(v);
    const t = v.game?.turn;
    if (!t) return;
    if (t.actor === v.you) {
      if (v.game!.stage === 'choose' && !done.has(`c${t.turn}`)) {
        done.add(`c${t.turn}`);
        room.send('action', { action: { kind: 'choose', turn: t.turn, choice: 0 } });
      }
      if (v.game!.stage === 'act' && t.word && !done.has(`a${t.turn}`)) {
        done.add(`a${t.turn}`);
        secrets.set(t.turn, t.word);
        room.send('action', { action: { kind: 'move', turn: t.turn, move: t.suggested![0] } });
        setTimeout(() => room.send('action', { action: { kind: 'card', turn: t.turn, card: 0 } }), 1000);
      }
    } else if (v.game!.stage === 'act' && !t.youGuessed && t.beats.length >= 2 && secrets.has(t.turn) && !done.has(`g${t.turn}`)) {
      done.add(`g${t.turn}`);
      room.send('action', { action: { kind: 'guess', turn: t.turn, text: 'غلط' } });
      setTimeout(() => room.send('action', { action: { kind: 'guess', turn: t.turn, text: secrets.get(t.turn) } }), 700);
    }
  });
  room.onMessage('matchSummary', (m: { summary: MatchSummary }) => (summary = m.summary));
  ['error', 'quickChat', 'stream'].forEach((m) => room.onMessage(m, () => {}));
  return { views, summary: () => summary, last: () => views[views.length - 1] };
}

describe('acting match', () => {
  it('plays a private match end to end', async () => {
    const ps = await Promise.all(['aa', 'ab'].map((n) => api.player(n)));
    const ticket = async (token: string) => (await api.call('POST', '/matchmaking/ticket', { gameId: 'acting', mode: 'private' }, token)).body;
    const t0 = await ticket(ps[0]!.token);
    const r0 = await new Client(wsUrl).create('game', { ...t0.options, ticket: t0.ticket, config: { rounds: 1, actSeconds: 60 } });
    const a0 = autoplay(r0);
    const code = (await waitFor(() => a0.last()?.code, 5_000, 'code'))!;
    const { roomId } = (await api.call('GET', `/rooms/by-code/${code}`, undefined, ps[1]!.token)).body;
    const t1 = await ticket(ps[1]!.token);
    const a1 = autoplay(await new Client(wsUrl).joinById(roomId, { ticket: t1.ticket }));
    await waitFor(() => a0.last()?.players.length === 2, 5_000, 'both seated');
    r0.send('start');
    await waitFor(() => a0.last()?.game?.final && a1.last()?.game?.final, 20_000, 'finished');
    const ranking = a0.last()!.game!.final!.ranking;
    expect(ranking).toHaveLength(2);
    for (const r of ranking) expect(r.correct).toBe(1);
    for (const a of [a0, a1]) for (const v of a.views) {
      const t = v.game?.turn;
      // The actor never sees a guesser's wrong guess, and guessers never see the cards list.
      if (t && t.actor === v.you) expect(t.yourGuesses).toEqual([]);
      if (t && t.actor !== v.you) expect(t.cards).toBeNull();
    }
    await waitFor(() => a0.summary() && a1.summary(), 10_000, 'summaries');
  });

  it('is open to teens (Safe Mode: approved moves and cards only)', async () => {
    const teen = await api.player('teen', '2011-03-03');
    const r = await api.call('POST', '/matchmaking/ticket', { gameId: 'acting', mode: 'private' }, teen.token);
    expect(r.status).toBe(200);
  });
});
