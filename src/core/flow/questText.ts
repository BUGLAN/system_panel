/**
 * 委托的文案读数与评级口径。移植自 flutter-final:app/lib/state/quest.dart / result.dart。
 */
import { payout } from '../data/rewards';
import type { AttrMap } from '../data/attrs';
import { attrName } from '../data/attrs';
import type { Grade, Rank } from '../data/rank';
import { fmtMin, pad2 } from '../format';
import type { Quest } from '../model/quest';

/** № 0041 */
export function serialText(q: Quest): string {
  return `№ ${String(q.serial).padStart(4, '0')}`;
}

/** 四档 kind 文案 */
export function kindLabel(q: Quest): string {
  if (q.kind === 'main') return `主线 · 第 ${q.planIndex + 1} 单 / ${q.planTotal}`;
  if (q.kind === 'remedy' && q.planIndex >= 0) return `补救 · 顶替主线第 ${q.planIndex + 1} 单`;
  if (q.kind === 'remedy') return '补救 · 24 小时内有效';
  if (q.hinted) return '日常 · 她替你留的';
  return '日常委托';
}

/** 委托编码：MAIN 02/180 · SIDE · DAILY · 补救 */
export function questCode(q: Quest): string {
  if (q.kind === 'main') return `MAIN ${pad2(q.planIndex + 1)}/${q.planTotal}`;
  if (q.kind === 'remedy')
    return q.planIndex >= 0 ? `补救 · 主线 ${pad2(q.planIndex + 1)}` : '补救';
  return 'DAILY';
}

/** 委托板 / 任务卡的时长读数：计时单「25 分钟」，打卡单「打卡」 */
export function timeLabel(q: Quest): string {
  return q.timed ? fmtMin(q.minutes) : '打卡';
}

/** 六维加成读数：体质 +1 · 灵巧 +1 */
export function attrsText(attrs: AttrMap): string {
  return Object.entries(attrs)
    .filter(([, v]) => (v ?? 0) > 0)
    .map(([k, v]) => `${attrName(k)} +${v}`)
    .join(' · ');
}

/** 这一单在给定条件下的报酬读数（与结算同一个 payout 派生 —— 显示 = 结算） */
export function lootTextOf(o: {
  rank: Rank;
  remedy?: boolean;
  crit?: boolean;
  dbl?: boolean;
}): string {
  const p = payout({
    rank: o.rank,
    remedy: o.remedy ?? false,
    crit: o.crit ?? false,
    dbl: o.dbl ?? false,
  });
  return `EXP +${p.exp} · 晶核 +${p.coin}`;
}

/** 队列里等接单的裸单出账 */
export function lootText(q: Quest): string {
  return lootTextOf({ rank: q.rank, remedy: q.kind === 'remedy' });
}

/**
 * 评级口径唯一真源（E2.2：证据为主、用时为辅）：
 *  有判真证据 = A；只有拿不准 / 未校验 = B；没证据 = C；
 *  计时单用时不到目标的 1/4 降一档；暴击且 A → S；打卡单不看用时。
 */
export function gradeOf(o: {
  timed: boolean;
  minutes: number;
  heldMs: number;
  verified: number;
  photos: number;
  crit: boolean;
}): Grade {
  let g: Grade = o.verified > 0 ? 'A' : o.photos > 0 ? 'B' : 'C';
  const limitSec = o.minutes * 60;
  if (o.timed && limitSec > 0 && Math.floor(o.heldMs / 1000) * 4 < limitSec) {
    g = g === 'A' ? 'B' : 'C';
  }
  if (o.crit && g === 'A') g = 'S';
  return g;
}
