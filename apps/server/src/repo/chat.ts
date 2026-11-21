/**
 * 聊天记录：每人保留最近 CHAT_HISTORY_MAX 条（旧 → 新）。
 */
import { asc, count, eq, inArray } from 'drizzle-orm';
import { CHAT_HISTORY_MAX, chatFromRow, type ChatMessage } from '../agent/chatService';
import type { Db } from '../db/client';
import { chat } from '../db/schema';

export function listChat(db: Db, userId: string): ChatMessage[] {
  return db
    .select({ data: chat.data })
    .from(chat)
    .where(eq(chat.userId, userId))
    .orderBy(asc(chat.id))
    .all()
    .map((r) => {
      try {
        return chatFromRow(JSON.parse(r.data));
      } catch {
        return null;
      }
    })
    .filter((m): m is ChatMessage => m !== null);
}

export function appendChat(db: Db, userId: string, msgs: ChatMessage[]): void {
  if (!msgs.length) return;
  db.insert(chat)
    .values(msgs.map((m) => ({ userId, at: m.at, data: JSON.stringify(m) })))
    .run();
  const n = db.select({ n: count() }).from(chat).where(eq(chat.userId, userId)).get()?.n ?? 0;
  if (n > CHAT_HISTORY_MAX) {
    const old = db
      .select({ id: chat.id })
      .from(chat)
      .where(eq(chat.userId, userId))
      .orderBy(asc(chat.id))
      .limit(n - CHAT_HISTORY_MAX)
      .all()
      .map((r) => r.id);
    db.delete(chat).where(inArray(chat.id, old)).run();
  }
}

export function clearChat(db: Db, userId: string): void {
  db.delete(chat).where(eq(chat.userId, userId)).run();
}
