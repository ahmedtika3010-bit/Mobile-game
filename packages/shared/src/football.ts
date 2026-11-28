/**
 * Football Challenges (تحديات الكورة): shared types between server and client.
 *
 * Five question modes, all answered by picking one of four choices:
 * - player:   clues about a player appear one by one; answering early pays more.
 * - career:   a player's clubs (with years) appear one by one; same scoring.
 * - shared:   two clubs; who played for both?
 * - transfer: a dated transfer (from, to, season); who made it?
 * - history:  a dated football history question.
 *
 * Every item carries the date its facts are correct for (`asOf`), and the
 * question itself names seasons and years, so later transfers never turn an
 * old answer wrong.
 *
 * Football Duel is the same game for exactly two players, decided by
 * questions won (head to head) rather than total points.
 *
 * The view matches the quiz view (stage names, question, reveal and final
 * shapes) with extra fields, so clients reuse the quiz screens.
 */
import type { QuizFinal, QuizQuestionView, QuizRevealView } from './quiz';

export type FootballMode = 'player' | 'career' | 'shared' | 'transfer' | 'history';
export const FOOTBALL_MODES: readonly FootballMode[] = ['player', 'career', 'shared', 'transfer', 'history'];

/** Modes whose lines appear one at a time (earlier answers earn a bigger bonus). */
export const FOOTBALL_PROGRESSIVE: readonly FootballMode[] = ['player', 'career'];

export type FootballAction = { kind: 'answer'; questionIndex: number; choice: number; clientElapsedMs?: number };

export interface FootballLine {
  /** A clue, a club name, or (transfer) the club. */
  text: string;
  /** Career: the years at that club. Transfer: "from" / "to" marker. */
  sub: string | null;
}

export interface FootballCard {
  mode: FootballMode;
  /** Only the lines already revealed; the rest stay on the server. */
  lines: FootballLine[];
  totalLines: number;
  /** When the next line appears (server time), or null if all are shown. */
  nextLineAt: number | null;
  /** The season or year the question is about, e.g. "صيف 2019". */
  when: string | null;
  /** Transfer fee, when it is well documented. */
  detail: string | null;
  /** The facts are correct as of this date (YYYY-MM-DD). */
  asOf: string | null;
}

export interface FootballQuestionView extends Omit<QuizQuestionView, 'category'> {
  category: FootballMode;
  football: FootballCard;
}

export interface FootballRevealView extends QuizRevealView {
  answer: string;
  /** Duel: who won this question (null when nobody or both equally). */
  winner: string | null;
}

export interface FootballDuelView {
  /** Questions won by each of the two players. */
  wins: Record<string, number>;
}

export interface FootballView {
  stage: 'question' | 'reveal' | 'finished';
  question: FootballQuestionView | null;
  yourChoice: number | null;
  answeredCount: number;
  reveal: FootballRevealView | null;
  scores: Record<string, number>;
  duel: FootballDuelView | null;
  final: QuizFinal | null;
}
