/**
 * Acting and Guessing (مثّل وخمّن).
 *
 * Rules (finalized for this build; numbers are configurable defaults):
 * - Every player acts the same number of times, in an order shuffled from the
 *   match seed (2 rounds up to 4 players, 1 above; private rooms 1 to 3).
 * - Turn: `choose` (the actor picks one of three words: one easy, one medium,
 *   one hard in the standard profile; a word picked in advance is used on
 *   timeout), `act`, `reveal`.
 * - The actor can only play pre-approved moves (ACT_MOVES: avatar
 *   animations, feelings and gestures) and reveal the word's approved hint
 *   cards. No camera, text or voice from the actor, so the game works in
 *   Safe Mode as is. Every move is free.
 * - Content rule (checked by the schema and tests): each word lists the moves
 *   that act it out and at least two hint cards that never contain the word,
 *   so every puzzle is solvable with what the actor has. The actor sees those
 *   suggested moves.
 * - Guessers: like Draw and Guess. Up to 100 / 130 / 160 points by
 *   difficulty, 40 to 100% by time left (whole seconds, latency compensated);
 *   only the approved word and its variants count after Arabic normalization;
 *   wrong guesses are private ("close" hint when one letter away); letter
 *   hints at half and three-quarter time.
 * - Actor: 80% of the word's points times the share of guessers who got it.
 * - Ranked play is off: a sequence of moves could be used as a prearranged
 *   code between friends, which cannot be detected automatically.
 */
import {
  type ActAction,
  type ActBeat,
  type ActReveal,
  type ActTurnView,
  type ActView,
  type Difficulty,
  type MatchMode,
  ACT_CATEGORIES,
  ACT_LIMITS,
  ACT_MOVE_IDS,
  matchApprovedAnswer,
  normalizeArabic,
  stripDefiniteArticle,
} from '@sahra/shared';
import { z } from 'zod';
import { type ActionResult, type ContentRow, type GameModule, type GameResults, Rng, placesFromScores } from './engine';
import { DRAW_POINTS, guesserPoints, isClose } from './draw';

export const ACT_TIMING = {
  chooseMs: 12_000,
  revealMs: 5_000,
  shortRevealMs: 2_500,
  actorGraceMs: 8_000,
  maxLatencyCompMs: 1_500,
  hintAt: [0.5, 0.75] as const,
};

const ACTOR_SHARE = 0.8;

export interface ActConfig {
  /** 0 = automatic (2 rounds up to 4 players, 1 round above). */
  rounds: number;
  actSeconds: number;
  difficulty: Difficulty | 'mixed';
}

const STANDARD_CONFIG: ActConfig = { rounds: 0, actSeconds: 80, difficulty: 'mixed' };

const configSchema = z.object({
  rounds: z.number().int().min(0).max(3).default(0),
  actSeconds: z.union([z.literal(60), z.literal(80), z.literal(100)]).default(80),
  difficulty: z.enum(['mixed', 'easy', 'medium', 'hard']).default('mixed'),
});

const norm = (s: string) => stripDefiniteArticle(normalizeArabic(s));

/** Content payload for one word (admin schema and seed). */
export const actPayloadSchema = z
  .object({
    word: z.string().trim().min(2).max(24),
    accepted: z.array(z.string().trim().min(1).max(30)).max(12).default([]),
    /** Moves that act the word out (ids from ACT_MOVES). */
    moves: z.array(z.string()).min(2).max(6),
    /** Approved hint cards the actor may reveal. */
    cards: z.array(z.string().trim().min(4).max(60)).min(2).max(5),
  })
  .refine((p) => p.moves.every((x) => ACT_MOVE_IDS.has(x)), { message: 'unknown move' })
  .refine((p) => new Set(p.moves).size === p.moves.length, { message: 'duplicate move' })
  // A card must never give the answer away as text.
  .refine((p) => p.cards.every((c) => [p.word, ...p.accepted].every((w) => !normalizeArabic(c).includes(norm(w)))), {
    message: 'a card contains the answer',
  });

export interface ActWord {
  id: string;
  word: string;
  accepted: string[];
  category: string;
  difficulty: Difficulty;
  moves: string[];
  cards: string[];
}

interface Turn {
  actor: string;
  choices: ActWord[];
  fallback: number;
  word: ActWord | null;
  beats: ActBeat[];
  shownCards: Set<number>;
  lastBeatAt: number;
  guessed: Map<string, number>;
  order: string[];
  wrong: Map<string, string[]>;
  close: Set<string>;
  lastGuessAt: Map<string, number>;
  guessCount: Map<string, number>;
  hintsByChoice: number[][];
  hintPositions: number[];
  actorGoneAt: number | null;
}

export interface ActState {
  players: string[];
  config: ActConfig;
  turns: Turn[];
  index: number;
  stage: 'choose' | 'act' | 'reveal' | 'finished';
  chooseEndsAt: number;
  startedAt: number;
  deadline: number;
  revealEndsAt: number;
  lastReveal: ActReveal | null;
  scores: Map<string, number>;
  correct: Map<string, number>;
  lastTickAt: number;
}

function asWord(row: ContentRow): ActWord | null {
  const parsed = actPayloadSchema.safeParse(row.payload);
  if (!parsed.success) return null;
  const d = row.difficulty as Difficulty;
  if (!(d in DRAW_POINTS) || !ACT_CATEGORIES.includes(row.category as never)) return null;
  return {
    id: row.id,
    word: parsed.data.word,
    accepted: [...new Set([...parsed.data.accepted, ...row.acceptedAnswers])],
    category: row.category,
    difficulty: d,
    moves: parsed.data.moves,
    cards: parsed.data.cards,
  };
}

const roundsFor = (c: ActConfig, n: number) => (c.rounds > 0 ? c.rounds : n <= 4 ? 2 : 1);
const letterPositions = (w: string) => [...w].map((ch, i) => (ch === ' ' ? -1 : i)).filter((i) => i >= 0);

function hintCount(word: string, now: number, s: ActState) {
  const letters = letterPositions(word).length;
  const allowed = letters >= 6 ? 2 : letters >= 4 ? 1 : 0;
  const span = s.deadline - s.startedAt;
  return ACT_TIMING.hintAt.filter((f, i) => i < allowed && now >= s.startedAt + f * span).length;
}

function startTurn(s: ActState, now: number) {
  s.stage = 'choose';
  s.chooseEndsAt = now + ACT_TIMING.chooseMs;
  s.startedAt = 0;
  s.deadline = 0;
  s.lastReveal = null;
}

function beginActing(s: ActState, choice: number, now: number) {
  const t = s.turns[s.index]!;
  t.word = t.choices[choice] ?? t.choices[0]!;
  t.hintPositions = t.hintsByChoice[choice] ?? [];
  s.stage = 'act';
  s.startedAt = now;
  s.deadline = now + s.config.actSeconds * 1000;
}

function closeTurn(s: ActState, now: number, ended: ActReveal['ended'], guessersAtEnd: number) {
  const t = s.turns[s.index]!;
  const word = t.word;
  const points: Record<string, number> = Object.fromEntries(s.players.map((p) => [p, 0]));
  if (word && ended !== 'actor_left') {
    for (const [p, pts] of t.guessed) points[p] = pts;
    const share = t.guessed.size / Math.max(1, guessersAtEnd);
    points[t.actor] = Math.round(DRAW_POINTS[word.difficulty] * ACTOR_SHARE * Math.min(1, share));
  }
  for (const p of s.players) s.scores.set(p, (s.scores.get(p) ?? 0) + (points[p] ?? 0));
  s.lastReveal = { word: word?.word ?? '', points, guessed: t.order.slice(), ended };
  s.stage = 'reveal';
  s.revealEndsAt = now + (ended === 'skipped' || ended === 'actor_left' ? ACT_TIMING.shortRevealMs : ACT_TIMING.revealMs);
}

function elapsedFor(s: ActState, raw: unknown, now: number) {
  const serverElapsed = now - s.startedAt;
  const c = (raw as { clientElapsedMs?: unknown }).clientElapsedMs;
  const reported = typeof c === 'number' && Number.isFinite(c) ? c : serverElapsed;
  return Math.min(serverElapsed, Math.max(reported, serverElapsed - ACT_TIMING.maxLatencyCompMs));
}

function ranking(s: ActState) {
  return placesFromScores(s.players.map((p) => ({ playerId: p, score: s.scores.get(p) ?? 0 }))).map((r) => ({
    ...r,
    correct: s.correct.get(r.playerId) ?? 0,
  }));
}

/**
 * What a practice bot actor does, in order: the suggested moves interleaved
 * with the hint cards (a card after every two moves).
 */
export function botScript(w: ActWord): ({ kind: 'move'; move: string } | { kind: 'card'; card: number })[] {
  const out: ({ kind: 'move'; move: string } | { kind: 'card'; card: number })[] = [];
  let card = 0;
  w.moves.forEach((move, i) => {
    out.push({ kind: 'move', move });
    if (i % 2 === 1 && card < w.cards.length) out.push({ kind: 'card', card: card++ });
  });
  while (card < w.cards.length) out.push({ kind: 'card', card: card++ });
  return out;
}

export const actingModule: GameModule<ActState, ActConfig, ActView> = {
  id: 'acting',
  capabilities: { minPlayers: 2, maxPlayers: 8, ranked: false, safeModeReady: true, spectators: 'none' },

  defaultConfig() {
    return { ...STANDARD_CONFIG };
  },

  validateConfig(raw: unknown, mode: MatchMode): ActConfig {
    if (mode !== 'private') return { ...STANDARD_CONFIG };
    const parsed = configSchema.safeParse(raw ?? {});
    return parsed.success ? parsed.data : { ...STANDARD_CONFIG };
  },

  expectedDurationSec(c) {
    const turns = 4 * roundsFor(c, 4);
    return Math.round(turns * (ACT_TIMING.chooseMs / 2000 + c.actSeconds * 0.75 + ACT_TIMING.revealMs / 1000));
  },

  contentRequest(c) {
    return { gameId: 'acting', count: 400, category: 'mixed', difficulty: c.difficulty };
  },

  setup(players, config, content, rng, now) {
    const words = content.map(asWord).filter((w): w is ActWord => w !== null);
    const byDiff: Record<Difficulty, ActWord[]> = { easy: [], medium: [], hard: [] };
    for (const w of rng.shuffle(words)) byDiff[w.difficulty].push(w);
    const order = rng.shuffle(players.slice());
    const actors = Array.from({ length: roundsFor(config, players.length) }, () => order).flat();
    const pattern: Difficulty[] = config.difficulty === 'mixed' ? ['easy', 'medium', 'hard'] : [config.difficulty, config.difficulty, config.difficulty];
    const need: Record<Difficulty, number> = { easy: 0, medium: 0, hard: 0 };
    for (const d of pattern) need[d] += actors.length;
    for (const d of Object.keys(need) as Difficulty[]) if (byDiff[d].length < need[d]) throw new Error('not_enough_content');
    const turns: Turn[] = actors.map((actor) => {
      const choices = pattern.map((d) => byDiff[d].shift()!);
      return {
        actor,
        choices,
        fallback: rng.int(choices.length),
        word: null,
        beats: [],
        shownCards: new Set(),
        lastBeatAt: 0,
        guessed: new Map(),
        order: [],
        wrong: new Map(),
        close: new Set(),
        lastGuessAt: new Map(),
        guessCount: new Map(),
        hintsByChoice: choices.map((w) => rng.shuffle(letterPositions(w.word))),
        hintPositions: [],
        actorGoneAt: null,
      };
    });
    const s: ActState = {
      players: players.slice(),
      config: { ...config },
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
    const a = raw as ActAction;
    if (!s.players.includes(playerId)) return { ok: false, code: 'not_in_match' };
    if (!a || typeof a !== 'object' || typeof a.kind !== 'string') return { ok: false, code: 'bad_action' };
    const t = s.turns[s.index];
    if (!t || a.turn !== s.index + 1) return { ok: false, code: 'not_accepting' };

    if (a.kind === 'choose') {
      if (playerId !== t.actor) return { ok: false, code: 'not_actor' };
      if (s.stage !== 'choose') return { ok: false, code: 'not_accepting' };
      if (!Number.isInteger(a.choice) || a.choice < 0 || a.choice >= t.choices.length) return { ok: false, code: 'bad_choice' };
      beginActing(s, a.choice, now);
      return { ok: true };
    }

    if (a.kind === 'move' || a.kind === 'card') {
      if (playerId !== t.actor) return { ok: false, code: 'not_actor' };
      if (s.stage !== 'act' || now > s.deadline || !t.word) return { ok: false, code: 'not_accepting' };
      if (t.beats.length >= ACT_LIMITS.movesPerTurn) return { ok: false, code: 'acting_limit' };
      if (now - t.lastBeatAt < ACT_LIMITS.moveGapMs) return { ok: false, code: 'too_fast' };
      if (a.kind === 'move') {
        if (typeof a.move !== 'string' || !ACT_MOVE_IDS.has(a.move)) return { ok: false, code: 'bad_move' };
        t.beats.push({ kind: 'move', move: a.move, at: now });
      } else {
        if (!Number.isInteger(a.card) || a.card < 0 || a.card >= t.word.cards.length) return { ok: false, code: 'bad_card' };
        if (t.shownCards.has(a.card)) return { ok: false, code: 'already_shown' };
        t.shownCards.add(a.card);
        t.beats.push({ kind: 'card', text: t.word.cards[a.card]!, at: now });
      }
      t.lastBeatAt = now;
      return { ok: true };
    }

    if (a.kind === 'guess') {
      if (playerId === t.actor) return { ok: false, code: 'actor_cannot_guess' };
      if (s.stage !== 'act' || now > s.deadline || !t.word) return { ok: false, code: 'not_accepting' };
      if (t.guessed.has(playerId)) return { ok: false, code: 'already_guessed' };
      if (typeof a.text !== 'string') return { ok: false, code: 'bad_action' };
      const text = a.text.trim().replace(/\s+/g, ' ');
      if (!text || text.length > ACT_LIMITS.guessLength) return { ok: false, code: 'bad_guess' };
      if (now - (t.lastGuessAt.get(playerId) ?? -Infinity) < ACT_LIMITS.guessGapMs) return { ok: false, code: 'too_fast' };
      const count = t.guessCount.get(playerId) ?? 0;
      if (count >= ACT_LIMITS.guessesPerTurn) return { ok: false, code: 'no_guesses_left' };
      t.lastGuessAt.set(playerId, now);
      t.guessCount.set(playerId, count + 1);
      const approved = [t.word.word, ...t.word.accepted];
      if (matchApprovedAnswer(text, approved, { ignoreDefiniteArticle: true }) >= 0) {
        t.guessed.set(playerId, guesserPoints(t.word.difficulty, elapsedFor(s, raw, now), s.config.actSeconds));
        t.order.push(playerId);
        t.close.delete(playerId);
        s.correct.set(playerId, (s.correct.get(playerId) ?? 0) + 1);
        return { ok: true };
      }
      t.wrong.set(playerId, [...(t.wrong.get(playerId) ?? []), text]);
      if (approved.some((w) => isClose(norm(text), norm(w)))) t.close.add(playerId);
      else t.close.delete(playerId);
      return { ok: true };
    }
    return { ok: false, code: 'bad_action' };
  },

  tick(s, now, active) {
    s.lastTickAt = now;
    for (let guard = 0; guard < 4; guard++) {
      const t = s.turns[s.index];
      if (!t) return;
      const guessers = s.players.filter((p) => p !== t.actor && active.has(p));
      if (s.stage === 'choose') {
        if (now < s.chooseEndsAt) return;
        if (!active.has(t.actor)) {
          closeTurn(s, now, 'skipped', guessers.length);
          continue;
        }
        beginActing(s, t.fallback, now);
      } else if (s.stage === 'act') {
        if (!active.has(t.actor)) {
          t.actorGoneAt ??= now;
          if (now >= t.actorGoneAt + ACT_TIMING.actorGraceMs) {
            closeTurn(s, now, 'actor_left', guessers.length);
            continue;
          }
        } else t.actorGoneAt = null;
        if (guessers.length > 0 && guessers.every((p) => t.guessed.has(p))) {
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
    if (s.stage === 'act' && t) {
      const span = s.deadline - s.startedAt;
      const wakes = [s.deadline, ...ACT_TIMING.hintAt.map((f) => s.startedAt + f * span)];
      if (t.actorGoneAt !== null) wakes.push(t.actorGoneAt + ACT_TIMING.actorGraceMs);
      const ahead = wakes.filter((w) => w > s.lastTickAt);
      return Math.min(...(ahead.length ? ahead : [s.deadline]));
    }
    if (s.stage === 'reveal') return s.revealEndsAt;
    return null;
  },

  botPlan(s, botId, _rng, skill) {
    const t = s.turns[s.index];
    if (!t) return null;
    const turnNo = s.index + 1;
    if (t.actor === botId) {
      if (s.stage === 'choose') {
        return { key: `${s.index}:choose`, at: s.chooseEndsAt - ACT_TIMING.chooseMs + 1800, action: { kind: 'choose', turn: turnNo, choice: 0 } };
      }
      if (s.stage !== 'act' || !t.word) return null;
      // Only the bot acts on its own turn, so the beats so far are its own script's.
      const next = botScript(t.word)[t.beats.length];
      if (!next) return null;
      const at = Math.max(s.startedAt + 1500, t.lastBeatAt + 3200);
      return { key: `${s.index}:a:${t.beats.length}`, at, action: { ...next, turn: turnNo } };
    }
    // Guesser bots do not "watch"; they answer after the actor has done a few
    // things, more often and sooner with more skill.
    if (s.stage !== 'act' || !t.word || t.guessed.has(botId) || t.beats.length < 3) return null;
    const own = new Rng(`${botId}:${s.index}:${t.word.id}`);
    const ease = { easy: 1, medium: 0.85, hard: 0.7 }[t.word.difficulty];
    if (own.next() > skill * ease + 0.2) return null;
    const span = s.deadline - s.startedAt;
    const at = Math.max(s.startedAt + span * (0.2 + (1 - skill) * 0.45 + own.next() * 0.25), t.lastBeatAt + 2500);
    if (at >= s.deadline) return null;
    return { key: `${s.index}:g`, at, action: { kind: 'guess', turn: turnNo, text: t.word.word, clientElapsedMs: at - s.startedAt } };
  },

  viewFor(s, viewer, now): ActView {
    const t = s.turns[s.index];
    const finished = s.stage === 'finished';
    let turn: ActTurnView | null = null;
    if (t && !finished) {
      const isActor = viewer === t.actor;
      const youGuessed = t.guessed.has(viewer);
      const revealing = s.stage === 'reveal';
      const word = t.word;
      let shape: string[] | null = null;
      if (word && s.stage === 'act' && !isActor) {
        const shown = new Set(t.hintPositions.slice(0, hintCount(word.word, now, s)));
        shape = [...word.word].map((ch, i) => (ch === ' ' ? ' ' : youGuessed || shown.has(i) ? ch : ''));
      }
      const acting = isActor && s.stage === 'act' && word;
      turn = {
        turn: s.index + 1,
        total: s.turns.length,
        actor: t.actor,
        chooseEndsAt: s.chooseEndsAt,
        startedAt: s.startedAt,
        deadline: s.deadline,
        choices:
          isActor && s.stage === 'choose'
            ? t.choices.map((w) => ({ word: w.word, difficulty: w.difficulty, points: DRAW_POINTS[w.difficulty] }))
            : null,
        word: word && (revealing || isActor || youGuessed) ? word.word : null,
        category: word && s.stage !== 'choose' ? word.category : null,
        difficulty: word && s.stage !== 'choose' ? word.difficulty : null,
        shape,
        beats: t.beats.slice(),
        cards: acting ? word.cards.map((text, i) => ({ text, shown: t.shownCards.has(i) })) : null,
        suggested: acting ? word.moves.slice() : null,
        guessed: t.order.slice(),
        youGuessed,
        yourGuesses: revealing ? [] : t.wrong.get(viewer) ?? [],
        close: t.close.has(viewer),
      };
    }
    return {
      stage: s.stage,
      turn,
      reveal: s.stage === 'reveal' ? s.lastReveal : null,
      scores: Object.fromEntries(s.scores),
      final: finished ? { ranking: ranking(s) } : null,
    };
  },

  isFinished(s) {
    return s.stage === 'finished';
  },

  results(s): GameResults {
    const max = s.turns.reduce((a, t) => a + DRAW_POINTS[t.word?.difficulty ?? 'medium'], 0);
    return {
      ranking: ranking(s),
      performance: Object.fromEntries(s.players.map((p) => [p, max > 0 ? Math.min(1, (s.scores.get(p) ?? 0) / max) : 0])),
    };
  },
};
