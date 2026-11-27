/**
 * Guess with Emoji (خمّن بالإيموجي).
 *
 * Rules (finalized for this build; numbers are configurable defaults):
 * - Everyone gets the same puzzles in the same order, shown at a common
 *   server time (like the quiz), with choices shuffled once per match.
 * - Public and ranked matches use multiple choice with a standardized
 *   profile. Private rooms may switch to typed answers.
 * - Typed answers count only if they match the approved answer or one of its
 *   approved variants after Arabic normalization (article-insensitive). No
 *   fuzzy matching. Each player gets EMOJI_MAX_GUESSES wrong guesses per
 *   puzzle; guesses are private and never sent to other players.
 * - Typed mode shows the answer's shape (letters per word) after half the
 *   time.
 * - Points: 100 for a correct answer plus up to 50 for speed, in whole-second
 *   buckets (same as the quiz), so phones and networks don't decide matches.
 */
import type { Difficulty, EmojiAction, EmojiAnswerMode, EmojiCategory, EmojiView, MatchMode } from '@sahra/shared';
import { EMOJI_CATEGORIES, EMOJI_MAX_GUESSES, matchApprovedAnswer, usesNewerEmoji } from '@sahra/shared';
import { z } from 'zod';
import { type ActionResult, type ContentRow, type GameModule, type GameResults, Rng, placesFromScores } from './engine';
import { QUIZ_TIMING, speedBonus } from './quiz';

export interface EmojiConfig {
  category: EmojiCategory | 'mixed';
  difficulty: Difficulty;
  questionCount: number;
  answerSeconds: number;
  answerMode: EmojiAnswerMode;
}

const STANDARD_CONFIG: EmojiConfig = { category: 'mixed', difficulty: 'medium', questionCount: 10, answerSeconds: 15, answerMode: 'choices' };

const configSchema = z.object({
  category: z.union([z.enum(EMOJI_CATEGORIES as [EmojiCategory, ...EmojiCategory[]]), z.literal('mixed')]).default('mixed'),
  difficulty: z.enum(['easy', 'medium', 'hard']).default('medium'),
  questionCount: z.number().int().min(5).max(15).default(10),
  answerSeconds: z.number().int().min(10).max(40).optional(),
  answerMode: z.enum(['choices', 'typed']).default('choices'),
});

export const emojiPayloadSchema = z
  .object({
    emojis: z.string().trim().min(1).max(40),
    answer: z.string().trim().min(2).max(60),
    wrong: z.array(z.string().trim().min(2).max(60)).length(3),
    accepted: z.array(z.string().trim().min(2).max(60)).max(12).default([]),
  })
  .refine((p) => !/[\p{L}\p{N}]/u.test(p.emojis.replace(/[\u{FE0F}\u{20E3}\u{200D}0-9#*]/gu, '')), { message: 'emojis must not contain text' })
  .refine((p) => !usesNewerEmoji(p.emojis), { message: 'uses emoji that older phones cannot show' })
  .refine((p) => new Set([p.answer, ...p.wrong]).size === 4, { message: 'duplicate choices' });

export interface EmojiPuzzle {
  id: string;
  category: EmojiCategory;
  emojis: string;
  answer: string;
  accepted: string[];
  choices: string[];
  correct: number;
}

export function parseEmojiContent(row: ContentRow): Omit<EmojiPuzzle, 'choices' | 'correct'> & { wrong: string[] } | null {
  const p = emojiPayloadSchema.safeParse(row.payload);
  if (!p.success || !EMOJI_CATEGORIES.includes(row.category as EmojiCategory)) return null;
  return {
    id: row.id,
    category: row.category as EmojiCategory,
    emojis: p.data.emojis,
    answer: p.data.answer,
    wrong: p.data.wrong,
    accepted: [...p.data.accepted, ...(row.acceptedAnswers ?? [])],
  };
}

/** The answer's shape: one dot per letter, words separated by spaces. */
export function answerShape(answer: string): string {
  return answer
    .replace(/[ً-ٰٟـ]/g, '')
    .trim()
    .split(/\s+/)
    .map((w) => '•'.repeat([...w].length))
    .join('  ');
}

interface Answer {
  choice: number;
  elapsedMs: number;
}

export interface EmojiState {
  players: string[];
  config: EmojiConfig;
  puzzles: EmojiPuzzle[];
  index: number;
  stage: 'question' | 'reveal' | 'finished';
  revealAt: number;
  deadline: number;
  revealEndsAt: number;
  /** Typed mode: when the answer's shape is shown (half time), and whether it is. */
  hintAt: number;
  hintShown: boolean;
  /** Per puzzle: correct answers (typed) or picks (choices). */
  answers: Map<string, Answer>[];
  /** Typed mode, current puzzle only: each player's wrong guesses. */
  guesses: Map<string, string[]>;
  scores: Map<string, number>;
  correct: Map<string, number>;
  lastPoints: Record<string, number>;
}

function startQuestion(s: EmojiState, now: number) {
  s.stage = 'question';
  s.revealAt = now + QUIZ_TIMING.revealLeadMs;
  s.deadline = s.revealAt + s.config.answerSeconds * 1000;
  s.lastPoints = {};
  s.guesses = new Map();
  s.hintAt = s.revealAt + Math.floor((s.deadline - s.revealAt) / 2);
  s.hintShown = false;
}

function closeQuestion(s: EmojiState, now: number) {
  const q = s.puzzles[s.index]!;
  const answers = s.answers[s.index]!;
  const points: Record<string, number> = {};
  for (const p of s.players) {
    const a = answers.get(p);
    let pts = 0;
    if (a && a.choice === q.correct) {
      pts = QUIZ_TIMING.correctPoints + speedBonus(a.elapsedMs, s.config.answerSeconds);
      s.correct.set(p, (s.correct.get(p) ?? 0) + 1);
    }
    points[p] = pts;
    s.scores.set(p, (s.scores.get(p) ?? 0) + pts);
  }
  s.lastPoints = points;
  s.stage = 'reveal';
  s.revealEndsAt = now + QUIZ_TIMING.revealStageMs;
}

function elapsedFor(s: EmojiState, raw: unknown, now: number) {
  const serverElapsed = now - s.revealAt;
  const r = (raw as { clientElapsedMs?: unknown }).clientElapsedMs;
  const reported = typeof r === 'number' && Number.isFinite(r) ? r : serverElapsed;
  return Math.min(serverElapsed, Math.max(reported, serverElapsed - QUIZ_TIMING.maxLatencyCompMs));
}

export const emojiModule: GameModule<EmojiState, EmojiConfig, EmojiView> = {
  id: 'emoji',
  capabilities: { minPlayers: 2, maxPlayers: 8, ranked: true, safeModeReady: true, spectators: 'none' },

  defaultConfig() {
    return { ...STANDARD_CONFIG };
  },

  validateConfig(raw: unknown, mode: MatchMode): EmojiConfig {
    // Only private rooms can change settings (and only they may use typed answers).
    if (mode !== 'private') return { ...STANDARD_CONFIG };
    const parsed = configSchema.safeParse(raw ?? {});
    if (!parsed.success) return { ...STANDARD_CONFIG };
    const c = parsed.data;
    return { ...c, answerSeconds: c.answerSeconds ?? (c.answerMode === 'typed' ? 30 : 15) };
  },

  expectedDurationSec(c) {
    const perQuestion = QUIZ_TIMING.revealLeadMs / 1000 + c.answerSeconds * 0.6 + QUIZ_TIMING.revealStageMs / 1000;
    return Math.round(c.questionCount * perQuestion);
  },

  contentRequest(c) {
    return { gameId: 'emoji', count: c.questionCount + 4, category: c.category, difficulty: c.difficulty };
  },

  setup(players, config, content, rng, now) {
    const puzzles = content
      .map(parseEmojiContent)
      .filter((q): q is NonNullable<typeof q> => q !== null)
      .slice(0, config.questionCount)
      .map(({ wrong, ...q }) => {
        const choices = rng.shuffle([q.answer, ...wrong]);
        return { ...q, choices, correct: choices.indexOf(q.answer) };
      });
    if (puzzles.length < Math.min(5, config.questionCount)) throw new Error('not_enough_content');
    const s: EmojiState = {
      players: players.slice(),
      config: { ...config, questionCount: puzzles.length },
      puzzles,
      index: 0,
      stage: 'question',
      revealAt: 0,
      deadline: 0,
      revealEndsAt: 0,
      hintAt: 0,
      hintShown: false,
      answers: puzzles.map(() => new Map()),
      guesses: new Map(),
      scores: new Map(players.map((p) => [p, 0])),
      correct: new Map(players.map((p) => [p, 0])),
      lastPoints: {},
    };
    startQuestion(s, now);
    return s;
  },

  onAction(s, playerId, raw, now): ActionResult {
    const a = raw as EmojiAction;
    if (!s.players.includes(playerId)) return { ok: false, code: 'not_in_match' };
    if (!a || typeof a !== 'object' || (a.kind !== 'answer' && a.kind !== 'guess')) return { ok: false, code: 'bad_action' };
    if (s.stage !== 'question' || a.questionIndex !== s.index) return { ok: false, code: 'not_accepting' };
    if (now < s.revealAt) return { ok: false, code: 'too_early' };
    if (now > s.deadline) return { ok: false, code: 'too_late' };
    const q = s.puzzles[s.index]!;
    const answers = s.answers[s.index]!;
    if (answers.has(playerId)) return { ok: false, code: 'already_answered' };

    if (s.config.answerMode === 'choices') {
      if (a.kind !== 'answer') return { ok: false, code: 'bad_action' };
      if (!Number.isInteger(a.choice) || a.choice < 0 || a.choice >= q.choices.length) return { ok: false, code: 'bad_choice' };
      answers.set(playerId, { choice: a.choice, elapsedMs: elapsedFor(s, raw, now) });
      return { ok: true };
    }

    if (a.kind !== 'guess' || typeof a.text !== 'string') return { ok: false, code: 'bad_action' };
    const text = a.text.trim().slice(0, 60);
    if (!text) return { ok: false, code: 'empty_guess' };
    const wrong = s.guesses.get(playerId) ?? [];
    if (wrong.length >= EMOJI_MAX_GUESSES) return { ok: false, code: 'no_guesses_left' };
    if (matchApprovedAnswer(text, [q.answer, ...q.accepted], { ignoreDefiniteArticle: true }) >= 0) {
      answers.set(playerId, { choice: q.correct, elapsedMs: elapsedFor(s, raw, now) });
    } else {
      s.guesses.set(playerId, [...wrong, text]);
    }
    // A wrong guess is still a valid action; the player sees it in their own view.
    return { ok: true };
  },

  tick(s, now, activePlayers) {
    if (s.stage === 'question') {
      if (s.config.answerMode === 'typed' && now >= s.hintAt) s.hintShown = true;
      const answers = s.answers[s.index]!;
      const done = (p: string) =>
        answers.has(p) || (s.config.answerMode === 'typed' && (s.guesses.get(p)?.length ?? 0) >= EMOJI_MAX_GUESSES);
      const everyoneActiveDone = activePlayers.size > 0 && [...activePlayers].every((p) => !s.players.includes(p) || done(p));
      if (now >= s.deadline || (now >= s.revealAt && everyoneActiveDone)) closeQuestion(s, now);
    } else if (s.stage === 'reveal' && now >= s.revealEndsAt) {
      if (s.index + 1 >= s.puzzles.length) {
        s.stage = 'finished';
      } else {
        s.index += 1;
        startQuestion(s, now);
      }
    }
  },

  botPlan(s, botId, rng, skill) {
    if (s.stage !== 'question' || s.answers[s.index]!.has(botId)) return null;
    const q = s.puzzles[s.index]!;
    const window = s.config.answerSeconds * 1000;
    const min = QUIZ_TIMING.botMinDelayMs;
    const at = s.revealAt + min + Math.floor(rng.next() * Math.max(1, window * QUIZ_TIMING.botMaxShare - min));
    const right = rng.next() < skill;
    const wrong = q.choices.map((_, i) => i).filter((i) => i !== q.correct);
    const choice = right || wrong.length === 0 ? q.correct : wrong[rng.int(wrong.length)]!;
    const action =
      s.config.answerMode === 'choices'
        ? { kind: 'answer', questionIndex: s.index, choice, clientElapsedMs: at - s.revealAt }
        : { kind: 'guess', questionIndex: s.index, text: q.choices[choice]!, clientElapsedMs: at - s.revealAt };
    return { key: String(s.index), at, action };
  },

  nextWakeAt(s) {
    if (s.stage === 'question') {
      // Typed mode also wakes at half time to show the hint.
      return s.config.answerMode === 'typed' && !s.hintShown ? s.hintAt : s.deadline;
    }
    if (s.stage === 'reveal') return s.revealEndsAt;
    return null;
  },

  viewFor(s, viewer): EmojiView {
    const q = s.puzzles[s.index];
    const answers = s.answers[s.index];
    const finished = s.stage === 'finished';
    const typed = s.config.answerMode === 'typed';
    return {
      stage: s.stage,
      question:
        q && !finished
          ? {
              index: s.index,
              total: s.puzzles.length,
              category: q.category,
              prompt: '',
              emojis: q.emojis,
              mode: s.config.answerMode,
              choices: typed ? [] : q.choices,
              hint: typed && (s.hintShown || s.stage === 'reveal') ? answerShape(q.answer) : null,
              revealAt: s.revealAt,
              deadline: s.deadline,
            }
          : null,
      yourChoice: answers?.get(viewer)?.choice ?? null,
      yourGuesses: s.stage === 'finished' ? [] : s.guesses.get(viewer) ?? [],
      answeredCount: answers?.size ?? 0,
      // The answer is only included after the puzzle closes.
      reveal:
        s.stage === 'reveal' && q
          ? {
              index: s.index,
              correctChoice: typed ? -1 : q.correct,
              answer: q.answer,
              explanation: null,
              points: s.lastPoints,
              picks: typed ? {} : Object.fromEntries([...(answers ?? new Map())].map(([p, a]) => [p, a.choice])),
            }
          : null,
      scores: Object.fromEntries(s.scores),
      final: finished ? { ranking: this.results(s).ranking.map((r) => ({ ...r, correct: r.correct ?? 0 })), ratingApplied: false } : null,
    };
  },

  isFinished(s) {
    return s.stage === 'finished';
  },

  results(s): GameResults {
    const max = s.puzzles.length * (QUIZ_TIMING.correctPoints + QUIZ_TIMING.maxSpeedBonus);
    const ranking = placesFromScores(s.players.map((p) => ({ playerId: p, score: s.scores.get(p) ?? 0 }))).map((r) => ({
      ...r,
      correct: s.correct.get(r.playerId) ?? 0,
    }));
    const performance = Object.fromEntries(s.players.map((p) => [p, max > 0 ? (s.scores.get(p) ?? 0) / max : 0]));
    return { ranking, performance };
  },
};
