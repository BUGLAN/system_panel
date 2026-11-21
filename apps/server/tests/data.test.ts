import { describe, expect, it } from 'vitest';
import { existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import type { StateView } from '@host/core/api/types';
import { saveFromJson } from '@host/core/save/saveData';
import { boundSave } from '@host/core/testing/helpers';
import { dayKey } from '@host/core/time/day';
import { llmSettings } from '../src/db/schema';
import { completion, fakeEndpoint } from './agent/fakeLlm';
import { testServer, type Client, type TestServer } from './helpers';

const LLM = {
  base: 'https://llm.test/v1',
  apiKey: 'sk-server-default-key-123456',
  textModel: 't',
  visionModel: '',
};
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);

async function richUser(s: TestServer, name = 'alice'): Promise<Client> {
  const c = await s.login(name);
  await c.json('POST', '/api/consent');
  await c.json('PUT', '/api/llm/settings', {
    useOwn: true,
    base: 'https://mine.test/v1',
    apiKey: 'sk-very-secret-own-key-9999',
    textModel: 'x',
    visionModel: '',
    temperature: 0.5,
    visionEnabled: true,
  });
  const save = boundSave();
  save.meta.lastRollDay = dayKey(s.clock.t, 'Asia/Shanghai');
  s.seed(c, save);
  const serial = save.queue[0]!.serial;
  await c.json('POST', '/api/flow/accept', { serial });
  const fd = new FormData();
  fd.set('file', new File([Buffer.from(JPEG)], 'a.jpg', { type: 'image/jpeg' }));
  fd.set('serial', String(serial));
  await c.req('POST', '/api/evidence', fd);
  await c.json('POST', '/api/flow/give-up', { serial });
  await c.json('POST', '/api/chat/status');
  return c;
}

const version = async (c: Client) =>
  (await c.json<{ state: StateView }>('GET', '/api/state')).body.state.version;

describe('导出', () => {
  it('范围：存档 + 聊天 + 流水 + 记忆 + 照片（Base64）；永远不含 Key / 同意 / 账号', async () => {
    const s = testServer({ llm: LLM });
    const c = await richUser(s);
    const res = await c.req('GET', '/api/data/export');
    expect(res.headers.get('content-disposition')).toMatch(/attachment; filename\*=UTF-8''/);
    const text = await res.text();
    const b = JSON.parse(text);
    expect(b).toMatchObject({ app: 'host-system', kind: 'backup', version: 1 });
    expect(b.save.goal.plan.length).toBeGreaterThan(0);
    expect(b.history).toHaveLength(1);
    expect(b.chat.length).toBeGreaterThanOrEqual(2);
    expect(b.evidence).toHaveLength(1);
    expect(b.evidence[0].data).toBe(Buffer.from(JPEG).toString('base64'));
    expect(text).not.toContain('sk-very-secret');
    expect(text).not.toContain('password');
    expect(text).not.toContain('consent');
  });
});

describe('重置', () => {
  it('清存档 / 聊天 / 流水 / 记忆 / 照片（磁盘也删）/ 快照；不清账号、设置、同意', async () => {
    const s = testServer({ llm: LLM });
    const c = await richUser(s);
    const v = await version(c);
    expect((await c.json('POST', '/api/data/reset', { baseVersion: v - 1 })).status).toBe(409);
    const r = await c.json<{ state: StateView }>('POST', '/api/data/reset', { baseVersion: v });
    expect(r.status).toBe(200);
    const g = saveFromJson(r.body.state.save, 0)!;
    expect(g.goal.plan).toHaveLength(0);
    expect((await c.json<{ entries: unknown[] }>('GET', '/api/history')).body.entries).toHaveLength(
      0,
    );
    expect((await c.json<{ messages: unknown[] }>('GET', '/api/chat')).body.messages).toHaveLength(
      0,
    );
    expect(existsSync(join(s.deps.config.dataDir, 'uploads', c.userId))).toBe(false);
    expect(s.deps.dbh.db.select().from(llmSettings).all()).toHaveLength(1);
    expect(
      (await c.json<{ me: { consent: unknown } }>('GET', '/api/me')).body.me.consent,
    ).not.toBeNull();
  });
});

describe('导入', () => {
  it('坏包 / 不是存档 / 版本太新 → 400 原因，现有数据不动', async () => {
    const s = testServer({ llm: LLM });
    const c = await richUser(s);
    const v = await version(c);
    const bad = await c.json<{ message: string }>('POST', '/api/data/import', {
      baseVersion: v,
      bundle: { hello: 1 },
    });
    expect(bad.status).toBe(400);
    expect(bad.body.message).toBe('这不是「宿主养成系统」导出的存档文件。');
    const newer = await c.json<{ message: string }>('POST', '/api/data/import', {
      baseVersion: v,
      bundle: { app: 'host-system', kind: 'backup', version: 99 },
    });
    expect(newer.body.message).toMatch(/更新版本/);
    const exp = JSON.parse(await (await c.req('GET', '/api/data/export')).text());
    exp.evidence[0].data = Buffer.from('not an image').toString('base64');
    const photo = await c.json<{ message: string }>('POST', '/api/data/import', {
      baseVersion: v,
      bundle: exp,
    });
    expect(photo.body.message).toMatch(/第 1 张证据照片读不出来/);
    expect(await version(c)).toBe(v);
    expect((await c.json<{ entries: unknown[] }>('GET', '/api/history')).body.entries).toHaveLength(
      1,
    );
  });

  it('导出 → 重置 → 导入：等级 / 主线 / 聊天 / 流水 / 照片都回来；导入前先存快照', async () => {
    const s = testServer({ llm: LLM });
    const c = await richUser(s);
    const text = await (await c.req('GET', '/api/data/export')).text();
    const before = s.saveOf(c);
    await c.json('POST', '/api/data/reset', { baseVersion: await version(c) });
    const r = await c.json<{ state: StateView }>('POST', '/api/data/import', {
      baseVersion: await version(c),
      bundle: JSON.parse(text),
    });
    expect(r.status).toBe(200);
    const after = s.saveOf(c);
    expect(after.goal.text).toBe(before.goal.text);
    expect(after.host.failCount).toBe(before.host.failCount);
    expect((await c.json<{ entries: unknown[] }>('GET', '/api/history')).body.entries).toHaveLength(
      1,
    );
    const exp = JSON.parse(text);
    const img = await c.req('GET', `/api/evidence/${exp.evidence[0].id}`);
    expect(img.status).toBe(200);
    expect(readdirSync(join(s.deps.config.dataDir, 'snapshots', c.userId))).toEqual([
      'pre-import.json',
    ]);
  });

  it('朋友的导出包可以导进自己的账号（照片编号按用户分开，不撞）', async () => {
    const s = testServer({ llm: LLM });
    const a = await richUser(s, 'alice');
    const text = await (await a.req('GET', '/api/data/export')).text();
    const b = await s.login('bob');
    const r = await b.json('POST', '/api/data/import', {
      baseVersion: await version(b),
      bundle: JSON.parse(text),
    });
    expect(r.status).toBe(200);
    const id = JSON.parse(text).evidence[0].id;
    expect((await b.req('GET', `/api/evidence/${id}`)).status).toBe(200);
    expect((await a.req('GET', `/api/evidence/${id}`)).status).toBe(200);
  });
});

describe('聊天', () => {
  it('自伤闸门：认真回应、不调模型；查状态不调模型', async () => {
    const ep = fakeEndpoint([{ text: '[annoyed]少废话。' }]);
    const s = testServer({ llm: LLM }, { fetch: ep.fetch });
    const c = await s.login();
    await c.json('POST', '/api/consent');
    const r = await c.json<{ messages: Array<{ kind?: string; from: string }> }>(
      'POST',
      '/api/chat',
      { text: '不想活了', scene: '大厅' },
    );
    expect(r.body.messages.at(-1)).toMatchObject({ from: 'sys', kind: 'care' });
    await c.json('POST', '/api/chat/status');
    expect(ep.calls).toHaveLength(0);
    const ok = await c.json<{ messages: Array<{ text: string }> }>('POST', '/api/chat', {
      text: '今天干嘛',
      scene: '大厅',
    });
    expect(ok.body.messages.at(-1)!.text).toBe('少废话。');
    expect(ep.calls).toHaveLength(1);
    const all = await c.json<{ messages: unknown[] }>('GET', '/api/chat');
    expect(all.body.messages).toHaveLength(6);
    expect((await c.json('POST', '/api/chat', { text: '字'.repeat(201) })).status).toBe(400);
  });

  it('工具改存档（换一个）在服务端执行并回最新状态', async () => {
    const ep = fakeEndpoint([
      { text: '', tools: [{ name: 'swap_quest', args: {} }] },
      { text: '[annoyed]换了。' },
    ]);
    const s = testServer({ llm: LLM }, { fetch: ep.fetch });
    const c = await s.login();
    await c.json('POST', '/api/consent');
    const save = boundSave();
    save.meta.lastRollDay = dayKey(s.clock.t, 'Asia/Shanghai');
    s.seed(c, save);
    await c.json('POST', '/api/flow/refill');
    const g = s.saveOf(c);
    g.queue = g.queue.filter((q) => q.kind === 'daily'); // 队首是日常才能换
    s.seed(c, g);
    const r = await c.json<{ state?: StateView; messages: Array<{ tool?: { name: string } }> }>(
      'POST',
      '/api/chat',
      { text: '换个任务', scene: '委托板' },
    );
    expect(r.body.messages.some((m) => m.tool?.name === 'swap_quest')).toBe(true);
    expect(r.body.state).toBeDefined();
    expect(s.saveOf(c).meta.retreatTotal).toBe(1);
    expect(completion('x')).toContain('choices');
  });
});
