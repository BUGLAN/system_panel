import { beforeEach, describe, expect, test } from 'vitest';
import { HostDb, KV } from '../../src/store/db';
import { SaveRepo } from '../../src/store/saveRepo';
import { DataRepo, PRE_IMPORT_KEY } from '../../src/store/dataRepo';
import {
  BUNDLE_VERSION,
  bundleFileName,
  checkBundle,
  checkBundleText,
} from '@host/core/save/bundle';
import { T0, sampleSave } from '@host/core/testing/fixtures';

let n = 0;
let db: HostDb;
let saves: SaveRepo;
let data: DataRepo;

beforeEach(() => {
  db = new HostDb(`data-test-${n++}`);
  saves = new SaveRepo(db, () => T0);
  data = new DataRepo(db, saves, () => T0);
});

const jpeg = (bytes: number[]) => new Blob([new Uint8Array(bytes)], { type: 'image/jpeg' });

async function seed() {
  await saves.save(sampleSave());
  await db.chat.bulkAdd([
    { at: T0, role: 'user', text: '查状态' },
    { at: T0 + 1, role: 'assistant', text: '[smug]你还活着。' },
  ]);
  await db.history.add({ at: T0, name: '出门走 3000 步', result: 'clear', exp: 1 });
  await db.memory.put({ id: 'm1', at: T0, text: '一周能跑三次' });
  await db.evidence.put({
    id: 'ev1',
    blob: jpeg([0xff, 0xd8, 1, 2, 3]),
    type: 'image/jpeg',
    takenAt: T0,
  });
  await db.kv.put({ key: KV.llm, value: { apiKey: 'sk-本机', base: 'https://x/v1' } });
  await db.kv.put({ key: KV.consent, value: { version: 1, at: T0 } });
}

describe('重置存档（E1.2 / G3.2）', () => {
  test('清存档、聊天、流水、长期记忆、证据照片；不清 LLM 设置和同意记录', async () => {
    await seed();
    await data.wipe();
    expect(await db.kv.get(KV.save)).toBeUndefined();
    expect(await db.chat.count()).toBe(0);
    expect(await db.history.count()).toBe(0);
    expect(await db.memory.count()).toBe(0);
    expect(await db.evidence.count()).toBe(0);
    expect((await db.kv.get(KV.llm))?.value).toMatchObject({ apiKey: 'sk-本机' });
    expect(await db.kv.get(KV.consent)).toBeDefined();
  });
});

describe('导出', () => {
  test('范围与重置一致，不含 LLM 设置（Key）与同意记录；照片转 Base64', async () => {
    await seed();
    const text = await data.exportText(sampleSave());
    expect(text).not.toContain('sk-本机');
    expect(text).not.toContain('consent');
    const b = JSON.parse(text);
    expect(b).toMatchObject({ app: 'host-system', kind: 'backup', version: BUNDLE_VERSION });
    expect(b.chat).toHaveLength(2);
    expect(b.history).toHaveLength(1);
    expect(b.memory).toHaveLength(1);
    expect(b.evidence[0]).toMatchObject({ id: 'ev1', type: 'image/jpeg' });
    expect(atob(b.evidence[0].data).length).toBe(5);
    expect(b.save.host.coins).toBe(26);
  });

  test('文件名带日期时间', () => {
    expect(bundleFileName(T0)).toBe('宿主养成系统-存档-20261121-1000.json');
  });
});

describe('导入', () => {
  test('往返：导出 → 重置 → 导入，数据和照片原样回来', async () => {
    await seed();
    const text = await data.exportText(sampleSave());
    await data.wipe();
    saves.unfreeze();

    const res = await data.importBundle(JSON.parse(text), null);
    expect(res.ok).toBe(true);
    expect(saves.isFrozen).toBe(true);
    const back = await new SaveRepo(db, () => T0).load();
    expect(back.host.coins).toBe(26);
    expect(back.active?.evidence.map((e) => e.id)).toEqual(['ev1', 'ev2']);
    expect(await db.chat.count()).toBe(2);
    expect(await db.memory.get('m1')).toMatchObject({ text: '一周能跑三次' });
    const ev = await db.evidence.get('ev1');
    expect(ev?.blob.type).toBe('image/jpeg');
    expect([...new Uint8Array(await ev!.blob.arrayBuffer())]).toEqual([0xff, 0xd8, 1, 2, 3]);
    // LLM 设置不受导入影响
    expect((await db.kv.get(KV.llm))?.value).toMatchObject({ apiKey: 'sk-本机' });
  });

  test('导入前先把当前数据存一份快照，再整体覆盖', async () => {
    await seed();
    const other = sampleSave();
    other.host.coins = 777;
    const bundle = JSON.parse(await data.exportText(other));
    bundle.chat = [];
    const res = await data.importBundle(bundle, sampleSave());
    expect(res.ok).toBe(true);
    const snap = await data.preImportSnapshot();
    expect(snap?.save).toMatchObject({ host: { coins: 26 } });
    expect(snap?.chat).toHaveLength(2);
    expect((await db.snapshots.get(PRE_IMPORT_KEY))?.at).toBe(T0);
    expect(await db.chat.count()).toBe(0);
    expect((await new SaveRepo(db).load()).host.coins).toBe(777);
  });

  test('不合格就拒绝并说明原因，不动现有数据', async () => {
    await seed();
    const good = JSON.parse(await data.exportText(sampleSave()));
    const cases: Array<[unknown, string]> = [
      ['hello', '不是一个存档文件'],
      [{ ...good, app: 'other' }, '不是「宿主养成系统」导出的'],
      [{ ...good, version: undefined }, '缺少版本号'],
      [{ ...good, version: BUNDLE_VERSION + 1 }, '更新版本的 App'],
      [{ ...good, save: { v: 99 } }, '主档读不出来'],
      [{ ...good, chat: 'x' }, '聊天记录不是一个列表'],
      [{ ...good, memory: [{ text: '没 id' }] }, '长期记忆里有读不懂的条目'],
      [{ ...good, evidence: [{ id: 'a', type: 'text/plain', data: 'AAAA' }] }, '第 1 张证据照片'],
      [
        { ...good, evidence: [{ id: 'a', type: 'image/jpeg', data: '不是base64' }] },
        '第 1 张证据照片',
      ],
    ];
    for (const [bad, reason] of cases) {
      const res = await data.importBundle(bad, sampleSave());
      expect(res.ok, reason).toBe(false);
      if (!res.ok) expect(res.reason).toContain(reason);
    }
    expect(saves.isFrozen).toBe(false);
    expect(await db.chat.count()).toBe(2);
    expect(await db.snapshots.count()).toBe(0);
    expect((await new SaveRepo(db).load()).host.coins).toBe(26);
  });

  test('文本层：JSON 坏也给原因', () => {
    const r = checkBundleText('{"app":', T0);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toContain('不是有效的 JSON');
  });

  test('从没绑定过的空包也能导入（save 为 null）', () => {
    const r = checkBundle(
      {
        app: 'host-system',
        kind: 'backup',
        version: 1,
        save: null,
        chat: [],
        history: [],
        memory: [],
        evidence: [],
      },
      T0,
    );
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.value.save).toBeNull();
  });
});
