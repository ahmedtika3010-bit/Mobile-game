/** General Knowledge Quiz: shared types between server and client. */
export type QuizCategory = 'geography' | 'history' | 'science' | 'sports' | 'general' | 'entertainment';

export const QUIZ_CATEGORIES: readonly QuizCategory[] = [
  'geography', 'history', 'science', 'sports', 'general', 'entertainment',
];

export type QuizAction = { kind: 'answer'; questionIndex: number; choice: number };

export interface QuizQuestionView {
  index: number;
  total: number;
  category: QuizCategory;
  prompt: string;
  choices: string[];
  /** Question becomes visible to every player at this server time. */
  revealAt: number;
  /** Answers after this server time are rejected. */
  deadline: number;
}

export interface QuizRevealView {
  index: number;
  correctChoice: number;
  explanation: string | null;
  /** Points each player earned for this question. */
  points: Record<string, number>;
  /** What each player picked (sent only after the question closes). */
  picks: Record<string, number>;
}

export interface QuizView {
  stage: 'question' | 'reveal' | 'finished';
  question: QuizQuestionView | null;
  /** Your own answer for the current question, if any (others' stay hidden until reveal). */
  yourChoice: number | null;
  answeredCount: number;
  reveal: QuizRevealView | null;
  scores: Record<string, number>;
  final: QuizFinal | null;
}

export interface QuizFinal {
  ranking: { playerId: string; score: number; correct: number; place: number }[];
  ratingApplied: boolean;
}
