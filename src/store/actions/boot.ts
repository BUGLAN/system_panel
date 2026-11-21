/**
 * 开机：读档 + 读设置 / 同意 / 偏好 + 读流水 → 换日 → 等宿主点「唤醒」→ 决定进哪一页。
 *  - 没同意告知页 → 告知页
 *  - 没主线也没记着的目标 → 绑定仪式
 *  - 有执行中的单 → 直接回执行页（计时按 startAt 推导）
 *  - 其余 → 大厅，她按离开时长说一句
 */
import { LINES, fillLine } from '../../core/data/lines';
import { awayLine } from '../../core/time/away';
import { persistence } from '../app';
import { game, historyAll, now, runFlow } from '../game';
import { hasConsent, loadServices } from '../services';
import { sayHome, setUi, toast, type Scene } from '../uiStore';
import { startSession } from './session';

let ready: Promise<void> | null = null;
let prevSeen: number | null = null;

export function bootData(): Promise<void> {
  ready ??= (async () => {
    await Promise.all([persistence.boot(), loadServices(), historyAll()]);
    prevSeen = game().lastSeen;
    runFlow((f) => f.rollDay(now()));
    startSession();
  })();
  return ready;
}

/** 开机日志（{host} 换成宿主名 + 等级） */
export function bootLines(): string[] {
  const h = game().host;
  return LINES.bootLog.map((l) => fillLine(l, { host: `${h.name} · LV${h.lv}` }));
}

export function wakeTarget(): Scene {
  const g = game();
  if (!hasConsent()) return 'consent';
  if (g.goal.plan.length === 0 && !g.pendingGoal) return 'onboard';
  if (g.active) return 'exec';
  return 'home';
}

/** 唤醒之后的第一句 */
export function greet(): void {
  const g = game();
  if (g.active) {
    setTimeout(() => toast('欢迎回来。你还有一单在计时。', 'ok'), 900);
    return;
  }
  const away = prevSeen === null ? 0 : now() - prevSeen;
  sayHome(awayLine(away) ?? LINES.back10m);
}

export function enterAfterBoot(): void {
  const target = wakeTarget();
  setUi({ scene: target, hist: [] });
  if (target === 'home' || target === 'exec') greet();
}
