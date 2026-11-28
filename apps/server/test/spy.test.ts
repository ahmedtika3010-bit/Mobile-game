/** Spy game rules: secrecy, turn flow, voting outcomes, guesses and timeouts. */
import { describe, expect, it } from 'vitest';
import type { ContentRow } from '../src/games/engine';
import { Rng } from '../src/games/engine';
import { SPY_POINTS, SPY_TIMING, type SpyState, maxSpies, spyModule as spy } from '../src/games/spy';

const pack: ContentRow = {
  id: 'pack1',
  category: 'places',
  difficulty: 'medium',
  acceptedAnswers: [],
  payload: {
    words: ['المطار', 'المستشفى', 'المدرسة', 'الشاطئ', 'السينما', 'المطعم', 'البنك', 'المكتبة', 'الفندق', 'المول', 'الجيم'],
    questions: ['س1؟', 'س2؟', 'س3؟', 'س4؟', 'س5؟', 'س6؟', 'س7؟', 'س8؟'],
  },
};
const players = ['a', 'b', 'c', 'd'];
const all = new Set(players);

function newGame(seed = 'seed-1', n = players) {
  const config = spy.validateConfig({}, 'private');
  return spy.setup(n, config, [pack], new Rng(seed), 0);
}
const spyOf = (s: SpyState) => [...s.spies][0]!;
const citizens = (s: SpyState) => s.players.filter((p) => !s.spies.has(p));

/** Plays every question turn instantly (asker asks the next player, answer 0). */
function playTurns(s: SpyState, t0 = SPY_TIMING.rolesMs) {
  let now = t0;
  spy.tick(s, now, all);
  while (s.stage === 'ask' || s.stage === 'answer') {
    const turn = s.turns[s.turnIndex]!;
    if (s.stage === 'ask') {
      const target = s.players.find((p) => p !== turn.asker)!;
      expect(spy.onAction(s, turn.asker, { kind: 'ask', turn: s.turnIndex, question: 0, target }, now)).toEqual({ ok: true });
      expect(spy.onAction(s, target, { kind: 'answer', turn: s.turnIndex, answer: 2 }, now)).toEqual({ ok: true });
    }
    now = s.stageEndsAt;
    spy.tick(s, now, all);
  }
  return now;
}

describe('spy game', () => {
  it('hides the word from the spy and spy identities from everyone', () => {
    const s = newGame();
    expect(s.spies.size).toBe(1);
    const sv = spy.viewFor(s, spyOf(s), 0);
    expect(sv.role).toBe('spy');
    expect(sv.word).toBeNull();
    expect(sv.category).toBe('places');
    const cv = spy.viewFor(s, citizens(s)[0]!, 0);
    expect(cv.role).toBe('citizen');
    expect(cv.word).toBe(s.word);
    expect(cv.guessOptions).toBeNull();
    const outsider = spy.viewFor(s, 'zz', 0);
    expect(outsider.role).toBeNull();
    expect(outsider.word).toBeNull();
    expect(JSON.stringify(cv)).not.toContain('"spies"');
    expect(JSON.stringify(sv)).not.toContain(s.word);
  });

  it('allows 2 spies only from 7 players', () => {
    expect(maxSpies(6)).toBe(1);
    expect(maxSpies(7)).toBe(2);
    const seven = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
    const s = spy.setup(seven, spy.validateConfig({ spies: 2 }, 'private'), [pack], new Rng('x'), 0);
    expect(s.spies.size).toBe(2);
    const four = spy.setup(players, spy.validateConfig({ spies: 2 }, 'private'), [pack], new Rng('x'), 0);
    expect(four.spies.size).toBe(1);
    // Public matches always use the standard config.
    expect(spy.validateConfig({ spies: 2 }, 'casual').spies).toBe(1);
  });

  it('runs one question turn per player, offering questions only to the asker', () => {
    const s = newGame();
    spy.tick(s, SPY_TIMING.rolesMs, all);
    expect(s.stage).toBe('ask');
    const asker = s.turns[0]!.asker;
    const other = players.find((p) => p !== asker)!;
    expect(spy.viewFor(s, asker, 0).turn!.questionOptions).toHaveLength(SPY_TIMING.questionOptions);
    expect(spy.viewFor(s, other, 0).turn!.questionOptions).toBeNull();
    expect(spy.onAction(s, other, { kind: 'ask', turn: 0, question: 0, target: asker }, 0)).toEqual({ ok: false, code: 'not_your_turn' });
    expect(spy.onAction(s, asker, { kind: 'ask', turn: 0, question: 0, target: asker }, 0)).toEqual({ ok: false, code: 'bad_target' });
    playTurns(s);
    expect(s.stage).toBe('discuss');
    expect(spy.viewFor(s, asker, 0).history).toHaveLength(players.length);
  });

  it('catching the spy gives them one guess; a wrong guess means citizens win', () => {
    const s = newGame();
    let now = playTurns(s);
    for (const p of players) spy.onAction(s, p, { kind: 'readyToVote' }, now);
    spy.tick(s, now, all);
    expect(s.stage).toBe('vote');
    const theSpy = spyOf(s);
    for (const p of players) {
      const target = p === theSpy ? citizens(s)[0]! : theSpy;
      expect(spy.onAction(s, p, { kind: 'vote', target }, now)).toEqual({ ok: true });
    }
    expect(spy.onAction(s, players[0]!, { kind: 'vote', target: players[1]! }, now)).toEqual({ ok: false, code: 'already_voted' });
    spy.tick(s, now, all);
    expect(s.stage).toBe('guess');
    const v = spy.viewFor(s, theSpy, now);
    expect(v.guessOptions).toHaveLength(SPY_TIMING.guessOptions);
    expect(spy.viewFor(s, citizens(s)[0]!, now).guessOptions).toBeNull();
    const wrong = v.guessOptions!.findIndex((w) => w !== s.word);
    spy.onAction(s, theSpy, { kind: 'guess', choice: wrong }, now);
    expect(s.final).toMatchObject({ winner: 'citizens', reason: 'caught', accused: theSpy });
    for (const c of citizens(s)) expect(s.scores.get(c)).toBe(SPY_POINTS.citizenWin + SPY_POINTS.goodVoteBonus);
    expect(s.scores.get(theSpy)).toBe(0);
    expect(spy.viewFor(s, theSpy, now).word).toBe(s.word);
  });

  it('a caught spy who names the word wins', () => {
    const s = newGame('seed-2');
    const now = playTurns(s);
    s.stage = 'vote';
    const theSpy = spyOf(s);
    for (const p of citizens(s)) spy.onAction(s, p, { kind: 'vote', target: theSpy }, now);
    spy.tick(s, s.stageEndsAt + 1e6, all); // vote time runs out without the spy voting
    expect(s.stage).toBe('guess');
    spy.onAction(s, theSpy, { kind: 'guess', choice: s.wordOptions.indexOf(s.word) }, now);
    expect(s.final).toMatchObject({ winner: 'spies', reason: 'caught_but_guessed' });
    expect(s.scores.get(theSpy)).toBe(SPY_POINTS.spyWin + SPY_POINTS.spyGuessBonus);
  });

  it('a tie or a wrongly accused citizen lets the spy win', () => {
    const s = newGame('seed-3');
    const now = playTurns(s);
    s.stage = 'vote';
    const [c1, c2] = citizens(s);
    const theSpy = spyOf(s);
    // Two votes each for two different citizens: tie.
    const votes: Record<string, string> = {};
    for (const p of s.players) votes[p] = p === c1 ? c2! : c1!;
    votes[c1!] = c2!;
    votes[c2!] = c1!;
    votes[theSpy] = c1!;
    const third = citizens(s)[2]!;
    votes[third] = c2!;
    for (const [p, t] of Object.entries(votes)) spy.onAction(s, p, { kind: 'vote', target: t }, now);
    spy.tick(s, now, all);
    expect(s.final).toMatchObject({ winner: 'spies', reason: 'spy_survived', accused: null });
    expect(s.final!.voteCounts[c1!]).toBe(2);
  });

  it('an early guess ends the game at once', () => {
    const right = newGame('seed-4');
    spy.tick(right, SPY_TIMING.rolesMs, all);
    const sp = spyOf(right);
    expect(spy.viewFor(right, sp, 0).guessOptions).not.toBeNull();
    spy.onAction(right, sp, { kind: 'guess', choice: right.wordOptions.indexOf(right.word) }, 0);
    expect(right.final).toMatchObject({ winner: 'spies', reason: 'spy_guessed_early' });

    const wrong = newGame('seed-5');
    spy.tick(wrong, SPY_TIMING.rolesMs, all);
    const sp2 = spyOf(wrong);
    expect(spy.onAction(wrong, citizens(wrong)[0]!, { kind: 'guess', choice: 0 }, 0)).toEqual({ ok: false, code: 'not_allowed' });
    spy.onAction(wrong, sp2, { kind: 'guess', choice: wrong.wordOptions.findIndex((w) => w !== wrong.word) }, 0);
    expect(wrong.final).toMatchObject({ winner: 'citizens', reason: 'spy_guessed_wrong' });
  });

  it('keeps going when players time out or drop', () => {
    const s = newGame('seed-6');
    spy.tick(s, SPY_TIMING.rolesMs, all);
    // Nobody acts: every turn times out into an automatic question and no answer.
    let guard = 0;
    while (s.stage !== 'discuss' && guard++ < 50) spy.tick(s, s.stageEndsAt, all);
    expect(s.stage).toBe('discuss');
    expect(s.turns.every((t) => t.question !== null && t.closed)).toBe(true);
    // Disconnected players do not block the vote.
    spy.tick(s, s.stageEndsAt, all);
    expect(s.stage).toBe('vote');
    const here = new Set(players.slice(0, 2));
    for (const p of here) spy.onAction(s, p, { kind: 'vote', target: players.find((x) => x !== p)! }, 0);
    spy.tick(s, 0, here);
    expect(['guess', 'finished']).toContain(s.stage);
    expect(spy.results(s).ranking).toHaveLength(players.length);
  });

  it('refuses to start without a valid pack', () => {
    expect(() => spy.setup(players, spy.defaultConfig('casual'), [{ ...pack, payload: { words: ['x'] } }], new Rng('a'), 0)).toThrow(
      'not_enough_content',
    );
  });
});
