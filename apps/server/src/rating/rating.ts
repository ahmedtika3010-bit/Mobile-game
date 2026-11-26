/**
 * Per-game skill ratings using OpenSkill (Weng-Lin), which supports more than
 * two players. Rating changes are keyed by (match, user) so a match can never
 * be rated twice.
 */
import { ordinal, rate, rating } from 'openskill';
import type { Tx } from '../db';

export interface RatedPlayer {
  userId: string;
  place: number;
}

export async function applyRatings(tx: Tx, matchId: string, gameId: string, players: RatedPlayer[]) {
  if (players.length < 2) return [];
  const already = await tx.ratingChange.count({ where: { matchId } });
  if (already > 0) return [];
  const current = await Promise.all(
    players.map(async (p) => {
      const r = await tx.skillRating.findUnique({ where: { userId_gameId: { userId: p.userId, gameId } } });
      return r ?? { userId: p.userId, gameId, ...rating(), matches: 0 };
    }),
  );
  const updated = rate(
    current.map((r) => [{ mu: r.mu, sigma: r.sigma }]),
    { rank: players.map((p) => p.place) },
  );
  const changes = [];
  for (let i = 0; i < players.length; i++) {
    const before = current[i]!;
    const after = updated[i]![0]!;
    await tx.skillRating.upsert({
      where: { userId_gameId: { userId: before.userId, gameId } },
      create: { userId: before.userId, gameId, mu: after.mu, sigma: after.sigma, matches: 1 },
      update: { mu: after.mu, sigma: after.sigma, matches: { increment: 1 } },
    });
    await tx.ratingChange.create({
      data: {
        matchId, userId: before.userId, gameId,
        muBefore: before.mu, muAfter: after.mu, sigmaBefore: before.sigma, sigmaAfter: after.sigma,
      },
    });
    changes.push({
      userId: before.userId,
      before: displayRating(before),
      after: displayRating(after),
    });
  }
  return changes;
}

/** Conservative display rating (mu - 3 sigma), scaled for readability. */
export function displayRating(r: { mu: number; sigma: number }): number {
  return Math.max(0, Math.round(ordinal(r) * 40 + 1000));
}
