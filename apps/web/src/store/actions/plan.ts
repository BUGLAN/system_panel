/**
 * 大厅 / 主线页的「重试拆解」与结算后的跟进（拆解都在服务端跑，这里只管加载卡和她那句）：
 *  - C5：没主线、记着一句目标 → 服务端走首目标拆解（成功补发见面礼，D1.2）
 *  - D3.2：清单走完、下一段 / 下一条主线没拆上 → 服务端续拆或铸下一条
 *  - 交单后窗口走完 / 收官：服务端已经起了任务，这里等它
 */
import type { PlanJobView } from '@host/core/api/types';
import type { PlanFailure } from '@host/core/goal/planFailure';
import { api } from '../api';
import { game } from '../game';
import { sayHome, sayMain, toast } from '../uiStore';
import { afterFirstGoal, resetBind } from './bind';
import { asFailure, finishJob, startServerJob, withPlanJob } from './planJob';

/** C5：用记着的那句目标重走首目标拆解 */
export async function retryPendingPlan(): Promise<void> {
  if (!game().pendingGoal) return;
  resetBind();
  const r = await withPlanJob({ kind: 'retry', title: '重试拆解' }, (onProgress) =>
    startServerJob({ kind: 'retry' }, onProgress),
  );
  if (!r) return;
  if (!r.ok) {
    const e = asFailure(r.error);
    toast(`还是没拆成：${e.detail.slice(0, 40)}`, 'err');
    sayHome('又没拆成。目标我还记着，[等会儿再试]。');
    return;
  }
  await afterFirstGoal();
}

/** 交单后：等服务端的续拆 / 收官任务；返回失败（null = 成功） */
export async function awaitFollowUp(
  jobId: string,
  kind: 'window' | 'finale',
): Promise<PlanFailure | null> {
  const r = await withPlanJob(
    kind === 'window'
      ? { kind: 'window', title: '这一段走完了' }
      : { kind: 'finale', title: '下一条主线' },
    async (onProgress) => {
      const job: PlanJobView = {
        id: jobId,
        kind,
        status: 'running',
        progress: { stage: 1 },
        failure: null,
        state: null,
        startedAt: 0,
        finishedAt: null,
      };
      return finishJob(job, onProgress);
    },
  );
  if (!r) return null;
  if (!r.ok) return asFailure(r.error);
  return null;
}

/** D3.2：会话里当场补拆 */
export async function resumePlan(): Promise<void> {
  const g = game();
  if (g.active || g.goal.plan.length === 0) return;
  const r = await withPlanJob({ kind: 'window', title: '这一段走完了' }, (onProgress) =>
    startServerJob({ kind: 'resume' }, onProgress),
  );
  if (!r) return;
  if (!r.ok) {
    const err = asFailure(r.error);
    toast(`没拆成：${err.detail.slice(0, 40)}`, 'err');
    sayHome('下一段还是没拆出来。[等会儿再试]。');
    sayMain('下一段还是没拆出来。[等会儿再试]。');
    return;
  }
  const n = game().goal.plan.length;
  const sameGoal = game().goal.at === g.goal.at;
  toast(sameGoal ? '下一段拆好了。' : '下一条主线排好了。', 'ok');
  sayHome(`接上了。清单现在 [[${n}]] 张。`);
}

/** 刷新页面时有一件拆解还在跑：接上加载卡，等它结束后拉一次状态 */
export async function resumeRunningJob(): Promise<'done' | 'failed' | null> {
  let job: PlanJobView | null;
  try {
    job = (await api<{ job: PlanJobView | null }>('GET', '/api/plan/jobs/current')).job;
  } catch {
    return null;
  }
  if (!job || job.status !== 'running') return null;
  const kind = job.kind === 'resume' ? 'window' : job.kind;
  const r = await withPlanJob({ kind, title: '她还在拆' }, (onProgress) =>
    finishJob(job, onProgress),
  );
  return r?.ok ? 'done' : 'failed';
}
