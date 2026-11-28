/**
 * Memory Challenges (تحديات الذاكرة): three modes, played by everyone at once.
 *
 * - `cards` (بطاقات الذاكرة): a grid of emoji cards is shown, then turned face
 *   down; find where each target emoji was.
 * - `sequence` (السلسلة): colored tiles light up one after another; repeat the
 *   order.
 * - `spot` (إيه اللي اتغير؟): a grid is shown, hidden, then shown again with
 *   one card changed; tap the changed card.
 *
 * Fairness: every round is generated from the match seed, sent before a
 * common `showAt` server time and hidden at the same `hideAt` for everyone, so
 * all players get exactly the same exposure regardless of phone or network.
 * Correctness gives most of the points; the speed bonus is small and counted
 * in whole seconds.
 */
export type MemoryMode = 'cards' | 'sequence' | 'spot';
export const MEMORY_MODES: readonly MemoryMode[] = ['cards', 'sequence', 'spot'];

export type MemoryStage = 'show' | 'answer' | 'reveal' | 'finished';

/** Number of color pads in the sequence mode (the client draws them). */
export const MEMORY_SEQUENCE_PADS = 4;

export type MemoryAction =
  /** cards: the cell for the next target; spot: the changed cell. */
  | { kind: 'pick'; round: number; cell: number; clientElapsedMs?: number }
  /** sequence: the whole order you remember (pad indices). */
  | { kind: 'sequence'; round: number; items: number[]; clientElapsedMs?: number };

export interface MemoryRoundView {
  round: number;
  total: number;
  mode: MemoryMode;
  /** Memorize between these server times; the content is hidden before and after. */
  showAt: number;
  hideAt: number;
  /** Answers open at this server time and close at the deadline. */
  answerAt: number;
  deadline: number;
  columns: number;
  cells: number;
  /** cards and spot: the grid to memorize (only during the show stage and the reveal). */
  grid: string[] | null;
  /** sequence: pad indices to memorize (only during the show stage and the reveal). */
  sequence: number[] | null;
  /** sequence: time each pad stays lit, from showAt. */
  stepMs: number;
  /** sequence: number of items to repeat (known while answering). */
  length: number;
  /** cards: the emojis to find, in order (answer stage and reveal). */
  targets: string[] | null;
  /** spot: the grid with one card changed (answer stage and reveal). */
  changedGrid: string[] | null;
}

export interface MemoryReveal {
  /** cards: cell of each target; spot: [changed cell]; sequence: the order. */
  answer: number[];
  /** Correct parts per player (targets found, sequence items in order, or 0/1). */
  correct: Record<string, number>;
  /** Out of how many parts. */
  parts: number;
  points: Record<string, number>;
  /** What each player answered (picks or sequence), shown after the round. */
  answers: Record<string, number[]>;
}

export interface MemoryView {
  stage: MemoryStage;
  round: MemoryRoundView | null;
  /** Your answers so far this round (cards: one cell per target found so far). */
  yourAnswer: number[];
  youDone: boolean;
  doneCount: number;
  reveal: MemoryReveal | null;
  scores: Record<string, number>;
  final: { ranking: { playerId: string; score: number; place: number; correct: number }[] } | null;
}
