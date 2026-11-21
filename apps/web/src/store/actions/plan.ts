/**
 * 大厅 / 主线页的「重试拆解」：
 *  - C5：没主线、记着一句目标 → 走首目标拆解（成功补发见面礼，D1.2）
 *  - D3.2：清单走完、下一段 / 下一条主线没拆上 → 续拆或铸下一条
 * 以及结算后的跟进（窗口走完续拆、收官铸下一条），失败一律可见、不留可再交的单。
 */
import {
  asPlanFailure,
  buildGoalWithAgent,
  extendGoalWithAgent,
  mintNextGoal,
} from '../../agent/goalBuilder';
import { statusLineOf } from '../../agent/chatTools';
import type { PlanFailure } from '@host/core/goal/planFailure';
import { goalWindowExhausted } from '@host/core/model/goal';
import { sfx } from '../../audio/sfx';
import { game, now, runFlow } from '../game';
import { memory, textClientAny } from '../services';
import { sayHome, sayMain, toast } from '../uiStore';
import { landFirstGoal, resetBind } from './bind';
import { withPlanJob } from './planJob';

const digest = (q: string) => memory().digest(q);

/** C5：用记着的那句目标重走首目标拆解 */
export async function retryPendingPlan(): Promise<void> {
  const text = game().pendingGoal;
  if (!text) return;
  resetBind();
  const r = await withPlanJob({ kind: 'retry', title: '重试拆解' }, (onProgress) =>
    buildGoalWithAgent({
      client: textClientAny(),
      text,
      at: now(),
      firstGoal: true,
      digest,
      onProgress,
    }),
  );
  if (!r) return;
  if (!r.ok) {
    sfx.play('error');
    const e = asPlanFailure(r.error);
    toast(`还是没拆成：${e.detail.slice(0, 40)}`, 'err');
    sayHome('又没拆成。目标我还记着，[等会儿再试]，日常先做着。');
    return;
  }
  await landFirstGoal(r.value.goal, {});
}

/** 续拆下一段 / 铸下一条主线；返回失败（null = 成功或没得拆） */
export async function followUpPlan(kind: 'window' | 'finale'): Promise<PlanFailure | null> {
  const r = await withPlanJob(
    kind === 'window'
      ? { kind: 'window', title: '这一段走完了' }
      : { kind: 'finale', title: '下一条主线' },
    async (onProgress) => {
      const g = game();
      const statusLine = statusLineOf(g);
      if (kind === 'window') {
        return {
          kind,
          goal: await extendGoalWithAgent({
            client: textClientAny(),
            goal: g.goal,
            now: now(),
            statusLine,
            digest,
            onProgress,
          }),
        };
      }
      return {
        kind,
        goal: await mintNextGoal({
          client: textClientAny(),
          prev: g.goal,
          statusLine,
          digest,
          onProgress,
        }),
      };
    },
  );
  if (!r) return null;
  if (!r.ok) return asPlanFailure(r.error);
  const { goal } = r.value;
  runFlow((f) => {
    if (kind === 'window') f.applyNextWindow(goal);
    else f.applyNextGoal(goal);
  });
  sfx.play('unlock');
  return null;
}

/** D3.2：会话里当场补拆 */
export async function resumePlan(): Promise<void> {
  const g = game();
  if (g.active || g.goal.plan.length === 0) return;
  const kind = goalWindowExhausted(g.goal) ? 'window' : 'finale';
  const err = await followUpPlan(kind);
  if (err) {
    sfx.play('error');
    toast(`没拆成：${err.detail.slice(0, 40)}`, 'err');
    sayHome('下一段还是没拆出来。[等会儿再试]。');
    sayMain('下一段还是没拆出来。[等会儿再试]。');
    return;
  }
  const n = game().goal.plan.length;
  toast(kind === 'window' ? '下一段拆好了。' : '下一条主线排好了。', 'ok');
  sayHome(`接上了。清单现在 [[${n}]] 张。`);
}
