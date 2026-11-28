/**
 * Game Night bookkeeping, kept apart from the room so it can be unit tested:
 * which games fit the room, the vote, and the session standings.
 */
import type { GameId, NightGamePlayed, NightStanding, NightView } from '@sahra/shared';
import type { GameModule, GameResults } from '../games/engine';
import { Rng } from '../games/engine';
import { listGames, getGame } from '../games/registry';

export interface NightState {
  startedAt: number;
  playlist: GameId[];
  played: NightGamePlayed[];
  /** playerId -> normalized performance per game played (0..100). */
  perf: Map<string, number[]>;
  wins: Map<string, number>;
  vote: {
    endsAt: number;
    options: GameId[];
    votes: Map<string, GameId>;
    tie: GameId[] | null;
    tieEndsAt: number | null;
  } | null;
  next: GameId | null;
  ended: { at: number } | null;
}

export function newNight(now: number): NightState {
  return { startedAt: now, playlist: [], played: [], perf: new Map(), wins: new Map(), vote: null, next: null, ended: null };
}

/** Games that can run with this many players, and in Safe Mode when the room is in Safe Mode. */
export function eligibleGames(players: number, safe: boolean): GameId[] {
  return listGames()
    .map((g) => getGame(g.id) as GameModule<unknown, unknown, unknown>)
    .filter((g) => players >= g.capabilities.minPlayers && players <= g.capabilities.maxPlayers)
    .filter((g) => !safe || g.capabilities.safeModeReady)
    .map((g) => g.id as GameId);
}

/** The games with the most votes (all options when nobody voted). */
export function topVoted(options: GameId[], votes: Iterable<GameId>): GameId[] {
  const count = new Map<GameId, number>();
  for (const v of votes) if (options.includes(v)) count.set(v, (count.get(v) ?? 0) + 1);
  if (count.size === 0) return options.slice();
  const max = Math.max(...count.values());
  return options.filter((o) => count.get(o) === max);
}

export function pickRandom<T>(items: T[], seed: string): T {
  return items[Math.floor(new Rng(seed).next() * items.length)]!;
}

/** Adds a finished game to the night (normalized 0..100 per player). */
export function recordGame(n: NightState, gameId: GameId, matchId: string | null, results: GameResults) {
  const winners = results.ranking.filter((r) => r.place === 1).map((r) => r.playerId);
  // A game with no winner (everyone shares first place) awards no win.
  const realWinners = winners.length === results.ranking.length && results.ranking.length > 1 ? [] : winners;
  for (const r of results.ranking) {
    const p = Math.round(100 * Math.max(0, Math.min(1, results.performance[r.playerId] ?? 0)));
    n.perf.set(r.playerId, [...(n.perf.get(r.playerId) ?? []), p]);
  }
  for (const w of realWinners) n.wins.set(w, (n.wins.get(w) ?? 0) + 1);
  n.played.push({ gameId, matchId, winners: realWinners });
}

export function standings(n: NightState): NightStanding[] {
  return [...n.perf.entries()]
    .map(([playerId, ps]) => ({
      playerId,
      points: ps.reduce((a, b) => a + b, 0),
      wins: n.wins.get(playerId) ?? 0,
      played: ps.length,
    }))
    .sort((a, b) => b.points - a.points || b.wins - a.wins || a.playerId.localeCompare(b.playerId));
}

/** Friendly titles for the summary: each player gets at most one. */
export function titles(n: NightState): { playerId: string; title: string }[] {
  const s = standings(n);
  if (s.length === 0 || n.played.length === 0) return [];
  const out: { playerId: string; title: string }[] = [];
  const taken = new Set<string>();
  const give = (playerId: string | undefined, title: string) => {
    if (!playerId || taken.has(playerId)) return;
    taken.add(playerId);
    out.push({ playerId, title });
  };
  give(s[0]!.points > 0 ? s[0]!.playerId : undefined, 'champion');
  const byWins = s.slice().sort((a, b) => b.wins - a.wins)[0];
  if (byWins && byWins.wins > 0) give(byWins.playerId === s[0]!.playerId ? undefined : byWins.playerId, 'most_wins');
  if (n.played.length >= 3) {
    const steady = [...n.perf.entries()]
      .filter(([, ps]) => ps.length === n.played.length)
      .sort((a, b) => Math.min(...b[1]) - Math.min(...a[1]))[0];
    give(steady?.[0], 'steady');
  }
  for (const x of s) give(x.playerId, 'good_sport');
  return out;
}

export function nightView(n: NightState, viewer: string, eligible: GameId[], voters: number): NightView {
  const v = n.vote;
  return {
    played: n.played,
    standings: standings(n),
    playlist: n.playlist,
    eligible,
    vote: v
      ? {
          endsAt: v.endsAt,
          options: v.options.map((gameId) => ({ gameId, votes: [...v.votes.values()].filter((x) => x === gameId).length })),
          yourVote: v.votes.get(viewer) ?? null,
          voted: v.votes.size,
          voters,
          tie: v.tie,
          tieEndsAt: v.tieEndsAt,
        }
      : null,
    next: n.next,
    summary: n.ended
      ? {
          standings: standings(n),
          played: n.played,
          durationSec: Math.round((n.ended.at - n.startedAt) / 1000),
          titles: titles(n),
        }
      : null,
    startedAt: n.startedAt,
  };
}
