/**
 * 前端的存档镜像：服务端是权威，这里只放最近一次拿到的状态（只读）。
 *  - 改存档只走 intent()：发意图 → 拿回整份最新状态 → 整体替换 → 处理顺带发生的事件
 *  - now()：按服务器时间校过的「现在」（计时走秒、换日判断用）
 *  - 离线：用本机缓存的最后一份状态只读显示，写操作一律提示「需要联网」
 */
import { createStore } from 'zustand/vanilla';
import { useStore } from 'zustand';
import type { FlowEvent, MeView, StateView } from '@host/core/api/types';
import { QuestFlow } from '@host/core/flow/questFlow';
import type { HistoryEntry } from '@host/core/flow/types';
import { saveFromJson, type SaveData } from '@host/core/save/saveData';
import { ApiError, api, setApiHooks } from './api';
import { cacheHistory, cacheState, cachedHistory } from './cache';
import { gameStore } from './gameStore';

export interface SyncState {
  me: MeView | null;
  /** 本地镜像的存档版本号 */
  version: number;
  tz: string | undefined;
  /** 服务器时间 − 本机时间 */
  skew: number;
  online: boolean;
  /** 读档走了备份（主档坏了） */
  source: StateView['source'] | null;
}

export const syncStore = createStore<SyncState>()(() => ({
  me: null,
  version: -1,
  tz: undefined,
  skew: 0,
  online: typeof navigator === 'undefined' ? true : navigator.onLine,
  source: null,
}));
export const useSync = <T>(sel: (s: SyncState) => T) => useStore(syncStore, sel);

/** 按服务器时间校过的「现在」 */
export const now = () => Date.now() + syncStore.getState().skew;
export const tz = () => syncStore.getState().tz;
export const online = () => syncStore.getState().online;

export function game(): SaveData {
  return gameStore.getState().game;
}

/** 只读推导用（主线锁、暴击率、补签可用性…），与服务端同一套规则、同一个时区 */
export function flowOf(g: SaveData = game()): QuestFlow {
  const t = tz();
  return new QuestFlow(g, t ? { tz: t } : {});
}

/** 收到一份服务端状态：比本地旧的丢掉（乱序回包），否则整体替换并缓存 */
export function applyState(v: StateView, o: { force?: boolean; fromCache?: boolean } = {}): void {
  const s = syncStore.getState();
  if (!o.force && v.version < s.version) return;
  const save = saveFromJson(v.save, v.serverNow);
  if (!save) return;
  syncStore.setState({
    version: v.version,
    tz: v.tz,
    source: v.source,
    ...(o.fromCache ? {} : { skew: v.serverNow - Date.now() }),
  });
  gameStore.getState().hydrate(save, v.source);
  if (!o.fromCache && s.me) void cacheState(s.me.username, v);
}

// ── 顺带发生的事（换日 / 护盾碎 / 超时判负）由执行编排器注册处理 ──────────

type EventHandler = (events: FlowEvent[]) => void;
let eventHandler: EventHandler = () => {};
export function onFlowEvents(fn: EventHandler): void {
  eventHandler = fn;
}
export function handleEvents(events: unknown): void {
  if (Array.isArray(events) && events.length) eventHandler(events as FlowEvent[]);
}

/** 在途的写请求数（SSE 推来的「版本变了」要等它们回来再比较，免得把自己的操作当成别处改的） */
let pendingWrites = 0;
export const writesInFlight = () => pendingWrites;

export type IntentResult<T> = { ok: true; r: T } | { ok: false; err: ApiError };

/** 发一个写意图。成功 / 被拒都会先把带回的最新状态落到本地。 */
export async function intent<T extends Record<string, unknown>>(
  path: string,
  body?: unknown,
  method: 'POST' | 'PUT' | 'DELETE' = 'POST',
): Promise<IntentResult<T>> {
  pendingWrites++;
  try {
    const r = await api<T>(method, path, body ?? {});
    handleEvents(r['events']);
    return { ok: true, r };
  } catch (e) {
    const err = e instanceof ApiError ? e : new ApiError(0, 'error', String(e));
    handleEvents(err.body['events']);
    return { ok: false, err };
  } finally {
    pendingWrites--;
  }
}

/** 拉一次最新状态（开机 / 回前台 / 跨 0 点 / 别处改了） */
export async function refreshState(boot = false): Promise<{ prevSeen: number | null } | null> {
  if (!syncStore.getState().me) return null;
  try {
    const r = await api<{ state: StateView; events: FlowEvent[]; prevSeen?: number | null }>(
      'GET',
      boot ? '/api/state?boot=1' : '/api/state',
    );
    handleEvents(r.events);
    return { prevSeen: r.prevSeen ?? null };
  } catch {
    return null;
  }
}

// ── 流水（档案 / 战报）──────────────────────────────────────

let historyCache: HistoryEntry[] | null = null;

export async function historyAll(): Promise<HistoryEntry[]> {
  const me = syncStore.getState().me;
  try {
    const r = await api<{ entries: HistoryEntry[] }>('GET', '/api/history');
    historyCache = r.entries;
    if (me) void cacheHistory(me.username, r.entries);
  } catch {
    historyCache ??= me ? await cachedHistory(me.username) : [];
  }
  return historyCache;
}

export function historySync(): HistoryEntry[] {
  return historyCache ?? [];
}

export function resetHistoryCache(): void {
  historyCache = null;
}

setApiHooks({
  onState: (s) => applyState(s),
  onOnline: (on) => {
    if (syncStore.getState().online !== on) syncStore.setState({ online: on });
  },
});

export function useGameReady(): boolean {
  return useSync((s) => s.version >= 0);
}
