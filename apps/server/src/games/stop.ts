/**
 * Stop / Atobees Complete (أتوبيس كومبليت).
 *
 * Rules (finalized for this build; numbers are configurable defaults):
 * - Each round draws a letter that the approved dictionary covers well in
 *   every category (no letter twice in a match). Everyone gets the same timer
 *   and can edit their sheet until it ends; the round ends early only when
 *   every connected player pressed "done".
 * - Checking is dictionary-based after Arabic normalization; nothing is
 *   guessed. 10 for a valid unique word, 5 for a valid shared word, 0 for a
 *   wrong letter, an empty cell, or a word the dictionary does not know.
 * - Unknown words are shown only to their author, who may appeal. Appeals go
 *   to human review (results.suggestions); approved words join the
 *   dictionary for future matches. Scores of a finished match do not change,
 *   so the game stays out of ranked play until appeals can be resolved
 *   before results are final.
 */
import type { MatchMode, StopAction, StopCategory, StopCell, StopFinal, StopRoundResult, StopView } from '@sahra/shared';
import { STOP_CATEGORIES, STOP_POINTS, normalizeArabic, stripDefiniteArticle } from '@sahra/shared';
import { z } from 'zod';
import { type ActionResult, type ContentRow, type GameModule, type GameResults, Rng, placesFromScores } from './engine';

export const STOP_TIMING = { reviewMs: 15000, botMinShare: 0.35, botMaxShare: 0.85 };
/** A letter is playable only if every category has at least this many dictionary words for it. */
export const STOP_MIN_WORDS_PER_LETTER = 2;

export interface StopConfig {
  rounds: number;
  answerSeconds: number;
}

const STANDARD_CONFIG: StopConfig = { rounds: 3, answerSeconds: 60 };

const configSchema = z.object({
  rounds: z.number().int().min(1).max(6).default(3),
  answerSeconds: z.number().int().min(30).max(120).default(60),
});

export const stopPayloadSchema = z.object({
  words: z.array(z.string().trim().min(2).max(40)).min(1).max(3000),
});

const LETTERS = 'ابتثجحخدذرزسشصضطظعغفقكلمنهوي'.split('');

/** Comparison key: normalized, article-insensitive, spaces ignored. */
export function stopKey(word: string): string {
  return stripDefiniteArticle(normalizeArabic(word)).replace(/\s+/g, '');
}

/** First letter for the letter rule ("الأردن" counts under ا, like "أردن"). */
export function stopInitial(word: string): string {
  return stopKey(word).charAt(0);
}

type Dictionary = Record<StopCategory, Map<string, string>>; // key -> display word

export function buildDictionary(content: ContentRow[]): Dictionary {
  const dict = Object.fromEntries(STOP_CATEGORIES.map((c) => [c, new Map<string, string>()])) as Dictionary;
  for (const row of content) {
    if (!STOP_CATEGORIES.includes(row.category as StopCategory)) continue;
    const p = stopPayloadSchema.safeParse(row.payload);
    if (!p.success) continue;
    const m = dict[row.category as StopCategory];
    for (const w of [...p.data.words, ...(row.acceptedAnswers ?? [])]) {
      const k = stopKey(w);
      if (k.length >= 2 && !m.has(k)) m.set(k, w);
    }
  }
  return dict;
}

export function playableLetters(dict: Dictionary): string[] {
  return LETTERS.filter((l) =>
    STOP_CATEGORIES.every((c) => [...dict[c].keys()].filter((k) => k.charAt(0) === l).length >= STOP_MIN_WORDS_PER_LETTER),
  );
}

export interface StopState {
  players: string[];
  config: StopConfig;
  dict: Dictionary;
  letters: string[];
  round: number; // 1-based
  stage: 'answer' | 'review' | 'finished';
  stageEndsAt: number;
  sheets: Map<string, Partial<Record<StopCategory, string>>>;
  done: Set<string>;
  results: StopRoundResult[];
  scores: Map<string, number>;
  /** Valid answers per player across the match (for rewards and stats). */
  valid: Map<string, number>;
  appeals: { round: number; category: StopCategory; word: string; userId: string }[];
  final: StopFinal | null;
}

export function scoreRound(
  letter: string,
  players: string[],
  sheets: Map<string, Partial<Record<StopCategory, string>>>,
  dict: Dictionary,
): Omit<StopRoundResult, 'round'> {
  const cells = Object.fromEntries(STOP_CATEGORIES.map((c) => [c, {} as Record<string, StopCell>])) as StopRoundResult['cells'];
  const points: Record<string, number> = Object.fromEntries(players.map((p) => [p, 0]));
  for (const c of STOP_CATEGORIES) {
    const keys = new Map<string, string>(); // player -> key of a valid answer
    for (const p of players) {
      const text = (sheets.get(p)?.[c] ?? '').trim();
      const k = stopKey(text);
      if (!k) cells[c][p] = { verdict: 'empty', text: null, points: 0 };
      else if (k.charAt(0) !== letter) cells[c][p] = { verdict: 'wrong_letter', text, points: 0 };
      else if (!dict[c].has(k)) cells[c][p] = { verdict: 'unknown', text, points: 0 };
      else keys.set(p, k);
    }
    for (const [p, k] of keys) {
      const shared = [...keys.values()].filter((x) => x === k).length > 1;
      const verdict = shared ? 'shared' : 'unique';
      cells[c][p] = { verdict, text: (sheets.get(p)?.[c] ?? '').trim(), points: STOP_POINTS[verdict] };
    }
    for (const p of players) points[p]! += cells[c][p]!.points;
  }
  return { letter, cells, points };
}

function closeRound(s: StopState, now: number) {
  const letter = s.letters[s.round - 1]!;
  const r = { round: s.round, ...scoreRound(letter, s.players, s.sheets, s.dict) };
  s.results.push(r);
  for (const p of s.players) {
    s.scores.set(p, (s.scores.get(p) ?? 0) + (r.points[p] ?? 0));
    const n = STOP_CATEGORIES.filter((c) => r.cells[c][p]!.points > 0).length;
    s.valid.set(p, (s.valid.get(p) ?? 0) + n);
  }
  s.stage = 'review';
  s.stageEndsAt = now + STOP_TIMING.reviewMs;
}

function startRound(s: StopState, now: number) {
  s.stage = 'answer';
  s.stageEndsAt = now + s.config.answerSeconds * 1000;
  s.sheets = new Map();
  s.done = new Set();
}

function ranking(s: StopState) {
  return placesFromScores(s.players.map((p) => ({ playerId: p, score: s.scores.get(p) ?? 0 }))).map((r) => ({
    ...r,
    correct: s.valid.get(r.playerId) ?? 0,
  }));
}

export const stopModule: GameModule<StopState, StopConfig, StopView> = {
  id: 'stop',
  // Not ranked: appeals are reviewed after the match, so results cannot be final yet.
  capabilities: { minPlayers: 2, maxPlayers: 8, ranked: false, safeModeReady: true, spectators: 'none' },

  defaultConfig() {
    return { ...STANDARD_CONFIG };
  },

  validateConfig(raw: unknown, mode: MatchMode): StopConfig {
    if (mode !== 'private') return { ...STANDARD_CONFIG };
    const parsed = configSchema.safeParse(raw ?? {});
    return parsed.success ? parsed.data : { ...STANDARD_CONFIG };
  },

  expectedDurationSec(c) {
    return Math.round(c.rounds * (c.answerSeconds * 0.85 + STOP_TIMING.reviewMs / 1000));
  },

  contentRequest() {
    // The whole approved dictionary (one item per category plus approved appeals).
    return { gameId: 'stop', count: 500, category: 'mixed', difficulty: 'medium' };
  },

  setup(players, config, content, rng, now) {
    const dict = buildDictionary(content);
    const letters = rng.shuffle(playableLetters(dict)).slice(0, config.rounds);
    if (letters.length < config.rounds) throw new Error('not_enough_content');
    const s: StopState = {
      players: players.slice(),
      config: { ...config },
      dict,
      letters,
      round: 1,
      stage: 'answer',
      stageEndsAt: 0,
      sheets: new Map(),
      done: new Set(),
      results: [],
      scores: new Map(players.map((p) => [p, 0])),
      valid: new Map(players.map((p) => [p, 0])),
      appeals: [],
      final: null,
    };
    startRound(s, now);
    return s;
  },

  onAction(s, playerId, raw, now): ActionResult {
    const a = raw as StopAction;
    if (!s.players.includes(playerId)) return { ok: false, code: 'not_in_match' };
    if (!a || typeof a !== 'object' || typeof a.kind !== 'string') return { ok: false, code: 'bad_action' };
    if (a.round !== s.round) return { ok: false, code: 'not_accepting' };
    switch (a.kind) {
      case 'answers': {
        if (s.stage !== 'answer' || now > s.stageEndsAt) return { ok: false, code: 'not_accepting' };
        if (!a.answers || typeof a.answers !== 'object') return { ok: false, code: 'bad_action' };
        const sheet: Partial<Record<StopCategory, string>> = {};
        for (const c of STOP_CATEGORIES) {
          const v = (a.answers as Record<string, unknown>)[c];
          if (typeof v === 'string' && v.trim()) sheet[c] = v.trim().slice(0, 40);
        }
        s.sheets.set(playerId, sheet);
        if (a.done === true) s.done.add(playerId);
        return { ok: true };
      }
      case 'done':
        if (s.stage !== 'answer') return { ok: false, code: 'not_accepting' };
        s.done.add(playerId);
        return { ok: true };
      case 'appeal': {
        const r = s.results.find((x) => x.round === a.round);
        const cell = r && STOP_CATEGORIES.includes(a.category) ? r.cells[a.category][playerId] : undefined;
        if (!cell || cell.verdict !== 'unknown' || !cell.text) return { ok: false, code: 'not_appealable' };
        if (cell.appealed) return { ok: false, code: 'already_appealed' };
        cell.appealed = true;
        s.appeals.push({ round: a.round, category: a.category, word: cell.text, userId: playerId });
        return { ok: true };
      }
      default:
        return { ok: false, code: 'bad_action' };
    }
  },

  tick(s, now, active) {
    for (let guard = 0; guard < 4; guard++) {
      if (s.stage === 'answer') {
        const here = s.players.filter((p) => active.has(p));
        const allDone = here.length > 0 && here.every((p) => s.done.has(p));
        if (now < s.stageEndsAt && !allDone) return;
        closeRound(s, now);
      } else if (s.stage === 'review') {
        if (now < s.stageEndsAt) return;
        if (s.round >= s.letters.length) {
          s.stage = 'finished';
          s.stageEndsAt = 0;
          s.final = {
            rounds: s.results.map((r) => ({ round: r.round, letter: r.letter, points: r.points })),
            ranking: ranking(s),
          };
          return;
        }
        s.round++;
        startRound(s, now);
      } else return;
    }
  },

  botPlan(s, botId, rng, skill) {
    if (s.stage !== 'answer' || s.done.has(botId)) return null;
    const letter = s.letters[s.round - 1]!;
    const span = s.config.answerSeconds * 1000;
    const at = s.stageEndsAt - span + Math.floor(span * (STOP_TIMING.botMinShare + rng.next() * (STOP_TIMING.botMaxShare - STOP_TIMING.botMinShare)));
    const answers: Partial<Record<StopCategory, string>> = {};
    for (const c of STOP_CATEGORIES) {
      if (rng.next() >= skill) continue;
      const words = [...s.dict[c].entries()].filter(([k]) => k.charAt(0) === letter).map(([, w]) => w);
      if (words.length) answers[c] = words[rng.int(words.length)]!;
    }
    // One plan per round: the bot fills its sheet once and is done.
    return { key: `r${s.round}`, at, action: { kind: 'answers', round: s.round, answers, done: true } };
  },

  nextWakeAt(s) {
    return s.stage === 'finished' ? null : s.stageEndsAt;
  },

  viewFor(s, viewer): StopView {
    const r = s.stage === 'review' ? s.results[s.results.length - 1]! : null;
    let result: StopRoundResult | null = null;
    if (r) {
      // Someone else's unknown word could be anything: only its author sees it.
      const cells = Object.fromEntries(
        STOP_CATEGORIES.map((c) => [
          c,
          Object.fromEntries(
            Object.entries(r.cells[c]).map(([p, cell]) => [
              p,
              cell.verdict === 'unknown' && p !== viewer ? { verdict: cell.verdict, text: null, points: 0 } : cell,
            ]),
          ),
        ]),
      ) as StopRoundResult['cells'];
      result = { ...r, cells };
    }
    return {
      stage: s.stage,
      stageEndsAt: s.stageEndsAt,
      round: s.round,
      totalRounds: s.letters.length,
      letter: s.stage === 'finished' ? null : s.letters[s.round - 1] ?? null,
      categories: STOP_CATEGORIES.slice(),
      yourAnswers: s.stage === 'answer' ? s.sheets.get(viewer) ?? {} : {},
      youDone: s.done.has(viewer),
      doneCount: s.stage === 'answer' ? s.done.size : 0,
      result,
      scores: Object.fromEntries(s.scores),
      final: s.final,
    };
  },

  isFinished(s) {
    return s.stage === 'finished';
  },

  results(s): GameResults {
    const max = s.letters.length * STOP_CATEGORIES.length * STOP_POINTS.unique;
    return {
      ranking: ranking(s),
      performance: Object.fromEntries(s.players.map((p) => [p, max > 0 ? (s.scores.get(p) ?? 0) / max : 0])),
      suggestions: s.appeals.map((a) => ({ gameId: 'stop', category: a.category, word: a.word, userId: a.userId })),
    };
  },
};
