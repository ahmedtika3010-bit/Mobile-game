/**
 * Friends: requests, the friend list, presence and room invitations.
 *
 * Safety rules (section 17 of the spec):
 * - Friend requests and invitations only between players of the same age
 *   group (adults with adults, minors with minors; unknown age counts as a
 *   minor and is not eligible at all until onboarding is complete).
 * - A block in either direction prevents requests and removes the friendship.
 * - Players are found by a shared friend code, or among people they really
 *   played a match with recently. There is no search by name.
 * - Refusals never say why (a minor's age, a block or a privacy setting all
 *   look the same to the sender).
 * - Online status is shown only to accepted friends, and players can hide it.
 */
import { randomBytes } from 'node:crypto';
import { Router } from 'express';
import { z } from 'zod';
import type { Presence } from '@colyseus/core';
import type { User } from '@prisma/client';
import { matchmakingAgeBucket } from '@sahra/shared';
import { config } from '../config';
import { prisma } from '../db';
import { getGame } from '../games/registry';
import { IN_GAME_KEY, ONLINE_KEY } from '../social/keys';
import { HttpError, wrap } from './app';

const ROOM_CODES_KEY = 'room_codes';
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I

type PublicFriend = { id: string; displayName: string | null; avatarId: string };
const pub = (u: { id: string; displayName: string | null; avatarId: string }): PublicFriend => ({
  id: u.id,
  displayName: u.displayName,
  avatarId: u.avatarId,
});

function eligible(u: User) {
  return u.status === 'active' && u.onboarded && u.ageBand !== 'unknown' && u.ageBand !== 'under_13';
}

/** True when the two players may be friends (and invite each other). */
export async function canBeFriends(a: User, b: User): Promise<boolean> {
  if (a.id === b.id || !eligible(a) || !eligible(b)) return false;
  if (matchmakingAgeBucket(a.ageBand) !== matchmakingAgeBucket(b.ageBand)) return false;
  const block = await prisma.block.findFirst({
    where: { OR: [{ blockerId: a.id, blockedId: b.id }, { blockerId: b.id, blockedId: a.id }] },
  });
  return !block;
}

async function pairRow(a: string, b: string) {
  return prisma.friendship.findFirst({
    where: { OR: [{ requesterId: a, addresseeId: b }, { requesterId: b, addresseeId: a }] },
  });
}

/** Removes any friendship, request and invitation between two players (used by blocking). */
export async function unlinkPlayers(a: string, b: string) {
  await prisma.friendship.deleteMany({
    where: { OR: [{ requesterId: a, addresseeId: b }, { requesterId: b, addresseeId: a }] },
  });
  await prisma.friendInvite.deleteMany({ where: { OR: [{ fromId: a, toId: b }, { fromId: b, toId: a }] } });
}

async function friendCodeOf(userId: string): Promise<string> {
  const u = await prisma.user.findUniqueOrThrow({ where: { id: userId }, select: { friendCode: true } });
  if (u.friendCode) return u.friendCode;
  for (let i = 0; i < 20; i++) {
    const code = Array.from(randomBytes(8), (x) => CODE_ALPHABET[x % CODE_ALPHABET.length]).join('');
    try {
      await prisma.user.update({ where: { id: userId }, data: { friendCode: code } });
      return code;
    } catch {
      // Taken (unique index): try another.
    }
  }
  throw new HttpError(500, 'code_allocation_failed');
}

async function sharedRecentMatch(a: string, b: string) {
  const since = new Date(Date.now() - config.social.playedWithDays * 86_400_000);
  const m = await prisma.match.findFirst({
    where: { startedAt: { gte: since }, AND: [{ players: { some: { userId: a } } }, { players: { some: { userId: b } } }] },
    select: { id: true },
  });
  return Boolean(m);
}

export type FriendStatus = 'online' | 'in_game' | 'offline';

export function friendsRouter(presence: Presence) {
  const r = Router();

  const statusOf = async (u: { id: string; showPresence: boolean }): Promise<{ status: FriendStatus; gameId?: string }> => {
    if (!u.showPresence) return { status: 'offline' };
    const game = await presence.hget(IN_GAME_KEY, u.id);
    if (game) {
      const g = JSON.parse(game) as { gameId: string };
      return { status: 'in_game', gameId: g.gameId };
    }
    const last = Number((await presence.hget(ONLINE_KEY, u.id)) ?? 0);
    return { status: Date.now() - last < config.social.onlineWindowMs ? 'online' : 'offline' };
  };

  const liveInvites = async (userId: string) => {
    const rows = await prisma.friendInvite.findMany({
      where: { toId: userId, expiresAt: { gt: new Date() } },
      include: { from: true },
      orderBy: { createdAt: 'desc' },
    });
    const out = [];
    for (const i of rows) {
      // Skip invitations to rooms that no longer exist.
      if (!(await presence.hget(ROOM_CODES_KEY, i.roomCode))) continue;
      out.push({ id: i.id, from: pub(i.from), roomCode: i.roomCode, gameId: i.gameId, expiresAt: i.expiresAt.getTime() });
    }
    return out;
  };

  const me = async (id: string) => prisma.user.findUniqueOrThrow({ where: { id } });

  r.get('/', wrap(async (req, res) => {
    const id = req.userId!;
    const u = await me(id);
    const rows = await prisma.friendship.findMany({
      where: { OR: [{ requesterId: id }, { addresseeId: id }] },
      include: { requester: true, addressee: true },
      orderBy: { createdAt: 'desc' },
    });
    const friends = [];
    const incoming = [];
    const outgoing = [];
    for (const row of rows) {
      const other = row.requesterId === id ? row.addressee : row.requester;
      if (row.status === 'accepted') friends.push({ ...pub(other), ...(await statusOf(other)), since: row.acceptedAt?.getTime() ?? 0 });
      else if (row.addresseeId === id) incoming.push({ ...pub(other), at: row.createdAt.getTime() });
      else outgoing.push({ ...pub(other), at: row.createdAt.getTime() });
    }
    const rank = { in_game: 0, online: 1, offline: 2 } as const;
    friends.sort((x, y) => rank[x.status] - rank[y.status] || (x.displayName ?? '').localeCompare(y.displayName ?? ''));
    res.json({
      code: eligible(u) ? await friendCodeOf(id) : null,
      settings: { allowFriendRequests: u.allowFriendRequests, showPresence: u.showPresence },
      friends,
      incoming,
      outgoing,
      invites: await liveInvites(id),
    });
  }));

  r.patch('/settings', wrap(async (req, res) => {
    const body = z.object({ allowFriendRequests: z.boolean().optional(), showPresence: z.boolean().optional() }).parse(req.body);
    const u = await prisma.user.update({ where: { id: req.userId! }, data: body });
    res.json({ settings: { allowFriendRequests: u.allowFriendRequests, showPresence: u.showPresence } });
  }));

  /** Send a request by friend code, or to someone you played with recently. */
  r.post('/requests', wrap(async (req, res) => {
    const body = z
      .object({ code: z.string().trim().toUpperCase().regex(/^[A-Z0-9]{8}$/).optional(), userId: z.string().uuid().optional() })
      .refine((b) => Boolean(b.code) !== Boolean(b.userId), 'code_or_user')
      .parse(req.body);
    const id = req.userId!;
    const u = await me(id);
    if (!eligible(u)) throw new HttpError(403, 'account_not_eligible');
    const other = body.code
      ? await prisma.user.findUnique({ where: { friendCode: body.code } })
      : await prisma.user.findUnique({ where: { id: body.userId! } });
    if (!other) throw new HttpError(404, 'player_not_found');
    if (other.id === id) throw new HttpError(400, 'cannot_add_self');
    if (body.userId && !(await sharedRecentMatch(id, other.id))) throw new HttpError(403, 'cannot_add');

    const existing = await pairRow(id, other.id);
    if (existing?.status === 'accepted') return res.json({ status: 'friends' });
    if (existing && existing.requesterId === id) return res.json({ status: 'requested' });
    if (!(await canBeFriends(u, other))) throw new HttpError(403, 'cannot_add');

    const friendsCount = (n: string) =>
      prisma.friendship.count({ where: { status: 'accepted', OR: [{ requesterId: n }, { addresseeId: n }] } });
    if ((await friendsCount(id)) >= config.social.maxFriends) throw new HttpError(409, 'too_many_friends');

    if (existing) {
      // They already asked: accept.
      if ((await friendsCount(other.id)) >= config.social.maxFriends) throw new HttpError(403, 'cannot_add');
      await prisma.friendship.update({
        where: { requesterId_addresseeId: { requesterId: other.id, addresseeId: id } },
        data: { status: 'accepted', acceptedAt: new Date() },
      });
      return res.json({ status: 'friends' });
    }
    if (!other.allowFriendRequests) throw new HttpError(403, 'cannot_add');
    const since = new Date(Date.now() - 86_400_000);
    const today = await prisma.friendship.count({ where: { requesterId: id, createdAt: { gte: since } } });
    if (today >= config.social.requestsPerDay) throw new HttpError(429, 'too_many_requests');
    const pending = await prisma.friendship.count({ where: { requesterId: id, status: 'pending' } });
    if (pending >= config.social.maxPendingOutgoing) throw new HttpError(429, 'too_many_requests');
    await prisma.friendship.create({ data: { requesterId: id, addresseeId: other.id } });
    res.status(201).json({ status: 'requested' });
  }));

  r.post('/requests/:userId/accept', wrap(async (req, res) => {
    const id = req.userId!;
    const from = String(req.params.userId);
    const row = await prisma.friendship.findUnique({ where: { requesterId_addresseeId: { requesterId: from, addresseeId: id } } });
    if (!row || row.status !== 'pending') throw new HttpError(404, 'request_not_found');
    const [u, other] = await Promise.all([me(id), me(from)]);
    // Re-check: ages, blocks and account state may have changed since the request.
    if (!(await canBeFriends(u, other))) {
      await prisma.friendship.delete({ where: { requesterId_addresseeId: { requesterId: from, addresseeId: id } } });
      throw new HttpError(403, 'cannot_add');
    }
    const count = await prisma.friendship.count({ where: { status: 'accepted', OR: [{ requesterId: id }, { addresseeId: id }] } });
    if (count >= config.social.maxFriends) throw new HttpError(409, 'too_many_friends');
    await prisma.friendship.update({
      where: { requesterId_addresseeId: { requesterId: from, addresseeId: id } },
      data: { status: 'accepted', acceptedAt: new Date() },
    });
    res.json({ status: 'friends' });
  }));

  // Declining is silent: the sender only sees the request disappear.
  r.post('/requests/:userId/decline', wrap(async (req, res) => {
    await prisma.friendship.deleteMany({ where: { requesterId: String(req.params.userId), addresseeId: req.userId!, status: 'pending' } });
    res.status(204).end();
  }));

  r.delete('/requests/:userId', wrap(async (req, res) => {
    await prisma.friendship.deleteMany({ where: { requesterId: req.userId!, addresseeId: String(req.params.userId), status: 'pending' } });
    res.status(204).end();
  }));

  r.delete('/:userId', wrap(async (req, res) => {
    await unlinkPlayers(req.userId!, String(req.params.userId));
    res.status(204).end();
  }));

  /** The app calls this about every 45 s while open: marks you online, returns what is new. */
  r.post('/ping', wrap(async (req, res) => {
    const id = req.userId!;
    await presence.hset(ONLINE_KEY, id, String(Date.now()));
    const incoming = await prisma.friendship.count({ where: { addresseeId: id, status: 'pending' } });
    res.json({ incoming, invites: await liveInvites(id) });
  }));

  r.post('/:userId/invite', wrap(async (req, res) => {
    const id = req.userId!;
    const to = String(req.params.userId);
    const { roomCode } = z.object({ roomCode: z.string().trim().toUpperCase().regex(/^[A-Z0-9]{6}$/) }).parse(req.body);
    const row = await pairRow(id, to);
    if (row?.status !== 'accepted') throw new HttpError(403, 'not_friends');
    const [u, other] = await Promise.all([me(id), me(to)]);
    if (!(await canBeFriends(u, other))) throw new HttpError(403, 'cannot_invite');
    const roomId = await presence.hget(ROOM_CODES_KEY, roomCode);
    if (!roomId) throw new HttpError(404, 'room_not_found');
    const recent = await prisma.friendInvite.count({ where: { fromId: id, createdAt: { gte: new Date(Date.now() - 3_600_000) } } });
    if (recent >= config.social.invitesPerHour) throw new HttpError(429, 'too_many_invites');
    const asked = z.object({ gameId: z.string().max(32).default('') }).parse(req.body).gameId;
    const gameId = getGame(asked) ? asked : '';
    const expiresAt = new Date(Date.now() + config.social.inviteTtlMs);
    await prisma.friendInvite.upsert({
      where: { fromId_toId: { fromId: id, toId: to } },
      create: { fromId: id, toId: to, roomCode, gameId, expiresAt },
      update: { roomCode, gameId, expiresAt, createdAt: new Date() },
    });
    res.status(201).json({ ok: true });
  }));

  r.delete('/invites/:id', wrap(async (req, res) => {
    await prisma.friendInvite.deleteMany({ where: { id: String(req.params.id), toId: req.userId! } });
    res.status(204).end();
  }));

  return r;
}
