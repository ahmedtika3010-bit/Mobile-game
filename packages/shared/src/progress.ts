/**
 * Cosmetics, missions, achievements and leaderboards: the shapes the server
 * sends to the app. Definitions (prices, targets, rewards) live on the server
 * so the admin dashboard can change them without an app update.
 */
import type { GameId } from './protocol';

export type CosmeticKind = 'frame' | 'title' | 'theme' | 'effect';
export type Rarity = 'common' | 'rare' | 'epic' | 'legendary';

/**
 * How an item looks, described as data so new items need no app update.
 * frame: ring around the avatar. title: a short line under the name.
 * theme: profile and home backdrop. effect: the victory celebration.
 */
export interface CosmeticLook {
  /** Hex colors (#RRGGBB): ring / text / backdrop gradient. */
  colors?: string[];
  /** frame: solid | gradient | glow | double. effect: confetti | rain | burst. */
  style?: string;
  /** title: the Arabic text shown. */
  text?: string;
  /** theme / effect: emoji used as decoration or particles. */
  emojis?: string[];
}

/** One way to get an item without paying (every paid item has one). */
export type UnlockPath = { kind: 'level'; level: number } | { kind: 'achievement'; achievementId: string } | { kind: 'default' };

export interface Price {
  currency: 'coins' | 'gems';
  amount: number;
}

export interface CosmeticItem {
  id: string;
  kind: CosmeticKind;
  name: string;
  rarity: Rarity;
  look: CosmeticLook;
  /** null: cannot be bought (earned through play only). */
  price: Price | null;
  unlock: UnlockPath;
  /** A returning event collection this item belongs to, if any. */
  event?: string;
}

export type Loadout = Partial<Record<CosmeticKind, string>>;

/** What other players see: the equipped frame and title, already resolved. */
export interface PublicCosmetics {
  frame?: CosmeticLook;
  title?: CosmeticLook;
  effect?: CosmeticLook;
}

export interface Reward {
  coins?: number;
  gems?: number;
  xp?: number;
  /** A cosmetic item id granted with the reward. */
  item?: string;
}

export interface ShopItemView extends CosmeticItem {
  owned: boolean;
  equipped: boolean;
  /** Owned because the unlock path is met (level reached, achievement claimed). */
  unlockedByPlay: boolean;
}

export interface ShopView {
  items: ShopItemView[];
  loadout: Loadout;
  coins: number;
  gems: number;
  level: number;
  /** Gem packs exist only once store billing is connected. */
  gemPurchasesAvailable: boolean;
}

export type MissionPeriod = 'daily' | 'weekly';

export interface MissionView {
  id: string;
  period: MissionPeriod;
  /** Template id, e.g. play_any, play_distinct, win, play_game. */
  kind: string;
  /** Set for play_game missions. */
  gameId?: GameId;
  target: number;
  progress: number;
  reward: Reward;
  claimed: boolean;
}

export interface LoginTrackView {
  /** Step of the 7-day track that today's claim gives (1..7); missing a day never resets it. */
  step: number;
  claimedToday: boolean;
  rewards: Reward[];
  /** A small one-off bonus for players returning after a long break. */
  welcomeBack: Reward | null;
}

export interface MissionsView {
  daily: MissionView[];
  weekly: MissionView[];
  dailyEndsAt: number;
  weeklyEndsAt: number;
  login: LoginTrackView;
}

export interface AchievementView {
  id: string;
  /** null for account-wide achievements. */
  gameId: GameId | null;
  kind: string;
  target: number;
  progress: number;
  reward: Reward;
  claimed: boolean;
}

export type LeaderboardPeriod = 'week' | 'month' | 'all';
export type LeaderboardScope = 'global' | 'friends';

export interface LeaderboardRow {
  rank: number;
  playerId: string;
  displayName: string;
  avatarId: string;
  cosmetics?: PublicCosmetics;
  points: number;
  matches: number;
}

export interface LeaderboardView {
  gameId: GameId | 'all';
  period: LeaderboardPeriod;
  scope: LeaderboardScope;
  /** points = best match results in the period; rating = official skill rating (ranked games). */
  metric: 'points' | 'rating';
  rows: LeaderboardRow[];
  you: LeaderboardRow | null;
  /** How many of your best matches count per game in this period. */
  bestOf: number;
}
