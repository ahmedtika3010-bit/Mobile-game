/**
 * Stop / Atobees Complete (أتوبيس كومبليت): the category-and-letter game.
 *
 * Each round has one Arabic letter. Everyone fills one word per category
 * (boy's name, girl's name, animal, plant, object, country) starting with
 * that letter, and can edit until the shared timer ends.
 *
 * Answers are checked against the approved dictionary after Arabic
 * normalization (hamza forms, taa marbuta, alef maqsura, diacritics and a
 * leading "ال" do not matter). Valid and unique: 10 points; valid but someone
 * else wrote the same word: 5; wrong letter, empty or not in the dictionary:
 * 0. A word missing from the dictionary is never shown to other players
 * (it could be anything); its author can appeal, which sends it to human
 * review so it can be added for future matches.
 */
export type StopCategory = 'boy' | 'girl' | 'animal' | 'plant' | 'object' | 'country';
export const STOP_CATEGORIES: readonly StopCategory[] = ['boy', 'girl', 'animal', 'plant', 'object', 'country'];

export type StopStage = 'answer' | 'review' | 'finished';

export type StopAction =
  /** Save your whole sheet for this round (can be sent again until the timer ends). */
  | { kind: 'answers'; round: number; answers: Partial<Record<StopCategory, string>>; done?: boolean }
  /** Finished early; the round ends when every connected player is done. */
  | { kind: 'done'; round: number }
  /** Ask for human review of one of your own words that the dictionary did not know. */
  | { kind: 'appeal'; round: number; category: StopCategory };

/**
 * - `unique`: valid, nobody else wrote it (10).
 * - `shared`: valid, someone else wrote the same word (5).
 * - `wrong_letter`: does not start with the round's letter (0).
 * - `unknown`: starts with the letter but is not in the dictionary (0, can be appealed).
 * - `empty`: nothing written (0).
 */
export type StopVerdict = 'unique' | 'shared' | 'wrong_letter' | 'unknown' | 'empty';

export const STOP_POINTS: Record<StopVerdict, number> = { unique: 10, shared: 5, wrong_letter: 0, unknown: 0, empty: 0 };

export interface StopCell {
  verdict: StopVerdict;
  /** The word, or null when it must not be shown to this viewer (someone else's unknown word). */
  text: string | null;
  points: number;
  /** Your own unknown word has been sent for review. */
  appealed?: boolean;
}

export interface StopRoundResult {
  round: number;
  letter: string;
  /** category -> playerId -> cell */
  cells: Record<StopCategory, Record<string, StopCell>>;
  points: Record<string, number>;
}

export interface StopFinal {
  rounds: { round: number; letter: string; points: Record<string, number> }[];
  ranking: { playerId: string; score: number; place: number; correct: number }[];
}

export interface StopView {
  stage: StopStage;
  stageEndsAt: number;
  round: number;
  totalRounds: number;
  letter: string | null;
  categories: StopCategory[];
  /** Your saved sheet for this round. Other players' answers are never sent while answering. */
  yourAnswers: Partial<Record<StopCategory, string>>;
  youDone: boolean;
  doneCount: number;
  result: StopRoundResult | null;
  scores: Record<string, number>;
  final: StopFinal | null;
}
