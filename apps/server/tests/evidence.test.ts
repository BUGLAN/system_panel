import { describe, expect, it } from 'vitest';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import type { StateView } from '@host/core/api/types';
import type { QuestResult } from '@host/core/flow/types';
import { saveFromJson } from '@host/core/save/saveData';
import { boundSave } from '@host/core/testing/helpers';
import { dayKey } from '@host/core/time/day';
import { evidence } from '../src/db/schema';
import type { VerdictEvent } from '../src/routes/evidence';
import { completion } from './agent/fakeLlm';
import { testServer, type Client, type TestServer } from './helpers';

const LLM = {
  base: 'https://llm.test/v1',
  apiKey: 'sk-server-default-key-123456',
  textModel: 't',
  visionModel: 'v',
};
const JPEG = (n = 200) => {
  const b = new Uint8Array(n);
  b.set([0xff, 0xd8, 0xff, 0xe0]);
  return b;
};

/** 视觉端点：按脚本回判词，可延迟 */
function visionFetch(verdicts: Array<{ match: unknown; note: string }>, delayMs = 0) {
  let i = 0;
  return async () => {
    if (delayMs) await new Promise((r) => setTimeout(r, delayMs));
    const v = verdicts[Math.min(i++, verdicts.length - 1)]!;
    return new Response(completion(JSON.stringify(v)), { status: 200 });
  };
}

async function setup(fetchImpl: () => Promise<Response>, submitWaitMs = 20_000) {
  const s = testServer({ llm: LLM }, { fetch: fetchImpl, submitWaitMs });
  const c = await s.login('alice');
  await c.json('POST', '/api/consent');
  const save = boundSave();
  save.meta.lastRollDay = dayKey(s.clock.t, 'Asia/Shanghai');
  s.seed(c, save);
  const serial = save.queue[0]!.serial;
  await c.json('POST', '/api/flow/accept', { serial });
  return { s, c, serial };
}

function upload(c: Client, serial: number, bytes: Uint8Array = JPEG(), type = 'image/jpeg') {
  const fd = new FormData();
  fd.set('file', new File([Buffer.from(bytes)], 'x.jpg', { type }));
  fd.set('serial', String(serial));
  return c
    .req('POST', '/api/evidence', fd)
    .then(async (r) => ({ status: r.status, body: (await r.json()) as Record<string, unknown> }));
}

function verdicts(s: TestServer, c: Client): VerdictEvent[] {
  const out: VerdictEvent[] = [];
  s.deps.bus.subscribe(c.userId, (e) => {
    if (e.type === 'verdict') out.push(e.verdict as VerdictEvent);
  });
  return out;
}

const active = (b: Record<string, unknown>) =>
  saveFromJson((b['state'] as StateView).save, 0)!.active!;

describe('证据上传', () => {
  it('入槽（未校验）→ 后台判真 → 推 verdict，槽上换成 verified', async () => {
    const { s, c, serial } = await setup(visionFetch([{ match: true, note: '跑步截图' }]));
    const seen = verdicts(s, c);
    const r = await upload(c, serial);
    expect(r.status).toBe(200);
    expect(r.body['checking']).toBe(true);
    const id = r.body['shotId'] as string;
    expect(active(r.body).evidence[0]).toMatchObject({ id, status: 'unverified' });
    await s.deps.checks.waitFor(c.userId, [id]);
    expect(seen).toEqual([{ id, serial, result: 'kept', status: 'verified', note: '跑步截图' }]);
    expect(s.saveOf(c).active!.evidence[0]!.status).toBe('verified');
    const row = s.deps.dbh.db.select().from(evidence).get()!;
    expect(existsSync(join(s.deps.config.dataDir, 'uploads', row.file))).toBe(true);
    expect(row.file.startsWith(c.userId)).toBe(true);
  });

  it('判定不符 → 撤槽并推原因', async () => {
    const { s, c, serial } = await setup(visionFetch([{ match: false, note: '这是一朵花' }]));
    const seen = verdicts(s, c);
    const r = await upload(c, serial);
    await s.deps.checks.waitFor(c.userId, [r.body['shotId'] as string]);
    expect(seen[0]).toMatchObject({ result: 'rejected', note: '这是一朵花' });
    expect(s.saveOf(c).active!.evidence).toHaveLength(0);
  });

  it('超 2MB / 不是 JPEG（改了扩展名也不行）/ 第 4 张 → 拒', async () => {
    const { s, c, serial } = await setup(visionFetch([{ match: true, note: '' }]));
    expect((await upload(c, serial, JPEG(2 * 1024 * 1024 + 10))).status).toBe(413);
    const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]);
    expect((await upload(c, serial, png)).status).toBe(422);
    const html = new TextEncoder().encode('<html>hi</html>');
    expect((await upload(c, serial, html)).body['message']).toBe('这不是图片。她不收奇怪的东西。');
    for (let i = 0; i < 3; i++) expect((await upload(c, serial)).status).toBe(200);
    const fourth = await upload(c, serial);
    expect(fourth.status).toBe(422);
    expect(fourth.body['message']).toBe('最多 3 张。先撤一张。');
    expect(s.saveOf(c).active!.evidence).toHaveLength(3);
  });

  it('不是执行中那一单 → 409', async () => {
    const { c, serial } = await setup(visionFetch([{ match: true, note: '' }]));
    expect((await upload(c, serial + 999)).status).toBe(409);
  });

  it('没配视觉模型 → 不校验，按未校验照收', async () => {
    const s = testServer({ llm: { ...LLM, visionModel: '' } });
    const c = await s.login();
    await c.json('POST', '/api/consent');
    const save = boundSave();
    save.meta.lastRollDay = dayKey(s.clock.t, 'Asia/Shanghai');
    s.seed(c, save);
    await c.json('POST', '/api/flow/accept', { serial: save.queue[0]!.serial });
    const r = await upload(c, save.queue[0]!.serial);
    expect(r.body['checking']).toBe(false);
  });
});

describe('交单与在途校验', () => {
  it('交单最多等这么久：等不到的按未校验评级；迟到的结论不改档', async () => {
    const { s, c, serial } = await setup(visionFetch([{ match: true, note: '晚到的' }], 150), 30);
    const seen = verdicts(s, c);
    const up = await upload(c, serial);
    s.clock.t += 10 * 60_000; // 用时够 1/4，不因「太快」降档
    const sub = await c.json<{ result: QuestResult }>('POST', '/api/flow/submit', { serial });
    expect(sub.status).toBe(200);
    expect(sub.body.result.grade).toBe('B'); // 只有未校验
    await s.deps.checks.waitFor(c.userId, [up.body['shotId'] as string], 1000);
    expect(seen[0]).toMatchObject({ result: 'gone' });
    expect(s.saveOf(c).active).toBeNull();
  });

  it('校验按时回来：判真计入评级', async () => {
    const { s, c, serial } = await setup(visionFetch([{ match: true, note: '' }], 5));
    await upload(c, serial);
    s.clock.t += 10 * 60_000;
    const sub = await c.json<{ result: QuestResult }>('POST', '/api/flow/submit', { serial });
    expect(sub.body.result.grade).toBe('A');
    expect(s.saveOf(c).active).toBeNull();
  });
});

describe('读图鉴权', () => {
  it('主人能读（private 缓存），别人 404，乱写的 id 404，撤槽后照片还在', async () => {
    const { s, c, serial } = await setup(visionFetch([{ match: true, note: '' }]));
    const r = await upload(c, serial);
    const id = r.body['shotId'] as string;
    const img = await c.req('GET', `/api/evidence/${id}`);
    expect(img.status).toBe(200);
    expect(img.headers.get('content-type')).toBe('image/jpeg');
    expect(img.headers.get('cache-control')).toBe('private, max-age=86400');
    expect(new Uint8Array(await img.arrayBuffer())[0]).toBe(0xff);
    const bob = await s.login('bob');
    expect((await bob.req('GET', `/api/evidence/${id}`)).status).toBe(404);
    expect((await bob.req('DELETE', `/api/evidence/${id}`)).status).toBe(409);
    expect((await c.req('GET', '/api/evidence/..%2F..%2Fapp.db')).status).toBe(404);
    expect((await c.req('DELETE', `/api/evidence/${id}`)).status).toBe(200);
    expect(s.saveOf(c).active!.evidence).toHaveLength(0);
    expect((await c.req('GET', `/api/evidence/${id}`)).status).toBe(200);
  });
});
