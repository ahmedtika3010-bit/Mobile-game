/** Memory Challenges rules: same exposure for all, hidden content, partial credit, fair speed bonus. */
import { usesNewerEmoji } from '@sahra/shared';
import { describe, expect, it } from 'vitest';
import { Rng } from '../src/games/engine';
import { MEMORY_EMOJI, MEMORY_TIMING, PROFILES, correctParts, generateRound, memoryModule as mem, type MemoryState } from '../src/games/memory';

const players = ['a', 'b', 'c'];
const all = new Set(players);
const game = (config: object) => mem.setup(players, mem.validateConfig(config, 'private'), [], new Rng('m'), 0);
const toAnswer = (s: MemoryState) => mem.tick(s, s.hideAt, all);

describe('memory challenges', () => {
  it('uses only emoji that older phones can draw, all different', () => {
    expect(new Set(MEMORY_EMOJI).size).toBe(MEMORY_EMOJI.length);
    for (const e of MEMORY_EMOJI) expect(usesNewerEmoji(e), e).toBe(false);
    expect(MEMORY_EMOJI.length).toBeGreaterThan(PROFILES.hard.cells + 1);
  });

  it('mixes all three modes and generates the same rounds from the same seed', () => {
    const s = game({ rounds: 6 });
    expect(new Set(s.rounds.map((r) => r.mode))).toEqual(new Set(['cards', 'sequence', 'spot']));
    expect(JSON.stringify(game({ rounds: 6 }).rounds)).toBe(JSON.stringify(s.rounds));
    expect(mem.validateConfig({ mode: 'cards', rounds: 3 }, 'casual')).toMatchObject({ mode: 'mixed', rounds: 6 });
  });

  it('shows the board only during the shared window and accepts answers only after it', () => {
    const s = game({ mode: 'cards', rounds: 3 });
    const v = mem.viewFor(s, 'a', 0);
    expect(v.round!.showAt).toBe(MEMORY_TIMING.leadMs);
    expect(v.round!.grid).toHaveLength(9);
    expect(v.round!.targets).toBeNull();
    expect(mem.onAction(s, 'a', { kind: 'pick', round: 1, cell: 0 }, s.showAt + 10)).toEqual({ ok: false, code: 'too_early' });
    toAnswer(s);
    const v2 = mem.viewFor(s, 'a', 0);
    expect(v2.stage).toBe('answer');
    expect(v2.round!.grid).toBeNull();
    expect(v2.round!.targets).toHaveLength(3);
    expect(mem.onAction(s, 'a', { kind: 'pick', round: 1, cell: 0 }, s.hideAt + 10)).toEqual({ ok: false, code: 'too_early' });
  });

  it('gives partial credit for cards and a speed bonus only for a perfect answer', () => {
    const s = game({ mode: 'cards', rounds: 3 });
    toAnswer(s);
    const r = s.rounds[0]!;
    const t = s.answerAt + 500;
    for (const cell of r.answer) expect(mem.onAction(s, 'a', { kind: 'pick', round: 1, cell }, t)).toEqual({ ok: true });
    expect(mem.onAction(s, 'a', { kind: 'pick', round: 1, cell: 0 }, t)).toEqual({ ok: false, code: 'already_answered' });
    mem.onAction(s, 'b', { kind: 'pick', round: 1, cell: r.answer[0]! }, t);
    mem.onAction(s, 'b', { kind: 'pick', round: 1, cell: (r.answer[1]! + 1) % 9 }, t);
    mem.tick(s, s.deadline, all);
    const rev = mem.viewFor(s, 'c', 0).reveal!;
    expect(rev.correct).toEqual({ a: 3, b: 1, c: 0 });
    expect(rev.points.a).toBe(100 + MEMORY_TIMING.maxSpeedBonus);
    expect(rev.points.b).toBe(33);
    expect(rev.points.c).toBe(0);
    expect(mem.viewFor(s, 'c', 0).round!.grid).toHaveLength(9);
  });

  it('scores the correct prefix of a sequence', () => {
    const r = generateRound('sequence', 'hard', new Rng('q'));
    expect(r.sequence).toHaveLength(8);
    for (let i = 1; i < r.sequence.length; i++) expect(r.sequence[i]).not.toBe(r.sequence[i - 1]);
    const wrongAt3 = r.sequence.map((n, i) => (i === 3 ? (n + 1) % 4 : n));
    expect(correctParts(r, wrongAt3)).toBe(3);
    expect(correctParts(r, r.sequence)).toBe(8);
  });

  it('finds the changed card in spot the change, and ends early when all are done', () => {
    const s = game({ mode: 'spot', rounds: 3 });
    const r = s.rounds[0]!;
    expect(r.changedGrid.filter((e, i) => e !== r.grid[i])).toHaveLength(1);
    toAnswer(s);
    expect(mem.viewFor(s, 'a', 0).round!.changedGrid).toEqual(r.changedGrid);
    const t = s.answerAt + 100;
    for (const p of players) mem.onAction(s, p, { kind: 'pick', round: 1, cell: p === 'c' ? (r.answer[0]! + 1) % 9 : r.answer[0]! }, t);
    mem.tick(s, t, all);
    expect(s.stage).toBe('reveal');
    expect(mem.viewFor(s, 'a', 0).reveal!.correct).toEqual({ a: 1, b: 1, c: 0 });
  });

  it('plays to the end with bots and ranks by score', () => {
    const s = game({ rounds: 3 });
    const rng = new Rng('bots');
    while (s.stage !== 'finished') {
      for (const p of players) {
        for (let k = 0; k < 4; k++) {
          const plan = mem.botPlan!(s, p, rng, p === 'a' ? 1 : 0.3);
          if (!plan) break;
          if (s.stage === 'show') mem.tick(s, s.hideAt, all);
          mem.onAction(s, p, plan.action, Math.max(plan.at, s.answerAt));
        }
      }
      mem.tick(s, s.stage === 'show' ? s.hideAt : s.stage === 'answer' ? s.deadline : s.revealEndsAt, all);
    }
    const f = mem.viewFor(s, 'b', 0).final!;
    expect(f.ranking[0]).toMatchObject({ playerId: 'a', place: 1, correct: 3 });
  });
});
