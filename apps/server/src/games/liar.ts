/**
 * Who Is the Liar? (مين الكداب؟), a hidden-role game with question pairs.
 *
 * Rules (finalized for this build; timings and points are configurable defaults):
 * - Several rounds. Each round one player is the liar: they get the "odd"
 *   question of a reviewed pair, everyone else gets the main question. Nobody
 *   is told who the liar is, not even the liar, until the answers are shown.
 * - Answer: everyone privately picks one of the pair's approved options.
 * - Discussion: the main question and every answer are shown to all. The
 *   liar now sees that their question was different. Players mark suspects
 *   (public) and use approved phrases; it ends early when everyone is ready.
 * - Vote: anonymous, one vote each, no self votes; only totals are shown.
 *   A single top-voted player is accused; a tie accuses nobody.
 * - Points: the liar is caught → everyone who voted for them gets 100.
 *   The liar survives (wrong accusation or tie) → the liar gets 150.
 * - The liar role rotates: each round picks among the players who have been
 *   the liar the fewest times.
 * - Difficulty (private rooms) = how similar the two questions are.
 *   Public matches use the standard config (medium).
 *
 * Secrets: the odd question and the liar's identity are never sent to anyone
 * before the round ends; the main question is not sent to the liar before the
 * discussion; votes are only sent as totals.
 */
import type { LiarAction, LiarDifficulty, LiarRoundResult, LiarStage, LiarView, MatchMode } from '@sahra/shared';
import { LIAR_DIFFICULTIES } from '@sahra/shared';
import { z } from 'zod';
import { type ActionResult, type ContentRow, type GameModule, type GameResults, Rng, placesFromScores } from './engine';

export const LIAR_TIMING = { roundEndMs: 8000 };
export const LIAR_POINTS = { caughtVote: 100, liarSurvived: 150 };

export interface LiarConfig {
  difficulty: LiarDifficulty;
  rounds: number;
  answerSeconds: number;
  discussSeconds: number;
  voteSeconds: number;
}

const STANDARD_CONFIG: LiarConfig = { difficulty: 'medium', rounds: 3, answerSeconds: 25, discussSeconds: 45, voteSeconds: 20 };

const configSchema = z.object({
  difficulty: z.enum(LIAR_DIFFICULTIES as [LiarDifficulty, ...LiarDifficulty[]]).default('medium'),
  rounds: z.number().int().min(1).max(6).default(3),
  answerSeconds: z.number().int().min(10).max(45).default(25),
  discussSeconds: z.number().int().min(15).max(120).default(45),
  voteSeconds: z.number().int().min(10).max(45).default(20),
});

const pairSchema = z.object({
  main: z.string().trim().min(4),
  odd: z.string().trim().min(4),
  options: z.array(z.string().trim().min(1)).min(3).max(6),
});

export interface LiarPair {
  id: string;
  main: string;
  odd: string;
  options: string[];
}

export function parseLiarPair(row: ContentRow): LiarPair | null {
  const p = pairSchema.safeParse(row.payload);
  if (!p.success || p.data.main === p.data.odd) return null;
  if (new Set(p.data.options).size !== p.data.options.length) return null;
  return { id: row.id, ...p.data };
}

export interface LiarState {
  players: string[];
  config: LiarConfig;
  rng: Rng;
  pairs: LiarPair[];
  round: number; // 0-based
  liar: string;
  liarCount: Map<string, number>;
  stage: LiarStage;
  stageEndsAt: number;
  answers: Map<string, number>;
  suspicions: Map<string, string>;
  ready: Set<string>;
  votes: Map<string, string>;
  scores: Map<string, number>;
  history: LiarRoundResult[];
}

function pickLiar(s: LiarState): string {
  const fewest = Math.min(...s.players.map((p) => s.liarCount.get(p) ?? 0));
  const pool = s.players.filter((p) => (s.liarCount.get(p) ?? 0) === fewest);
  const liar = pool[s.rng.int(pool.length)]!;
  s.liarCount.set(liar, (s.liarCount.get(liar) ?? 0) + 1);
  return liar;
}

function startRound(s: LiarState, round: number, now: number) {
  s.round = round;
  s.liar = pickLiar(s);
  s.answers.clear();
  s.suspicions.clear();
  s.ready.clear();
  s.votes.clear();
  s.stage = 'answer';
  s.stageEndsAt = now + s.config.answerSeconds * 1000;
}

function voteCounts(s: LiarState): Record<string, number> {
  const counts: Record<string, number> = Object.fromEntries(s.players.map((p) => [p, 0]));
  for (const t of s.votes.values()) counts[t] = (counts[t] ?? 0) + 1;
  return counts;
}

function closeVote(s: LiarState, now: number) {
  const counts = voteCounts(s);
  const max = Math.max(0, ...Object.values(counts));
  const leaders = Object.keys(counts).filter((p) => counts[p] === max);
  const accused = max > 0 && leaders.length === 1 ? leaders[0]! : null;
  const caught = accused === s.liar;
  const points: Record<string, number> = Object.fromEntries(s.players.map((p) => [p, 0]));
  if (caught) {
    for (const [voter, target] of s.votes) if (target === s.liar) points[voter] = LIAR_POINTS.caughtVote;
  } else {
    points[s.liar] = LIAR_POINTS.liarSurvived;
  }
  for (const p of s.players) s.scores.set(p, (s.scores.get(p) ?? 0) + points[p]!);
  const pair = s.pairs[s.round]!;
  s.history.push({ round: s.round + 1, liar: s.liar, mainQuestion: pair.main, oddQuestion: pair.odd, voteCounts: counts, accused, caught, points });
  if (s.round + 1 >= s.config.rounds) {
    s.stage = 'finished';
    s.stageEndsAt = 0;
  } else {
    s.stage = 'roundEnd';
    s.stageEndsAt = now + LIAR_TIMING.roundEndMs;
  }
}

/** One time-based transition; returns true if the state changed. */
function step(s: LiarState, now: number, active: ReadonlySet<string>): boolean {
  const allActive = (set: { has(p: string): boolean }) => {
    const here = s.players.filter((p) => active.has(p));
    return here.length > 0 && here.every((p) => set.has(p));
  };
  switch (s.stage) {
    case 'answer':
      if (now < s.stageEndsAt && !allActive(s.answers)) return false;
      s.stage = 'discuss';
      s.stageEndsAt = now + s.config.discussSeconds * 1000;
      return true;
    case 'discuss':
      if (now < s.stageEndsAt && !allActive(s.ready)) return false;
      s.stage = 'vote';
      s.stageEndsAt = now + s.config.voteSeconds * 1000;
      return true;
    case 'vote':
      if (now < s.stageEndsAt && !allActive(s.votes)) return false;
      closeVote(s, now);
      return true;
    case 'roundEnd':
      if (now < s.stageEndsAt) return false;
      startRound(s, s.round + 1, now);
      return true;
    default:
      return false;
  }
}

export const liarModule: GameModule<LiarState, LiarConfig, LiarView> = {
  id: 'liar',
  // Ranked stays off until the rules are playtested for fairness.
  capabilities: { minPlayers: 3, maxPlayers: 8, ranked: false, safeModeReady: true, spectators: 'none' },

  defaultConfig() {
    return { ...STANDARD_CONFIG };
  },

  validateConfig(raw: unknown, mode: MatchMode): LiarConfig {
    if (mode !== 'private') return { ...STANDARD_CONFIG };
    const parsed = configSchema.safeParse(raw ?? {});
    return parsed.success ? parsed.data : { ...STANDARD_CONFIG };
  },

  expectedDurationSec(c) {
    const perRound = c.answerSeconds * 0.7 + c.discussSeconds * 0.8 + c.voteSeconds * 0.7 + LIAR_TIMING.roundEndMs / 1000;
    return Math.round(c.rounds * perRound);
  },

  contentRequest(c) {
    return { gameId: 'liar', count: c.rounds + 4, category: 'mixed', difficulty: c.difficulty };
  },

  setup(players, config, content, rng, now) {
    const pairs = content.map(parseLiarPair).filter((p): p is LiarPair => p !== null).slice(0, config.rounds);
    if (pairs.length < config.rounds) throw new Error('not_enough_content');
    const s: LiarState = {
      players: players.slice(),
      config: { ...config },
      rng,
      pairs,
      round: 0,
      liar: '',
      liarCount: new Map(),
      stage: 'answer',
      stageEndsAt: 0,
      answers: new Map(),
      suspicions: new Map(),
      ready: new Set(),
      votes: new Map(),
      scores: new Map(players.map((p) => [p, 0])),
      history: [],
    };
    startRound(s, 0, now);
    return s;
  },

  onAction(s, playerId, raw, _now): ActionResult {
    const a = raw as LiarAction;
    if (!s.players.includes(playerId)) return { ok: false, code: 'not_in_match' };
    if (!a || typeof a !== 'object' || typeof a.kind !== 'string') return { ok: false, code: 'bad_action' };
    switch (a.kind) {
      case 'answer': {
        if (s.stage !== 'answer' || a.round !== s.round + 1) return { ok: false, code: 'not_accepting' };
        if (s.answers.has(playerId)) return { ok: false, code: 'already_answered' };
        const n = s.pairs[s.round]!.options.length;
        if (!Number.isInteger(a.choice) || a.choice < 0 || a.choice >= n) return { ok: false, code: 'bad_choice' };
        s.answers.set(playerId, a.choice);
        return { ok: true };
      }
      case 'suspect': {
        if (s.stage !== 'discuss') return { ok: false, code: 'not_accepting' };
        if (a.target === null) {
          s.suspicions.delete(playerId);
          return { ok: true };
        }
        if (a.target === playerId || !s.players.includes(a.target)) return { ok: false, code: 'bad_target' };
        s.suspicions.set(playerId, a.target);
        return { ok: true };
      }
      case 'readyToVote':
        if (s.stage !== 'discuss') return { ok: false, code: 'not_accepting' };
        s.ready.add(playerId);
        return { ok: true };
      case 'vote':
        if (s.stage !== 'vote') return { ok: false, code: 'not_accepting' };
        if (s.votes.has(playerId)) return { ok: false, code: 'already_voted' };
        if (a.target === playerId || !s.players.includes(a.target)) return { ok: false, code: 'bad_target' };
        s.votes.set(playerId, a.target);
        return { ok: true };
      default:
        return { ok: false, code: 'bad_action' };
    }
  },

  tick(s, now, activePlayers) {
    for (let guard = 0; guard < 8 && step(s, now, activePlayers); guard++);
  },

  nextWakeAt(s) {
    return s.stage === 'finished' ? null : s.stageEndsAt;
  },

  viewFor(s, viewer): LiarView {
    const inMatch = s.players.includes(viewer);
    const pair = s.pairs[s.round]!;
    const revealed = s.stage !== 'answer';
    const roundOver = s.stage === 'roundEnd' || s.stage === 'finished';
    const finished = s.stage === 'finished';
    return {
      stage: s.stage,
      stageEndsAt: s.stageEndsAt,
      round: s.round + 1,
      rounds: s.config.rounds,
      difficulty: s.config.difficulty,
      yourQuestion: inMatch ? (viewer === s.liar ? pair.odd : pair.main) : null,
      mainQuestion: revealed ? pair.main : null,
      options: pair.options,
      yourAnswer: s.answers.get(viewer) ?? null,
      answeredCount: s.answers.size,
      answers: revealed ? Object.fromEntries(s.players.map((p) => [p, s.answers.get(p) ?? null])) : null,
      youAreLiar: revealed && inMatch ? viewer === s.liar : null,
      suspicions: s.stage === 'discuss' || s.stage === 'vote' ? Object.fromEntries(s.suspicions) : {},
      readyCount: s.ready.size,
      youReady: s.ready.has(viewer),
      yourVote: s.votes.get(viewer) ?? null,
      votedCount: s.votes.size,
      scores: Object.fromEntries(s.scores),
      lastRound: roundOver ? s.history[s.history.length - 1] ?? null : null,
      final: finished
        ? { rounds: s.history, ranking: placesFromScores(s.players.map((p) => ({ playerId: p, score: s.scores.get(p) ?? 0 }))) }
        : null,
    };
  },

  isFinished(s) {
    return s.stage === 'finished';
  },

  results(s): GameResults {
    const ranking = placesFromScores(s.players.map((p) => ({ playerId: p, score: s.scores.get(p) ?? 0 })));
    const best = LIAR_POINTS.liarSurvived * Math.max(1, Math.ceil(s.config.rounds / Math.max(1, s.players.length))) +
      LIAR_POINTS.caughtVote * s.config.rounds;
    const performance = Object.fromEntries(s.players.map((p) => [p, Math.min(1, (s.scores.get(p) ?? 0) / best)]));
    return { ranking, performance };
  },
};
