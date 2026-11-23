/**
 * 宿主状态摘要：拆解提示词【宿主档案】位用（纯函数）。
 */
import { needFor } from '../data/rewards';
import { goalDoneCount, goalTotalTasks } from '../model/goal';
import type { SaveData } from '../save/saveData';

export interface StatusSummary extends Record<string, unknown> {
  name: string;
  lv: number;
  exp: number;
  expNeed: number;
  streak: number;
  bestStreak: number;
  goal: string;
  planDone: number;
  planTotal: number;
  doneCount: number;
  executing: string;
}

export function statusSummary(s: SaveData): StatusSummary {
  const h = s.host;
  return {
    name: h.name,
    lv: h.lv,
    exp: h.exp,
    expNeed: needFor(h.lv),
    streak: h.streak,
    bestStreak: h.bestStreak,
    goal: s.goal.text,
    planDone: goalDoneCount(s.goal),
    planTotal: goalTotalTasks(s.goal),
    doneCount: h.doneCount,
    executing: s.active?.task.name ?? '',
  };
}

/** 她的宿主档案一行（系统提示词【宿主档案】位） */
export function statusLineOf(s: SaveData): string {
  const st = statusSummary(s);
  return (
    `${st.name} · LV${st.lv} · 连击 ${st.streak}` +
    (s.goal.short ? ` · 主线「${s.goal.short}」` : '') +
    (st.planTotal ? ` · 主线进度 ${st.planDone}/${st.planTotal} 单` : '')
  );
}
