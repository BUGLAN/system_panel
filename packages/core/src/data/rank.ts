/**
 * 档位阶梯 F < E < D < C < B < A < S。
 * F 只用于补救残单（新生成的任务不出 F）。
 * 移植自 flutter-final:app/lib/data/rarity.dart（只保留结算与造单要用的部分；
 * 旧色谱已废，颜色一律读 design/tokens）。
 */
export const RANKS = ['F', 'E', 'D', 'C', 'B', 'A', 'S'] as const;
export type Rank = (typeof RANKS)[number];

export function isRank(v: unknown): v is Rank {
  return typeof v === 'string' && (RANKS as readonly string[]).includes(v);
}

/** 档位序号（F=0 … S=6），认不出的按 F */
export function rankIndex(r: Rank): number {
  return RANKS.indexOf(r);
}

/** 升 / 降档，钉在 F~S 之间（store.js `rankShift`） */
export function rankShift(r: Rank, d: number): Rank {
  const i = Math.min(RANKS.length - 1, Math.max(0, rankIndex(r) + d));
  return RANKS[i] as Rank;
}

/** 验收评级（结算页与主线卡战报同一口径） */
export const GRADES = ['S', 'A', 'B', 'C'] as const;
export type Grade = (typeof GRADES)[number];

export function isGrade(v: unknown): v is Grade {
  return typeof v === 'string' && (GRADES as readonly string[]).includes(v);
}

/** 每档给的六维点数（rarity.dart `pt`）：造单时按类目权重分到各维 */
export const RANK_ATTR_POINTS: Record<Rank, number> = {
  F: 1,
  E: 1,
  D: 2,
  C: 2,
  B: 3,
  A: 4,
  S: 6,
};
