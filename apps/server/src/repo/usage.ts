/**
 * 每日 LLM 用量（按用户时区的日历日）。只对用服务器默认 Key 的普通用户设上限。
 */
import { and, eq, sql } from 'drizzle-orm';
import type { Db } from '../db/client';
import { llmUsage } from '../db/schema';

export type UsageKind = 'text' | 'vision';

export function usageOf(db: Db, userId: string, day: string): { text: number; vision: number } {
  const r = db
    .select()
    .from(llmUsage)
    .where(and(eq(llmUsage.userId, userId), eq(llmUsage.day, day)))
    .get();
  return { text: r?.textCalls ?? 0, vision: r?.visionCalls ?? 0 };
}

export function bumpUsage(db: Db, userId: string, day: string, kind: UsageKind): void {
  const col = kind === 'text' ? llmUsage.textCalls : llmUsage.visionCalls;
  db.insert(llmUsage)
    .values({
      userId,
      day,
      textCalls: kind === 'text' ? 1 : 0,
      visionCalls: kind === 'vision' ? 1 : 0,
    })
    .onConflictDoUpdate({
      target: [llmUsage.userId, llmUsage.day],
      set: { [kind === 'text' ? 'textCalls' : 'visionCalls']: sql`${col} + 1` },
    })
    .run();
}
