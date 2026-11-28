/**
 * Who Among Us? (مين فينا؟), a casual social voting game.
 *
 * Rules (finalized for this build; numbers are configurable defaults):
 * - A fixed number of approved questions ("Who among us would ...?"), all
 *   suitable for ages 13+. On each one every player votes for another player
 *   (never themselves) or skips, with no penalty.
 * - Voting is anonymous: who voted for whom is never stored in the view or
 *   sent to anyone, only totals.
 * - Reveal: the most-voted player (up to two on a tie). Nothing is shown when
 *   fewer than MIN_VOTES people voted (too easy to work out who voted), and
 *   counts are only shown from COUNTS_FROM votes. To avoid repeated
 *   targeting, a player is shown as the pick at most `maxHighlights` times
 *   per match; after that the question shows as "spread out".
 * - No winner, loser or rating. Everyone gets a friendly title at the end and
 *   small participation rewards (see finalize).
 */
import type { MatchMode, WhoAction, WhoCategory, WhoFinal, WhoReveal, WhoStage, WhoTitle, WhoView } from '@sahra/shared';
import { WHO_CATEGORIES } from '@sahra/shared';
import { z } from 'zod';
import { type ActionResult, type ContentRow, type GameModule, type GameResults, Rng } from './engine';

export const WHO_TIMING = { revealMs: 5000 };
export const WHO_LIMITS = { minVotes: 3, countsFrom: 5 };

export interface WhoConfig {
  questionCount: number;
  voteSeconds: number;
}

const STANDARD_CONFIG: WhoConfig = { questionCount: 8, voteSeconds: 15 };

const configSchema = z.object({
  questionCount: z.number().int().min(5).max(12).default(8),
  voteSeconds: z.number().int().min(10).max(30).default(15),
});

const payloadSchema = z.object({ text: z.string().trim().min(8).max(140) });

interface WhoQuestion {
  id: string;
  text: string;
  category: WhoCategory;
}

export function parseWhoQuestion(row: ContentRow): WhoQuestion | null {
  const p = payloadSchema.safeParse(row.payload);
  if (!p.success || !WHO_CATEGORIES.includes(row.category as WhoCategory)) return null;
  return { id: row.id, text: p.data.text, category: row.category as WhoCategory };
}

export function maxHighlights(questions: number, players: number) {
  return Math.max(2, Math.ceil(questions / players) + 1);
}

export interface WhoState {
  players: string[];
  config: WhoConfig;
  questions: WhoQuestion[];
  index: number; // 0-based
  stage: WhoStage;
  stageEndsAt: number;
  /** Current question only: voter -> target id or 'skip'. Cleared each question. */
  choices: Map<string, string>;
  reveal: WhoReveal | null;
  highlightCount: Map<string, number>;
  /** Votes received per player per category (totals only). */
  received: Map<string, Map<WhoCategory, number>>;
  participated: Map<string, number>;
  votesCast: number;
  skips: number;
  highlights: { text: string; picks: string[] }[];
  final: WhoFinal | null;
}

function closeQuestion(s: WhoState, now: number) {
  const q = s.questions[s.index]!;
  const counts = new Map<string, number>();
  let votes = 0;
  for (const [voter, choice] of s.choices) {
    s.participated.set(voter, (s.participated.get(voter) ?? 0) + 1);
    if (choice === 'skip') {
      s.skips++;
      continue;
    }
    votes++;
    counts.set(choice, (counts.get(choice) ?? 0) + 1);
    const byCat = s.received.get(choice) ?? new Map<WhoCategory, number>();
    byCat.set(q.category, (byCat.get(q.category) ?? 0) + 1);
    s.received.set(choice, byCat);
  }
  s.votesCast += votes;
  s.choices.clear();

  let reveal: WhoReveal;
  if (votes < WHO_LIMITS.minVotes) {
    reveal = { kind: 'too_few', picks: [], votes, counts: null };
  } else {
    const max = Math.max(...counts.values());
    const cap = maxHighlights(s.questions.length, s.players.length);
    const top = [...counts.keys()].filter((p) => counts.get(p) === max);
    const shown = top.length <= 2 ? top.filter((p) => (s.highlightCount.get(p) ?? 0) < cap) : [];
    if (shown.length === 0) {
      reveal = { kind: 'spread', picks: [], votes, counts: null };
    } else {
      for (const p of shown) s.highlightCount.set(p, (s.highlightCount.get(p) ?? 0) + 1);
      s.highlights.push({ text: q.text, picks: shown });
      reveal = {
        kind: 'pick',
        picks: shown,
        votes,
        counts: votes >= WHO_LIMITS.countsFrom ? Object.fromEntries(shown.map((p) => [p, counts.get(p)!])) : null,
      };
    }
  }
  s.reveal = reveal;
  s.stage = 'reveal';
  s.stageEndsAt = now + WHO_TIMING.revealMs;
}

function titleFor(s: WhoState, player: string): WhoTitle {
  const byCat = s.received.get(player);
  if (!byCat || byCat.size === 0) return 'mystery';
  let best: WhoCategory = WHO_CATEGORIES[0]!;
  let bestN = -1;
  for (const c of WHO_CATEGORIES) {
    const n = byCat.get(c) ?? 0;
    if (n > bestN) {
      best = c;
      bestN = n;
    }
  }
  return best;
}

function finish(s: WhoState) {
  s.stage = 'finished';
  s.stageEndsAt = 0;
  s.reveal = null;
  s.final = {
    questions: s.questions.length,
    votesCast: s.votesCast,
    skips: s.skips,
    titles: Object.fromEntries(s.players.map((p) => [p, titleFor(s, p)])),
    highlights: s.highlights,
  };
}

function step(s: WhoState, now: number, active: ReadonlySet<string>): boolean {
  switch (s.stage) {
    case 'vote': {
      const here = s.players.filter((p) => active.has(p));
      const allIn = here.length > 0 && here.every((p) => s.choices.has(p));
      if (now < s.stageEndsAt && !allIn) return false;
      closeQuestion(s, now);
      return true;
    }
    case 'reveal':
      if (now < s.stageEndsAt) return false;
      if (s.index + 1 >= s.questions.length) {
        finish(s);
      } else {
        s.index++;
        s.reveal = null;
        s.stage = 'vote';
        s.stageEndsAt = now + s.config.voteSeconds * 1000;
      }
      return true;
    default:
      return false;
  }
}

export const whoModule: GameModule<WhoState, WhoConfig, WhoView> = {
  id: 'who',
  // Never ranked: no winners or losers by design.
  capabilities: { minPlayers: 3, maxPlayers: 10, ranked: false, safeModeReady: true, spectators: 'none', rewards: 'participation' },

  defaultConfig() {
    return { ...STANDARD_CONFIG };
  },

  validateConfig(raw: unknown, mode: MatchMode): WhoConfig {
    if (mode !== 'private') return { ...STANDARD_CONFIG };
    const parsed = configSchema.safeParse(raw ?? {});
    return parsed.success ? parsed.data : { ...STANDARD_CONFIG };
  },

  expectedDurationSec(c) {
    return Math.round(c.questionCount * (c.voteSeconds * 0.7 + WHO_TIMING.revealMs / 1000));
  },

  contentRequest(c) {
    return { gameId: 'who', count: c.questionCount + 6, category: 'mixed', difficulty: 'medium' };
  },

  setup(players, config, content, _rng: Rng, now) {
    const questions = content.map(parseWhoQuestion).filter((q): q is WhoQuestion => q !== null).slice(0, config.questionCount);
    if (questions.length < config.questionCount) throw new Error('not_enough_content');
    return {
      players: players.slice(),
      config: { ...config },
      questions,
      index: 0,
      stage: 'vote',
      stageEndsAt: now + config.voteSeconds * 1000,
      choices: new Map(),
      reveal: null,
      highlightCount: new Map(),
      received: new Map(),
      participated: new Map(),
      votesCast: 0,
      skips: 0,
      highlights: [],
      final: null,
    };
  },

  onAction(s, playerId, raw): ActionResult {
    const a = raw as WhoAction;
    if (!s.players.includes(playerId)) return { ok: false, code: 'not_in_match' };
    if (!a || typeof a !== 'object' || typeof a.kind !== 'string') return { ok: false, code: 'bad_action' };
    if (s.stage !== 'vote' || a.question !== s.index + 1) return { ok: false, code: 'not_accepting' };
    if (s.choices.has(playerId)) return { ok: false, code: 'already_answered' };
    switch (a.kind) {
      case 'vote':
        if (a.target === playerId || !s.players.includes(a.target)) return { ok: false, code: 'bad_target' };
        s.choices.set(playerId, a.target);
        return { ok: true };
      case 'skip':
        s.choices.set(playerId, 'skip');
        return { ok: true };
      default:
        return { ok: false, code: 'bad_action' };
    }
  },

  tick(s, now, activePlayers) {
    for (let guard = 0; guard < 6 && step(s, now, activePlayers); guard++);
  },

  nextWakeAt(s) {
    return s.stage === 'finished' ? null : s.stageEndsAt;
  },

  viewFor(s, viewer): WhoView {
    const q = s.questions[s.index]!;
    return {
      stage: s.stage,
      stageEndsAt: s.stageEndsAt,
      index: s.index + 1,
      total: s.questions.length,
      question: s.stage === 'finished' ? null : { text: q.text, category: q.category },
      yourChoice: s.stage === 'vote' ? s.choices.get(viewer) ?? null : null,
      answeredCount: s.choices.size,
      reveal: s.stage === 'reveal' ? s.reveal : null,
      final: s.final,
    };
  },

  isFinished(s) {
    return s.stage === 'finished';
  },

  results(s): GameResults {
    // Everyone shares first place; the score is participation, not votes received.
    const ranking = s.players.map((p) => ({ playerId: p, score: s.participated.get(p) ?? 0, place: 1, correct: s.participated.get(p) ?? 0 }));
    const performance = Object.fromEntries(s.players.map((p) => [p, Math.min(1, (s.participated.get(p) ?? 0) / s.questions.length)]));
    return { ranking, performance };
  },
};
