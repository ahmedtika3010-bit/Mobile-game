/**
 * The one room type every game runs in. It owns membership, host handover,
 * countdowns, timers, reconnection (90 s), Safe Mode, and persistence; the
 * game module owns only its rules. Each player receives a view built for them,
 * so hidden information never reaches a client that must not see it.
 */
import { randomBytes, randomUUID } from 'node:crypto';
import { type Client, Room } from '@colyseus/core';
import type { Delayed } from '@colyseus/timer';
import {
  type AgeBand,
  type CommMode,
  type GameId,
  NIGHT_ID,
  NIGHT_LIMITS,
  type MatchMode,
  type PublicPlayer,
  type RoomPhase,
  type RoomView,
  SAFE_PHRASES,
  matchmakingAgeBucket,
  roomCommMode,
} from '@sahra/shared';
import { config } from '../config';
import { prisma } from '../db';
import { verifySeatTicket } from '../auth/tokens';
import { selectContent } from '../content/select';
import { type GameModule, PRACTICE_BOT_PREFIX, Rng } from '../games/engine';
import { getGame } from '../games/registry';
import { finalizeMatch, saveMatchLog, type ActionLogEntry } from './finalize';
import { IN_GAME_KEY } from '../social/keys';
import { type NightState, eligibleGames, newNight, nightView, pickRandom, recordGame, topVoted } from './night';

export const ROOM_NAME = 'game';
const CODE_KEY = 'room_codes';
/** Room code -> the game id its tickets use ('night' for Game Night rooms). */
export const CODE_GAME_KEY = 'room_code_games';

interface Member {
  userId: string;
  sessionId: string;
  client: Client | null;
  displayName: string;
  avatarId: string;
  ageBand: AgeBand;
  ready: boolean;
  connected: boolean;
  waiting: boolean;
  /** Practice-mode computer player: no connection, no account, never host. */
  isBot?: boolean;
  botSkill?: number;
  /** What this connection already received of the game's stream (see GameModule.streamFor). */
  stream?: { key: string; sent: number };
}

/** Practice bots: clearly named as bots, using the starter characters. */
const PRACTICE_BOTS = [
  { name: 'بوت نور', avatarId: 'chibi_p_nour', skill: 0.55 },
  { name: 'بوت كريم', avatarId: 'chibi_p_karim', skill: 0.65 },
  { name: 'بوت ريم', avatarId: 'chibi_p_reem', skill: 0.75 },
];

export interface CreateOptions {
  gameId: string;
  mode: MatchMode;
  ageBucket: 'adult' | 'minor' | 'any';
  config?: unknown;
}

interface AuthData {
  userId: string;
  displayName: string;
  avatarId: string;
  ageBand: AgeBand;
}

export const ROOM_TIMING = {
  publicCountdownMs: 10_000,
  fullRoomCountdownMs: 3_000,
  privateCountdownMs: 3_000,
  resultsHoldMs: 15_000,
};

export class GameRoom extends Room {
  // Colyseus `maxClients` caps seats; set from the game's capabilities.
  private game!: GameModule<any, any, any>;
  private gameId!: string;
  /** What tickets for this room name: the game, or 'night' for a Game Night room. */
  private ticketGameId!: string;
  private night: NightState | null = null;
  private voteTimer: Delayed | null = null;
  private mode!: MatchMode;
  private ageBucket!: CreateOptions['ageBucket'];
  private code: string | null = null;
  private gameConfig: unknown;
  private members = new Map<string, Member>();
  private hostId: string | null = null;
  private phase: RoomPhase = 'lobby';
  private commMode: CommMode = 'normal';
  private countdownEndsAt: number | null = null;
  private countdownTimer: Delayed | null = null;
  private wakeTimer: Delayed | null = null;
  private resetTimer: Delayed | null = null;
  private gameState: any = null;
  private matchId: string | null = null;
  private matchPlayers: string[] = [];
  private leftEarly = new Set<string>();
  private actionLog: ActionLogEntry[] = [];
  private finalizing: Promise<void> | null = null;
  private botTimers = new Map<string, { key: string; timer: Delayed }>();
  private botRng = new Rng(randomUUID());

  async onCreate(options: CreateOptions) {
    const isNight = options.gameId === NIGHT_ID;
    if (isNight && options.mode !== 'private') throw new Error('night_private_only');
    // A Game Night room starts on the quiz; the game changes before each match.
    const game = getGame(isNight ? 'quiz' : options.gameId);
    if (!game) throw new Error('unknown_game');
    this.game = game;
    this.gameId = game.id;
    this.ticketGameId = options.gameId;
    this.mode = options.mode;
    this.ageBucket = options.mode === 'private' ? 'any' : options.ageBucket;
    this.gameConfig = game.validateConfig(isNight ? undefined : options.config, this.mode);
    this.maxClients = isNight ? NIGHT_LIMITS.maxPlayers : game.capabilities.maxPlayers;
    if (isNight) this.night = newNight(Date.now());
    this.autoDispose = true;

    if (this.mode === 'private') {
      this.code = await this.allocateCode();
      // Private rooms are joined by code only, never by public matchmaking.
      await this.setPrivate(true);
    }
    if (this.mode === 'practice') {
      // One person against bots; nobody else can find or join this room.
      this.maxClients = 1;
      await this.setPrivate(true);
    }
    await this.setMetadata({
      gameId: this.ticketGameId,
      mode: this.mode,
      ageBucket: this.ageBucket,
      expectedDurationSec: game.expectedDurationSec(this.gameConfig),
    });

    this.onMessage('ready', (client, msg: { ready?: boolean }) => this.handleReady(client, !!msg?.ready));
    this.onMessage('start', (client) => this.handleStart(client));
    this.onMessage('action', (client, msg: { action?: unknown }) => this.handleAction(client, msg?.action));
    this.onMessage('resync', (client) => {
      const m = this.memberBySession(client.sessionId);
      if (!m) return;
      m.stream = undefined;
      this.sendStream(m);
    });
    this.onMessage('quickChat', (client, msg: { phraseId?: string }) => this.handleQuickChat(client, msg?.phraseId));
    if (this.night) {
      this.onMessage('nightVote', (client, msg: { gameId?: string }) => this.handleNightVote(client, msg?.gameId));
      this.onMessage('nightPick', (client, msg: { gameId?: string }) => this.handleNightPick(client, msg?.gameId));
      this.onMessage('nightPlaylist', (client, msg: { games?: unknown }) => this.handleNightPlaylist(client, msg?.games));
      this.onMessage('nightEnd', (client) => this.handleNightEnd(client));
      this.onMessage('nightNew', (client) => this.handleNightNew(client));
    }
    this.onMessage('ping', (client, msg: { clientTime?: number }) =>
      client.send('pong', { clientTime: Number(msg?.clientTime) || 0, serverTime: Date.now() }),
    );
  }

  private async allocateCode(): Promise<string> {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I
    for (let attempt = 0; attempt < 20; attempt++) {
      const bytes = randomBytes(6);
      const code = Array.from(bytes, (b) => alphabet[b % alphabet.length]).join('');
      const existing = await this.presence.hget(CODE_KEY, code);
      if (!existing) {
        await this.presence.hset(CODE_KEY, code, this.roomId);
        await this.presence.hset(CODE_GAME_KEY, code, this.ticketGameId);
        return code;
      }
    }
    throw new Error('code_allocation_failed');
  }

  async onAuth(_client: Client, options: { ticket?: string }): Promise<AuthData> {
    if (!options?.ticket) throw new Error('ticket_required');
    const t = await verifySeatTicket(options.ticket);
    if (t.gameId !== this.ticketGameId) throw new Error('ticket_game_mismatch');
    if (this.mode === 'private' ? t.mode !== 'private' : t.mode !== this.mode) throw new Error('ticket_mode_mismatch');
    if (this.ageBucket !== 'any' && t.ageBucket !== this.ageBucket) throw new Error('age_bucket_mismatch');

    const user = await prisma.user.findUnique({ where: { id: t.userId } });
    if (!user || user.status !== 'active' || !user.onboarded || !user.displayName) throw new Error('account_not_eligible');
    if (user.ageBand === 'under_13') throw new Error('account_not_eligible');
    // A game whose Safe Mode is not tested yet is offered to adults only (practice against bots excepted).
    // (Game Night only offers games that fit the room's Safe Mode state instead.)
    if (!this.night && !this.game.capabilities.safeModeReady && this.mode !== 'practice' && user.ageBand !== 'adult') {
      throw new Error('safe_mode_unavailable');
    }
    // Recompute from the account, never trust the ticket alone for age.
    if (this.ageBucket !== 'any' && matchmakingAgeBucket(user.ageBand) !== this.ageBucket) throw new Error('age_bucket_mismatch');

    // In public rooms, never seat players who have blocked each other.
    if (this.mode !== 'private' && this.mode !== 'practice' && this.members.size > 0) {
      const others = [...this.members.keys()];
      const conflict = await prisma.block.count({
        where: {
          OR: [
            { blockerId: user.id, blockedId: { in: others } },
            { blockedId: user.id, blockerId: { in: others } },
          ],
        },
      });
      if (conflict > 0) throw new Error('blocked_conflict');
    }
    return { userId: user.id, displayName: user.displayName, avatarId: user.avatarId, ageBand: user.ageBand };
  }

  onJoin(client: Client, _options: unknown, auth: AuthData) {
    const existing = this.members.get(auth.userId);
    if (existing?.client && existing.client.sessionId !== client.sessionId) {
      // Same account joined from a new connection: the newest wins.
      existing.client.leave(4000);
    }
    const inMatch = this.matchPlayers.includes(auth.userId) && !this.leftEarly.has(auth.userId);
    const member: Member = {
      userId: auth.userId,
      sessionId: client.sessionId,
      client,
      displayName: auth.displayName,
      avatarId: auth.avatarId,
      ageBand: auth.ageBand,
      ready: existing?.ready ?? false,
      connected: true,
      // Players joining mid-match wait in the lobby until the next match.
      waiting: (this.phase === 'playing' || this.phase === 'countdown') && !inMatch,
    };
    this.members.set(auth.userId, member);
    // Friends see "in a game" (with which game) while you are in a room.
    void this.presence.hset(IN_GAME_KEY, auth.userId, JSON.stringify({ gameId: this.gameId, mode: this.mode, roomId: this.roomId }));
    if (!this.hostId || !this.members.get(this.hostId)?.connected) this.hostId = auth.userId;
    if (this.mode === 'practice' && ![...this.members.values()].some((m) => m.isBot)) {
      this.addPracticeBots();
      this.updateCommMode();
      return this.beginCountdown(ROOM_TIMING.privateCountdownMs);
    }
    this.updateCommMode();
    this.maybeAutoCountdown();
    this.broadcastViews();
  }

  async onLeave(client: Client, consented: boolean) {
    const member = this.memberBySession(client.sessionId);
    if (!member) return;
    const inActiveMatch =
      (this.phase === 'playing' || this.phase === 'countdown') && this.matchPlayers.includes(member.userId);

    if (inActiveMatch && !consented) {
      member.connected = false;
      member.client = null;
      this.reassignHostIfNeeded();
      this.afterStateChange();
      try {
        const newClient = await this.allowReconnection(client, config.reconnectSeconds);
        member.client = newClient;
        member.sessionId = newClient.sessionId;
        member.connected = true;
        member.stream = undefined;
        this.logEvent(member.userId, 'reconnected', {});
        this.afterStateChange();
        return;
      } catch {
        this.logEvent(member.userId, 'reconnect_timeout', {});
      }
    }

    if (inActiveMatch) {
      // Confirmed departure (or reconnect window expired) during a match.
      this.leftEarly.add(member.userId);
      this.logEvent(member.userId, consented ? 'left' : 'abandoned', {});
    }
    // Remove unless the same account already came back on a newer connection.
    if (this.members.get(member.userId) === member) {
      this.members.delete(member.userId);
      void this.clearInGame(member.userId);
    }
    this.reassignHostIfNeeded();
    this.cancelCountdownIfTooFew();
    this.afterStateChange();
  }

  private addPracticeBots() {
    PRACTICE_BOTS.forEach((b, i) => {
      const userId = `${PRACTICE_BOT_PREFIX}${i + 1}`;
      this.members.set(userId, {
        userId,
        sessionId: userId,
        client: null,
        displayName: b.name,
        avatarId: b.avatarId,
        ageBand: 'adult',
        ready: true,
        connected: true,
        waiting: false,
        isBot: true,
        botSkill: b.skill,
      });
    });
  }

  /** Schedules each bot's next move once per decision (e.g. once per question). */
  private scheduleBots() {
    if (!this.game.botPlan || !this.gameState) return;
    for (const m of this.members.values()) {
      if (!m.isBot || !this.matchPlayers.includes(m.userId)) continue;
      const plan = this.game.botPlan(this.gameState, m.userId, this.botRng, m.botSkill ?? 0.6);
      if (!plan || this.botTimers.get(m.userId)?.key === plan.key) continue;
      this.botTimers.get(m.userId)?.timer.clear();
      const timer = this.clock.setTimeout(() => {
        if (this.phase !== 'playing' || !this.gameState) return;
        const now = Date.now();
        if (this.game.onAction(this.gameState, m.userId, plan.action, now).ok) this.advance(now);
      }, Math.max(0, plan.at - Date.now()));
      this.botTimers.set(m.userId, { key: plan.key, timer });
    }
  }

  private clearBotTimers() {
    for (const t of this.botTimers.values()) t.timer.clear();
    this.botTimers.clear();
  }

  /** Clears the "in a game" status, unless the player is already in another room. */
  private async clearInGame(userId: string) {
    const v = await this.presence.hget(IN_GAME_KEY, userId);
    if (v && (JSON.parse(v) as { roomId?: string }).roomId === this.roomId) await this.presence.hdel(IN_GAME_KEY, userId);
  }

  async onDispose() {
    this.clearBotTimers();
    for (const m of this.members.values()) if (!m.isBot) await this.clearInGame(m.userId);
    this.voteTimer?.clear();
    if (this.code) {
      await this.presence.hdel(CODE_KEY, this.code);
      await this.presence.hdel(CODE_GAME_KEY, this.code);
    }
    if (this.phase === 'playing' && this.matchId) {
      const matchId = this.matchId;
      await prisma.match.update({ where: { id: matchId }, data: { state: 'aborted', endedAt: new Date() } }).catch(() => {});
      // Keep the record of an abandoned match too, so reports made during it have evidence.
      await prisma.$transaction((tx) => saveMatchLog(tx, matchId, this.actionLog)).catch(() => {});
    }
  }

  /* ------------------------------ handlers ------------------------------ */

  private handleReady(client: Client, ready: boolean) {
    const m = this.memberBySession(client.sessionId);
    if (!m || this.phase !== 'lobby') return;
    m.ready = ready;
    this.broadcastViews();
  }

  private async handleStart(client: Client) {
    const m = this.memberBySession(client.sessionId);
    if (!m) return;
    if (this.mode !== 'private' && this.mode !== 'practice') {
      return this.sendError(client, 'not_allowed', 'Public matches start automatically');
    }
    if (m.userId !== this.hostId) return this.sendError(client, 'not_host', 'Only the host can start');
    if (this.night) {
      if (this.phase !== 'lobby' || this.night.ended) return;
      if (this.nightEligible().length === 0) return this.sendError(client, 'not_enough_players', 'Not enough players');
      return this.nightContinue();
    }
    // Practice "play again" skips the wait on the results screen.
    if (this.mode === 'practice' && this.phase === 'results' && this.resetTimer) {
      await this.resetToLobby();
    }
    if (this.phase !== 'lobby') return;
    if (this.eligiblePlayers().length < this.game.capabilities.minPlayers) {
      return this.sendError(client, 'not_enough_players', 'Not enough players');
    }
    this.beginCountdown(ROOM_TIMING.privateCountdownMs);
  }

  private handleAction(client: Client, action: unknown) {
    const m = this.memberBySession(client.sessionId);
    if (!m || this.phase !== 'playing' || !this.gameState) return;
    const now = Date.now();
    const res = this.game.onAction(this.gameState, m.userId, action, now);
    if (!res.ok) return this.sendError(client, res.code, 'Action rejected');
    this.logEvent(m.userId, 'action', { action, now });
    this.advance(now);
  }

  private handleQuickChat(client: Client, phraseId: unknown) {
    const m = this.memberBySession(client.sessionId);
    if (!m || typeof phraseId !== 'string') return;
    // Only pre-approved phrases are relayed (Safe Mode and, for now, Normal Mode too:
    // free text chat and voice are not implemented yet).
    if (!(SAFE_PHRASES as readonly string[]).includes(phraseId)) return;
    this.broadcast('quickChat', { from: m.userId, phraseId });
  }

  /* ------------------------------ lifecycle ------------------------------ */

  private eligiblePlayers(): Member[] {
    return [...this.members.values()].filter((m) => m.connected);
  }

  private maybeAutoCountdown() {
    if (this.mode === 'private' || this.mode === 'practice' || this.phase !== 'lobby') return;
    const n = this.eligiblePlayers().length;
    if (n < this.game.capabilities.minPlayers) return;
    const full = n >= this.maxClients;
    if (this.countdownTimer && !full) return;
    this.beginCountdown(full ? ROOM_TIMING.fullRoomCountdownMs : ROOM_TIMING.publicCountdownMs);
  }

  private cancelCountdownIfTooFew() {
    if (this.phase !== 'countdown') return;
    if (this.eligiblePlayers().length >= this.game.capabilities.minPlayers) return;
    this.countdownTimer?.clear();
    this.countdownTimer = null;
    this.countdownEndsAt = null;
    this.phase = 'lobby';
    if (this.night) this.night.next = null;
    for (const m of this.members.values()) m.waiting = false;
  }

  private beginCountdown(ms: number) {
    this.countdownTimer?.clear();
    this.phase = 'countdown';
    this.countdownEndsAt = Date.now() + ms;
    this.countdownTimer = this.clock.setTimeout(() => void this.startMatch(), ms);
    this.broadcastViews();
  }

  private async startMatch() {
    this.countdownTimer = null;
    this.countdownEndsAt = null;
    const players = this.eligiblePlayers();
    if (players.length < this.game.capabilities.minPlayers) {
      this.phase = 'lobby';
      return this.broadcastViews();
    }
    const persisted = this.mode !== 'practice';
    if (this.mode !== 'private' && persisted) await this.lock();

    const seed = randomUUID();
    const rng = new Rng(seed);
    try {
      const req = this.game.contentRequest(this.gameConfig);
      const content = req ? await selectContent(req, rng) : [];
      const now = Date.now();
      this.matchPlayers = players.map((p) => p.userId);
      this.leftEarly.clear();
      this.actionLog = [];
      this.gameState = this.game.setup(this.matchPlayers, this.gameConfig, content, rng, now);
      this.clearBotTimers();
      if (persisted) {
        const match = await prisma.match.create({
          data: {
            roomId: this.roomId,
            gameId: this.gameId,
            mode: this.mode as Exclude<MatchMode, 'practice'>,
            commMode: this.commMode,
            config: this.gameConfig as object,
            seed,
            players: { create: this.matchPlayers.map((userId) => ({ userId })) },
          },
        });
        this.matchId = match.id;
      }
      for (const p of players) p.waiting = false;
      if (this.night) this.night.next = null;
      this.phase = 'playing';
      this.advance(Date.now());
    } catch (e) {
      this.matchPlayers = [];
      this.gameState = null;
      this.phase = 'lobby';
      if (this.mode !== 'private' && persisted) await this.unlock();
      const known = ['not_enough_content', 'duel_needs_two'];
      const code = e instanceof Error && known.includes(e.message) ? e.message : 'start_failed';
      this.broadcast('error', { code, message: 'Could not start the match' });
      this.broadcastViews();
    }
  }

  /** Runs the game's clock forward and schedules the next wake-up. */
  private advance(now: number) {
    if (!this.gameState) return;
    const active = new Set(
      this.matchPlayers.filter((p) => this.members.get(p)?.connected && !this.leftEarly.has(p)),
    );
    this.game.tick(this.gameState, now, active);
    if (this.game.isFinished(this.gameState)) {
      this.wakeTimer?.clear();
      this.wakeTimer = null;
      this.phase = 'results';
      this.broadcastViews();
      void this.finish();
      return;
    }
    const at = this.game.nextWakeAt(this.gameState);
    this.wakeTimer?.clear();
    this.wakeTimer = at === null ? null : this.clock.setTimeout(() => this.advance(Date.now()), Math.max(0, at - now));
    this.broadcastViews();
    this.scheduleBots();
  }

  private async finish() {
    this.clearBotTimers();
    if (this.mode === 'practice') {
      // Practice pays nothing and saves nothing, so bots cannot be farmed.
      for (const m of this.members.values()) {
        m.client?.send('matchSummary', {
          summary: { matchId: 'practice', xp: 0, coins: 0, rating: null, notes: ['practice_no_rewards'] },
        });
      }
      this.resetTimer = this.clock.setTimeout(() => this.resetToLobby(), ROOM_TIMING.resultsHoldMs);
      return;
    }
    if (this.finalizing || !this.matchId) return;
    const matchId = this.matchId;
    const results = this.game.results(this.gameState);
    if (this.night) recordGame(this.night, this.gameId as GameId, matchId, results);
    this.broadcastViews();
    this.finalizing = finalizeMatch({
      matchId,
      gameId: this.gameId,
      mode: this.mode,
      results,
      players: this.matchPlayers,
      leftEarly: [...this.leftEarly],
      log: this.actionLog,
    })
      .then((summaries) => {
        for (const [userId, summary] of summaries) {
          this.members.get(userId)?.client?.send('matchSummary', { summary });
        }
      })
      .catch((e) => {
        console.error('finalize failed', matchId, e);
        this.broadcast('error', { code: 'finalize_failed', message: 'Results could not be saved; they will be retried' });
      })
      .finally(() => {
        this.finalizing = null;
        this.resetTimer = this.clock.setTimeout(
          () => void (this.night ? this.afterNightGame() : this.resetToLobby()),
          ROOM_TIMING.resultsHoldMs,
        );
      });
  }

  private async resetToLobby() {
    this.resetTimer?.clear();
    this.resetTimer = null;
    this.phase = 'lobby';
    this.gameState = null;
    this.matchId = null;
    this.matchPlayers = [];
    this.leftEarly.clear();
    for (const m of this.members.values()) {
      m.waiting = false;
      m.ready = false;
    }
    if (this.mode !== 'private' && this.mode !== 'practice') await this.unlock();
    this.maybeAutoCountdown();
    this.broadcastViews();
  }

  /* ------------------------------ helpers ------------------------------ */

  private afterStateChange() {
    const v = this.night?.vote;
    if (this.phase === 'vote' && v && !v.tie && v.votes.size >= this.eligiblePlayers().length) return this.closeVote();
    if (this.phase === 'playing') this.advance(Date.now());
    else this.broadcastViews();
  }

  /* ------------------------------ Game Night ------------------------------ */

  private nightEligible(): GameId[] {
    return eligibleGames(this.eligiblePlayers().filter((m) => !m.isBot).length, this.commMode === 'safe');
  }

  private isHost(client: Client) {
    const m = this.memberBySession(client.sessionId);
    return Boolean(m && m.userId === this.hostId);
  }

  /** After a game (or when the host starts): the next playlist game, or a vote. */
  private nightContinue() {
    const n = this.night!;
    const eligible = this.nightEligible();
    while (n.playlist.length && !eligible.includes(n.playlist[0]!)) n.playlist.shift();
    if (n.playlist.length) return this.nightChoose(n.playlist.shift()!);
    if (eligible.length === 0) {
      this.phase = 'lobby';
      return this.broadcastViews();
    }
    this.phase = 'vote';
    n.vote = { endsAt: Date.now() + NIGHT_LIMITS.voteMs, options: eligible, votes: new Map(), tie: null, tieEndsAt: null };
    this.voteTimer?.clear();
    this.voteTimer = this.clock.setTimeout(() => this.closeVote(), NIGHT_LIMITS.voteMs);
    this.broadcastViews();
  }

  private async afterNightGame() {
    if (this.night?.ended) return; // the host ended the night during the results
    await this.resetToLobby();
    if (this.night && !this.night.ended && this.phase === 'lobby') this.nightContinue();
  }

  private handleNightVote(client: Client, gameId: unknown) {
    const m = this.memberBySession(client.sessionId);
    const v = this.night?.vote;
    if (!m || this.phase !== 'vote' || !v || v.tie) return;
    if (typeof gameId !== 'string' || !v.options.includes(gameId as GameId)) return this.sendError(client, 'bad_vote', 'Not an option');
    v.votes.set(m.userId, gameId as GameId);
    this.afterStateChange();
  }

  private closeVote() {
    const n = this.night;
    const v = n?.vote;
    if (!n || !v) return;
    this.voteTimer?.clear();
    this.voteTimer = null;
    const top = topVoted(v.options, v.votes.values());
    if (top.length === 1) return this.nightChoose(top[0]!);
    const host = this.hostId ? this.members.get(this.hostId) : undefined;
    if (!host?.connected) return this.nightChoose(pickRandom(top, randomUUID()));
    // A tie: the host (or the temporary leader) picks, else one is drawn.
    v.tie = top;
    v.tieEndsAt = Date.now() + NIGHT_LIMITS.tieMs;
    this.voteTimer = this.clock.setTimeout(() => this.nightChoose(pickRandom(top, randomUUID())), NIGHT_LIMITS.tieMs);
    this.broadcastViews();
  }

  private handleNightPick(client: Client, gameId: unknown) {
    const v = this.night?.vote;
    if (!v?.tie || !this.isHost(client)) return;
    if (typeof gameId !== 'string' || !v.tie.includes(gameId as GameId)) return this.sendError(client, 'bad_vote', 'Not tied');
    this.nightChoose(gameId as GameId);
  }

  private nightChoose(gameId: GameId) {
    const n = this.night!;
    this.voteTimer?.clear();
    this.voteTimer = null;
    n.vote = null;
    const game = getGame(gameId)!;
    this.game = game;
    this.gameId = gameId;
    this.gameConfig = game.validateConfig(undefined, this.mode);
    n.next = gameId;
    this.beginCountdown(NIGHT_LIMITS.nextGameMs);
  }

  private handleNightPlaylist(client: Client, games: unknown) {
    const n = this.night;
    if (!n || n.ended || !this.isHost(client)) return;
    if (!Array.isArray(games) || games.length > NIGHT_LIMITS.maxPlaylist || !games.every((g) => typeof g === 'string' && getGame(g))) {
      return this.sendError(client, 'bad_playlist', 'Unknown games');
    }
    n.playlist = games as GameId[];
    this.broadcastViews();
  }

  private handleNightEnd(client: Client) {
    const n = this.night;
    if (!n || n.ended || !this.isHost(client)) return;
    if (this.phase === 'playing') return this.sendError(client, 'not_allowed', 'Finish the current game first');
    this.voteTimer?.clear();
    this.voteTimer = null;
    this.countdownTimer?.clear();
    this.countdownTimer = null;
    this.countdownEndsAt = null;
    this.resetTimer?.clear();
    this.resetTimer = null;
    n.vote = null;
    n.next = null;
    n.ended = { at: Date.now() };
    this.gameState = null;
    this.matchPlayers = [];
    this.phase = 'summary';
    this.broadcastViews();
  }

  private handleNightNew(client: Client) {
    if (!this.night?.ended || !this.isHost(client)) return;
    this.night = newNight(Date.now());
    void this.resetToLobby();
  }

  private updateCommMode() {
    const mode = roomCommMode([...this.members.values()].filter((m) => !m.isBot).map((m) => m.ageBand));
    // Safe Mode is sticky for the room's lifetime: it never switches back to
    // Normal Mode automatically when a minor leaves.
    if (this.commMode === 'normal' && mode === 'safe') this.commMode = 'safe';
    if (this.commMode === 'safe' && !this.night && !this.game.capabilities.safeModeReady) {
      // A game without a tested Safe Mode cannot run in a mixed-age room.
      this.broadcast('error', { code: 'safe_mode_unavailable', message: 'This game is not available in Safe Mode yet' });
    }
  }

  private reassignHostIfNeeded() {
    const host = this.hostId ? this.members.get(this.hostId) : undefined;
    if (host?.connected) return;
    const next = [...this.members.values()].find((m) => m.connected && !m.isBot);
    this.hostId = next?.userId ?? null;
  }

  private memberBySession(sessionId: string): Member | undefined {
    for (const m of this.members.values()) if (m.sessionId === sessionId) return m;
    return undefined;
  }

  private logEvent(userId: string | null, kind: string, data: Record<string, unknown>) {
    if (this.matchId) this.actionLog.push({ userId, kind, data, at: new Date() });
  }

  private sendError(client: Client, code: string, message: string) {
    client.send('error', { code, message });
  }

  private publicPlayers(): PublicPlayer[] {
    return [...this.members.values()].map((m) => ({
      playerId: m.userId,
      displayName: m.displayName,
      avatarId: m.avatarId,
      connected: m.connected,
      ready: m.ready,
      isHost: m.userId === this.hostId,
      waiting: m.waiting,
      ...(m.isBot ? { isBot: true } : {}),
    }));
  }

  private broadcastViews() {
    const now = Date.now();
    const players = this.publicPlayers();
    for (const m of this.members.values()) {
      if (!m.client) continue;
      const view: RoomView = {
        roomId: this.roomId,
        code: this.code,
        gameId: this.gameId as RoomView['gameId'],
        mode: this.mode,
        phase: this.phase,
        commMode: this.commMode,
        players,
        you: m.userId,
        serverNow: now,
        countdownEndsAt: this.countdownEndsAt,
        expectedDurationSec: this.game.expectedDurationSec(this.gameConfig),
        matchId: this.matchId,
        ...(this.night ? { night: nightView(this.night, m.userId, this.nightEligible(), this.eligiblePlayers().length) } : {}),
        // Waiting players and non-participants get no game view.
        game: this.gameState && this.matchPlayers.includes(m.userId) ? this.game.viewFor(this.gameState, m.userId, now) : null,
      };
      m.client.send('view', view);
      this.sendStream(m);
    }
  }

  /** Sends a player the stream items they have not received yet (a new key starts over). */
  private sendStream(m: Member) {
    if (!m.client || !this.game.streamFor || !this.gameState || !this.matchPlayers.includes(m.userId)) return;
    const s = this.game.streamFor(this.gameState, m.userId);
    if (!s) return;
    const fresh = m.stream?.key !== s.key;
    const from = fresh ? 0 : m.stream!.sent;
    if (!fresh && s.items.length <= from) return;
    m.client.send('stream', { key: s.key, from, items: s.items.slice(from) });
    m.stream = { key: s.key, sent: s.items.length };
  }
}
