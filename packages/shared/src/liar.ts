/**
 * Who Is the Liar? (مين الكداب؟): shared types between server and client.
 *
 * Each round everyone gets the same question except one player (the liar),
 * who gets a similar but different one, without knowing it. Everyone picks an
 * answer from the same approved options. Then the main question and all
 * answers are shown, players discuss with approved reactions and vote
 * anonymously. Answers are chosen from approved options, so it is Safe Mode ready.
 */
export type LiarDifficulty = 'easy' | 'medium' | 'hard';
export const LIAR_DIFFICULTIES: readonly LiarDifficulty[] = ['easy', 'medium', 'hard'];

/** Content categories for question pairs (all rooms play a mix). */
export type LiarCategory = 'daily' | 'food' | 'fun' | 'tech' | 'places';
export const LIAR_CATEGORIES: readonly LiarCategory[] = ['daily', 'food', 'fun', 'tech', 'places'];

export type LiarStage = 'answer' | 'discuss' | 'vote' | 'roundEnd' | 'finished';

export type LiarAction =
  /** Pick an answer (index into options) for the current round. */
  | { kind: 'answer'; round: number; choice: number }
  /** Public "I suspect X" marker during discussion (null clears it). */
  | { kind: 'suspect'; target: string | null }
  /** Ready to vote: discussion ends early when every active player is ready. */
  | { kind: 'readyToVote' }
  /** Anonymous vote for one other player. */
  | { kind: 'vote'; target: string };

export interface LiarRoundResult {
  round: number;
  liar: string;
  mainQuestion: string;
  oddQuestion: string;
  /** Votes received per player (who voted for whom stays secret). */
  voteCounts: Record<string, number>;
  /** Single top-voted player, or null on a tie / no votes. */
  accused: string | null;
  caught: boolean;
  /** Points each player earned this round. */
  points: Record<string, number>;
}

export interface LiarFinal {
  rounds: LiarRoundResult[];
  ranking: { playerId: string; score: number; place: number }[];
}

export interface LiarView {
  stage: LiarStage;
  stageEndsAt: number;
  /** 1-based round number. */
  round: number;
  rounds: number;
  difficulty: LiarDifficulty;
  /** The question you were given this round (null outside the match). */
  yourQuestion: string | null;
  /** The main question, shown to everyone from the discussion on. */
  mainQuestion: string | null;
  options: string[];
  yourAnswer: number | null;
  answeredCount: number;
  /** Everyone's answers (null = no answer), from the discussion on. */
  answers: Record<string, number | null> | null;
  /** From the discussion on, whether you are this round's liar. */
  youAreLiar: boolean | null;
  suspicions: Record<string, string>;
  readyCount: number;
  youReady: boolean;
  yourVote: string | null;
  votedCount: number;
  /** Total points so far. */
  scores: Record<string, number>;
  /** The round that just ended (roundEnd and finished). */
  lastRound: LiarRoundResult | null;
  final: LiarFinal | null;
}
