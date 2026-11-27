/**
 * Draw and Guess (ارسم وخمّن): players take turns drawing a secret word while
 * everyone else types guesses.
 *
 * - Every player draws the same number of times; the order is shuffled from
 *   the match seed (teams alternate in team mode).
 * - The drawer picks one of three words. In the standard profile the three
 *   are one easy, one medium and one hard word, and harder words pay more.
 * - Drawing tools are restricted on purpose: a fixed palette, three brush
 *   sizes, undo and clear. There is no text tool and no image import.
 * - Guesses are private: wrong guesses are never shown to other players, so
 *   the guess box cannot be used as a chat. Others only see that someone got it.
 * - Any guesser can hide the drawing for themselves; when enough guessers
 *   hide it, the turn is stopped for everyone. Reports keep the strokes as
 *   evidence.
 *
 * Strokes are sent as an append-only list of operations over a separate
 * stream (only new operations are sent), not inside the per-player view.
 */
export type DrawStage = 'choose' | 'draw' | 'reveal' | 'finished';

export type DrawCategory = 'animals' | 'food' | 'objects' | 'places' | 'nature' | 'transport' | 'sports' | 'jobs';
export const DRAW_CATEGORIES: readonly DrawCategory[] = ['animals', 'food', 'objects', 'places', 'nature', 'transport', 'sports', 'jobs'];

/** The drawing is a square of DRAW_CANVAS x DRAW_CANVAS units. */
export const DRAW_CANVAS = 1000;
/** Fixed palette; the last color is white, which works as an eraser on the white canvas. */
export const DRAW_COLORS = ['#1E2230', '#E5484D', '#F76B15', '#FFC53D', '#30A46C', '#0090FF', '#8E4EC6', '#8D5B3A', '#FFFFFF'] as const;
/** Brush widths in canvas units. */
export const DRAW_WIDTHS = [7, 16, 36] as const;

export const DRAW_LIMITS = {
  /** Points (x, y pairs) in one operation. */
  pointsPerOp: 64,
  /** Operations in one action message. */
  opsPerAction: 16,
  /** All points drawn in one turn. */
  pointsPerTurn: 12_000,
  opsPerTurn: 2_500,
  guessLength: 40,
  guessesPerTurn: 30,
  /** Minimum time between two guesses from the same player. */
  guessGapMs: 600,
};

/**
 * One drawing operation. Points are flat [x0, y0, x1, y1, ...] integers in
 * 0..DRAW_CANVAS.
 */
export type DrawOp =
  /** Begin a stroke with a palette color and brush size. */
  | { t: 'b'; c: number; w: number; p: number[] }
  /** Add points to the current stroke. */
  | { t: 'p'; p: number[] }
  /** Undo the last stroke. */
  | { t: 'u' }
  /** Clear the canvas. */
  | { t: 'x' };

export type DrawAction =
  | { kind: 'choose'; turn: number; choice: number }
  | { kind: 'draw'; turn: number; ops: DrawOp[] }
  | { kind: 'guess'; turn: number; text: string; clientElapsedMs?: number }
  /** Hide this drawing for me (counts toward stopping the turn). */
  | { kind: 'hide'; turn: number };

export interface DrawTurnView {
  turn: number;
  total: number;
  drawer: string;
  /** The drawer's team in team mode (0 or 1), else null. */
  drawerTeam: number | null;
  chooseEndsAt: number;
  startedAt: number;
  deadline: number;
  /** Drawer only, while choosing. */
  choices: { word: string; difficulty: string; points: number }[] | null;
  /** The word: drawer while drawing; everyone at the reveal. */
  word: string | null;
  category: string | null;
  difficulty: string | null;
  /**
   * The word's shape for guessers: one entry per character, '' for a hidden
   * letter, ' ' for a space, or the letter once it is revealed as a hint.
   */
  shape: string[] | null;
  /** Players who guessed it, in order. */
  guessed: string[];
  youGuessed: boolean;
  /** Your own wrong guesses this turn (never sent to anyone else). */
  yourGuesses: string[];
  /** Your last wrong guess was one letter away. */
  close: boolean;
  youHid: boolean;
}

export interface DrawReveal {
  word: string;
  /** Points per player this turn (the drawer included). */
  points: Record<string, number>;
  guessed: string[];
  /** 'stopped' = hidden by enough guessers; 'drawer_left' = the drawer disconnected. */
  ended: 'all_guessed' | 'time' | 'stopped' | 'drawer_left' | 'skipped';
}

export interface DrawView {
  stage: DrawStage;
  turn: DrawTurnView | null;
  /** The current canvas stream: its key and how many operations it has. */
  canvas: { key: string; ops: number } | null;
  reveal: DrawReveal | null;
  scores: Record<string, number>;
  /** Team mode: each player's team (0 or 1) and the two team totals. */
  teams: { of: Record<string, number>; scores: [number, number] } | null;
  final: {
    ranking: { playerId: string; score: number; place: number; correct: number }[];
    teamScores: [number, number] | null;
  } | null;
}

/** Stream payload the room sends next to the view: operations from `from` on. */
export interface StreamChunk {
  key: string;
  from: number;
  items: unknown[];
}
