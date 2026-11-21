/**
 * 结算经济的唯一常数家（数值一个都不许改，docs/00 第三节）。
 * 移植自 flutter-final:app/lib/data/rewards.dart + agent/vision_core.dart 的暴击率公式。
 *
 *  - EXP：F0 / E1 / D2 / C4 / B6 / A8 / S10；晶核：F3 / E~C 5 / B7 / A10 / S20
 *  - 升级曲线 need(lv) = 12 + lv × 6
 *  - 结算乘区：暴击 ×2、双倍卡 ×2（可叠到 ×4）、补救单 ×0.5，补救单 EXP 保底 1；
 *    晶核吃暴击不吃双倍
 *  - 暴击率：底 6% + 已校验证据 7%/张 + 拿不准 / 未校验 4%/张 + 连胜 1%/天（≤10 天）
 *    + 暴击芯片 25%，封顶 85%
 */
import type { Rank } from './rank';

export const EXP_BY_RANK: Record<Rank, number> = { F: 0, E: 1, D: 2, C: 4, B: 6, A: 8, S: 10 };
export const COIN_BY_RANK: Record<Rank, number> = { F: 3, E: 5, D: 5, C: 5, B: 7, A: 10, S: 20 };

export const CRIT_MULTIPLIER = 2;
export const DBL_MULTIPLIER = 2;
export const REMEDY_FACTOR = 0.5;

/** 升到下一级要的经验 */
export function needFor(lv: number): number {
  return 12 + lv * 6;
}

export interface Payout {
  /** 暴击 / 双倍之前那一跳（结算页第一行） */
  baseExp: number;
  /** 最终入账 */
  exp: number;
  coin: number;
}

/** Dart 的 double.round()：.5 远离 0（JS 的 Math.round 对正数一致，这里只处理非负） */
function roundHalfUp(x: number): number {
  return Math.floor(x + 0.5);
}

/** 一单的出账（纯函数 —— 结算与所有展示读数的唯一口径） */
export function payout(o: { rank: Rank; crit: boolean; dbl: boolean; remedy?: boolean }): Payout {
  const k = o.remedy ? REMEDY_FACTOR : 1;
  const raw = roundHalfUp(EXP_BY_RANK[o.rank] * k);
  const baseExp = o.remedy && raw < 1 ? 1 : raw;
  const exp = baseExp * (o.crit ? CRIT_MULTIPLIER : 1) * (o.dbl ? DBL_MULTIPLIER : 1);
  const coin = roundHalfUp(COIN_BY_RANK[o.rank] * k) * (o.crit ? CRIT_MULTIPLIER : 1);
  return { baseExp, exp, coin };
}

export const CRIT_BASE = 0.06;
export const CRIT_PER_VERIFIED = 0.07;
export const CRIT_PER_UNVERIFIED = 0.04;
export const CRIT_PER_STREAK_DAY = 0.01;
export const CRIT_STREAK_DAYS_MAX = 10;
export const CRIT_CHIP = 0.25;
export const CRIT_CAP = 0.85;

/** 证据带来的暴击加成：已校验 7%/张，拿不准与未校验 4%/张（不符的不在槽里） */
export function evidenceCritBonus(o: {
  verified: number;
  unverified: number;
  unsure?: number;
}): number {
  return o.verified * CRIT_PER_VERIFIED + (o.unverified + (o.unsure ?? 0)) * CRIT_PER_UNVERIFIED;
}

/** 暴击率总公式 */
export function critChance(o: {
  verified?: number;
  unverified?: number;
  unsure?: number;
  streak?: number;
  critItem?: boolean;
}): number {
  const bonus = evidenceCritBonus({
    verified: o.verified ?? 0,
    unverified: o.unverified ?? 0,
    unsure: o.unsure ?? 0,
  });
  const streakBonus =
    Math.min(CRIT_STREAK_DAYS_MAX, Math.max(0, o.streak ?? 0)) * CRIT_PER_STREAK_DAY;
  return Math.min(CRIT_CAP, CRIT_BASE + bonus + streakBonus + (o.critItem ? CRIT_CHIP : 0));
}
