/**
 * Wire protocol between the mobile client and the game server.
 * The server never sends secret state to a player who must not see it: each
 * client receives its own `RoomView`, built by the server per viewer.
 */
import type { NightView } from './night';
import type { CommMode } from './age';

export type GameId = 'quiz' | 'spy' | 'liar' | 'who' | 'emoji' | 'stop' | 'memory' | 'draw' | 'football' | 'acting';
/** practice = one player against labelled bots; no rewards, nothing saved. */
export type MatchMode = 'casual' | 'ranked' | 'private' | 'practice';
export type Difficulty = 'easy' | 'medium' | 'hard';
export type SessionLength = 'quick' | 'standard' | 'extended';

export type RoomPhase = 'lobby' | 'countdown' | 'playing' | 'results' | 'closed' | 'vote' | 'summary';

export interface PublicPlayer {
  playerId: string;
  displayName: string;
  avatarId: string;
  connected: boolean;
  ready: boolean;
  isHost: boolean;
  /** Joined mid-match: waits in the lobby until the next match. */
  waiting: boolean;
  /** A computer player (practice mode only); always shown as a bot. */
  isBot?: boolean;
}

export interface RoomView<GameView = unknown> {
  roomId: string;
  code: string | null;
  gameId: GameId;
  mode: MatchMode;
  phase: RoomPhase;
  commMode: CommMode;
  players: PublicPlayer[];
  you: string;
  /** Server clock (ms since epoch) when this view was built. */
  serverNow: number;
  countdownEndsAt: number | null;
  /** Estimated match duration in seconds, shown before entry. */
  expectedDurationSec: number;
  /** The saved match being played (null in practice); lets reports point at it. */
  matchId: string | null;
  game: GameView | null;
  /** Game Night rooms only (see night.ts); the current game is gameId. */
  night?: NightView | null;
}

/* ---------- Client -> server messages ---------- */
export type ClientMessage =
  | { type: 'ready'; ready: boolean }
  | { type: 'start' }
  | { type: 'action'; action: unknown }
  | { type: 'quickChat'; phraseId: string }
  | { type: 'ping'; clientTime: number }
  /** Ask the room to resend the current stream from the start (after a gap). */
  | { type: 'resync' };

/* ---------- Server -> client messages ---------- */
export type ServerMessage =
  | { type: 'view'; view: RoomView }
  | { type: 'pong'; clientTime: number; serverTime: number }
  | { type: 'quickChat'; from: string; phraseId: string }
  | { type: 'error'; code: string; message: string }
  | { type: 'matchSummary'; summary: MatchSummary }
  /** Append-only game data sent outside the view (Draw and Guess strokes). */
  | { type: 'stream'; key: string; from: number; items: unknown[] };

export interface MatchSummary {
  matchId: string;
  xp: number;
  coins: number;
  /** Set only when this match changed the player's official rating. */
  rating: { before: number; after: number; provisional: boolean; matchesPlayed: number } | null;
  /** Why a reward or rating was withheld, if it was. */
  notes: string[];
}

/** Approved Safe Mode phrases. Clients render the localized text by id. */
export const SAFE_PHRASES = ['gg', 'nice', 'wow', 'good_luck', 'thanks', 'oops', 'hurry'] as const;
export type SafePhraseId = (typeof SAFE_PHRASES)[number];
