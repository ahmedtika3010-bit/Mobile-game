/**
 * Spy (الجاسوس): shared types between server and client.
 *
 * Everyone except the spies sees a secret word; spies only see its category.
 * Players take turns asking each other approved questions and answering on an
 * approved scale, discuss with approved reactions, then vote anonymously.
 * All communication uses approved content, so the game works in Safe Mode.
 */
export type SpyCategory = 'places' | 'food' | 'jobs' | 'animals' | 'objects' | 'sports';

export const SPY_CATEGORIES: readonly SpyCategory[] = ['places', 'food', 'jobs', 'animals', 'objects', 'sports'];

/** Approved answer scale (index = answer id). Clients show localized text by index. */
export const SPY_ANSWERS = ['always', 'often', 'sometimes', 'rarely', 'never'] as const;
export type SpyAnswerId = (typeof SPY_ANSWERS)[number];

export type SpyStage = 'roles' | 'ask' | 'answer' | 'discuss' | 'vote' | 'guess' | 'finished';

export type SpyAction =
  /** Asker picks one of the offered questions and a target. */
  | { kind: 'ask'; turn: number; question: number; target: string }
  /** Target answers on the approved scale (index into SPY_ANSWERS). */
  | { kind: 'answer'; turn: number; answer: number }
  /** Public "I suspect X" marker during discussion (null clears it). */
  | { kind: 'suspect'; target: string | null }
  /** Ready to vote: discussion ends early when every active player is ready. */
  | { kind: 'readyToVote' }
  /** Anonymous vote for one other player. */
  | { kind: 'vote'; target: string }
  /** A spy names the word: any time before the vote, or when caught. */
  | { kind: 'guess'; choice: number };

export interface SpyTurnView {
  index: number;
  total: number;
  asker: string;
  target: string | null;
  /** Only the asker receives the question options. */
  questionOptions: string[] | null;
  question: string | null;
  answer: number | null;
}

export interface SpyHistoryEntry {
  asker: string;
  target: string;
  question: string;
  /** Index into SPY_ANSWERS, or null if the target did not answer in time. */
  answer: number | null;
}

export type SpyWinner = 'spies' | 'citizens';
export type SpyEndReason =
  /** A spy named the word before the vote. */
  | 'spy_guessed_early'
  /** A spy named a wrong word before the vote. */
  | 'spy_guessed_wrong'
  /** The vote picked a citizen, or there was a tie. */
  | 'spy_survived'
  /** The vote caught a spy, who then named the word. */
  | 'caught_but_guessed'
  /** The vote caught a spy, who could not name the word. */
  | 'caught';

export interface SpyFinal {
  winner: SpyWinner;
  reason: SpyEndReason;
  spies: string[];
  word: string;
  /** Votes received per player (who voted for whom stays secret). */
  voteCounts: Record<string, number>;
  accused: string | null;
  guessedWord: string | null;
  ranking: { playerId: string; score: number; place: number }[];
}

export interface SpyView {
  stage: SpyStage;
  stageEndsAt: number;
  category: SpyCategory;
  /** Your role; null for anyone outside the match. */
  role: 'spy' | 'citizen' | null;
  /** The secret word, only for citizens (and for everyone once finished). */
  word: string | null;
  spyCount: number;
  turn: SpyTurnView | null;
  history: SpyHistoryEntry[];
  /** Public suspicion markers: who each player currently suspects. */
  suspicions: Record<string, string>;
  readyCount: number;
  youReady: boolean;
  yourVote: string | null;
  votedCount: number;
  /** Word options, only sent to a spy who may guess now. */
  guessOptions: string[] | null;
  /** During the `guess` stage: the caught spy. */
  guesser: string | null;
  final: SpyFinal | null;
}
