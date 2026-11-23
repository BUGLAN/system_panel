import type { Rank } from '../data/rank';
import type { Quest } from '../model/quest';

/** 一单的结算结果（结算页、台词都读它） */
export interface QuestResult {
  quest: Quest;
  beforeLv: number;
  beforeExp: number;
  beforeNeed: number;
  /** 入账的 EXP */
  exp: number;
  streak: number;
  streakUp: boolean;
  /** 交了几份证据 / 其中判真几份 */
  photos: number;
  verified: number;
  /** 升到的每一级（空 = 没升级） */
  ups: number[];
  /** 点亮的主线环（-1 = 不属于当前主线） */
  planClear: number;
  /** 主线收官（最后一环也清了） */
  finale: boolean;
  /** 这一单走完了当前窗口，需要续拆下一段 */
  windowEnd: boolean;
  /** 续拆已经接上（结算后由跟进步骤置位） */
  windowNext: boolean;
  /** 队列空了 */
  empty: boolean;
  heldMs: number;
  afterLv: number;
  afterNeed: number;
  /** 结算后的经验余额 */
  endExp: number;
}

/** 一条流水 */
export interface HistoryEntry {
  at: number;
  name: string;
  rank: Rank;
  exp: number;
  /** 记账后的连胜 */
  streak: number;
  /** 旧版还有认输 / 超时的记录，照样读出来 */
  result: 'clear' | 'quit' | 'timeout';
}

/** 后台校验结论落到槽上的结果 */
export type EvidenceApply = 'kept' | 'rejected' | 'gone';
