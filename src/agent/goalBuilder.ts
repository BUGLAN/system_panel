/**
 * 一次完整的目标铸造 = 匹配（类别 / 短字 / 期限）+ 拆第一个窗口 + 规则校验；
 * 续拆 = 只拆下一个窗口。失败一律抛 PlanFailure（不落库、不改目标）。
 * 移植自 flutter-final main.dart 的 _buildGoalWithAgent / _extendGoalWithAgent。
 */
import { categoryOf } from '../core/goal/categories';
import {
  buildGoalFromPlan,
  extendGoalWithWindow,
  nextPlanWindow,
  planProgressDigest,
  planTaskCountFor,
  planWindowFor,
} from '../core/goal/plan';
import { PlanFailure, type PlanFailureCode } from '../core/goal/planFailure';
import type { Goal } from '../core/model/goal';
import type { LlmClient } from './llmClient';
import type { GoalMatch } from './mainlineTools';
import { generatePlanTasks, matchGoal, type MemoryDigest } from './planAgent';

/** 加载卡的分步进度：0 匹配 → 1 拆解（含段进度）→ 2 校验 */
export interface PlanProgress {
  stage: 0 | 1 | 2;
  segDone?: number;
  segTotal?: number;
}

export interface BuildOptions {
  client: LlmClient;
  text: string;
  at: number;
  firstGoal?: boolean;
  answers?: Record<string, string>;
  /** 绑定仪式里已经匹配过（为了出访谈卡），就不再匹配 */
  match?: GoalMatch;
  statusLine?: string;
  digest?: MemoryDigest;
  onProgress?: (p: PlanProgress) => void;
  signal?: AbortSignal;
}

/** 任何异常都落成可见的 PlanFailure（防止加载卡永远挂着） */
export function asPlanFailure(e: unknown): PlanFailure {
  if (e instanceof PlanFailure) return e;
  return new PlanFailure('badResponse', `意外异常：${e instanceof Error ? e.message : String(e)}`);
}

export async function buildGoalWithAgent(
  o: BuildOptions,
): Promise<{ goal: Goal; line: string | null }> {
  try {
    o.onProgress?.({ stage: 0 });
    const m =
      o.match ??
      (await matchGoal({
        client: o.client,
        goalText: o.text,
        ...(o.statusLine ? { statusLine: o.statusLine } : {}),
        ...(o.digest ? { digest: o.digest } : {}),
        ...(o.signal ? { signal: o.signal } : {}),
      }));
    const window = planWindowFor({
      total: planTaskCountFor(m.days, m.quota),
      firstGoal: o.firstGoal ?? false,
    });
    o.onProgress?.({ stage: 1 });
    const { tasks, line } = await generatePlanTasks({
      client: o.client,
      brief: {
        goalText: o.text,
        days: m.days,
        taskCount: window.size,
        cat: m.cat,
        interview: o.answers ?? {},
        ...(o.statusLine ? { statusLine: o.statusLine } : {}),
        firstGoal: o.firstGoal ?? false,
        window,
      },
      ...(o.digest ? { digest: o.digest } : {}),
      onProgress: (done, total) => o.onProgress?.({ stage: 1, segDone: done, segTotal: total }),
      ...(o.signal ? { signal: o.signal } : {}),
    });
    o.onProgress?.({ stage: 2 });
    const goal = buildGoalFromPlan({
      text: o.text,
      short: m.short,
      cat: m.cat,
      days: m.days,
      quota: m.quota,
      tasks,
      answers: o.answers ?? {},
      at: o.at,
      firstGoal: o.firstGoal ?? false,
    });
    return { goal, line };
  } catch (e) {
    throw asPlanFailure(e);
  }
}

/** 续拆下一段（同一条主线；不再匹配） */
export async function extendGoalWithAgent(o: {
  client: LlmClient;
  goal: Goal;
  now: number;
  statusLine?: string;
  digest?: MemoryDigest;
  onProgress?: (p: PlanProgress) => void;
  signal?: AbortSignal;
}): Promise<Goal> {
  try {
    const g = o.goal;
    const cat = categoryOf(g.cat);
    const window = nextPlanWindow(g);
    o.onProgress?.({ stage: 1 });
    const { tasks } = await generatePlanTasks({
      client: o.client,
      brief: {
        goalText: g.text,
        days: g.days,
        taskCount: window.size,
        cat,
        interview: g.interview,
        ...(o.statusLine ? { statusLine: o.statusLine } : {}),
        firstGoal: false,
        window,
        progress: planProgressDigest(g, o.now),
      },
      ...(o.digest ? { digest: o.digest } : {}),
      onProgress: (done, total) => o.onProgress?.({ stage: 1, segDone: done, segTotal: total }),
      ...(o.signal ? { signal: o.signal } : {}),
    });
    o.onProgress?.({ stage: 2 });
    return extendGoalWithWindow(g, cat, tasks);
  } catch (e) {
    throw asPlanFailure(e);
  }
}

/** 收官后铸下一条主线：沿用上一目标的文本、访谈答案与立目标时刻（O-2） */
export async function mintNextGoal(
  o: Omit<BuildOptions, 'text' | 'at' | 'answers'> & { prev: Goal },
): Promise<Goal> {
  const { goal } = await buildGoalWithAgent({
    ...o,
    text: o.prev.text,
    at: o.prev.at,
    answers: o.prev.interview,
  });
  return goal;
}

// ── 失败卡文案（B1：按失败类型给标题和说明）─────────────────

export function planFailTitle(c: PlanFailureCode): string {
  switch (c) {
    case 'noKey':
      return '还没配 Key';
    case 'noConsent':
      return '还没同意告知';
    case 'network':
      return '网络断了';
    case 'cors':
      return '浏览器拦了跨域';
    case 'timeout':
      return '等太久了';
    case 'httpError':
      return '上游不可用';
    case 'badGoal':
      return '这个目标她不接';
    default:
      return '这次没拆明白';
  }
}

/** 失败时她那句（答案都在 —— 重试不用重答） */
export function planFailLine(c: PlanFailureCode): string {
  switch (c) {
    case 'noKey':
      return '脑子（Key）还没装上。去设置里填好，或者先跳过，目标我记着。';
    case 'noConsent':
      return '你还没点同意，我不会把你的目标发出去。';
    case 'cors':
      return '浏览器把这家服务商挡在外面了。去设置里换一家能直连的，答案我记着。';
    case 'network':
    case 'timeout':
    case 'httpError':
      return '不是你的锅，是上游掉线。答案我都记着，点[重试]就行。';
    case 'badGoal':
      return '这个我不拆。换一个说法，或者换一个目标。';
    default:
      return '这次没拆明白。答案我都记着——[重试]，或者换个说法。';
  }
}
