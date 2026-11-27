/** Draw and Guess rules: fair rotation, private guesses, hints, scoring, hiding, word bank. */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { DRAW_CATEGORIES, normalizeArabic } from '@sahra/shared';
import { describe, expect, it } from 'vitest';
import { type ContentRow, Rng } from '../src/games/engine';
import {
  DRAW_POINTS,
  DRAW_TIMING,
  type DrawState,
  drawModule as draw,
  drawPayloadSchema,
  guesserPoints,
  hideThreshold,
  isClose,
  sketchOps,
} from '../src/games/draw';

type FileWord = { category: string; difficulty: string; word: string; accepted: string[]; sketch?: unknown };
const bank: FileWord[] = JSON.parse(readFileSync(join(__dirname, '..', 'prisma', 'content', 'draw_ar_v1.json'), 'utf8'));
const rows: ContentRow[] = bank.map((w, i) => ({
  id: `w${i}`,
  category: w.category,
  difficulty: w.difficulty,
  payload: { word: w.word, accepted: w.accepted, ...(w.sketch ? { sketch: w.sketch } : {}) },
  acceptedAnswers: [],
}));

const players = ['a', 'b', 'c', 'd'];
const all = new Set(players);
const game = (config: object = {}, ps = players, seed = 'd') => draw.setup(ps, draw.validateConfig(config, 'private'), rows, new Rng(seed), 0);
const turnOf = (s: DrawState) => s.turns[s.index]!;
const choose = (s: DrawState, choice = 0, at = 100) => draw.onAction(s, turnOf(s).drawer, { kind: 'choose', turn: s.index + 1, choice }, at);
const guesser = (s: DrawState) => players.find((p) => p !== turnOf(s).drawer)!;

describe('draw and guess', () => {
  it('ships a valid word bank in every category and difficulty', () => {
    const words = new Set<string>();
    for (const w of bank) {
      expect(drawPayloadSchema.safeParse({ word: w.word, accepted: w.accepted, sketch: w.sketch }).success, w.word).toBe(true);
      expect(DRAW_CATEGORIES).toContain(w.category);
      const n = normalizeArabic(w.word);
      expect(words.has(n), `duplicate ${w.word}`).toBe(false);
      words.add(n);
    }
    for (const c of DRAW_CATEGORIES) for (const d of ['easy', 'medium', 'hard']) {
      expect(bank.filter((w) => w.category === c && w.difficulty === d).length, `${c}/${d}`).toBeGreaterThanOrEqual(4);
    }
    // Enough words for the largest match (8 players x 3 rounds, three choices each).
    for (const d of ['easy', 'medium', 'hard']) expect(bank.filter((w) => w.difficulty === d).length).toBeGreaterThanOrEqual(24);
    expect(bank.filter((w) => w.sketch).length).toBeGreaterThanOrEqual(20);
  });

  it('gives every player the same number of turns, with one easy, one medium and one hard choice', () => {
    for (const n of [2, 3, 5, 8]) {
      const ps = Array.from({ length: n }, (_, i) => `p${i}`);
      const s = game({ rounds: 2 }, ps);
      const counts = new Map<string, number>();
      for (const t of s.turns) counts.set(t.drawer, (counts.get(t.drawer) ?? 0) + 1);
      expect([...counts.values()]).toEqual(ps.map(() => 2));
      for (const t of s.turns) expect(t.choices.map((w) => w.difficulty)).toEqual(['easy', 'medium', 'hard']);
      const used = s.turns.flatMap((t) => t.choices.map((w) => w.id));
      expect(new Set(used).size).toBe(used.length);
    }
    // Standard matches: two rounds up to four players, one above.
    expect(draw.setup(players, draw.defaultConfig('casual'), rows, new Rng('x'), 0).turns).toHaveLength(8);
    expect(draw.setup([...players, 'e', 'f'], draw.defaultConfig('casual'), rows, new Rng('x'), 0).turns).toHaveLength(6);
    expect(draw.validateConfig({ rounds: 3, teams: true }, 'casual')).toMatchObject({ rounds: 0, teams: false });
  });

  it('shows the choices and the word only to the drawer, and the shape with timed hints to guessers', () => {
    const s = game();
    const drawer = turnOf(s).drawer;
    const g = guesser(s);
    expect(draw.viewFor(s, drawer, 0).turn!.choices).toHaveLength(3);
    expect(draw.viewFor(s, g, 0).turn!.choices).toBeNull();
    expect(choose(s, 2)).toEqual({ ok: true });
    const word = turnOf(s).word!.word;
    expect(draw.viewFor(s, drawer, 200).turn!.word).toBe(word);
    const v = draw.viewFor(s, g, 200).turn!;
    expect(v.word).toBeNull();
    expect(v.shape).toHaveLength([...word].length);
    const hidden = (shape: string[]) => shape.filter((c) => c === '').length;
    const letters = [...word].filter((c) => c !== ' ').length;
    expect(hidden(v.shape!)).toBe(letters);
    const late = draw.viewFor(s, g, s.startedAt + 0.8 * (s.deadline - s.startedAt)).turn!;
    const hints = letters >= 6 ? 2 : letters >= 4 ? 1 : 0;
    expect(hidden(late.shape!)).toBe(letters - hints);
  });

  it('keeps wrong guesses private, hints when close, and scores by whole seconds', () => {
    const s = game();
    choose(s, 0); // easy
    const t = turnOf(s);
    const [g1, g2] = players.filter((p) => p !== t.drawer);
    const word = t.word!.word;
    expect(draw.onAction(s, g1!, { kind: 'guess', turn: 1, text: 'كلمة غلط خالص' }, 1_000)).toEqual({ ok: true });
    expect(draw.viewFor(s, g1!, 1_000).turn!.yourGuesses).toEqual(['كلمة غلط خالص']);
    expect(draw.viewFor(s, g2!, 1_000).turn!.yourGuesses).toEqual([]);
    expect(draw.onAction(s, g1!, { kind: 'guess', turn: 1, text: 'تاني' }, 1_100)).toEqual({ ok: false, code: 'too_fast' });
    expect(draw.onAction(s, t.drawer, { kind: 'guess', turn: 1, text: word }, 2_000)).toEqual({ ok: false, code: 'drawer_cannot_guess' });
    // The definite article and spelling normalization still count.
    expect(draw.onAction(s, g1!, { kind: 'guess', turn: 1, text: `ال${word}`, clientElapsedMs: 9_400 }, 10_000)).toEqual({ ok: true });
    expect(draw.viewFor(s, g2!, 10_000).turn!.guessed).toEqual([g1]);
    expect(draw.viewFor(s, g1!, 10_000).turn!.word).toBe(word);
    expect(t.guessed.get(g1!)).toBe(guesserPoints(t.word!.difficulty, 9_400, 80));
    expect(guesserPoints('easy', 0, 80)).toBe(DRAW_POINTS.easy);
    expect(guesserPoints('easy', 999, 80)).toBe(guesserPoints('easy', 0, 80));
    expect(guesserPoints('hard', 79_000, 80)).toBe(Math.round((DRAW_POINTS.hard * 0.4) / 5) * 5);
    expect(isClose('برتقانة', 'برتقانه')).toBe(true);
    expect(isClose('شمس', 'شمسي')).toBe(false); // too short to hint
    expect(isClose('سلحفاة', 'سلحفاة')).toBe(false);
  });

  it('ends the turn when everyone guessed and pays the drawer by the share who got it', () => {
    const s = game();
    choose(s, 1); // medium
    const t = turnOf(s);
    const word = t.word!.word;
    let at = 1_000;
    for (const p of players.filter((p) => p !== t.drawer)) {
      draw.onAction(s, p, { kind: 'guess', turn: 1, text: word }, (at += 700));
    }
    draw.tick(s, at, all);
    expect(s.stage).toBe('reveal');
    expect(s.lastReveal!.ended).toBe('all_guessed');
    expect(s.lastReveal!.points[t.drawer]).toBe(Math.round(DRAW_POINTS.medium * 0.8));
    draw.tick(s, s.revealEndsAt, all);
    expect(s.stage).toBe('choose');
    expect(s.index).toBe(1);
  });

  it('validates strokes and streams them to everyone except players who hid the drawing', () => {
    const s = game();
    choose(s, 0);
    const t = turnOf(s);
    const [g1, g2, g3] = players.filter((p) => p !== t.drawer);
    const ok = draw.onAction(s, t.drawer, { kind: 'draw', turn: 1, ops: [{ t: 'b', c: 1, w: 0, p: [10, 10, 20, 20] }, { t: 'p', p: [30, 30] }] }, 500);
    expect(ok).toEqual({ ok: true });
    for (const bad of [
      [{ t: 'p', p: [1, 1] }, { t: 'u' }, { t: 'p', p: [1, 1] }], // points after undo with no open stroke
      [{ t: 'b', c: 99, w: 0, p: [1, 1] }],
      [{ t: 'b', c: 0, w: 0, p: [1, 1, 2] }],
      [{ t: 'b', c: 0, w: 0, p: [1, 1001] }],
      [{ t: 'text', s: 'كلمة' }],
    ]) {
      expect(draw.onAction(s, t.drawer, { kind: 'draw', turn: 1, ops: bad }, 600)).toEqual({ ok: false, code: 'bad_ops' });
    }
    expect(draw.onAction(s, g1!, { kind: 'draw', turn: 1, ops: [{ t: 'x' }] }, 600)).toEqual({ ok: false, code: 'not_drawer' });
    expect(draw.streamFor!(s, g1!)).toEqual({ key: 't1', items: t.ops });
    expect(t.ops).toHaveLength(2);
    // One of three guessers hides it: only their stream goes blank.
    draw.onAction(s, g1!, { kind: 'hide', turn: 1 }, 700);
    expect(draw.streamFor!(s, g1!)).toEqual({ key: 't1:hidden', items: [] });
    expect(draw.streamFor!(s, g2!)!.items).toHaveLength(2);
    draw.tick(s, 800, all);
    expect(s.stage).toBe('draw');
    // A second one (2 of 3) stops the turn for everyone; the drawer scores nothing.
    draw.onAction(s, g2!, { kind: 'hide', turn: 1 }, 900);
    draw.tick(s, 900, all);
    expect(s.lastReveal).toMatchObject({ ended: 'stopped' });
    expect(s.lastReveal!.points[t.drawer]).toBe(0);
    expect(draw.streamFor!(s, g3!)).toEqual({ key: 't1:stopped', items: [] });
    expect([1, 2, 3, 4, 5, 8].map(hideThreshold)).toEqual([1, 2, 2, 2, 3, 4]);
  });

  it('picks a word on timeout, skips an absent drawer and ends the turn if the drawer leaves', () => {
    const s = game();
    const t = turnOf(s);
    draw.tick(s, s.chooseEndsAt, all);
    expect(s.stage).toBe('draw');
    expect(t.word).toBe(t.choices[t.fallback]);
    const without = new Set(players.filter((p) => p !== t.drawer));
    draw.tick(s, s.startedAt + 1_000, without);
    expect(s.stage).toBe('draw');
    draw.tick(s, s.startedAt + 1_000 + DRAW_TIMING.drawerGraceMs, without);
    expect(s.lastReveal).toMatchObject({ ended: 'drawer_left' });
    expect(Object.values(s.lastReveal!.points).every((p) => p === 0)).toBe(true);
    draw.tick(s, s.revealEndsAt, all);
    const next = turnOf(s);
    draw.tick(s, s.chooseEndsAt, new Set(players.filter((p) => p !== next.drawer)));
    expect(s.lastReveal).toMatchObject({ ended: 'skipped' });
  });

  it('balances teams by averaging, and gives teammates the same place', () => {
    const ps = ['a', 'b', 'c', 'd', 'e'];
    const s = game({ teams: true, rounds: 1 }, ps);
    const teams = draw.viewFor(s, 'a', 0).teams!;
    const sizes = [0, 1].map((t) => Object.values(teams.of).filter((x) => x === t).length).sort();
    expect(sizes).toEqual([2, 3]);
    // Drawers alternate between the teams.
    expect(s.turns.slice(0, 4).map((t) => teams.of[t.drawer])).toEqual([0, 1, 0, 1]);
    for (const p of ps) s.scores.set(p, teams.of[p] === 0 ? 100 : 90);
    s.stage = 'finished';
    const final = draw.viewFor(s, 'a', 0).final!;
    expect(final.teamScores).toEqual([100, 90]);
    for (const r of final.ranking) expect(r.place).toBe(teams.of[r.playerId] === 0 ? 1 : 2);
  });

  it('lets a practice bot draw its sketch and guess only after something was drawn', () => {
    const ps = ['me', 'bot_1', 'bot_2'];
    const s = draw.setup(ps, draw.defaultConfig('practice'), rows, new Rng('p'), 0);
    const rng = new Rng('b');
    // Find the bot's turn and let it choose and draw.
    while (!turnOf(s).drawer.startsWith('bot_')) s.index++;
    const t = turnOf(s);
    const bot = t.drawer;
    const pick = draw.botPlan!(s, bot, rng, 0.6)!;
    expect(t.choices[(pick.action as { choice: number }).choice]!.sketch).not.toBeNull();
    draw.onAction(s, bot, pick.action, pick.at);
    const total = sketchOps(t.word!.sketch).length;
    const other = ps.find((p) => p !== bot && p !== 'me')!;
    expect(draw.botPlan!(s, other, rng, 1)).toBeNull(); // nothing drawn yet
    for (let i = 0; i < total; i++) {
      const plan = draw.botPlan!(s, bot, rng, 0.6)!;
      expect(draw.onAction(s, bot, plan.action, plan.at)).toEqual({ ok: true });
    }
    expect(draw.botPlan!(s, bot, rng, 0.6)).toBeNull();
    expect(t.ops).toHaveLength(total);
  });
});
