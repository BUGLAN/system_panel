/**
 * 目标拆解的简报：目标一句话 + 期限 + 要交几张 + 类别 + 访谈答案 + 宿主档案。
 * 移植自 flutter-final:app/lib/agent/plan_brief.dart。
 */
import type { GoalCategory } from '@host/core/data/categoryTypes';
import { RANKS } from '@host/core/data/rank';
import {
  planWindowFor,
  rankCapMinutes,
  segmentPhase,
  segmentTo,
  windowCount,
  windowIndex,
  windowIsLast,
  windowIsWhole,
  windowTo,
  type PlanSegment,
  type PlanWindow,
} from '@host/core/goal/plan';
import { PLAN_GUARD } from '@host/core/agent/guardrail';

/** 兑现单的时限下限（提示词里写给模型） */
export const PLAN_FINAL_MINUTES = 120;

export interface PlanBrief {
  goalText: string;
  days: number;
  /** 这一轮要交几张（= 窗口张数） */
  taskCount: number;
  cat: GoalCategory;
  interview: Record<string, string>;
  statusLine?: string;
  firstGoal: boolean;
  /** 非空 = 这一轮只拆窗口里的一段 */
  segment?: PlanSegment | null;
  /** 滚动生成的窗口；null = 整份清单一次拆完 */
  window?: PlanWindow | null;
  /** 续拆时「前面做到了哪里」 */
  progress?: string | null;
}

export function briefWindow(b: PlanBrief): PlanWindow {
  return (
    b.window ?? planWindowFor({ total: b.taskCount, firstGoal: b.firstGoal, size: b.taskCount })
  );
}

function questionOf(cat: GoalCategory, cardId: string): string {
  const c = cat.cards.find((x) => x.id === cardId);
  if (c) return c.question;
  if (cardId === 'common.slot') return '一周愿意投入几个时段？';
  if (cardId === 'common.history') return '上次立目标是什么结果？';
  return cardId;
}

/** 交给模型的正文（期限与条数必须写进来） */
export function briefUserText(b: PlanBrief): string {
  const seg = b.segment ?? null;
  const w = briefWindow(b);
  const L: string[] = [`宿主立了目标：「${b.goalText}」。`];
  if (windowIsWhole(w)) {
    L.push(
      `期限 ${b.days} 天，清单要正好 ${w.total} 张（= 期限天数），` +
        `${windowIsLast(w) ? `第 ${w.total} 张是兑现单。` : '这一份不摆兑现单。'}`,
    );
  } else {
    L.push(
      `期限 ${b.days} 天，整条主线共 ${w.total} 张。清单**滚动生成**：每次只拆一段，他做完这一段再拆下一段。`,
    );
    L.push(
      `**这一轮是第 ${windowIndex(w) + 1}/${windowCount(w)} 段：第 ${w.from}~${windowTo(w)} 张，共 ${w.size} 张**。` +
        `档位只能在 ${w.lo}~${w.hi} 之间，逐张不许倒退。` +
        `${windowIsLast(w) ? `本段最后一张（第 ${w.total} 张）就是整条主线的兑现单，必须 S 级。` : '本段不含兑现单（兑现单在最后一段），不要提前收尾。'}`,
    );
  }
  if (b.progress?.trim()) {
    L.push('前面做到了哪里（接着往下排，别重复）：', b.progress.trim());
  }
  if (seg) {
    L.push(
      `这一段分 ${seg.count} 份同时拆。**你只负责第 ${seg.index + 1} 份：第 ${seg.from}~${segmentTo(seg)} 张，共 ${seg.size} 张**。`,
    );
    L.push(`本段阶段：${segmentPhase(seg)}。`);
    L.push(
      `本段档位只能在 ${seg.lo}~${seg.hi} 之间，段内逐张不许倒退。` +
        `${seg.last ? `本段最后一张（第 ${segmentTo(seg)} 张）就是整条主线的兑现单，必须 S 级。` : '本段不含兑现单。'}`,
    );
  }
  L.push(`目标类型：${b.cat.label}（${b.cat.id}）。`);
  const answers = Object.entries(b.interview);
  if (answers.length) {
    L.push('访谈答案（他亲口说的，必须用进拆解）：');
    for (const [k, v] of answers) L.push(`- ${questionOf(b.cat, k)} → ${v}`);
  }
  if (b.firstGoal) L.push('这是**首目标的第一段**：档位只能 E/D/C，一张一天，先验证他能坚持。');
  L.push('每张的 minutes 必须落在档位上限之内（超了整份作废）：');
  L.push(RANKS.map((r) => `${r} ≤ ${rankCapMinutes(r)} 分钟`).join(' · '));
  if (seg ? seg.last : windowIsLast(w))
    L.push(`兑现单（最后一张）时限必须 ≥ ${PLAN_FINAL_MINUTES} 分钟。`);
  L.push('minutes 是预计耗时，只作参考、不倒计时：做完拍证据交单即可。');
  L.push(PLAN_GUARD, '');
  L.push(
    seg
      ? `用 set_plan 只把本段这 ${seg.size} 张交上来（第 ${seg.from}~${segmentTo(seg)} 张，不要交别的段）。`
      : `用 set_plan 把这 ${w.size} 张交上来${windowIsWhole(w) ? '' : `（第 ${w.from}~${windowTo(w)} 张，不要交别的段）`}。`,
  );
  return L.join('\n').trim();
}

/** 她这一轮的场合 */
export function briefScenario(b: PlanBrief): string {
  const w = briefWindow(b);
  const seg = b.segment ?? null;
  const span = seg
    ? `（这一轮只拆第 ${seg.from}~${segmentTo(seg)} 张）`
    : windowIsWhole(w)
      ? ''
      : `（滚动生成：这一轮只拆第 ${w.from}~${windowTo(w)} 张）`;
  return (
    `拆计划：把宿主的目标「${b.goalText}」拆成单次可执行的任务，` +
    `期限 ${b.days} 天、整条主线共 ${w.total} 张${span}。` +
    '他现在的状态（等级/连击/主线进度）已经写在上面的宿主档案里，直接据此拆，用 set_plan 一次交上来。'
  );
}
