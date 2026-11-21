/**
 * 导出 / 导入 / 重置（范围一致）：存档、聊天、流水、长期记忆、证据照片（导入前快照随重置一起清）。
 * 不碰：账号、LLM 设置（含 Key）、同意记录。导出永远不含 Key。
 */
import { mkdirSync, rmSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { eq } from 'drizzle-orm';
import {
  BUNDLE_APP,
  BUNDLE_KIND,
  BUNDLE_VERSION,
  base64ToBytes,
  bytesToBase64,
  type BackupBundle,
  type CheckedBundle,
} from '@host/core/save/bundle';
import { saveToJson } from '@host/core/save/saveData';
import { historyFromRow } from '@host/core/flow/history';
import type { HistoryEntry } from '@host/core/flow/types';
import type { Json } from '@host/core/save/json';
import { chatFromRow, type ChatMessage } from '../agent/chatService';
import type { MemoryEntry } from '../agent/memory';
import type { Db } from '../db/client';
import { memory as memoryTable, saveCorrupt, saves } from '../db/schema';
import {
  EVIDENCE_MAX_BYTES,
  allEvidence,
  clearEvidence,
  isSafeId,
  putEvidenceFile,
  readEvidenceFile,
  sniffImage,
} from '../evidence/store';
import { appendChat, clearChat, listChat } from './chat';
import { appendHistory, clearHistory, listHistory } from './history';
import { memoryBackendFor } from './memory';
import { loadSave, resetSave, writeSave } from './saves';

export function snapshotFile(dataDir: string, userId: string): string {
  return join(dataDir, 'snapshots', userId, 'pre-import.json');
}

export async function exportBundle(
  db: Db,
  dataDir: string,
  userId: string,
  now: number,
): Promise<BackupBundle> {
  const row = db.select({ v: saves.version }).from(saves).where(eq(saves.userId, userId)).get();
  const save = row ? loadSave(db, userId, now).save : null;
  const mem = await memoryBackendFor(db, userId).all();
  const evidence = allEvidence(db, userId).flatMap((e) => {
    const buf = readEvidenceFile(dataDir, e.file);
    return buf
      ? [{ id: e.id, type: e.mime, takenAt: e.takenAt, data: bytesToBase64(new Uint8Array(buf)) }]
      : [];
  });
  return {
    app: BUNDLE_APP,
    kind: BUNDLE_KIND,
    version: BUNDLE_VERSION,
    exportedAt: now,
    save: save ? saveToJson(save) : null,
    chat: listChat(db, userId) as unknown as Json[],
    history: listHistory(db, userId) as unknown as Json[],
    memory: mem as unknown as Json[],
    evidence,
  };
}

/** 导入包里的照片先全部验一遍（类型 / 大小 / 编号），任何一张不行就整包拒收 */
export function checkBundlePhotos(b: CheckedBundle): string | null {
  for (let i = 0; i < b.bundle.evidence.length; i++) {
    const e = b.bundle.evidence[i]!;
    const bytes = base64ToBytes(e.data);
    if (!isSafeId(e.id)) return `第 ${i + 1} 张证据照片的编号读不懂。`;
    if (bytes.length > EVIDENCE_MAX_BYTES) return `第 ${i + 1} 张证据照片太大了（超过 2MB）。`;
    if (!sniffImage(bytes)) return `第 ${i + 1} 张证据照片读不出来。`;
  }
  return null;
}

/** 清掉这个用户的全部游戏数据（重置）；返回新版本号 */
export function wipeUserData(db: Db, dataDir: string, userId: string, now: number): number {
  return db.transaction(() => {
    clearChat(db, userId);
    clearHistory(db, userId);
    db.delete(memoryTable).where(eq(memoryTable.userId, userId)).run();
    db.delete(saveCorrupt).where(eq(saveCorrupt.userId, userId)).run();
    clearEvidence(db, dataDir, userId);
    rmSync(join(dataDir, 'snapshots', userId), { recursive: true, force: true });
    return resetSave(db, userId, now);
  });
}

/** 导入：先把当前数据写成快照，再整体覆盖（库里同一事务；照片已逐张预检过） */
export async function importBundle(
  db: Db,
  dataDir: string,
  userId: string,
  b: CheckedBundle,
  now: number,
): Promise<number> {
  const snap = await exportBundle(db, dataDir, userId, now);
  const file = snapshotFile(dataDir, userId);
  mkdirSync(join(dataDir, 'snapshots', userId), { recursive: true });
  writeFileSync(file, JSON.stringify(snap));

  const chat = b.bundle.chat.map(chatFromRow).filter((m): m is ChatMessage => m !== null);
  const history = b.bundle.history.map(historyFromRow).filter((e): e is HistoryEntry => e !== null);
  const mem = b.bundle.memory
    .map((m): MemoryEntry | null =>
      typeof m['text'] === 'string' && typeof m['id'] === 'string'
        ? {
            id: m['id'],
            text: m['text'],
            at: typeof m['at'] === 'number' ? m['at'] : now,
            source:
              (['interview', 'chat', 'tool', 'milestone'] as const).find(
                (s) => s === m['source'],
              ) ?? 'chat',
            weight: typeof m['weight'] === 'number' ? Math.trunc(m['weight']) : 1,
          }
        : null,
    )
    .filter((m): m is MemoryEntry => m !== null);

  const backend = memoryBackendFor(db, userId);
  return db.transaction(() => {
    clearChat(db, userId);
    clearHistory(db, userId);
    db.delete(memoryTable).where(eq(memoryTable.userId, userId)).run();
    clearEvidence(db, dataDir, userId);
    let version = resetSave(db, userId, now);
    if (b.save) version = writeSave(db, userId, b.save, now);
    appendChat(db, userId, chat);
    appendHistory(db, userId, history);
    for (const m of mem) void backend.put(m);
    for (const e of b.bundle.evidence) {
      const bytes = base64ToBytes(e.data);
      putEvidenceFile(db, dataDir, {
        userId,
        id: e.id,
        bytes,
        mime: sniffImage(bytes) ?? 'image/jpeg',
        takenAt: e.takenAt,
        serial: 0,
      });
    }
    return version;
  });
}

export function hasSnapshot(dataDir: string, userId: string): boolean {
  return existsSync(snapshotFile(dataDir, userId));
}

export function readSnapshot(dataDir: string, userId: string): string | null {
  const f = snapshotFile(dataDir, userId);
  return existsSync(f) ? readFileSync(f, 'utf8') : null;
}
