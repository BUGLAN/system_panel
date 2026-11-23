/**
 * 档位阶梯 F < E < D < C < B < A < S。
 * 新生成的任务不出 F（F 只在旧存档里出现）。
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
