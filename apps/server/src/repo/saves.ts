/**
 * 存档主档：一人一行（data + bak + version）。语义移植自前端 SaveRepo（G1.1）：
 *  - 写前把上一份好串滚进 bak（只滚能解析的串，坏档绝不进 bak），与主档同一条 UPDATE
 *  - 主档读坏 → 原串另存 save_corrupt + 记日志 → 退回 bak 并立刻写回 → 告诉前端 source=backup
 *  - bak 也坏 → 抛 SaveCorrupt（不静默清零，交给管理员处理）
 *  - 没有行 = 没有档（全新账号），version 0
 */
import { eq } from 'drizzle-orm';
import {
  SAVE_VERSION,
  freshSave,
  parseSave,
  stringifySave,
  type SaveData,
} from '@host/core/save/saveData';
import type { Db } from '../db/client';
import { saveCorrupt, saves } from '../db/schema';
import { ApiError } from '../http/errors';
import { log } from '../log';

export type SaveSource = 'primary' | 'backup' | 'none';

export interface LoadedSave {
  save: SaveData;
  version: number;
  source: SaveSource;
  /** 上一次带登录态的请求时刻（「你走了多久」） */
  lastSeenAt: number | null;
}

export const saveCorruptError = () =>
  new ApiError(500, 'save_corrupt', '存档读不出来，备份也坏了。数据没删，联系管理员处理。');

export function loadSave(db: Db, userId: string, now: number): LoadedSave {
  const row = db.select().from(saves).where(eq(saves.userId, userId)).get();
  if (!row) return { save: freshSave(now), version: 0, source: 'none', lastSeenAt: null };
  const main = parseSave(row.data, now);
  if (main)
    return { save: main, version: row.version, source: 'primary', lastSeenAt: row.lastSeenAt };

  // 主档坏了：原串留底，退 bak
  db.insert(saveCorrupt).values({ userId, raw: row.data, at: now }).run();
  log.error('存档主档解析失败，尝试用备份恢复', { u: userId, bytes: row.data.length });
  const restored = row.bak ? parseSave(row.bak, now) : null;
  if (!restored || !row.bak) {
    log.error('存档备份也解析失败', { u: userId });
    throw saveCorruptError();
  }
  const version = row.version + 1;
  db.update(saves)
    .set({ data: row.bak, version, updatedAt: now })
    .where(eq(saves.userId, userId))
    .run();
  return { save: restored, version, source: 'backup', lastSeenAt: row.lastSeenAt };
}

/** 写档：上一份（能解析的）主档滚进 bak；返回新版本号 */
export function writeSave(db: Db, userId: string, save: SaveData, now: number): number {
  const raw = stringifySave(save, now);
  const row = db
    .select({ data: saves.data, version: saves.version })
    .from(saves)
    .where(eq(saves.userId, userId))
    .get();
  if (!row) {
    db.insert(saves)
      .values({
        userId,
        data: raw,
        bak: null,
        schemaV: SAVE_VERSION,
        version: 1,
        updatedAt: now,
        lastSeenAt: null,
      })
      .run();
    return 1;
  }
  const prevGood = parseSave(row.data, now) ? row.data : undefined;
  const version = row.version + 1;
  db.update(saves)
    .set({
      data: raw,
      ...(prevGood !== undefined ? { bak: prevGood } : {}),
      schemaV: SAVE_VERSION,
      version,
      updatedAt: now,
    })
    .where(eq(saves.userId, userId))
    .run();
  return version;
}

/** 盖「最近一次来过」的戳（没有档就不建） */
export function touchSeen(db: Db, userId: string, now: number): void {
  db.update(saves).set({ lastSeenAt: now }).where(eq(saves.userId, userId)).run();
}

/** 当前版本号（没有档 = 0） */
export function saveVersion(db: Db, userId: string): number {
  return db.select({ v: saves.version }).from(saves).where(eq(saves.userId, userId)).get()?.v ?? 0;
}

/** 重置：删掉这一行（下次读就是全新档）；版本号要继续往上走，所以留一行空白档 */
export function resetSave(db: Db, userId: string, now: number): number {
  const v = saveVersion(db, userId);
  db.delete(saves).where(eq(saves.userId, userId)).run();
  db.insert(saves)
    .values({
      userId,
      data: stringifySave(freshSave(now), now),
      bak: null,
      schemaV: SAVE_VERSION,
      version: v + 1,
      updatedAt: now,
      lastSeenAt: now,
    })
    .run();
  return v + 1;
}
