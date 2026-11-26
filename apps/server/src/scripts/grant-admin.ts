// Usage: npx tsx src/scripts/grant-admin.ts <userId> [owner|moderator|content_editor]
import { prisma } from '../db';

async function main() {
  const [userId, role = 'owner'] = process.argv.slice(2);
  if (!userId) throw new Error('userId required');
  if (!['owner', 'moderator', 'content_editor'].includes(role)) throw new Error('bad role');
  await prisma.adminRole.upsert({
    where: { userId },
    create: { userId, role: role as 'owner' },
    update: { role: role as 'owner' },
  });
  await prisma.auditLog.create({ data: { actorId: 'cli', action: 'grant_admin', targetType: 'user', targetId: userId, data: { role } } });
  console.log(`granted ${role} to ${userId}`);
}
main().finally(() => prisma.$disconnect());
