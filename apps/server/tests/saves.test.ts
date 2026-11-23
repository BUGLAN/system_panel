// 存档仓库的语义（移植自前端 saveRepo 单测）：bak 滚动、坏档不进 bak、坏档恢复、重置
import { describe, expect, it } from 'vitest';
import { freshSave, parseSave } from '@host/core/save/saveData';
import { createUser } from '../src/auth/accounts';
import { openDb } from '../src/db/client';
import { saves } from '../src/db/schema';
import { loadSave, resetSave, writeSave } from '../src/repo/saves';

async function db() {
  const h = openDb(':memory:');
  const u = await createUser(h.db, {
    username: 'alice',
    password: 'password123',
    tz: 'UTC',
    now: 1,
  });
  return { db: h.db, uid: u.id };
}

describe('存档仓库', () => {
  it('没有档 = 全新档、version 0、source none', async () => {
    const { db: d, uid } = await db();
    expect(loadSave(d, uid, 5)).toMatchObject({ version: 0, source: 'none', lastSeenAt: null });
  });

  it('每次写都把上一份好档滚进 bak，版本 +1', async () => {
    const { db: d, uid } = await db();
    const a = freshSave(1);
    a.host.exp = 1;
    const b = freshSave(1);
    b.host.exp = 2;
    expect(writeSave(d, uid, a, 10)).toBe(1);
    expect(writeSave(d, uid, b, 20)).toBe(2);
    const row = d.select().from(saves).get()!;
    expect(parseSave(row.data, 0)!.host.exp).toBe(2);
    expect(parseSave(row.bak!, 0)!.host.exp).toBe(1);
  });

  it('坏掉的主档绝不滚进 bak', async () => {
    const { db: d, uid } = await db();
    writeSave(d, uid, freshSave(1), 10);
    writeSave(d, uid, freshSave(1), 11);
    const goodBak = d.select().from(saves).get()!.bak;
    d.update(saves).set({ data: 'garbage' }).run();
    writeSave(d, uid, freshSave(1), 12);
    expect(d.select().from(saves).get()!.bak).toBe(goodBak);
  });

  it('版本比本服务认识的新 → 当坏档处理（退 bak）', async () => {
    const { db: d, uid } = await db();
    writeSave(d, uid, freshSave(1), 10);
    writeSave(d, uid, freshSave(1), 11);
    d.update(saves)
      .set({ data: JSON.stringify({ v: 99 }) })
      .run();
    expect(loadSave(d, uid, 12).source).toBe('backup');
  });

  it('重置：留一行空白档，版本号继续往上走', async () => {
    const { db: d, uid } = await db();
    const a = freshSave(1);
    a.host.lv = 9;
    writeSave(d, uid, a, 10);
    expect(resetSave(d, uid, 20)).toBe(2);
    const l = loadSave(d, uid, 30);
    expect(l.save.host.lv).toBe(1);
    expect(d.select().from(saves).get()!.bak).toBeNull();
  });
});
