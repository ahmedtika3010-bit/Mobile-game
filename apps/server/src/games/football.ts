/**
 * Football Challenges (تحديات الكورة).
 *
 * Rules (finalized for this build; numbers are configurable defaults):
 * - Five modes (see @sahra/shared football.ts). Quick Play and ranked mix
 *   all five in a balanced rotation so one queue serves every mode; private
 *   rooms may pick a single mode, a difficulty, and the 1v1 Duel format.
 * - Everyone sees the same items in the same order at a common server time,
 *   with choices shuffled once per match (like the quiz).
 * - Instant modes: 100 points for a right answer plus up to 50 for speed,
 *   counted in whole-second buckets.
 * - Progressive modes (player clues, career path): lines appear on a fixed
 *   server schedule. The bonus is 50 × (share of lines still hidden when you
 *   answered), so knowing it from the first clue pays most. Lines not yet
 *   shown are never sent to clients.
 * - Duel (private, exactly two players): each question goes to the player
 *   with more points on it; most questions won wins, total points break ties.
 * - Items carry `asOf` dates and name seasons/years in the question, so
 *   later transfers never make a stored answer wrong.
 */
import type { Difficulty, FootballAction, FootballCard, FootballLine, FootballMode, FootballView, MatchMode } from '@sahra/shared';
import { FOOTBALL_MODES, FOOTBALL_PROGRESSIVE } from '@sahra/shared';
import { z } from 'zod';
import { type ActionResult, type ContentRow, type GameModule, type GameResults, Rng } from './engine';
import { QUIZ_TIMING, speedBonus } from './quiz';

export const FOOTBALL_TIMING = {
  /** Extra seconds progressive modes get on top of `answerSeconds`. */
  progressiveExtraSec: 8,
  /** Progressive lines are all shown by this share of the answer window. */
  linesDoneShare: 0.6,
  /** Lines visible at the start: player clues / career clubs (half, rounded up). */
  firstPlayerClues: 1,
};

export interface FootballConfig {
  modes: FootballMode | 'mixed';
  difficulty: Difficulty | 'mixed';
  questionCount: number;
  answerSeconds: number;
  duel: boolean;
}

const DIFFICULTY_RANK: Record<string, number> = { easy: 0, medium: 1, hard: 2 };

const STANDARD_CONFIG: FootballConfig = { modes: 'mixed', difficulty: 'mixed', questionCount: 10, answerSeconds: 15, duel: false };

const configSchema = z.object({
  modes: z.union([z.enum(FOOTBALL_MODES as [FootballMode, ...FootballMode[]]), z.literal('mixed')]).default('mixed'),
  difficulty: z.enum(['easy', 'medium', 'hard', 'mixed']).default('mixed'),
  questionCount: z.number().int().min(5).max(15).default(10),
  answerSeconds: z.number().int().min(10).max(30).default(15),
  duel: z.boolean().default(false),
});

const name = z.string().trim().min(1).max(40);
const common = {
  answer: name,
  wrong: z.array(name).length(3),
  /** YYYY-MM-DD: the facts are correct as of this date. */
  asOf: z.string().date(),
  explanation: z.string().trim().max(160).optional(),
};

export const footballPayloadSchema = z
  .discriminatedUnion('mode', [
    z.object({ mode: z.literal('player'), clues: z.array(z.string().trim().min(4).max(110)).min(3).max(4), ...common }),
    z.object({
      mode: z.literal('career'),
      path: z.array(z.tuple([name, z.string().trim().min(4).max(20)])).min(3).max(10),
      ...common,
    }),
    z.object({ mode: z.literal('shared'), clubs: z.array(name).min(2).max(3), ...common }),
    z.object({
      mode: z.literal('transfer'),
      from: name,
      to: name,
      when: z.string().trim().min(4).max(30),
      fee: z.string().trim().max(40).optional(),
      ...common,
    }),
    z.object({
      mode: z.literal('history'),
      prompt: z.string().trim().min(10).max(160),
      when: z.string().trim().min(4).max(30).optional(),
      ...common,
    }),
  ])
  .refine((p) => new Set([p.answer, ...p.wrong]).size === 4, { message: 'duplicate choices' });

export type FootballPayload = z.infer<typeof footballPayloadSchema>;

export interface FootballItem {
  id: string;
  mode: FootballMode;
  difficulty: string;
  prompt: string;
  lines: FootballLine[];
  /** How many lines show at the start (all of them for instant modes). */
  shownAtStart: number;
  when: string | null;
  detail: string | null;
  asOf: string;
  answer: string;
  explanation: string | null;
  choices: string[];
  correct: number;
}

export function parseFootballContent(row: ContentRow): (Omit<FootballItem, 'choices' | 'correct'> & { wrong: string[] }) | null {
  const parsed = footballPayloadSchema.safeParse(row.payload);
  if (!parsed.success || parsed.data.mode !== row.category) return null;
  const p = parsed.data;
  const base = {
    id: row.id,
    mode: p.mode,
    difficulty: row.difficulty,
    asOf: p.asOf,
    answer: p.answer,
    wrong: p.wrong,
    explanation: p.explanation ?? null,
    prompt: '',
    when: null as string | null,
    detail: null as string | null,
  };
  switch (p.mode) {
    case 'player':
      return { ...base, lines: p.clues.map((text) => ({ text, sub: null })), shownAtStart: FOOTBALL_TIMING.firstPlayerClues };
    case 'career':
      return { ...base, lines: p.path.map(([text, sub]) => ({ text, sub })), shownAtStart: Math.ceil(p.path.length / 2) };
    case 'shared':
      return { ...base, lines: p.clubs.map((text) => ({ text, sub: null })), shownAtStart: p.clubs.length };
    case 'transfer':
      return {
        ...base,
        lines: [{ text: p.from, sub: 'from' }, { text: p.to, sub: 'to' }],
        shownAtStart: 2,
        when: p.when,
        detail: p.fee ?? null,
      };
    case 'history':
      return { ...base, prompt: p.prompt, lines: [], shownAtStart: 0, when: p.when ?? null };
  }
}

/**
 * Picks the match's items. Mixed matches rotate through the modes in a
 * shuffled order so every mode gets an equal share, then order the picks
 * easy to hard so the match builds up.
 */
export function pickItems<T extends { mode: FootballMode; difficulty: string }>(all: T[], config: FootballConfig, rng: Rng): T[] {
  // A chosen difficulty comes first; nearby difficulties only top up a thin bank.
  const target = config.difficulty === 'mixed' ? null : DIFFICULTY_RANK[config.difficulty]!;
  const distance = (i: T) => (target === null ? 0 : Math.abs((DIFFICULTY_RANK[i.difficulty] ?? 1) - target));
  const items = all.map((item, i) => ({ item, i })).sort((a, b) => distance(a.item) - distance(b.item) || a.i - b.i).map((x) => x.item);
  if (config.modes !== 'mixed') return items.filter((i) => i.mode === config.modes).slice(0, config.questionCount);
  const pools = new Map<FootballMode, T[]>(FOOTBALL_MODES.map((m) => [m, items.filter((i) => i.mode === m)]));
  const order = rng.shuffle(FOOTBALL_MODES.slice());
  const picked: T[] = [];
  while (picked.length < config.questionCount && [...pools.values()].some((p) => p.length > 0)) {
    for (const m of order) {
      const next = pools.get(m)!.shift();
      if (next && picked.length < config.questionCount) picked.push(next);
    }
  }
  if (config.difficulty !== 'mixed') return picked;
  return picked
    .map((item, i) => ({ item, i }))
    .sort((a, b) => (DIFFICULTY_RANK[a.item.difficulty] ?? 1) - (DIFFICULTY_RANK[b.item.difficulty] ?? 1) || a.i - b.i)
    .map((x) => x.item);
}

interface Answer {
  choice: number;
  elapsedMs: number;
}

export interface FootballState {
  players: string[];
  config: FootballConfig;
  items: FootballItem[];
  index: number;
  stage: 'question' | 'reveal' | 'finished';
  revealAt: number;
  deadline: number;
  revealEndsAt: number;
  /** Progressive modes: ms between new lines (0 for instant modes). */
  lineGapMs: number;
  answers: Map<string, Answer>[];
  scores: Map<string, number>;
  correct: Map<string, number>;
  wins: Map<string, number>;
  lastPoints: Record<string, number>;
  lastWinner: string | null;
  /** Last time the room advanced the clock (to schedule the next line). */
  lastTick: number;
}

const isProgressive = (m: FootballMode) => FOOTBALL_PROGRESSIVE.includes(m);

export function windowSeconds(item: FootballItem, config: FootballConfig) {
  return config.answerSeconds + (isProgressive(item.mode) ? FOOTBALL_TIMING.progressiveExtraSec : 0);
}

/** Lines visible `elapsedMs` after the question appeared. */
export function linesShownAt(item: FootballItem, lineGapMs: number, elapsedMs: number) {
  if (lineGapMs <= 0) return item.lines.length;
  return Math.min(item.lines.length, item.shownAtStart + Math.floor(Math.max(0, elapsedMs) / lineGapMs));
}

/** Points for a right answer: 100 plus the speed or early-clue bonus. */
export function footballPoints(item: FootballItem, lineGapMs: number, elapsedMs: number, config: FootballConfig) {
  const hiddenAtStart = item.lines.length - item.shownAtStart;
  if (!isProgressive(item.mode) || hiddenAtStart <= 0 || lineGapMs <= 0) {
    return QUIZ_TIMING.correctPoints + speedBonus(elapsedMs, windowSeconds(item, config));
  }
  const hidden = item.lines.length - linesShownAt(item, lineGapMs, elapsedMs);
  return QUIZ_TIMING.correctPoints + Math.round((QUIZ_TIMING.maxSpeedBonus * hidden) / hiddenAtStart);
}

function startQuestion(s: FootballState, now: number) {
  const item = s.items[s.index]!;
  const windowMs = windowSeconds(item, s.config) * 1000;
  const hidden = item.lines.length - item.shownAtStart;
  s.stage = 'question';
  s.revealAt = now + QUIZ_TIMING.revealLeadMs;
  s.deadline = s.revealAt + windowMs;
  s.lineGapMs = isProgressive(item.mode) && hidden > 0 ? Math.floor((windowMs * FOOTBALL_TIMING.linesDoneShare) / hidden) : 0;
  s.lastPoints = {};
  s.lastWinner = null;
}

function closeQuestion(s: FootballState, now: number) {
  const item = s.items[s.index]!;
  const answers = s.answers[s.index]!;
  const points: Record<string, number> = {};
  for (const p of s.players) {
    const a = answers.get(p);
    let pts = 0;
    if (a && a.choice === item.correct) {
      pts = footballPoints(item, s.lineGapMs, a.elapsedMs, s.config);
      s.correct.set(p, (s.correct.get(p) ?? 0) + 1);
    }
    points[p] = pts;
    s.scores.set(p, (s.scores.get(p) ?? 0) + pts);
  }
  if (s.config.duel) {
    const [a, b] = s.players as [string, string];
    const pa = points[a] ?? 0;
    const pb = points[b] ?? 0;
    s.lastWinner = pa > pb ? a : pb > pa ? b : null;
    if (s.lastWinner) s.wins.set(s.lastWinner, (s.wins.get(s.lastWinner) ?? 0) + 1);
  }
  s.lastPoints = points;
  s.stage = 'reveal';
  s.revealEndsAt = now + QUIZ_TIMING.revealStageMs;
}

function elapsedFor(s: FootballState, raw: unknown, now: number) {
  const serverElapsed = now - s.revealAt;
  const r = (raw as { clientElapsedMs?: unknown }).clientElapsedMs;
  const reported = typeof r === 'number' && Number.isFinite(r) ? r : serverElapsed;
  return Math.min(serverElapsed, Math.max(reported, serverElapsed - QUIZ_TIMING.maxLatencyCompMs));
}

/** Duel ranking: questions won, then points. Everyone else: points. */
function ranking(s: FootballState) {
  const key = (p: string) => [s.config.duel ? s.wins.get(p) ?? 0 : 0, s.scores.get(p) ?? 0] as const;
  const sorted = s.players.slice().sort((a, b) => {
    const [wa, pa] = key(a);
    const [wb, pb] = key(b);
    return wb - wa || pb - pa;
  });
  let place = 0;
  return sorted.map((p, i) => {
    const prev = sorted[i - 1];
    if (!prev || key(prev)[0] !== key(p)[0] || key(prev)[1] !== key(p)[1]) place = i + 1;
    return { playerId: p, score: s.scores.get(p) ?? 0, place, correct: s.correct.get(p) ?? 0 };
  });
}

export const footballModule: GameModule<FootballState, FootballConfig, FootballView> = {
  id: 'football',
  capabilities: { minPlayers: 2, maxPlayers: 8, ranked: true, safeModeReady: true, spectators: 'none' },

  defaultConfig() {
    return { ...STANDARD_CONFIG };
  },

  validateConfig(raw: unknown, mode: MatchMode): FootballConfig {
    // Quick Play, ranked and practice always mix every mode with the standard profile.
    if (mode !== 'private') return { ...STANDARD_CONFIG };
    const parsed = configSchema.safeParse(raw ?? {});
    return parsed.success ? parsed.data : { ...STANDARD_CONFIG };
  },

  expectedDurationSec(c) {
    const avgWindow = c.answerSeconds + (c.modes === 'mixed' ? 0.4 : FOOTBALL_PROGRESSIVE.includes(c.modes) ? 1 : 0) * FOOTBALL_TIMING.progressiveExtraSec;
    const perQuestion = QUIZ_TIMING.revealLeadMs / 1000 + avgWindow * 0.6 + QUIZ_TIMING.revealStageMs / 1000;
    return Math.round(c.questionCount * perQuestion);
  },

  contentRequest(c) {
    // Every difficulty is fetched so a thin difficulty can be topped up (see pickItems).
    return { gameId: 'football', count: 300, category: c.modes, difficulty: 'mixed' };
  },

  setup(players, config, content, rng, now) {
    if (config.duel && players.length !== 2) throw new Error('duel_needs_two');
    const parsed = content.map(parseFootballContent).filter((q): q is NonNullable<typeof q> => q !== null);
    const items = pickItems(parsed, config, rng).map(({ wrong, ...q }) => {
      const choices = rng.shuffle([q.answer, ...wrong]);
      return { ...q, choices, correct: choices.indexOf(q.answer) };
    });
    if (items.length < Math.min(5, config.questionCount)) throw new Error('not_enough_content');
    const s: FootballState = {
      players: players.slice(),
      config: { ...config, questionCount: items.length },
      items,
      index: 0,
      stage: 'question',
      revealAt: 0,
      deadline: 0,
      revealEndsAt: 0,
      lineGapMs: 0,
      answers: items.map(() => new Map()),
      scores: new Map(players.map((p) => [p, 0])),
      correct: new Map(players.map((p) => [p, 0])),
      wins: new Map(players.map((p) => [p, 0])),
      lastPoints: {},
      lastWinner: null,
      lastTick: now,
    };
    startQuestion(s, now);
    return s;
  },

  onAction(s, playerId, raw, now): ActionResult {
    const a = raw as FootballAction;
    if (!s.players.includes(playerId)) return { ok: false, code: 'not_in_match' };
    if (!a || typeof a !== 'object' || a.kind !== 'answer') return { ok: false, code: 'bad_action' };
    if (s.stage !== 'question' || a.questionIndex !== s.index) return { ok: false, code: 'not_accepting' };
    if (now < s.revealAt) return { ok: false, code: 'too_early' };
    if (now > s.deadline) return { ok: false, code: 'too_late' };
    const item = s.items[s.index]!;
    if (!Number.isInteger(a.choice) || a.choice < 0 || a.choice >= item.choices.length) return { ok: false, code: 'bad_choice' };
    const answers = s.answers[s.index]!;
    if (answers.has(playerId)) return { ok: false, code: 'already_answered' };
    answers.set(playerId, { choice: a.choice, elapsedMs: elapsedFor(s, raw, now) });
    return { ok: true };
  },

  tick(s, now, activePlayers) {
    s.lastTick = now;
    if (s.stage === 'question') {
      const answers = s.answers[s.index]!;
      const everyoneActiveAnswered = activePlayers.size > 0 && [...activePlayers].every((p) => !s.players.includes(p) || answers.has(p));
      if (now >= s.deadline || (now >= s.revealAt && everyoneActiveAnswered)) closeQuestion(s, now);
    } else if (s.stage === 'reveal' && now >= s.revealEndsAt) {
      if (s.index + 1 >= s.items.length) {
        s.stage = 'finished';
      } else {
        s.index += 1;
        startQuestion(s, now);
      }
    }
  },

  botPlan(s, botId, rng, skill) {
    if (s.stage !== 'question' || s.answers[s.index]!.has(botId)) return null;
    const item = s.items[s.index]!;
    const window = windowSeconds(item, s.config) * 1000;
    const min = QUIZ_TIMING.botMinDelayMs;
    const at = s.revealAt + min + Math.floor(rng.next() * Math.max(1, window * QUIZ_TIMING.botMaxShare - min));
    // On progressive questions, bots that wait for more clues are more often right.
    const shown = linesShownAt(item, s.lineGapMs, at - s.revealAt);
    const boost = isProgressive(item.mode) && item.lines.length > 0 ? 0.25 * (shown / item.lines.length) : 0;
    const right = rng.next() < Math.min(0.95, skill + boost);
    const wrong = item.choices.map((_, i) => i).filter((i) => i !== item.correct);
    const choice = right || wrong.length === 0 ? item.correct : wrong[rng.int(wrong.length)]!;
    return { key: String(s.index), at, action: { kind: 'answer', questionIndex: s.index, choice, clientElapsedMs: at - s.revealAt } };
  },

  nextWakeAt(s) {
    if (s.stage === 'question') {
      const item = s.items[s.index]!;
      if (s.lineGapMs > 0) {
        // Wake for each new line so every client gets it at the same time.
        const shown = linesShownAt(item, s.lineGapMs, s.lastTick - s.revealAt);
        if (shown < item.lines.length) return Math.min(s.deadline, s.revealAt + (shown - item.shownAtStart + 1) * s.lineGapMs);
      }
      return s.deadline;
    }
    if (s.stage === 'reveal') return s.revealEndsAt;
    return null;
  },

  viewFor(s, viewer, now): FootballView {
    const item = s.items[s.index];
    const answers = s.answers[s.index];
    const finished = s.stage === 'finished';
    let card: FootballCard | null = null;
    if (item && !finished) {
      const shown = s.stage === 'reveal' ? item.lines.length : now < s.revealAt ? item.shownAtStart : linesShownAt(item, s.lineGapMs, now - s.revealAt);
      const next = shown < item.lines.length && s.lineGapMs > 0 ? s.revealAt + (shown - item.shownAtStart + 1) * s.lineGapMs : null;
      card = {
        mode: item.mode,
        lines: item.lines.slice(0, shown),
        totalLines: item.lines.length,
        nextLineAt: next,
        when: item.when,
        detail: item.detail,
        asOf: item.asOf,
      };
    }
    return {
      stage: s.stage,
      question:
        item && card
          ? {
              index: s.index,
              total: s.items.length,
              category: item.mode,
              prompt: item.prompt,
              choices: item.choices,
              revealAt: s.revealAt,
              deadline: s.deadline,
              football: card,
            }
          : null,
      yourChoice: answers?.get(viewer)?.choice ?? null,
      answeredCount: answers?.size ?? 0,
      // The answer is only included after the question closes.
      reveal:
        s.stage === 'reveal' && item
          ? {
              index: s.index,
              correctChoice: item.correct,
              answer: item.answer,
              explanation: item.explanation,
              points: s.lastPoints,
              picks: Object.fromEntries([...(answers ?? new Map())].map(([p, a]) => [p, a.choice])),
              winner: s.lastWinner,
            }
          : null,
      scores: Object.fromEntries(s.scores),
      duel: s.config.duel ? { wins: Object.fromEntries(s.wins) } : null,
      final: finished ? { ranking: ranking(s), ratingApplied: false } : null,
    };
  },

  isFinished(s) {
    return s.stage === 'finished';
  },

  results(s): GameResults {
    const max = s.items.length * (QUIZ_TIMING.correctPoints + QUIZ_TIMING.maxSpeedBonus);
    const performance = Object.fromEntries(s.players.map((p) => [p, max > 0 ? (s.scores.get(p) ?? 0) / max : 0]));
    return { ranking: ranking(s), performance };
  },
};
