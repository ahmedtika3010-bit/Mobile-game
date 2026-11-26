/**
 * General Knowledge Quiz.
 *
 * Fairness rules:
 * - Every player gets the same questions in the same order, with choices
 *   shuffled identically (one seed per match).
 * - A question is sent ahead of time with a common `revealAt` server time, so
 *   all clients show it at the same moment regardless of download speed.
 * - Points are mostly for correctness (100). Speed adds at most 50, counted in
 *   whole-second buckets so small device or network differences do not matter.
 * - Network compensation: the client reports how long it took after it showed
 *   the question; the server accepts that, but never more than
 *   MAX_LATENCY_COMP_MS below what the server itself measured.
 */
import type { MatchMode, QuizAction, QuizCategory, QuizView, Difficulty } from '@sahra/shared';
import { QUIZ_CATEGORIES } from '@sahra/shared';
import { z } from 'zod';
import {
  type ActionResult,
  type ContentRow,
  type GameModule,
  type GameResults,
  Rng,
  placesFromScores,
} from './engine';

export const QUIZ_TIMING = {
  /** Delay between sending a question and showing it, so slow downloads are not penalized. */
  revealLeadMs: 1000,
  revealStageMs: 4000,
  maxLatencyCompMs: 1500,
  correctPoints: 100,
  maxSpeedBonus: 50,
};

export interface QuizConfig {
  category: QuizCategory | 'mixed';
  difficulty: Difficulty;
  questionCount: number;
  answerSeconds: number;
}

const RANKED_CONFIG: QuizConfig = { category: 'mixed', difficulty: 'medium', questionCount: 10, answerSeconds: 15 };

const configSchema = z.object({
  category: z.union([z.enum(QUIZ_CATEGORIES as [QuizCategory, ...QuizCategory[]]), z.literal('mixed')]).default('mixed'),
  difficulty: z.enum(['easy', 'medium', 'hard']).default('medium'),
  questionCount: z.number().int().min(5).max(20).default(10),
  answerSeconds: z.number().int().min(8).max(30).default(15),
});

export interface QuizQuestion {
  id: string;
  category: QuizCategory;
  prompt: string;
  choices: string[];
  correct: number;
  explanation: string | null;
}

interface Answer {
  choice: number;
  elapsedMs: number;
}

export interface QuizState {
  players: string[];
  config: QuizConfig;
  questions: QuizQuestion[];
  index: number;
  stage: 'question' | 'reveal' | 'finished';
  revealAt: number;
  deadline: number;
  revealEndsAt: number;
  answers: Map<string, Answer>[];
  scores: Map<string, number>;
  correct: Map<string, number>;
  lastPoints: Record<string, number>;
}

const payloadSchema = z.object({
  prompt: z.string().min(1),
  choices: z.array(z.string().min(1)).min(2).max(6),
  correct: z.number().int().min(0),
  explanation: z.string().nullable().optional(),
});

export function parseQuizContent(row: ContentRow): QuizQuestion | null {
  const p = payloadSchema.safeParse(row.payload);
  if (!p.success || p.data.correct >= p.data.choices.length) return null;
  return {
    id: row.id,
    category: row.category as QuizCategory,
    prompt: p.data.prompt,
    choices: p.data.choices,
    correct: p.data.correct,
    explanation: p.data.explanation ?? null,
  };
}

export function speedBonus(elapsedMs: number, answerSeconds: number): number {
  const bucket = Math.floor(Math.max(0, elapsedMs) / 1000);
  const remaining = Math.max(0, answerSeconds - 1 - bucket);
  return Math.round((QUIZ_TIMING.maxSpeedBonus * remaining) / Math.max(1, answerSeconds - 1));
}

function startQuestion(s: QuizState, now: number) {
  s.stage = 'question';
  s.revealAt = now + QUIZ_TIMING.revealLeadMs;
  s.deadline = s.revealAt + s.config.answerSeconds * 1000;
  s.lastPoints = {};
}

function closeQuestion(s: QuizState, now: number) {
  const q = s.questions[s.index]!;
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

export const quizModule: GameModule<QuizState, QuizConfig, QuizView> = {
  id: 'quiz',
  capabilities: { minPlayers: 2, maxPlayers: 8, ranked: true, safeModeReady: true, spectators: 'none' },

  defaultConfig(mode: MatchMode) {
    return { ...RANKED_CONFIG, ...(mode === 'ranked' ? {} : {}) };
  },

  validateConfig(raw: unknown, mode: MatchMode): QuizConfig {
    if (mode === 'ranked') return { ...RANKED_CONFIG };
    const parsed = configSchema.safeParse(raw ?? {});
    return parsed.success ? parsed.data : { ...RANKED_CONFIG };
  },

  expectedDurationSec(c) {
    const perQuestion = QUIZ_TIMING.revealLeadMs / 1000 + c.answerSeconds * 0.6 + QUIZ_TIMING.revealStageMs / 1000;
    return Math.round(c.questionCount * perQuestion);
  },

  contentRequest(c) {
    return { gameId: 'quiz', count: c.questionCount, category: c.category, difficulty: c.difficulty };
  },

  setup(players, config, content, rng, now) {
    const questions = content
      .map(parseQuizContent)
      .filter((q): q is QuizQuestion => q !== null)
      .slice(0, config.questionCount)
      .map((q) => {
        // Shuffle choices with the match seed; every player sees the same order.
        const order = rng.shuffle(q.choices.map((_, i) => i));
        return { ...q, choices: order.map((i) => q.choices[i]!), correct: order.indexOf(q.correct) };
      });
    if (questions.length < Math.min(5, config.questionCount)) {
      throw new Error('not_enough_content');
    }
    const s: QuizState = {
      players: players.slice(),
      config: { ...config, questionCount: questions.length },
      questions,
      index: 0,
      stage: 'question',
      revealAt: 0,
      deadline: 0,
      revealEndsAt: 0,
      answers: questions.map(() => new Map()),
      scores: new Map(players.map((p) => [p, 0])),
      correct: new Map(players.map((p) => [p, 0])),
      lastPoints: {},
    };
    startQuestion(s, now);
    return s;
  },

  onAction(s, playerId, raw, now): ActionResult {
    const a = raw as QuizAction;
    if (!s.players.includes(playerId)) return { ok: false, code: 'not_in_match' };
    if (!a || a.kind !== 'answer' || typeof a.choice !== 'number') return { ok: false, code: 'bad_action' };
    if (s.stage !== 'question' || a.questionIndex !== s.index) return { ok: false, code: 'not_accepting' };
    if (now < s.revealAt) return { ok: false, code: 'too_early' };
    if (now > s.deadline) return { ok: false, code: 'too_late' };
    const q = s.questions[s.index]!;
    if (!Number.isInteger(a.choice) || a.choice < 0 || a.choice >= q.choices.length) return { ok: false, code: 'bad_choice' };
    const answers = s.answers[s.index]!;
    if (answers.has(playerId)) return { ok: false, code: 'already_answered' };
    const serverElapsed = now - s.revealAt;
    const reported = typeof (raw as { clientElapsedMs?: unknown }).clientElapsedMs === 'number'
      ? (raw as { clientElapsedMs: number }).clientElapsedMs
      : serverElapsed;
    const elapsedMs = Math.min(serverElapsed, Math.max(reported, serverElapsed - QUIZ_TIMING.maxLatencyCompMs));
    answers.set(playerId, { choice: a.choice, elapsedMs });
    return { ok: true };
  },

  tick(s, now, activePlayers) {
    if (s.stage === 'question') {
      const answers = s.answers[s.index]!;
      const everyoneActiveAnswered =
        activePlayers.size > 0 && [...activePlayers].every((p) => !s.players.includes(p) || answers.has(p));
      if (now >= s.deadline || (now >= s.revealAt && everyoneActiveAnswered)) closeQuestion(s, now);
    } else if (s.stage === 'reveal' && now >= s.revealEndsAt) {
      if (s.index + 1 >= s.questions.length) {
        s.stage = 'finished';
      } else {
        s.index += 1;
        startQuestion(s, now);
      }
    }
  },

  nextWakeAt(s) {
    if (s.stage === 'question') return s.deadline;
    if (s.stage === 'reveal') return s.revealEndsAt;
    return null;
  },

  viewFor(s, viewer): QuizView {
    const q = s.questions[s.index];
    const answers = s.answers[s.index];
    const scores = Object.fromEntries(s.scores);
    const finished = s.stage === 'finished';
    return {
      stage: s.stage,
      question:
        q && !finished
          ? {
              index: s.index,
              total: s.questions.length,
              category: q.category,
              prompt: q.prompt,
              choices: q.choices,
              revealAt: s.revealAt,
              deadline: s.deadline,
            }
          : null,
      yourChoice: answers?.get(viewer)?.choice ?? null,
      answeredCount: answers?.size ?? 0,
      // The correct answer is only included after the question closes.
      reveal:
        s.stage === 'reveal' && q
          ? { index: s.index, correctChoice: q.correct, explanation: q.explanation, points: s.lastPoints }
          : null,
      scores,
      final: finished ? { ranking: this.results(s).ranking.map((r) => ({ ...r, correct: r.correct ?? 0 })), ratingApplied: false } : null,
    };
  },

  isFinished(s) {
    return s.stage === 'finished';
  },

  results(s): GameResults {
    const max = s.questions.length * (QUIZ_TIMING.correctPoints + QUIZ_TIMING.maxSpeedBonus);
    const ranking = placesFromScores(s.players.map((p) => ({ playerId: p, score: s.scores.get(p) ?? 0 }))).map((r) => ({
      ...r,
      correct: s.correct.get(r.playerId) ?? 0,
    }));
    const performance = Object.fromEntries(s.players.map((p) => [p, max > 0 ? (s.scores.get(p) ?? 0) / max : 0]));
    return { ranking, performance };
  },
};

export { Rng };
