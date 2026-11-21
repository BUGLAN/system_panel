/**
 * 结算演出的时间轴（纯数据，单测钉住总时长）。docs/00 第四节：
 *  - 结算总时长 ≤ 1.6s（到「收下」按钮出现）
 *  - EXP count-up 800ms、ease-out cubic；暴击：定格 200ms → CRIT 印章 2.2 → 1 → 续滚双倍
 *  - 经验条：不跨级 520ms；跨级先涨满 360ms → 白闪 → 归零 → 再涨到余额 420ms
 *  - 升级叠层 ≤ 2s（同一天重复只播简版）
 *
 * 暴击那一下（定格 + 印章）只压在 EXP 那一行上；为了不超 1.6s，暴击时扫描与评级印章缩短。
 */
import { MOTION } from '../../design/tokens';

export interface CritBeat {
  /** 先滚到暴击前的数 */
  baseMs: number;
  freezeMs: number;
  /** CRIT 印章 2.2 → 1 */
  stampMs: number;
  /** 续滚到翻倍后的数（base + rest = 800ms count-up 预算） */
  restMs: number;
}

export interface SettleTimeline {
  scanMs: number;
  rankAt: number;
  rankMs: number;
  rowsAt: number;
  rowStagger: number;
  rows: number;
  countMs: number;
  crit: CritBeat | null;
  barAt: number;
  bar:
    | { kind: 'same'; ms: number }
    | { kind: 'cross'; fillMs: number; flashMs: number; refillMs: number };
  /** 「收下」按钮出现的时刻 = 总时长 */
  totalMs: number;
}

export const SETTLE_MAX_MS = MOTION.settleMaxMs;
export const LEVELUP_MAX_MS = MOTION.levelUpMaxMs;

export function buildSettleTimeline(o: {
  crit: boolean;
  rows: number;
  levelUp: boolean;
}): SettleTimeline {
  const scanMs = o.crit ? 200 : 300;
  const rankAt = scanMs;
  const rankMs = o.crit ? 220 : 320;
  const rowsAt = rankAt + rankMs - 60;
  const rowStagger = 60;
  const rows = Math.max(1, o.rows);
  const countMs = MOTION.countUpMs;
  const crit: CritBeat | null = o.crit
    ? { baseMs: 360, freezeMs: MOTION.critFreezeMs, stampMs: 220, restMs: countMs - 360 }
    : null;
  const expRowMs = crit ? crit.baseMs + crit.freezeMs + crit.stampMs + crit.restMs : countMs;
  const otherRowsEnd = rows > 1 ? rowsAt + (rows - 1) * rowStagger + countMs : 0;
  const countEnd = Math.max(rowsAt + expRowMs, otherRowsEnd);
  const barAt = rowsAt + 40;
  const bar: SettleTimeline['bar'] = o.levelUp
    ? {
        kind: 'cross',
        fillMs: MOTION.expBarFillMs,
        flashMs: MOTION.flash.ms,
        refillMs: MOTION.expBarRefillMs,
      }
    : { kind: 'same', ms: MOTION.expBarMs };
  const barEnd = barAt + (bar.kind === 'same' ? bar.ms : bar.fillMs + bar.flashMs + bar.refillMs);
  return {
    scanMs,
    rankAt,
    rankMs,
    rowsAt,
    rowStagger,
    rows,
    countMs,
    crit,
    barAt,
    bar,
    totalMs: Math.max(countEnd, barEnd),
  };
}

/** 升级叠层：完整版 / 同日简版 */
export function levelUpDurationMs(brief: boolean): number {
  return brief ? 900 : 1900;
}
