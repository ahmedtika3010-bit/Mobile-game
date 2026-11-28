/** Stop end to end: two clients, private room, an appeal saved for human review. */
import { Client, type Room } from 'colyseus.js';
import type { MatchSummary, RoomView, StopView } from '@sahra/shared';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma } from '../src/db';
import { STOP_TIMING } from '../src/games/stop';
import { ROOM_TIMING } from '../src/rooms/GameRoom';
import { startServer } from '../src/server';
import { Api, resetDb, waitFor } from './helpers';

let server: Awaited<ReturnType<typeof startServer>>;
let api: Api;
let wsUrl: string;

beforeAll(async () => {
  Object.assign(ROOM_TIMING, { privateCountdownMs: 200, resultsHoldMs: 500 });
  Object.assign(STOP_TIMING, { reviewMs: 300 });
  server = await startServer(0);
  api = new Api(`http://localhost:${server.port}`);
  wsUrl = `ws://localhost:${server.port}`;
});
afterAll(async () => {
  await server.close();
  await prisma.$disconnect();
});
// Two letters (ب, س) with two words in every category.
const DICT: Record<string, string[]> = {
  boy: ['باسم', 'بلال', 'سامي', 'سعيد'],
  girl: ['بسمة', 'بشرى', 'سارة', 'سلمى'],
  animal: ['بطة', 'بقرة', 'سمكة', 'سنجاب'],
  plant: ['بصل', 'بطيخ', 'سبانخ', 'سمسم'],
  object: ['باب', 'برطمان', 'ساعة', 'سرير'],
  country: ['بلجيكا', 'البرازيل', 'السويد', 'سوريا'],
};
beforeEach(async () => {
  await resetDb();
  await prisma.contentItem.createMany({
    data: Object.entries(DICT).map(([category, words]) => ({ gameId: 'stop', category, difficulty: 'medium', status: 'approved' as const, payload: { words } })),
  });
});

/** Player 0 writes the first dictionary word plus an unknown animal, and appeals it; player 1 writes the first word too. */
function autoplay(room: Room, appeal: boolean) {
  const views: RoomView<StopView>[] = [];
  let summary: MatchSummary | undefined;
  const sent = new Set<string>();
  room.onMessage('view', (v: RoomView<StopView>) => {
    views.push(v);
    const g = v.game;
    if (!g || !g.letter) return;
    if (g.stage === 'answer' && !sent.has(`a${g.round}`)) {
      sent.add(`a${g.round}`);
      const answers = Object.fromEntries(Object.entries(DICT).map(([c, ws]) => [c, ws.find((w) => w.replace(/^ال/, '').startsWith(g.letter!))!]));
      if (appeal) answers.animal = `${g.letter}حيوان نادر`;
      room.send('action', { action: { kind: 'answers', round: g.round, answers, done: true } });
    }
    if (appeal && g.stage === 'review' && g.result?.cells.animal[v.you]?.verdict === 'unknown' && !sent.has(`p${g.round}`)) {
      sent.add(`p${g.round}`);
      room.send('action', { action: { kind: 'appeal', round: g.round, category: 'animal' } });
    }
  });
  room.onMessage('matchSummary', (m: { summary: MatchSummary }) => (summary = m.summary));
  ['error', 'quickChat'].forEach((m) => room.onMessage(m, () => {}));
  return { views, summary: () => summary, last: () => views[views.length - 1] };
}

describe('stop match', () => {
  it('plays a private match and saves appeals for review', async () => {
    const ps = await Promise.all(['sa', 'sb'].map((n) => api.player(n)));
    const ticket = async (token: string) => (await api.call('POST', '/matchmaking/ticket', { gameId: 'stop', mode: 'private' }, token)).body;
    const t0 = await ticket(ps[0]!.token);
    const r0 = await new Client(wsUrl).create('game', { ...t0.options, ticket: t0.ticket, config: { rounds: 2, answerSeconds: 30 } });
    const a0 = autoplay(r0, true);
    const code = (await waitFor(() => a0.last()?.code, 5_000, 'code'))!;
    const { roomId } = (await api.call('GET', `/rooms/by-code/${code}`, undefined, ps[1]!.token)).body;
    const t1 = await ticket(ps[1]!.token);
    const a1 = autoplay(await new Client(wsUrl).joinById(roomId, { ticket: t1.ticket }), false);
    await waitFor(() => a0.last()?.players.length === 2, 5_000, 'both seated');
    r0.send('start');
    await waitFor(() => a0.last()?.game?.final && a1.last()?.game?.final, 20_000, 'finished');
    const f = a0.last()!.game!.final!;
    // Same five words each round (5 points each); player 0's animal is unknown, player 1's is unique.
    expect(f.ranking.find((r) => r.playerId === ps[1]!.id)).toMatchObject({ score: 2 * (5 * 5 + 10), place: 1 });
    expect(f.ranking.find((r) => r.playerId === ps[0]!.id)).toMatchObject({ score: 2 * 25, place: 2 });
    // Player 1 never saw player 0's unknown word.
    expect(JSON.stringify(a1.views)).not.toContain('حيوان نادر');
    await waitFor(() => a0.summary() && a1.summary(), 10_000, 'summaries');
    const appeals = await prisma.contentItem.findMany({ where: { gameId: 'stop', status: 'in_review' } });
    expect(appeals).toHaveLength(2);
    expect(appeals.map((x) => (x.payload as { words: string[] }).words[0]).every((w) => w?.endsWith('حيوان نادر') === true)).toBe(true);
  });
});
