/**
 * 等 LLM 的整屏加载卡：同一时间只跑一件（防连点），进度跟着真实阶段走。
 * 中途重置 / 换目标了，迟到的回包按 token 丢弃。
 */
import type { PlanProgress } from '../../agent/goalBuilder';
import { setUi, uiStore, type PlanJobView } from '../uiStore';

let token = 0;

export function planBusy(): boolean {
  return uiStore.getState().planJob !== null;
}

/** 跑一件需要等 LLM 的活；已经有一件在跑就返回 null（不收第二次） */
export async function withPlanJob<T>(
  view: Omit<PlanJobView, 'progress'>,
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
    return { ok: true, value };
  } catch (error) {
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
