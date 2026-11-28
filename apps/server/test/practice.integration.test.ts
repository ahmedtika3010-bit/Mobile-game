/**
 * Practice mode: one player against labelled bots. Starts by itself, plays a
 * full match, pays nothing and saves nothing.
 */
import { Client } from 'colyseus.js';
import type { MatchSummary, QuizView, RoomView } from '@sahra/shared';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma } from '../src/db';
import { QUIZ_TIMING } from '../src/games/quiz';
import { ROOM_TIMING } from '../src/rooms/GameRoom';
import { startServer } from '../src/server';
import { Api, resetDb, seedApprovedQuiz, waitFor } from './helpers';

let server: Awaited<ReturnType<typeof startServer>>;
let api: Api;
let wsUrl: string;

beforeAll(async () => {
  Object.assign(ROOM_TIMING, { privateCountdownMs: 200, resultsHoldMs: 500 });
  Object.assign(QUIZ_TIMING, { revealLeadMs: 100, revealStageMs: 150, botMinDelayMs: 50, botMaxShare: 0.05 });
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

describe('practice against bots', () => {
  it('starts alone, shows bots as bots, reveals picks, and pays nothing', async () => {
    const p = await api.player('solo');
    const t = await api.call('POST', '/matchmaking/ticket', { gameId: 'quiz', mode: 'practice' }, p.token);
    expect(t.status).toBe(200);
    expect(t.body.options.ageBucket).toBe('any');
    const room = await new Client(wsUrl).create('game', {
      ...t.body.options,
      ticket: t.body.ticket,
      config: { questionCount: 5, answerSeconds: 8 },
    });
    const views: RoomView<QuizView>[] = [];
    let summary: MatchSummary | undefined;
    room.onMessage('view', (v: RoomView<QuizView>) => views.push(v));
    room.onMessage('matchSummary', (m: { summary: MatchSummary }) => (summary = m.summary));
    room.onMessage('error', () => {});

    const first = await waitFor(() => views.find((v) => v.players.length === 4), 5_000, 'bots seated');
    const bots = first.players.filter((x) => x.isBot);
    expect(bots).toHaveLength(3);
    expect(bots.every((b) => b.displayName.startsWith('بوت'))).toBe(true);
    expect(first.players.find((x) => x.playerId === p.id)!.isHost).toBe(true);

    // The match starts without anyone pressing start; answer every question.
    let sawPicks = false;
    const answered = new Set<number>();
    await waitFor(() => {
      const v = views[views.length - 1];
      const g = v?.game;
      if (g?.reveal && Object.keys(g.reveal.picks).some((id) => id.startsWith('bot_'))) sawPicks = true;
      if (g?.stage === 'question' && g.question && !answered.has(g.question.index) && v!.serverNow >= g.question.revealAt) {
        answered.add(g.question.index);
        room.send('action', { action: { kind: 'answer', questionIndex: g.question.index, choice: 0 } });
      }
      return views.some((x) => x.game?.stage === 'finished') ? true : null;
    }, 30_000, 'match finished');

    expect(sawPicks).toBe(true);
    const s = await waitFor(() => summary, 5_000, 'summary');
    expect(s).toMatchObject({ xp: 0, coins: 0, rating: null });
    expect(s.notes).toContain('practice_no_rewards');
    expect(await prisma.match.count()).toBe(0);
    expect(await prisma.ledgerEntry.count()).toBe(0);

    // "Play again" from the results screen starts a new countdown right away.
    const before = views.length;
    room.send('start');
    await waitFor(() => (views.slice(before).some((v) => v.phase === 'countdown') ? true : null), 3_000, 'rematch countdown');
    await room.leave();
  });
});
