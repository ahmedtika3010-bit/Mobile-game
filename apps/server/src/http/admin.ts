/**
 * Admin API. One owner account today; roles (moderator, content_editor) are
 * already enforced so more staff can be added later. Every write is audited.
 */
import { Router } from 'express';
import { parse } from 'csv-parse/sync';
import { z } from 'zod';
import { DRAW_CATEGORIES, EMOJI_CATEGORIES, STOP_CATEGORIES, LIAR_CATEGORIES, QUIZ_CATEGORIES, SPY_CATEGORIES, WHO_CATEGORIES } from '@sahra/shared';
import { emojiPayloadSchema } from '../games/emoji';
import { drawPayloadSchema } from '../games/draw';
import { stopPayloadSchema } from '../games/stop';
import { prisma } from '../db';
import { audit } from '../safety/audit';
import { HttpError, requireAdmin, wrap } from './app';

const quizPayload = z
  .object({
    prompt: z.string().trim().min(3).max(300),
    choices: z.array(z.string().trim().min(1).max(120)).min(2).max(6),
    correct: z.number().int().min(0),
    explanation: z.string().trim().max(500).nullable().optional(),
  })
  .refine((p) => p.correct < p.choices.length, { message: 'correct out of range' })
  .refine((p) => new Set(p.choices).size === p.choices.length, { message: 'duplicate choices' });

/** Spy: one reviewable pack per category (secret words + approved questions). */
const spyPayload = z
  .object({
    words: z.array(z.string().trim().min(1).max(40)).min(8).max(60),
    questions: z.array(z.string().trim().min(5).max(120)).min(6).max(60),
  })
  .refine((p) => new Set(p.words).size === p.words.length, { message: 'duplicate words' });

const spyItemSchema = z.object({
  gameId: z.literal('spy'),
  category: z.enum(SPY_CATEGORIES as [string, ...string[]]),
  difficulty: z.literal('medium').default('medium'),
  language: z.string().default('ar'),
  locale: z.string().optional(),
  payload: spyPayload,
  source: z.enum(['human', 'ai_suggested']).default('human'),
});

const liarPayload = z
  .object({
    main: z.string().trim().min(5).max(140),
    odd: z.string().trim().min(5).max(140),
    options: z.array(z.string().trim().min(1).max(40)).min(3).max(6),
  })
  .refine((p) => p.main !== p.odd, { message: 'questions must differ' })
  .refine((p) => new Set(p.options).size === p.options.length, { message: 'duplicate options' });

const liarItemSchema = z.object({
  gameId: z.literal('liar'),
  category: z.enum(LIAR_CATEGORIES as [string, ...string[]]),
  difficulty: z.enum(['easy', 'medium', 'hard']),
  language: z.string().default('ar'),
  locale: z.string().optional(),
  payload: liarPayload,
  source: z.enum(['human', 'ai_suggested']).default('human'),
});

const whoItemSchema = z.object({
  gameId: z.literal('who'),
  category: z.enum(WHO_CATEGORIES as [string, ...string[]]),
  difficulty: z.literal('medium').default('medium'),
  language: z.string().default('ar'),
  locale: z.string().optional(),
  payload: z.object({ text: z.string().trim().min(8).max(140) }),
  source: z.enum(['human', 'ai_suggested']).default('human'),
});

const emojiItemSchema = z.object({
  gameId: z.literal('emoji'),
  category: z.enum(EMOJI_CATEGORIES as [string, ...string[]]),
  difficulty: z.enum(['easy', 'medium', 'hard']),
  language: z.string().default('ar'),
  locale: z.string().optional(),
  payload: emojiPayloadSchema,
  source: z.enum(['human', 'ai_suggested']).default('human'),
});

/** Stop: dictionary words for one category (a full list, or one appealed word). */
const stopItemSchema = z.object({
  gameId: z.literal('stop'),
  category: z.enum(STOP_CATEGORIES as [string, ...string[]]),
  difficulty: z.literal('medium').default('medium'),
  language: z.string().default('ar'),
  locale: z.string().optional(),
  payload: stopPayloadSchema,
  source: z.enum(['human', 'ai_suggested']).default('human'),
});

/** Draw and Guess: one word with its approved variants (and an optional bot sketch). */
const drawItemSchema = z.object({
  gameId: z.literal('draw'),
  category: z.enum(DRAW_CATEGORIES as [string, ...string[]]),
  difficulty: z.enum(['easy', 'medium', 'hard']),
  language: z.string().default('ar'),
  locale: z.string().optional(),
  payload: drawPayloadSchema,
  source: z.enum(['human', 'ai_suggested']).default('human'),
});

const quizItemSchema = z.object({
  gameId: z.literal('quiz'),
  category: z.enum(QUIZ_CATEGORIES as [string, ...string[]]),
  difficulty: z.enum(['easy', 'medium', 'hard']),
  language: z.string().default('ar'),
  locale: z.string().optional(),
  payload: quizPayload,
  factAsOf: z.string().date().optional(),
  expiresAt: z.string().date().optional(),
  source: z.enum(['human', 'ai_suggested']).default('human'),
});

const itemSchema = z.discriminatedUnion('gameId', [quizItemSchema, spyItemSchema, liarItemSchema, whoItemSchema, emojiItemSchema, stopItemSchema, drawItemSchema]);

/** CSV columns for quiz imports (UTF-8, header row required). */
export const QUIZ_CSV_COLUMNS = [
  'category', 'difficulty', 'prompt', 'choice1', 'choice2', 'choice3', 'choice4', 'correct', 'explanation', 'fact_as_of', 'expires_at',
] as const;

export function adminRouter() {
  const r = Router();

  /* ---------------- content ---------------- */
  r.get('/content', requireAdmin('content_editor'), wrap(async (req, res) => {
    const status = z.enum(['draft', 'in_review', 'approved', 'rejected', 'retired']).optional().parse(req.query.status);
    const gameId = z.enum(['quiz', 'spy', 'liar', 'who', 'emoji', 'stop']).default('quiz').parse(req.query.gameId);
    const items = await prisma.contentItem.findMany({
      where: { gameId, ...(status ? { status } : {}) },
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
    res.json({ items });
  }));

  r.post('/content', requireAdmin('content_editor'), wrap(async (req, res) => {
    const body = itemSchema.parse(req.body);
    const item = await prisma.$transaction(async (tx) => {
      const created = await tx.contentItem.create({
        data: {
          gameId: body.gameId,
          category: body.category,
          difficulty: body.difficulty,
          language: body.language,
          locale: body.locale,
          payload: body.payload,
          source: body.source,
          status: 'in_review',
          factAsOf: body.gameId === 'quiz' && body.factAsOf ? new Date(body.factAsOf) : null,
          expiresAt: body.gameId === 'quiz' && body.expiresAt ? new Date(body.expiresAt) : null,
        },
      });
      await audit(tx, req.userId!, 'content_create', 'content', created.id);
      return created;
    });
    res.status(201).json({ item });
  }));

  r.post('/content/import', requireAdmin('content_editor'), wrap(async (req, res) => {
    if (typeof req.body !== 'string' || !req.body.trim()) throw new HttpError(400, 'csv_body_required');
    const fileName = String(req.query.fileName ?? 'upload.csv').slice(0, 200);
    let rows: Record<string, string>[];
    try {
      rows = parse(req.body, { columns: true, skip_empty_lines: true, trim: true, bom: true });
    } catch {
      throw new HttpError(400, 'csv_unreadable');
    }
    const errors: { row: number; error: string }[] = [];
    const valid: z.infer<typeof quizItemSchema>[] = [];
    rows.forEach((row, i) => {
      const choices = [row.choice1, row.choice2, row.choice3, row.choice4].filter((c): c is string => !!c);
      const parsed = quizItemSchema.safeParse({
        gameId: 'quiz',
        category: row.category,
        difficulty: row.difficulty,
        payload: { prompt: row.prompt, choices, correct: Number(row.correct) - 1, explanation: row.explanation || null },
        factAsOf: row.fact_as_of || undefined,
        expiresAt: row.expires_at || undefined,
      });
      if (parsed.success) valid.push(parsed.data);
      else errors.push({ row: i + 2, error: parsed.error.issues.map((x) => `${x.path.join('.')}: ${x.message}`).join('; ') });
    });
    const batch = await prisma.$transaction(async (tx) => {
      const b = await tx.importBatch.create({
        data: { uploadedBy: req.userId!, fileName, rowCount: rows.length, errorCount: errors.length, errors },
      });
      // Imported items always start as drafts and need human approval.
      await tx.contentItem.createMany({
        data: valid.map((v) => ({
          gameId: v.gameId, category: v.category, difficulty: v.difficulty, language: v.language,
          payload: v.payload, source: 'import_csv' as const, status: 'draft' as const, importBatchId: b.id,
          factAsOf: v.factAsOf ? new Date(v.factAsOf) : null, expiresAt: v.expiresAt ? new Date(v.expiresAt) : null,
        })),
      });
      await audit(tx, req.userId!, 'content_import', 'import_batch', b.id, { rows: rows.length, errors: errors.length });
      return b;
    });
    res.status(201).json({ batchId: batch.id, imported: valid.length, errors });
  }));

  r.post('/content/:id/review', requireAdmin('content_editor'), wrap(async (req, res) => {
    const { decision, note } = z
      .object({ decision: z.enum(['approved', 'rejected', 'retired']), note: z.string().max(500).optional() })
      .parse(req.body);
    const id = String(req.params.id);
    const item = await prisma.$transaction(async (tx) => {
      const current = await tx.contentItem.findUnique({ where: { id } });
      if (!current) throw new HttpError(404, 'not_found');
      const updated = await tx.contentItem.update({
        where: { id },
        data: { status: decision, publishedAt: decision === 'approved' ? new Date() : current.publishedAt },
      });
      await tx.contentReview.create({ data: { itemId: id, reviewerId: req.userId!, decision, note } });
      await audit(tx, req.userId!, `content_${decision}`, 'content', id, { note });
      return updated;
    });
    res.json({ item });
  }));

  /* ---------------- reports & sanctions ---------------- */
  r.get('/reports', requireAdmin('moderator'), wrap(async (req, res) => {
    const status = z.enum(['open', 'in_review', 'actioned', 'dismissed']).default('open').parse(req.query.status);
    const reports = await prisma.report.findMany({
      where: { status },
      orderBy: [{ severity: 'asc' }, { createdAt: 'asc' }],
      take: 100,
      include: {
        reporter: { select: { id: true, displayName: true } },
        reported: { select: { id: true, displayName: true, status: true, ageBand: true } },
      },
    });
    res.json({ reports });
  }));

  r.post('/reports/:id/resolve', requireAdmin('moderator'), wrap(async (req, res) => {
    const body = z
      .object({
        action: z.enum(['dismiss', 'warning', 'comm_restriction', 'ranked_ban', 'suspension', 'lift_restriction']),
        days: z.number().int().min(1).max(3650).optional(),
        note: z.string().max(1000).optional(),
      })
      .parse(req.body);
    const id = String(req.params.id);
    const result = await prisma.$transaction(async (tx) => {
      const report = await tx.report.findUnique({ where: { id } });
      if (!report) throw new HttpError(404, 'not_found');
      if (report.status === 'actioned' || report.status === 'dismissed') throw new HttpError(409, 'already_resolved');
      const now = new Date();
      if (body.action === 'dismiss' || body.action === 'lift_restriction') {
        const target = await tx.user.findUniqueOrThrow({ where: { id: report.reportedId } });
        if (target.status === 'restricted') await tx.user.update({ where: { id: target.id }, data: { status: 'active' } });
      } else {
        await tx.sanction.create({
          data: {
            userId: report.reportedId,
            kind: body.action,
            reason: report.reason,
            reportId: report.id,
            issuedBy: req.userId!,
            endsAt: body.days ? new Date(now.getTime() + body.days * 86_400_000) : null,
          },
        });
        await tx.user.update({
          where: { id: report.reportedId },
          data: { status: body.action === 'suspension' ? 'suspended' : 'active' },
        });
      }
      const updated = await tx.report.update({
        where: { id },
        data: { status: body.action === 'dismiss' ? 'dismissed' : 'actioned', resolvedAt: now, resolvedBy: req.userId! },
      });
      await audit(tx, req.userId!, `report_${body.action}`, 'report', id, { note: body.note, days: body.days });
      return updated;
    });
    res.json({ report: result });
  }));

  r.get('/audit', requireAdmin(), wrap(async (_req, res) => {
    const rows = await prisma.auditLog.findMany({ orderBy: { at: 'desc' }, take: 200 });
    res.json({ entries: rows.map((e) => ({ ...e, id: e.id.toString() })) });
  }));

  r.get('/stats', requireAdmin(), wrap(async (_req, res) => {
    const since = new Date(Date.now() - 86_400_000);
    const [users, matches24h, openReports, pendingContent] = await Promise.all([
      prisma.user.count(),
      prisma.match.count({ where: { startedAt: { gte: since } } }),
      prisma.report.count({ where: { status: 'open' } }),
      prisma.contentItem.count({ where: { status: { in: ['draft', 'in_review'] } } }),
    ]);
    res.json({ users, matches24h, openReports, pendingContent });
  }));

  return r;
}
