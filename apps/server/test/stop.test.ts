/** Stop / Atobees Complete rules: letters, normalization, unique vs shared, hidden unknown words, appeals. */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { STOP_CATEGORIES } from '@sahra/shared';
import { describe, expect, it } from 'vitest';
import type { ContentRow } from '../src/games/engine';
import { Rng } from '../src/games/engine';
import { buildDictionary, playableLetters, scoreRound, stopInitial, stopModule as stop, type StopState } from '../src/games/stop';

const lists = JSON.parse(readFileSync(join(__dirname, '../prisma/content/stop_ar_v1.json'), 'utf8')) as { category: string; words: string[] }[];
const content: ContentRow[] = lists.map((l, i) => ({ id: `d${i}`, category: l.category, difficulty: 'medium', acceptedAnswers: [], payload: { words: l.words } }));
const dict = buildDictionary(content);
const players = ['a', 'b', 'c'];
const all = new Set(players);
const game = (rounds = 3) => stop.setup(players, stop.validateConfig({ rounds }, 'private'), content, new Rng('s'), 0);
/** Forces the current round's letter (setup draws a random one). */
const withLetter = (s: StopState, l: string) => (s.letters[s.round - 1] = l);

describe('stop', () => {
  it('ships a dictionary that covers enough letters', () => {
    expect(playableLetters(dict).length).toBeGreaterThanOrEqual(15);
    for (const c of STOP_CATEGORIES) expect(dict[c].size, c).toBeGreaterThanOrEqual(100);
  });

  it('ignores hamza, taa marbuta and the article when checking the letter and the word', () => {
    expect(stopInitial('الأردن')).toBe('ا');
    expect(stopInitial('إيطاليا')).toBe('ا');
    const sheets = new Map([
      ['a', { country: 'الاردن', animal: 'أرنب', boy: 'احمد', girl: 'أمل', plant: 'أناناس', object: 'إبريق' }],
      ['b', { country: 'أردن', animal: 'أسد', boy: 'بلال', girl: 'كلام فاضي' }],
      ['c', {}],
    ]);
    const r = scoreRound('ا', players, sheets, dict);
    expect(r.cells.country.a).toMatchObject({ verdict: 'shared', points: 5 });
    expect(r.cells.country.b).toMatchObject({ verdict: 'shared', points: 5 });
    expect(r.cells.animal.a).toMatchObject({ verdict: 'unique', points: 10 });
    expect(r.cells.boy.b).toMatchObject({ verdict: 'wrong_letter', points: 0 });
    expect(r.cells.girl.b).toMatchObject({ verdict: 'wrong_letter' });
    expect(r.cells.plant.c).toMatchObject({ verdict: 'empty', points: 0 });
    expect(r.points).toEqual({ a: 5 + 10 + 10 + 10 + 10 + 10, b: 5 + 10, c: 0 });
  });

  it('keeps answers secret while playing and lets people edit until the timer ends', () => {
    const s = game();
    withLetter(s, 'م');
    expect(stop.onAction(s, 'a', { kind: 'answers', round: 1, answers: { boy: 'محمد' } }, 1000)).toEqual({ ok: true });
    expect(stop.onAction(s, 'a', { kind: 'answers', round: 1, answers: { boy: 'مازن', girl: 'مريم' } }, 2000)).toEqual({ ok: true });
    expect(stop.viewFor(s, 'a', 0).yourAnswers).toEqual({ boy: 'مازن', girl: 'مريم' });
    expect(JSON.stringify(stop.viewFor(s, 'b', 0))).not.toContain('مازن');
    expect(stop.onAction(s, 'a', { kind: 'answers', round: 1, answers: { boy: 'مراد' } }, s.stageEndsAt + 1)).toEqual({ ok: false, code: 'not_accepting' });
  });

  it('ends a round early only when everyone connected is done', () => {
    const s = game();
    stop.onAction(s, 'a', { kind: 'done', round: 1 }, 0);
    stop.onAction(s, 'b', { kind: 'answers', round: 1, answers: {}, done: true }, 0);
    stop.tick(s, 10, all);
    expect(s.stage).toBe('answer');
    stop.tick(s, 10, new Set(['a', 'b']));
    expect(s.stage).toBe('review');
  });

  it('shows an unknown word only to its author, who can appeal it once', () => {
    const s = game();
    withLetter(s, 'م');
    stop.onAction(s, 'a', { kind: 'answers', round: 1, answers: { animal: 'مخلوق غريب', boy: 'محمد' } }, 0);
    stop.tick(s, s.stageEndsAt, all);
    const mine = stop.viewFor(s, 'a', 0).result!;
    const theirs = stop.viewFor(s, 'b', 0).result!;
    expect(mine.cells.animal.a).toMatchObject({ verdict: 'unknown', text: 'مخلوق غريب' });
    expect(theirs.cells.animal.a).toEqual({ verdict: 'unknown', text: null, points: 0 });
    expect(theirs.cells.boy.a).toMatchObject({ verdict: 'unique', text: 'محمد' });
    expect(stop.onAction(s, 'b', { kind: 'appeal', round: 1, category: 'animal' }, 0)).toEqual({ ok: false, code: 'not_appealable' });
    expect(stop.onAction(s, 'a', { kind: 'appeal', round: 1, category: 'boy' }, 0)).toEqual({ ok: false, code: 'not_appealable' });
    expect(stop.onAction(s, 'a', { kind: 'appeal', round: 1, category: 'animal' }, 0)).toEqual({ ok: true });
    expect(stop.onAction(s, 'a', { kind: 'appeal', round: 1, category: 'animal' }, 0)).toEqual({ ok: false, code: 'already_appealed' });
    expect(stop.viewFor(s, 'a', 0).result!.cells.animal.a!.appealed).toBe(true);
    expect(stop.results(s).suggestions).toEqual([{ gameId: 'stop', category: 'animal', word: 'مخلوق غريب', userId: 'a' }]);
  });

  it('uses a different letter each round and finishes with a ranking', () => {
    const s = game(3);
    expect(new Set(s.letters).size).toBe(3);
    while (s.stage !== 'finished') {
      if (s.stage === 'answer') {
        const l = s.letters[s.round - 1]!;
        const word = [...dict.boy.entries()].find(([k]) => k[0] === l)![1];
        stop.onAction(s, 'b', { kind: 'answers', round: s.round, answers: { boy: word } }, s.stageEndsAt - 1);
      }
      stop.tick(s, s.stageEndsAt, all);
    }
    const f = stop.viewFor(s, 'a', 0).final!;
    expect(f.rounds).toHaveLength(3);
    expect(f.ranking[0]).toMatchObject({ playerId: 'b', score: 30, place: 1, correct: 3 });
  });

  it('gives practice bots real dictionary words for the letter', () => {
    const s = game();
    const plan = stop.botPlan!(s, 'c', new Rng('b'), 1)!;
    const a = plan.action as { answers: Record<string, string>; done: boolean };
    expect(a.done).toBe(true);
    expect(Object.keys(a.answers)).toHaveLength(6);
    for (const w of Object.values(a.answers)) expect(stopInitial(w)).toBe(s.letters[0]);
  });
});
