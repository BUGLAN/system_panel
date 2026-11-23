/**
 * 结算经济的唯一常数家。
 *
 *  - EXP：F0 / E1 / D2 / C4 / B6 / A8 / S10
 *  - 升级曲线 need(lv) = 12 + lv × 6
 */
import type { Rank } from './rank';

export const EXP_BY_RANK: Record<Rank, number> = { F: 0, E: 1, D: 2, C: 4, B: 6, A: 8, S: 10 };

/** 升到下一级要的经验 */
export function needFor(lv: number): number {
  return 12 + lv * 6;
}

/** 一单的出账（结算与所有展示读数的唯一口径） */
export function expFor(rank: Rank): number {
  return EXP_BY_RANK[rank];
}
