/**
 * The contract every game implements. The room owns membership, timers,
 * reconnection and safety; a game module owns only its rules. Modules are
 * pure (time is passed in), which keeps them deterministic and testable.
 */
import type { MatchMode } from '@sahra/shared';

export interface ContentRow {
  id: string;
  category: string;
  difficulty: string;
  payload: unknown;
  acceptedAnswers: string[];
}

export interface ContentRequest {
  gameId: string;
  count: number;
  category: string | 'mixed';
  difficulty: string;
}

export type ActionResult = { ok: true } | { ok: false; code: string };

export interface GameResults {
  ranking: { playerId: string; score: number; place: number; correct?: number }[];
  /** 0..1 normalized performance per player, for cross-game summaries. */
  performance: Record<string, number>;
  /** Words players asked to add to the content (appeals); saved for human review. */
  suggestions?: { gameId: string; category: string; word: string; userId: string }[];
}

export interface GameCapabilities {
  minPlayers: number;
  maxPlayers: number;
  ranked: boolean;
  /** Must be true (after Safe Mode testing) before the game is offered to mixed-age rooms. */
  safeModeReady: boolean;
  spectators: 'none' | 'public_only';
  /** 'participation': no winners; small flat rewards for taking part. */
  rewards?: 'performance' | 'participation';
}

export interface GameModule<State, Config, View> {
  id: string;
  capabilities: GameCapabilities;
  /** Standardized config for ranked; defaults for casual/private. */
  defaultConfig(mode: MatchMode): Config;
  /** Validates a host's settings; ranked always uses the standardized config. */
  validateConfig(raw: unknown, mode: MatchMode): Config;
  expectedDurationSec(config: Config): number;
  contentRequest(config: Config): ContentRequest | null;
  setup(players: string[], config: Config, content: ContentRow[], rng: Rng, now: number): State;
  onAction(state: State, playerId: string, action: unknown, now: number): ActionResult;
  /** Advance time-based phases. `activePlayers` are players still connected. */
  tick(state: State, now: number, activePlayers: ReadonlySet<string>): void;
  nextWakeAt(state: State): number | null;
  viewFor(state: State, viewer: string, now: number): View;
  isFinished(state: State): boolean;
  results(state: State): GameResults;
  /**
   * Optional: what a practice bot does next. `key` identifies the decision
   * (e.g. the question index) so the room schedules each one only once.
   */
  botPlan?(state: State, botId: string, rng: Rng, skill: number): { key: string; at: number; action: unknown } | null;
}

/** Small deterministic PRNG (mulberry32) seeded from a string; seeds are stored per match. */
export class Rng {
  private s: number;
  constructor(seed: string) {
    let h = 1779033703 ^ seed.length;
    for (let i = 0; i < seed.length; i++) {
      h = Math.imul(h ^ seed.charCodeAt(i), 3432918353);
      h = (h << 13) | (h >>> 19);
    }
    this.s = h >>> 0;
  }
  next(): number {
    let t = (this.s += 0x6d2b79f5);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }
  int(maxExclusive: number): number {
    return Math.floor(this.next() * maxExclusive);
  }
  shuffle<T>(arr: T[]): T[] {
    const a = arr.slice();
    for (let i = a.length - 1; i > 0; i--) {
      const j = this.int(i + 1);
      [a[i], a[j]] = [a[j] as T, a[i] as T];
    }
    return a;
  }
}

/** Standard competition ranking: equal scores share a place (1,1,3). */
export function placesFromScores(scores: { playerId: string; score: number }[]) {
  const sorted = scores.slice().sort((a, b) => b.score - a.score);
  let lastScore = Number.NaN;
  let lastPlace = 0;
  return sorted.map((s, i) => {
    const place = s.score === lastScore ? lastPlace : i + 1;
    lastScore = s.score;
    lastPlace = place;
    return { ...s, place };
  });
}
