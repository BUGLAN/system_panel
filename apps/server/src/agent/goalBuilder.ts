/**
 * 一次完整的目标铸造 = 匹配（类别 / 短字 / 期限）+ 拆第一个窗口 + 规则校验；
 * 续拆 = 只拆下一个窗口。失败一律抛 PlanFailure（不落库、不改目标）。
 * 移植自 flutter-final main.dart 的 _buildGoalWithAgent / _extendGoalWithAgent。
 */
import { categoryOf } from '@host/core/goal/categories';
import {
  buildGoalFromPlan,
  extendGoalWithWindow,
  nextPlanWindow,
  planProgressDigest,
  planTaskCountFor,
  planWindowFor,
} from '@host/core/goal/plan';
import { PlanFailure } from '@host/core/goal/planFailure';
import type { Goal } from '@host/core/model/goal';
import type { LlmClient } from './llmClient';
import type { GoalMatch } from './mainlineTools';
import { generatePlanTasks, matchGoal } from './planAgent';

import type { PlanProgress } from '@host/core/api/types';

export type { PlanProgress };

export interface BuildOptions {
  client: LlmClient;
  text: string;
  at: number;
  firstGoal?: boolean;
  answers?: Record<string, string>;
  /** 绑定仪式里已经匹配过（为了出访谈卡），就不再匹配 */
  match?: GoalMatch;
  statusLine?: string;
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
      onProgress: (done, total) => o.onProgress?.({ stage: 1, segDone: done, segTotal: total }),
      ...(o.signal ? { signal: o.signal } : {}),
    });
    o.onProgress?.({ stage: 2 });
    return extendGoalWithWindow(g, tasks);
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

// 失败卡文案前后端共用，放在 core
export { planFailLine, planFailTitle } from '@host/core/goal/planFailCopy';
