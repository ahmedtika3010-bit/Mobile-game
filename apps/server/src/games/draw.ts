/**
 * Draw and Guess (ارسم وخمّن).
 *
 * Rules (finalized for this build; numbers are configurable defaults):
 * - Every player draws the same number of times. The drawing order is
 *   shuffled once from the match seed and repeated each round; in team mode
 *   the two teams alternate. Standard matches play 2 rounds with up to 4
 *   players and 1 round with more.
 * - Turn: `choose` (the drawer picks one of three words; on timeout a word
 *   chosen in advance from the seed is used), `draw` (everyone else types
 *   guesses), `reveal`.
 * - Choices: one easy, one medium and one hard word ("mixed", the standard
 *   profile), or three of one difficulty in private rooms. Harder words pay
 *   more, for the drawer and the guessers alike.
 * - Guessers: up to 100 / 130 / 160 points by difficulty, from 40% to 100%
 *   by time left, counted in whole seconds with the quiz's latency
 *   compensation. Only the approved word and its approved variants count,
 *   after Arabic normalization (article-insensitive); no fuzzy matching.
 * - Drawer: 80% of the word's points times the share of guessers who got it.
 * - Wrong guesses are private (shown only to their author, with a "close"
 *   hint when one letter away). Others only see who got it, never what they
 *   typed, so the guess box is not a chat.
 * - Letter hints for guessers at half time and three-quarter time (for words
 *   long enough to keep a challenge).
 * - Safety: restricted tools (fixed palette, three sizes, undo, clear; no
 *   text or images). Any guesser can hide the drawing for themselves (its
 *   strokes stop reaching them); when enough guessers hide it, the turn is
 *   stopped for everyone and the drawer scores 0. Drawing letters or agreed
 *   symbols cannot be detected automatically, so the game is not ranked and
 *   Safe Mode (mixed ages, minors) is not offered until it has been tested.
 * - The turn ends when time runs out, when every connected guesser got it,
 *   when it is stopped, or when the drawer has been disconnected for a few
 *   seconds (nobody scores then).
 */
import {
  type Difficulty,
  type DrawAction,
  type DrawOp,
  type DrawReveal,
  type DrawTurnView,
  type DrawView,
  type MatchMode,
  DRAW_CANVAS,
  DRAW_COLORS,
  DRAW_LIMITS,
  DRAW_WIDTHS,
  matchApprovedAnswer,
  normalizeArabic,
  stripDefiniteArticle,
} from '@sahra/shared';
import { z } from 'zod';
import { type ActionResult, type ContentRow, type GameModule, type GameResults, Rng, isPracticeBot, placesFromScores } from './engine';

export const DRAW_TIMING = {
  chooseMs: 12_000,
  revealMs: 5_000,
  /** Shorter reveal for a skipped or abandoned turn. */
  shortRevealMs: 2_500,
  /** How long a disconnected drawer keeps the turn. */
  drawerGraceMs: 8_000,
  maxLatencyCompMs: 1_500,
  /** Letter hints, as fractions of the drawing time. */
  hintAt: [0.5, 0.75] as const,
};

export const DRAW_POINTS: Record<Difficulty, number> = { easy: 100, medium: 130, hard: 160 };
const MIN_SHARE = 0.4;
const DRAWER_SHARE = 0.8;

export interface DrawConfig {
  /** 0 = automatic (2 rounds up to 4 players, 1 round above). */
  rounds: number;
  drawSeconds: number;
  difficulty: Difficulty | 'mixed';
  teams: boolean;
}

const STANDARD_CONFIG: DrawConfig = { rounds: 0, drawSeconds: 80, difficulty: 'mixed', teams: false };

const configSchema = z.object({
  rounds: z.number().int().min(0).max(3).default(0),
  drawSeconds: z.union([z.literal(60), z.literal(80), z.literal(100)]).default(80),
  difficulty: z.enum(['mixed', 'easy', 'medium', 'hard']).default('mixed'),
  teams: z.boolean().default(false),
});

const sketchStroke = z.object({
  c: z.number().int().min(0).max(DRAW_COLORS.length - 1),
  w: z.number().int().min(0).max(DRAW_WIDTHS.length - 1),
  p: z.array(z.number().int().min(0).max(DRAW_CANVAS)).min(2).max(800).refine((p) => p.length % 2 === 0),
});

/** Content payload for one word (admin schema and seed). */
export const drawPayloadSchema = z.object({
  word: z.string().trim().min(2).max(24),
  accepted: z.array(z.string().trim().min(1).max(30)).max(12).default([]),
  /** Optional simple drawing that practice bots use. */
  sketch: z.array(sketchStroke).max(40).optional(),
});

export interface Word {
  id: string;
  word: string;
  accepted: string[];
  category: string;
  difficulty: Difficulty;
  sketch: { c: number; w: number; p: number[] }[] | null;
}

interface Turn {
  drawer: string;
  choices: Word[];
  /** Picked if the drawer does not choose in time. */
  fallback: number;
  word: Word | null;
  ops: DrawOp[];
  points: number;
  strokeOpen: boolean;
  lastOpAt: number;
  /** player -> points earned */
  guessed: Map<string, number>;
  order: string[];
  wrong: Map<string, string[]>;
  close: Set<string>;
  lastGuessAt: Map<string, number>;
  guessCount: Map<string, number>;
  hid: Set<string>;
  /** Letter positions the hints reveal, in order, for each choice (fixed at setup). */
  hintsByChoice: number[][];
  /** The chosen word's hint positions. */
  hintPositions: number[];
  drawerGoneAt: number | null;
}

export interface DrawState {
  players: string[];
  config: DrawConfig;
  team: Map<string, number> | null;
  turns: Turn[];
  index: number;
  stage: 'choose' | 'draw' | 'reveal' | 'finished';
  chooseEndsAt: number;
  startedAt: number;
  deadline: number;
  revealEndsAt: number;
  lastReveal: DrawReveal | null;
  scores: Map<string, number>;
  correct: Map<string, number>;
  /** Time of the last tick, so the next wake-up can skip hints already shown. */
  lastTickAt: number;
}

function asWord(row: ContentRow): Word | null {
  const parsed = drawPayloadSchema.safeParse(row.payload);
  if (!parsed.success) return null;
  const d = row.difficulty as Difficulty;
  if (!(d in DRAW_POINTS)) return null;
  return {
    id: row.id,
    word: parsed.data.word,
    accepted: [...new Set([...parsed.data.accepted, ...row.acceptedAnswers])],
    category: row.category,
    difficulty: d,
    sketch: parsed.data.sketch ?? null,
  };
}

function roundsFor(config: DrawConfig, players: number) {
  if (config.rounds > 0) return config.rounds;
  return players <= 4 ? 2 : 1;
}

/** Letters (not spaces) of a word; hints reveal some of their positions. */
function letterPositions(word: string): number[] {
  return [...word].map((ch, i) => (ch === ' ' ? -1 : i)).filter((i) => i >= 0);
}

function hintCount(word: string, now: number, s: DrawState): number {
  const letters = letterPositions(word).length;
  const allowed = letters >= 6 ? 2 : letters >= 4 ? 1 : 0;
  const span = s.deadline - s.startedAt;
  return DRAW_TIMING.hintAt.filter((f, i) => i < allowed && now >= s.startedAt + f * span).length;
}

export function guesserPoints(difficulty: Difficulty, elapsedMs: number, drawSeconds: number) {
  const max = DRAW_POINTS[difficulty];
  const bucket = Math.floor(Math.max(0, elapsedMs) / 1000);
  const remaining = Math.max(0, drawSeconds - 1 - bucket);
  const share = MIN_SHARE + ((1 - MIN_SHARE) * remaining) / Math.max(1, drawSeconds - 1);
  return Math.round((max * share) / 5) * 5;
}

/** One-letter difference (edit distance 1) between normalized words of 4+ letters. */
export function isClose(a: string, b: string): boolean {
  if (a === b || Math.min(a.length, b.length) < 4 || Math.abs(a.length - b.length) > 1) return false;
  let i = 0;
  let j = 0;
  let edits = 0;
  while (i < a.length && j < b.length) {
    if (a[i] === b[j]) {
      i++;
      j++;
      continue;
    }
    if (++edits > 1) return false;
    if (a.length > b.length) i++;
    else if (b.length > a.length) j++;
    else {
      i++;
      j++;
    }
  }
  return edits + (a.length - i) + (b.length - j) <= 1;
}

function activeGuessers(s: DrawState, t: Turn, active: ReadonlySet<string>) {
  return s.players.filter((p) => p !== t.drawer && active.has(p));
}

/** Guessers needed to stop a drawing: all of them up to two, otherwise half. */
export function hideThreshold(guessers: number) {
  if (guessers <= 2) return Math.max(1, guessers);
  return Math.ceil(guessers / 2);
}

function startTurn(s: DrawState, now: number) {
  s.stage = 'choose';
  s.chooseEndsAt = now + DRAW_TIMING.chooseMs;
  s.startedAt = 0;
  s.deadline = 0;
  s.lastReveal = null;
}

function beginDrawing(s: DrawState, choice: number, now: number) {
  const t = s.turns[s.index]!;
  t.word = t.choices[choice] ?? t.choices[0]!;
  t.hintPositions = t.hintsByChoice[choice] ?? [];
  s.stage = 'draw';
  s.startedAt = now;
  s.deadline = now + s.config.drawSeconds * 1000;
}

function closeTurn(s: DrawState, now: number, ended: DrawReveal['ended'], guessersAtEnd: number) {
  const t = s.turns[s.index]!;
  const word = t.word;
  const points: Record<string, number> = Object.fromEntries(s.players.map((p) => [p, 0]));
  if (word) {
    for (const [p, pts] of t.guessed) points[p] = pts;
    if (ended !== 'stopped' && ended !== 'drawer_left') {
      const share = t.guessed.size / Math.max(1, guessersAtEnd);
      points[t.drawer] = Math.round(DRAW_POINTS[word.difficulty] * DRAWER_SHARE * Math.min(1, share));
    }
    if (ended === 'drawer_left') for (const p of s.players) points[p] = 0;
  }
  for (const p of s.players) s.scores.set(p, (s.scores.get(p) ?? 0) + (points[p] ?? 0));
  s.lastReveal = { word: word?.word ?? '', points, guessed: t.order.slice(), ended };
  s.stage = 'reveal';
  s.revealEndsAt = now + (ended === 'skipped' || ended === 'drawer_left' ? DRAW_TIMING.shortRevealMs : DRAW_TIMING.revealMs);
}

function validOp(op: unknown): DrawOp | null {
  if (!op || typeof op !== 'object') return null;
  const o = op as Record<string, unknown>;
  const pointsOk = (p: unknown): p is number[] =>
    Array.isArray(p) &&
    p.length >= 2 &&
    p.length % 2 === 0 &&
    p.length <= DRAW_LIMITS.pointsPerOp * 2 &&
    p.every((n) => Number.isInteger(n) && n >= 0 && n <= DRAW_CANVAS);
  switch (o.t) {
    case 'b':
      if (!Number.isInteger(o.c) || (o.c as number) < 0 || (o.c as number) >= DRAW_COLORS.length) return null;
      if (!Number.isInteger(o.w) || (o.w as number) < 0 || (o.w as number) >= DRAW_WIDTHS.length) return null;
      return pointsOk(o.p) ? { t: 'b', c: o.c as number, w: o.w as number, p: (o.p as number[]).slice() } : null;
    case 'p':
      return pointsOk(o.p) ? { t: 'p', p: (o.p as number[]).slice() } : null;
    case 'u':
      return { t: 'u' };
    case 'x':
      return { t: 'x' };
    default:
      return null;
  }
}

function elapsedFor(s: DrawState, raw: unknown, now: number) {
  const serverElapsed = now - s.startedAt;
  const c = (raw as { clientElapsedMs?: unknown }).clientElapsedMs;
  const reported = typeof c === 'number' && Number.isFinite(c) ? c : serverElapsed;
  return Math.min(serverElapsed, Math.max(reported, serverElapsed - DRAW_TIMING.maxLatencyCompMs));
}

function teamScores(s: DrawState): [number, number] | null {
  if (!s.team) return null;
  const avg = (team: number) => {
    const members = s.players.filter((p) => s.team!.get(p) === team);
    const sum = members.reduce((a, p) => a + (s.scores.get(p) ?? 0), 0);
    return members.length ? Math.round(sum / members.length) : 0;
  };
  return [avg(0), avg(1)];
}

function ranking(s: DrawState) {
  const ts = teamScores(s);
  if (s.team && ts) {
    // Team mode: teammates share their team's place; each keeps their own points.
    const teamPlace = (team: number) => (ts[team]! >= ts[1 - team]! ? 1 : 2);
    return s.players
      .map((p) => ({ playerId: p, score: s.scores.get(p) ?? 0, place: teamPlace(s.team!.get(p)!), correct: s.correct.get(p) ?? 0 }))
      .sort((a, b) => a.place - b.place || b.score - a.score);
  }
  return placesFromScores(s.players.map((p) => ({ playerId: p, score: s.scores.get(p) ?? 0 }))).map((r) => ({
    ...r,
    correct: s.correct.get(r.playerId) ?? 0,
  }));
}

/** Bot drawing: each sketch stroke becomes a begin op and point chunks. */
export function sketchOps(sketch: Word['sketch']): { op: DrawOp; stroke: number }[] {
  const out: { op: DrawOp; stroke: number }[] = [];
  (sketch ?? []).forEach((st, stroke) => {
    const chunk = 16; // points (pairs) per op
    for (let i = 0; i < st.p.length; i += chunk * 2) {
      const p = st.p.slice(i, i + chunk * 2);
      out.push({ op: i === 0 ? { t: 'b', c: st.c, w: st.w, p } : { t: 'p', p }, stroke });
    }
  });
  return out;
}

export const drawModule: GameModule<DrawState, DrawConfig, DrawView> = {
  id: 'draw',
  capabilities: { minPlayers: 2, maxPlayers: 8, ranked: false, safeModeReady: false, spectators: 'none' },

  defaultConfig() {
    return { ...STANDARD_CONFIG };
  },

  validateConfig(raw: unknown, mode: MatchMode): DrawConfig {
    if (mode !== 'private') return { ...STANDARD_CONFIG };
    const parsed = configSchema.safeParse(raw ?? {});
    return parsed.success ? parsed.data : { ...STANDARD_CONFIG };
  },

  expectedDurationSec(c) {
    // Estimate for four players.
    const turns = 4 * roundsFor(c, 4);
    const perTurn = DRAW_TIMING.chooseMs / 2000 + c.drawSeconds * 0.75 + DRAW_TIMING.revealMs / 1000;
    return Math.round(turns * perTurn);
  },

  contentRequest(c) {
    return { gameId: 'draw', count: 400, category: 'mixed', difficulty: c.difficulty };
  },

  setup(players, config, content, rng, now) {
    const words = content.map(asWord).filter((w): w is Word => w !== null);
    const byDiff: Record<Difficulty, Word[]> = { easy: [], medium: [], hard: [] };
    for (const w of rng.shuffle(words)) byDiff[w.difficulty].push(w);

    let order = rng.shuffle(players.slice());
    let team: Map<string, number> | null = null;
    if (config.teams && players.length >= 4) {
      team = new Map(order.map((p, i) => [p, i % 2]));
      // Alternate teams in the drawing order.
      const a = order.filter((p) => team!.get(p) === 0);
      const b = order.filter((p) => team!.get(p) === 1);
      order = [];
      for (let i = 0; i < Math.max(a.length, b.length); i++) {
        if (a[i]) order.push(a[i]!);
        if (b[i]) order.push(b[i]!);
      }
    }
    const rounds = roundsFor(config, players.length);
    const drawers = Array.from({ length: rounds }, () => order).flat();
    const pattern: Difficulty[] = config.difficulty === 'mixed' ? ['easy', 'medium', 'hard'] : [config.difficulty, config.difficulty, config.difficulty];
    const need: Record<Difficulty, number> = { easy: 0, medium: 0, hard: 0 };
    for (const d of pattern) need[d] += drawers.length;
    for (const d of Object.keys(need) as Difficulty[]) {
      if (byDiff[d].length < need[d]) throw new Error('not_enough_content');
    }
    const turns: Turn[] = drawers.map((drawer) => {
      const choices = pattern.map((d, i) => {
        const pile = byDiff[d];
        // A practice bot's first choice is a word it has a simple sketch for.
        const at = i === 0 && isPracticeBot(drawer) ? Math.max(0, pile.findIndex((w) => w.sketch)) : 0;
        return pile.splice(at, 1)[0]!;
      });
      return {
        drawer,
        choices,
        fallback: rng.int(choices.length),
        word: null,
        ops: [],
        points: 0,
        strokeOpen: false,
        lastOpAt: 0,
        guessed: new Map(),
        order: [],
        wrong: new Map(),
        close: new Set(),
        lastGuessAt: new Map(),
        guessCount: new Map(),
        hid: new Set(),
        hintsByChoice: choices.map((w) => rng.shuffle(letterPositions(w.word))),
        hintPositions: [],
        drawerGoneAt: null,
      };
    });
    const s: DrawState = {
      players: players.slice(),
      config: { ...config },
      team,
      turns,
      index: 0,
      stage: 'choose',
      chooseEndsAt: 0,
      startedAt: 0,
      deadline: 0,
      revealEndsAt: 0,
      lastReveal: null,
      scores: new Map(players.map((p) => [p, 0])),
      correct: new Map(players.map((p) => [p, 0])),
      lastTickAt: now,
    };
    startTurn(s, now);
    return s;
  },

  onAction(s, playerId, raw, now): ActionResult {
    const a = raw as DrawAction;
    if (!s.players.includes(playerId)) return { ok: false, code: 'not_in_match' };
    if (!a || typeof a !== 'object' || typeof a.kind !== 'string') return { ok: false, code: 'bad_action' };
    const t = s.turns[s.index];
    if (!t || a.turn !== s.index + 1) return { ok: false, code: 'not_accepting' };

    if (a.kind === 'choose') {
      if (playerId !== t.drawer) return { ok: false, code: 'not_drawer' };
      if (s.stage !== 'choose') return { ok: false, code: 'not_accepting' };
      if (!Number.isInteger(a.choice) || a.choice < 0 || a.choice >= t.choices.length) return { ok: false, code: 'bad_choice' };
      beginDrawing(s, a.choice, now);
      return { ok: true };
    }

    if (a.kind === 'draw') {
      if (playerId !== t.drawer) return { ok: false, code: 'not_drawer' };
      if (s.stage !== 'draw' || now > s.deadline) return { ok: false, code: 'not_accepting' };
      if (!Array.isArray(a.ops) || a.ops.length === 0 || a.ops.length > DRAW_LIMITS.opsPerAction) return { ok: false, code: 'bad_ops' };
      const ops: DrawOp[] = [];
      let open = t.strokeOpen;
      let pts = 0;
      for (const raw of a.ops) {
        const op = validOp(raw);
        if (!op) return { ok: false, code: 'bad_ops' };
        if (op.t === 'p' && !open) return { ok: false, code: 'bad_ops' };
        if (op.t === 'b') open = true;
        if (op.t === 'u' || op.t === 'x') open = false;
        if (op.t === 'b' || op.t === 'p') pts += op.p.length / 2;
        ops.push(op);
      }
      if (t.ops.length + ops.length > DRAW_LIMITS.opsPerTurn || t.points + pts > DRAW_LIMITS.pointsPerTurn) {
        return { ok: false, code: 'drawing_limit' };
      }
      t.ops.push(...ops);
      t.points += pts;
      t.strokeOpen = open;
      t.lastOpAt = now;
      return { ok: true };
    }

    if (a.kind === 'guess') {
      if (playerId === t.drawer) return { ok: false, code: 'drawer_cannot_guess' };
      if (s.stage !== 'draw' || now > s.deadline || !t.word) return { ok: false, code: 'not_accepting' };
      if (t.guessed.has(playerId)) return { ok: false, code: 'already_guessed' };
      if (typeof a.text !== 'string') return { ok: false, code: 'bad_action' };
      const text = a.text.trim().replace(/\s+/g, ' ');
      if (!text || text.length > DRAW_LIMITS.guessLength) return { ok: false, code: 'bad_guess' };
      if (now - (t.lastGuessAt.get(playerId) ?? -Infinity) < DRAW_LIMITS.guessGapMs) return { ok: false, code: 'too_fast' };
      const count = t.guessCount.get(playerId) ?? 0;
      if (count >= DRAW_LIMITS.guessesPerTurn) return { ok: false, code: 'no_guesses_left' };
      t.lastGuessAt.set(playerId, now);
      t.guessCount.set(playerId, count + 1);
      const approved = [t.word.word, ...t.word.accepted];
      if (matchApprovedAnswer(text, approved, { ignoreDefiniteArticle: true }) >= 0) {
        const pts = guesserPoints(t.word.difficulty, elapsedFor(s, raw, now), s.config.drawSeconds);
        t.guessed.set(playerId, pts);
        t.order.push(playerId);
        t.close.delete(playerId);
        s.correct.set(playerId, (s.correct.get(playerId) ?? 0) + 1);
        return { ok: true };
      }
      t.wrong.set(playerId, [...(t.wrong.get(playerId) ?? []), text]);
      const norm = stripDefiniteArticle(normalizeArabic(text));
      if (approved.some((w) => isClose(norm, stripDefiniteArticle(normalizeArabic(w))))) t.close.add(playerId);
      else t.close.delete(playerId);
      return { ok: true };
    }

    if (a.kind === 'hide') {
      if (playerId === t.drawer) return { ok: false, code: 'not_allowed' };
      if (s.stage !== 'draw') return { ok: false, code: 'not_accepting' };
      t.hid.add(playerId);
      return { ok: true };
    }
    return { ok: false, code: 'bad_action' };
  },

  tick(s, now, active) {
    s.lastTickAt = now;
    for (let guard = 0; guard < 4; guard++) {
      const t = s.turns[s.index];
      if (!t) return;
      if (s.stage === 'choose') {
        if (now < s.chooseEndsAt) return;
        if (!active.has(t.drawer)) {
          closeTurn(s, now, 'skipped', activeGuessers(s, t, active).length);
          continue;
        }
        beginDrawing(s, t.fallback, now);
      } else if (s.stage === 'draw') {
        const guessers = activeGuessers(s, t, active);
        if (!active.has(t.drawer)) {
          t.drawerGoneAt ??= now;
          if (now >= t.drawerGoneAt + DRAW_TIMING.drawerGraceMs) {
            closeTurn(s, now, 'drawer_left', guessers.length);
            continue;
          }
        } else t.drawerGoneAt = null;
        const hidden = guessers.filter((p) => t.hid.has(p)).length;
        if (guessers.length > 0 && hidden >= hideThreshold(guessers.length)) {
          closeTurn(s, now, 'stopped', guessers.length);
          continue;
        }
        const allGuessed = guessers.length > 0 && guessers.every((p) => t.guessed.has(p));
        if (allGuessed) {
          closeTurn(s, now, 'all_guessed', new Set([...guessers, ...t.guessed.keys()]).size);
          continue;
        }
        if (now < s.deadline) return;
        closeTurn(s, now, 'time', new Set([...guessers, ...t.guessed.keys()]).size);
      } else if (s.stage === 'reveal') {
        if (now < s.revealEndsAt) return;
        if (s.index + 1 >= s.turns.length) {
          s.stage = 'finished';
          return;
        }
        s.index++;
        startTurn(s, now);
      } else return;
    }
  },

  nextWakeAt(s) {
    const t = s.turns[s.index];
    if (s.stage === 'choose') return s.chooseEndsAt;
    if (s.stage === 'draw' && t) {
      const span = s.deadline - s.startedAt;
      const wakes = [s.deadline, ...DRAW_TIMING.hintAt.map((f) => s.startedAt + f * span)];
      if (t.drawerGoneAt !== null) wakes.push(t.drawerGoneAt + DRAW_TIMING.drawerGraceMs);
      // The room calls this right after tick, so the next wake-up is the earliest one still ahead.
      const ahead = wakes.filter((w) => w > s.lastTickAt);
      return Math.min(...(ahead.length ? ahead : [s.deadline]));
    }
    if (s.stage === 'reveal') return s.revealEndsAt;
    return null;
  },

  streamFor(s, viewer) {
    const t = s.turns[s.index];
    if (!t || s.stage === 'finished') return null;
    const key = `t${s.index + 1}`;
    if (s.stage === 'reveal' && s.lastReveal?.ended === 'stopped') return { key: `${key}:stopped`, items: [] };
    if (t.hid.has(viewer)) return { key: `${key}:hidden`, items: [] };
    return { key, items: t.ops };
  },

  botPlan(s, botId, _rng, skill) {
    const t = s.turns[s.index];
    if (!t) return null;
    const turnNo = s.index + 1;
    if (t.drawer === botId) {
      if (s.stage === 'choose') {
        const pick = Math.max(0, t.choices.findIndex((w) => w.sketch));
        return { key: `${s.index}:choose`, at: s.chooseEndsAt - DRAW_TIMING.chooseMs + 1800, action: { kind: 'choose', turn: turnNo, choice: pick } };
      }
      if (s.stage !== 'draw' || !t.word?.sketch) return null;
      // Only the bot draws on its own turn, so the operations so far are its own plan's.
      const plan = sketchOps(t.word.sketch);
      const cursor = t.ops.length;
      const next = plan[cursor];
      if (!next) return null;
      const at = s.startedAt + 900 + cursor * 110 + next.stroke * 300;
      return { key: `${s.index}:d:${cursor}`, at, action: { kind: 'draw', turn: turnNo, ops: [next.op] } };
    }
    // Guesser bots do not see the drawing; they answer after the drawer has drawn
    // a fair amount, more often and sooner with more skill.
    if (s.stage !== 'draw' || !t.word || t.guessed.has(botId) || t.points < 40) return null;
    const own = new Rng(`${botId}:${s.index}:${t.word.id}`);
    const ease = { easy: 1, medium: 0.85, hard: 0.7 }[t.word.difficulty];
    if (own.next() > skill * ease + 0.2) return null;
    const span = s.deadline - s.startedAt;
    const at = Math.max(s.startedAt + span * (0.2 + (1 - skill) * 0.45 + own.next() * 0.25), t.lastOpAt + 2500);
    if (at >= s.deadline) return null;
    return { key: `${s.index}:g`, at, action: { kind: 'guess', turn: turnNo, text: t.word.word, clientElapsedMs: at - s.startedAt } };
  },

  viewFor(s, viewer, now): DrawView {
    const t = s.turns[s.index];
    const finished = s.stage === 'finished';
    let turn: DrawTurnView | null = null;
    if (t && !finished) {
      const isDrawer = viewer === t.drawer;
      const youGuessed = t.guessed.has(viewer);
      const revealing = s.stage === 'reveal';
      const word = t.word;
      const showWord = !!word && (revealing || isDrawer || youGuessed);
      let shape: string[] | null = null;
      if (word && s.stage === 'draw' && !isDrawer) {
        const shown = new Set(t.hintPositions.slice(0, hintCount(word.word, now, s)));
        shape = [...word.word].map((ch, i) => (ch === ' ' ? ' ' : youGuessed || shown.has(i) ? ch : ''));
      }
      turn = {
        turn: s.index + 1,
        total: s.turns.length,
        drawer: t.drawer,
        drawerTeam: s.team?.get(t.drawer) ?? null,
        chooseEndsAt: s.chooseEndsAt,
        startedAt: s.startedAt,
        deadline: s.deadline,
        choices:
          isDrawer && s.stage === 'choose'
            ? t.choices.map((w) => ({ word: w.word, difficulty: w.difficulty, points: DRAW_POINTS[w.difficulty] }))
            : null,
        word: showWord ? word!.word : null,
        category: word && s.stage !== 'choose' ? word.category : null,
        difficulty: word && s.stage !== 'choose' ? word.difficulty : null,
        shape,
        guessed: t.order.slice(),
        youGuessed,
        yourGuesses: revealing ? [] : t.wrong.get(viewer) ?? [],
        close: t.close.has(viewer),
        youHid: t.hid.has(viewer),
      };
    }
    const stream = t && !finished ? drawModule.streamFor!(s, viewer) : null;
    const ts = teamScores(s);
    return {
      stage: s.stage,
      turn,
      canvas: stream ? { key: stream.key, ops: stream.items.length } : null,
      reveal: s.stage === 'reveal' ? s.lastReveal : null,
      scores: Object.fromEntries(s.scores),
      teams: s.team && ts ? { of: Object.fromEntries(s.team), scores: ts } : null,
      final: finished ? { ranking: ranking(s), teamScores: ts } : null,
    };
  },

  isFinished(s) {
    return s.stage === 'finished';
  },

  results(s): GameResults {
    const max = s.turns.reduce((a, t) => a + DRAW_POINTS[t.word?.difficulty ?? 'medium'], 0);
    return {
      ranking: ranking(s).map(({ playerId, score, place, correct }) => ({ playerId, score, place, correct })),
      performance: Object.fromEntries(s.players.map((p) => [p, max > 0 ? Math.min(1, (s.scores.get(p) ?? 0) / max) : 0])),
    };
  },
};
