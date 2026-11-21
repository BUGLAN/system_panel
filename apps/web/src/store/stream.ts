/**
 * 实时通道（SSE /api/stream）：别处改了存档 → 拉新状态；拆解进度；视觉校验结论。
 * 页面切后台就断开（省电、iOS 也会掐），回前台重连并拉一次状态补齐。
 */
import type { PlanJobView, VerdictEvent } from '@host/core/api/types';
import { refreshState, syncStore, writesInFlight } from './game';

type Handlers = {
  job?: (j: PlanJobView) => void;
  verdict?: (v: VerdictEvent) => void;
  /** 别处改了存档、本地已同步（前一刻的执行中单据 serial，没有 = null） */
  remote?: (prevActive: number | null) => void;
};
const handlers: Handlers = {};
export function onStream(h: Handlers): void {
  Object.assign(handlers, h);
}

let es: EventSource | null = null;
let refreshTimer: ReturnType<typeof setTimeout> | null = null;
let activeOf: () => number | null = () => null;

/** 注入「当前执行中单据」的读法（避免循环依赖） */
export function setActiveReader(fn: () => number | null): void {
  activeOf = fn;
}

function scheduleRefresh(version: number): void {
  if (refreshTimer) clearTimeout(refreshTimer);
  refreshTimer = setTimeout(async () => {
    refreshTimer = null;
    // 自己的写请求还没回来：等它回来再比，免得把自己的操作当成「别处改的」
    if (writesInFlight() > 0) return scheduleRefresh(version);
    if (version <= syncStore.getState().version) return;
    const prev = activeOf();
    await refreshState();
    handlers.remote?.(prev);
  }, 150);
}

export function openStream(): void {
  if (es || typeof EventSource === 'undefined' || !syncStore.getState().me) return;
  es = new EventSource('/api/stream');
  es.addEventListener('state', (e) => {
    const v = JSON.parse((e as MessageEvent<string>).data) as { version: number };
    scheduleRefresh(v.version);
  });
  es.addEventListener('hello', (e) => {
    const v = JSON.parse((e as MessageEvent<string>).data) as { version: number };
    scheduleRefresh(v.version);
  });
  es.addEventListener('job', (e) => {
    const v = JSON.parse((e as MessageEvent<string>).data) as { job: PlanJobView };
    handlers.job?.(v.job);
  });
  es.addEventListener('verdict', (e) => {
    const v = JSON.parse((e as MessageEvent<string>).data) as { verdict: VerdictEvent };
    handlers.verdict?.(v.verdict);
  });
}

export function closeStream(): void {
  es?.close();
  es = null;
}
