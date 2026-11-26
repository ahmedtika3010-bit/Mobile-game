import { prisma } from '../src/db';

export async function resetDb() {
  await prisma.$executeRawUnsafe(`TRUNCATE "AuditLog","LedgerEntry","RatingChange","SkillRating","Progression","MatchEvent","MatchPlayer","Match","Report","Block","Sanction","AdminRole","ContentReview","ContentItem","ImportBatch","RefreshToken","AuthIdentity","User" CASCADE`);
}

export async function seedApprovedQuiz(n = 12) {
  await prisma.contentItem.createMany({
    data: Array.from({ length: n }, (_, i) => ({
      gameId: 'quiz',
      category: 'general',
      difficulty: 'medium',
      status: 'approved' as const,
      payload: { prompt: `سؤال تجريبي ${i}`, choices: ['صح', 'غلط 1', 'غلط 2', 'غلط 3'], correct: 0, explanation: null },
    })),
  });
}

export class Api {
  constructor(public base: string) {}
  async call(method: string, path: string, body?: unknown, token?: string, contentType = 'application/json') {
    const res = await fetch(this.base + path, {
      method,
      headers: { 'content-type': contentType, ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: body === undefined ? undefined : typeof body === 'string' ? body : JSON.stringify(body),
    });
    const text = await res.text();
    return { status: res.status, body: text ? JSON.parse(text) : null };
  }
  async player(subject: string, dob = '1995-05-05', name = subject) {
    const login = await this.call('POST', '/auth/dev', { subject });
    const token = login.body.accessToken as string;
    const prof = await this.call('POST', '/me/profile', { displayName: name, dateOfBirth: dob }, token);
    return { token, id: login.body.user.id as string, profile: prof };
  }
}

export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export async function waitFor<T>(fn: () => T | undefined | null | false, timeoutMs = 15_000, label = 'condition'): Promise<T> {
  const start = Date.now();
  for (;;) {
    const v = fn();
    if (v) return v;
    if (Date.now() - start > timeoutMs) throw new Error(`timeout waiting for ${label}`);
    await sleep(20);
  }
}
