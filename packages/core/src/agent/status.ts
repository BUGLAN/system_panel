/**
 * 宿主状态摘要：聊天「查状态」卡片与系统提示词【宿主档案】位共用（纯函数）。
 */
import { attrName } from '../data/attrs';
import { needFor } from '../data/rewards';
import { weakestAttr } from '../goal/daily';
import { goalDoneCount, goalTotalTasks } from '../model/goal';
import type { SaveData } from '../save/saveData';

export interface StatusSummary extends Record<string, unknown> {
  name: string;
  lv: number;
  exp: number;
  expNeed: number;
  coins: number;
  streak: number;
  bestStreak: number;
  queue: number;
  goal: string;
  planDone: number;
  planTotal: number;
  weakest: string;
  weakestValue: number;
  doneCount: number;
  failCount: number;
  items: Record<string, number>;
  executing: string;
}

export function statusSummary(s: SaveData): StatusSummary {
  const h = s.host;
  const [wk, wv] = weakestAttr(h.attrs);
  return {
    name: h.name,
    lv: h.lv,
    exp: h.exp,
    expNeed: needFor(h.lv),
    coins: h.coins,
    streak: h.streak,
    bestStreak: h.bestStreak,
    queue: s.queue.length,
    goal: s.goal.text,
    planDone: goalDoneCount(s.goal),
    planTotal: goalTotalTasks(s.goal),
    weakest: attrName(wk),
    weakestValue: wv,
    doneCount: h.doneCount,
    failCount: h.failCount,
    items: { ...h.items },
    executing: s.active?.task.name ?? '',
  };
}

/** 她的宿主档案一行（系统提示词【宿主档案】位） */
export function statusLineOf(s: SaveData): string {
  const st = statusSummary(s);
  return (
    `${st.name} · LV${st.lv} · 连击 ${st.streak} · 手里 ${st.queue} 单` +
    (s.goal.short ? ` · 主线「${s.goal.short}」` : '') +
    (st.planTotal ? ` · 主线进度 ${st.planDone}/${st.planTotal} 单` : '') +
    ` · 最弱维 ${st.weakest} ${st.weakestValue} · 连败 ${st.failCount} 次`
  );
}
