import type { ContentRow, ContentRequest, Rng } from '../games/engine';
import { prisma } from '../db';

/**
 * Picks approved, non-expired content for a match. Only items a human approved
 * are ever playable (AI suggestions and imports start as drafts).
 */
export async function selectContent(req: ContentRequest, rng: Rng, now = new Date()): Promise<ContentRow[]> {
  const rows = await prisma.contentItem.findMany({
    where: {
      gameId: req.gameId,
      status: 'approved',
      difficulty: req.difficulty,
      ...(req.category === 'mixed' ? {} : { category: req.category }),
      OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
    },
    select: { id: true, category: true, difficulty: true, payload: true, acceptedAnswers: true },
    take: 500,
  });
  return rng.shuffle(rows).slice(0, req.count);
}
