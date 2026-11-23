/**
 * 委托的文案读数。移植自 flutter-final:app/lib/state/quest.dart。
 */
import { expFor } from '../data/rewards';
import { fmtMin, pad2 } from '../format';
import type { Quest } from '../model/quest';

/** № 0041 */
export function serialText(q: Quest): string {
  return `№ ${String(q.serial).padStart(4, '0')}`;
}

/** 主线 · 第 2 单 / 30 */
export function kindLabel(q: Quest): string {
  return `主线 · 第 ${q.planIndex + 1} 单 / ${q.planTotal}`;
}

/** 委托编码：MAIN 02/30 */
export function questCode(q: Quest): string {
  return `MAIN ${pad2(q.planIndex + 1)}/${q.planTotal}`;
}

/** 预计耗时读数：「约 25 分钟」 */
export function timeLabel(q: Quest): string {
  return `约 ${fmtMin(q.minutes)}`;
}

/** 这一单的报酬读数（与结算同一个口径 —— 显示 = 结算） */
export function lootText(q: Quest): string {
  return `EXP +${expFor(q.rank)}`;
}
