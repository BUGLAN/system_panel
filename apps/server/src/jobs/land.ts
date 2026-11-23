/**
 * 首目标落库（绑定仪式 / 重试记着的那句）：主线进在手窗口。
 * 移植自前端 store/actions/bind.ts 的 landFirstGoal。前提：拆的这段时间里还没有主线。
 */
import type { StateView } from '@host/core/api/types';
import { PlanFailure } from '@host/core/goal/planFailure';
import type { Goal } from '@host/core/model/goal';
import type { AuthUser } from '../auth/accounts';
import type { Deps } from '../http/context';
import { runFlow } from '../flow/runner';

export async function landFirstGoal(deps: Deps, user: AuthUser, goal: Goal): Promise<StateView> {
  const r = await runFlow(deps, user, (f) => {
    if (f.goal.plan.length > 0)
      throw new PlanFailure('badResponse', '等待期间已经有主线了，这次拆出来的作废了。');
    f.newGoal(goal);
  });
  return r.state;
}
