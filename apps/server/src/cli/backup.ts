/**
 * 在线备份：better-sqlite3 的 backup()（不停服、WAL 下也一致）+ 复制上传目录与快照。
 * 产物：<BACKUP_DIR>/<时间戳>/{app.db, uploads/, snapshots/}；只留最近 keep 份。
 * 恢复步骤见 docs/02。
 */
import { cpSync, existsSync, mkdirSync, readdirSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import type { Config } from '../config';
import type { DbHandle } from '../db/client';

function stamp(ms: number): string {
  return new Date(ms).toISOString().replace(/[-:]/g, '').replace(/\..+$/, '').replace('T', '-');
}

export async function runBackup(
  dbh: DbHandle,
  config: Config,
  o: { keep: number; now: number },
): Promise<string> {
  const dir = join(config.backupDir, stamp(o.now));
  mkdirSync(dir, { recursive: true });
  await dbh.sqlite.backup(join(dir, 'app.db'));
  for (const sub of ['uploads', 'snapshots']) {
    const src = join(config.dataDir, sub);
    if (existsSync(src)) cpSync(src, join(dir, sub), { recursive: true });
  }
  const keep = Math.max(1, o.keep || 14);
  const all = readdirSync(config.backupDir)
    .filter((d) => /^\d{8}-\d{6}$/.test(d))
    .sort();
  for (const old of all.slice(0, Math.max(0, all.length - keep)))
    rmSync(join(config.backupDir, old), { recursive: true, force: true });
  return dir;
}
