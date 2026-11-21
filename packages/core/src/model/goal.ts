/**
 * 目标 = 一句话 + 期限 + 任务清单（滚动生成：清单里只有已拆出来的窗口）。
 * 移植自 flutter-final:app/lib/state/goal.dart。
 */
import type { AttrMap } from '../data/attrs';
import { isGrade, type Grade, type Rank } from '../data/rank';
import {
  arr,
  attrMap,
  bool,
  int,
  intOrNull,
  isObj,
  rank,
  str,
  strMap,
  strOrNull,
  type Json,
} from '../save/json';

/** todo 待发布 / 在队列等接；active 正在执行；done 已完成；abandoned 随放弃主线作废 */
export type PlanState = 'todo' | 'active' | 'done' | 'abandoned';

export interface PlanTask {
  /** 清单内序号（0 基） */
  index: number;
  /** 短名（节点轨 / 大牌角标） */
  short: string;
  title: string;
  proof: string;
  minutes: number;
  rank: Rank;
  attrs: AttrMap;
  state: PlanState;
  /** 兑现单：它完成 = 目标完成 */
  finalTask: boolean;
  /** 已完成：用时（毫秒）/ 完成时刻（epoch ms） */
  heldMs: number | null;
  doneAt: number | null;
  timed: boolean;
  /** 结算时落库的评级（S/A/B/C，与结算页同一口径） */
  grade: Grade | null;
}

export interface Goal {
  text: string;
  short: string;
  /** 立目标的时刻（epoch ms） */
  at: number;
  plan: PlanTask[];
  /** 类目 id：run/slim/fit/lang/exam/sleep/skill/make/code/bold/gen */
  cat: string;
  /** 期限（天） */
  days: number;
  /** 访谈答案（卡 id → 答案原文） */
  interview: Record<string, string>;
  /** 显式身份；一般留空，按立目标时刻推 */
  uid: string;
  /** 整条主线一共几张（滚动生成时 > plan.length） */
  planTotal: number;
  /** 目标自带的次数配额（0 = 没有） */
  quota: number;
}

const PLAN_STATES: readonly PlanState[] = ['todo', 'active', 'done', 'abandoned'];

export function goalId(g: Goal): string {
  return g.uid || `g${g.at}`;
}

/** 未绑定 = 没有清单 */
export function goalIsEmpty(g: Goal): boolean {
  return g.plan.length === 0;
}

export function planTaskOpen(t: PlanTask): boolean {
  return t.state === 'todo' || t.state === 'active';
}

export function goalDoneCount(g: Goal): number {
  return g.plan.filter((t) => t.state === 'done').length;
}

/** 整条主线总张数（进度分母）：滚动生成时 > 已拆出来的 plan.length */
export function goalTotalTasks(g: Goal): number {
  return g.planTotal > g.plan.length ? g.planTotal : g.plan.length;
}

/** 还有没拆出来的窗口 */
export function goalHasMoreWindows(g: Goal): boolean {
  return g.planTotal > g.plan.length;
}

/** 清单里第一张还没做完的（-1 = 全部走完） */
export function goalFirstOpenIndex(g: Goal): number {
  return g.plan.findIndex(planTaskOpen);
}

/** 已拆出来的都走完、整条主线还没完 —— 该续拆了 */
export function goalWindowExhausted(g: Goal): boolean {
  return goalHasMoreWindows(g) && goalFirstOpenIndex(g) < 0;
}

export function goalTaskAt(g: Goal, i: number): PlanTask | undefined {
  return i >= 0 && i < g.plan.length ? g.plan[i] : undefined;
}

function startOfDayMs(ms: number): number {
  const d = new Date(ms);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
}

/** 已过天数（第 1 天 = 立目标当天） */
export function goalPassedDays(g: Goal, now: number): number {
  const d = Math.round((startOfDayMs(now) - startOfDayMs(g.at)) / 86_400_000) + 1;
  return d < 1 ? 1 : d;
}

/** 剩余天数（可以为负 = 已超期） */
export function goalRemainingDays(g: Goal, now: number): number {
  return g.days - goalPassedDays(g, now);
}

/** 「3 月 5 日」 */
export function goalStartedText(g: Goal): string {
  const d = new Date(g.at);
  return `${d.getMonth() + 1} 月 ${d.getDate()} 日`;
}

export function emptyGoal(now: number): Goal {
  return {
    text: '',
    short: '',
    at: now,
    plan: [],
    cat: '',
    days: 0,
    interview: {},
    uid: '',
    planTotal: 0,
    quota: 0,
  };
}

export function planTaskToJson(t: PlanTask): Json {
  return {
    index: t.index,
    short: t.short,
    title: t.title,
    proof: t.proof,
    minutes: t.minutes,
    ...(t.timed ? {} : { mode: 'checkin' }),
    rank: t.rank,
    ...(Object.keys(t.attrs).length ? { attrs: { ...t.attrs } } : {}),
    state: t.state,
    final: t.finalTask,
    ...(t.heldMs !== null ? { heldMs: t.heldMs } : {}),
    ...(t.doneAt !== null ? { doneAt: t.doneAt } : {}),
    ...(t.grade !== null ? { grade: t.grade } : {}),
  };
}

export function planTaskFromJson(v: unknown, index: number): PlanTask | null {
  if (!isObj(v)) return null;
  const state = str(v, 'state', 'todo');
  const grade = strOrNull(v, 'grade');
  return {
    index: int(v, 'index', index),
    short: str(v, 'short', ''),
    title: str(v, 'title', ''),
    proof: str(v, 'proof', ''),
    minutes: int(v, 'minutes', 0),
    rank: rank(v, 'rank', 'F'),
    attrs: attrMap(v, 'attrs', {}),
    state: (PLAN_STATES as readonly string[]).includes(state) ? (state as PlanState) : 'todo',
    finalTask: bool(v, 'final', false),
    heldMs: intOrNull(v, 'heldMs'),
    doneAt: intOrNull(v, 'doneAt'),
    timed: v['mode'] !== 'checkin',
    grade: isGrade(grade) ? grade : null,
  };
}

export function goalToJson(g: Goal): Json {
  return {
    text: g.text,
    short: g.short,
    at: g.at,
    cat: g.cat,
    days: g.days,
    interview: { ...g.interview },
    ...(g.uid ? { uid: g.uid } : {}),
    ...(g.planTotal > 0 ? { planTotal: g.planTotal } : {}),
    ...(g.quota > 0 ? { quota: g.quota } : {}),
    plan: g.plan.map(planTaskToJson),
  };
}

/** 没有清单 = 未绑定（给空目标）；字段缺 / 类型不对走默认 */
export function goalFromJson(v: unknown, now: number): Goal {
  if (!isObj(v)) return emptyGoal(now);
  const plan = arr(v, 'plan')
    .map((t, i) => planTaskFromJson(t, i))
    .filter((t): t is PlanTask => t !== null);
  if (plan.length === 0) return emptyGoal(now);
  const days = int(v, 'days', 0);
  return {
    text: str(v, 'text', ''),
    short: str(v, 'short', ''),
    at: int(v, 'at', now),
    plan,
    cat: str(v, 'cat', ''),
    days: days < 1 ? plan.length : days,
    interview: strMap(v, 'interview', {}),
    uid: str(v, 'uid', ''),
    planTotal: int(v, 'planTotal', 0),
    quota: int(v, 'quota', 0),
  };
}
