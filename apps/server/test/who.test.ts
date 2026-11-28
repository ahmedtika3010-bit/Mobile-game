/** Who Among Us? rules: anonymity, minimum votes, anti-targeting cap, no winners. */
import { describe, expect, it } from 'vitest';
import type { ContentRow } from '../src/games/engine';
import { Rng } from '../src/games/engine';
import { WHO_LIMITS, type WhoState, maxHighlights, whoModule as who } from '../src/games/who';

const cats = ['funny', 'friends', 'everyday', 'personality'];
const content: ContentRow[] = Array.from({ length: 14 }, (_, i) => ({
  id: `q${i}`,
  category: cats[i % 4]!,
  difficulty: 'medium',
  acceptedAnswers: [],
  payload: { text: `مين فينا سؤال رقم ${i}؟` },
}));
const players = ['a', 'b', 'c', 'd', 'e', 'f'];
const all = new Set(players);
const newGame = (n = players, questionCount = 8) =>
  who.setup(n, who.validateConfig({ questionCount }, 'private'), content, new Rng('x'), 0);

function voteAll(s: WhoState, target: (p: string) => string | 'skip') {
  for (const p of s.players) {
    const t = target(p);
    const action = t === 'skip' ? { kind: 'skip', question: s.index + 1 } : { kind: 'vote', question: s.index + 1, target: t };
    expect(who.onAction(s, p, action, 0)).toEqual({ ok: true });
  }
  who.tick(s, 0, all);
}
const next = (s: WhoState) => who.tick(s, s.stageEndsAt, all);

describe('who among us', () => {
  it('never sends who voted for whom', () => {
    const s = newGame();
    who.onAction(s, 'a', { kind: 'vote', question: 1, target: 'b' }, 0);
    const v = who.viewFor(s, 'c', 0);
    expect(v.yourChoice).toBeNull();
    expect(v.answeredCount).toBe(1);
    expect(JSON.stringify(v)).not.toContain('"b"');
    expect(who.viewFor(s, 'a', 0).yourChoice).toBe('b');
  });

  it('shows the pick, and counts only with enough votes', () => {
    const s = newGame();
    voteAll(s, (p) => (p === 'b' ? 'a' : 'b'));
    expect(s.stage).toBe('reveal');
    const r = who.viewFor(s, 'a', 0).reveal!;
    expect(r).toMatchObject({ kind: 'pick', picks: ['b'], votes: 6 });
    expect(r.counts).toEqual({ b: 5 });
  });

  it('hides results when too few people voted', () => {
    const s = newGame();
    voteAll(s, (p) => (p === 'a' ? 'b' : p === 'c' ? 'b' : 'skip'));
    expect(who.viewFor(s, 'a', 0).reveal).toMatchObject({ kind: 'too_few', picks: [], counts: null, votes: 2 });
    expect(WHO_LIMITS.minVotes).toBe(3);
  });

  it('does not single out the same player again and again', () => {
    const s = newGame(players, 12);
    const cap = maxHighlights(12, players.length);
    const shown: string[] = [];
    for (let i = 0; i < 12; i++) {
      voteAll(s, (p) => (p === 'a' ? 'b' : 'a'));
      shown.push(who.viewFor(s, 'b', 0).reveal!.kind);
      next(s);
    }
    expect(shown.filter((k) => k === 'pick')).toHaveLength(cap);
    expect(shown.slice(cap).every((k) => k === 'spread')).toBe(true);
    expect(s.stage).toBe('finished');
  });

  it('can not vote for yourself, twice, or late', () => {
    const s = newGame();
    expect(who.onAction(s, 'a', { kind: 'vote', question: 1, target: 'a' }, 0)).toEqual({ ok: false, code: 'bad_target' });
    expect(who.onAction(s, 'a', { kind: 'skip', question: 2 }, 0)).toEqual({ ok: false, code: 'not_accepting' });
    expect(who.onAction(s, 'a', { kind: 'skip', question: 1 }, 0)).toEqual({ ok: true });
    expect(who.onAction(s, 'a', { kind: 'vote', question: 1, target: 'b' }, 0)).toEqual({ ok: false, code: 'already_answered' });
  });

  it('ends with titles for everyone and no winner', () => {
    const s = newGame(players, 5);
    for (let i = 0; i < 5; i++) {
      voteAll(s, (p) => (p === 'c' ? 'skip' : p === 'a' ? 'b' : 'a'));
      next(s);
    }
    const f = who.viewFor(s, 'a', 0).final!;
    expect(Object.keys(f.titles)).toHaveLength(6);
    expect(f.titles['f']).toBe('mystery');
    expect(f.skips).toBe(5);
    const res = who.results(s);
    expect(res.ranking.every((r) => r.place === 1)).toBe(true);
    expect(res.ranking.find((r) => r.playerId === 'a')!.score).toBe(5);
    expect(who.capabilities.ranked).toBe(false);
    expect(who.capabilities.rewards).toBe('participation');
  });

  it('moves on when time runs out or players drop', () => {
    const s = newGame(['a', 'b', 'c'], 5);
    who.onAction(s, 'a', { kind: 'vote', question: 1, target: 'b' }, 0);
    who.tick(s, 0, new Set(['a']));
    expect(s.stage).toBe('reveal');
    expect(who.viewFor(s, 'a', 0).reveal!.kind).toBe('too_few');
  });
});
