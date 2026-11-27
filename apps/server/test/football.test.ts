/** Football Challenges rules: content bank, balanced modes, hidden clues, scoring, duel. */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { FOOTBALL_MODES, normalizeArabic } from '@sahra/shared';
import { describe, expect, it } from 'vitest';
import { type ContentRow, Rng } from '../src/games/engine';
import {
  type FootballState,
  footballModule as football,
  footballPayloadSchema,
  footballPoints,
  linesShownAt,
} from '../src/games/football';
import { QUIZ_TIMING } from '../src/games/quiz';

type FileItem = { category: string; difficulty: string; payload: Record<string, unknown> & { mode: string; answer: string; wrong: string[] } };
const bank: FileItem[] = JSON.parse(readFileSync(join(__dirname, '..', 'prisma', 'content', 'football_ar_v1.json'), 'utf8'));
const rows: ContentRow[] = bank.map((b, i) => ({ id: `f${i}`, category: b.category, difficulty: b.difficulty, payload: b.payload, acceptedAnswers: [] }));

const two = ['a', 'b'];
const game = (config: object, ps = two, seed = 'f') => football.setup(ps, football.validateConfig(config, 'private'), rows, new Rng(seed), 0);
const item = (s: FootballState) => s.items[s.index]!;
const answer = (s: FootballState, p: string, choice: number, at: number) =>
  football.onAction(s, p, { kind: 'answer', questionIndex: s.index, choice, clientElapsedMs: at - s.revealAt }, at);

describe('football challenges', () => {
  it('ships a valid, dated bank for every mode and difficulty', () => {
    const answersByKey = new Set<string>();
    for (const b of bank) {
      const p = footballPayloadSchema.safeParse(b.payload);
      expect(p.success, JSON.stringify(b.payload)).toBe(true);
      expect(b.payload.mode).toBe(b.category);
      expect(String(b.payload.asOf)).toMatch(/^20\d\d-\d\d-\d\d$/);
      // No answer is listed twice among its own choices, even after normalization.
      const norm = [b.payload.answer, ...b.payload.wrong].map((c) => normalizeArabic(c));
      expect(new Set(norm).size).toBe(4);
      const key = JSON.stringify([b.category, b.payload.prompt ?? b.payload.answer, b.payload.from, b.payload.when, b.payload.clubs]);
      expect(answersByKey.has(key), key).toBe(false);
      answersByKey.add(key);
    }
    for (const m of FOOTBALL_MODES) {
      expect(bank.filter((b) => b.category === m).length, m).toBeGreaterThanOrEqual(20);
      for (const d of ['easy', 'medium', 'hard']) expect(bank.filter((b) => b.category === m && b.difficulty === d).length, `${m}/${d}`).toBeGreaterThanOrEqual(3);
    }
  });

  it('mixes all five modes equally in Quick Play and builds from easy to hard', () => {
    const s = football.setup(two, football.validateConfig({ modes: 'player', duel: true }, 'casual'), rows, new Rng('q'), 0);
    expect(s.config).toMatchObject({ modes: 'mixed', duel: false, questionCount: 10 });
    const counts = new Map<string, number>();
    for (const i of s.items) counts.set(i.mode, (counts.get(i.mode) ?? 0) + 1);
    expect([...counts.values()]).toEqual([2, 2, 2, 2, 2]);
    const rank = { easy: 0, medium: 1, hard: 2 } as Record<string, number>;
    const ranks = s.items.map((i) => rank[i.difficulty]!);
    expect(ranks).toEqual(ranks.slice().sort());
  });

  it('lets a private room pick a single mode and difficulty', () => {
    const s = game({ modes: 'transfer', difficulty: 'hard', questionCount: 5 });
    expect(s.items.every((i) => i.mode === 'transfer' && i.difficulty === 'hard')).toBe(true);
    // A thin difficulty is topped up with the nearest one instead of failing to start.
    const thin = game({ modes: 'shared', difficulty: 'hard', questionCount: 10 });
    expect(thin.items).toHaveLength(10);
    expect(thin.items.slice(0, 3).every((i) => i.difficulty === 'hard')).toBe(true);
    expect(thin.items.slice(3).every((i) => i.difficulty === 'medium')).toBe(true);
  });

  it('keeps unrevealed clues on the server and pays more for answering early', () => {
    const s = game({ modes: 'player', questionCount: 5 });
    const q = item(s);
    expect(q.lines.length).toBeGreaterThanOrEqual(3);
    const first = football.viewFor(s, 'a', s.revealAt + 10).question!.football;
    expect(first.lines).toHaveLength(1);
    expect(first.totalLines).toBe(q.lines.length);
    expect(JSON.stringify(football.viewFor(s, 'a', s.revealAt + 10))).not.toContain(q.lines[2]!.text);
    expect(first.nextLineAt).toBe(s.revealAt + s.lineGapMs);
    // The room wakes up for each new line.
    expect(football.nextWakeAt(s)).toBe(s.revealAt + s.lineGapMs);
    const later = football.viewFor(s, 'a', s.revealAt + 2 * s.lineGapMs + 1).question!.football;
    expect(later.lines).toHaveLength(3);
    expect(linesShownAt(q, s.lineGapMs, 0)).toBe(1);
    // All lines are out by 60% of the window, so everyone sees every clue before time runs out.
    expect(s.revealAt + (q.lines.length - 1) * s.lineGapMs).toBeLessThanOrEqual(s.revealAt + (s.deadline - s.revealAt) * 0.6);
    const early = footballPoints(q, s.lineGapMs, 500, s.config);
    const late = footballPoints(q, s.lineGapMs, (q.lines.length - 1) * s.lineGapMs + 10, s.config);
    expect(early).toBe(QUIZ_TIMING.correctPoints + QUIZ_TIMING.maxSpeedBonus);
    expect(late).toBe(QUIZ_TIMING.correctPoints);
  });

  it('shows half the career path at first', () => {
    const s = game({ modes: 'career', questionCount: 5 });
    const q = item(s);
    expect(football.viewFor(s, 'a', s.revealAt).question!.football.lines).toHaveLength(Math.ceil(q.lines.length / 2));
    expect(s.deadline - s.revealAt).toBe((15 + 8) * 1000);
  });

  it('shows dated transfers whole and scores them by speed', () => {
    const s = game({ modes: 'transfer', questionCount: 5 });
    const card = football.viewFor(s, 'a', s.revealAt).question!.football;
    expect(card.lines.map((l) => l.sub)).toEqual(['from', 'to']);
    expect(card.when).toBeTruthy();
    expect(card.asOf).toMatch(/^20/);
    expect(s.deadline - s.revealAt).toBe(15_000);
    const q = item(s);
    expect(answer(s, 'a', q.correct, s.revealAt + 1200)).toEqual({ ok: true });
    expect(answer(s, 'a', q.correct, s.revealAt + 1300)).toEqual({ ok: false, code: 'already_answered' });
    expect(answer(s, 'b', (q.correct + 1) % 4, s.revealAt + 1500)).toEqual({ ok: true });
    // The answer is not in anyone's view until the question closes.
    expect(football.viewFor(s, 'b', s.revealAt + 1600).reveal).toBeNull();
    football.tick(s, s.revealAt + 1600, new Set(two));
    const v = football.viewFor(s, 'b', s.revealAt + 1600);
    expect(v.reveal).toMatchObject({ correctChoice: q.correct, answer: q.answer });
    expect(v.reveal!.points).toEqual({ a: 100 + Math.round((50 * 13) / 14), b: 0 });
  });

  it('decides a duel by questions won, then points', () => {
    expect(() => game({ duel: true }, ['a', 'b', 'c'])).toThrow('duel_needs_two');
    const s = game({ duel: true, questionCount: 5, modes: 'history' });
    let t = 0;
    // a wins 3 questions by being faster; b is right every time, so b has more points.
    for (let i = 0; i < 5; i++) {
      const q = item(s);
      t = s.revealAt;
      const aWins = i < 3;
      answer(s, 'a', aWins ? q.correct : (q.correct + 1) % 4, t + 500);
      answer(s, 'b', q.correct, t + (aWins ? 14_000 : 500));
      football.tick(s, t + 14_100, new Set(two));
      expect(football.viewFor(s, 'a', t + 9100).reveal!.winner).toBe(aWins ? 'a' : 'b');
      football.tick(s, s.revealEndsAt, new Set(two));
    }
    expect(football.isFinished(s)).toBe(true);
    const v = football.viewFor(s, 'a', t + 99_999);
    expect(v.duel!.wins).toEqual({ a: 3, b: 2 });
    expect(v.final!.ranking[0]).toMatchObject({ playerId: 'a', place: 1 });
    expect(v.scores.b).toBeGreaterThan(v.scores.a!);
  });

  it('refuses answers outside the window', () => {
    const s = game({ modes: 'history', questionCount: 5 });
    expect(answer(s, 'a', 0, s.revealAt - 10)).toEqual({ ok: false, code: 'too_early' });
    expect(answer(s, 'a', 0, s.deadline + 10)).toEqual({ ok: false, code: 'too_late' });
    expect(answer(s, 'a', 7, s.revealAt + 10)).toEqual({ ok: false, code: 'bad_choice' });
    expect(answer(s, 'zz', 0, s.revealAt + 10)).toEqual({ ok: false, code: 'not_in_match' });
  });

  it('lets practice bots play every mode', () => {
    const s = football.setup(['me', 'bot_1'], football.validateConfig({}, 'practice'), rows, new Rng('p'), 0);
    while (!football.isFinished(s)) {
      const plan = football.botPlan!(s, 'bot_1', new Rng(`b${s.index}`), 0.7);
      expect(plan).not.toBeNull();
      expect(football.onAction(s, 'bot_1', plan!.action, plan!.at)).toEqual({ ok: true });
      football.tick(s, s.deadline, new Set(['me', 'bot_1']));
      football.tick(s, s.revealEndsAt, new Set(['me', 'bot_1']));
    }
    expect(football.results(s).ranking[0]!.playerId).toBe('bot_1');
  });
});
