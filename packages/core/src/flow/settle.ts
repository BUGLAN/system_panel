/**
 * 结算 / 认输 / 超时（护盾）。移植自 flutter-final QuestFlow.settle / fail。
 *
 * 结算时序（G4.1）：入账 → 清执行中 → 补发 → 记流水，这一单到此结清；
 * 窗口走完 / 收官只在结果里打标记（windowEnd / finale），续拆与铸下一条主线由调用方
 * 先落盘、再 await 拆解、拆好后用 applyNextWindow / applyNextGoal 接上。
 */
import { RANK_ATTR_POINTS, rankShift } from '../data/rank';
import { needFor, payout } from '../data/rewards';
import { splitAttrs } from '../goal/split';
import type { ActiveQuest } from '../model/active';
import type { Quest } from '../model/quest';
import { goalHasMoreWindows, goalId, goalTaskAt, goalWindowExhausted } from '../model/goal';
import { addDays, dayKey } from '../time/day';
import { QuestFlow } from './questFlow';
import { gradeOf } from './questText';
import type { FailOutcome, QuestResult, TimeoutOutcome } from './types';

/** 计时单的截止时刻（含护盾顺延） */
export function deadlineOf(a: ActiveQuest): number {
  return a.startAt + a.task.minutes * 60_000 + a.extraMs;
}

/** 结算。没有执行中的单 → 抛（不许把「没结算」伪装成「结算成功」） */
export function settle(f: QuestFlow, o: { now: number; forceCrit?: boolean }): QuestResult {
  const a = f.active;
  if (!a) throw new Error('settle：没有正在执行的单，没有可结算的东西');
  const t0 = o.now;
  const task = a.task;
  const heldMs = Math.max(0, t0 - a.startAt);
  // 交单即封存，并在这一刻取证据读数
  a.sealed = true;
  const photos = a.evidence.length;
  const verified = a.evidence.filter((e) => e.status === 'verified').length;

  const chance = f.critChance();
  const roll = f.rnd();
  const crit = o.forceCrit ?? roll < chance;
  const near = !crit && roll - chance < 0.08 ? Math.max(1, Math.round((roll - chance) * 100)) : 0;

  const remedy = task.kind === 'remedy';
  const p = payout({ rank: task.rank, crit, dbl: a.dbl, remedy });
  const host = f.host;
  const beforeLv = host.lv;
  const beforeExp = host.exp;
  const beforeNeed = needFor(beforeLv);

  // 经验入账 + 升级循环
  let lv = beforeLv;
  let cur = beforeExp + p.exp;
  const ups: number[] = [];
  while (cur >= needFor(lv)) {
    cur -= needFor(lv);
    lv++;
    ups.push(lv);
  }
  host.lv = lv;
  host.exp = cur;
  host.coins += p.coin;
  host.totalExp += p.exp;

  // 六维
  for (const [k, v] of Object.entries(task.attrs) as Array<[keyof typeof host.attrs, number]>) {
    host.attrs[k] = (host.attrs[k] ?? 0) + v;
  }

  // 连胜：今天第一单才 +1；昨天也完成过 = 接上，否则从 1 起
  const today = dayKey(t0, f.tz);
  const m = f.meta;
  let streakUp = false;
  if (m.lastDoneDay !== today) {
    const consecutive = m.lastDoneDay === addDays(today, -1);
    host.streak = consecutive ? host.streak + 1 : 1;
    host.bestStreak = Math.max(host.bestStreak, host.streak);
    streakUp = true;
  }
  m.lastDoneDay = today;

  host.doneCount += 1;
  if (crit) host.critCount += 1;

  const grade = gradeOf({
    timed: task.timed,
    minutes: task.minutes,
    heldMs,
    verified,
    photos,
    crit,
  });

  // 计划：划掉这一张；顶替某一环的补救单交掉 = 这一环过关
  let planClear = -1;
  let finale = false;
  let windowEnd = false;
  const planSlot = task.kind === 'main' || f.isPlanRemedy(task);
  const g = f.goal;
  if (
    planSlot &&
    task.planIndex >= 0 &&
    task.goalId === goalId(g) &&
    goalTaskAt(g, task.planIndex)
  ) {
    const pt = g.plan[task.planIndex];
    if (pt && pt.state !== 'done') {
      g.plan[task.planIndex] = { ...pt, state: 'done', heldMs, doneAt: t0, grade };
      planClear = task.planIndex;
      const allDone = g.plan.every((x) => x.state === 'done');
      finale = pt.finalTask || (allDone && !goalHasMoreWindows(g));
      windowEnd = !finale && goalWindowExhausted(g);
    }
  }

  // 称号
  const titles: string[] = [];
  const add = (id: string) => {
    if (!host.ownedTitles.includes(id) && !titles.includes(id)) titles.push(id);
  };
  if (host.doneCount >= 1) add('first');
  if (crit) add('crit');
  if (host.doneCount >= 5) add('done5');
  if (remedy) add('redeem');
  if (host.streak >= 3) add('streak3');
  if (task.rank === 'A') add('rankA');
  if (host.doneCount >= 15) add('done15');
  if (host.streak >= 7) add('streak7');
  if (task.rank === 'S') add('rankS');
  if (finale) add('finale');
  // 「口头巨人」强制期结束：交成一单 → 换回之前的称号
  if (host.title === 'mouth' && m.titleBeforeShame !== null) {
    host.title = m.titleBeforeShame;
    m.titleBeforeShame = null;
  }
  if (titles.length) {
    host.ownedTitles = [...new Set([...host.ownedTitles, ...titles])];
    if (host.title !== 'mouth') host.title = titles[titles.length - 1] as string;
  }

  // 结清：清掉执行中，再补一张（窗口把执行中的那张也算在内，必须放在清空之后）
  f.active = null;
  if (!finale && planSlot) f.publishPlanTasks();

  f.history.push({
    at: t0,
    name: task.name,
    rank: task.rank,
    kind: task.kind,
    exp: p.exp,
    coin: p.coin,
    streak: host.streak,
    result: 'clear',
    attrs: { ...task.attrs },
  });
  f.notify();

  return {
    quest: task,
    beforeLv,
    beforeExp,
    beforeNeed,
    baseExp: p.baseExp,
    exp: p.exp,
    coin: p.coin,
    attrs: { ...task.attrs },
    streak: host.streak,
    streakUp,
    crit,
    dbl: a.dbl,
    photos,
    verified,
    chance,
    near,
    ups,
    titles,
    planClear,
    finale,
    windowEnd,
    windowNext: false,
    redeemed: remedy,
    empty: f.queue.length === 0,
    tooFast: task.timed && heldMs < 60_000,
    heldMs,
    afterLv: lv,
    afterNeed: needFor(lv),
    endExp: cur,
    grade,
  };
}

/**
 * 认输 / 超时。打卡单不判超时（返回 null、什么都不动）。
 * 主线认输：补救单顶替这一环（继承 goalId / planIndex，当场入队）；
 * 顶替的补救单再认输 → 那一格空出、原单补回。认输不断连胜（C6）。
 */
export function fail(
  f: QuestFlow,
  o: { now: number; how?: 'quit' | 'timeout' },
): FailOutcome | null {
  const a = f.active;
  if (!a) return null;
  const how = o.how ?? 'quit';
  if (how === 'timeout' && !a.task.timed) return null;
  const task = a.task;
  const heldMs = Math.max(0, o.now - a.startAt);
  f.host.failCount += 1;

  const mainSlot = task.kind === 'main' && task.goalId === goalId(f.goal);
  let remedy: Quest | null = null;
  let deadline: number | null = null;
  if (task.kind !== 'remedy') {
    const rr = rankShift(task.rank, -2);
    remedy = {
      serial: f.nextSerial(),
      kind: 'remedy',
      planIndex: mainSlot ? task.planIndex : -1,
      planTotal: mainSlot ? task.planTotal : 0,
      goalId: mainSlot ? task.goalId : '',
      name: `${task.name}（简化版）`,
      reason: f.reasonForRemedy(),
      proof: task.proof,
      minutes: Math.max(5, Math.ceil(task.minutes / 2)),
      rank: rr,
      attrs: splitAttrs(task.attrs, RANK_ATTR_POINTS[rr]),
      hinted: false,
      timed: task.timed,
    };
    deadline = o.now + 24 * 3_600_000;
    f.meta.remedyOffer = remedy;
    f.meta.remedyDeadline = deadline;
    // 顶替主线的补救单当场入队（停在失败页时杀进程也不丢这一环）
    if (mainSlot) f.queue.unshift(remedy);
  }
  const wasPlanRemedy = f.isPlanRemedy(task);
  f.active = null;
  if (wasPlanRemedy) f.publishPlanTasks();

  f.history.push({
    at: o.now,
    name: task.name,
    rank: task.rank,
    kind: task.kind,
    exp: 0,
    coin: 0,
    streak: f.host.streak,
    result: how,
    attrs: {},
  });
  f.notify();
  return { task, heldMs, how, remedy, remedyDeadline: deadline };
}

/**
 * 计时单到点了吗（每秒检查）：没到 / 打卡单 → none；装着护盾 → 护盾碎掉、
 * 顺延 ceil(时长 ÷ 2) 分钟（docs/01 Q3）；否则超时判负。
 */
export function checkTimeout(f: QuestFlow, now: number): TimeoutOutcome {
  const a = f.active;
  if (!a || a.sealed || !a.task.timed) return { kind: 'none' };
  if (now < deadlineOf(a)) return { kind: 'none' };
  if (a.shield) {
    const extendMin = Math.ceil(a.task.minutes / 2);
    a.shield = false;
    a.extraMs += extendMin * 60_000;
    f.notify();
    return { kind: 'shield', extendMin };
  }
  const outcome = fail(f, { now, how: 'timeout' });
  return outcome ? { kind: 'fail', outcome } : { kind: 'none' };
}
