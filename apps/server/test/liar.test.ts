/** Who Is the Liar? rules: secrecy, rotation, voting outcomes and timeouts. */
import { describe, expect, it } from 'vitest';
import type { ContentRow } from '../src/games/engine';
import { Rng } from '../src/games/engine';
import { LIAR_POINTS, LIAR_TIMING, type LiarState, liarModule as liar } from '../src/games/liar';

const pair = (i: number): ContentRow => ({
  id: `p${i}`,
  category: 'daily',
  difficulty: 'medium',
  acceptedAnswers: [],
  payload: { main: `سؤال أساسي ${i}؟`, odd: `سؤال مختلف ${i}؟`, options: ['أ', 'ب', 'ج', 'د'] },
});
const content = [0, 1, 2, 3, 4, 5].map(pair);
const players = ['a', 'b', 'c', 'd'];
const all = new Set(players);

function newGame(seed = 's1', rounds = 3, n = players) {
  return liar.setup(n, liar.validateConfig({ rounds }, 'private'), content, new Rng(seed), 0);
}
const citizens = (s: LiarState) => s.players.filter((p) => p !== s.liar);

function answerAll(s: LiarState, now: number) {
  for (const p of s.players) expect(liar.onAction(s, p, { kind: 'answer', round: s.round + 1, choice: 1 }, now)).toEqual({ ok: true });
  liar.tick(s, now, all);
}
function voteAll(s: LiarState, target: (p: string) => string, now: number) {
  for (const p of s.players) liar.onAction(s, p, { kind: 'readyToVote' }, now);
  liar.tick(s, now, all);
  expect(s.stage).toBe('vote');
  for (const p of s.players) expect(liar.onAction(s, p, { kind: 'vote', target: target(p) }, now)).toEqual({ ok: true });
  liar.tick(s, now, all);
}

describe('liar game', () => {
  it('hides the odd question, the liar and the main question until the discussion', () => {
    const s = newGame();
    expect(s.stage).toBe('answer');
    const lv = liar.viewFor(s, s.liar, 0);
    const cv = liar.viewFor(s, citizens(s)[0]!, 0);
    expect(lv.yourQuestion).toBe('سؤال مختلف 0؟');
    expect(cv.yourQuestion).toBe('سؤال أساسي 0؟');
    for (const v of [lv, cv]) {
      expect(v.youAreLiar).toBeNull();
      expect(v.mainQuestion).toBeNull();
      expect(v.answers).toBeNull();
      expect(v.lastRound).toBeNull();
    }
    expect(JSON.stringify(lv)).not.toContain('سؤال أساسي');
    expect(JSON.stringify(cv)).not.toContain('سؤال مختلف');
    const outsider = liar.viewFor(s, 'zz', 0);
    expect(outsider.yourQuestion).toBeNull();
    expect(JSON.stringify(outsider)).not.toContain('سؤال');
  });

  it('reveals the main question and all answers for the discussion, but not the liar', () => {
    const s = newGame();
    answerAll(s, 1000);
    expect(s.stage).toBe('discuss');
    const cv = liar.viewFor(s, citizens(s)[0]!, 1000);
    expect(cv.mainQuestion).toBe('سؤال أساسي 0؟');
    expect(cv.answers).toEqual(Object.fromEntries(players.map((p) => [p, 1])));
    expect(cv.youAreLiar).toBe(false);
    expect(liar.viewFor(s, s.liar, 1000).youAreLiar).toBe(true);
    expect(JSON.stringify(cv)).not.toContain('سؤال مختلف');
    expect(JSON.stringify(cv)).not.toContain(`"${s.liar}":true`);
  });

  it('catching the liar rewards everyone who voted for them', () => {
    const s = newGame('s2', 1);
    answerAll(s, 0);
    const theLiar = s.liar;
    const [c1] = citizens(s);
    voteAll(s, (p) => (p === theLiar ? c1! : p === c1 ? s.players.find((x) => x !== c1 && x !== theLiar)! : theLiar), 0);
    expect(s.stage).toBe('finished');
    const r = s.history[0]!;
    expect(r).toMatchObject({ liar: theLiar, accused: theLiar, caught: true, oddQuestion: 'سؤال مختلف 0؟' });
    const voters = s.players.filter((p) => p !== theLiar && p !== c1);
    for (const p of voters) expect(s.scores.get(p)).toBe(LIAR_POINTS.caughtVote);
    expect(s.scores.get(c1!)).toBe(0);
    expect(s.scores.get(theLiar)).toBe(0);
    const v = liar.viewFor(s, c1!, 0);
    expect(v.final!.rounds).toHaveLength(1);
    expect(v.lastRound!.liar).toBe(theLiar);
  });

  it('a tie or a wrong accusation lets the liar score', () => {
    const s = newGame('s3', 1);
    answerAll(s, 0);
    const [c1, c2, c3] = citizens(s);
    // c1 and c2 vote for each other, c3 and the liar vote for c1 → c1 accused.
    const votes: Record<string, string> = { [c1!]: c2!, [c2!]: c1!, [c3!]: c1!, [s.liar]: c1! };
    voteAll(s, (p) => votes[p]!, 0);
    expect(s.history[0]).toMatchObject({ accused: c1, caught: false });
    expect(s.scores.get(s.liar)).toBe(LIAR_POINTS.liarSurvived);
  });

  it('rotates the liar so nobody repeats before everyone had a turn', () => {
    const s = newGame('s4', 4);
    const liars: string[] = [];
    let now = 0;
    for (let r = 0; r < 4; r++) {
      liars.push(s.liar);
      answerAll(s, now);
      voteAll(s, (p) => players.find((x) => x !== p)!, now);
      now = s.stageEndsAt || now;
      liar.tick(s, now + LIAR_TIMING.roundEndMs, all);
    }
    expect(s.stage).toBe('finished');
    expect(new Set(liars).size).toBe(4);
    expect(liar.results(s).ranking).toHaveLength(4);
  });

  it('rejects bad actions', () => {
    const s = newGame();
    expect(liar.onAction(s, 'a', { kind: 'answer', round: 2, choice: 0 }, 0)).toEqual({ ok: false, code: 'not_accepting' });
    expect(liar.onAction(s, 'a', { kind: 'answer', round: 1, choice: 9 }, 0)).toEqual({ ok: false, code: 'bad_choice' });
    expect(liar.onAction(s, 'a', { kind: 'answer', round: 1, choice: 0 }, 0)).toEqual({ ok: true });
    expect(liar.onAction(s, 'a', { kind: 'answer', round: 1, choice: 1 }, 0)).toEqual({ ok: false, code: 'already_answered' });
    expect(liar.onAction(s, 'a', { kind: 'vote', target: 'b' }, 0)).toEqual({ ok: false, code: 'not_accepting' });
    expect(liar.onAction(s, 'zz', { kind: 'readyToVote' }, 0)).toEqual({ ok: false, code: 'not_in_match' });
  });

  it('keeps going when players time out or drop', () => {
    const s = newGame('s5', 2);
    liar.onAction(s, 'a', { kind: 'answer', round: 1, choice: 0 }, 0);
    liar.tick(s, s.stageEndsAt, all); // the others never answer
    expect(s.stage).toBe('discuss');
    expect(liar.viewFor(s, 'a', 0).answers!['b']).toBeNull();
    liar.tick(s, s.stageEndsAt, all);
    expect(s.stage).toBe('vote');
    const here = new Set(['a', 'b']);
    liar.onAction(s, 'a', { kind: 'vote', target: 'b' }, 0);
    liar.onAction(s, 'b', { kind: 'vote', target: 'a' }, 0);
    liar.tick(s, 0, here);
    expect(s.stage).toBe('roundEnd');
    liar.tick(s, s.stageEndsAt, here);
    expect(s.stage).toBe('answer');
    expect(s.round).toBe(1);
  });

  it('uses the standard config in public matches and needs enough pairs', () => {
    expect(liar.validateConfig({ rounds: 6, difficulty: 'hard' }, 'casual')).toMatchObject({ rounds: 3, difficulty: 'medium' });
    expect(liar.validateConfig({ rounds: 6, difficulty: 'hard' }, 'private')).toMatchObject({ rounds: 6, difficulty: 'hard' });
    expect(() => liar.setup(players, liar.validateConfig({ rounds: 3 }, 'private'), content.slice(0, 2), new Rng('x'), 0)).toThrow(
      'not_enough_content',
    );
    const bad = { ...pair(9), payload: { main: 'نفس السؤال؟', odd: 'نفس السؤال؟', options: ['أ', 'ب', 'ج'] } };
    expect(() => liar.setup(players, liar.validateConfig({ rounds: 1 }, 'private'), [bad], new Rng('x'), 0)).toThrow('not_enough_content');
  });
});
