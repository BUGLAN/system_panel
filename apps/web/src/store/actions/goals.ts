/**
 * 换目标。
 */
import { createStore } from 'zustand/vanilla';
import { useStore } from 'zustand';
import { CRISIS_CARE_LINE, isCrisisText } from '@host/core/agent/guardrail';
import { isVagueGoal } from '@host/core/goal/categories';
import type { PlanFailure } from '@host/core/goal/planFailure';
import { goalHasMoreWindows } from '@host/core/model/goal';
import { game } from '../game';
import { confirmBox, sayMain, setUi } from '../uiStore';
import { resetBind, setBindText } from './bind';
import { go } from './nav';
import { asFailure, startServerJob, withPlanJob } from './planJob';

// ── 换目标 ───────────────────────────────────────────────

export interface SwapState {
  text: string;
  line: string;
  error: PlanFailure | null;
}
export const swapStore = createStore<SwapState>()(() => ({
  text: '',
  line: '要换？那就说清楚换成什么。[旧的那条]，说换就换。',
  error: null,
}));
export const useSwap = <T>(sel: (s: SwapState) => T) => useStore(swapStore, sel);

export function openGoalSwap(): void {
  const first = game().goal.plan.length === 0;
  swapStore.setState({
    text: first ? game().pendingGoal : '',
    error: null,
    line: first
      ? '一句话说清你想变成什么样。我先问三个问题，再排[第一段]。'
      : '要换？那就说清楚换成什么。[旧的那条]，说换就换。',
  });
  setUi({ sheet: 'goalSwap' });
}

export async function submitGoalSwap(): Promise<void> {
  const typed = swapStore.getState().text.trim();
  if (isCrisisText(typed)) {
    swapStore.setState({ error: null, line: CRISIS_CARE_LINE });
    return;
  }
  if (isVagueGoal(typed)) {
    swapStore.setState({ line: '太空了。说点具体的——[一句话]。' });
    return;
  }
  // 首次立目标：走绑定仪式的访谈（B2），带原文进去
  if (game().goal.plan.length === 0) {
    setUi({ sheet: null });
    resetBind();
    setBindText(typed);
    await go('onboard');
    return;
  }
  const ok = await confirmBox({
    title: '确认换线？',
    body: `「${game().goal.text}」\n确认后旧清单[整条撤下]。等级与连胜保留。`,
    yes: '确认换线',
    no: '算了',
    danger: true,
  });
  if (!ok) return;
  swapStore.setState({ error: null, line: '……行，让我把这条拆开。' });
  const r = await withPlanJob({ kind: 'swap', title: '换一条主线' }, (onProgress) =>
    startServerJob({ kind: 'swap', text: typed }, onProgress),
  );
  if (!r) return;
  if (!r.ok) {
    swapStore.setState({
      error: asFailure(r.error),
      line: '拆不动。[换个说法]再来。',
    });
    return;
  }
  const g = game().goal;
  setUi({ sheet: null });
  await go('main');
  sayMain(
    goalHasMoreWindows(g)
      ? `行。旧的撤了。${g.days} 天的路，先排了 [[${g.plan.length} 单]]，做完我再往下拆。「${typed}」——别又三天热度。`
      : `行。旧的撤了，新清单 [[${g.plan.length} 单]] 已经在你手上。「${typed}」——别又三天热度。`,
  );
}
