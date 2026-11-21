/**
 * 首目标落库（绑定仪式 / 重试记着的那句）：主线进在手 + 当天日常（还没有的话）+ 见面礼 + 访谈记忆。
 * 移植自前端 store/actions/bind.ts 的 landFirstGoal。前提：拆的这段时间里还没有主线。
 */
import type { StateView } from '@host/core/api/types';
import { applyBindGift, categoryOf, memoriesFromInterview } from '@host/core/goal/categories';
import { PlanFailure } from '@host/core/goal/planFailure';
import type { Goal } from '@host/core/model/goal';
import { dayKey } from '@host/core/time/day';
import type { MemoryStore } from '../agent/memory';
import type { AuthUser } from '../auth/accounts';
import type { Deps } from '../http/context';
import { runFlow } from '../flow/runner';

export async function landFirstGoal(
  deps: Deps,
  user: AuthUser,
  goal: Goal,
  answers: Record<string, string>,
  mem: MemoryStore,
): Promise<StateView> {
  const r = await runFlow(deps, user, (f, now) => {
    if (f.goal.plan.length > 0)
      throw new PlanFailure('badResponse', '等待期间已经有主线了，这次拆出来的作废了。');
    const live = f.queue.length > 0 || f.save.pendingGoal.length > 0;
    f.newGoal(goal);
    if (!live) f.queue.push(...f.genTodaysDailies());
    f.host.items = applyBindGift(f.host.items);
    f.meta.lastRollDay = dayKey(now, user.tz);
    f.notify();
  });
  if (Object.keys(answers).length) {
    const cat = categoryOf(goal.cat);
    for (const text of memoriesFromInterview({
      cat,
      answers,
      goalText: goal.text,
      days: goal.days,
    }))
      await mem.add(text, 'interview', 2).catch(() => undefined);
  }
  return r.state;
}
