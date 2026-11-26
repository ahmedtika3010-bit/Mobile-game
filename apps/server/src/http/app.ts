import express, { type NextFunction, type Request, type Response } from 'express';
import { join } from 'node:path';
import { computeAgeBand, matchmakingAgeBucket, type MatchMode } from '@sahra/shared';
import { z } from 'zod';
import type { AdminRoleKind } from '@prisma/client';
import type { Presence } from '@colyseus/core';
import { config } from '../config';
import { prisma } from '../db';
import { issueRefreshToken, rotateRefreshToken, signAccessToken, signSeatTicket, verifyAccessToken } from '../auth/tokens';
import { verifyAppleIdToken, verifyGoogleIdToken, type VerifiedIdentity } from '../auth/providers';
import { balances } from '../economy/ledger';
import { getGame, listGames } from '../games/registry';
import { adminRouter } from './admin';
import { safetyRouter } from './safety';
import { displayRating } from '../rating/rating';

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      userId?: string;
      adminRole?: AdminRoleKind;
    }
  }
}

export class HttpError extends Error {
  constructor(public status: number, public code: string) {
    super(code);
  }
}

export const wrap =
  (fn: (req: Request, res: Response) => Promise<unknown>) => (req: Request, res: Response, next: NextFunction) =>
    fn(req, res).catch(next);

export async function requireAuth(req: Request, _res: Response, next: NextFunction) {
  try {
    const h = req.headers.authorization ?? '';
    const token = h.startsWith('Bearer ') ? h.slice(7) : '';
    if (!token) throw new HttpError(401, 'unauthenticated');
    req.userId = await verifyAccessToken(token).catch(() => {
      throw new HttpError(401, 'invalid_token');
    });
    const user = await prisma.user.findUnique({ where: { id: req.userId }, select: { status: true } });
    if (!user || user.status === 'deleted') throw new HttpError(401, 'invalid_token');
    if (user.status === 'suspended') throw new HttpError(403, 'account_suspended');
    next();
  } catch (e) {
    next(e);
  }
}

export function requireAdmin(...roles: AdminRoleKind[]) {
  return async (req: Request, _res: Response, next: NextFunction) => {
    try {
      const role = await prisma.adminRole.findUnique({ where: { userId: req.userId! } });
      if (!role || (roles.length && role.role !== 'owner' && !roles.includes(role.role))) throw new HttpError(403, 'forbidden');
      req.adminRole = role.role;
      next();
    } catch (e) {
      next(e);
    }
  };
}

async function signIn(identity: VerifiedIdentity | { provider: 'dev'; subject: string; email: null }) {
  const existing = await prisma.authIdentity.findUnique({
    where: { provider_subject: { provider: identity.provider, subject: identity.subject } },
    include: { user: true },
  });
  const user =
    existing?.user ??
    (await prisma.user.create({
      data: { identities: { create: { provider: identity.provider, subject: identity.subject, email: identity.email } } },
    }));
  return {
    accessToken: await signAccessToken(user.id),
    refreshToken: await issueRefreshToken(user.id),
    user: publicMe(user),
  };
}

function publicMe(u: { id: string; displayName: string | null; avatarId: string; ageBand: string; onboarded: boolean; status: string }) {
  // Date of birth is never returned; only the derived eligibility band.
  return { id: u.id, displayName: u.displayName, avatarId: u.avatarId, ageBand: u.ageBand, onboarded: u.onboarded, status: u.status };
}

const profileSchema = z.object({
  displayName: z.string().trim().min(2).max(20),
  dateOfBirth: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  avatarId: z.string().regex(/^chibi_[a-z0-9_]{1,32}$/).optional(),
});

const ticketSchema = z.object({
  gameId: z.string(),
  mode: z.enum(['casual', 'ranked', 'private']),
});

export function createApp(presence: Presence) {
  const app = express();
  app.disable('x-powered-by');
  app.use(express.json({ limit: '256kb' }));
  app.use(express.text({ type: 'text/csv', limit: '5mb' }));

  app.get('/health', (_req, res) => res.json({ ok: true, app: config.appName }));

  // Browsing games does not need an account.
  app.get('/games', (_req, res) => {
    res.json({
      games: listGames().map((g) => {
        const game = getGame(g.id)!;
        const def = game.defaultConfig('casual');
        return { ...g, expectedDurationSec: game.expectedDurationSec(def) };
      }),
    });
  });

  /* ------------------------------ auth ------------------------------ */
  app.post('/auth/google', wrap(async (req, res) => {
    const idToken = z.object({ idToken: z.string().min(10) }).parse(req.body).idToken;
    const identity = await verifyGoogleIdToken(idToken).catch((e) => {
      throw new HttpError(e.message === 'google_not_configured' ? 503 : 401, e.message === 'google_not_configured' ? e.message : 'invalid_google_token');
    });
    res.json(await signIn(identity));
  }));

  app.post('/auth/apple', wrap(async (req, res) => {
    const idToken = z.object({ idToken: z.string().min(10) }).parse(req.body).idToken;
    const identity = await verifyAppleIdToken(idToken).catch((e) => {
      throw new HttpError(e.message === 'apple_not_configured' ? 503 : 401, e.message === 'apple_not_configured' ? e.message : 'invalid_apple_token');
    });
    res.json(await signIn(identity));
  }));

  // Local development and automated tests only. Disabled in production.
  app.post('/auth/dev', wrap(async (req, res) => {
    if (!config.devAuth) throw new HttpError(404, 'not_found');
    const subject = z.object({ subject: z.string().min(1).max(64) }).parse(req.body).subject;
    res.json(await signIn({ provider: 'dev', subject, email: null }));
  }));

  app.post('/auth/refresh', wrap(async (req, res) => {
    const token = z.object({ refreshToken: z.string() }).parse(req.body).refreshToken;
    const rotated = await rotateRefreshToken(token);
    if (!rotated) throw new HttpError(401, 'invalid_refresh_token');
    res.json({ accessToken: await signAccessToken(rotated.userId), refreshToken: rotated.refreshToken });
  }));

  /* ------------------------------ me ------------------------------ */
  app.get('/me', requireAuth, wrap(async (req, res) => {
    const u = await prisma.user.findUniqueOrThrow({ where: { id: req.userId! } });
    res.json({ user: publicMe(u) });
  }));

  app.post('/me/profile', requireAuth, wrap(async (req, res) => {
    const body = profileSchema.parse(req.body);
    const u = await prisma.user.findUniqueOrThrow({ where: { id: req.userId! } });
    const data: Record<string, unknown> = { displayName: body.displayName };
    if (body.avatarId) data.avatarId = body.avatarId;
    if (body.dateOfBirth) {
      // Date of birth can be set once by the player; corrections go through support.
      if (u.dateOfBirth) throw new HttpError(409, 'date_of_birth_already_set');
      const band = computeAgeBand(body.dateOfBirth, new Date());
      if (band === 'unknown') throw new HttpError(400, 'invalid_date_of_birth');
      data.dateOfBirth = new Date(`${body.dateOfBirth}T00:00:00Z`);
      data.ageBand = band;
    }
    const ageBand = (data.ageBand as string | undefined) ?? u.ageBand;
    data.onboarded = ageBand !== 'under_13' && ageBand !== 'unknown';
    const updated = await prisma.user.update({ where: { id: u.id }, data });
    if (updated.ageBand === 'under_13') throw new HttpError(403, 'below_minimum_age');
    res.json({ user: publicMe(updated) });
  }));

  app.get('/me/wallet', requireAuth, wrap(async (req, res) => {
    const b = await balances(req.userId!);
    const prog = await prisma.progression.findUnique({ where: { userId: req.userId! } });
    res.json({ coins: b.coins, gems: b.gems, xp: prog?.xp ?? 0, level: prog?.level ?? 1 });
  }));

  app.get('/me/ratings', requireAuth, wrap(async (req, res) => {
    const rows = await prisma.skillRating.findMany({ where: { userId: req.userId! } });
    res.json({
      ratings: rows.map((r) => ({
        gameId: r.gameId,
        rating: displayRating(r),
        matchesPlayed: r.matches,
        provisional: r.matches < config.rating.provisionalMatches,
      })),
    });
  }));

  /* ------------------------------ matchmaking ------------------------------ */
  app.post('/matchmaking/ticket', requireAuth, wrap(async (req, res) => {
    const { gameId, mode } = ticketSchema.parse(req.body);
    const game = getGame(gameId);
    if (!game) throw new HttpError(404, 'unknown_game');
    if (mode === 'ranked' && !game.capabilities.ranked) throw new HttpError(400, 'ranked_unavailable');
    const u = await prisma.user.findUniqueOrThrow({ where: { id: req.userId! } });
    if (!u.onboarded || u.status !== 'active' || u.ageBand === 'under_13' || u.ageBand === 'unknown') {
      throw new HttpError(403, 'account_not_eligible');
    }
    const ageBucket = matchmakingAgeBucket(u.ageBand);
    const ticket = await signSeatTicket({ userId: u.id, gameId, mode, ageBucket });
    res.json({
      ticket,
      roomName: 'game',
      // Clients pass these as join options; the room re-checks them against the ticket.
      options: { gameId, mode: mode as MatchMode, ageBucket: mode === 'private' ? 'any' : ageBucket },
    });
  }));

  app.get('/rooms/by-code/:code', requireAuth, wrap(async (req, res) => {
    const code = String(req.params.code).toUpperCase();
    if (!/^[A-Z0-9]{6}$/.test(code)) throw new HttpError(400, 'bad_code');
    const roomId = await presence.hget('room_codes', code);
    if (!roomId) throw new HttpError(404, 'room_not_found');
    res.json({ roomId });
  }));

  app.use('/safety', requireAuth, safetyRouter());
  app.use('/admin', requireAuth, adminRouter());
  app.use('/admin-ui', express.static(join(__dirname, '..', '..', 'admin-ui')));
  if (config.devAuth) {
    // Local development only: serve the Flutter web build (flutter build web --base-href /play/).
    app.use('/play', express.static(join(__dirname, '..', '..', '..', 'mobile', 'build', 'web')));
  }

  app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    if (err instanceof HttpError) return res.status(err.status).json({ error: err.code });
    if (err instanceof z.ZodError) return res.status(400).json({ error: 'invalid_request', details: err.issues });
    console.error(err);
    res.status(500).json({ error: 'internal_error' });
  });

  return app;
}
