import type { AttrMap } from '../data/attrs';
import type { Grade, Rank } from '../data/rank';
import type { Quest } from '../model/quest';

/** 一单的结算结果（结算页、战报、台词都读它） */
export interface QuestResult {
  quest: Quest;
  beforeLv: number;
  beforeExp: number;
  beforeNeed: number;
  /** 暴击 / 双倍之前那一跳 */
  baseExp: number;
  /** 最终入账 */
  exp: number;
  coin: number;
  attrs: AttrMap;
  streak: number;
  streakUp: boolean;
  crit: boolean;
  dbl: boolean;
  /** 交了几份证据 / 其中判真几份 */
  photos: number;
  verified: number;
  /** 当时的暴击率 */
  chance: number;
  /** 差一点就暴击（百分点；只有差不到 8% 才有值） */
  near: number;
  /** 升到的每一级（空 = 没升级） */
  ups: number[];
  /** 本次解锁的称号 id */
  titles: string[];
  /** 点亮的主线环（-1 = 非主线） */
  planClear: number;
  /** 主线收官（最后一环也清了） */
  finale: boolean;
  /** 这一单走完了当前窗口，需要续拆下一段 */
  windowEnd: boolean;
  /** 续拆已经接上（结算后由跟进步骤置位） */
  windowNext: boolean;
  /** 补救单抵消了那次失败 */
  redeemed: boolean;
  /** 队列空了 */
  empty: boolean;
  /** 计时单 60 秒内就交 */
  tooFast: boolean;
  heldMs: number;
  afterLv: number;
  afterNeed: number;
  /** 结算后的经验余额 */
  endExp: number;
  grade: Grade;
}

/** 认输 / 超时的产出 */
export interface FailOutcome {
  task: Quest;
  heldMs: number;
  how: 'quit' | 'timeout';
  /** 生成的补救单（补救单再认输时没有） */
  remedy: Quest | null;
  remedyDeadline: number | null;
}

/** 「换一个」的产出 */
export interface RetreatOutcome {
  task: Quest;
  /** 换上的那一单；null = F 级但日常池枯了 */
  replacement: Quest | null;
  /** 今天第几次退缩 / 累计 */
  count: number;
  total: number;
  /** 这次触发了「口头巨人」 */
  shame: boolean;
}

/** 计时单到点的处理结果 */
export type TimeoutOutcome =
  | { kind: 'none' }
  /** 护盾挡下：截止时间顺延 extendMin 分钟 */
  | { kind: 'shield'; extendMin: number }
  | { kind: 'fail'; outcome: FailOutcome };

/** 一条流水 */
export interface HistoryEntry {
  at: number;
  name: string;
  rank: Rank;
  kind: Quest['kind'];
  exp: number;
  coin: number;
  /** 记账后的连胜 */
  streak: number;
  result: 'clear' | 'quit' | 'timeout';
  attrs: AttrMap;
}

/** 后台校验结论落到槽上的结果 */
export type EvidenceApply = 'kept' | 'rejected' | 'gone';
