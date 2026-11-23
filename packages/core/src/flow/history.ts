/**
 * 流水的读写形状与 7 天战报聚合。
 * 移植自 flutter-final QuestFlow 的 HistoryLog / WeekSummary。
 */
import { isRank } from '../data/rank';
import { isObj } from '../save/json';
import { addDays, dayKey, daysBetween } from '../time/day';
import type { HistoryEntry } from './types';

/** 流水滚动上限（满了删最旧；累计 EXP 另存，不受影响） */
export const HISTORY_MAX = 400;

const RESULTS = ['clear', 'quit', 'timeout'] as const;

/** 读一行流水（字段坏就给默认，整行不是对象 = null） */
export function historyFromRow(v: unknown): HistoryEntry | null {
  if (!isObj(v)) return null;
  const num = (k: string) => (typeof v[k] === 'number' ? (v[k] as number) : 0);
  const result = v['result'];
  return {
    at: num('at'),
    name: typeof v['name'] === 'string' ? v['name'] : '',
    rank: isRank(v['rank']) ? v['rank'] : 'F',
    exp: num('exp'),
    streak: num('streak'),
    result: (RESULTS as readonly unknown[]).includes(result)
      ? (result as HistoryEntry['result'])
      : 'clear',
  };
}

export interface WeekSummary {
  /** 7 天内完成数 */
  doneCount: number;
  totalExp: number;
  bestStreak: number;
  /** 7 列完成数（0 = 6 天前 … 6 = 今天） */
  dayDone: number[];
  /** 最近 ≤8 条（新 → 旧） */
  recent: HistoryEntry[];
}

/** 战报聚合（纯函数；all 按时间旧 → 新） */
export function summarizeWeek(all: HistoryEntry[], now: number, tz?: string): WeekSummary {
  const today = dayKey(now, tz);
  const start = addDays(today, -6);
  const dayDone = [0, 0, 0, 0, 0, 0, 0];
  let doneCount = 0;
  let totalExp = 0;
  let bestStreak = 0;
  for (const e of all) {
    const idx = 6 - daysBetween(dayKey(e.at, tz), today);
    if (daysBetween(start, dayKey(e.at, tz)) < 0 || idx < 0 || idx > 6) continue;
    totalExp += e.exp;
    bestStreak = Math.max(bestStreak, e.streak);
    if (e.result === 'clear') {
      dayDone[idx] = (dayDone[idx] ?? 0) + 1;
      doneCount++;
    }
  }
  const recent = all.slice(-8).reverse();
  return { doneCount, totalExp, bestStreak, dayDone, recent };
}
