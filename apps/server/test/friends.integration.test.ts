/** Friends: codes, requests, age and block rules, presence, and room invitations. */
import { Client } from 'colyseus.js';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma } from '../src/db';
import { startServer } from '../src/server';
import { Api, resetDb, waitFor } from './helpers';

let server: Awaited<ReturnType<typeof startServer>>;
let api: Api;
let wsUrl: string;

beforeAll(async () => {
  server = await startServer(0);
  api = new Api(`http://localhost:${server.port}`);
  wsUrl = `ws://localhost:${server.port}`;
});
afterAll(async () => {
  await server.close();
  await prisma.$disconnect();
});
beforeEach(async () => {
  await resetDb();
});

type P = { token: string; id: string };
const list = async (p: P) => (await api.call('GET', '/friends', undefined, p.token)).body;
const ask = (p: P, body: object) => api.call('POST', '/friends/requests', body, p.token);
async function befriend(a: P, b: P) {
  const code = (await list(b)).code;
  expect((await ask(a, { code })).body.status).toBe('requested');
  expect((await api.call('POST', `/friends/requests/${a.id}/accept`, {}, b.token)).body.status).toBe('friends');
}

describe('friends', () => {
  it('adds a friend by code: request, accept, list, unfriend', async () => {
    const [a, b] = await Promise.all([api.player('fa'), api.player('fb')]);
    const la = await list(a);
    expect(la.code).toMatch(/^[A-Z0-9]{8}$/);
    expect((await list(a)).code).toBe(la.code); // stable
    const code = (await list(b)).code;
    expect((await ask(a, { code: code.toLowerCase() })).status).toBe(201);
    expect((await ask(a, { code })).body.status).toBe('requested'); // no duplicate
    expect((await list(b)).incoming.map((x: { id: string }) => x.id)).toEqual([a.id]);
    expect((await list(a)).outgoing.map((x: { id: string }) => x.id)).toEqual([b.id]);
    // The incoming count arrives with the presence ping.
    expect((await api.call('POST', '/friends/ping', {}, b.token)).body.incoming).toBe(1);
    await api.call('POST', `/friends/requests/${a.id}/accept`, {}, b.token);
    const after = await list(a);
    expect(after.friends.map((f: { id: string }) => f.id)).toEqual([b.id]);
    expect(after.outgoing).toEqual([]);
    expect((await api.call('DELETE', `/friends/${b.id}`, undefined, a.token)).status).toBe(204);
    expect((await list(b)).friends).toEqual([]);
  });

  it('accepts automatically when both asked each other, and declines silently', async () => {
    const [a, b, c] = await Promise.all([api.player('fa'), api.player('fb'), api.player('fc')]);
    await ask(a, { code: (await list(b)).code });
    expect((await ask(b, { code: (await list(a)).code })).body.status).toBe('friends');
    await ask(c, { code: (await list(a)).code });
    expect((await api.call('POST', `/friends/requests/${c.id}/decline`, {}, a.token)).status).toBe(204);
    expect((await list(c)).outgoing).toEqual([]);
    expect((await api.call('POST', `/friends/requests/${c.id}/accept`, {}, a.token)).status).toBe(404);
  });

  it('never links adults and minors, and gives the same answer as for any refusal', async () => {
    const [adult, teen, teen2] = await Promise.all([
      api.player('ad'),
      api.player('tn', '2011-03-03'),
      api.player('tn2', '2010-06-06'),
    ]);
    const teenCode = (await list(teen)).code;
    const r1 = await ask(adult, { code: teenCode });
    expect(r1.status).toBe(403);
    expect(r1.body.error).toBe('cannot_add');
    expect((await ask(teen, { code: (await list(adult)).code })).body.error).toBe('cannot_add');
    // Teens can be friends with teens.
    await befriend(teen, teen2);
    expect((await ask(adult, { code: 'ZZZZZZZZ' })).status).toBe(404);
  });

  it('respects blocks and the privacy setting, and a block ends the friendship', async () => {
    const [a, b, c] = await Promise.all([api.player('fa'), api.player('fb'), api.player('fc')]);
    await befriend(a, b);
    await api.call('POST', '/safety/blocks', { userId: a.id }, b.token);
    expect((await list(a)).friends).toEqual([]);
    expect((await ask(a, { code: (await list(b)).code })).body.error).toBe('cannot_add');
    await api.call('PATCH', '/friends/settings', { allowFriendRequests: false }, c.token);
    expect((await ask(a, { code: (await list(c)).code })).body.error).toBe('cannot_add');
    expect((await list(c)).settings).toEqual({ allowFriendRequests: false, showPresence: true });
  });

  it('adds by player id only after a real match together', async () => {
    const [a, b] = await Promise.all([api.player('fa'), api.player('fb')]);
    expect((await ask(a, { userId: b.id })).body.error).toBe('cannot_add');
    await prisma.match.create({
      data: { roomId: 'r', gameId: 'quiz', mode: 'casual', commMode: 'normal', config: {}, seed: 's', players: { create: [{ userId: a.id }, { userId: b.id }] } },
    });
    expect((await ask(a, { userId: b.id })).status).toBe(201);
  });

  it('shows presence to friends only when allowed, including the game being played', async () => {
    const [a, b] = await Promise.all([api.player('fa'), api.player('fb')]);
    await befriend(a, b);
    const statusOfB = async () => (await list(a)).friends[0].status;
    expect(await statusOfB()).toBe('offline');
    await api.call('POST', '/friends/ping', {}, b.token);
    expect(await statusOfB()).toBe('online');
    const t = (await api.call('POST', '/matchmaking/ticket', { gameId: 'quiz', mode: 'private' }, b.token)).body;
    const room = await new Client(wsUrl).create('game', { ...t.options, ticket: t.ticket });
    ['view', 'error', 'quickChat', 'pong'].forEach((m) => room.onMessage(m, () => {}));
    await new Promise((r) => setTimeout(r, 200));
    const f = (await list(a)).friends[0];
    expect(f).toMatchObject({ status: 'in_game', gameId: 'quiz' });
    await room.leave();
    await new Promise((r) => setTimeout(r, 300));
    expect(await statusOfB()).toBe('online');
    await api.call('PATCH', '/friends/settings', { showPresence: false }, b.token);
    expect(await statusOfB()).toBe('offline');
  });

  it('invites a friend to a private room by its code', async () => {
    const [a, b, c] = await Promise.all([api.player('fa'), api.player('fb'), api.player('fc')]);
    await befriend(a, b);
    const t = (await api.call('POST', '/matchmaking/ticket', { gameId: 'quiz', mode: 'private' }, a.token)).body;
    const room = await new Client(wsUrl).create('game', { ...t.options, ticket: t.ticket });
    let code: string | undefined;
    room.onMessage('view', (v: { code?: string }) => (code = v.code ?? code));
    ['error', 'quickChat', 'pong'].forEach((m) => room.onMessage(m, () => {}));
    await waitFor(() => code, 5_000, 'code');
    expect((await api.call('POST', `/friends/${c.id}/invite`, { roomCode: code, gameId: 'quiz' }, a.token)).body.error).toBe('not_friends');
    expect((await api.call('POST', `/friends/${b.id}/invite`, { roomCode: 'AAAAAA' }, a.token)).body.error).toBe('room_not_found');
    expect((await api.call('POST', `/friends/${b.id}/invite`, { roomCode: code, gameId: 'quiz' }, a.token)).status).toBe(201);
    const ping = (await api.call('POST', '/friends/ping', {}, b.token)).body;
    expect(ping.invites).toHaveLength(1);
    expect(ping.invites[0]).toMatchObject({ roomCode: code, gameId: 'quiz', from: { id: a.id } });
    await api.call('DELETE', `/friends/invites/${ping.invites[0].id}`, undefined, b.token);
    expect((await api.call('POST', '/friends/ping', {}, b.token)).body.invites).toEqual([]);
    // Invitations to a room that closed disappear.
    await api.call('POST', `/friends/${b.id}/invite`, { roomCode: code, gameId: 'quiz' }, a.token);
    await room.leave();
    await new Promise((r) => setTimeout(r, 300));
    expect((await api.call('POST', '/friends/ping', {}, b.token)).body.invites).toEqual([]);
  });
});
