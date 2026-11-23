/**
 * 会话时钟：每秒一拍。
 *  - 跨过账号时区的 0 点 / 从后台回来 → 拉一次状态（换日由服务端判）
 *  - 前台连 SSE，后台断开；恢复联网自动同步
 */
import { dayKey } from '@host/core/time/day';
import { game, now, online, refreshState, syncStore, tz } from '../game';
import { closeStream, openStream } from '../stream';

let timer: number | null = null;
let lastDay = '';

/** 跨日了就拉一次（同一天反复进出不重复拉） */
export function rollDayIfNeeded(): void {
  if (!syncStore.getState().me || !online()) return;
  const today = dayKey(now(), tz());
  if (game().meta.lastRollDay === today || lastDay === today) return;
  lastDay = today;
  void refreshState();
}

export function startSession(): void {
  if (timer !== null || typeof window === 'undefined') return;
  timer = window.setInterval(rollDayIfNeeded, 1000);
  openStream();
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      openStream();
      void refreshState();
    } else closeStream();
  });
  window.addEventListener('online', () => {
    syncStore.setState({ online: true });
    openStream();
    void refreshState();
  });
  window.addEventListener('offline', () => syncStore.setState({ online: false }));
}
