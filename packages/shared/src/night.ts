/**
 * Game Night (سهرة اللعب): one private room where friends play several games
 * in a row without recreating the room.
 *
 * - The host may queue a playlist; when it is empty, everyone votes for the
 *   next game (20 s, or sooner when every player has voted).
 * - A tie goes to the host (temporary leader if the host left), who has a few
 *   seconds to pick; otherwise one of the tied games is drawn at random.
 * - Only games that fit the room's player count and its Safe Mode state are
 *   offered.
 * - Session points use each game's normalized performance (0..100 per game),
 *   so games with bigger raw scores or shorter rounds do not dominate.
 */
import type { GameId } from './protocol';

/** The ticket and room id used for a Game Night room. */
export const NIGHT_ID = 'night';

export const NIGHT_LIMITS = {
  voteMs: 20_000,
  tieMs: 10_000,
  /** "Next game" countdown between games. */
  nextGameMs: 5_000,
  maxPlaylist: 10,
  maxPlayers: 8,
};

export interface NightStanding {
  playerId: string;
  /** Sum of normalized performance (0..100 per game played). */
  points: number;
  wins: number;
  played: number;
}

export interface NightGamePlayed {
  gameId: GameId;
  matchId: string | null;
  winners: string[];
}

export interface NightView {
  /** Games played so far in this night, in order. */
  played: NightGamePlayed[];
  standings: NightStanding[];
  /** Games the host queued (next first). */
  playlist: GameId[];
  /** Games that fit the room right now (player count, Safe Mode). */
  eligible: GameId[];
  vote: {
    endsAt: number;
    options: { gameId: GameId; votes: number }[];
    yourVote: GameId | null;
    voted: number;
    voters: number;
    /** Set when the vote tied and the host is choosing between these. */
    tie: GameId[] | null;
    tieEndsAt: number | null;
  } | null;
  /** The game about to start (during the countdown between games). */
  next: GameId | null;
  /** Set when the host ended the night: the final summary. */
  summary: {
    standings: NightStanding[];
    played: NightGamePlayed[];
    durationSec: number;
    /** Fun titles: playerId -> title id (best_overall, most_wins, all_rounder...). */
    titles: { playerId: string; title: string }[];
  } | null;
  startedAt: number;
}
