/** Game Night bookkeeping: eligible games, the vote, standings and titles. */
import { describe, expect, it } from 'vitest';
import { eligibleGames, newNight, nightView, recordGame, standings, titles, topVoted } from '../src/rooms/night';

describe('game night', () => {
  it('offers only games that fit the player count and Safe Mode', () => {
    const two = eligibleGames(2, false);
    expect(two).toContain('quiz');
    expect(two).not.toContain('spy'); // needs 3
    expect(eligibleGames(4, false)).toContain('spy');
    expect(eligibleGames(4, false)).toContain('draw');
    expect(eligibleGames(4, true)).not.toContain('draw'); // Safe Mode not tested yet
    expect(eligibleGames(1, false)).toEqual([]);
  });

  it('counts votes; ties and empty votes return every leader', () => {
    expect(topVoted(['quiz', 'stop', 'memory'], ['stop', 'stop', 'quiz'])).toEqual(['stop']);
    expect(topVoted(['quiz', 'stop'], ['stop', 'quiz'])).toEqual(['quiz', 'stop']);
    expect(topVoted(['quiz', 'stop'], [])).toEqual(['quiz', 'stop']);
    expect(topVoted(['quiz'], ['draw' as never])).toEqual(['quiz']); // votes for non-options ignored
  });

  it('adds normalized points per game so no game dominates, and gives friendly titles', () => {
    const n = newNight(0);
    const r = (places: [string, number, number][]) => ({
      ranking: places.map(([playerId, place, score]) => ({ playerId, place, score })),
      performance: Object.fromEntries(places.map(([p, place]) => [p, place === 1 ? 1 : place === 2 ? 0.5 : 0])),
    });
    recordGame(n, 'quiz', 'm1', r([['a', 1, 900], ['b', 2, 500], ['c', 3, 10]]));
    recordGame(n, 'stop', 'm2', r([['b', 1, 30], ['a', 2, 20], ['c', 3, 0]]));
    recordGame(n, 'memory', 'm3', r([['a', 1, 5], ['c', 2, 4], ['b', 3, 1]]));
    // Who Among Us: everyone shares first place, nobody wins.
    recordGame(n, 'who', 'm4', { ranking: ['a', 'b', 'c'].map((p) => ({ playerId: p, place: 1, score: 0 })), performance: { a: 0.5, b: 0.5, c: 0.5 } });
    expect(n.played.map((p) => p.winners)).toEqual([['a'], ['b'], ['a'], []]);
    const s = standings(n);
    expect(s.map((x) => [x.playerId, x.points, x.wins, x.played])).toEqual([
      ['a', 300, 2, 4],
      ['b', 200, 1, 4],
      ['c', 100, 0, 4],
    ]);
    const t = titles(n);
    expect(t.find((x) => x.playerId === 'a')!.title).toBe('champion');
    expect(new Set(t.map((x) => x.playerId)).size).toBe(t.length); // one title each
    expect(t).toHaveLength(3);
  });

  it('shows each player only their own vote', () => {
    const n = newNight(0);
    n.vote = { endsAt: 1, options: ['quiz', 'stop'], votes: new Map([['a', 'quiz'], ['b', 'stop']]), tie: null, tieEndsAt: null };
    const va = nightView(n, 'a', ['quiz', 'stop'], 3);
    expect(va.vote!.yourVote).toBe('quiz');
    expect(nightView(n, 'c', [], 3).vote!.yourVote).toBeNull();
    expect(va.vote!.options).toEqual([{ gameId: 'quiz', votes: 1 }, { gameId: 'stop', votes: 1 }]);
    expect(va.vote!.voted).toBe(2);
  });
});
