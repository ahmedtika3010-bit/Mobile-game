/**
 * Guess with Emoji (خمّن بالإيموجي).
 *
 * Every player sees the same emoji puzzle at the same moment. Public and
 * ranked matches use multiple choice; private rooms may switch to typed
 * answers, checked against the approved answer and its approved spelling
 * variants after Arabic normalization (never fuzzy guessing).
 *
 * The view deliberately matches the quiz view (same stage names, question,
 * reveal and final shapes) with a few extra fields, so clients can reuse the
 * quiz screens.
 */
import type { QuizFinal, QuizQuestionView, QuizRevealView } from './quiz';

export type EmojiCategory = 'movies' | 'football' | 'food' | 'places' | 'sayings' | 'games';
export const EMOJI_CATEGORIES: readonly EmojiCategory[] = ['movies', 'football', 'food', 'places', 'sayings', 'games'];

export type EmojiAnswerMode = 'choices' | 'typed';

/** Wrong typed guesses allowed per puzzle. */
export const EMOJI_MAX_GUESSES = 3;

export type EmojiAction =
  | { kind: 'answer'; questionIndex: number; choice: number; clientElapsedMs?: number }
  | { kind: 'guess'; questionIndex: number; text: string; clientElapsedMs?: number };

export interface EmojiQuestionView extends Omit<QuizQuestionView, 'category'> {
  category: EmojiCategory;
  emojis: string;
  mode: EmojiAnswerMode;
  /** Typed mode only, after half the time: the answer's shape, e.g. "•••• ••". */
  hint: string | null;
}

export interface EmojiRevealView extends QuizRevealView {
  /** The approved answer, as text (typed mode has no choices). */
  answer: string;
}

export interface EmojiView {
  stage: 'question' | 'reveal' | 'finished';
  question: EmojiQuestionView | null;
  /** Choice mode: your pick. Typed mode: 0 once you solved it. */
  yourChoice: number | null;
  /** Typed mode: your own wrong guesses on this puzzle (never anyone else's). */
  yourGuesses: string[];
  /** Choice mode: players who answered. Typed mode: players who solved it. */
  answeredCount: number;
  reveal: EmojiRevealView | null;
  scores: Record<string, number>;
  final: QuizFinal | null;
}

/**
 * Code points from Emoji 12.0 or later, which phones on Android 9 and older
 * draw as empty boxes. Puzzles must avoid them so everyone sees the same
 * picture. Not exhaustive for every symbol block, but it covers the ranges
 * where new emoji were added (colored shapes, Symbols and Pictographs
 * Extended-A, and the 12.0+ additions in the Supplemental block).
 */
const NEWER_EMOJI: [number, number][] = [
  [0x1f6d5, 0x1f6d7], [0x1f6fa, 0x1f6fc], [0x1f7e0, 0x1f7f0],
  [0x1f90c, 0x1f90f], [0x1f93f, 0x1f93f], [0x1f971, 0x1f972], [0x1f976, 0x1f978], [0x1f97b, 0x1f97b],
  [0x1f9a3, 0x1f9a4], [0x1f9a5, 0x1f9af], [0x1f9ba, 0x1f9bf], [0x1f9c3, 0x1f9cb], [0x1f9cd, 0x1f9cf],
  [0x1fa70, 0x1faff],
];

export function usesNewerEmoji(s: string): boolean {
  for (const ch of s) {
    const cp = ch.codePointAt(0)!;
    if (NEWER_EMOJI.some(([a, b]) => cp >= a && cp <= b)) return true;
  }
  return false;
}
