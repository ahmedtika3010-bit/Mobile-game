/**
 * Default definitions for cosmetics, missions, achievements, the daily login
 * track and leaderboards. Everything here is data (prices, targets, rewards,
 * colors), so the admin dashboard can later override it without code changes.
 * All numbers are starting values that need playtesting.
 */
import type { CosmeticItem, GameId, Reward } from '@sahra/shared';

const SUN = '#FFC83D';
const ORANGE = '#FF8A3D';
const CORAL = '#FF5A7A';
const PINK = '#FF6FD8';
const GRAPE = '#8E5BFF';
const SKY = '#3DA5FF';
const MINT = '#1FD1A5';
const GOLD = '#FFD966';
const WHITE = '#FFFFFF';

export const ALL_GAMES: GameId[] = ['quiz', 'spy', 'liar', 'who', 'emoji', 'stop', 'memory', 'draw', 'football', 'acting'];

/* -------------------------------- cosmetics -------------------------------- */

export const COSMETICS: CosmeticItem[] = [
  // Frames: the ring around your avatar in rooms, results and leaderboards.
  { id: 'frame_basic', kind: 'frame', name: 'إطار بسيط', rarity: 'common', look: { colors: [WHITE], style: 'solid' }, price: null, unlock: { kind: 'default' } },
  { id: 'frame_mint', kind: 'frame', name: 'نعناع', rarity: 'common', look: { colors: [MINT], style: 'solid' }, price: { currency: 'coins', amount: 300 }, unlock: { kind: 'level', level: 3 } },
  { id: 'frame_sun', kind: 'frame', name: 'شمس', rarity: 'common', look: { colors: [SUN], style: 'solid' }, price: { currency: 'coins', amount: 400 }, unlock: { kind: 'level', level: 5 } },
  { id: 'frame_coral', kind: 'frame', name: 'مرجان', rarity: 'common', look: { colors: [CORAL, PINK], style: 'gradient' }, price: { currency: 'coins', amount: 500 }, unlock: { kind: 'level', level: 6 } },
  { id: 'frame_ocean', kind: 'frame', name: 'بحر', rarity: 'rare', look: { colors: [SKY, MINT], style: 'gradient' }, price: { currency: 'coins', amount: 800 }, unlock: { kind: 'level', level: 8 } },
  { id: 'frame_sunset', kind: 'frame', name: 'غروب', rarity: 'rare', look: { colors: [ORANGE, PINK, GRAPE], style: 'gradient' }, price: { currency: 'coins', amount: 1000 }, unlock: { kind: 'level', level: 10 } },
  { id: 'frame_neon', kind: 'frame', name: 'نيون', rarity: 'epic', look: { colors: [PINK, SKY], style: 'glow' }, price: { currency: 'coins', amount: 1600 }, unlock: { kind: 'level', level: 14 } },
  { id: 'frame_night', kind: 'frame', name: 'ليل السهرة', rarity: 'epic', look: { colors: [GRAPE, SKY], style: 'double' }, price: { currency: 'gems', amount: 60 }, unlock: { kind: 'level', level: 16 } },
  { id: 'frame_gold', kind: 'frame', name: 'دهب', rarity: 'legendary', look: { colors: [GOLD, ORANGE], style: 'glow' }, price: { currency: 'gems', amount: 120 }, unlock: { kind: 'level', level: 25 } },
  { id: 'frame_champion', kind: 'frame', name: 'البطل', rarity: 'epic', look: { colors: [SUN, CORAL], style: 'double' }, price: null, unlock: { kind: 'achievement', achievementId: 'wins_25' } },
  { id: 'frame_explorer', kind: 'frame', name: 'الرحّال', rarity: 'epic', look: { colors: [MINT, SUN], style: 'double' }, price: null, unlock: { kind: 'achievement', achievementId: 'explorer_10' } },

  // Titles: a short line under your name.
  { id: 'title_newcomer', kind: 'title', name: 'لسه جديد', rarity: 'common', look: { text: 'لسه جديد', colors: [WHITE] }, price: null, unlock: { kind: 'default' } },
  { id: 'title_quick', kind: 'title', name: 'سريع البديهة', rarity: 'common', look: { text: 'سريع البديهة', colors: [SKY] }, price: { currency: 'coins', amount: 350 }, unlock: { kind: 'level', level: 4 } },
  { id: 'title_funny', kind: 'title', name: 'ابن نكتة', rarity: 'common', look: { text: 'ابن نكتة', colors: [SUN] }, price: { currency: 'coins', amount: 350 }, unlock: { kind: 'level', level: 4 } },
  { id: 'title_mood', kind: 'title', name: 'صاحب مزاج', rarity: 'rare', look: { text: 'صاحب مزاج', colors: [MINT] }, price: { currency: 'coins', amount: 600 }, unlock: { kind: 'level', level: 7 } },
  { id: 'title_night_owl', kind: 'title', name: 'بومة السهرة', rarity: 'rare', look: { text: 'بومة السهرة 🦉', colors: [GRAPE] }, price: { currency: 'coins', amount: 900 }, unlock: { kind: 'level', level: 11 } },
  { id: 'title_legend', kind: 'title', name: 'أسطورة', rarity: 'legendary', look: { text: 'أسطورة ✨', colors: [GOLD] }, price: { currency: 'gems', amount: 100 }, unlock: { kind: 'level', level: 30 } },
  { id: 'title_veteran', kind: 'title', name: 'متعوّد على السهر', rarity: 'epic', look: { text: 'متعوّد على السهر', colors: [ORANGE] }, price: null, unlock: { kind: 'achievement', achievementId: 'matches_200' } },
  { id: 'title_social', kind: 'title', name: 'اجتماعي', rarity: 'rare', look: { text: 'اجتماعي 🤝', colors: [PINK] }, price: null, unlock: { kind: 'achievement', achievementId: 'friends_5' } },
  { id: 'title_quiz', kind: 'title', name: 'العقل المدبّر', rarity: 'epic', look: { text: 'العقل المدبّر 🧠', colors: [SKY] }, price: null, unlock: { kind: 'achievement', achievementId: 'quiz_wins_10' } },
  { id: 'title_spy', kind: 'title', name: 'الجاسوس الصامت', rarity: 'epic', look: { text: 'الجاسوس الصامت 🕵️', colors: [GRAPE] }, price: null, unlock: { kind: 'achievement', achievementId: 'spy_wins_10' } },
  { id: 'title_liar', kind: 'title', name: 'كاشف الكدب', rarity: 'epic', look: { text: 'كاشف الكدب 🤥', colors: [CORAL] }, price: null, unlock: { kind: 'achievement', achievementId: 'liar_wins_10' } },
  { id: 'title_who', kind: 'title', name: 'روح الأوضة', rarity: 'epic', look: { text: 'روح الأوضة 👀', colors: [PINK] }, price: null, unlock: { kind: 'achievement', achievementId: 'who_matches_25' } },
  { id: 'title_emoji', kind: 'title', name: 'ملك الإيموجي', rarity: 'epic', look: { text: 'ملك الإيموجي 😎', colors: [SUN] }, price: null, unlock: { kind: 'achievement', achievementId: 'emoji_wins_10' } },
  { id: 'title_stop', kind: 'title', name: 'أسرع إيد', rarity: 'epic', look: { text: 'أسرع إيد 🚌', colors: [ORANGE] }, price: null, unlock: { kind: 'achievement', achievementId: 'stop_wins_10' } },
  { id: 'title_memory', kind: 'title', name: 'ذاكرة حديد', rarity: 'epic', look: { text: 'ذاكرة حديد 🧩', colors: [MINT] }, price: null, unlock: { kind: 'achievement', achievementId: 'memory_wins_10' } },
  { id: 'title_draw', kind: 'title', name: 'فنان الأوضة', rarity: 'epic', look: { text: 'فنان الأوضة 🎨', colors: [CORAL] }, price: null, unlock: { kind: 'achievement', achievementId: 'draw_wins_10' } },
  { id: 'title_football', kind: 'title', name: 'ملك الكورة', rarity: 'epic', look: { text: 'ملك الكورة ⚽', colors: [MINT] }, price: null, unlock: { kind: 'achievement', achievementId: 'football_wins_10' } },
  { id: 'title_acting', kind: 'title', name: 'نجم التمثيل', rarity: 'epic', look: { text: 'نجم التمثيل 🎭', colors: [GRAPE] }, price: null, unlock: { kind: 'achievement', achievementId: 'acting_wins_10' } },

  // Themes: the backdrop of your home screen and profile.
  { id: 'theme_night', kind: 'theme', name: 'سهرة', rarity: 'common', look: { colors: ['#3A1A7A', '#1C1150'], emojis: ['🌙'] }, price: null, unlock: { kind: 'default' } },
  { id: 'theme_sunset', kind: 'theme', name: 'غروب النيل', rarity: 'rare', look: { colors: ['#FF8A3D', '#5B2A8C'], emojis: ['🌅'] }, price: { currency: 'coins', amount: 900 }, unlock: { kind: 'level', level: 9 } },
  { id: 'theme_sea', kind: 'theme', name: 'بحر إسكندرية', rarity: 'rare', look: { colors: ['#3DA5FF', '#1C1150'], emojis: ['🌊'] }, price: { currency: 'coins', amount: 900 }, unlock: { kind: 'level', level: 12 } },
  { id: 'theme_desert', kind: 'theme', name: 'صحرا', rarity: 'epic', look: { colors: ['#FFC83D', '#8C4A2A'], emojis: ['🐪'] }, price: { currency: 'coins', amount: 1500 }, unlock: { kind: 'level', level: 18 } },
  { id: 'theme_lanterns', kind: 'theme', name: 'فوانيس', rarity: 'epic', look: { colors: ['#8E5BFF', '#1A1033'], emojis: ['🏮', '✨'] }, price: { currency: 'gems', amount: 80 }, unlock: { kind: 'level', level: 22 }, event: 'ramadan' },

  // Victory effects: what falls on screen when you win.
  { id: 'effect_confetti', kind: 'effect', name: 'قصاقيص', rarity: 'common', look: { style: 'confetti' }, price: null, unlock: { kind: 'default' } },
  { id: 'effect_stars', kind: 'effect', name: 'نجوم', rarity: 'rare', look: { style: 'rain', emojis: ['⭐', '✨'] }, price: { currency: 'coins', amount: 700 }, unlock: { kind: 'level', level: 7 } },
  { id: 'effect_hearts', kind: 'effect', name: 'قلوب', rarity: 'rare', look: { style: 'rain', emojis: ['💜', '💖', '💛'] }, price: { currency: 'coins', amount: 700 }, unlock: { kind: 'level', level: 9 } },
  { id: 'effect_fireworks', kind: 'effect', name: 'صواريخ', rarity: 'epic', look: { style: 'burst', emojis: ['🎆', '🎇', '✨'] }, price: { currency: 'coins', amount: 1400 }, unlock: { kind: 'level', level: 15 } },
  { id: 'effect_coins', kind: 'effect', name: 'مطر كوينز', rarity: 'epic', look: { style: 'rain', emojis: ['🪙'] }, price: { currency: 'gems', amount: 50 }, unlock: { kind: 'level', level: 20 } },
  { id: 'effect_crowns', kind: 'effect', name: 'تيجان', rarity: 'legendary', look: { style: 'burst', emojis: ['👑', '✨'] }, price: null, unlock: { kind: 'achievement', achievementId: 'wins_100' } },
];

export const DEFAULT_LOADOUT = { frame: 'frame_basic', title: 'title_newcomer', theme: 'theme_night', effect: 'effect_confetti' } as const;

/* -------------------------------- missions -------------------------------- */

/**
 * Mission templates. Each day / week a player gets a few, picked from these
 * by a seed (same for the whole day, different per player). Progress is read
 * from saved matches, so it can never be counted twice.
 * play_any: finished matches. play_distinct: different games. win: first place.
 * play_game: matches of one game. perf: summed performance points (0..100 per match).
 * private: matches in private rooms. night: matches inside a Game Night.
 */
export interface MissionTemplate {
  kind: 'play_any' | 'play_distinct' | 'win' | 'play_game' | 'perf' | 'private' | 'night';
  target: number;
  reward: Reward;
}

export const DAILY_MISSIONS: MissionTemplate[] = [
  { kind: 'play_any', target: 3, reward: { coins: 60, xp: 30 } },
  { kind: 'play_distinct', target: 2, reward: { coins: 80, xp: 30 } },
  { kind: 'win', target: 1, reward: { coins: 70, xp: 30 } },
  { kind: 'play_game', target: 1, reward: { coins: 50, xp: 20 } },
  { kind: 'perf', target: 150, reward: { coins: 70, xp: 30 } },
  { kind: 'private', target: 1, reward: { coins: 40, xp: 20 } },
];

export const WEEKLY_MISSIONS: MissionTemplate[] = [
  { kind: 'play_any', target: 15, reward: { coins: 250, xp: 150, gems: 5 } },
  { kind: 'play_distinct', target: 5, reward: { coins: 300, xp: 150, gems: 5 } },
  { kind: 'win', target: 5, reward: { coins: 300, xp: 150, gems: 5 } },
  { kind: 'perf', target: 900, reward: { coins: 250, xp: 150, gems: 5 } },
  { kind: 'night', target: 3, reward: { coins: 250, xp: 150, gems: 5 } },
];

/* ------------------------------- achievements ------------------------------ */

/**
 * matches / wins: finished matches and first places (any game, or one game).
 * distinct: different games played. level: account level. friends: accepted friends.
 * nights: matches played inside a Game Night.
 */
export interface AchievementDef {
  id: string;
  kind: 'matches' | 'wins' | 'distinct' | 'level' | 'friends' | 'nights';
  gameId: GameId | null;
  target: number;
  reward: Reward;
}

const perGame: AchievementDef[] = ALL_GAMES.flatMap((g): AchievementDef[] => [
  { id: `${g}_matches_25`, kind: 'matches', gameId: g, target: 25, reward: { coins: 150, xp: 100, ...(g === 'who' ? { item: 'title_who' } : {}) } },
  ...(g === 'who' ? [] : [{ id: `${g}_wins_10`, kind: 'wins' as const, gameId: g, target: 10, reward: { coins: 200, gems: 5, item: `title_${g}` } }]),
]);

export const ACHIEVEMENTS: AchievementDef[] = [
  { id: 'matches_1', kind: 'matches', gameId: null, target: 1, reward: { coins: 50, xp: 50 } },
  { id: 'matches_10', kind: 'matches', gameId: null, target: 10, reward: { coins: 100, xp: 100 } },
  { id: 'matches_50', kind: 'matches', gameId: null, target: 50, reward: { coins: 300, gems: 5 } },
  { id: 'matches_200', kind: 'matches', gameId: null, target: 200, reward: { coins: 800, gems: 15, item: 'title_veteran' } },
  { id: 'wins_1', kind: 'wins', gameId: null, target: 1, reward: { coins: 50, xp: 50 } },
  { id: 'wins_25', kind: 'wins', gameId: null, target: 25, reward: { coins: 400, gems: 10, item: 'frame_champion' } },
  { id: 'wins_100', kind: 'wins', gameId: null, target: 100, reward: { coins: 1000, gems: 25, item: 'effect_crowns' } },
  { id: 'explorer_5', kind: 'distinct', gameId: null, target: 5, reward: { coins: 200, gems: 5 } },
  { id: 'explorer_10', kind: 'distinct', gameId: null, target: 10, reward: { coins: 500, gems: 10, item: 'frame_explorer' } },
  { id: 'level_5', kind: 'level', gameId: null, target: 5, reward: { gems: 10 } },
  { id: 'level_10', kind: 'level', gameId: null, target: 10, reward: { gems: 20 } },
  { id: 'level_20', kind: 'level', gameId: null, target: 20, reward: { gems: 40 } },
  { id: 'friends_1', kind: 'friends', gameId: null, target: 1, reward: { coins: 100 } },
  { id: 'friends_5', kind: 'friends', gameId: null, target: 5, reward: { coins: 200, item: 'title_social' } },
  { id: 'nights_10', kind: 'nights', gameId: null, target: 10, reward: { coins: 300, gems: 5 } },
  ...perGame,
];

/* --------------------------- daily login and more --------------------------- */

export const progressConfig = {
  /** The game day starts at midnight in this offset from UTC (Cairo = +120). */
  dayOffsetMinutes: 120,
  dailyMissionCount: 3,
  weeklyMissionCount: 3,
  /**
   * A 7-step track. Each day you open the app you claim the next step; a
   * missed day just waits (nothing resets), and after step 7 it starts again.
   */
  loginTrack: [
    { coins: 30 },
    { coins: 40 },
    { coins: 50, xp: 30 },
    { coins: 60 },
    { coins: 70, xp: 50 },
    { coins: 80 },
    { coins: 100, gems: 5 },
  ] as Reward[],
  /** Small, capped bonus for coming back after a break. */
  welcomeBack: { afterDays: 7, onceEveryDays: 30, reward: { coins: 150, xp: 50 } as Reward },
  leaderboard: {
    /** Only your best N matches of each game count, so short games are not favored. */
    bestOf: { week: 10, month: 30, all: 100 },
    size: 50,
  },
  /** Real-money Gems need store billing (Google Play / App Store); off until connected. */
  gemPurchasesAvailable: false,
};

export const cosmeticById = (id: string) => COSMETICS.find((c) => c.id === id);
export const achievementById = (id: string) => ACHIEVEMENTS.find((a) => a.id === id);
