/**
 * Shop, missions, achievements, daily login and leaderboards.
 *
 * Progress is always read from saved matches (never from counters the client
 * could push), and every reward is claimed through a unique RewardClaim row
 * plus idempotent ledger grants, so a retried request cannot pay twice.
 */
import { Prisma } from '@prisma/client';
import type {
  AchievementView,
  CosmeticItem,
  CosmeticKind,
  GameId,
  LeaderboardPeriod,
  LeaderboardRow,
  LeaderboardScope,
  LeaderboardView,
  Loadout,
  MissionPeriod,
  MissionView,
  MissionsView,
  PublicCosmetics,
  Reward,
  ShopView,
} from '@sahra/shared';
import { matchmakingAgeBucket } from '@sahra/shared';
import { prisma, type Tx } from '../db';
import { grant } from '../economy/ledger';
import { Rng } from '../games/engine';
import { getGame } from '../games/registry';
import { displayRating } from '../rating/rating';
import { config } from '../config';
import {
  ACHIEVEMENTS,
  ALL_GAMES,
  COSMETICS,
  DAILY_MISSIONS,
  DEFAULT_LOADOUT,
  WEEKLY_MISSIONS,
  achievementById,
  cosmeticById,
  progressConfig,
  type MissionTemplate,
} from './catalog';

export class ProgressError extends Error {
  constructor(public status: number, public code: string) {
    super(code);
  }
}

/* --------------------------------- time ---------------------------------- */

const DAY = 86_400_000;

/** The game day (YYYY-MM-DD) and its start, in the configured offset. */
export function gameDay(now = Date.now()) {
  const off = progressConfig.dayOffsetMinutes * 60_000;
  const local = now + off;
  const start = Math.floor(local / DAY) * DAY - off;
  return { id: new Date(local).toISOString().slice(0, 10), start, end: start + DAY };
}

/** Weeks start on Saturday (as in most of the region). */
export function gameWeek(now = Date.now()) {
  const d = gameDay(now);
  const off = progressConfig.dayOffsetMinutes * 60_000;
  const weekday = new Date(d.start + off).getUTCDay(); // 0 = Sunday, 6 = Saturday
  const start = d.start - ((weekday + 1) % 7) * DAY;
  return { id: new Date(start + off).toISOString().slice(0, 10), start, end: start + 7 * DAY };
}

/* -------------------------------- matches -------------------------------- */

export interface PlayedMatch {
  gameId: GameId;
  mode: string;
  night: boolean;
  place: number | null;
  performance: number;
  players: number;
  endedAt: Date;
}

/** Matches the player finished (not left early) since a time. Practice is never saved. */
export async function playedMatches(userId: string, since?: number): Promise<PlayedMatch[]> {
  const rows = await prisma.matchPlayer.findMany({
    where: {
      userId,
      leftEarly: false,
      match: { state: 'completed', ...(since ? { endedAt: { gte: new Date(since) } } : {}) },
    },
    select: {
      place: true,
      performance: true,
      match: { select: { gameId: true, mode: true, night: true, endedAt: true, _count: { select: { players: true } } } },
    },
  });
  return rows.map((r) => ({
    gameId: r.match.gameId as GameId,
    mode: r.match.mode,
    night: r.match.night,
    place: r.place,
    performance: r.performance ?? 0,
    players: r.match._count.players,
    endedAt: r.match.endedAt ?? new Date(0),
  }));
}

/** A real win: first place, against at least one other player, in a game that has winners. */
export const isWin = (m: PlayedMatch) => m.place === 1 && m.players >= 2 && getGame(m.gameId)?.capabilities.rewards !== 'participation';

/* -------------------------------- rewards -------------------------------- */

/** Claims a reward once: the RewardClaim row is the lock, grants are keyed by it too. */
async function claimOnce(tx: Tx, userId: string, key: string, reward: Reward, source: string): Promise<boolean> {
  const res = await tx.rewardClaim.createMany({ data: [{ userId, key }], skipDuplicates: true });
  if (res.count === 0) return false;
  for (const currency of ['coins', 'gems', 'xp'] as const) {
    const amount = reward[currency];
    if (amount) await grant(tx, { userId, currency, amount, reason: source, idempotencyKey: `claim:${userId}:${key}:${currency}` });
  }
  if (reward.item) {
    await tx.ownedCosmetic.createMany({ data: [{ userId, itemId: reward.item, source: `${source}:${key}` }], skipDuplicates: true });
  }
  return true;
}

async function claimedKeys(userId: string, prefix: string) {
  const rows = await prisma.rewardClaim.findMany({ where: { userId, key: { startsWith: prefix } }, select: { key: true, createdAt: true } });
  return rows;
}

async function userOrThrow(userId: string) {
  const u = await prisma.user.findUnique({ where: { id: userId } });
  if (!u) throw new ProgressError(404, 'not_found');
  return u;
}

/* -------------------------------- missions ------------------------------- */

function pickMissions(userId: string, periodId: string, pool: MissionTemplate[], count: number, minor: boolean) {
  const rng = new Rng(`${userId}:${periodId}`);
  const picked = rng.shuffle(pool).slice(0, count);
  // Games a minor can play in public (Safe Mode ready) for "play this game" missions.
  const games = ALL_GAMES.filter((g) => !minor || getGame(g)?.capabilities.safeModeReady);
  return picked.map((t) => ({ ...t, gameId: t.kind === 'play_game' ? games[rng.int(games.length)] : undefined }));
}

function missionProgress(t: MissionTemplate & { gameId?: GameId }, ms: PlayedMatch[]): number {
  switch (t.kind) {
    case 'play_any':
      return ms.length;
    case 'play_distinct':
      return new Set(ms.map((m) => m.gameId)).size;
    case 'win':
      return ms.filter(isWin).length;
    case 'play_game':
      return ms.filter((m) => m.gameId === t.gameId).length;
    case 'perf':
      return ms.reduce((a, m) => a + Math.round(100 * Math.max(0, Math.min(1, m.performance))), 0);
    case 'private':
      return ms.filter((m) => m.mode === 'private').length;
    case 'night':
      return ms.filter((m) => m.night).length;
  }
}

async function missionList(userId: string, now: number) {
  const u = await userOrThrow(userId);
  const minor = matchmakingAgeBucket(u.ageBand) === 'minor';
  const day = gameDay(now);
  const week = gameWeek(now);
  const weekMatches = await playedMatches(userId, week.start);
  const dayMatches = weekMatches.filter((m) => m.endedAt.getTime() >= day.start);
  const claimed = new Set((await claimedKeys(userId, 'mission:')).map((c) => c.key));
  const build = (period: MissionPeriod, periodId: string, pool: MissionTemplate[], count: number, ms: PlayedMatch[]): MissionView[] =>
    pickMissions(userId, periodId, pool, count, minor).map((t, i) => {
      const id = `mission:${period === 'daily' ? 'd' : 'w'}:${periodId}:${i}`;
      return {
        id,
        period,
        kind: t.kind,
        ...(t.gameId ? { gameId: t.gameId } : {}),
        target: t.target,
        progress: Math.min(t.target, missionProgress(t, ms)),
        reward: t.reward,
        claimed: claimed.has(id),
      };
    });
  return {
    daily: build('daily', day.id, DAILY_MISSIONS, progressConfig.dailyMissionCount, dayMatches),
    weekly: build('weekly', week.id, WEEKLY_MISSIONS, progressConfig.weeklyMissionCount, weekMatches),
    day,
    week,
  };
}

async function loginState(userId: string, now: number) {
  const day = gameDay(now);
  const logins = (await claimedKeys(userId, 'login:')).sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime());
  const claimedToday = logins.some((l) => l.key === `login:${day.id}`);
  const previous = logins.filter((l) => l.key !== `login:${day.id}`);
  const track = progressConfig.loginTrack;
  const step = ((claimedToday ? logins.length - 1 : logins.length) % track.length) + 1;
  // Welcome back: the last visit was long ago, and no such bonus recently.
  const wb = progressConfig.welcomeBack;
  const last = previous.at(-1);
  const welcomes = await claimedKeys(userId, 'welcome:');
  const recentWelcome = welcomes.some((w) => now - w.createdAt.getTime() < wb.onceEveryDays * DAY);
  const away = last ? now - last.createdAt.getTime() >= wb.afterDays * DAY : false;
  const welcomeAvailable = !claimedToday && away && !recentWelcome;
  return { day, step, claimedToday, track, welcomeAvailable, welcomedToday: welcomes.some((w) => w.key === `welcome:${day.id}`) };
}

export async function missionsView(userId: string, now = Date.now()): Promise<MissionsView> {
  const m = await missionList(userId, now);
  const l = await loginState(userId, now);
  return {
    daily: m.daily,
    weekly: m.weekly,
    dailyEndsAt: m.day.end,
    weeklyEndsAt: m.week.end,
    login: {
      step: l.step,
      claimedToday: l.claimedToday,
      rewards: l.track,
      welcomeBack: l.welcomeAvailable ? progressConfig.welcomeBack.reward : null,
    },
  };
}

export async function claimMission(userId: string, missionId: string, now = Date.now()): Promise<Reward> {
  const { daily, weekly } = await missionList(userId, now);
  const m = [...daily, ...weekly].find((x) => x.id === missionId);
  if (!m) throw new ProgressError(404, 'mission_not_found');
  if (m.progress < m.target) throw new ProgressError(409, 'mission_not_done');
  const ok = await prisma.$transaction((tx) => claimOnce(tx, userId, m.id, m.reward, 'mission'));
  if (!ok) throw new ProgressError(409, 'already_claimed');
  return m.reward;
}

export async function claimLogin(userId: string, now = Date.now()): Promise<{ reward: Reward; welcomeBack: Reward | null }> {
  const l = await loginState(userId, now);
  if (l.claimedToday) throw new ProgressError(409, 'already_claimed');
  const reward = l.track[l.step - 1]!;
  const welcome = l.welcomeAvailable ? progressConfig.welcomeBack.reward : null;
  const ok = await prisma.$transaction(async (tx) => {
    const done = await claimOnce(tx, userId, `login:${l.day.id}`, reward, 'login');
    if (done && welcome) await claimOnce(tx, userId, `welcome:${l.day.id}`, welcome, 'welcome_back');
    return done;
  });
  if (!ok) throw new ProgressError(409, 'already_claimed');
  return { reward, welcomeBack: welcome };
}

/* ------------------------------ achievements ----------------------------- */

export async function achievementsView(userId: string): Promise<AchievementView[]> {
  const [ms, prog, friends, claims] = await Promise.all([
    playedMatches(userId),
    prisma.progression.findUnique({ where: { userId } }),
    prisma.friendship.count({ where: { status: 'accepted', OR: [{ requesterId: userId }, { addresseeId: userId }] } }),
    claimedKeys(userId, 'ach:'),
  ]);
  const claimed = new Set(claims.map((c) => c.key));
  const level = prog?.level ?? 1;
  return ACHIEVEMENTS.map((a) => {
    const mine = a.gameId ? ms.filter((m) => m.gameId === a.gameId) : ms;
    const value = {
      matches: () => mine.length,
      wins: () => mine.filter(isWin).length,
      distinct: () => new Set(ms.map((m) => m.gameId)).size,
      level: () => level,
      friends: () => friends,
      nights: () => ms.filter((m) => m.night).length,
    }[a.kind]();
    return {
      id: a.id,
      gameId: a.gameId,
      kind: a.kind,
      target: a.target,
      progress: Math.min(a.target, value),
      reward: a.reward,
      claimed: claimed.has(`ach:${a.id}`),
    };
  });
}

export async function claimAchievement(userId: string, id: string): Promise<Reward> {
  const def = achievementById(id);
  if (!def) throw new ProgressError(404, 'achievement_not_found');
  const a = (await achievementsView(userId)).find((x) => x.id === id)!;
  if (a.progress < a.target) throw new ProgressError(409, 'achievement_not_done');
  const ok = await prisma.$transaction((tx) => claimOnce(tx, userId, `ach:${id}`, def.reward, 'achievement'));
  if (!ok) throw new ProgressError(409, 'already_claimed');
  return def.reward;
}

/* ---------------------------------- shop --------------------------------- */

function ownedSet(stored: string[], level: number): { owned: Set<string>; byPlay: Set<string> } {
  const owned = new Set(stored);
  const byPlay = new Set<string>();
  for (const c of COSMETICS) {
    if (c.unlock.kind === 'default' || (c.unlock.kind === 'level' && level >= c.unlock.level)) {
      owned.add(c.id);
      byPlay.add(c.id);
    } else if (c.unlock.kind === 'achievement' && stored.includes(c.id)) byPlay.add(c.id);
  }
  return { owned, byPlay };
}

export function resolveLoadout(raw: unknown): Required<Loadout> {
  const l = (raw && typeof raw === 'object' ? raw : {}) as Loadout;
  const out = { ...DEFAULT_LOADOUT } as Required<Loadout>;
  for (const kind of ['frame', 'title', 'theme', 'effect'] as CosmeticKind[]) {
    const id = l[kind];
    if (id && cosmeticById(id)?.kind === kind) out[kind] = id;
  }
  return out;
}

/** What other players see in rooms and on leaderboards. */
export function publicCosmetics(raw: unknown): PublicCosmetics {
  const l = resolveLoadout(raw);
  const look = (id: string) => cosmeticById(id)?.look;
  return { frame: look(l.frame), title: look(l.title), effect: look(l.effect) };
}

async function shopState(userId: string) {
  const [u, prog, owned, wallet] = await Promise.all([
    userOrThrow(userId),
    prisma.progression.findUnique({ where: { userId } }),
    prisma.ownedCosmetic.findMany({ where: { userId }, select: { itemId: true } }),
    prisma.ledgerEntry.groupBy({ by: ['currency'], where: { userId }, _sum: { amount: true } }),
  ]);
  const level = prog?.level ?? 1;
  const sets = ownedSet(owned.map((o) => o.itemId), level);
  const bal = (c: string) => wallet.find((w) => w.currency === c)?._sum.amount ?? 0;
  return { u, level, ...sets, coins: bal('coins'), gems: bal('gems') };
}

export async function shopView(userId: string): Promise<ShopView> {
  const s = await shopState(userId);
  const loadout = resolveLoadout(s.u.loadout);
  return {
    items: COSMETICS.map((c: CosmeticItem) => ({
      ...c,
      owned: s.owned.has(c.id),
      equipped: loadout[c.kind] === c.id,
      unlockedByPlay: s.byPlay.has(c.id),
    })),
    loadout,
    coins: s.coins,
    gems: s.gems,
    level: s.level,
    gemPurchasesAvailable: progressConfig.gemPurchasesAvailable,
  };
}

export async function buyItem(userId: string, itemId: string) {
  const item = cosmeticById(itemId);
  if (!item) throw new ProgressError(404, 'item_not_found');
  if (!item.price) throw new ProgressError(409, 'not_for_sale');
  const price = item.price;
  await prisma.$transaction(async (tx) => {
    // One purchase at a time per player, so two taps cannot both spend the same coins.
    await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${userId}))`;
    const prog = await tx.progression.findUnique({ where: { userId } });
    const stored = await tx.ownedCosmetic.findMany({ where: { userId }, select: { itemId: true } });
    if (ownedSet(stored.map((o) => o.itemId), prog?.level ?? 1).owned.has(itemId)) throw new ProgressError(409, 'already_owned');
    const bal = await tx.ledgerEntry.aggregate({ where: { userId, currency: price.currency }, _sum: { amount: true } });
    if ((bal._sum.amount ?? 0) < price.amount) throw new ProgressError(409, 'not_enough_' + price.currency);
    await grant(tx, { userId, currency: price.currency, amount: -price.amount, reason: 'purchase', idempotencyKey: `buy:${userId}:${itemId}`, refId: itemId });
    await tx.ownedCosmetic.create({ data: { userId, itemId, source: 'purchase' } });
  });
  return shopView(userId);
}

export async function equip(userId: string, kind: CosmeticKind, itemId: string) {
  const item = cosmeticById(itemId);
  if (!item || item.kind !== kind) throw new ProgressError(404, 'item_not_found');
  const s = await shopState(userId);
  if (!s.owned.has(itemId)) throw new ProgressError(403, 'not_owned');
  const loadout = { ...resolveLoadout(s.u.loadout), [kind]: itemId };
  await prisma.user.update({ where: { id: userId }, data: { loadout } });
  return shopView(userId);
}

/* ------------------------------ leaderboards ----------------------------- */

function periodStart(period: LeaderboardPeriod, now: number): number | null {
  if (period === 'week') return gameWeek(now).start;
  if (period === 'month') {
    const off = progressConfig.dayOffsetMinutes * 60_000;
    const d = new Date(now + off);
    return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1) - off;
  }
  return null;
}

/** Games that appear on leaderboards (Who Among Us has no winners by design). */
export const LEADERBOARD_GAMES = ALL_GAMES.filter((g) => getGame(g)?.capabilities.rewards !== 'participation');

export async function leaderboard(
  userId: string,
  opts: { gameId: GameId | 'all'; period: LeaderboardPeriod; scope: LeaderboardScope; metric?: 'points' | 'rating' },
  now = Date.now(),
): Promise<LeaderboardView> {
  const me = await userOrThrow(userId);
  const bucket = matchmakingAgeBucket(me.ageBand);
  const bestOf = progressConfig.leaderboard.bestOf[opts.period];
  const size = progressConfig.leaderboard.size;
  let ids: string[] | null = null;
  if (opts.scope === 'friends') {
    const fs = await prisma.friendship.findMany({
      where: { status: 'accepted', OR: [{ requesterId: userId }, { addresseeId: userId }] },
      select: { requesterId: true, addresseeId: true },
    });
    ids = [userId, ...fs.map((f) => (f.requesterId === userId ? f.addresseeId : f.requesterId))];
  }
  // Players only ever see their own age group (adults with adults, minors with minors).
  const bands = bucket === 'adult' ? ['adult'] : ['teen_13_15', 'teen_16_17'];

  let scored: { userId: string; points: number; matches: number }[];
  const metric = opts.metric === 'rating' && opts.gameId !== 'all' && getGame(opts.gameId)?.capabilities.ranked ? 'rating' : 'points';
  if (metric === 'rating') {
    const rows = await prisma.skillRating.findMany({
      where: {
        gameId: opts.gameId,
        matches: { gte: config.rating.provisionalMatches },
        user: { ageBand: { in: bands as never } },
        ...(ids ? { userId: { in: ids } } : {}),
      },
    });
    scored = rows.map((r) => ({ userId: r.userId, points: displayRating(r), matches: r.matches }));
  } else {
    const since = periodStart(opts.period, now);
    const games = opts.gameId === 'all' ? LEADERBOARD_GAMES : [opts.gameId];
    // Global boards count public matches only (private rooms are easy to farm);
    // the friends board also counts private rooms played together.
    const modes = opts.scope === 'friends' ? ['casual', 'ranked', 'private'] : ['casual', 'ranked'];
    scored = await prisma.$queryRaw<{ userId: string; points: number; matches: number }[]>`
      SELECT "userId", SUM(p)::int AS points, COUNT(*)::int AS matches FROM (
        SELECT mp."userId", ROUND(100 * LEAST(1, GREATEST(0, COALESCE(mp.performance, 0)))) AS p,
               ROW_NUMBER() OVER (PARTITION BY mp."userId", m."gameId" ORDER BY mp.performance DESC NULLS LAST) AS rn
        FROM "MatchPlayer" mp
        JOIN "Match" m ON m.id = mp."matchId"
        JOIN "User" u ON u.id = mp."userId"
        WHERE m.state = 'completed' AND mp."leftEarly" = false
          AND m."gameId" IN (${Prisma.join(games)})
          AND m.mode IN (${Prisma.join(modes)})
          AND u."ageBand"::text IN (${Prisma.join(bands)})
          AND u.status = 'active'
          ${since ? Prisma.sql`AND m."endedAt" >= ${new Date(since)}` : Prisma.empty}
          ${ids ? Prisma.sql`AND mp."userId" IN (${Prisma.join(ids)})` : Prisma.empty}
      ) t WHERE rn <= ${bestOf}
      GROUP BY "userId"`;
  }
  scored.sort((a, b) => b.points - a.points || b.matches - a.matches || a.userId.localeCompare(b.userId));
  const top = scored.slice(0, size);
  const mineIdx = scored.findIndex((s) => s.userId === userId);
  const wanted = [...new Set([...top.map((t) => t.userId), userId])];
  const users = await prisma.user.findMany({ where: { id: { in: wanted } }, select: { id: true, displayName: true, avatarId: true, loadout: true } });
  const byId = new Map(users.map((u) => [u.id, u]));
  const row = (s: { userId: string; points: number; matches: number }, rank: number): LeaderboardRow => {
    const u = byId.get(s.userId);
    return {
      rank,
      playerId: s.userId,
      displayName: u?.displayName ?? '—',
      avatarId: u?.avatarId ?? '',
      cosmetics: publicCosmetics(u?.loadout),
      points: s.points,
      matches: s.matches,
    };
  };
  return {
    gameId: opts.gameId,
    period: opts.period,
    scope: opts.scope,
    metric,
    rows: top.map((s, i) => row(s, i + 1)),
    you: mineIdx >= 0 ? row(scored[mineIdx]!, mineIdx + 1) : null,
    bestOf,
  };
}
