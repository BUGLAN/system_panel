import { describe, expect, it } from 'vitest';
import type { PlanJobView, StateView } from '@host/core/api/types';
import { saveFromJson } from '@host/core/save/saveData';
import { users, llmSettings } from '../src/db/schema';
import {
  autoPlan,
  fakeEndpoint,
  matchReply,
  type FakeEndpoint,
  type Scripted,
} from './agent/fakeLlm';
import { testServer, type Client, type TestServer } from './helpers';

const LLM = {
  base: 'https://llm.test/v1',
  apiKey: 'sk-server-default-key-123456',
  textModel: 'm-text',
  visionModel: '',
};
const OWN = {
  useOwn: true,
  base: 'https://mine.test/v1',
  apiKey: 'sk-my-own-secret-abcd',
  textModel: 'my-model',
  visionModel: 'my-vision',
  temperature: 0.5,
  visionEnabled: true,
};

/** 一个按请求内容回话的假端点：匹配请求 → set_goal_category；拆解请求 → 合规 set_plan */
function smartEndpoint(): FakeEndpoint {
  const script: Scripted = (body) => {
    const tools = (body['tools'] as Array<{ function: { name: string } }> | undefined) ?? [];
    if (tools.some((t) => t.function.name === 'set_goal_category')) {
      const m = matchReply('run', 30);
      return typeof m === 'function' ? m(body) : m;
    }
    return typeof autoPlan === 'function' ? autoPlan(body) : autoPlan;
  };
  return fakeEndpoint([script]);
}

async function setup(
  ep: FakeEndpoint,
  opts: { consent?: boolean; quota?: Partial<TestServer['deps']['config']['quotas']> } = {},
) {
  const s = testServer(
    { llm: LLM, quotas: { ratePerMin: 100, dailyText: 150, dailyVision: 60, ...opts.quota } },
    { fetch: ep.fetch },
  );
  const c = await s.login('alice');
  if (opts.consent !== false) await c.json('POST', '/api/consent');
  return { s, c };
}

async function waitJob(s: TestServer, c: Client, id: string): Promise<PlanJobView> {
  await s.deps.jobs.done.get(id);
  return (await c.json<{ job: PlanJobView }>('GET', `/api/plan/jobs/${id}`)).body.job;
}

describe('模型设置与 Key', () => {
  it('Key 加密存库、接口永远不回明文；留空 = 不改，空串 = 清掉', async () => {
    const { s, c } = await setup(fakeEndpoint([{ text: 'pong' }]));
    const put = await c.json<{ settings: Record<string, unknown> }>(
      'PUT',
      '/api/llm/settings',
      OWN,
    );
    expect(put.status).toBe(200);
    expect(JSON.stringify(put.body)).not.toContain(OWN.apiKey);
    expect(put.body.settings).toMatchObject({ hasOwnKey: true, keyHint: '…abcd', useOwn: true });
    const row = s.deps.dbh.db.select().from(llmSettings).get()!;
    expect(row.keyEnc).not.toContain('abcd');
    expect(row.keyEnc.startsWith('v1.')).toBe(true);
    const { apiKey: _k, ...noKey } = OWN;
    await c.json('PUT', '/api/llm/settings', { ...noKey, textModel: 'm2' });
    const get = await c.json<{ settings: Record<string, unknown> }>('GET', '/api/llm/settings');
    expect(get.body.settings).toMatchObject({ hasOwnKey: true, textModel: 'm2' });
    expect(JSON.stringify(get.body)).not.toContain(OWN.apiKey);
    await c.json('PUT', '/api/llm/settings', { ...OWN, apiKey: '' });
    expect(
      (await c.json<{ settings: { hasOwnKey: boolean } }>('GET', '/api/llm/settings')).body.settings
        .hasOwnKey,
    ).toBe(false);
  });

  it('用自己的：整套走自己的端点 / Key / 模型；用默认：走服务器配的', async () => {
    const ep = fakeEndpoint([{ text: 'pong' }]);
    const urls: string[] = [];
    const auth: string[] = [];
    const spy: FakeEndpoint['fetch'] = (u, init) => {
      urls.push(u);
      auth.push(String((init?.headers as Record<string, string>)['Authorization']));
      return ep.fetch(u, init);
    };
    const s = testServer({ llm: LLM }, { fetch: spy });
    const c = await s.login();
    await c.json('POST', '/api/consent');
    const def = await c.json<{ mode: string; text: { ok: boolean; line: string } }>(
      'POST',
      '/api/llm/test',
    );
    expect(def.body.mode).toBe('server');
    expect(def.body.text.line).toMatch(/^连上了 · /);
    expect(urls[0]).toBe('https://llm.test/v1/chat/completions');
    await c.json('PUT', '/api/llm/settings', OWN);
    const own = await c.json<{ mode: string }>('POST', '/api/llm/test');
    expect(own.body.mode).toBe('own');
    expect(urls.slice(1)).toContain('https://mine.test/v1/chat/completions');
    expect(auth).toContain(`Bearer ${OWN.apiKey}`);
    expect(ep.calls.some((b) => b['model'] === 'my-vision')).toBe(true);
  });

  it('测试连接的失败分类：没配 / 401 / 没同意（零请求）', async () => {
    const none = testServer();
    const c0 = await none.login();
    await c0.json('POST', '/api/consent');
    const r0 = await c0.json<{ text: { line: string } }>('POST', '/api/llm/test');
    expect(r0.body.text.line).toMatch(/^没配好：/);

    const ep = fakeEndpoint([{ status: 401, text: 'bad key' }]);
    const { c } = await setup(ep);
    const r = await c.json<{ text: { ok: boolean; line: string } }>('POST', '/api/llm/test');
    expect(r.body.text).toMatchObject({ ok: false });
    expect(r.body.text.line).toMatch(/^服务商报错 HTTP 401/);

    const ep2 = fakeEndpoint([{ text: 'never' }]);
    const { c: c2 } = await setup(ep2, { consent: false });
    const r2 = await c2.json<{ text: { line: string } }>('POST', '/api/llm/test');
    expect(r2.body.text.line).toBe('还没同意首启告知页，请求不会发出。');
    expect(ep2.calls).toHaveLength(0);
  });

  it('同意 / 撤回跟账号走', async () => {
    const { c } = await setup(fakeEndpoint([{ text: 'x' }]), { consent: false });
    const g = await c.json<{ me: { consent: { version: number } } }>('POST', '/api/consent');
    expect(g.body.me.consent.version).toBe(2);
    const w = await c.json<{ me: { consent: unknown } }>('DELETE', '/api/consent');
    expect(w.body.me.consent).toBeNull();
  });
});

describe('额度与限速', () => {
  it('服务器默认 Key：每日上限到了 → quota，零请求；管理员不限', async () => {
    const ep = fakeEndpoint([{ text: 'pong' }]);
    const { s, c } = await setup(ep, { quota: { dailyText: 2 } });
    await c.json('POST', '/api/llm/test');
    await c.json('POST', '/api/llm/test');
    const r = await c.json<{ text: { line: string } }>('POST', '/api/llm/test');
    expect(r.body.text.line).toMatch(/^额度：今天的文本额度（2 次）用完了/);
    expect(ep.calls).toHaveLength(2);
    const u = await c.json<{ used: { text: number }; limits: { text: number } }>(
      'GET',
      '/api/llm/usage',
    );
    expect(u.body).toMatchObject({ used: { text: 2 }, limits: { text: 2 } });
    s.deps.dbh.db.update(users).set({ role: 'admin' }).run();
    expect((await c.json<{ text: { ok: boolean } }>('POST', '/api/llm/test')).body.text.ok).toBe(
      true,
    );
  });

  it('自己的 Key 不受每日上限，但照样限速', async () => {
    const ep = fakeEndpoint([{ text: 'pong' }]);
    const { s, c } = await setup(ep, { quota: { dailyText: 1, ratePerMin: 3 } });
    await c.json('PUT', '/api/llm/settings', { ...OWN, visionModel: '' });
    for (let i = 0; i < 3; i++)
      expect((await c.json<{ text: { ok: boolean } }>('POST', '/api/llm/test')).body.text.ok).toBe(
        true,
      );
    const r = await c.json<{ text: { line: string } }>('POST', '/api/llm/test');
    expect(r.body.text.line).toMatch(/^额度：太快了，\d+ 秒后再试。/);
    s.clock.t += 61_000;
    expect((await c.json<{ text: { ok: boolean } }>('POST', '/api/llm/test')).body.text.ok).toBe(
      true,
    );
  });

  it('拆解碰上额度用完 → 失败卡 quota', async () => {
    const ep = smartEndpoint();
    const { s, c } = await setup(ep, { quota: { dailyText: 0 } });
    const r = await c.json<{ job: PlanJobView }>('POST', '/api/plan/jobs', {
      kind: 'bind',
      text: '三个月跑完半马',
    });
    const job = await waitJob(s, c, r.body.job.id);
    expect(job.status).toBe('failed');
    expect(job.failure?.code).toBe('quota');
  });
});

describe('匹配与拆解任务', () => {
  it('绑定：匹配出访谈卡 → 起任务 → 进度 → 落库（主线 + 日常 + 见面礼 + 访谈记忆）', async () => {
    const ep = smartEndpoint();
    const { s, c } = await setup(ep);
    const m = await c.json<{ match: { catId: string }; cards: Array<{ id: string }> }>(
      'POST',
      '/api/plan/match',
      { text: '三个月跑完半马' },
    );
    expect(m.status).toBe(200);
    expect(m.body.match.catId).toBe('run');
    expect(m.body.cards).toHaveLength(3);
    const answers = Object.fromEntries(m.body.cards.map((k) => [k.id, '一周三次']));
    const seen: string[] = [];
    s.deps.bus.subscribe(c.userId, (e) => {
      if (e.type === 'job')
        seen.push((e.job as PlanJobView).status + ':' + (e.job as PlanJobView).progress.stage);
    });
    const callsBefore = ep.calls.length;
    const r = await c.json<{ job: PlanJobView }>('POST', '/api/plan/jobs', {
      kind: 'bind',
      text: '三个月跑完半马',
      answers,
    });
    // 第二次点（连点）：拿到同一件
    const again = await c.json<{ job: PlanJobView }>('POST', '/api/plan/jobs', {
      kind: 'bind',
      text: '三个月跑完半马',
      answers,
    });
    expect(again.body.job.id).toBe(r.body.job.id);
    const job = await waitJob(s, c, r.body.job.id);
    expect(job.status).toBe('done');
    // 匹配过的不再匹配一次
    expect(
      ep.calls.slice(callsBefore).some((b) => JSON.stringify(b).includes('set_goal_category')),
    ).toBe(false);
    expect(seen[0]).toBe('running:0');
    expect(seen).toContain('running:2');
    expect(seen.at(-1)).toMatch(/^done/);
    const g = saveFromJson((job.state as StateView).save, 0)!;
    expect(g.goal.plan.length).toBeGreaterThan(0);
    expect(g.queue.some((q) => q.kind === 'main')).toBe(true);
    expect(g.queue.some((q) => q.kind === 'daily')).toBe(true);
    expect(g.host.items['dbl']).toBe(1);
    const mem = s.deps.dbh.db
      .select()
      .from((await import('../src/db/schema')).memory)
      .all();
    expect(mem.some((x) => x.text.includes('一周三次'))).toBe(true);
  });

  it('拆解失败停在失败态（错误分类），答案不动、可重试', async () => {
    const ep = fakeEndpoint([{ throw: 'network' }, { throw: 'network' }]);
    const { s, c } = await setup(ep);
    const r = await c.json<{ job: PlanJobView }>('POST', '/api/plan/jobs', {
      kind: 'bind',
      text: '三个月跑完半马',
    });
    const job = await waitJob(s, c, r.body.job.id);
    expect(job).toMatchObject({ status: 'failed', failure: { code: 'network' } });
    expect(s.saveOf(c).goal.plan).toHaveLength(0);
    const cur = await c.json<{ job: PlanJobView }>('GET', '/api/plan/jobs/current');
    expect(cur.body.job.id).toBe(job.id);
  });

  it('自伤闸门与「太空了」在服务端兜底：不调 LLM', async () => {
    const ep = smartEndpoint();
    const { c } = await setup(ep);
    const crisis = await c.json<{ code: string; message: string }>('POST', '/api/plan/match', {
      text: '不想活了',
    });
    expect(crisis.status).toBe(422);
    expect(crisis.body.code).toBe('crisis');
    expect(crisis.body.message).not.toMatch(/\d{3,}/); // 不写热线号码
    expect((await c.json('POST', '/api/plan/jobs', { kind: 'swap', text: '变优秀' })).status).toBe(
      422,
    );
    expect((await c.json('POST', '/api/plan/match', { text: '一'.repeat(51) })).status).toBe(400);
    expect(ep.calls).toHaveLength(0);
  });

  it('先跳过后重试：用记着的那句拆，成功补发见面礼', async () => {
    const ep = smartEndpoint();
    const { s, c } = await setup(ep);
    await c.json('POST', '/api/flow/skip-plan', { text: '三个月跑完半马' });
    const r = await c.json<{ job: PlanJobView }>('POST', '/api/plan/jobs', { kind: 'retry' });
    const job = await waitJob(s, c, r.body.job.id);
    expect(job.status).toBe('done');
    const g = s.saveOf(c);
    expect(g.pendingGoal).toBe('');
    expect(g.host.items['dbl']).toBe(1);
    expect(g.queue.filter((q) => q.kind === 'daily')).toHaveLength(1); // 跳过时发过日常，不再叠发
  });

  it('换目标：旧主线全撤、日常保留；等待期间目标变了 → 结果作废', async () => {
    const ep = smartEndpoint();
    const { s, c } = await setup(ep);
    await c.json('POST', '/api/plan/match', { text: '三个月跑完半马' });
    const first = await c.json<{ job: PlanJobView }>('POST', '/api/plan/jobs', {
      kind: 'bind',
      text: '三个月跑完半马',
    });
    await waitJob(s, c, first.body.job.id);
    const before = s.saveOf(c);
    const r = await c.json<{ job: PlanJobView }>('POST', '/api/plan/jobs', {
      kind: 'swap',
      text: '两个月学会游泳',
    });
    const job = await waitJob(s, c, r.body.job.id);
    expect(job.status).toBe('done');
    const after = s.saveOf(c);
    expect(after.goal.text).toBe('两个月学会游泳');
    expect(after.queue.filter((q) => q.kind === 'daily').length).toBe(
      before.queue.filter((q) => q.kind === 'daily').length,
    );
    // 并发换线：第一件还在拆时改了目标
    const slow = testServer(
      { llm: LLM },
      {
        fetch: async (u, init) => {
          await new Promise((res) => setTimeout(res, 5));
          return smartEndpoint().fetch(u, init);
        },
      },
    );
    const sc = await slow.login();
    await sc.json('POST', '/api/consent');
    slow.seed(sc, after);
    const j = await sc.json<{ job: PlanJobView }>('POST', '/api/plan/jobs', {
      kind: 'swap',
      text: '一个月读完三本书',
    });
    const changed = slow.saveOf(sc);
    changed.goal.at += 1;
    slow.seed(sc, changed);
    const res = await waitJob(slow, sc, j.body.job.id);
    expect(res.status).toBe('failed');
    expect(res.failure?.detail).toContain('作废');
  });

  it('别人的任务 id 读不到（404）', async () => {
    const ep = smartEndpoint();
    const { s, c } = await setup(ep);
    const r = await c.json<{ job: PlanJobView }>('POST', '/api/plan/jobs', {
      kind: 'bind',
      text: '三个月跑完半马',
    });
    await waitJob(s, c, r.body.job.id);
    const bob = await s.login('bob');
    expect((await bob.json('GET', `/api/plan/jobs/${r.body.job.id}`)).status).toBe(404);
    expect((await bob.json<{ job: unknown }>('GET', '/api/plan/jobs/current')).body.job).toBeNull();
  });
});

describe('交单后的续拆', () => {
  it('这一单走完窗口 → 交单回 followUp 任务 id；任务成功后清单变长', async () => {
    const { boundSave, runGoal } = await import('@host/core/testing/helpers');
    const { dayKey } = await import('@host/core/time/day');
    const ep = smartEndpoint();
    const { s, c } = await setup(ep);
    const save = boundSave(runGoal(['E'], 20));
    save.meta.lastRollDay = dayKey(s.clock.t, 'Asia/Shanghai');
    s.seed(c, save);
    const head = save.queue[0]!;
    await c.json('POST', '/api/flow/accept', { serial: head.serial });
    const g = s.saveOf(c);
    g.active!.evidence.push({ id: 'e1', status: 'verified', note: '', takenAt: s.clock.t });
    s.seed(c, g);
    s.clock.t += 10 * 60_000;
    const r = await c.json<{ result: { windowEnd: boolean }; followUp: { jobId: string } }>(
      'POST',
      '/api/flow/submit',
      { serial: head.serial },
    );
    expect(r.body.result.windowEnd).toBe(true);
    expect(r.body.followUp.jobId).toBeTruthy();
    const job = await waitJob(s, c, r.body.followUp.jobId);
    expect(job.kind).toBe('window');
    expect(job.status).toBe('done');
    expect(s.saveOf(c).goal.plan.length).toBeGreaterThan(1);
  });
});
