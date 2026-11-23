/**
 * 流水（结算；旧版还有认输 / 超时记录）：每人最多 HISTORY_MAX 条，超出删最旧的。
 */
import { asc, count, eq, inArray } from 'drizzle-orm';
import { HISTORY_MAX, historyFromRow } from '@host/core/flow/history';
import type { HistoryEntry } from '@host/core/flow/types';
import type { Db } from '../db/client';
import { history } from '../db/schema';

export function appendHistory(db: Db, userId: string, entries: HistoryEntry[]): void {
  if (!entries.length) return;
  db.insert(history)
    .values(entries.map((e) => ({ userId, at: e.at, data: JSON.stringify(e) })))
    .run();
  const n = db.select({ n: count() }).from(history).where(eq(history.userId, userId)).get()?.n ?? 0;
  if (n > HISTORY_MAX) {
    const old = db
      .select({ id: history.id })
      .from(history)
      .where(eq(history.userId, userId))
      .orderBy(asc(history.id))
      .limit(n - HISTORY_MAX)
      .all()
      .map((r) => r.id);
    db.delete(history).where(inArray(history.id, old)).run();
  }
}

/** 旧 → 新 */
export function listHistory(db: Db, userId: string): HistoryEntry[] {
  return db
    .select({ data: history.data })
    .from(history)
    .where(eq(history.userId, userId))
    .orderBy(asc(history.id))
    .all()
    .map((r) => {
      try {
        return historyFromRow(JSON.parse(r.data));
      } catch {
        return null;
      }
    })
    .filter((e): e is HistoryEntry => e !== null);
}

export function clearHistory(db: Db, userId: string): void {
  db.delete(history).where(eq(history.userId, userId)).run();
}
