/** Shop, daily login, missions, achievements and leaderboards. */
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma } from '../src/db';
import { startServer } from '../src/server';
import { balances, grant } from '../src/economy/ledger';
import { gameDay, gameWeek, leaderboard, missionsView } from '../src/progress/service';
import { Api, resetDb } from './helpers';

let server: Awaited<ReturnType<typeof startServer>>;
let api: Api;

beforeAll(async () => {
  server = await startServer(0);
  api = new Api(`http://localhost:${server.port}`);
});
afterAll(async () => {
  await server.close();
  await prisma.$disconnect();
});
beforeEach(async () => {
  await resetDb();
});

type P = { token: string; id: string };
const call = (p: P, method: string, path: string, body?: unknown) => api.call(method, '/progress' + path, body, p.token);

/** Saves a finished match directly (the same rows a real match leaves behind). */
async function played(
  userId: string,
  o: { gameId?: string; mode?: string; place?: number; perf?: number; night?: boolean; others?: string[]; at?: Date } = {},
) {
  const players = [userId, ...(o.others ?? [])];
  await prisma.match.create({
    data: {
      roomId: 'r',
      gameId: o.gameId ?? 'quiz',
      mode: o.mode ?? 'casual',
      commMode: 'normal',
      config: {},
      seed: 's',
      state: 'completed',
      night: o.night ?? false,
      endedAt: o.at ?? new Date(),
      players: {
        create: players.map((id, i) => ({ userId: id, place: i === 0 ? (o.place ?? 2) : i + 1, performance: i === 0 ? (o.perf ?? 0.5) : 0.1 })),
      },
    },
  });
}
async function opponent() {
  return (await api.player('opp' + Math.random().toString(36).slice(2, 8))).id;
}
const coins = async (id: string) => (await balances(id)).coins;

describe('game day and week', () => {
  it('starts days at midnight Cairo time and weeks on Saturday', () => {
    // 2026-11-28 is a Saturday. 22:30 UTC on the 27th is 00:30 on the 28th in Cairo.
    const t = Date.UTC(2026, 10, 27, 22, 30);
    expect(gameDay(t).id).toBe('2026-11-28');
    expect(gameWeek(t).id).toBe('2026-11-28');
    expect(gameWeek(Date.UTC(2026, 10, 27, 12)).id).toBe('2026-11-21'); // Friday belongs to last week
  });
});

describe('daily login', () => {
  it('claims once a day and a missed day never resets the track', async () => {
    const a = await api.player('la');
    let m = (await call(a, 'GET', '/missions')).body;
    expect(m.login).toMatchObject({ step: 1, claimedToday: false, welcomeBack: null });
    const r = await call(a, 'POST', '/login/claim');
    expect(r.body.reward).toEqual({ coins: 30 });
    expect((await call(a, 'POST', '/login/claim')).body.error).toBe('already_claimed');
    expect(await coins(a.id)).toBe(30);
    m = (await call(a, 'GET', '/missions')).body;
    expect(m.login).toMatchObject({ step: 1, claimedToday: true });
    // Five days later (four missed): the next step, not back to step 1.
    const later = Date.now() + 5 * 86_400_000;
    expect((await missionsView(a.id, later)).login.step).toBe(2);
  });

  it('gives a small welcome-back bonus after a long break, at most once a month', async () => {
    const a = await api.player('lb');
    await call(a, 'POST', '/login/claim');
    await prisma.rewardClaim.updateMany({ where: { userId: a.id }, data: { createdAt: new Date(Date.now() - 10 * 86_400_000) } });
    // Pretend that claim was on an old day (its ledger key moves with it).
    await prisma.rewardClaim.updateMany({ where: { userId: a.id }, data: { key: 'login:2000-01-01' } });
    await prisma.ledgerEntry.updateMany({ where: { userId: a.id }, data: { idempotencyKey: `claim:${a.id}:login:2000-01-01:coins` } });
    const m = (await call(a, 'GET', '/missions')).body;
    expect(m.login.welcomeBack).toEqual({ coins: 150, xp: 50 });
    const r = (await call(a, 'POST', '/login/claim')).body;
    expect(r.welcomeBack).toEqual({ coins: 150, xp: 50 });
    expect(await coins(a.id)).toBe(30 + 40 + 150);
  });
});

describe('missions', () => {
  it('counts saved matches of today, pays once, and refuses unfinished missions', async () => {
    const a = await api.player('ma');
    const opp = await opponent();
    let m = (await call(a, 'GET', '/missions')).body;
    expect(m.daily).toHaveLength(3);
    expect(m.weekly).toHaveLength(3);
    expect(new Set(m.daily.map((x: { kind: string }) => x.kind)).size).toBe(3);
    expect(m.dailyEndsAt).toBeGreaterThan(Date.now());
    // Same missions all day for this player.
    expect((await call(a, 'GET', '/missions')).body.daily.map((x: { id: string }) => x.id)).toEqual(m.daily.map((x: { id: string }) => x.id));
    const first = m.daily[0];
    expect((await call(a, 'POST', '/missions/claim', { id: first.id })).body.error).toBe('mission_not_done');

    // Plenty of varied play: every daily mission is done.
    const games = ['quiz', 'spy', 'liar', 'who', 'emoji', 'stop', 'memory', 'draw', 'football', 'acting'];
    for (const g of games) await played(a.id, { gameId: g, place: 1, perf: 1, mode: 'private', others: [opp] });
    m = (await call(a, 'GET', '/missions')).body;
    for (const d of m.daily) expect(d.progress).toBe(d.target);
    const before = await coins(a.id);
    const r = await call(a, 'POST', '/missions/claim', { id: first.id });
    expect(r.status).toBe(200);
    expect(await coins(a.id)).toBe(before + (first.reward.coins ?? 0));
    expect((await call(a, 'POST', '/missions/claim', { id: first.id })).body.error).toBe('already_claimed');
    expect((await call(a, 'GET', '/missions')).body.daily[0].claimed).toBe(true);
    // Yesterday's matches do not count for today.
    const b = await api.player('mb');
    await played(b.id, { at: new Date(gameDay().start - 60_000), others: [opp] });
    const mb = await missionsView(b.id);
    const playAny = mb.daily.find((x) => x.kind === 'play_any');
    if (playAny) expect(playAny.progress).toBe(0);
  });

  it('never asks minors to play a game that is not Safe Mode ready', async () => {
    const t = await api.player('mteen', '2011-03-03');
    for (let i = 0; i < 40; i++) {
      const v = await missionsView(t.id, Date.now() + i * 86_400_000);
      for (const d of v.daily) if (d.kind === 'play_game') expect(d.gameId).not.toBe('draw');
    }
  });
});

describe('achievements', () => {
  it('tracks progress from matches and grants items that cannot be bought', async () => {
    const a = await api.player('aa');
    const opp = await opponent();
    let list = (await call(a, 'GET', '/achievements')).body.achievements;
    expect(list.find((x: { id: string }) => x.id === 'matches_1')).toMatchObject({ progress: 0, claimed: false });
    for (let i = 0; i < 25; i++) await played(a.id, { place: 1, others: [opp] });
    // Who Among Us has no winners: first place there is not a win.
    await played(a.id, { gameId: 'who', place: 1, others: [opp] });
    list = (await call(a, 'GET', '/achievements')).body.achievements;
    const wins = list.find((x: { id: string }) => x.id === 'wins_25');
    expect(wins).toMatchObject({ progress: 25, target: 25 });
    expect(list.find((x: { id: string }) => x.id === 'quiz_wins_10').progress).toBe(10);
    expect(list.find((x: { id: string }) => x.id === 'matches_200').progress).toBe(26);

    // The champion frame is not for sale...
    expect((await call(a, 'POST', '/shop/buy', { itemId: 'frame_champion' })).body.error).toBe('not_for_sale');
    expect((await call(a, 'POST', '/shop/equip', { kind: 'frame', itemId: 'frame_champion' })).body.error).toBe('not_owned');
    // ...it comes with the achievement.
    const r = await call(a, 'POST', '/achievements/claim', { id: 'wins_25' });
    expect(r.body.reward).toMatchObject({ coins: 400, gems: 10, item: 'frame_champion' });
    expect((await call(a, 'POST', '/achievements/claim', { id: 'wins_25' })).body.error).toBe('already_claimed');
    expect((await call(a, 'POST', '/achievements/claim', { id: 'wins_100' })).body.error).toBe('achievement_not_done');
    const shop = (await call(a, 'POST', '/shop/equip', { kind: 'frame', itemId: 'frame_champion' })).body;
    expect(shop.loadout.frame).toBe('frame_champion');
    expect(shop.items.find((x: { id: string }) => x.id === 'frame_champion')).toMatchObject({ owned: true, equipped: true, unlockedByPlay: true });
    expect(shop.gems).toBe(10);
  });
});

describe('shop', () => {
  it('sells for coins, never twice, never below zero, and unlocks by level for free', async () => {
    const a = await api.player('sa');
    let shop = (await call(a, 'GET', '/shop')).body;
    expect(shop.loadout).toEqual({ frame: 'frame_basic', title: 'title_newcomer', theme: 'theme_night', effect: 'effect_confetti' });
    expect(shop.gemPurchasesAvailable).toBe(false);
    for (const item of shop.items) {
      // Every paid item also has a way to earn it by playing.
      if (item.price) expect(['level', 'achievement']).toContain(item.unlock.kind);
    }
    expect((await call(a, 'POST', '/shop/buy', { itemId: 'frame_mint' })).body.error).toBe('not_enough_coins');

    await prisma.$transaction((tx) => grant(tx, { userId: a.id, currency: 'coins', amount: 1000, reason: 'test', idempotencyKey: 'test:sa' }));
    // Two items at once with coins for only one of them (500 + 700 > 1000).
    const [x, y] = await Promise.all([
      call(a, 'POST', '/shop/buy', { itemId: 'frame_coral' }),
      call(a, 'POST', '/shop/buy', { itemId: 'effect_stars' }),
    ]);
    expect([x.status, y.status].sort()).toEqual([200, 409]);
    const c = await coins(a.id);
    expect(c === 500 || c === 300).toBe(true);
    expect(c).toBeGreaterThanOrEqual(0);
    const bought = x.status === 200 ? 'frame_coral' : 'effect_stars';
    expect((await call(a, 'POST', '/shop/buy', { itemId: bought })).body.error).toBe('already_owned');

    // Level 5 unlocks the sun frame without paying.
    await prisma.progression.upsert({ where: { userId: a.id }, create: { userId: a.id, xp: 1000, level: 5 }, update: { level: 5 } });
    shop = (await call(a, 'GET', '/shop')).body;
    expect(shop.items.find((i: { id: string }) => i.id === 'frame_sun')).toMatchObject({ owned: true, unlockedByPlay: true });
    expect((await call(a, 'POST', '/shop/buy', { itemId: 'frame_sun' })).body.error).toBe('already_owned');
    expect((await call(a, 'POST', '/shop/equip', { kind: 'title', itemId: 'frame_sun' })).body.error).toBe('item_not_found');
    expect((await call(a, 'POST', '/shop/equip', { kind: 'frame', itemId: 'frame_sun' })).body.loadout.frame).toBe('frame_sun');
  });
});

describe('leaderboards', () => {
  it('counts only the best matches per game, keeps age groups apart, and has a friends view', async () => {
    const a = await api.player('ba', '1990-01-01', 'سارة');
    const b = await api.player('bb', '1991-01-01', 'كريم');
    const teen = await api.player('bt', '2010-01-01', 'تيم');
    const opp = await opponent();
    for (let i = 0; i < 12; i++) await played(a.id, { perf: 1, others: [opp] }); // only 10 count this week
    await played(b.id, { perf: 0.9, others: [opp] });
    await played(b.id, { gameId: 'spy', perf: 0.8, others: [opp] });
    await played(b.id, { perf: 1, mode: 'private', others: [opp] }); // private rooms do not count globally
    await played(teen.id, { perf: 1, others: [opp] });

    const lb = (await call(a, 'GET', '/leaderboards?game=all&period=week')).body;
    expect(lb.bestOf).toBe(10);
    const pts = Object.fromEntries(lb.rows.map((r: { playerId: string; points: number }) => [r.playerId, r.points]));
    expect(pts[a.id]).toBe(1000);
    expect(pts[b.id]).toBe(170);
    expect(pts[teen.id]).toBeUndefined();
    expect(lb.you).toMatchObject({ rank: 1, displayName: 'سارة' });
    expect(lb.rows[0].cosmetics.frame).toBeTruthy();

    // A teen sees only teens.
    const lt = (await call(teen, 'GET', '/leaderboards?game=quiz&period=week')).body;
    expect(lt.rows.map((r: { playerId: string }) => r.playerId)).toEqual([teen.id]);

    // Last week's matches are not on this week's board but stay on all-time.
    await played(b.id, { perf: 1, others: [opp], at: new Date(gameWeek().start - 86_400_000) });
    const week = await leaderboard(b.id, { gameId: 'quiz', period: 'week', scope: 'global' });
    const all = await leaderboard(b.id, { gameId: 'quiz', period: 'all', scope: 'global' });
    expect(week.you?.points).toBe(90);
    expect(all.you?.points).toBe(190);

    // Friends board: only friends, private rooms included.
    await prisma.friendship.create({ data: { requesterId: a.id, addresseeId: b.id, status: 'accepted', acceptedAt: new Date() } });
    const fr = await leaderboard(b.id, { gameId: 'quiz', period: 'week', scope: 'friends' });
    expect(fr.rows.map((r) => r.playerId).sort()).toEqual([a.id, b.id].sort());
    expect(fr.you?.points).toBe(190);
  });
});
