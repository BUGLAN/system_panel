/**
 * 会话时钟：每秒一拍。换日（跨过 0 点 / 从后台回来）、执行中单据的到点检查（护盾 / 超时判负）。
 * 执行相关的处理挂在 onSecond 上，由执行编排器注册。
 */
import { dayKey } from '../../core/time/day';
import { game, now, runFlow } from '../game';

type SecondHook = (t: number) => void;
const hooks = new Set<SecondHook>();
let timer: number | null = null;

export function onSecond(fn: SecondHook): () => void {
  hooks.add(fn);
  return () => hooks.delete(fn);
}

/** 跨日了就换日（同一天反复进出不重发日常） */
export function rollDayIfNeeded(): void {
  const t = now();
  if (game().meta.lastRollDay === dayKey(t)) return;
  runFlow((f) => f.rollDay(t));
}

export function startSession(): void {
  if (timer !== null || typeof window === 'undefined') return;
  timer = window.setInterval(() => {
    const t = now();
    rollDayIfNeeded();
    for (const h of hooks) {
      try {
        h(t);
      } catch (e) {
        console.error('[session] 每秒回调出错', e);
      }
    }
  }, 1000);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') rollDayIfNeeded();
  });
}
