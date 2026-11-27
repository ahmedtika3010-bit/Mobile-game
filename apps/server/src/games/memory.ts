/**
 * Memory Challenges (تحديات الذاكرة).
 *
 * Rules (finalized for this build; numbers are configurable defaults):
 * - Rounds are generated from the match seed (no content database needed).
 *   Mixed matches cycle through the three modes; private rooms may pick one.
 * - Each round: `show` (content visible from showAt to hideAt, the same
 *   window for everyone), then `answer` (opens at answerAt = hideAt + a short
 *   gap, closes at the deadline or when every connected player is done), then
 *   `reveal`.
 * - The content to memorize is only included in views during the show stage
 *   and the reveal. A modified client could still keep it, so the game stays
 *   out of ranked play until integrity checks exist.
 * - Points: up to 100 for correctness (cards and sequence give partial
 *   credit), plus up to 30 for speed only when fully correct, counted in
 *   whole seconds with the quiz's latency compensation.
 */
import type { Difficulty, MatchMode, MemoryAction, MemoryMode, MemoryRoundView, MemoryView } from '@sahra/shared';
import { MEMORY_MODES, MEMORY_SEQUENCE_PADS } from '@sahra/shared';
import { z } from 'zod';
import { type ActionResult, type GameModule, type GameResults, Rng, placesFromScores } from './engine';

export const MEMORY_TIMING = {
  leadMs: 1500,
  gapMs: 800,
  revealMs: 4000,
  maxLatencyCompMs: 1500,
  fullPoints: 100,
  maxSpeedBonus: 30,
};

/** Emoji from Emoji 11 or earlier, easy to tell apart at a glance. */
export const MEMORY_EMOJI = [
  '🍎', '🍌', '🍇', '🍉', '🍓', '🍒', '🍍', '🥝', '🍕', '🍩', '🍦', '🧁', '🍪', '🥕',
  '🐶', '🐱', '🐭', '🐰', '🦊', '🐻', '🐼', '🐸', '🐵', '🐔', '🐧', '🐢', '🐙', '🦋',
  '🌸', '🌻', '🌈', '⭐', '🌙', '⚽', '🏀', '🎈', '🎁', '🎸', '🚗', '🚀', '✈️', '🏠',
  '⏰', '🔑', '💎', '🎩', '👑', '☂️',
];

interface Profile {
  cells: number;
  columns: number;
  targets: number;
  cardsShowMs: number;
  spotShowMs: number;
  seqLength: number;
  stepMs: number;
}

export const PROFILES: Record<Difficulty, Profile> = {
  easy: { cells: 6, columns: 3, targets: 2, cardsShowMs: 6000, spotShowMs: 5000, seqLength: 4, stepMs: 800 },
  medium: { cells: 9, columns: 3, targets: 3, cardsShowMs: 5000, spotShowMs: 4000, seqLength: 6, stepMs: 700 },
  hard: { cells: 12, columns: 4, targets: 3, cardsShowMs: 5000, spotShowMs: 3500, seqLength: 8, stepMs: 600 },
};

const ANSWER_SECONDS: Record<MemoryMode, number> = { cards: 12, spot: 10, sequence: 15 };

export interface MemoryConfig {
  mode: MemoryMode | 'mixed';
  difficulty: Difficulty;
  rounds: number;
}

const STANDARD_CONFIG: MemoryConfig = { mode: 'mixed', difficulty: 'medium', rounds: 6 };

const configSchema = z.object({
  mode: z.enum(['mixed', 'cards', 'sequence', 'spot']).default('mixed'),
  difficulty: z.enum(['easy', 'medium', 'hard']).default('medium'),
  rounds: z.number().int().min(3).max(9).default(6),
});

export interface MemoryRound {
  mode: MemoryMode;
  columns: number;
  grid: string[];
  /** cards: the target emojis; their cells are the answer. */
  targets: string[];
  /** spot: the grid with one card changed. */
  changedGrid: string[];
  sequence: number[];
  stepMs: number;
  showMs: number;
  answerSeconds: number;
  /** cards: target cells; spot: [changed cell]; sequence: the order. */
  answer: number[];
}

export function generateRound(mode: MemoryMode, difficulty: Difficulty, rng: Rng): MemoryRound {
  const p = PROFILES[difficulty];
  const pool = rng.shuffle(MEMORY_EMOJI);
  const grid = pool.slice(0, p.cells);
  const base = { mode, columns: p.columns, grid: [] as string[], targets: [] as string[], changedGrid: [] as string[], sequence: [] as number[], stepMs: p.stepMs };
  if (mode === 'cards') {
    const cells = rng.shuffle(grid.map((_, i) => i)).slice(0, p.targets);
    return { ...base, grid, targets: cells.map((c) => grid[c]!), showMs: p.cardsShowMs, answerSeconds: ANSWER_SECONDS.cards, answer: cells };
  }
  if (mode === 'spot') {
    const cell = rng.int(p.cells);
    const changedGrid = grid.slice();
    changedGrid[cell] = pool[p.cells]!; // an emoji that was not on the board
    return { ...base, grid, changedGrid, showMs: p.spotShowMs, answerSeconds: ANSWER_SECONDS.spot, answer: [cell] };
  }
  // Sequence: no pad twice in a row, so every step is visible as a new flash.
  const sequence: number[] = [];
  while (sequence.length < p.seqLength) {
    const n = rng.int(MEMORY_SEQUENCE_PADS);
    if (n !== sequence[sequence.length - 1]) sequence.push(n);
  }
  return {
    ...base,
    sequence,
    showMs: p.seqLength * p.stepMs + 400,
    answerSeconds: ANSWER_SECONDS.sequence,
    answer: sequence,
  };
}

interface Answer {
  items: number[];
  elapsedMs: number;
  done: boolean;
}

export interface MemoryState {
  players: string[];
  config: MemoryConfig;
  rounds: MemoryRound[];
  index: number; // 0-based
  stage: 'show' | 'answer' | 'reveal' | 'finished';
  showAt: number;
  hideAt: number;
  answerAt: number;
  deadline: number;
  revealEndsAt: number;
  answers: Map<string, Answer>;
  lastReveal: MemoryView['reveal'];
  scores: Map<string, number>;
  /** Fully correct rounds per player. */
  perfect: Map<string, number>;
}

function startRound(s: MemoryState, now: number) {
  const r = s.rounds[s.index]!;
  s.stage = 'show';
  s.showAt = now + MEMORY_TIMING.leadMs;
  s.hideAt = s.showAt + r.showMs;
  s.answerAt = s.hideAt + MEMORY_TIMING.gapMs;
  s.deadline = s.answerAt + r.answerSeconds * 1000;
  s.answers = new Map();
  s.lastReveal = null;
}

/** Correct parts of an answer: cards count found targets, sequence counts the correct prefix. */
export function correctParts(r: MemoryRound, items: number[]): number {
  if (r.mode === 'sequence') {
    let n = 0;
    while (n < r.answer.length && items[n] === r.answer[n]) n++;
    return n;
  }
  return r.answer.filter((cell, i) => items[i] === cell).length;
}

export function speedBonus(elapsedMs: number, answerSeconds: number) {
  const bucket = Math.floor(Math.max(0, elapsedMs) / 1000);
  const remaining = Math.max(0, answerSeconds - 1 - bucket);
  return Math.round((MEMORY_TIMING.maxSpeedBonus * remaining) / Math.max(1, answerSeconds - 1));
}

function closeRound(s: MemoryState, now: number) {
  const r = s.rounds[s.index]!;
  const parts = r.answer.length;
  const correct: Record<string, number> = {};
  const points: Record<string, number> = {};
  const answers: Record<string, number[]> = {};
  for (const p of s.players) {
    const a = s.answers.get(p);
    const c = a ? correctParts(r, a.items) : 0;
    let pts = Math.round((MEMORY_TIMING.fullPoints * c) / parts);
    if (a && c === parts) {
      pts += speedBonus(a.elapsedMs, r.answerSeconds);
      s.perfect.set(p, (s.perfect.get(p) ?? 0) + 1);
    }
    correct[p] = c;
    points[p] = pts;
    answers[p] = a?.items ?? [];
    s.scores.set(p, (s.scores.get(p) ?? 0) + pts);
  }
  s.lastReveal = { answer: r.answer, correct, parts, points, answers };
  s.stage = 'reveal';
  s.revealEndsAt = now + MEMORY_TIMING.revealMs;
}

function elapsedFor(s: MemoryState, raw: unknown, now: number) {
  const serverElapsed = now - s.answerAt;
  const c = (raw as { clientElapsedMs?: unknown }).clientElapsedMs;
  const reported = typeof c === 'number' && Number.isFinite(c) ? c : serverElapsed;
  return Math.min(serverElapsed, Math.max(reported, serverElapsed - MEMORY_TIMING.maxLatencyCompMs));
}

function ranking(s: MemoryState) {
  return placesFromScores(s.players.map((p) => ({ playerId: p, score: s.scores.get(p) ?? 0 }))).map((r) => ({
    ...r,
    correct: s.perfect.get(r.playerId) ?? 0,
  }));
}

export const memoryModule: GameModule<MemoryState, MemoryConfig, MemoryView> = {
  id: 'memory',
  capabilities: { minPlayers: 2, maxPlayers: 8, ranked: false, safeModeReady: true, spectators: 'none' },

  defaultConfig() {
    return { ...STANDARD_CONFIG };
  },

  validateConfig(raw: unknown, mode: MatchMode): MemoryConfig {
    if (mode !== 'private') return { ...STANDARD_CONFIG };
    const parsed = configSchema.safeParse(raw ?? {});
    return parsed.success ? parsed.data : { ...STANDARD_CONFIG };
  },

  expectedDurationSec(c) {
    const p = PROFILES[c.difficulty];
    const perMode: Record<MemoryMode, number> = {
      cards: p.cardsShowMs / 1000 + ANSWER_SECONDS.cards * 0.6,
      spot: p.spotShowMs / 1000 + ANSWER_SECONDS.spot * 0.6,
      sequence: (p.seqLength * p.stepMs) / 1000 + ANSWER_SECONDS.sequence * 0.6,
    };
    const avg = c.mode === 'mixed' ? (perMode.cards + perMode.spot + perMode.sequence) / 3 : perMode[c.mode];
    const fixed = (MEMORY_TIMING.leadMs + MEMORY_TIMING.gapMs + MEMORY_TIMING.revealMs) / 1000;
    return Math.round(c.rounds * (avg + fixed));
  },

  contentRequest() {
    return null; // generated from the match seed
  },

  setup(players, config, _content, rng, now) {
    const order = rng.shuffle(MEMORY_MODES.slice());
    const rounds = Array.from({ length: config.rounds }, (_, i) =>
      generateRound(config.mode === 'mixed' ? order[i % order.length]! : config.mode, config.difficulty, rng),
    );
    const s: MemoryState = {
      players: players.slice(),
      config: { ...config },
      rounds,
      index: 0,
      stage: 'show',
      showAt: 0,
      hideAt: 0,
      answerAt: 0,
      deadline: 0,
      revealEndsAt: 0,
      answers: new Map(),
      lastReveal: null,
      scores: new Map(players.map((p) => [p, 0])),
      perfect: new Map(players.map((p) => [p, 0])),
    };
    startRound(s, now);
    return s;
  },

  onAction(s, playerId, raw, now): ActionResult {
    const a = raw as MemoryAction;
    if (!s.players.includes(playerId)) return { ok: false, code: 'not_in_match' };
    if (!a || typeof a !== 'object' || typeof a.kind !== 'string') return { ok: false, code: 'bad_action' };
    if (a.round !== s.index + 1) return { ok: false, code: 'not_accepting' };
    // Answers are only accepted in the answer window, never while the content is visible.
    if ((s.stage !== 'answer' && s.stage !== 'show') || now > s.deadline) return { ok: false, code: 'not_accepting' };
    if (now < s.answerAt) return { ok: false, code: 'too_early' };
    const r = s.rounds[s.index]!;
    const prev = s.answers.get(playerId);
    if (prev?.done) return { ok: false, code: 'already_answered' };
    const cells = r.mode === 'sequence' ? 0 : r.grid.length;

    if (a.kind === 'pick' && r.mode !== 'sequence') {
      if (!Number.isInteger(a.cell) || a.cell < 0 || a.cell >= cells) return { ok: false, code: 'bad_cell' };
      const items = [...(prev?.items ?? []), a.cell];
      const done = items.length >= r.answer.length;
      s.answers.set(playerId, { items, elapsedMs: elapsedFor(s, raw, now), done });
      return { ok: true };
    }
    if (a.kind === 'sequence' && r.mode === 'sequence') {
      if (!Array.isArray(a.items) || a.items.length > r.answer.length) return { ok: false, code: 'bad_sequence' };
      if (!a.items.every((n) => Number.isInteger(n) && n >= 0 && n < MEMORY_SEQUENCE_PADS)) return { ok: false, code: 'bad_sequence' };
      s.answers.set(playerId, { items: a.items.slice(), elapsedMs: elapsedFor(s, raw, now), done: true });
      return { ok: true };
    }
    return { ok: false, code: 'bad_action' };
  },

  tick(s, now, active) {
    for (let guard = 0; guard < 4; guard++) {
      if (s.stage === 'show') {
        if (now < s.hideAt) return;
        s.stage = 'answer';
      } else if (s.stage === 'answer') {
        const here = s.players.filter((p) => active.has(p));
        const allDone = here.length > 0 && here.every((p) => s.answers.get(p)?.done);
        if (now < s.deadline && !(allDone && now >= s.answerAt)) return;
        closeRound(s, now);
      } else if (s.stage === 'reveal') {
        if (now < s.revealEndsAt) return;
        if (s.index + 1 >= s.rounds.length) {
          s.stage = 'finished';
          return;
        }
        s.index++;
        startRound(s, now);
      } else return;
    }
  },

  botPlan(s, botId, rng, skill) {
    if (s.stage !== 'show' && s.stage !== 'answer') return null;
    const r = s.rounds[s.index]!;
    const a = s.answers.get(botId);
    if (a?.done) return null;
    const step = a?.items.length ?? 0;
    const window = r.answerSeconds * 1000;
    const at = s.answerAt + 1200 + step * 900 + Math.floor(rng.next() * window * 0.5);
    if (r.mode === 'sequence') {
      // Remembers a prefix that grows with skill, then guesses.
      const keep = Math.round(r.answer.length * Math.min(1, skill + rng.next() * 0.3));
      const items = r.answer.map((n, i) => (i < keep ? n : (n + 1 + rng.int(MEMORY_SEQUENCE_PADS - 1)) % MEMORY_SEQUENCE_PADS));
      return { key: `${s.index}:seq`, at, action: { kind: 'sequence', round: s.index + 1, items, clientElapsedMs: at - s.answerAt } };
    }
    const right = rng.next() < skill;
    const target = r.answer[step]!;
    const cell = right ? target : (target + 1 + rng.int(r.grid.length - 1)) % r.grid.length;
    return { key: `${s.index}:${step}`, at, action: { kind: 'pick', round: s.index + 1, cell, clientElapsedMs: at - s.answerAt } };
  },

  nextWakeAt(s) {
    if (s.stage === 'show') return s.hideAt;
    if (s.stage === 'answer') return s.deadline;
    if (s.stage === 'reveal') return s.revealEndsAt;
    return null;
  },

  viewFor(s, viewer): MemoryView {
    const r = s.rounds[s.index];
    const finished = s.stage === 'finished';
    const showing = s.stage === 'show';
    const revealing = s.stage === 'reveal';
    const answering = s.stage === 'answer';
    const round: MemoryRoundView | null =
      r && !finished
        ? {
            round: s.index + 1,
            total: s.rounds.length,
            mode: r.mode,
            showAt: s.showAt,
            hideAt: s.hideAt,
            answerAt: s.answerAt,
            deadline: s.deadline,
            columns: r.columns,
            cells: r.grid.length,
            grid: r.mode !== 'sequence' && (showing || revealing) ? r.grid : null,
            sequence: r.mode === 'sequence' && (showing || revealing) ? r.sequence : null,
            stepMs: r.stepMs,
            length: r.mode === 'sequence' ? r.sequence.length : r.answer.length,
            targets: r.mode === 'cards' && (answering || revealing) ? r.targets : null,
            changedGrid: r.mode === 'spot' && (answering || revealing) ? r.changedGrid : null,
          }
        : null;
    const done = [...s.answers.values()].filter((a) => a.done).length;
    return {
      stage: s.stage,
      round,
      yourAnswer: s.answers.get(viewer)?.items ?? [],
      youDone: s.answers.get(viewer)?.done ?? false,
      doneCount: finished ? 0 : done,
      reveal: revealing ? s.lastReveal : null,
      scores: Object.fromEntries(s.scores),
      final: finished ? { ranking: ranking(s) } : null,
    };
  },

  isFinished(s) {
    return s.stage === 'finished';
  },

  results(s): GameResults {
    const max = s.rounds.length * (MEMORY_TIMING.fullPoints + MEMORY_TIMING.maxSpeedBonus);
    return {
      ranking: ranking(s),
      performance: Object.fromEntries(s.players.map((p) => [p, max > 0 ? (s.scores.get(p) ?? 0) / max : 0])),
    };
  },
};
