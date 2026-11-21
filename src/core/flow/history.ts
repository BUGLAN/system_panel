/**
 * 流水（结算 / 认输）的读写形状与 7 天战报聚合。
 * 移植自 flutter-final QuestFlow 的 HistoryLog / WeekSummary。
 */
import { ATTR_KEYS, isAttrKey, type AttrKey, type AttrMap } from '../data/attrs';
import { isRank } from '../data/rank';
import { isObj } from '../save/json';
import { addDays, dayKey, daysBetween } from '../time/day';
import type { HistoryEntry } from './types';

/** 流水滚动上限（满了删最旧；累计 EXP 另存，不受影响） */
export const HISTORY_MAX = 400;

const KINDS = ['main', 'daily', 'remedy'] as const;
const RESULTS = ['clear', 'quit', 'timeout'] as const;

/** 读一行流水（字段坏就给默认，整行不是对象 = null） */
export function historyFromRow(v: unknown): HistoryEntry | null {
  if (!isObj(v)) return null;
  const attrs: AttrMap = {};
  if (isObj(v['attrs'])) {
    for (const [k, n] of Object.entries(v['attrs'])) {
      if (isAttrKey(k) && typeof n === 'number') attrs[k] = n;
    }
  }
  const num = (k: string) => (typeof v[k] === 'number' ? (v[k] as number) : 0);
  const kind = v['kind'];
  const result = v['result'];
  return {
    at: num('at'),
    name: typeof v['name'] === 'string' ? v['name'] : '',
    rank: isRank(v['rank']) ? v['rank'] : 'F',
    kind: (KINDS as readonly unknown[]).includes(kind) ? (kind as HistoryEntry['kind']) : 'daily',
    exp: num('exp'),
    coin: num('coin'),
    streak: num('streak'),
    result: (RESULTS as readonly unknown[]).includes(result)
      ? (result as HistoryEntry['result'])
      : 'clear',
    attrs,
  };
}

export interface WeekSummary {
  /** 7 天内完成数 */
  doneCount: number;
  totalExp: number;
  totalCoin: number;
  bestStreak: number;
  /** 7 列完成数（0 = 6 天前 … 6 = 今天） */
  dayDone: number[];
  /** 7 天窗口内各维增量 */
  dayAttrs: Record<AttrKey, number>;
  /** 逐日各维增量 */
  dayAttrsByDay: AttrMap[];
  /** 最近 ≤8 条（新 → 旧） */
  recent: HistoryEntry[];
}

/** 战报聚合（纯函数；all 按时间旧 → 新） */
export function summarizeWeek(all: HistoryEntry[], now: number): WeekSummary {
  const today = dayKey(now);
  const start = addDays(today, -6);
  const dayDone = [0, 0, 0, 0, 0, 0, 0];
  const dayAttrsByDay: AttrMap[] = dayDone.map(() => ({}));
  const dayAttrs = Object.fromEntries(ATTR_KEYS.map((k) => [k, 0])) as Record<AttrKey, number>;
  let doneCount = 0;
  let totalExp = 0;
  let totalCoin = 0;
  let bestStreak = 0;
  for (const e of all) {
    const idx = 6 - daysBetween(dayKey(e.at), today);
    if (daysBetween(start, dayKey(e.at)) < 0 || idx < 0 || idx > 6) continue;
    totalExp += e.exp;
    totalCoin += e.coin;
    bestStreak = Math.max(bestStreak, e.streak);
    if (e.result === 'clear') {
      dayDone[idx] = (dayDone[idx] ?? 0) + 1;
      doneCount++;
    }
    const day = dayAttrsByDay[idx] as AttrMap;
    for (const [k, v] of Object.entries(e.attrs) as Array<[AttrKey, number]>) {
      dayAttrs[k] += v;
      day[k] = (day[k] ?? 0) + v;
    }
  }
  const recent = all.slice(-8).reverse();
  return { doneCount, totalExp, totalCoin, bestStreak, dayDone, dayAttrs, dayAttrsByDay, recent };
}
