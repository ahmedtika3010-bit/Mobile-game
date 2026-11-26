import { Router } from 'express';
import { z } from 'zod';
import type { ReportSeverity } from '@prisma/client';
import { config } from '../config';
import { prisma } from '../db';
import { audit } from '../safety/audit';
import { HttpError, wrap } from './app';

export const REPORT_REASONS: Record<string, ReportSeverity> = {
  child_safety: 'critical',
  threat_or_self_harm: 'critical',
  sexual_content: 'high',
  hate_or_harassment: 'high',
  bullying: 'medium',
  cheating: 'medium',
  inappropriate_name_or_avatar: 'low',
  spam: 'low',
  other: 'low',
};

const reportSchema = z.object({
  reportedUserId: z.string().uuid(),
  reason: z.enum(Object.keys(REPORT_REASONS) as [string, ...string[]]),
  matchId: z.string().uuid().optional(),
  roomId: z.string().max(64).optional(),
  note: z.string().max(500).optional(),
});

export function safetyRouter() {
  const r = Router();

  r.post('/reports', wrap(async (req, res) => {
    const body = reportSchema.parse(req.body);
    const reporterId = req.userId!;
    if (body.reportedUserId === reporterId) throw new HttpError(400, 'cannot_report_self');
    const reported = await prisma.user.findUnique({ where: { id: body.reportedUserId } });
    if (!reported) throw new HttpError(404, 'user_not_found');
    // Simple rate limit: at most 20 reports per reporter per day.
    const recent = await prisma.report.count({ where: { reporterId, createdAt: { gte: new Date(Date.now() - 86_400_000) } } });
    if (recent >= 20) throw new HttpError(429, 'too_many_reports');

    const severity = REPORT_REASONS[body.reason]!;
    const report = await prisma.$transaction(async (tx) => {
      // Keep only the minimal evidence: the reported player's recorded events in that match.
      const evidence = body.matchId
        ? await tx.matchEvent.findMany({ where: { matchId: body.matchId, userId: body.reportedUserId }, take: 200, orderBy: { at: 'desc' } })
        : [];
      const created = await tx.report.create({
        data: {
          reporterId,
          reportedId: body.reportedUserId,
          reason: body.reason,
          severity,
          matchId: body.matchId,
          roomId: body.roomId,
          note: body.note,
          evidence: evidence.length ? JSON.parse(JSON.stringify(evidence, (_k, v) => (typeof v === 'bigint' ? v.toString() : v))) : undefined,
          evidenceExpiresAt: new Date(Date.now() + config.reportEvidenceRetentionDays * 86_400_000),
        },
      });
      if (severity === 'critical' && reported.status === 'active') {
        // Immediate protective restriction until a human reviews the report.
        await tx.user.update({ where: { id: reported.id }, data: { status: 'restricted' } });
        await audit(tx, 'system', 'auto_restrict', 'user', reported.id, { reportId: created.id, reason: body.reason });
      }
      return created;
    });
    // Reporting someone also blocks them for the reporter.
    await prisma.block.upsert({
      where: { blockerId_blockedId: { blockerId: reporterId, blockedId: body.reportedUserId } },
      create: { blockerId: reporterId, blockedId: body.reportedUserId },
      update: {},
    });
    res.status(201).json({ reportId: report.id, severity });
  }));

  r.get('/blocks', wrap(async (req, res) => {
    const rows = await prisma.block.findMany({
      where: { blockerId: req.userId! },
      include: { blocked: { select: { id: true, displayName: true, avatarId: true } } },
    });
    res.json({ blocks: rows.map((b) => b.blocked) });
  }));

  r.post('/blocks', wrap(async (req, res) => {
    const { userId } = z.object({ userId: z.string().uuid() }).parse(req.body);
    if (userId === req.userId) throw new HttpError(400, 'cannot_block_self');
    await prisma.block.upsert({
      where: { blockerId_blockedId: { blockerId: req.userId!, blockedId: userId } },
      create: { blockerId: req.userId!, blockedId: userId },
      update: {},
    });
    res.status(204).end();
  }));

  r.delete('/blocks/:userId', wrap(async (req, res) => {
    await prisma.block.deleteMany({ where: { blockerId: req.userId!, blockedId: String(req.params.userId) } });
    res.status(204).end();
  }));

  return r;
}
