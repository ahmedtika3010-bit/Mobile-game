/**
 * Persists a finished match: player results, rewards and (for eligible ranked
 * matches) rating changes, all in one transaction. Every grant is keyed by
 * match and player, so running this twice cannot pay twice.
 */
import type { MatchMode, MatchSummary } from '@sahra/shared';
import { config } from '../config';
import { prisma } from '../db';
import { coinsEarnedFromMatchesToday, grant } from '../economy/ledger';
import type { GameResults } from '../games/engine';
import { getGame } from '../games/registry';
import { applyRatings } from '../rating/rating';

export interface ActionLogEntry {
  userId: string | null;
  kind: string;
  data: Record<string, unknown>;
  at: Date;
}

export interface FinalizeInput {
  matchId: string;
  gameId: string;
  mode: MatchMode;
  results: GameResults;
  players: string[];
  leftEarly: string[];
  log: ActionLogEntry[];
}

export async function finalizeMatch(input: FinalizeInput): Promise<Map<string, MatchSummary>> {
  const { matchId, gameId, mode, results, players } = input;
  const participationOnly = getGame(gameId)?.capabilities.rewards === 'participation';
  const left = new Set(input.leftEarly);
  const n = players.length;

  // Confirmed departures from a ranked match count as a loss (last place).
  const ranking = results.ranking.map((r) => (mode === 'ranked' && left.has(r.playerId) ? { ...r, place: n } : r));
  const stayed = players.filter((p) => !left.has(p));
  // A ranked match keeps competitive integrity only if at least two players finished it.
  const integrityOk = stayed.length >= 2;
  const rated = mode === 'ranked' && integrityOk;

  const summaries = new Map<string, MatchSummary>();

  await prisma.$transaction(async (tx) => {
    const match = await tx.match.findUniqueOrThrow({ where: { id: matchId } });
    if (match.state === 'completed') return; // already finalized

    await tx.match.update({ where: { id: matchId }, data: { state: 'completed', endedAt: new Date(), integrityOk } });
    for (const r of ranking) {
      await tx.matchPlayer.update({
        where: { matchId_userId: { matchId, userId: r.playerId } },
        data: { score: r.score, place: r.place, performance: results.performance[r.playerId] ?? 0, leftEarly: left.has(r.playerId) },
      });
    }
    // Appealed words go to human review; they never change this match's scores.
    const seen = new Set<string>();
    for (const sug of results.suggestions ?? []) {
      const key = `${sug.category}:${sug.word}`;
      if (seen.has(key)) continue;
      seen.add(key);
      await tx.contentItem.create({
        data: {
          gameId: sug.gameId,
          category: sug.category,
          difficulty: 'medium',
          payload: { words: [sug.word], appeal: { matchId, userId: sug.userId } },
          source: 'human',
          status: 'in_review',
        },
      });
    }
    if (input.log.length) {
      await tx.matchEvent.createMany({
        data: input.log.map((e) => ({ matchId, userId: e.userId, kind: e.kind, data: e.data as object, at: e.at })),
      });
    }

    for (const r of ranking) {
      const notes: string[] = [];
      let xp = 0;
      let coins = 0;
      if (left.has(r.playerId)) {
        notes.push('left_early_no_rewards');
      } else {
        if (participationOnly) {
          // No winners: small, flat rewards for taking part (`correct` = questions answered).
          xp = Math.min(40, 20 + 2 * (r.correct ?? 0));
          coins = 10;
        } else {
          xp = Math.min(100, 20 + 5 * (r.correct ?? 0));
          coins = 10 + (r.place === 1 ? 10 : 0);
        }
        if (mode === 'private') {
          // Limit reward extraction from private rooms.
          if (stayed.length < config.economy.privateRoomMinPlayersForCoins) {
            coins = 0;
            notes.push('private_room_too_small_for_coins');
          } else coins = Math.floor(coins / 2);
        }
        const today = await coinsEarnedFromMatchesToday(tx, r.playerId);
        const room = Math.max(0, config.economy.dailyMatchCoinCap - today);
        if (coins > room) {
          coins = room;
          notes.push('daily_coin_cap_reached');
        }
        await grant(tx, { userId: r.playerId, currency: 'xp', amount: xp, reason: 'match_reward', idempotencyKey: `match:${matchId}:${r.playerId}:xp`, refId: matchId });
        await grant(tx, { userId: r.playerId, currency: 'coins', amount: coins, reason: 'match_reward', idempotencyKey: `match:${matchId}:${r.playerId}:coins`, refId: matchId });
      }
      summaries.set(r.playerId, { matchId, xp, coins, rating: null, notes });
    }

    if (rated) {
      const changes = await applyRatings(tx, matchId, gameId, ranking.map((r) => ({ userId: r.playerId, place: r.place })));
      for (const c of changes) {
        const sr = await tx.skillRating.findUnique({ where: { userId_gameId: { userId: c.userId, gameId } } });
        const s = summaries.get(c.userId);
        if (s && sr) {
          s.rating = {
            before: c.before,
            after: c.after,
            provisional: sr.matches <= config.rating.provisionalMatches,
            matchesPlayed: sr.matches,
          };
        }
      }
    } else if (mode === 'ranked') {
      for (const s of summaries.values()) s.notes.push('match_lost_integrity_no_rating_change');
    }
  });

  return summaries;
}
