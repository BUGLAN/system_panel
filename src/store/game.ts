/**
 * 读写存档的唯一入口：runFlow 在存档的深拷贝上跑 QuestFlow，改了才提交（触发自动存档），
 * 产生的流水追加进 history 表。界面层不直接改 game。
 */
import { QuestFlow } from '../core/flow/questFlow';
import type { HistoryEntry } from '../core/flow/types';
import type { SaveData } from '../core/save/saveData';
import { appDb } from './db';
import { gameStore } from './gameStore';
import { appendHistory, loadHistory } from './sideRepos';

export const now = () => Date.now();

export function game(): SaveData {
  return gameStore.getState().game;
}

let historyCache: HistoryEntry[] | null = null;

export async function historyAll(): Promise<HistoryEntry[]> {
  historyCache ??= await loadHistory(appDb());
  return historyCache;
}

export function historySync(): HistoryEntry[] {
  return historyCache ?? [];
}

export function resetHistoryCache(): void {
  historyCache = [];
}

/** 在存档上跑一段流程；f.changed 才提交 */
export function runFlow<T>(fn: (f: QuestFlow) => T): T {
  const f = new QuestFlow(game());
  const out = fn(f);
  commitFlow(f);
  return out;
}

export function commitFlow(f: QuestFlow): void {
  if (f.changed) gameStore.getState().setGame(f.save);
  if (f.history.length) {
    const entries = f.history.splice(0);
    historyCache = [...(historyCache ?? []), ...entries];
    void appendHistory(appDb(), entries).catch((e) => console.error('[history] 写入失败', e));
  }
}

/** 直接替换存档（工具 / 编排器已经算好新存档时） */
export function setGame(next: SaveData): void {
  gameStore.getState().setGame(next);
}
