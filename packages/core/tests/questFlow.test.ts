import { describe, expect, test } from 'vitest';
import { QuestFlow } from '../src/flow/questFlow';
import { settle } from '../src/flow/settle';
import { kindLabel, lootText, questCode, timeLabel } from '../src/flow/questText';
import { goalFirstOpenIndex } from '../src/model/goal';
import { freshSave, saveFromJson, saveToJson } from '../src/save/saveData';
import { quest, sampleSave, T0 } from './fixtures';
import { DAY, boundSave, flowWithActive, runGoal } from './helpers';

const MIN = 60_000;

describe('在手窗口与主线锁', () => {
  test('绑定后只发当前这一张主线到手', () => {
    const s = boundSave();
    expect(s.queue.map((q) => q.planIndex)).toEqual([0]);
  });

  test('publishPlanTasks 幂等：再调不重发', () => {
    const f = new QuestFlow(boundSave());
    expect(f.publishPlanTasks()).toEqual([]);
    expect(f.changed).toBe(false);
  });

  test('执行中的那张也占窗口：接单后不补发', () => {
    const f = flowWithActive();
    expect(f.publishPlanTasks()).toEqual([]);
    expect(f.queue).toEqual([]);
  });

  test('主线只能接清单里第一张没完成的（E1.3）', () => {
    const f = new QuestFlow(boundSave());
    expect(f.isMainLocked(f.head!)).toBe(false);
    expect(f.isMainLocked({ ...f.head!, planIndex: 2 })).toBe(true);
  });
});

describe('接单与证据（C4 / C7）', () => {
  test('accept：出队、active 记 startAt', () => {
    const f = flowWithActive();
    expect(f.active?.task.planIndex).toBe(0);
    expect(f.active?.startAt).toBe(T0);
    expect(f.queue).toEqual([]);
    expect(f.changed).toBe(true);
  });

  test('判定不符的 addEvidence 直接拒；最多 3 张；按 id 撤', () => {
    const f = flowWithActive();
    expect(f.addEvidence({ id: 'x', status: 'mismatch', note: '', takenAt: T0 })).toBe(false);
    for (const id of ['a', 'b', 'c'])
      f.addEvidence({ id, status: 'unverified', note: '', takenAt: T0 });
    expect(f.addEvidence({ id: 'd', status: 'unverified', note: '', takenAt: T0 })).toBe(false);
    expect(f.removeEvidence('b')).toBe(true);
    expect(f.removeEvidence('b')).toBe(false);
    expect(f.active?.evidence.map((e) => e.id)).toEqual(['a', 'c']);
  });

  test('后台结论落槽：不符撤掉，拿不准 / 未校验照收，找不到 = gone', () => {
    const f = flowWithActive();
    for (const id of ['a', 'b', 'c'])
      f.addEvidence({ id, status: 'unverified', note: '', takenAt: T0 });
    expect(f.applyVerdict('a', 'mismatch', '这是一朵花')).toBe('rejected');
    expect(f.applyVerdict('b', 'unsure', '有点糊')).toBe('kept');
    expect(f.applyVerdict('c', 'verified', '看得到读数')).toBe('kept');
    expect(f.applyVerdict('zzz', 'verified', '')).toBe('gone');
    expect(f.active?.evidence.map((e) => [e.id, e.status])).toEqual([
      ['b', 'unsure'],
      ['c', 'verified'],
    ]);
  });

  test('交单即封存：结算后回来的结论一律 gone', () => {
    const f = flowWithActive();
    f.addEvidence({ id: 'a', status: 'unverified', note: '', takenAt: T0 });
    settle(f, { now: T0 + 30 * MIN });
    expect(f.applyVerdict('a', 'mismatch', '')).toBe('gone');
  });
});

describe('结算', () => {
  test('没接单时 settle 抛', () => {
    expect(() => settle(new QuestFlow(boundSave()), { now: T0 })).toThrow();
  });

  test('E 级主线：EXP +1、连胜起 1、划掉这一环并补下一张', () => {
    const f = flowWithActive();
    f.addEvidence({ id: 'a', status: 'verified', note: '', takenAt: T0 });
    const r = settle(f, { now: T0 + 25 * MIN });
    expect([r.exp, r.streak, r.streakUp, r.photos, r.verified]).toEqual([1, 1, true, 1, 1]);
    expect(f.goal.plan[0]).toMatchObject({
      state: 'done',
      heldMs: 25 * MIN,
      doneAt: T0 + 25 * MIN,
    });
    expect(r.planClear).toBe(0);
    expect(f.active).toBeNull();
    expect(f.queue.map((q) => q.planIndex)).toEqual([1]);
    expect(f.history[0]).toEqual({
      at: T0 + 25 * MIN,
      name: '跑 1 公里',
      rank: 'E',
      exp: 1,
      streak: 1,
      result: 'clear',
    });
  });

  test('升级：溢出滚入下一档，连升两级 ups 依次记录；累计 EXP 不扣', () => {
    const f = flowWithActive(boundSave(runGoal(['S', 'S'])));
    f.host.exp = 17;
    f.host.lv = 1;
    const r = settle(f, { now: T0 + 30 * MIN });
    // S = 10；17+10 = 27 → LV1 需 18 → 9
    expect(r.exp).toBe(10);
    expect(r.ups).toEqual([2]);
    expect([f.host.lv, f.host.exp, r.afterNeed]).toEqual([2, 9, 24]);
    expect(f.host.totalExp).toBe(10);
    const g = flowWithActive(f.save);
    g.host.exp = 23;
    const r2 = settle(g, { now: T0 + 40 * MIN });
    // 23+10 = 33 → LV2 需 24 → 9（LV3 需 30，不够再升）
    expect(r2.ups).toEqual([3]);
  });

  test('不属于当前主线的单（旧档）照样入账，但不划清单', () => {
    const s = boundSave();
    s.queue = [quest(900, { goalId: 'old', planIndex: 0 })];
    const f = flowWithActive(s);
    const r = settle(f, { now: T0 + MIN });
    expect(r.planClear).toBe(-1);
    expect(r.exp).toBe(1);
    expect(f.goal.plan[0]?.state).toBe('todo');
  });
});

describe('连胜（C6）', () => {
  test('同一天第二单不再 +1；隔天接上 +1；断一天以上从 1 起', () => {
    let f = flowWithActive();
    settle(f, { now: T0 });
    f = flowWithActive(f.save, T0 + MIN);
    expect(settle(f, { now: T0 + 2 * MIN }).streakUp).toBe(false);
    f = flowWithActive(f.save, T0 + DAY);
    expect(settle(f, { now: T0 + DAY }).streak).toBe(2);
    f = flowWithActive(f.save, T0 + 3 * DAY);
    expect(settle(f, { now: T0 + 3 * DAY }).streak).toBe(1);
    expect(f.host.bestStreak).toBe(2);
  });

  test('重启（存档往返）后连胜照样接上 —— 旧版漏存 lastDoneDay 的 bug', () => {
    const f = flowWithActive();
    settle(f, { now: T0 });
    const reloaded = JSON.parse(JSON.stringify(f.save));
    const g = flowWithActive(reloaded, T0 + DAY);
    expect(settle(g, { now: T0 + DAY }).streak).toBe(2);
  });

  test('换日发现昨天一单没完成 → 连胜当场归零；同一天反复换日只算一次', () => {
    const f = flowWithActive();
    settle(f, { now: T0 });
    f.host.streak = 5;
    expect(f.rollDay(T0 + DAY)).toBe(true);
    expect(f.host.streak).toBe(5);
    expect(f.rollDay(T0 + DAY + MIN)).toBe(false);
    f.rollDay(T0 + 2 * DAY);
    expect(f.host.streak).toBe(0);
  });
});

describe('换日', () => {
  test('主线单留在手上（单号不变）；手上空了补回当前这一张', () => {
    const f = new QuestFlow(boundSave());
    const serial = f.head!.serial;
    f.rollDay(T0 + DAY);
    expect(f.queue.map((q) => q.serial)).toEqual([serial]);
    f.queue.splice(0);
    f.rollDay(T0 + 2 * DAY);
    expect(f.queue.map((q) => q.planIndex)).toEqual([0]);
  });

  test('没绑定：只记换日，不发单', () => {
    const f = new QuestFlow(freshSave(T0));
    expect(f.rollDay(T0)).toBe(true);
    expect(f.queue).toEqual([]);
  });
});

describe('C5 先跳过 / 换目标', () => {
  test('跳过：记住目标、可重试', () => {
    const f = new QuestFlow(freshSave(T0));
    f.skipPlan(' 三个月学会弹吉他 ');
    expect(f.save.pendingGoal).toBe('三个月学会弹吉他');
    expect(f.canRetryPlan).toBe(true);
    expect(f.queue).toEqual([]);
  });

  test('newGoal：旧主线单撤下、新主线进在手窗口、记着的目标清掉', () => {
    const s = boundSave();
    s.pendingGoal = 'x';
    const f = new QuestFlow(s);
    const first = f.newGoal(runGoal(['E', 'D', 'S'], 3, 'g-new'));
    expect(first.goalId).toBe('g-new');
    expect(f.queue.map((q) => q.goalId)).toEqual(['g-new']);
    expect(f.save.pendingGoal).toBe('');
    expect(() => f.newGoal({ ...f.goal, plan: [] })).toThrow();
  });
});

describe('滚动生成：窗口走完续拆、最后一段收官', () => {
  test('窗口走完 → windowEnd；续拆接上后补回当前这一张', () => {
    let f = flowWithActive(boundSave(runGoal(['E', 'E'], 30)));
    settle(f, { now: T0 });
    f = flowWithActive(f.save);
    const r = settle(f, { now: T0 + MIN });
    expect([r.windowEnd, r.finale, r.empty]).toEqual([true, false, true]);
    expect(f.canResumePlan).toBe(true);
    const next = runGoal(['E', 'E', 'D', 'D'], 30);
    next.plan = [...f.goal.plan, ...next.plan.slice(2).map((t) => ({ ...t }))];
    f.applyNextWindow(next);
    expect(goalFirstOpenIndex(f.goal)).toBe(2);
    expect(f.queue.map((q) => q.planIndex)).toEqual([2]);
  });

  test('兑现单交掉 = finale；下一条主线落库撤掉旧主线单', () => {
    let f = flowWithActive(boundSave(runGoal(['E', 'S'])));
    settle(f, { now: T0 });
    f = flowWithActive(f.save);
    const r = settle(f, { now: T0 + MIN });
    expect(r.finale).toBe(true);
    f.applyNextGoal(runGoal(['D', 'C', 'S'], 3, 'g-2'));
    expect(f.queue.map((q) => q.goalId)).toEqual(['g-2']);
  });

  test('续拆交回的目标身份不对 → 抛', () => {
    const f = new QuestFlow(boundSave(runGoal(['E'], 10)));
    expect(() => f.applyNextWindow(runGoal(['E', 'E'], 10, 'other'))).toThrow();
  });
});

describe('文案读数', () => {
  test('主线编码、耗时、报酬与结算同一口径', () => {
    const q = quest(41, { planIndex: 1, planTotal: 30, minutes: 25, rank: 'C' });
    expect(kindLabel(q)).toBe('主线 · 第 2 单 / 30');
    expect(questCode(q)).toBe('MAIN 02/30');
    expect(timeLabel(q)).toBe('约 25 分钟');
    expect(lootText(q)).toBe('EXP +4');
  });
});

describe('旧档兼容', () => {
  test('旧版的日常 / 补救单与已拿掉的字段读档时丢掉，主线与执行中保留', () => {
    const raw = saveToJson(sampleSave()) as Record<string, unknown>;
    raw['queue'] = [
      ...(raw['queue'] as unknown[]),
      { serial: 60, kind: 'daily', name: '喝水', rank: 'E', mode: 'checkin' },
      { serial: 61, kind: 'remedy', name: '补救', rank: 'F', planIndex: 0 },
    ];
    raw['host'] = { ...(raw['host'] as object), coins: 99, items: { dbl: 1 }, title: 'mouth' };
    const s = saveFromJson(raw, T0)!;
    expect(s.queue.map((q) => q.serial)).toEqual([53]);
    expect(s.active?.task.serial).toBe(51);
    expect(s.host).not.toHaveProperty('coins');
    expect(s.meta.nextSerial).toBe(54);
  });
});
