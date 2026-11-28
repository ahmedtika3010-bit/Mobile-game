/** Acting and Guessing rules: solvable bank, approved moves only, private guesses, scoring, bots. */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { ACT_CATEGORIES, ACT_MOVES, normalizeArabic, usesNewerEmoji } from '@sahra/shared';
import { describe, expect, it } from 'vitest';
import { type ActState, actingModule as acting, actPayloadSchema, botScript } from '../src/games/acting';
import { type ContentRow, Rng } from '../src/games/engine';

type FileWord = { category: string; difficulty: string; word: string; accepted: string[]; moves: string[]; cards: string[] };
const bank: FileWord[] = JSON.parse(readFileSync(join(__dirname, '..', 'prisma', 'content', 'acting_ar_v1.json'), 'utf8'));
const rows: ContentRow[] = bank.map((w, i) => ({
  id: `a${i}`,
  category: w.category,
  difficulty: w.difficulty,
  payload: { word: w.word, accepted: w.accepted, moves: w.moves, cards: w.cards },
  acceptedAnswers: [],
}));

const players = ['a', 'b', 'c'];
const all = new Set(players);
const game = (config: object = {}, ps = players, seed = 'x') => acting.setup(ps, acting.validateConfig(config, 'private'), rows, new Rng(seed), 0);
const turnOf = (s: ActState) => s.turns[s.index]!;
const choose = (s: ActState, choice = 0, at = 100) => acting.onAction(s, turnOf(s).actor, { kind: 'choose', turn: s.index + 1, choice }, at);
const guesser = (s: ActState) => players.find((p) => p !== turnOf(s).actor)!;

describe('acting and guessing', () => {
  it('has a free, old-phone-safe move library with unique ids', () => {
    expect(new Set(ACT_MOVES.map((m) => m.id)).size).toBe(ACT_MOVES.length);
    for (const m of ACT_MOVES) expect(usesNewerEmoji(m.emoji), m.id).toBe(false);
    for (const g of ['action', 'feeling', 'gesture']) expect(ACT_MOVES.filter((m) => m.group === g).length).toBeGreaterThanOrEqual(10);
  });

  it('ships a bank where every word is solvable with its moves and cards', () => {
    const seen = new Set<string>();
    for (const w of bank) {
      const p = actPayloadSchema.safeParse({ word: w.word, accepted: w.accepted, moves: w.moves, cards: w.cards });
      expect(p.success, `${w.word}: ${p.success ? '' : p.error.issues.map((i) => i.message)}`).toBe(true);
      expect(w.moves.length).toBeGreaterThanOrEqual(2);
      expect(w.cards.length).toBeGreaterThanOrEqual(2);
      expect(ACT_CATEGORIES).toContain(w.category);
      const n = normalizeArabic(w.word);
      expect(seen.has(n), `duplicate ${w.word}`).toBe(false);
      seen.add(n);
    }
    // Enough words for the largest match (8 players, one easy, medium and hard choice each).
    for (const d of ['easy', 'medium', 'hard']) expect(bank.filter((w) => w.difficulty === d).length).toBeGreaterThanOrEqual(24);
  });

  it('refuses a card that gives the answer away', () => {
    expect(actPayloadSchema.safeParse({ word: 'قطة', accepted: [], moves: ['eat', 'sleep'], cards: ['القطة بتحب السمك', 'بتقول مياو'] }).success).toBe(false);
    expect(actPayloadSchema.safeParse({ word: 'قطة', accepted: [], moves: ['eat', 'teleport'], cards: ['بتحب السمك', 'بتقول مياو'] }).success).toBe(false);
  });

  it('gives everyone the same number of turns with an easy, a medium and a hard choice', () => {
    const s = game({ rounds: 2 });
    const counts = new Map<string, number>();
    for (const t of s.turns) counts.set(t.actor, (counts.get(t.actor) ?? 0) + 1);
    expect([...counts.values()]).toEqual([2, 2, 2]);
    for (const t of s.turns) expect(t.choices.map((c) => c.difficulty)).toEqual(['easy', 'medium', 'hard']);
    const v = acting.viewFor(s, turnOf(s).actor, 10).turn!;
    expect(v.choices).toHaveLength(3);
    expect(acting.viewFor(s, guesser(s), 10).turn!.choices).toBeNull();
  });

  it('lets the actor play only approved moves and the word’s own cards', () => {
    const s = game();
    choose(s);
    const t = turnOf(s);
    const actor = t.actor;
    const move = (m: string, at: number) => acting.onAction(s, actor, { kind: 'move', turn: 1, move: m }, at);
    expect(move('teleport', 2000)).toEqual({ ok: false, code: 'bad_move' });
    expect(move(t.word!.moves[0]!, 2000)).toEqual({ ok: true });
    expect(move('happy', 2100)).toEqual({ ok: false, code: 'too_fast' });
    expect(acting.onAction(s, guesser(s), { kind: 'move', turn: 1, move: 'happy' }, 4000)).toEqual({ ok: false, code: 'not_actor' });
    expect(acting.onAction(s, actor, { kind: 'card', turn: 1, card: 0 }, 4000)).toEqual({ ok: true });
    expect(acting.onAction(s, actor, { kind: 'card', turn: 1, card: 0 }, 6000)).toEqual({ ok: false, code: 'already_shown' });
    expect(acting.onAction(s, actor, { kind: 'card', turn: 1, card: 9 }, 6000)).toEqual({ ok: false, code: 'bad_card' });
    // Guessers see what was played, never the word, the hidden cards or the suggestions.
    const gv = acting.viewFor(s, guesser(s), 6000).turn!;
    expect(gv.beats.map((b) => b.kind)).toEqual(['move', 'card']);
    expect(gv.word).toBeNull();
    expect(gv.cards).toBeNull();
    expect(gv.suggested).toBeNull();
    expect(JSON.stringify(acting.viewFor(s, guesser(s), 6000))).not.toContain(t.word!.cards[1]!);
    const av = acting.viewFor(s, actor, 6000).turn!;
    expect(av.word).toBe(t.word!.word);
    expect(av.cards!.map((c) => c.shown)).toEqual(t.word!.cards.map((_, i) => i === 0));
    expect(av.suggested).toEqual(t.word!.moves);
  });

  it('keeps wrong guesses private and scores the actor by share of guessers', () => {
    const s = game({ actSeconds: 60 });
    choose(s);
    const t = turnOf(s);
    const [g1, g2] = players.filter((p) => p !== t.actor) as [string, string];
    expect(acting.onAction(s, g1, { kind: 'guess', turn: 1, text: 'حاجة غلط خالص' }, 1000)).toEqual({ ok: true });
    expect(acting.viewFor(s, g1, 1000).turn!.yourGuesses).toEqual(['حاجة غلط خالص']);
    expect(JSON.stringify(acting.viewFor(s, g2, 1000))).not.toContain('حاجة غلط خالص');
    expect(JSON.stringify(acting.viewFor(s, t.actor, 1000))).not.toContain('حاجة غلط خالص');
    expect(acting.onAction(s, g1, { kind: 'guess', turn: 1, text: t.word!.word }, 1300)).toEqual({ ok: false, code: 'too_fast' });
    expect(acting.onAction(s, g1, { kind: 'guess', turn: 1, text: t.word!.word, clientElapsedMs: 5000 }, 5100)).toEqual({ ok: true });
    expect(acting.onAction(s, t.actor, { kind: 'guess', turn: 1, text: t.word!.word }, 5200)).toEqual({ ok: false, code: 'actor_cannot_guess' });
    acting.tick(s, s.deadline, all);
    const r = acting.viewFor(s, g2, s.deadline).reveal!;
    expect(r.ended).toBe('time');
    expect(r.word).toBe(t.word!.word);
    const max = { easy: 100, medium: 130, hard: 160 }[t.word!.difficulty]!;
    expect(r.points[t.actor]).toBe(Math.round(max * 0.8 * 0.5));
    expect(r.points[g2]).toBe(0);
    expect(r.points[g1]).toBeGreaterThan(0);
  });

  it('ends the turn when every guesser got it, and skips an absent actor', () => {
    const s = game();
    choose(s);
    const t = turnOf(s);
    for (const [i, g] of players.filter((p) => p !== t.actor).entries()) {
      acting.onAction(s, g, { kind: 'guess', turn: 1, text: t.word!.accepted[0] ?? t.word!.word }, 3000 + i * 10);
    }
    acting.tick(s, 3100, all);
    expect(acting.viewFor(s, 'a', 3100).reveal!.ended).toBe('all_guessed');
    acting.tick(s, s.revealEndsAt, all);
    expect(s.stage).toBe('choose');
    const absent = new Set(players.filter((p) => p !== turnOf(s).actor));
    acting.tick(s, s.chooseEndsAt, absent);
    expect(acting.viewFor(s, 'a', s.chooseEndsAt).reveal!.ended).toBe('skipped');
  });

  it('shows letter hints at half and three-quarter time', () => {
    const s = game();
    choose(s, 2);
    const t = turnOf(s);
    const g = guesser(s);
    const letters = (now: number) => acting.viewFor(s, g, now).turn!.shape!.filter((c) => c && c !== ' ').length;
    expect(letters(s.startedAt + 100)).toBe(0);
    const n = [...t.word!.word].filter((c) => c !== ' ').length;
    const span = s.deadline - s.startedAt;
    expect(letters(s.startedAt + span * 0.5 + 1)).toBe(n >= 4 ? 1 : 0);
    expect(letters(s.startedAt + span * 0.75 + 1)).toBe(n >= 6 ? 2 : n >= 4 ? 1 : 0);
  });

  it('lets practice bots act out their word and guess', () => {
    const ps = ['me', 'bot_1', 'bot_2'];
    const s = acting.setup(ps, acting.validateConfig({}, 'practice'), rows, new Rng('bots'), 0);
    const active = new Set(ps);
    let guard = 0;
    let botGuesses = 0;
    while (!acting.isFinished(s) && guard++ < 2000) {
      const t = turnOf(s);
      let acted = false;
      for (const b of ['bot_1', 'bot_2']) {
        const plan = acting.botPlan!(s, b, new Rng(b), 0.9);
        if (plan) {
          const now = Math.max(plan.at, s.lastTickAt);
          if (acting.onAction(s, b, plan.action, now).ok) {
            acted = true;
            if ((plan.action as { kind: string }).kind === 'guess') botGuesses++;
          }
          acting.tick(s, now, active);
        }
      }
      if (!acted) acting.tick(s, acting.nextWakeAt(s) ?? s.lastTickAt + 1000, active);
      if (t.actor !== 'me' && t.word) expect(t.beats.length).toBeLessThanOrEqual(botScript(t.word).length);
    }
    expect(acting.isFinished(s)).toBe(true);
    const botTurns = s.turns.filter((t) => t.actor.startsWith('bot_'));
    for (const t of botTurns) expect(t.beats.length).toBeGreaterThanOrEqual(3);
    expect(botGuesses).toBeGreaterThan(0);
  });
});
