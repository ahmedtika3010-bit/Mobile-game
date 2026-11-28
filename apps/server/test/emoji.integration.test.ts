/** Guess with Emoji end to end: a private room with typed answers, two clients. */
import { Client, type Room } from 'colyseus.js';
import type { EmojiView, MatchSummary, RoomView } from '@sahra/shared';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma } from '../src/db';
import { QUIZ_TIMING } from '../src/games/quiz';
import { ROOM_TIMING } from '../src/rooms/GameRoom';
import { startServer } from '../src/server';
import { Api, resetDb, waitFor } from './helpers';

let server: Awaited<ReturnType<typeof startServer>>;
let api: Api;
let wsUrl: string;

beforeAll(async () => {
  Object.assign(ROOM_TIMING, { privateCountdownMs: 200, resultsHoldMs: 500 });
  Object.assign(QUIZ_TIMING, { revealLeadMs: 50, revealStageMs: 50 });
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
    data: Array.from({ length: 6 }, (_, i) => ({
      gameId: 'emoji',
      category: 'food',
      difficulty: 'medium',
      status: 'approved' as const,
      payload: { emojis: `🍕${'🍔'.repeat(i + 1)}`, answer: `أكلة رقم ${i}`, wrong: ['غلط أ', 'غلط ب', 'غلط ج'], accepted: [] },
    })),
  });
});

/** Player 0 always types the right answer (without hamza); player 1 guesses wrong until locked out. */
function autoplay(room: Room, right: boolean) {
  const views: RoomView<EmojiView>[] = [];
  let summary: MatchSummary | undefined;
  const sent = new Set<string>();
  room.onMessage('view', (v: RoomView<EmojiView>) => {
    views.push(v);
    const g = v.game;
    const q = g?.question;
    if (g?.stage !== 'question' || !q || g.yourChoice !== null) return;
    const key = `${q.index}:${g.yourGuesses.length}`;
    if (sent.has(key) || g.yourGuesses.length >= 3) return;
    sent.add(key);
    const text = right ? `اكلة رقم ${q.emojis.length / 2 - 2}` : `غلط ${g.yourGuesses.length}`;
    setTimeout(() => room.send('action', { action: { kind: 'guess', questionIndex: q.index, text } }), Math.max(0, q.revealAt - Date.now()) + 60);
  });
  room.onMessage('matchSummary', (m: { summary: MatchSummary }) => (summary = m.summary));
  ['error', 'quickChat'].forEach((m) => room.onMessage(m, () => {}));
  return { views, summary: () => summary, last: () => views[views.length - 1] };
}

describe('emoji match', () => {
  it('plays a typed private match end to end', async () => {
    const ps = await Promise.all(['ea', 'eb'].map((n) => api.player(n)));
    const ticket = async (token: string) => (await api.call('POST', '/matchmaking/ticket', { gameId: 'emoji', mode: 'private' }, token)).body;
    const t0 = await ticket(ps[0]!.token);
    const r0 = await new Client(wsUrl).create('game', { ...t0.options, ticket: t0.ticket, config: { questionCount: 5, answerMode: 'typed', answerSeconds: 10 } });
    const a0 = autoplay(r0, true);
    const code = (await waitFor(() => a0.last()?.code, 5_000, 'code'))!;
    const { roomId } = (await api.call('GET', `/rooms/by-code/${code}`, undefined, ps[1]!.token)).body;
    const t1 = await ticket(ps[1]!.token);
    const a1 = autoplay(await new Client(wsUrl).joinById(roomId, { ticket: t1.ticket }), false);
    await waitFor(() => a0.last()?.players.length === 2, 5_000, 'both seated');
    r0.send('start');
    await waitFor(() => a0.last()?.game?.final && a1.last()?.game?.final, 30_000, 'finished');
    const ranking = a0.last()!.game!.final!.ranking;
    expect(ranking.find((r) => r.playerId === ps[0]!.id)).toMatchObject({ place: 1, correct: 5 });
    expect(ranking.find((r) => r.playerId === ps[1]!.id)).toMatchObject({ score: 0, correct: 0 });
    // Player 1's wrong guesses never reach player 0.
    expect(JSON.stringify(a0.views)).not.toContain('غلط 0');
    await waitFor(() => a0.summary() && a1.summary(), 10_000, 'summaries');
  });
});
