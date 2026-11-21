import { beforeEach, describe, expect, test } from 'vitest';
import { createAutosave } from '../../src/store/autosave';
import { createGameStore } from '../../src/store/gameStore';
import { createPersistence } from '../../src/store/persistence';
import { HostDb } from '../../src/store/db';
import { SaveRepo } from '../../src/store/saveRepo';
import { T0, sampleSave } from '../fixtures';

const tickMicro = () => new Promise<void>((r) => setTimeout(r, 0));

describe('自动存档：同一拍合并、串行写入', () => {
  test('同一拍里的多次请求只写一次，写的是最新状态', async () => {
    let value = 0;
    const writes: number[] = [];
    const a = createAutosave({ read: () => value, write: async (v) => void writes.push(v) });
    a.arm();
    value = 1;
    a.request();
    value = 2;
    a.request();
    value = 3;
    a.request();
    await a.flush();
    expect(writes).toEqual([3]);
  });

  test('读档前（未 arm）的请求一律忽略', async () => {
    const writes: number[] = [];
    const a = createAutosave({ read: () => 1, write: async (v) => void writes.push(v) });
    a.request();
    await a.flush();
    expect(writes).toEqual([]);
  });

  test('写入期间的新改动排在后面，只再写一次；写入从不并发', async () => {
    let value = 0;
    let inFlight = 0;
    let maxInFlight = 0;
    const writes: number[] = [];
    let release: (() => void) | null = null;
    const a = createAutosave({
      read: () => value,
      write: (v) =>
        new Promise<void>((res) => {
          inFlight++;
          maxInFlight = Math.max(maxInFlight, inFlight);
          release = () => {
            inFlight--;
            writes.push(v);
            res();
          };
        }),
    });
    a.arm();
    value = 1;
    a.request();
    await tickMicro();
    // 第一笔还在写：连续改三次、分三拍请求
    for (const v of [2, 3, 4]) {
      value = v;
      a.request();
      await tickMicro();
    }
    (release as unknown as () => void)();
    await tickMicro();
    (release as unknown as () => void)();
    await a.flush();
    expect(writes).toEqual([1, 4]);
    expect(maxInFlight).toBe(1);
  });

  test('写盘失败不打断后续写入', async () => {
    const writes: number[] = [];
    const errors: unknown[] = [];
    let fail = true;
    let value = 0;
    const a = createAutosave({
      read: () => value,
      write: async (v) => {
        if (fail) throw new Error('磁盘满');
        writes.push(v);
      },
      onError: (e) => errors.push(e),
    });
    a.arm();
    value = 1;
    a.request();
    await a.flush();
    fail = false;
    value = 2;
    a.request();
    await a.flush();
    expect(errors).toHaveLength(1);
    expect(writes).toEqual([2]);
  });

  test('disarm 之后不再写（重置 / 导入）', async () => {
    const writes: number[] = [];
    const a = createAutosave({ read: () => 1, write: async (v) => void writes.push(v) });
    a.arm();
    a.disarm();
    a.request();
    await a.flush();
    expect(writes).toEqual([]);
  });
});

describe('存档状态接到磁盘', () => {
  let n = 0;
  let db: HostDb;
  beforeEach(() => {
    db = new HostDb(`persist-test-${n++}`);
  });

  function fakeDoc() {
    const listeners: Array<() => void> = [];
    return {
      visibilityState: 'visible' as DocumentVisibilityState,
      addEventListener: (_: string, fn: () => void) => void listeners.push(fn),
      removeEventListener: () => {},
      fire() {
        listeners.forEach((f) => f());
      },
    };
  }

  test('读档完成前不写盘；之后 game 一变就存', async () => {
    const repo = new SaveRepo(db, () => T0);
    await repo.save(sampleSave());
    const store = createGameStore(T0);
    const p = createPersistence(store, repo, null);

    const source = await p.boot();
    expect(source).toBe('primary');
    expect(store.getState().game.host.coins).toBe(26);

    store.getState().setGame((g) => ({ ...g, host: { ...g.host, coins: 30 } }));
    await p.flush();
    expect((await new SaveRepo(db).load()).host.coins).toBe(30);
    p.stop();
  });

  test('引用没变（没改存档字段）就不写', async () => {
    const repo = new SaveRepo(db, () => T0);
    let saves = 0;
    const orig = repo.save.bind(repo);
    repo.save = async (d) => {
      saves++;
      return orig(d);
    };
    const store = createGameStore(T0);
    const p = createPersistence(store, repo, null);
    await p.boot();
    store.getState().setGame((g) => g);
    await p.flush();
    expect(saves).toBe(0);
    p.stop();
  });

  test('切后台时立刻补一次（盖上 lastSeen）', async () => {
    let clock = T0;
    const repo = new SaveRepo(db, () => clock);
    const store = createGameStore(T0);
    const doc = fakeDoc();
    const p = createPersistence(store, repo, doc);
    await p.boot();
    clock = T0 + 60_000;
    doc.visibilityState = 'hidden';
    doc.fire();
    await p.flush();
    expect((await new SaveRepo(db).load()).lastSeen).toBe(T0 + 60_000);
    p.stop();
  });
});
