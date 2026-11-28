/**
 * Spy (الجاسوس), a social deduction game.
 *
 * Rules (finalized for this build; timings are configurable defaults):
 * - Everyone gets the same secret word from one category, except the spies,
 *   who only see the category. 1 spy by default; hosts may pick 2 when there
 *   are at least 7 players. Quick play always uses 1.
 * - Question turns: each player asks once per round. The asker picks one of
 *   four approved questions for the category and a target; the target answers
 *   on an approved five-step scale. Everyone sees every question and answer.
 * - Discussion: players mark who they suspect (public) and use approved
 *   phrases; it ends early when everyone is ready to vote.
 * - Vote: anonymous, one vote each, no self votes. Only the totals are shown.
 *   A single top-voted player is accused; a tie accuses nobody.
 * - Outcome:
 *   - Accused is a spy: that spy gets one guess at the word. Right → spies win,
 *     wrong or no guess → citizens win.
 *   - Accused is a citizen, or nobody: spies win.
 *   - Before the vote, a spy may name the word at any time: right → spies win
 *     at once, wrong → citizens win at once.
 * - Points: winners 100 (spies 150, +50 more when they named the word);
 *   every citizen who voted for a spy gets +50 even if their team lost.
 *
 * Secrets: the word is never sent to spies, spy identities are never sent
 * before the end, and players outside the match get no game view at all.
 */
import type {
  MatchMode,
  SpyAction,
  SpyCategory,
  SpyEndReason,
  SpyFinal,
  SpyHistoryEntry,
  SpyStage,
  SpyView,
  SpyWinner,
} from '@sahra/shared';
import { SPY_ANSWERS, SPY_CATEGORIES } from '@sahra/shared';
import { z } from 'zod';
import { type ActionResult, type ContentRow, type GameModule, type GameResults, Rng, placesFromScores } from './engine';

export const SPY_TIMING = {
  rolesMs: 7000,
  showAnswerMs: 3500,
  guessMs: 20000,
  questionOptions: 4,
  guessOptions: 10,
};

export const SPY_POINTS = { citizenWin: 100, spyWin: 150, spyGuessBonus: 50, goodVoteBonus: 50 };

export interface SpyConfig {
  category: SpyCategory | 'mixed';
  spies: number;
  rounds: number;
  askSeconds: number;
  answerSeconds: number;
  discussSeconds: number;
  voteSeconds: number;
}

const STANDARD_CONFIG: SpyConfig = {
  category: 'mixed',
  spies: 1,
  rounds: 1,
  askSeconds: 20,
  answerSeconds: 15,
  discussSeconds: 45,
  voteSeconds: 25,
};

const configSchema = z.object({
  category: z.union([z.enum(SPY_CATEGORIES as [SpyCategory, ...SpyCategory[]]), z.literal('mixed')]).default('mixed'),
  spies: z.number().int().min(1).max(2).default(1),
  rounds: z.number().int().min(1).max(2).default(1),
  askSeconds: z.number().int().min(10).max(40).default(20),
  answerSeconds: z.number().int().min(8).max(30).default(15),
  discussSeconds: z.number().int().min(15).max(120).default(45),
  voteSeconds: z.number().int().min(15).max(45).default(25),
});

const packSchema = z.object({
  words: z.array(z.string().min(1)).min(8),
  questions: z.array(z.string().min(1)).min(6),
});

export interface SpyPack {
  id: string;
  category: SpyCategory;
  words: string[];
  questions: string[];
}

export function parseSpyPack(row: ContentRow): SpyPack | null {
  const p = packSchema.safeParse(row.payload);
  if (!p.success || !SPY_CATEGORIES.includes(row.category as SpyCategory)) return null;
  const words = [...new Set(p.data.words.map((w) => w.trim()))];
  if (words.length < 8) return null;
  return { id: row.id, category: row.category as SpyCategory, words, questions: p.data.questions };
}

/** Most spies allowed for a player count: 1, or 2 from 7 players. */
export function maxSpies(players: number) {
  return players >= 7 ? 2 : 1;
}

interface Turn {
  asker: string;
  target: string | null;
  /** Indices into state.questions offered to the asker. */
  options: number[];
  question: number | null;
  answer: number | null;
  closed: boolean;
}

export interface SpyState {
  players: string[];
  config: SpyConfig;
  rng: Rng;
  category: SpyCategory;
  packId: string;
  word: string;
  wordOptions: string[];
  spies: Set<string>;
  questions: string[];
  used: Set<number>;
  turns: Turn[];
  turnIndex: number;
  stage: SpyStage;
  stageEndsAt: number;
  suspicions: Map<string, string>;
  ready: Set<string>;
  votes: Map<string, string>;
  guesser: string | null;
  final: SpyFinal | null;
  scores: Map<string, number>;
}

function offerQuestions(s: SpyState): number[] {
  const all = s.questions.map((_, i) => i);
  let fresh = all.filter((i) => !s.used.has(i));
  if (fresh.length < SPY_TIMING.questionOptions) {
    s.used.clear();
    fresh = all;
  }
  return s.rng.shuffle(fresh).slice(0, SPY_TIMING.questionOptions);
}

function startTurn(s: SpyState, index: number, now: number) {
  s.turnIndex = index;
  const turn = s.turns[index];
  if (!turn) {
    s.stage = 'discuss';
    s.stageEndsAt = now + s.config.discussSeconds * 1000;
    return;
  }
  turn.options = offerQuestions(s);
  s.stage = 'ask';
  s.stageEndsAt = now + s.config.askSeconds * 1000;
}

function applyAsk(s: SpyState, option: number, target: string, now: number) {
  const turn = s.turns[s.turnIndex]!;
  const q = turn.options[option]!;
  turn.question = q;
  turn.target = target;
  s.used.add(q);
  s.stage = 'answer';
  s.stageEndsAt = now + s.config.answerSeconds * 1000;
}

function closeAnswer(s: SpyState, answer: number | null, now: number) {
  const turn = s.turns[s.turnIndex]!;
  turn.answer = answer;
  turn.closed = true;
  s.stageEndsAt = now + SPY_TIMING.showAnswerMs;
}

function startVote(s: SpyState, now: number) {
  s.stage = 'vote';
  s.stageEndsAt = now + s.config.voteSeconds * 1000;
}

function voteCounts(s: SpyState): Record<string, number> {
  const counts: Record<string, number> = Object.fromEntries(s.players.map((p) => [p, 0]));
  for (const t of s.votes.values()) counts[t] = (counts[t] ?? 0) + 1;
  return counts;
}

function finish(s: SpyState, winner: SpyWinner, reason: SpyEndReason, accused: string | null, guessedWord: string | null) {
  const guessed = reason === 'spy_guessed_early' || reason === 'caught_but_guessed';
  for (const p of s.players) {
    const isSpy = s.spies.has(p);
    let pts = 0;
    if (winner === 'spies' && isSpy) pts += SPY_POINTS.spyWin + (guessed ? SPY_POINTS.spyGuessBonus : 0);
    if (winner === 'citizens' && !isSpy) pts += SPY_POINTS.citizenWin;
    const v = s.votes.get(p);
    if (!isSpy && v && s.spies.has(v)) pts += SPY_POINTS.goodVoteBonus;
    s.scores.set(p, pts);
  }
  s.stage = 'finished';
  s.stageEndsAt = 0;
  s.final = {
    winner,
    reason,
    spies: s.players.filter((p) => s.spies.has(p)),
    word: s.word,
    voteCounts: voteCounts(s),
    accused,
    guessedWord,
    ranking: placesFromScores(s.players.map((p) => ({ playerId: p, score: s.scores.get(p) ?? 0 }))),
  };
}

function closeVote(s: SpyState, now: number) {
  const counts = voteCounts(s);
  const max = Math.max(0, ...Object.values(counts));
  const leaders = Object.keys(counts).filter((p) => counts[p] === max);
  const accused = max > 0 && leaders.length === 1 ? leaders[0]! : null;
  if (accused && s.spies.has(accused)) {
    s.stage = 'guess';
    s.guesser = accused;
    s.stageEndsAt = now + SPY_TIMING.guessMs;
  } else {
    finish(s, 'spies', 'spy_survived', accused, null);
  }
}

/** One time-based transition; returns true if the state changed. */
function step(s: SpyState, now: number, active: ReadonlySet<string>): boolean {
  const gone = (p: string | null) => p !== null && !active.has(p);
  const allActive = (set: { has(p: string): boolean }) => {
    const here = s.players.filter((p) => active.has(p));
    return here.length > 0 && here.every((p) => set.has(p));
  };
  switch (s.stage) {
    case 'roles':
      if (now < s.stageEndsAt) return false;
      startTurn(s, 0, now);
      return true;
    case 'ask': {
      const turn = s.turns[s.turnIndex]!;
      if (now < s.stageEndsAt && !gone(turn.asker)) return false;
      // Time ran out (or the asker dropped): ask a random offered question.
      const others = s.players.filter((p) => p !== turn.asker && active.has(p));
      const pool = others.length ? others : s.players.filter((p) => p !== turn.asker);
      applyAsk(s, s.rng.int(turn.options.length), pool[s.rng.int(pool.length)]!, now);
      return true;
    }
    case 'answer': {
      const turn = s.turns[s.turnIndex]!;
      if (!turn.closed) {
        if (now < s.stageEndsAt && !gone(turn.target)) return false;
        closeAnswer(s, null, now);
        return true;
      }
      if (now < s.stageEndsAt) return false;
      startTurn(s, s.turnIndex + 1, now);
      return true;
    }
    case 'discuss':
      if (now < s.stageEndsAt && !allActive(s.ready)) return false;
      startVote(s, now);
      return true;
    case 'vote':
      if (now < s.stageEndsAt && !allActive(s.votes)) return false;
      closeVote(s, now);
      return true;
    case 'guess':
      if (now < s.stageEndsAt && !gone(s.guesser)) return false;
      finish(s, 'citizens', 'caught', s.guesser, null);
      return true;
    default:
      return false;
  }
}

export const spyModule: GameModule<SpyState, SpyConfig, SpyView> = {
  id: 'spy',
  // Ranked stays off until the standardized rules are playtested for fairness.
  capabilities: { minPlayers: 3, maxPlayers: 8, ranked: false, safeModeReady: true, spectators: 'none' },

  defaultConfig() {
    return { ...STANDARD_CONFIG };
  },

  validateConfig(raw: unknown, mode: MatchMode): SpyConfig {
    if (mode !== 'private') return { ...STANDARD_CONFIG };
    const parsed = configSchema.safeParse(raw ?? {});
    return parsed.success ? parsed.data : { ...STANDARD_CONFIG };
  },

  expectedDurationSec(c) {
    const typicalPlayers = 6;
    const perTurn = c.askSeconds * 0.5 + c.answerSeconds * 0.5 + SPY_TIMING.showAnswerMs / 1000;
    return Math.round(
      SPY_TIMING.rolesMs / 1000 + typicalPlayers * c.rounds * perTurn + c.discussSeconds * 0.8 + c.voteSeconds * 0.6 + 10,
    );
  },

  contentRequest(c) {
    return { gameId: 'spy', count: 3, category: c.category, difficulty: 'medium' };
  },

  setup(players, config, content, rng, now) {
    const pack = content.map(parseSpyPack).find((p): p is SpyPack => p !== null);
    if (!pack) throw new Error('not_enough_content');
    const word = pack.words[rng.int(pack.words.length)]!;
    const decoys = rng.shuffle(pack.words.filter((w) => w !== word)).slice(0, SPY_TIMING.guessOptions - 1);
    const spyCount = Math.min(config.spies, maxSpies(players.length));
    const spies = new Set(rng.shuffle(players).slice(0, spyCount));
    const turns: Turn[] = [];
    for (let r = 0; r < config.rounds; r++) {
      for (const asker of rng.shuffle(players)) {
        turns.push({ asker, target: null, options: [], question: null, answer: null, closed: false });
      }
    }
    return {
      players: players.slice(),
      config: { ...config, spies: spyCount },
      rng,
      category: pack.category,
      packId: pack.id,
      word,
      wordOptions: rng.shuffle([word, ...decoys]),
      spies,
      questions: pack.questions,
      used: new Set(),
      turns,
      turnIndex: 0,
      stage: 'roles',
      stageEndsAt: now + SPY_TIMING.rolesMs,
      suspicions: new Map(),
      ready: new Set(),
      votes: new Map(),
      guesser: null,
      final: null,
      scores: new Map(players.map((p) => [p, 0])),
    };
  },

  onAction(s, playerId, raw, now): ActionResult {
    const a = raw as SpyAction;
    if (!s.players.includes(playerId)) return { ok: false, code: 'not_in_match' };
    if (!a || typeof a !== 'object' || typeof a.kind !== 'string') return { ok: false, code: 'bad_action' };
    if (s.stage === 'finished') return { ok: false, code: 'not_accepting' };
    const turn = s.turns[s.turnIndex];
    switch (a.kind) {
      case 'ask': {
        if (s.stage !== 'ask' || !turn || a.turn !== s.turnIndex) return { ok: false, code: 'not_accepting' };
        if (turn.asker !== playerId) return { ok: false, code: 'not_your_turn' };
        if (!Number.isInteger(a.question) || a.question < 0 || a.question >= turn.options.length) {
          return { ok: false, code: 'bad_choice' };
        }
        if (a.target === playerId || !s.players.includes(a.target)) return { ok: false, code: 'bad_target' };
        applyAsk(s, a.question, a.target, now);
        return { ok: true };
      }
      case 'answer': {
        if (s.stage !== 'answer' || !turn || turn.closed || a.turn !== s.turnIndex) return { ok: false, code: 'not_accepting' };
        if (turn.target !== playerId) return { ok: false, code: 'not_your_turn' };
        if (!Number.isInteger(a.answer) || a.answer < 0 || a.answer >= SPY_ANSWERS.length) return { ok: false, code: 'bad_choice' };
        closeAnswer(s, a.answer, now);
        return { ok: true };
      }
      case 'suspect': {
        if (s.stage === 'vote' || s.stage === 'guess') return { ok: false, code: 'not_accepting' };
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
      case 'guess': {
        if (!s.spies.has(playerId)) return { ok: false, code: 'not_allowed' };
        const early = s.stage === 'ask' || s.stage === 'answer' || s.stage === 'discuss';
        const caught = s.stage === 'guess' && s.guesser === playerId;
        if (!early && !caught) return { ok: false, code: 'not_accepting' };
        if (!Number.isInteger(a.choice) || a.choice < 0 || a.choice >= s.wordOptions.length) return { ok: false, code: 'bad_choice' };
        const named = s.wordOptions[a.choice]!;
        const right = named === s.word;
        if (early) finish(s, right ? 'spies' : 'citizens', right ? 'spy_guessed_early' : 'spy_guessed_wrong', null, named);
        else finish(s, right ? 'spies' : 'citizens', right ? 'caught_but_guessed' : 'caught', playerId, named);
        return { ok: true };
      }
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

  viewFor(s, viewer): SpyView {
    const inMatch = s.players.includes(viewer);
    const isSpy = s.spies.has(viewer);
    const finished = s.stage === 'finished';
    const turn = s.turns[s.turnIndex];
    const inTurns = s.stage === 'ask' || s.stage === 'answer';
    const history: SpyHistoryEntry[] = s.turns
      .filter((t) => t.closed && t.question !== null && t.target !== null)
      .map((t) => ({ asker: t.asker, target: t.target!, question: s.questions[t.question!]!, answer: t.answer }));
    const canGuess =
      isSpy && ((s.stage === 'ask' || s.stage === 'answer' || s.stage === 'discuss') || (s.stage === 'guess' && s.guesser === viewer));
    return {
      stage: s.stage,
      stageEndsAt: s.stageEndsAt,
      category: s.category,
      role: inMatch ? (isSpy ? 'spy' : 'citizen') : null,
      word: finished || (inMatch && !isSpy) ? s.word : null,
      spyCount: s.spies.size,
      turn:
        inTurns && turn
          ? {
              index: s.turnIndex,
              total: s.turns.length,
              asker: turn.asker,
              target: turn.target,
              questionOptions: s.stage === 'ask' && viewer === turn.asker ? turn.options.map((i) => s.questions[i]!) : null,
              question: turn.question === null ? null : s.questions[turn.question]!,
              answer: turn.closed ? turn.answer : null,
            }
          : null,
      history,
      suspicions: Object.fromEntries(s.suspicions),
      readyCount: s.ready.size,
      youReady: s.ready.has(viewer),
      yourVote: s.votes.get(viewer) ?? null,
      votedCount: s.votes.size,
      guessOptions: canGuess ? s.wordOptions : null,
      guesser: s.stage === 'guess' ? s.guesser : null,
      final: s.final,
    };
  },

  isFinished(s) {
    return s.stage === 'finished';
  },

  results(s): GameResults {
    const ranking = placesFromScores(s.players.map((p) => ({ playerId: p, score: s.scores.get(p) ?? 0 })));
    const best = SPY_POINTS.spyWin + SPY_POINTS.spyGuessBonus;
    const performance = Object.fromEntries(s.players.map((p) => [p, Math.min(1, (s.scores.get(p) ?? 0) / best)]));
    return { ranking, performance };
  },
};
