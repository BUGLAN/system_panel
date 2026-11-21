/**
 * 设计令牌的 TS 镜像。唯一源是 tokens.css；这里给 JS 侧（canvas 粒子、Motion 参数、
 * 结算时间轴）用，tests/design/tokens.test.ts 逐项比对两边，改色只改 CSS 再同步这里。
 */
import type { Grade, Rank } from '@host/core/data/rank';

export const COLORS = {
  bg: '#06050c',
  ink: '#0d0b18',
  acid: '#d6ff3d',
  hot: '#ff3b7a',
  cyan: '#3be8ff',
  violet: '#8f6bff',
  gold: '#ffcc4d',
  mint: '#3dffa8',
  txt: '#f4f1ff',
  dim: '#8c88aa',
  dim2: '#55516e',
  onAccent: '#0a0910',
  flame: '#ffb35c',
  flameCore: '#ff8a3d',
} as const;

/** 稀有度色谱（Ref.rank） */
export const RANK_COLORS: Record<Rank, string> = {
  F: '#9aa3b2',
  E: '#3dffa8',
  D: '#3be8ff',
  C: '#8f6bff',
  B: '#ffcc4d',
  A: '#ff3b7a',
  S: '#ffffff',
};

/** 评级色（S/A/B/C） */
export const GRADE_COLORS: Record<Grade, string> = {
  S: '#ffffff',
  A: '#d6ff3d',
  B: '#3be8ff',
  C: '#ff3b7a',
};

export function rankColor(r: Rank): string {
  return RANK_COLORS[r];
}

/** 卡片右上那排小菱形亮几个（参考稿 RARN） */
export const RANK_PIPS: Record<Rank, number> = { F: 1, E: 1, D: 2, C: 3, B: 4, A: 5, S: 5 };

/** 缓动（cubic-bezier 四参数，Motion 的 ease 可直接吃数组） */
export const EASE = {
  ease: [0.2, 0.9, 0.2, 1],
  snap: [0.7, 0, 0.2, 1],
  pop: [0.2, 1.4, 0.4, 1],
  wipe: [0.75, 0, 0.25, 1],
  flip: [0.3, 1.3, 0.4, 1],
  slam: [0.6, 0, 0.8, 0.4],
} as const satisfies Record<string, readonly [number, number, number, number]>;

/**
 * 动效参数（docs/00 第四节，不许凭感觉改）。
 * 禁用线性匀速：这里不提供 linear，组件里也不要写。
 */
export const MOTION = {
  /** 弹簧：stiffness 100 / damping 20，过冲到 1.08 再回弹 */
  spring: { type: 'spring', stiffness: 100, damping: 20 } as const,
  springOvershoot: 1.08,
  /** 亮帧：全屏白色、16% 透明度、脉冲 180ms，音效踩这一帧 */
  flash: { color: '#ffffff', opacity: 0.16, ms: 180 },
  /** EXP count-up：800ms、ease-out cubic */
  countUpMs: 800,
  /** 暴击：定格 200ms → CRIT 印章 scale 2.2 → 1 → 续滚双倍 */
  critFreezeMs: 200,
  critStampFrom: 2.2,
  /** 经验条：不跨级 520ms；跨级先涨满 360ms → 白闪 + 升级 → 归零 → 再涨到余额 420ms */
  expBarMs: 520,
  expBarFillMs: 360,
  expBarRefillMs: 420,
  /** 总时长上限 */
  settleMaxMs: 1600,
  levelUpMaxMs: 2000,
  publishMaxMs: 800,
  /** 失败：更短、更暗、更安静（亮度是成功的 1/3） */
  failBrightness: 1 / 3,
  /** 打字机：标准每字 34ms */
  typeMsPerChar: 34,
} as const;

/** ease-out cubic（count-up 用） */
export function easeOutCubic(t: number): number {
  const k = Math.min(1, Math.max(0, t));
  return 1 - Math.pow(1 - k, 3);
}
