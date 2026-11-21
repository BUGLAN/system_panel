import { beforeEach, describe, expect, test } from 'vitest';
import { HostDb, KV } from '../../src/store/db';
import { SaveRepo } from '../../src/store/saveRepo';
import { DataRepo } from '../../src/store/dataRepo';
import { freshSave, parseSave } from '../../src/core/save/saveData';
import { T0, sampleSave } from '../fixtures';

let n = 0;
let db: HostDb;
let clock: number;
const tick = () => clock;
const repo = () => new SaveRepo(db, tick);

beforeEach(() => {
  db = new HostDb(`save-test-${n++}`);
  clock = T0;
});

const raw = async (key: string) => (await db.kv.get(key))?.value as string | undefined;
const coinsOf = (s: string | undefined) => (s ? parseSave(s, T0)?.host.coins : undefined);

describe('备份滚动与坏档保护（G1.1）', () => {
  test('正常存两次 → bak 是第一次的内容，主档是第二次', async () => {
    const r = repo();
    const s = sampleSave();
    await r.save({ ...s, host: { ...s.host, coins: 1 } });
    await r.save({ ...s, host: { ...s.host, coins: 2 } });
    expect(coinsOf(await raw(KV.saveBak))).toBe(1);
    expect(coinsOf(await raw(KV.save))).toBe(2);
  });

  test('跨启动：读到的好档在本次第一次存盘时滚进 bak', async () => {
    const s = sampleSave();
    await repo().save({ ...s, host: { ...s.host, coins: 10 } });
    const r2 = repo();
    const { source } = await r2.loadDetailed();
    expect(source).toBe('primary');
    await r2.save({ ...s, host: { ...s.host, coins: 11 } });
    expect(coinsOf(await raw(KV.saveBak))).toBe(10);
    expect(coinsOf(await raw(KV.save))).toBe(11);
  });

  test('坏主档 → 从 bak 恢复；原串另存 corrupt；主档立刻被好数据写回', async () => {
    const r = repo();
    const s = sampleSave();
    await r.save({ ...s, host: { ...s.host, coins: 5 } });
    await r.save({ ...s, host: { ...s.host, coins: 6 } });
    await db.kv.put({ key: KV.save, value: '{"host": 截断了' });

    const r2 = repo();
    const { data, source } = await r2.loadDetailed();
    expect(source).toBe('backup');
    expect(data.host.coins).toBe(5);
    expect(await raw(KV.saveCorrupt)).toBe('{"host": 截断了');
    expect(coinsOf(await raw(KV.save))).toBe(5);

    // 下次存盘：bak 仍是那份好档，不会把坏串滚进去
    await r2.save({ ...data, host: { ...data.host, coins: 7 } });
    expect(coinsOf(await raw(KV.saveBak))).toBe(5);
    expect(coinsOf(await raw(KV.save))).toBe(7);
  });

  test('坏主档且没有 bak → 空白档、source=corrupt，corrupt 存了原串', async () => {
    await db.kv.put({ key: KV.save, value: 'garbage' });
    const { data, source } = await repo().loadDetailed();
    expect(source).toBe('corrupt');
    expect(data).toEqual(freshSave(T0));
    expect(await raw(KV.saveCorrupt)).toBe('garbage');
  });

  test('不是对象 / 版本比 App 新 也算坏档（走 bak）', async () => {
    const r = repo();
    await r.save(sampleSave());
    await r.save(sampleSave());
    for (const bad of ['[1,2]', '"str"', JSON.stringify({ v: 99 })]) {
      await db.kv.put({ key: KV.save, value: bad });
      const { source } = await repo().loadDetailed();
      expect(source, bad).toBe('backup');
    }
  });

  test('主档是空串（截断）→ 走 bak；空串不另存 corrupt', async () => {
    const r = repo();
    await r.save(sampleSave());
    await r.save(sampleSave());
    await db.kv.put({ key: KV.save, value: '' });
    const { source } = await repo().loadDetailed();
    expect(source).toBe('backup');
    expect(await raw(KV.saveCorrupt)).toBeUndefined();
  });

  test('bak 也坏 → 空白档、source=corrupt', async () => {
    await db.kv.put({ key: KV.save, value: 'bad' });
    await db.kv.put({ key: KV.saveBak, value: 'also bad' });
    const { source, data } = await repo().loadDetailed();
    expect(source).toBe('corrupt');
    expect(data.goal.plan).toEqual([]);
  });

  test('没有主档 = 没有档，不去翻 bak（不复活旧档）', async () => {
    await db.kv.put({ key: KV.saveBak, value: JSON.stringify({ host: { coins: 999 } }) });
    const { data, source } = await repo().loadDetailed();
    expect(source).toBe('none');
    expect(data.host.coins).toBe(0);
  });

  test('存盘盖上 lastSeen', async () => {
    clock = T0 + 12345;
    await repo().save(sampleSave());
    const back = await repo().load();
    expect(back.lastSeen).toBe(T0 + 12345);
  });
});

describe('冻结与重置', () => {
  test('冻结后 save 静默跳过；解冻后能写', async () => {
    const r = repo();
    r.freeze();
    await r.save(sampleSave());
    expect(await raw(KV.save)).toBeUndefined();
    r.unfreeze();
    await r.save(sampleSave());
    expect(await raw(KV.save)).toBeDefined();
  });

  test('重置后 bak / corrupt 也没了；重新绑定后的第一次存盘不把旧档滚进 bak', async () => {
    const r = repo();
    const data = new DataRepo(db, r, tick);
    const s = sampleSave();
    await r.save({ ...s, host: { ...s.host, coins: 1 } });
    await r.save({ ...s, host: { ...s.host, coins: 2 } });
    await db.kv.put({ key: KV.saveCorrupt, value: 'x' });

    const fresh = await data.wipe();
    expect(fresh).toEqual(freshSave(T0));
    expect(r.isFrozen).toBe(true);
    for (const k of [KV.save, KV.saveBak, KV.saveCorrupt]) expect(await raw(k), k).toBeUndefined();

    // 重置后自动存档被冻结：旧内存状态写不回去
    await r.save(s);
    expect(await raw(KV.save)).toBeUndefined();

    r.unfreeze();
    await r.save(fresh);
    expect(await raw(KV.saveBak)).toBeUndefined();
    expect(coinsOf(await raw(KV.save))).toBe(0);
  });
});
