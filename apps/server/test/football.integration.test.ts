/** Football Challenges end to end: a private 1v1 duel with progressive clues, two clients. */
import { Client, type Room } from 'colyseus.js';
import type { FootballView, MatchSummary, RoomView } from '@sahra/shared';
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
  const common = (i: number) => ({ answer: `صح ${i}`, wrong: [`غلط أ${i}`, `غلط ب${i}`, `غلط ج${i}`], asOf: '2025-06-30' });
  await prisma.contentItem.createMany({
    data: [
      ...Array.from({ length: 3 }, (_, i) => ({
        gameId: 'football', category: 'player', difficulty: 'easy', status: 'approved' as const,
        payload: { mode: 'player', clues: [`أول تلميح ${i}`, `تاني تلميح ${i}`, `سر التلميح الأخير ${i}`], ...common(i) },
      })),
      ...Array.from({ length: 3 }, (_, i) => ({
        gameId: 'football', category: 'history', difficulty: 'easy', status: 'approved' as const,
        payload: { mode: 'history', prompt: `سؤال تاريخ رقم ${i} عن الكورة؟`, when: '2010', ...common(i + 3) },
      })),
    ],
  });
});

/** Player 0 always picks the right answer at once; player 1 always picks a wrong one. */
function autoplay(room: Room, right: boolean) {
  const views: RoomView<FootballView>[] = [];
  let summary: MatchSummary | undefined;
  const sent = new Set<number>();
  room.onMessage('view', (v: RoomView<FootballView>) => {
    views.push(v);
    const g = v.game;
    const q = g?.question;
    if (g?.stage !== 'question' || !q || g.yourChoice !== null || sent.has(q.index)) return;
    sent.add(q.index);
    const choice = q.choices.findIndex((c) => c.startsWith(right ? 'صح' : 'غلط'));
    setTimeout(() => room.send('action', { action: { kind: 'answer', questionIndex: q.index, choice } }), Math.max(0, q.revealAt - Date.now()) + 60);
  });
  room.onMessage('matchSummary', (m: { summary: MatchSummary }) => (summary = m.summary));
  ['error', 'quickChat'].forEach((m) => room.onMessage(m, () => {}));
  return { views, summary: () => summary, last: () => views[views.length - 1] };
}

describe('football match', () => {
  it('plays a private duel end to end without leaking clues early', async () => {
    const ps = await Promise.all(['fa', 'fb'].map((n) => api.player(n)));
    const ticket = async (token: string) => (await api.call('POST', '/matchmaking/ticket', { gameId: 'football', mode: 'private' }, token)).body;
    const t0 = await ticket(ps[0]!.token);
    const r0 = await new Client(wsUrl).create('game', { ...t0.options, ticket: t0.ticket, config: { duel: true, questionCount: 5, answerSeconds: 10 } });
    const a0 = autoplay(r0, true);
    const code = (await waitFor(() => a0.last()?.code, 5_000, 'code'))!;
    const { roomId } = (await api.call('GET', `/rooms/by-code/${code}`, undefined, ps[1]!.token)).body;
    const t1 = await ticket(ps[1]!.token);
    const a1 = autoplay(await new Client(wsUrl).joinById(roomId, { ticket: t1.ticket }), false);
    await waitFor(() => a0.last()?.players.length === 2, 5_000, 'both seated');
    r0.send('start');
    await waitFor(() => a0.last()?.game?.final && a1.last()?.game?.final, 30_000, 'finished');

    const g = a0.last()!.game!;
    expect(g.duel!.wins[ps[0]!.id]).toBe(5);
    expect(g.final!.ranking[0]).toMatchObject({ playerId: ps[0]!.id, place: 1, correct: 5 });
    // Mixed modes were played, and the last clue of a player question never
    // reached anyone while the question was still open (everyone answered early).
    const questionViews = [...a0.views, ...a1.views].filter((v) => v.game?.stage === 'question');
    expect(new Set(questionViews.map((v) => v.game!.question!.category))).toEqual(new Set(['player', 'history']));
    expect(JSON.stringify(questionViews)).not.toContain('سر التلميح الأخير');
    expect(JSON.stringify(questionViews)).not.toContain('"answer"');
    await waitFor(() => a0.summary() && a1.summary(), 10_000, 'summaries');
  });
});
