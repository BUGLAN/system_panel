/**
 * 结算。移植自 flutter-final QuestFlow.settle（暴击、道具、晶核、六维、称号、评级都已拿掉）。
 *
 * 结算时序（G4.1）：入账 → 清执行中 → 补发 → 记流水，这一单到此结清；
 * 窗口走完 / 收官只在结果里打标记（windowEnd / finale），续拆与铸下一条主线由调用方
 * 先落盘、再 await 拆解、拆好后用 applyNextWindow / applyNextGoal 接上。
 */
import { expFor, needFor } from '../data/rewards';
import { goalHasMoreWindows, goalWindowExhausted } from '../model/goal';
import { addDays, dayKey } from '../time/day';
import { planSlotOf, type QuestFlow } from './questFlow';
import type { QuestResult } from './types';

/** 结算。没有执行中的单 → 抛（不许把「没结算」伪装成「结算成功」） */
export function settle(f: QuestFlow, o: { now: number }): QuestResult {
  const a = f.active;
  if (!a) throw new Error('settle：没有正在执行的单，没有可结算的东西');
  const t0 = o.now;
  const task = a.task;
  const heldMs = Math.max(0, t0 - a.startAt);
  // 交单即封存，并在这一刻取证据读数
  a.sealed = true;
  const photos = a.evidence.length;
  const verified = a.evidence.filter((e) => e.status === 'verified').length;

  const exp = expFor(task.rank);
  const host = f.host;
  const beforeLv = host.lv;
  const beforeExp = host.exp;
  const beforeNeed = needFor(beforeLv);

  // 经验入账 + 升级循环
  let lv = beforeLv;
  let cur = beforeExp + exp;
  const ups: number[] = [];
  while (cur >= needFor(lv)) {
    cur -= needFor(lv);
    lv++;
    ups.push(lv);
  }
  host.lv = lv;
  host.exp = cur;
  host.totalExp += exp;

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

  // 计划：划掉这一张
  let planClear = -1;
  let finale = false;
  let windowEnd = false;
  const g = f.goal;
  const slot = planSlotOf(g, task);
  const pt = slot >= 0 ? g.plan[slot] : undefined;
  if (pt && pt.state !== 'done') {
    g.plan[slot] = { ...pt, state: 'done', heldMs, doneAt: t0 };
    planClear = slot;
    const allDone = g.plan.every((x) => x.state === 'done');
    finale = pt.finalTask || (allDone && !goalHasMoreWindows(g));
    windowEnd = !finale && goalWindowExhausted(g);
  }

  // 结清：清掉执行中，再补一张（窗口把执行中的那张也算在内，必须放在清空之后）
  f.active = null;
  if (!finale) f.publishPlanTasks();

  f.history.push({
    at: t0,
    name: task.name,
    rank: task.rank,
    exp,
    streak: host.streak,
    result: 'clear',
  });
  f.notify();

  return {
    quest: task,
    beforeLv,
    beforeExp,
    beforeNeed,
    exp,
    streak: host.streak,
    streakUp,
    photos,
    verified,
    ups,
    planClear,
    finale,
    windowEnd,
    windowNext: false,
    empty: f.queue.length === 0,
    heldMs,
    afterLv: lv,
    afterNeed: needFor(lv),
    endExp: cur,
  };
}
