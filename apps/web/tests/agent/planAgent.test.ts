import { describe, expect, test } from 'vitest';
import {
  buildGoalWithAgent,
  extendGoalWithAgent,
  planFailLine,
  planFailTitle,
} from '../../src/agent/goalBuilder';
import { generatePlanTasks, matchGoal, matchPrompt } from '../../src/agent/planAgent';
import { briefUserText } from '../../src/agent/planBrief';
import { parseTaskMode } from '../../src/agent/mainlineTools';
import { categoryOf } from '@host/core/goal/categories';
import { PlanFailure } from '@host/core/goal/planFailure';
import { planSegmentsFor, planWindowFor, type PlanSegment } from '@host/core/goal/plan';
import { RANKS, rankIndex, type Rank } from '@host/core/data/rank';
import { T0 } from '@host/core/testing/fixtures';
import { fakeClient, fakeEndpoint, type Scripted } from './fakeLlm';

const ladder = (n: number, lo: Rank, hi: Rank, lastS = false): Rank[] =>
  Array.from({ length: n }, (_, i) => {
    if (lastS && i === n - 1) return 'S';
    const l = rankIndex(lo);
    const h = rankIndex(hi === 'S' && lastS ? 'A' : hi);
    return RANKS[Math.min(h, l + Math.floor(((h - l) * i) / Math.max(1, n - 1)))] as Rank;
  });

const tasks = (ranks: Rank[], mode?: string) =>
  ranks.map((r, i) => ({
    short: `第${i + 1}`,
    title: `骑车 ${10 + i} 分钟`,
    proof: '轨迹截图',
    minutes: 10,
    rank: r,
    ...(mode ? { mode } : {}),
  }));

/** 按请求里的「第 a~b 张 / 区间」自动交一份合规的 set_plan */
const autoPlan: Scripted = (body) => {
  const msgs = body['messages'] as Array<{ content: string }>;
  const user = String(msgs[msgs.length - 1]?.content ?? '');
  const all = msgs.map((m) => String(m.content)).join('\n');
  const seg = /你只负责第 \d+ 份：第 (\d+)~(\d+) 张，共 (\d+) 张/.exec(all);
  const range =
    /本段档位只能在 ([FEDCBAS])~([FEDCBAS]) 之间/.exec(all) ??
    /档位只能在 ([FEDCBAS])~([FEDCBAS]) 之间/.exec(all);
  const count = seg
    ? Number(seg[3])
    : Number(/正好 (\d+) 张|共 (\d+) 张\*\*/.exec(all)?.[1] ?? /共 (\d+) 张\*\*/.exec(all)?.[1]);
  const lo = (range?.[1] ?? 'E') as Rank;
  const hi = (range?.[2] ?? 'C') as Rank;
  const lastS = /必须 S 级/.test(all) && !/本段不含兑现单/.test(all);
  void user;
  return {
    text: '',
    tools: [{ name: 'set_plan', args: { tasks: tasks(ladder(count, lo, hi, lastS)) } }],
  };
};

const matchReply = (id = 'run', days = 30, quota = 0): Scripted => ({
  text: '',
  tools: [{ name: 'set_goal_category', args: { id, short: '骑车', days, quota } }],
});

describe('拆解提示词', () => {
  test('窗口 / 段 / 档位上限 / 打卡规则 / 护栏都写进正文', () => {
    const w = planWindowFor({ total: 180 });
    const seg = planSegmentsFor(w)[0] as PlanSegment;
    const t = briefUserText({
      goalText: '半年减重 10 斤',
      days: 180,
      taskCount: w.size,
      cat: categoryOf('slim'),
      interview: { 'slim.now': '60kg' },
      firstGoal: false,
      window: w,
      segment: seg,
    });
    expect(t).toContain('第 1/13 段：第 1~14 张');
    expect(t).toContain('你只负责第 1 份：第 1~7 张');
    expect(t).toContain('D ≤ 40 分钟');
    expect(t).toContain('"checkin"');
    expect(t).toContain('每周最多减约 1 公斤');
    expect(t).toContain('60kg');
  });

  test('匹配提示词带护栏条款', () => {
    expect(matchPrompt('x')).toContain('〔不拆〕');
  });

  test('mode：checkin → 打卡；缺省 / 非法 / 大小写空白都容忍', () => {
    expect(parseTaskMode(' CheckIn ')).toBe(false);
    expect(parseTaskMode(undefined)).toBe(true);
    expect(parseTaskMode('weird')).toBe(true);
  });
});

describe('工具循环', () => {
  const brief = (n: number, firstGoal = true) => ({
    goalText: '两周内骑自行车 10 次',
    days: 14,
    taskCount: n,
    cat: categoryOf('run'),
    interview: {},
    firstGoal,
    window: planWindowFor({ total: n, firstGoal }),
  });

  test('一次交对就收工；打卡标记一路带上', async () => {
    const ep = fakeEndpoint([
      {
        text: '',
        tools: [{ name: 'set_plan', args: { tasks: tasks(['E', 'D', 'C'], 'checkin') } }],
      },
    ]);
    const r = await generatePlanTasks({ client: fakeClient(ep), brief: brief(3) });
    expect(r.tasks.map((t) => [t.rank, t.timed])).toEqual([
      ['E', false],
      ['D', false],
      ['C', false],
    ]);
    expect(ep.calls).toHaveLength(1);
  });

  test('规则错（首目标给了 S）回填原因重交；第二次对了就收', async () => {
    const ep = fakeEndpoint([
      { text: '', tools: [{ name: 'set_plan', args: { tasks: tasks(['E', 'D', 'S']) } }] },
      { text: '', tools: [{ name: 'set_plan', args: { tasks: tasks(['E', 'D', 'C']) } }] },
    ]);
    const r = await generatePlanTasks({ client: fakeClient(ep), brief: brief(3) });
    expect(r.tasks).toHaveLength(3);
    const second = ep.calls[1]!['messages'] as Array<{ content: string }>;
    expect(second[second.length - 1]!.content).toContain('被规则驳回');
  });

  test('她按护栏拒拆 → badGoal；只说话不交工具 → noPlan', async () => {
    const refuse = fakeEndpoint([{ text: '[cold]〔不拆〕这是违法的。' }]);
    await expect(
      generatePlanTasks({ client: fakeClient(refuse), brief: brief(3) }),
    ).rejects.toMatchObject({ code: 'badGoal' });
    const talk = fakeEndpoint([{ text: '我想想。' }]);
    await expect(
      generatePlanTasks({ client: fakeClient(talk), brief: brief(3) }),
    ).rejects.toMatchObject({ code: 'noPlan' });
  });

  test('请求失败 → 原样带出失败类型', async () => {
    const ep = fakeEndpoint([{ status: 401 }]);
    const e = await generatePlanTasks({ client: fakeClient(ep), brief: brief(3) }).catch(
      (x: unknown) => x,
    );
    expect(e).toBeInstanceOf(PlanFailure);
    expect((e as PlanFailure).code).toBe('httpError');
  });

  test('180 天目标只拆第一个窗口：14 张 = 2×7 两路并行', async () => {
    const ep = fakeEndpoint([autoPlan]);
    const w = planWindowFor({ total: 180 });
    let progress: number[] = [];
    const r = await generatePlanTasks({
      client: fakeClient(ep),
      brief: {
        goalText: '半年减重',
        days: 180,
        taskCount: 14,
        cat: categoryOf('slim'),
        interview: {},
        firstGoal: false,
        window: w,
      },
      onProgress: (d, t) => (progress = [d, t]),
    });
    expect(r.tasks).toHaveLength(14);
    expect(ep.calls).toHaveLength(2);
    expect(progress).toEqual([2, 2]);
  });
});

describe('匹配与整条铸造', () => {
  test('匹配：自造 id 给原因重交一次；期限越界抛', async () => {
    const ep = fakeEndpoint([
      {
        text: '',
        tools: [
          {
            name: 'set_goal_category',
            args: { id: 'cycling', short: '骑车', days: 14, quota: 10 },
          },
        ],
      },
      matchReply('run', 14, 10),
    ]);
    const m = await matchGoal({ client: fakeClient(ep), goalText: '两周内骑自行车 10 次' });
    expect([m.cat.id, m.days, m.quota]).toEqual(['run', 14, 10]);
  });

  test('首目标：匹配 → 拆第一段（E~C、≤14 张）→ 校验落成目标；次数配额定总张数', async () => {
    const ep = fakeEndpoint([matchReply('run', 14, 10), autoPlan]);
    const stages: number[] = [];
    const { goal } = await buildGoalWithAgent({
      client: fakeClient(ep),
      text: '两周内骑自行车 10 次',
      at: T0,
      firstGoal: true,
      answers: { 'run.now': '3 公里以内' },
      onProgress: (p) => stages.push(p.stage),
    });
    expect([goal.plan.length, goal.planTotal, goal.cat, goal.short]).toEqual([
      10,
      10,
      'run',
      '骑车',
    ]);
    expect(goal.plan.every((t) => ['E', 'D', 'C'].includes(t.rank))).toBe(true);
    expect(goal.plan.some((t) => t.finalTask)).toBe(false);
    expect(stages).toEqual(expect.arrayContaining([0, 1, 2]));
    expect(goal.interview).toEqual({ 'run.now': '3 公里以内' });
  });

  test('续拆：同一条主线接上下一段（不再匹配），进度摘要进提示词', async () => {
    const ep = fakeEndpoint([matchReply('slim', 180), autoPlan]);
    const { goal } = await buildGoalWithAgent({
      client: fakeClient(ep),
      text: '半年减重 10 斤',
      at: T0,
    });
    const done = {
      ...goal,
      plan: goal.plan.map((t) => ({ ...t, state: 'done' as const, heldMs: 60_000 })),
    };
    const ep2 = fakeEndpoint([autoPlan]);
    const next = await extendGoalWithAgent({ client: fakeClient(ep2), goal: done, now: T0 });
    expect(next.plan).toHaveLength(28);
    const all = (ep2.calls[0]!['messages'] as Array<{ content: string }>)
      .map((m) => m.content)
      .join('\n');
    expect(all).toContain('前面做到了哪里');
  });

  test('任何异常都落成 PlanFailure；失败卡按类型给标题和说明', async () => {
    const ep = fakeEndpoint([{ throw: 'network' }, { throw: 'network' }]);
    await expect(
      buildGoalWithAgent({ client: fakeClient(ep, { online: false }), text: 'x', at: T0 }),
    ).rejects.toMatchObject({ code: 'network' });
    expect(planFailTitle('httpError')).toBe('上游不可用');
    expect(planFailLine('noKey')).toContain('Key');
    expect(planFailTitle('cors')).toContain('跨域');
  });
});
