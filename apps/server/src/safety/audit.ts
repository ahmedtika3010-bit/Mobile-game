import type { Tx } from '../db';

export async function audit(tx: Tx, actorId: string, action: string, targetType: string, targetId: string | null, data?: object) {
  await tx.auditLog.create({ data: { actorId, action, targetType, targetId, data } });
}
