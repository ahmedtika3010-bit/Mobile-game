/**
 * Who Among Us? (مين فينا؟): a casual, anonymous group-voting game.
 *
 * Each question ("Who among us would ...?") everyone votes for another
 * player or skips. Nobody wins or loses and there is no skill rating; the
 * end screen is a fun group summary. Votes are never attributed to voters,
 * and results with too few votes are hidden so individual votes can't be
 * worked out.
 */
export type WhoCategory = 'funny' | 'friends' | 'everyday' | 'personality';
export const WHO_CATEGORIES: readonly WhoCategory[] = ['funny', 'friends', 'everyday', 'personality'];

export type WhoStage = 'vote' | 'reveal' | 'finished';

export type WhoAction =
  /** Vote for another player on the current question (1-based index). */
  | { kind: 'vote'; question: number; target: string }
  /** Skip the current question; no penalty. */
  | { kind: 'skip'; question: number };

/**
 * - `pick`: the most-voted player(s) (at most two on a tie).
 * - `too_few`: not enough votes to show anything without exposing voters.
 * - `spread`: votes too spread out, or the top pick has been shown too often.
 */
export type WhoRevealKind = 'pick' | 'too_few' | 'spread';

export interface WhoReveal {
  kind: WhoRevealKind;
  picks: string[];
  /** Number of votes (skips excluded). */
  votes: number;
  /** Votes per shown pick, only when enough people voted. */
  counts: Record<string, number> | null;
}

export type WhoTitle = 'funny' | 'friends' | 'everyday' | 'personality' | 'mystery';

export interface WhoFinal {
  questions: number;
  votesCast: number;
  skips: number;
  /** A friendly title per player, based on the kind of questions they were picked for. */
  titles: Record<string, WhoTitle>;
  /** Questions whose result was shown, with who was picked. */
  highlights: { text: string; picks: string[] }[];
}

export interface WhoView {
  stage: WhoStage;
  stageEndsAt: number;
  /** 1-based question number. */
  index: number;
  total: number;
  question: { text: string; category: WhoCategory } | null;
  /** Your choice on the current question: a player id, 'skip', or null. */
  yourChoice: string | null;
  answeredCount: number;
  reveal: WhoReveal | null;
  final: WhoFinal | null;
}
