/**
 * 计划规则：总张数、滚动窗口、档位阶梯、分段并行、校验、落成清单、续拆、进度摘要。
 * 移植自 flutter-final:app/lib/state/goal_gen.dart（规则部分）。
 *
 * 拆解只有 LLM 一条路：这里只判规则，任何不合规都抛 PlanRuleError，不修正、不降级。
 */
import type { GoalCategory } from '../data/categoryTypes';
import { RANK_ATTR_POINTS, RANKS, isRank, rankIndex, type Rank } from '../data/rank';
import {
  goalDoneCount,
  goalHasMoreWindows,
  goalPassedDays,
  goalTotalTasks,
  type Goal,
  type PlanTask,
} from '../model/goal';
import { PlanRuleError } from './planFailure';
import { splitAttrs } from './split';

/** 一张任务的原料（= set_plan 工具 item 的形状） */
export interface TaskSpec {
  short: string;
  title: string;
  proof: string;
  minutes: number;
  rank: string;
  /** false = 打卡单；缺省 = 计时单 */
  timed?: boolean;
}

export const PLAN_MIN_TASKS = 2;
export const PLAN_MAX_TASKS = 400;

/** 各档位的时限上限（分钟） */
export function rankCapMinutes(rank: string): number {
  switch (rank) {
    case 'F':
      return 20;
    case 'E':
      return 30;
    case 'D':
      return 40;
    case 'C':
      return 60;
    case 'B':
      return 90;
    case 'A':
      return 120;
    default:
      return 180;
  }
}

/** 首目标第一段允许的档位 */
export const FIRST_GOAL_RANKS: readonly Rank[] = ['E', 'D', 'C'];

/** 期限 / 次数配额 → 整条主线总张数 */
export function planTaskCountFor(days: number, quota = 0): number {
  const n = quota > 0 ? quota : days;
  return Math.min(PLAN_MAX_TASKS, Math.max(PLAN_MIN_TASKS, n));
}

/** 一次拆几张 */
export const PLAN_WINDOW_SIZE = 14;

const LADDER: readonly Rank[] = ['E', 'D', 'C', 'B', 'A'];

function ladderAt(pos: number, total: number): Rank {
  const i = Math.min(
    LADDER.length - 1,
    Math.floor(((pos - 1) * LADDER.length) / Math.max(1, total)),
  );
  return LADDER[i] as Rank;
}

function maxRank(a: Rank, b: Rank): Rank {
  return rankIndex(a) >= rankIndex(b) ? a : b;
}

/** 滚动生成的一个窗口：整条主线里第 from~to 张 */
export interface PlanWindow {
  /** 本窗口第一张在整条主线里的序号（1 基） */
  from: number;
  size: number;
  total: number;
  lo: Rank;
  hi: Rank;
  /** 首目标第一段（只许 E~C、不摆兑现单） */
  firstGoal: boolean;
}

export const windowTo = (w: PlanWindow) => w.from + w.size - 1;
/** 第几段（0 基） */
export const windowIndex = (w: PlanWindow) => Math.floor((w.from - 1) / PLAN_WINDOW_SIZE);
/** 一共几段 */
export const windowCount = (w: PlanWindow) => Math.ceil(w.total / PLAN_WINDOW_SIZE);
/** 收尾那一张就是整条主线的兑现单（必须 S） */
export const windowIsLast = (w: PlanWindow) => windowTo(w) >= w.total && !w.firstGoal;
/** 一次就拆完了整条主线 */
export const windowIsWhole = (w: PlanWindow) => w.from === 1 && w.size >= w.total;

/** 从第 planned + 1 张开始的下一个窗口（档位按在整条主线里的位置取阶梯） */
export function planWindowFor(o: {
  total: number;
  planned?: number;
  firstGoal?: boolean;
  size?: number;
}): PlanWindow {
  const planned = o.planned ?? 0;
  const from = planned + 1;
  const n = Math.max(1, Math.min(o.size ?? PLAN_WINDOW_SIZE, o.total - planned));
  const to = from + n - 1;
  if (o.firstGoal) {
    return { from, size: n, total: o.total, lo: 'E', hi: 'C', firstGoal: true };
  }
  // 只有「一次拆完的短目标」放开到 F
  const lo: Rank = from === 1 && to >= o.total ? 'F' : ladderAt(from, o.total);
  const hi: Rank = to >= o.total ? 'S' : maxRank(ladderAt(to + 1, o.total), lo);
  return { from, size: n, total: o.total, lo, hi, firstGoal: false };
}

/** 目标已经拆到哪了 → 下一个窗口 */
export function nextPlanWindow(g: Goal): PlanWindow {
  return planWindowFor({ total: goalTotalTasks(g), planned: g.plan.length });
}

/** 续拆时告诉模型「前面做到了哪里」 */
export function planProgressDigest(g: Goal, now: number, recent = 8): string {
  const days = g.days <= 0 ? goalTotalTasks(g) : g.days;
  const lines: string[] = [
    `现在是第 ${Math.min(Math.max(1, days), Math.max(1, goalPassedDays(g, now)))}/${days} 天；` +
      `已拆 ${g.plan.length}/${goalTotalTasks(g)} 张，完成 ${goalDoneCount(g)} 张。`,
  ];
  const done = g.plan.filter((x) => x.state === 'done');
  if (done.length) {
    const tail = done.length <= recent ? done : done.slice(done.length - recent);
    lines.push(
      done.length <= recent
        ? '已完成的单：'
        : `最近完成的 ${tail.length} 张（共 ${done.length} 张）：`,
    );
    for (const x of tail) {
      const held = x.heldMs === null ? '' : `，用时 ${Math.floor(x.heldMs / 60_000)} 分钟`;
      lines.push(`- 第 ${x.index + 1} 张 [${x.rank}]「${x.title}」${held}`);
    }
  }
  const last = g.plan[g.plan.length - 1];
  if (last) {
    lines.push(
      `上一段最后一张是第 ${last.index + 1} 张 [${last.rank}]「${last.title}」` +
        `（${last.minutes} 分钟）——强度从这里接着往上走，别重复已经做过的。`,
    );
  }
  return lines.join('\n').trim();
}

// ── 分段并行拆解 ──────────────────────────────────────────

/** 一段最多几张 */
export const PLAN_SEGMENT_SIZE = 12;
/** 同时最多拆几段 */
export const PLAN_SEGMENT_CONCURRENCY = 6;

export interface PlanSegment {
  /** 窗口里第几段（0 基）/ 一共几段 */
  index: number;
  count: number;
  from: number;
  size: number;
  total: number;
  lo: Rank;
  hi: Rank;
  /** 本段收尾那一张是整条主线的兑现单 */
  last: boolean;
}

export const segmentTo = (s: PlanSegment) => s.from + s.size - 1;

/** 阶段提示（让各段的强度曲线接得上） */
export function segmentPhase(s: PlanSegment): string {
  if (s.last) return '冲刺与兑现：强度拉满，最后一张是兑现单';
  const k = (s.from - 1) / Math.max(1, s.total);
  if (k < 0.25) return '起步期：低强度、先把习惯立住';
  if (k < 0.6) return '加量期：在前一段的基础上逐步加码';
  return '强化期：逼近目标强度';
}

/** 窗口 → 段：≤12 张一段；更长的均分，档位在窗口区间里插值（向下取整）、首尾相接 */
export function planSegmentsFor(w: PlanWindow): PlanSegment[] {
  const k = w.size <= PLAN_SEGMENT_SIZE ? 1 : Math.ceil(w.size / PLAN_SEGMENT_SIZE);
  const base = Math.floor(w.size / k);
  const extra = w.size % k;
  const lo = rankIndex(w.lo);
  const hi = rankIndex(w.hi);
  const bound = (j: number): Rank => {
    if (j <= 0) return w.lo;
    if (j >= k) return w.hi;
    return RANKS[lo + Math.floor(((hi - lo) * j) / k)] as Rank;
  };
  const out: PlanSegment[] = [];
  let from = w.from;
  for (let i = 0; i < k; i++) {
    const size = base + (i < extra ? 1 : 0);
    out.push({
      index: i,
      count: k,
      from,
      size,
      total: w.total,
      lo: bound(i),
      hi: bound(i + 1),
      last: windowIsLast(w) && i === k - 1,
    });
    from += size;
  }
  return out;
}

// ── 校验 ──────────────────────────────────────────────────

function validateRange(o: {
  tasks: TaskSpec[];
  from: number;
  lo: Rank;
  hi: Rank;
  last: boolean;
}): void {
  const l = rankIndex(o.lo);
  const h = rankIndex(o.hi);
  o.tasks.forEach((t, i) => {
    const n = o.from + i;
    if (!t.short.trim()) throw new PlanRuleError(`第 ${n} 张的 short 是空的`);
    if (!t.title.trim()) throw new PlanRuleError(`第 ${n} 张的 title 是空的`);
    if (!t.proof.trim()) throw new PlanRuleError(`第 ${n} 张的 proof 是空的`);
    if (!isRank(t.rank)) {
      throw new PlanRuleError(`第 ${n} 张的 rank「${t.rank}」不在 ${RANKS.join('/')} 里`);
    }
    const r = rankIndex(t.rank);
    if (r < l || r > h)
      throw new PlanRuleError(`第 ${n} 张档位 ${t.rank} 不在本段区间 ${o.lo}~${o.hi} 里`);
    const cap = rankCapMinutes(t.rank);
    if (t.minutes < 5 || t.minutes > cap) {
      throw new PlanRuleError(
        `第 ${n} 张「${t.short}」的时限 ${t.minutes} 分钟越界（${t.rank} 档允许 5~${cap}）`,
      );
    }
    const prev = o.tasks[i - 1];
    if (prev && isRank(prev.rank) && r < rankIndex(prev.rank)) {
      throw new PlanRuleError(`第 ${n} 张档位倒退了：${prev.rank} → ${t.rank}（必须低开高走）`);
    }
  });
  const lastTask = o.tasks[o.tasks.length - 1];
  if (o.last && lastTask && lastTask.rank !== 'S') {
    throw new PlanRuleError(
      `第 ${o.from + o.tasks.length - 1} 张是兑现单，必须 S 级，模型给了 ${lastTask.rank}`,
    );
  }
}

export function validatePlanSegment(seg: PlanSegment, tasks: TaskSpec[]): void {
  if (tasks.length !== seg.size) {
    throw new PlanRuleError(
      `第 ${seg.index + 1} 段要正好 ${seg.size} 张（第 ${seg.from}~${segmentTo(seg)} 张），模型给了 ${tasks.length} 张`,
    );
  }
  validateRange({ tasks, from: seg.from, lo: seg.lo, hi: seg.hi, last: seg.last });
}

export function validatePlanWindow(w: PlanWindow, tasks: TaskSpec[]): void {
  if (tasks.length !== w.size) {
    throw new PlanRuleError(
      windowIsWhole(w)
        ? `清单条数必须是 ${w.size} 张，模型给了 ${tasks.length} 张`
        : `这一段要正好 ${w.size} 张（第 ${w.from}~${windowTo(w)} 张），模型给了 ${tasks.length} 张`,
    );
  }
  validateRange({ tasks, from: w.from, lo: w.lo, hi: w.hi, last: windowIsLast(w) });
}

/** 新目标第一个窗口的校验 */
export function validatePlan(o: {
  days: number;
  tasks: TaskSpec[];
  quota?: number;
  firstGoal?: boolean;
}): void {
  if (o.days < PLAN_MIN_TASKS || o.days > PLAN_MAX_TASKS) {
    throw new PlanRuleError(`期限 ${o.days} 天不在 ${PLAN_MIN_TASKS}~${PLAN_MAX_TASKS} 之间`);
  }
  validatePlanWindow(
    planWindowFor({
      total: planTaskCountFor(o.days, o.quota ?? 0),
      firstGoal: o.firstGoal ?? false,
    }),
    o.tasks,
  );
}

/** 已校验的任务池 → 清单（六维按类目倾向与档位点数分配，生成时定死） */
export function buildPlanTasks(o: {
  cat: GoalCategory;
  tasks: TaskSpec[];
  firstGoal?: boolean;
  from?: number;
  total?: number;
}): PlanTask[] {
  const from = o.from ?? 0;
  const total = o.total ?? from + o.tasks.length;
  return o.tasks.map((t, i) => {
    const rank = t.rank as Rank;
    return {
      index: from + i,
      short: t.short,
      title: t.title,
      proof: t.proof,
      minutes: t.minutes,
      rank,
      attrs: splitAttrs(o.cat.tilt, RANK_ATTR_POINTS[rank]),
      state: 'todo',
      // 首目标第一段不摆兑现门；其余整条主线的末张 = 兑现单
      finalTask: !o.firstGoal && from + i === total - 1,
      heldMs: null,
      doneAt: null,
      timed: t.timed ?? true,
      grade: null,
    };
  });
}

/** 用已校验的第一个窗口铸一个目标（计划落库的唯一入口） */
export function buildGoalFromPlan(o: {
  text: string;
  short: string;
  cat: GoalCategory;
  days: number;
  quota?: number;
  tasks: TaskSpec[];
  answers?: Record<string, string>;
  at: number;
  uid?: string;
  firstGoal?: boolean;
}): Goal {
  const clean = o.text.trim();
  if (!clean) throw new PlanRuleError('目标文本是空的');
  const quota = o.quota ?? 0;
  validatePlan({ days: o.days, tasks: o.tasks, quota, firstGoal: o.firstGoal ?? false });
  const total = planTaskCountFor(o.days, quota);
  return {
    text: clean,
    short: o.short.trim() || clean,
    at: o.at,
    plan: buildPlanTasks({ cat: o.cat, tasks: o.tasks, firstGoal: o.firstGoal ?? false, total }),
    cat: o.cat.id,
    days: o.days,
    interview: { ...(o.answers ?? {}) },
    uid: o.uid ?? '',
    planTotal: total,
    quota,
  };
}

/** 续拆：把下一个窗口的任务接到清单后面（身份、期限、总张数都不变） */
export function extendGoalWithWindow(g: Goal, cat: GoalCategory, tasks: TaskSpec[]): Goal {
  if (!goalHasMoreWindows(g)) {
    throw new Error(`目标「${g.text}」已经拆满 ${goalTotalTasks(g)} 张，没有下一段`);
  }
  validatePlanWindow(nextPlanWindow(g), tasks);
  return {
    ...g,
    plan: [
      ...g.plan,
      ...buildPlanTasks({ cat, tasks, from: g.plan.length, total: goalTotalTasks(g) }),
    ],
  };
}
