import { describe, expect, test } from 'vitest';
import { QuestFlow } from '../src/flow/questFlow';
import { checkTimeout, deadlineOf, fail, settle } from '../src/flow/settle';
import { gradeOf, kindLabel, questCode, timeLabel } from '../src/flow/questText';
import { goalFirstOpenIndex, goalId } from '../src/model/goal';
import { freshSave } from '../src/save/saveData';
import { quest, T0 } from './fixtures';
import { DAY, boundSave, fixed, flowWithActive, runGoal, seeded } from './helpers';

const MIN = 60_000;

describe('在手窗口与主线锁', () => {
  test('绑定后主线发 3 张到手、按清单顺序排队首', () => {
    const s = boundSave();
    expect(s.queue.map((q) => [q.kind, q.planIndex])).toEqual([
      ['main', 0],
      ['main', 1],
      ['main', 2],
    ]);
    expect(new Set(s.queue.map((q) => q.serial)).size).toBe(3);
  });

  test('publishPlanTasks 幂等：再调不重发', () => {
    const f = new QuestFlow(boundSave());
    expect(f.publishPlanTasks()).toEqual([]);
    expect(f.changed).toBe(false);
  });

  test('主线只能接清单里第一张没完成的；日常 / 补救不锁（E1.3）', () => {
    const f = new QuestFlow(boundSave());
    const [m0, m1] = f.queue;
    expect(f.isMainLocked(m0!)).toBe(false);
    expect(f.isMainLocked(m1!)).toBe(true);
    expect(f.isMainLocked(quest(99))).toBe(false);
  });

  test('空目标（未绑定）什么都不种', () => {
    const f = new QuestFlow(freshSave(T0));
    f.seedForCurrentGoal();
    expect(f.queue).toEqual([]);
  });
});

describe('接单与道具', () => {
  test('accept：出队、active 记 startAt', () => {
    const f = flowWithActive();
    expect(f.active?.task.planIndex).toBe(0);
    expect(f.active?.startAt).toBe(T0);
    expect(f.queue.some((q) => q.serial === f.active?.task.serial)).toBe(false);
    expect(f.changed).toBe(true);
  });

  test('useItem：扣库存、挂标记；重复 / 没库存 / 没接单都 false', () => {
    const f = flowWithActive();
    f.host.items = { dbl: 1, crit: 0, shield: 1, patch: 0 };
    expect(f.useItem('dbl')).toBe(true);
    expect(f.host.items['dbl']).toBe(0);
    expect(f.active?.dbl).toBe(true);
    expect(f.useItem('dbl')).toBe(false);
    expect(f.useItem('crit')).toBe(false);
    expect(new QuestFlow(boundSave()).useItem('dbl')).toBe(false);
  });

  test('护盾：打卡单装不上；碎过之后这一单不能再装', () => {
    const s = boundSave();
    s.queue[0] = { ...s.queue[0]!, timed: false };
    const f = flowWithActive(s);
    f.host.items['shield'] = 2;
    expect(f.itemBlock('shield')).toBe('打卡单用不上。');
    const g = flowWithActive();
    g.host.items['shield'] = 2;
    expect(g.useItem('shield')).toBe(true);
    const dl = deadlineOf(g.active!);
    expect(checkTimeout(g, dl).kind).toBe('shield');
    expect(g.itemBlock('shield')).toBe('这一单的护盾已经碎过了。');
  });

  test('critChance：底 6% + 连胜；芯片 +25%；critBase 不含证据', () => {
    const f = flowWithActive();
    f.host.streak = 6;
    expect(f.critChance()).toBeCloseTo(0.12);
    f.addEvidence({ id: 'a', status: 'verified', note: '', takenAt: T0 });
    f.addEvidence({ id: 'b', status: 'unverified', note: '', takenAt: T0 });
    expect(f.critChance()).toBeCloseTo(0.12 + 0.07 + 0.04);
    expect(f.critBase()).toBeCloseTo(0.12);
  });
});

describe('证据（C4 / C7）', () => {
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

  test('E 级主线：EXP +1、晶核 +5、六维 +、连胜起 1、划掉这一环并补一张', () => {
    const f = flowWithActive();
    const r = settle(f, { now: T0 + 25 * MIN });
    expect([r.exp, r.coin, r.streak, r.streakUp]).toEqual([1, 5, 1, true]);
    expect(f.host.attrs['力']).toBeGreaterThan(0);
    expect(f.goal.plan[0]).toMatchObject({
      state: 'done',
      heldMs: 25 * MIN,
      doneAt: T0 + 25 * MIN,
    });
    expect(r.planClear).toBe(0);
    expect(f.active).toBeNull();
    expect(f.queue.filter((q) => q.kind === 'main').map((q) => q.planIndex)).toEqual([1, 2, 3]);
    expect(f.history[0]).toMatchObject({ result: 'clear', exp: 1, coin: 5 });
  });

  test('暴击 ×2、双倍卡叠 ×4，critCount 记账', () => {
    const f = flowWithActive(boundSave(runGoal(['C', 'C', 'S'])));
    f.host.items['dbl'] = 1;
    f.useItem('dbl');
    const r = settle(f, { now: T0 + 30 * MIN, forceCrit: true });
    expect([r.exp, r.coin, r.baseExp]).toEqual([16, 10, 4]);
    expect(f.host.critCount).toBe(1);
    expect(r.titles).toContain('crit');
  });

  test('升级：溢出滚入下一档，连升两级 ups 依次记录；累计 EXP 不扣', () => {
    const f = flowWithActive(boundSave(runGoal(['S', 'S'])));
    f.host.exp = 17;
    f.host.items['dbl'] = 1;
    f.useItem('dbl');
    const r = settle(f, { now: T0 + 30 * MIN, forceCrit: true });
    // S：10 × 暴击 2 × 双倍 2 = 40；17+40 = 57 → LV1 需 18 → 39 → LV2 需 24 → 15
    expect(r.exp).toBe(40);
    expect(r.ups).toEqual([2, 3]);
    expect([f.host.lv, f.host.exp, r.afterNeed]).toEqual([3, 15, 30]);
    expect(f.host.totalExp).toBe(40);
  });

  test('60 秒内交计时单 → tooFast；打卡单不算', () => {
    expect(settle(flowWithActive(), { now: T0 + 30_000 }).tooFast).toBe(true);
    const s = boundSave();
    s.queue[0] = { ...s.queue[0]!, timed: false };
    expect(settle(flowWithActive(s), { now: T0 + 30_000 }).tooFast).toBe(false);
  });

  test('评级落库：主线卡战报读的就是结算那一刻的评级', () => {
    const f = flowWithActive();
    f.addEvidence({ id: 'a', status: 'verified', note: '', takenAt: T0 });
    const r = settle(f, { now: T0 + 25 * MIN });
    expect(r.grade).toBe('A');
    expect(f.goal.plan[0]?.grade).toBe('A');
  });

  test('称号：首单 first；5 单 done5；A 级 rankA', () => {
    const f = flowWithActive();
    f.host.doneCount = 4;
    const r = settle(f, { now: T0 + 25 * MIN });
    expect(r.titles).toEqual(expect.arrayContaining(['first', 'done5']));
    expect(f.host.title).toBe(r.titles[r.titles.length - 1]);
  });
});

describe('评级口径（E2.2 证据为主、用时为辅）', () => {
  const base = { timed: true, minutes: 20, heldMs: 15 * MIN, verified: 0, photos: 0, crit: false };
  test('有判真 = A；只有拿不准 / 未校验 = B；没证据 = C', () => {
    expect(gradeOf({ ...base, verified: 1, photos: 1 })).toBe('A');
    expect(gradeOf({ ...base, photos: 2 })).toBe('B');
    expect(gradeOf(base)).toBe('C');
  });
  test('计时单用时不到 1/4 降一档；打卡单不看用时；暴击 A → S', () => {
    expect(gradeOf({ ...base, heldMs: 4 * MIN, verified: 1, photos: 1 })).toBe('B');
    expect(gradeOf({ ...base, heldMs: 4 * MIN, photos: 1 })).toBe('C');
    expect(gradeOf({ ...base, timed: false, heldMs: 1000, verified: 1, photos: 1 })).toBe('A');
    expect(gradeOf({ ...base, verified: 1, photos: 1, crit: true })).toBe('S');
    expect(gradeOf({ ...base, photos: 1, crit: true })).toBe('B');
  });
});

describe('连胜（C6）与补签（docs/01 Q4）', () => {
  test('同一天第二单不再 +1；隔天接上 +1；断一天以上从 1 起', () => {
    let f = flowWithActive();
    settle(f, { now: T0 });
    f = flowWithActive(f.save, fixed(0.99), T0 + MIN);
    expect(settle(f, { now: T0 + 2 * MIN }).streakUp).toBe(false);
    f = flowWithActive(f.save, fixed(0.99), T0 + DAY);
    expect(settle(f, { now: T0 + DAY }).streak).toBe(2);
    f = flowWithActive(f.save, fixed(0.99), T0 + 3 * DAY);
    expect(settle(f, { now: T0 + 3 * DAY }).streak).toBe(1);
    expect(f.host.bestStreak).toBe(2);
  });

  test('认输不断连胜', () => {
    let f = flowWithActive();
    settle(f, { now: T0 });
    f = flowWithActive(f.save);
    fail(f, { now: T0 + MIN });
    expect(f.host.streak).toBe(1);
  });

  test('重启（存档往返）后连胜照样接上 —— 旧版漏存 lastDoneDay 的 bug', () => {
    const f = flowWithActive();
    settle(f, { now: T0 });
    const reloaded = JSON.parse(JSON.stringify(f.save));
    const g = flowWithActive(reloaded, fixed(0.99), T0 + DAY);
    expect(settle(g, { now: T0 + DAY }).streak).toBe(2);
  });

  test('换日发现昨天一单没完成 → 连胜当场归零，记下断前的值', () => {
    const f = flowWithActive();
    settle(f, { now: T0 });
    f.host.streak = 5;
    f.rollDay(T0 + DAY);
    expect(f.host.streak).toBe(5);
    f.rollDay(T0 + 2 * DAY);
    expect(f.host.streak).toBe(0);
    expect(f.meta.brokenStreak).toBe(5);
    expect(f.meta.missedDay).toBe('2026-11-22');
  });

  test('补签券：只断了昨天 → 恢复为断前 +1；今天再完成接着 +1', () => {
    const f = flowWithActive();
    settle(f, { now: T0 });
    f.host.streak = 5;
    f.host.items['patch'] = 1;
    f.rollDay(T0 + 2 * DAY);
    expect(f.patchStatus(T0 + 2 * DAY)).toEqual({ ok: true, restoreTo: 6 });
    expect(f.usePatch(T0 + 2 * DAY)).toBe(true);
    expect([f.host.streak, f.host.items['patch'], f.meta.lastDoneDay]).toEqual([
      6,
      0,
      '2026-11-22',
    ]);
    const g = flowWithActive(f.save, fixed(0.99), T0 + 2 * DAY);
    expect(settle(g, { now: T0 + 2 * DAY }).streak).toBe(7);
  });

  test('补签券：今天已经完成过（连胜从 1 起了）→ 断前 +1 再 +1', () => {
    let f = flowWithActive();
    settle(f, { now: T0 });
    f.host.streak = 5;
    f.host.items['patch'] = 1;
    f.rollDay(T0 + 2 * DAY);
    f = flowWithActive(f.save, fixed(0.99), T0 + 2 * DAY);
    expect(settle(f, { now: T0 + 2 * DAY }).streak).toBe(1);
    expect(f.patchStatus(T0 + 2 * DAY)).toEqual({ ok: true, restoreTo: 7 });
    f.usePatch(T0 + 2 * DAY);
    expect(f.host.streak).toBe(7);
  });

  test('补签券不能用的几种情况都说明原因', () => {
    const f = flowWithActive();
    settle(f, { now: T0 });
    f.host.items['patch'] = 1;
    expect(f.patchStatus(T0 + DAY)).toEqual({ ok: false, reason: '没断签，用不上。' });
    f.host.streak = 3;
    f.rollDay(T0 + 4 * DAY);
    expect(f.patchStatus(T0 + 4 * DAY)).toEqual({ ok: false, reason: '断了不止一天，补不回来。' });
    f.rollDay(T0 + 5 * DAY);
    expect(f.patchStatus(T0 + 5 * DAY)).toEqual({ ok: false, reason: '没断签，用不上。' });
    f.host.items['patch'] = 0;
    expect(f.patchStatus(T0 + 5 * DAY).ok).toBe(false);
  });
});

describe('认输与补救（E1.4 补救单顶替这一环）', () => {
  test('主线认输：failCount +1、补救单顶替这一环（降两档 / 时长减半 / 24h / 当场入队）', () => {
    const f = flowWithActive(boundSave(runGoal(['C', 'C', 'S'])));
    const o = fail(f, { now: T0 + 10 * MIN })!;
    expect(f.host.failCount).toBe(1);
    expect(o.remedy).toMatchObject({
      kind: 'remedy',
      rank: 'E',
      minutes: 10,
      planIndex: 0,
      goalId: goalId(f.goal),
      name: '跑 1 公里（简化版）',
    });
    expect(o.remedyDeadline).toBe(T0 + 10 * MIN + DAY);
    expect(f.queue[0]?.serial).toBe(o.remedy?.serial);
    expect(f.queue.some((q) => q.kind === 'main' && q.planIndex === 0)).toBe(false);
    expect(f.history[0]).toMatchObject({ result: 'quit', exp: 0 });
    expect(kindLabel(o.remedy!)).toBe('补救 · 顶替主线第 1 单');
    expect(questCode(o.remedy!)).toBe('补救 · 主线 01');
  });

  test('takeRemedy 不会把已入队的补救单再塞一张；先放委托板 = 排队尾', () => {
    const f = flowWithActive();
    const o = fail(f, { now: T0 })!;
    const r = f.takeRemedy(false)!;
    expect(r.serial).toBe(o.remedy?.serial);
    expect(f.queue.filter((q) => q.serial === r.serial)).toHaveLength(1);
    expect(f.queue[f.queue.length - 1]?.serial).toBe(r.serial);
    expect(f.meta.remedyOffer).toBeNull();
    expect(f.takeRemedy(true)).toBeNull();
  });

  test('交掉顶替主线的补救单 = 这一环过关，奖励按补救降档', () => {
    let f = flowWithActive(boundSave(runGoal(['C', 'C', 'S'])));
    fail(f, { now: T0 });
    f = flowWithActive(f.save);
    const r = settle(f, { now: T0 + 10 * MIN });
    expect(r.redeemed).toBe(true);
    expect(r.planClear).toBe(0);
    expect(f.goal.plan[0]?.state).toBe('done');
    expect(r.exp).toBe(1);
    expect(r.titles).toContain('redeem');
  });

  test('补救单再认输 → 不再生成补救单，原单补回手上', () => {
    let f = flowWithActive();
    fail(f, { now: T0 });
    f = flowWithActive(f.save);
    const o = fail(f, { now: T0 + MIN })!;
    expect(o.remedy).toBeNull();
    expect(f.queue.some((q) => q.kind === 'main' && q.planIndex === 0)).toBe(true);
  });

  test('日常单认输：补救单只挂在 offer 上（不顶替主线）', () => {
    const s = boundSave();
    s.queue.unshift(quest(200, { rank: 'D' }));
    const f = flowWithActive(s);
    const o = fail(f, { now: T0 })!;
    expect(o.remedy?.planIndex).toBe(-1);
    expect(f.queue.some((q) => q.serial === o.remedy?.serial)).toBe(false);
    expect(kindLabel(o.remedy!)).toBe('补救 · 24 小时内有效');
  });
});

describe('超时与护盾（docs/01 Q3）', () => {
  test('没到点 = none；到点没护盾 = 超时判负', () => {
    const f = flowWithActive();
    const dl = deadlineOf(f.active!);
    expect(checkTimeout(f, dl - 1).kind).toBe('none');
    const r = checkTimeout(f, dl);
    expect(r.kind).toBe('fail');
    if (r.kind === 'fail') expect(r.outcome.how).toBe('timeout');
  });

  test('装着护盾：到点护盾碎掉、顺延 ceil(时长/2)；顺延后再到点照常判负', () => {
    const f = flowWithActive(boundSave(runGoal(['E', 'S'])));
    f.active!.task.minutes = 25;
    f.host.items['shield'] = 1;
    f.useItem('shield');
    const dl = deadlineOf(f.active!);
    expect(checkTimeout(f, dl)).toEqual({ kind: 'shield', extendMin: 13 });
    expect(f.active?.shield).toBe(false);
    expect(f.active?.extraMs).toBe(13 * MIN);
    expect(checkTimeout(f, dl + 13 * MIN - 1).kind).toBe('none');
    expect(checkTimeout(f, dl + 13 * MIN).kind).toBe('fail');
  });

  test('打卡单不判超时；认输照常', () => {
    const s = boundSave();
    s.queue[0] = { ...s.queue[0]!, timed: false };
    const f = flowWithActive(s);
    expect(checkTimeout(f, T0 + 10 * DAY).kind).toBe('none');
    expect(fail(f, { now: T0, how: 'timeout' })).toBeNull();
    expect(fail(f, { now: T0 })?.how).toBe('quit');
    expect(timeLabel(s.queue[0]!)).toBe('打卡');
  });
});

describe('换一个 retreat', () => {
  test('非 F 级：同一张单降一档重刻（serial 不变）', () => {
    const s = boundSave();
    const d = quest(300, { rank: 'C', attrs: { 智: 1, 知: 1 } });
    s.queue.push(d);
    const f = new QuestFlow(s, { rnd: seeded() });
    const o = f.retreat(d, T0)!;
    expect(o.replacement).toMatchObject({ serial: 300, rank: 'D' });
    expect([o.count, o.total, o.shame]).toEqual([1, 1, false]);
  });

  test('F 级还退：换另一张 F 日常顶位', () => {
    const s = boundSave();
    const d = quest(300, { rank: 'F' });
    s.queue.push(d);
    const f = new QuestFlow(s, { rnd: seeded() });
    const o = f.retreat(d, T0)!;
    expect(o.replacement?.rank).toBe('F');
    expect(o.replacement?.serial).not.toBe(300);
  });

  test('跨日 retreatToday 归零；累计 ≥3 强制佩戴「口头巨人」，交成一单后换回', () => {
    const s = boundSave();
    s.queue.push(quest(300, { rank: 'B' }));
    let f = new QuestFlow(s, { rnd: seeded() });
    f.host.title = 'first';
    f.host.ownedTitles = ['bind', 'first'];
    f.retreat(
      f.queue.find((q) => q.serial === 300)!,
      T0,
    );
    f.retreat(
      f.queue.find((q) => q.serial === 300)!,
      T0,
    );
    const o = f.retreat(
      f.queue.find((q) => q.serial === 300)!,
      T0 + DAY,
    )!;
    expect([o.count, o.total, o.shame]).toEqual([1, 3, true]);
    expect(f.host.title).toBe('mouth');
    expect(f.equip('first')).toBe(false);
    f = flowWithActive(f.save);
    settle(f, { now: T0 + DAY });
    expect(f.host.title).not.toBe('mouth');
    expect(f.host.ownedTitles).toContain('mouth');
  });

  test('不在她手里的单 → null，计数不动', () => {
    const f = new QuestFlow(boundSave());
    expect(f.retreat(quest(999), T0)).toBeNull();
    expect(f.meta.retreatTotal).toBe(0);
  });
});

describe('补给与佩戴', () => {
  test('买得起扣晶核 + 道具 +1；买不起 / 等级不够分文不动', () => {
    const f = new QuestFlow(boundSave());
    f.host.coins = 60;
    expect(f.buy('dbl')).toBe(true);
    expect([f.host.coins, f.host.items['dbl']]).toEqual([0, 1]);
    expect(f.buy('patch')).toBe(false);
    f.host.coins = 200;
    expect(f.buyBlock('shield')).toBe('LV2 解锁。');
    f.host.lv = 2;
    expect(f.buy('shield')).toBe(true);
    expect(f.host.coins).toBe(110);
  });

  test('equip：未解锁 false；已解锁换挂', () => {
    const f = new QuestFlow(boundSave());
    expect(f.equip('done15')).toBe(false);
    f.host.ownedTitles.push('first');
    expect(f.equip('first')).toBe(true);
    expect(f.host.title).toBe('first');
  });
});

describe('换日', () => {
  test('隔夜日常作废、主线重钉（新单号）、发当日日常；同一天不重发', () => {
    const s = boundSave();
    s.queue.push(quest(500), quest(501));
    s.meta.lastRollDay = '2026-11-21';
    const f = new QuestFlow(s, { rnd: seeded(3) });
    expect(f.rollDay(T0)).toBe(false);
    expect(f.rollDay(T0 + DAY)).toBe(true);
    expect(f.queue.some((q) => q.serial === 500)).toBe(false);
    expect(f.queue.filter((q) => q.kind === 'main').map((q) => q.planIndex)).toEqual([0, 1, 2]);
    expect(f.queue.filter((q) => q.kind === 'daily').length).toBeGreaterThanOrEqual(1);
    expect(f.rollDay(T0 + DAY + 1000)).toBe(false);
  });

  test('补救单只留未过期的', () => {
    const f = flowWithActive();
    fail(f, { now: T0 });
    f.meta.lastRollDay = '2026-11-21';
    f.rollDay(T0 + 2 * DAY);
    expect(f.queue.some((q) => q.kind === 'remedy')).toBe(false);
    expect(f.queue.some((q) => q.kind === 'main' && q.planIndex === 0)).toBe(true);
  });

  test('没绑定也没记着目标：不发日常', () => {
    const f = new QuestFlow(freshSave(T0), { rnd: seeded() });
    f.rollDay(T0);
    expect(f.queue).toEqual([]);
  });
});

describe('C5 先跳过 / 换目标', () => {
  test('跳过：记住目标、当天日常发出、可重试；重复跳过不叠发', () => {
    const f = new QuestFlow(freshSave(T0), { rnd: seeded() });
    const out = f.skipPlan(' 三个月学会弹吉他 ');
    expect(out.length).toBeGreaterThan(0);
    expect(f.save.pendingGoal).toBe('三个月学会弹吉他');
    expect(f.canRetryPlan).toBe(true);
    f.skipPlan('三个月学会弹吉他');
    expect(f.queue.length).toBe(out.length);
  });

  test('newGoal：旧主线单撤下、新主线进在手窗口、日常保留、记着的目标清掉', () => {
    const s = boundSave();
    s.queue.push(quest(700));
    s.pendingGoal = 'x';
    const f = new QuestFlow(s);
    const first = f.newGoal(runGoal(['E', 'D', 'S'], 3, 'g-new'));
    expect(first.goalId).toBe('g-new');
    expect(f.queue.filter((q) => q.kind === 'main').every((q) => q.goalId === 'g-new')).toBe(true);
    expect(f.queue.some((q) => q.serial === 700)).toBe(true);
    expect(f.save.pendingGoal).toBe('');
    expect(() => f.newGoal({ ...f.goal, plan: [] })).toThrow();
  });
});

describe('滚动生成：窗口走完续拆、最后一段收官', () => {
  test('窗口走完 → windowEnd；续拆接上后在手窗口补齐', () => {
    let f = flowWithActive(boundSave(runGoal(['E', 'E'], 30)));
    settle(f, { now: T0 });
    f = flowWithActive(f.save);
    const r = settle(f, { now: T0 + MIN });
    expect([r.windowEnd, r.finale]).toEqual([true, false]);
    expect(f.canResumePlan).toBe(true);
    const next = runGoal(['E', 'E', 'D', 'D'], 30);
    next.plan = [...f.goal.plan, ...next.plan.slice(2).map((t) => ({ ...t }))];
    f.applyNextWindow(next);
    expect(goalFirstOpenIndex(f.goal)).toBe(2);
    expect(f.queue.filter((q) => q.kind === 'main').map((q) => q.planIndex)).toEqual([2, 3]);
  });

  test('兑现单交掉 = finale；下一条主线落库撤掉旧主线单', () => {
    let f = flowWithActive(boundSave(runGoal(['E', 'S'])));
    settle(f, { now: T0 });
    f = flowWithActive(f.save);
    const r = settle(f, { now: T0 + MIN });
    expect(r.finale).toBe(true);
    expect(r.titles).toContain('finale');
    f.applyNextGoal(runGoal(['D', 'C', 'S'], 3, 'g-2'));
    expect(f.queue.filter((q) => q.kind === 'main').map((q) => q.goalId)).toEqual([
      'g-2',
      'g-2',
      'g-2',
    ]);
  });

  test('续拆交回的目标身份不对 → 抛', () => {
    const f = new QuestFlow(boundSave(runGoal(['E'], 10)));
    expect(() => f.applyNextWindow(runGoal(['E', 'E'], 10, 'other'))).toThrow();
  });
});
