/**
 * 打开数据库：WAL、外键、忙等待；启动时跑迁移。测试用 ':memory:'。
 */
import Database from 'better-sqlite3';
import { drizzle, type BetterSQLite3Database } from 'drizzle-orm/better-sqlite3';
import { migrate } from 'drizzle-orm/better-sqlite3/migrator';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as schema from './schema';

export type Db = BetterSQLite3Database<typeof schema>;

export interface DbHandle {
  sqlite: Database.Database;
  db: Db;
  close(): void;
}

/** 迁移目录：源码里在 apps/server/drizzle，打包后复制到 dist/drizzle */
export function migrationsDir(): string {
  const here = dirname(fileURLToPath(import.meta.url));
  for (const c of [
    join(here, 'drizzle'),
    join(here, '..', '..', 'drizzle'),
    join(here, '..', 'drizzle'),
  ]) {
    if (existsSync(join(c, 'meta', '_journal.json'))) return c;
  }
  throw new Error(`找不到数据库迁移目录（从 ${here} 往上找 drizzle/）`);
}

export function openDb(file: string): DbHandle {
  const sqlite = new Database(file);
  sqlite.pragma('journal_mode = WAL');
  sqlite.pragma('foreign_keys = ON');
  sqlite.pragma('busy_timeout = 5000');
  sqlite.pragma('synchronous = NORMAL');
  const db = drizzle(sqlite, { schema });
  migrate(db, { migrationsFolder: migrationsDir() });
  return { sqlite, db, close: () => sqlite.close() };
}
