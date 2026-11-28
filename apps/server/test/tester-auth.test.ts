/** Closed-test sign-in: invite code + a device key, with brute-force limits. */
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { config } from '../src/config';
import { prisma } from '../src/db';
import { startServer } from '../src/server';
import { Api, resetDb } from './helpers';

let server: Awaited<ReturnType<typeof startServer>>;
let api: Api;
const key = (c: string) => c.repeat(40);

beforeAll(async () => {
  server = await startServer(0);
  api = new Api(`http://localhost:${server.port}`);
});
afterAll(async () => {
  config.closedTestCode = '';
  await server.close();
  await prisma.$disconnect();
});
beforeEach(async () => {
  await resetDb();
  config.closedTestCode = 'SAHRA-FRIENDS';
});

describe('tester sign-in', () => {
  it('is hidden when no invite code is configured', async () => {
    config.closedTestCode = '';
    expect((await api.call('POST', '/auth/tester', { code: 'x', deviceKey: key('a') })).status).toBe(404);
  });

  it('signs in with the right code and keeps the same account per device', async () => {
    const first = await api.call('POST', '/auth/tester', { code: ' sahra-friends ', deviceKey: key('a') });
    expect(first.status).toBe(200);
    expect(first.body.accessToken).toBeTruthy();
    const again = await api.call('POST', '/auth/tester', { code: 'SAHRA-FRIENDS', deviceKey: key('a') });
    expect(again.body.user.id).toBe(first.body.user.id);
    const other = await api.call('POST', '/auth/tester', { code: 'SAHRA-FRIENDS', deviceKey: key('b') });
    expect(other.body.user.id).not.toBe(first.body.user.id);
    // The raw device key is never stored.
    const ids = await prisma.authIdentity.findMany({ where: { provider: 'tester' } });
    expect(ids.every((i) => !i.subject.includes('aaaa'))).toBe(true);
  });

  it('rejects a wrong code, short keys, and too many attempts', async () => {
    expect((await api.call('POST', '/auth/tester', { code: 'SAHRA-FRIENDS', deviceKey: 'short' })).status).toBe(400);
    for (let i = 0; i < 10; i++) {
      const r = await api.call('POST', '/auth/tester', { code: 'WRONG-CODE', deviceKey: key('c') });
      expect(r.status).toBe(403);
      expect(r.body.error ?? r.body.code).toBeTruthy();
    }
    expect((await api.call('POST', '/auth/tester', { code: 'SAHRA-FRIENDS', deviceKey: key('c') })).status).toBe(429);
  });
});
