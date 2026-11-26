import { createHash, randomBytes } from 'node:crypto';
import { SignJWT, jwtVerify } from 'jose';
import { config } from '../config';
import { prisma } from '../db';

const key = () => new TextEncoder().encode(config.jwtSecret);
const ISSUER = 'sahra';

export interface AccessClaims {
  sub: string;
  typ: 'access';
}

export async function signAccessToken(userId: string): Promise<string> {
  return new SignJWT({ typ: 'access' })
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(userId)
    .setIssuer(ISSUER)
    .setIssuedAt()
    .setExpirationTime(`${config.accessTokenTtlSec}s`)
    .sign(key());
}

export async function verifyAccessToken(token: string): Promise<string> {
  const { payload } = await jwtVerify(token, key(), { issuer: ISSUER });
  if (payload.typ !== 'access' || !payload.sub) throw new Error('bad_token');
  return payload.sub;
}

/** Short-lived ticket minted by the server that lets a client claim a room seat. */
export interface SeatTicket {
  userId: string;
  gameId: string;
  mode: string;
  ageBucket: 'adult' | 'minor';
}

export async function signSeatTicket(t: SeatTicket): Promise<string> {
  return new SignJWT({ typ: 'seat', ...t })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuer(ISSUER)
    .setIssuedAt()
    .setExpirationTime('120s')
    .sign(key());
}

export async function verifySeatTicket(token: string): Promise<SeatTicket> {
  const { payload } = await jwtVerify(token, key(), { issuer: ISSUER });
  if (payload.typ !== 'seat') throw new Error('bad_ticket');
  return payload as unknown as SeatTicket;
}

const hash = (t: string) => createHash('sha256').update(t).digest('hex');

export async function issueRefreshToken(userId: string): Promise<string> {
  const token = randomBytes(32).toString('base64url');
  await prisma.refreshToken.create({
    data: {
      userId,
      tokenHash: hash(token),
      expiresAt: new Date(Date.now() + config.refreshTokenTtlDays * 86_400_000),
    },
  });
  return token;
}

/** Rotates a refresh token: the old one is revoked, a new pair is issued. */
export async function rotateRefreshToken(token: string): Promise<{ userId: string; refreshToken: string } | null> {
  const row = await prisma.refreshToken.findUnique({ where: { tokenHash: hash(token) } });
  if (!row || row.revokedAt || row.expiresAt < new Date()) return null;
  const revoked = await prisma.refreshToken.updateMany({
    where: { id: row.id, revokedAt: null },
    data: { revokedAt: new Date() },
  });
  if (revoked.count !== 1) return null; // concurrent reuse
  return { userId: row.userId, refreshToken: await issueRefreshToken(row.userId) };
}
