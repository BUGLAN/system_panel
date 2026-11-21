/**
 * 证据照片的磁盘存储：data/uploads/<userId>/<id>.jpg（不在公开静态目录，只能经鉴权接口读）。
 * 文件名、目录全部由服务端生成（随机 id），不接受客户端给的路径。
 */
import { mkdirSync, readFileSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { and, eq } from 'drizzle-orm';
import type { Db } from '../db/client';
import { evidence } from '../db/schema';
import { randomId, sha256 } from '../auth/tokens';

export const EVIDENCE_MAX_BYTES = 2 * 1024 * 1024;
const SAFE_ID = /^[A-Za-z0-9_-]{8,48}$/;

export const isSafeId = (id: string) => SAFE_ID.test(id);

/** 看文件头认类型（不信扩展名和 Content-Type） */
export function sniffImage(b: Uint8Array): 'image/jpeg' | 'image/png' | 'image/webp' | null {
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'image/jpeg';
  if (b.length >= 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47)
    return 'image/png';
  if (
    b.length >= 12 &&
    String.fromCharCode(...b.subarray(0, 4)) === 'RIFF' &&
    String.fromCharCode(...b.subarray(8, 12)) === 'WEBP'
  )
    return 'image/webp';
  return null;
}

const EXT: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

export interface EvidenceRow {
  id: string;
  file: string;
  mime: string;
  bytes: number;
  takenAt: number;
}

export function uploadsDir(dataDir: string): string {
  return join(dataDir, 'uploads');
}

/** 落盘 + 入表；返回 id */
export function putEvidenceFile(
  db: Db,
  dataDir: string,
  o: {
    userId: string;
    bytes: Uint8Array;
    mime: string;
    takenAt: number;
    serial: number;
    id?: string;
  },
): EvidenceRow {
  const id = o.id && isSafeId(o.id) ? o.id : randomId();
  const rel = join(o.userId, `${id}.${EXT[o.mime] ?? 'jpg'}`);
  const dir = join(uploadsDir(dataDir), o.userId);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(uploadsDir(dataDir), rel), o.bytes);
  db.insert(evidence)
    .values({
      id,
      userId: o.userId,
      file: rel,
      mime: o.mime,
      bytes: o.bytes.length,
      sha256: sha256(o.bytes),
      takenAt: o.takenAt,
      questSerial: o.serial,
    })
    .onConflictDoNothing()
    .run();
  return { id, file: rel, mime: o.mime, bytes: o.bytes.length, takenAt: o.takenAt };
}

/** 按 id 取（不是这个用户的 = 没有） */
export function evidenceRow(db: Db, userId: string, id: string) {
  if (!isSafeId(id)) return null;
  return (
    db
      .select()
      .from(evidence)
      .where(and(eq(evidence.id, id), eq(evidence.userId, userId)))
      .get() ?? null
  );
}

export function readEvidenceFile(dataDir: string, file: string): Buffer | null {
  const p = join(uploadsDir(dataDir), file);
  return existsSync(p) ? readFileSync(p) : null;
}

export function dropEvidence(db: Db, dataDir: string, userId: string, id: string): void {
  const r = evidenceRow(db, userId, id);
  if (!r) return;
  rmSync(join(uploadsDir(dataDir), r.file), { force: true });
  db.delete(evidence)
    .where(and(eq(evidence.id, id), eq(evidence.userId, userId)))
    .run();
}

export function setEvidenceVerdict(
  db: Db,
  userId: string,
  id: string,
  status: string,
  note: string,
): void {
  db.update(evidence)
    .set({ status, note })
    .where(and(eq(evidence.id, id), eq(evidence.userId, userId)))
    .run();
}

/** 某用户的全部照片（导出 / 重置用） */
export function allEvidence(db: Db, userId: string) {
  return db.select().from(evidence).where(eq(evidence.userId, userId)).all();
}

/** 删掉某用户的全部照片（磁盘 + 表） */
export function clearEvidence(db: Db, dataDir: string, userId: string): void {
  rmSync(join(uploadsDir(dataDir), userId), { recursive: true, force: true });
  db.delete(evidence).where(eq(evidence.userId, userId)).run();
}
