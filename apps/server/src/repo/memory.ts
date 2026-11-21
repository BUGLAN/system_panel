/**
 * 长期记忆的存储后端（每人一份，MemoryStore 的语义不变：同文去重、≤200 条、按相关度取 ≤8 条）。
 */
import { and, eq, inArray } from 'drizzle-orm';
import {
  MemoryStore,
  type MemoryBackend,
  type MemoryEntry,
  type MemorySource,
} from '../agent/memory';
import type { Db } from '../db/client';
import { memory } from '../db/schema';

const SOURCES: readonly MemorySource[] = ['interview', 'chat', 'tool', 'milestone'];

export function memoryBackendFor(db: Db, userId: string): MemoryBackend {
  return {
    all: async () =>
      db
        .select()
        .from(memory)
        .where(eq(memory.userId, userId))
        .all()
        .map((r): MemoryEntry => ({
          id: r.id,
          text: r.text,
          at: r.at,
          source: (SOURCES as readonly string[]).includes(r.source)
            ? (r.source as MemorySource)
            : 'chat',
          weight: r.weight,
        })),
    put: async (e) =>
      void db
        .insert(memory)
        .values({ userId, ...e })
        .onConflictDoUpdate({
          target: [memory.userId, memory.id],
          set: { text: e.text, at: e.at, source: e.source, weight: e.weight },
        })
        .run(),
    remove: async (ids) => {
      if (ids.length)
        db.delete(memory)
          .where(and(eq(memory.userId, userId), inArray(memory.id, ids)))
          .run();
    },
    clear: async () => void db.delete(memory).where(eq(memory.userId, userId)).run(),
  };
}

export function memoryFor(db: Db, userId: string, clock: () => number): MemoryStore {
  return new MemoryStore(memoryBackendFor(db, userId), clock);
}
