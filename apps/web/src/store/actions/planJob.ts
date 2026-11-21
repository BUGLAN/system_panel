/**
 * 等 LLM 的整屏加载卡：同一时间只跑一件（防连点），进度跟着服务端真实阶段走。
 *  - withPlanJob：等一个同步请求（匹配类目）
 *  - runServerJob：起一件服务端拆解任务，进度经 SSE 推来（SSE 断了每 3 秒查一次兜底）
 * 中途重置 / 换目标了，迟到的结果按 token 丢弃。
 */
import type { PlanJobKind, PlanJobView, PlanProgress, StateView } from '@host/core/api/types';
import { PlanFailure, type PlanFailureCode } from '@host/core/goal/planFailure';
import { ApiError, api } from '../api';
import { applyState } from '../game';
import { onStream } from '../stream';
import { setUi, uiStore, type PlanJobUi } from '../uiStore';

let token = 0;

export function planBusy(): boolean {
  return uiStore.getState().planJob !== null;
}

/** 跑一件需要等 LLM 的活；已经有一件在跑就返回 null（不收第二次） */
export async function withPlanJob<T>(
  view: Omit<PlanJobUi, 'progress'>,
  work: (onProgress: (p: PlanProgress) => void, isCurrent: () => boolean) => Promise<T>,
): Promise<{ ok: true; value: T } | { ok: false; error: unknown } | null> {
  if (planBusy()) return null;
  const my = ++token;
  setUi({ planJob: { ...view, progress: { stage: 0 } } });
  const onProgress = (p: PlanProgress) => {
    if (my !== token) return;
    const cur = uiStore.getState().planJob;
    if (cur) setUi({ planJob: { ...cur, progress: p } });
  };
  try {
    const value = await work(onProgress, () => my === token);
    if (my !== token) return null;
    return { ok: true, value };
  } catch (error) {
    if (my !== token) return null;
    return { ok: false, error };
  } finally {
    if (my === token) setUi({ planJob: null });
  }
}

/** 作废在跑的那一件（重置存档时） */
export function cancelPlanJob(): void {
  token++;
  setUi({ planJob: null });
}

// ── 服务端拆解任务 ───────────────────────────────────────────

const waiters = new Map<string, (j: PlanJobView) => void>();
const progressOf = new Map<string, (p: PlanProgress) => void>();

onStream({
  job: (j) => {
    progressOf.get(j.id)?.(j.progress);
    if (j.status !== 'running') waiters.get(j.id)?.(j);
  },
});

/** 等一件任务结束：SSE 推结论；同时每 3 秒查一次兜底（SSE 断了也不会卡死） */
export function waitJob(id: string, onProgress?: (p: PlanProgress) => void): Promise<PlanJobView> {
  return new Promise((resolve) => {
    let done = false;
    const finish = (j: PlanJobView) => {
      if (done) return;
      done = true;
      clearInterval(poll);
      waiters.delete(id);
      progressOf.delete(id);
      resolve(j);
    };
    if (onProgress) progressOf.set(id, onProgress);
    waiters.set(id, finish);
    const poll = setInterval(async () => {
      try {
        const r = await api<{ job: PlanJobView }>('GET', `/api/plan/jobs/${id}`);
        onProgress?.(r.job.progress);
        if (r.job.status !== 'running') finish(r.job);
      } catch (e) {
        // 任务没了（服务重启）→ 按「网络断了」失败
        if (e instanceof ApiError && e.status === 404)
          finish({
            id,
            kind: 'bind',
            status: 'failed',
            progress: { stage: 0 },
            failure: { code: 'network', detail: e.message },
            state: null,
            startedAt: 0,
            finishedAt: 0,
          });
      }
    }, 3000);
  });
}

export function failureOf(j: PlanJobView): PlanFailure {
  return new PlanFailure(
    (j.failure?.code ?? 'badResponse') as PlanFailureCode,
    j.failure?.detail ?? '没拆成',
  );
}

/** 起任务并等它结束；成功时把落库后的状态落到本地。抛 PlanFailure = 失败。 */
export async function startServerJob(
  body: { kind: PlanJobKind; text?: string; answers?: Record<string, string> },
  onProgress: (p: PlanProgress) => void,
): Promise<StateView> {
  let job: PlanJobView;
  try {
    job = (await api<{ job: PlanJobView }>('POST', '/api/plan/jobs', body)).job;
  } catch (e) {
    if (e instanceof ApiError && e.offline) throw new PlanFailure('network', e.message);
    if (e instanceof ApiError && e.code === 'crisis') throw new PlanFailure('badGoal', e.message);
    throw new PlanFailure('badResponse', e instanceof Error ? e.message : String(e));
  }
  return finishJob(job, onProgress);
}

/** 等一件已经起了的任务（交单后的续拆、刷新后接上） */
export async function finishJob(
  job: PlanJobView,
  onProgress: (p: PlanProgress) => void,
): Promise<StateView> {
  onProgress(job.progress);
  const done = job.status === 'running' ? await waitJob(job.id, onProgress) : job;
  if (done.status === 'failed') throw failureOf(done);
  if (done.state) applyState(done.state);
  return done.state as StateView;
}

/** 任何异常都落成可见的 PlanFailure（防止加载卡永远挂着） */
export function asFailure(e: unknown): PlanFailure {
  if (e instanceof PlanFailure) return e;
  if (e instanceof ApiError) {
    const f = e.body['failure'] as { code?: string; detail?: string } | undefined;
    if (f?.code) return new PlanFailure(f.code as PlanFailureCode, f.detail ?? e.message);
    if (e.offline) return new PlanFailure('network', e.message);
    if (e.code === 'rate_limited') return new PlanFailure('quota', e.message);
    return new PlanFailure(e.status === 422 ? 'badGoal' : 'httpError', e.message);
  }
  return new PlanFailure('badResponse', `意外异常：${e instanceof Error ? e.message : String(e)}`);
}
