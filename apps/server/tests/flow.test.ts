import { describe, expect, it } from 'vitest';
import { eq } from 'drizzle-orm';
import type { QuestResult } from '@host/core/flow/types';
import { saveFromJson, type SaveData } from '@host/core/save/saveData';
import type { StateView } from '@host/core/api/types';
import { QuestFlow } from '@host/core/flow/questFlow';
import { boundSave } from '@host/core/testing/helpers';
import { dayKey } from '@host/core/time/day';
import { history, saveCorrupt, saves } from '../src/db/schema';
import { T0, testServer, type Client, type TestServer } from './helpers';

const TZ = 'Asia/Shanghai';

/** 已绑定、今天已换过日的档（免得第一下请求就换日） */
function bound(): SaveData {
  const s = boundSave();
  s.meta.lastRollDay = dayKey(T0, TZ);
  return s;
}

type Body = {
  ok: boolean;
  code?: string;
  message?: string;
  state: StateView;
  events: { kind: string }[];
};

const saveOfView = (v: StateView) => saveFromJson(v.save, v.serverNow)!;

async function setup(): Promise<{ s: TestServer; c: Client; save: SaveData }> {
  const s = testServer();
  const c = await s.login('alice', TZ);
  const save = bound();
  s.seed(c, save);
  return { s, c, save };
}

/** 接下队首，塞一张已判真的证据 */
async function acceptWithEvidence(s: TestServer, c: Client): Promise<number> {
  const head = s.saveOf(c).queue[0]!;
  const r = await c.json<Body>('POST', '/api/flow/accept', { serial: head.serial });
  expect(r.status).toBe(200);
  const g = s.saveOf(c);
  g.active!.evidence.push({ id: 'ev1', status: 'verified', note: '', takenAt: s.clock.t });
  s.seed(c, g);
  return head.serial;
}

describe('读状态', () => {
  it('全新账号：空白档；第一下请求就换日（与旧版开机 rollDay 一致）', async () => {
    const s = testServer();
    const c = await s.login();
    const r = await c.json<Body & { prevSeen: number | null }>('GET', '/api/state?boot=1');
    expect(r.status).toBe(200);
    expect(r.body.state.version).toBe(1);
    expect(r.body.state.source).toBe('none');
    expect(r.body.events).toEqual([{ kind: 'rollDay' }]);
    expect(r.body.state.tz).toBe(TZ);
    expect(r.body.state.serverNow).toBe(T0);
    expect(r.body.prevSeen).toBeNull();
    expect(saveOfView(r.body.state).goal.plan).toHaveLength(0);
    expect(s.deps.dbh.db.select().from(saves).all()).toHaveLength(1);
  });

  it('boot 时给出「上次来过」的时刻', async () => {
    const { s, c } = await setup();
    await c.json('GET', '/api/state');
    s.clock.t += 3 * 3_600_000;
    const r = await c.json<{ prevSeen: number }>('GET', '/api/state?boot=1');
    expect(r.body.prevSeen).toBe(T0);
  });
});

describe('接单 → 交单 → 结算落库', () => {
  it('接单记服务器时间；交单结算入账、记一条流水、版本号递增', async () => {
    const { s, c } = await setup();
    const v0 = (await c.json<Body>('GET', '/api/state')).body.state.version;
    const serial = await acceptWithEvidence(s, c);
    expect(s.saveOf(c).active!.startAt).toBe(T0);
    s.clock.t += 15 * 60_000;
    const r = await c.json<Body & { result: QuestResult; followUp: null }>(
      'POST',
      '/api/flow/submit',
      { serial },
    );
    expect(r.status).toBe(200);
    expect(r.body.result.exp).toBe(1); // E 级 EXP 1
    expect(r.body.result.streak).toBe(1);
    expect(r.body.result.heldMs).toBe(15 * 60_000);
    expect(r.body.followUp).toBeNull();
    const g = saveOfView(r.body.state);
    expect(g.active).toBeNull();
    expect(g.host.exp).toBe(1);
    expect(g.queue.map((q) => q.planIndex)).toEqual([1]);
    expect(g.meta.lastDoneDay).toBe(dayKey(s.clock.t, TZ));
    expect(r.body.state.version).toBeGreaterThan(v0);
    const h = await c.json<{ entries: { result: string }[] }>('GET', '/api/history');
    expect(h.body.entries.map((e) => e.result)).toEqual(['clear']);
    // 再交一次：已经交过了
    const again = await c.json<Body>('POST', '/api/flow/submit', { serial });
    expect(again.status).toBe(409);
    expect(again.body.message).toBe('这一单已经交过了。');
  });

  it('没证据不收（422），存档不动', async () => {
    const { s, c } = await setup();
    const head = s.saveOf(c).queue[0]!;
    await c.json('POST', '/api/flow/accept', { serial: head.serial });
    const v = (await c.json<Body>('GET', '/api/state')).body.state.version;
    const r = await c.json<Body>('POST', '/api/flow/submit', { serial: head.serial });
    expect(r.status).toBe(422);
    expect(r.body.message).toBe('没有证据，她不收。先上传截图。');
    expect(r.body.state.version).toBe(v);
    expect(s.saveOf(c).active).not.toBeNull();
  });

  it('执行中再接别的单 → 409 并附最新状态；主线没解封 → 422 带原因', async () => {
    const { s, c, save } = await setup();
    const f = new QuestFlow(save);
    f.queue.push(f.planTask(1));
    s.seed(c, f.save);
    const q = s.saveOf(c).queue;
    const locked = await c.json<Body>('POST', '/api/flow/accept', { serial: q[1]!.serial });
    expect(locked.status).toBe(422);
    expect(locked.body.message).toBe('主线第 02 单还没解封：先做第 01 单。');
    await c.json('POST', '/api/flow/accept', { serial: q[0]!.serial });
    const busy = await c.json<Body>('POST', '/api/flow/accept', { serial: q[1]!.serial });
    expect(busy.status).toBe(409);
    expect(busy.body.code).toBe('stale');
    expect(saveOfView(busy.body.state).active?.task.serial).toBe(q[0]!.serial);
  });
});

describe('不计时、换日', () => {
  it('接单后隔很久再交也照收（没有倒计时、没有超时判负）', async () => {
    const { s, c } = await setup();
    const serial = await acceptWithEvidence(s, c);
    s.clock.t += 5 * 3_600_000;
    const st = await c.json<Body>('GET', '/api/state');
    expect(st.body.events).toEqual([]);
    expect(saveOfView(st.body.state).active?.task.serial).toBe(serial);
    const r = await c.json<Body>('POST', '/api/flow/submit', { serial });
    expect(r.status).toBe(200);
  });

  it('跨过账号时区的 0 点：换日、断签当场归零、手上的主线单不动', async () => {
    const { s, c, save } = await setup();
    save.host.streak = 5;
    save.meta.lastDoneDay = dayKey(T0 - 86_400_000, TZ);
    s.seed(c, save);
    s.clock.t += 2 * 86_400_000;
    const r = await c.json<Body>('GET', '/api/state');
    expect(r.body.events).toEqual([{ kind: 'rollDay' }]);
    const g = saveOfView(r.body.state);
    expect(g.host.streak).toBe(0);
    expect(g.queue.map((q) => q.serial)).toEqual(save.queue.map((q) => q.serial));
  });
});

describe('先跳过 / 已下线的接口', () => {
  it('先跳过：只记住目标，不发单', async () => {
    const s = testServer();
    const c = await s.login();
    const r = await c.json<Body>('POST', '/api/flow/skip-plan', { text: '  三个月学会弹吉他 ' });
    const g = saveOfView(r.body.state);
    expect(g.pendingGoal).toBe('三个月学会弹吉他');
    expect(g.queue).toEqual([]);
  });

  it('道具 / 认输 / 补救 / 补给 / 补签 / 称号 / 计时 / 聊天的接口都已下线', async () => {
    const { c } = await setup();
    for (const p of [
      '/api/flow/equip',
      '/api/flow/give-up',
      '/api/flow/take-remedy',
      '/api/flow/refill',
      '/api/flow/buy',
      '/api/flow/patch',
      '/api/flow/wear',
      '/api/flow/tick',
      '/api/chat',
    ])
      expect((await c.req('POST', p, {})).status, p).toBe(404);
  });
});

describe('并发与去重', () => {
  it('两台设备同时接同一单：一个成功，一个 409', async () => {
    const { s, c, save } = await setup();
    const other = s.client();
    other.cookie = c.cookie;
    const serial = save.queue[0]!.serial;
    const [a, b] = await Promise.all([
      c.json('POST', '/api/flow/accept', { serial }),
      other.json('POST', '/api/flow/accept', { serial }),
    ]);
    expect([a.status, b.status].sort()).toEqual([200, 409]);
  });

  it('同一个 intentId 重放：只执行一次，回同一份响应', async () => {
    const { c, save } = await setup();
    const serial = save.queue[0]!.serial;
    const send = (id: string) =>
      c
        .req('POST', '/api/flow/accept', { serial }, { 'x-intent-id': id })
        .then(async (r) => ({ status: r.status, body: (await r.json()) as unknown }));
    const [r1, r2] = await Promise.all([send('acc-1'), send('acc-1')]);
    expect(r1).toEqual(r2);
    expect(r1.status).toBe(200);
    expect((await send('acc-2')).status).toBe(409);
  });
});

describe('坏档保护', () => {
  it('主档坏 → 留底 + 用备份恢复，告诉前端 source=backup', async () => {
    const { s, c } = await setup();
    await c.json('POST', '/api/flow/accept', { serial: s.saveOf(c).queue[0]!.serial }); // 再写一次，bak 里有好档
    s.deps.dbh.db.update(saves).set({ data: '{坏掉了' }).run();
    const r = await c.json<Body>('GET', '/api/state');
    expect(r.status).toBe(200);
    expect(r.body.state.source).toBe('backup');
    expect(saveOfView(r.body.state).goal.plan.length).toBeGreaterThan(0);
    expect(s.deps.dbh.db.select().from(saveCorrupt).all()[0]!.raw).toBe('{坏掉了');
    expect((await c.json<Body>('GET', '/api/state')).body.state.source).toBe('primary');
  });

  it('主档和备份都坏 → 500 save_corrupt，数据不清零', async () => {
    const { s, c } = await setup();
    s.deps.dbh.db.update(saves).set({ data: 'x', bak: 'y' }).run();
    const r = await c.json<Body>('GET', '/api/state');
    expect(r.status).toBe(500);
    expect(r.body.code).toBe('save_corrupt');
    expect(s.deps.dbh.db.select().from(saves).get()!.bak).toBe('y');
  });
});

describe('用户隔离', () => {
  it('B 的请求碰不到 A 的存档与流水', async () => {
    const { s, c: alice } = await setup();
    const serial = await acceptWithEvidence(s, alice);
    await alice.json('POST', '/api/flow/submit', { serial });
    const bob = await s.login('bob');
    const st = await bob.json<Body>('GET', '/api/state');
    expect(saveOfView(st.body.state).goal.plan).toHaveLength(0);
    expect(
      (await bob.json<{ entries: unknown[] }>('GET', '/api/history')).body.entries,
    ).toHaveLength(0);
    const take = await bob.json<Body>('POST', '/api/flow/submit', { serial });
    expect(take.status).toBe(409);
    const aliceRows = s.deps.dbh.db
      .select()
      .from(history)
      .where(eq(history.userId, alice.userId))
      .all();
    expect(aliceRows).toHaveLength(1);
  });
});
