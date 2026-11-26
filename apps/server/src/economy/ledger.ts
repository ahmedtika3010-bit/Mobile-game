/**
 * Double-grant-proof economy ledger. Balances are sums of entries; every grant
 * carries an idempotency key that is unique in the database, so a retried
 * request, a reconnect or a duplicated finalize cannot pay twice.
 */
import { Prisma, type Currency } from '@prisma/client';
import { prisma, type Tx } from '../db';

export interface Grant {
  userId: string;
  currency: Currency;
  amount: number;
  reason: string;
  idempotencyKey: string;
  refId?: string;
}

/** Returns true if granted now, false if this key was already granted. */
export async function grant(tx: Tx, g: Grant): Promise<boolean> {
  if (!Number.isInteger(g.amount) || g.amount === 0) return false;
  const res = await tx.ledgerEntry.createMany({ data: [g], skipDuplicates: true });
  if (res.count === 1 && g.currency === 'xp') {
    const prog = await tx.progression.upsert({
      where: { userId: g.userId },
      create: { userId: g.userId, xp: g.amount, level: levelForXp(g.amount) },
      update: { xp: { increment: g.amount } },
    });
    const level = levelForXp(prog.xp);
    if (level !== prog.level) await tx.progression.update({ where: { userId: g.userId }, data: { level } });
  }
  return res.count === 1;
}

export async function balances(userId: string): Promise<Record<Currency, number>> {
  const rows = await prisma.ledgerEntry.groupBy({ by: ['currency'], where: { userId }, _sum: { amount: true } });
  const out: Record<Currency, number> = { coins: 0, gems: 0, xp: 0 };
  for (const r of rows) out[r.currency] = r._sum.amount ?? 0;
  return out;
}

export async function coinsEarnedFromMatchesToday(tx: Tx, userId: string, now = new Date()): Promise<number> {
  const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  const r = await tx.ledgerEntry.aggregate({
    where: { userId, currency: 'coins', reason: 'match_reward', createdAt: { gte: start } },
    _sum: { amount: true },
  });
  return r._sum.amount ?? 0;
}

/** Level curve: level n needs 100 * n * (n - 1) / 2 XP (placeholder; needs playtesting). */
export function levelForXp(xp: number): number {
  let level = 1;
  while (100 * ((level + 1) * level) / 2 <= xp) level++;
  return level;
}

export const isUniqueViolation = (e: unknown) =>
  e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002';
