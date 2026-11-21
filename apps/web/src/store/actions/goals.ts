/**
 * 委托板「再要一批」、补给购买 / 补签、名牒佩戴、换目标。
 */
import { createStore } from 'zustand/vanilla';
import { useStore } from 'zustand';
import { CRISIS_CARE_LINE, isCrisisText } from '@host/core/agent/guardrail';
import { itemById } from '@host/core/data/items';
import { titleName } from '@host/core/data/titles';
import { isVagueGoal } from '@host/core/goal/categories';
import { DAILY_CAP } from '@host/core/goal/daily';
import type { PlanFailure } from '@host/core/goal/planFailure';
import { goalHasMoreWindows } from '@host/core/model/goal';
import { sfx } from '../../audio/sfx';
import { flowOf, game, intent, now } from '../game';
import { confirmBox, sayMain, setUi, toast } from '../uiStore';
import { resetBind, setBindText } from './bind';
import { go } from './nav';
import { asFailure, startServerJob, withPlanJob } from './planJob';

/** 委托板清空后「再要一批委托」：补 2 张日常（日上限 6） */
export async function refillDailies(): Promise<void> {
  const inQueue = game().queue.filter((q) => q.kind === 'daily').length;
  if (Math.max(0, DAILY_CAP - inQueue) === 0) {
    toast('今天的日常已经给满了。', 'err');
    return;
  }
  const r = await intent('/api/flow/refill');
  if (!r.ok) {
    sfx.play('error');
    toast(r.err.message, 'err');
    return;
  }
  sfx.play('success');
  toast('她叹了口气，又塞给你几单。', 'ok');
}

export async function buyItem(id: string): Promise<boolean> {
  const it = itemById(id);
  const why = flowOf().buyBlock(id);
  const say = (w: string) =>
    toast(w === '晶核不够。' ? '钱包比你的决心还薄。' : `${it?.name ?? ''}：${w}`, 'err');
  if (why) {
    sfx.play('error');
    say(why);
    return false;
  }
  const r = await intent('/api/flow/buy', { item: id });
  if (!r.ok) {
    sfx.play('error');
    if (r.err.code === 'rejected') say(r.err.message);
    else toast(r.err.message, 'err');
    return false;
  }
  sfx.play('buy');
  toast(`${it?.name ?? ''} ×1 入库。别浪费。`, 'ok');
  return true;
}

export async function applyPatchTicket(): Promise<boolean> {
  const st = flowOf().patchStatus(now());
  if (!st.ok) {
    sfx.play('error');
    toast(st.reason, 'err');
    return false;
  }
  const r = await intent('/api/flow/patch');
  if (!r.ok) {
    sfx.play('error');
    toast(r.err.message, 'err');
    return false;
  }
  sfx.play('success');
  toast(`补签成功，连胜回到 ${game().host.streak} 天。这叫补救，不叫作弊。`, 'ok');
  return true;
}

export async function wearTitle(id: string): Promise<void> {
  const h = game().host;
  if (!h.ownedTitles.includes(id)) {
    sfx.play('error');
    toast('还没解锁。', 'err');
    return;
  }
  if (h.title === 'mouth') {
    sfx.play('error');
    toast('「口头巨人」摘不掉。完成一单再说。', 'err');
    return;
  }
  if (h.title === id) {
    toast('已经戴着了。再戴一次也不会更帅。');
    return;
  }
  const r = await intent('/api/flow/wear', { title: id });
  if (!r.ok) {
    sfx.play('error');
    toast(r.err.message, 'err');
    return;
  }
  sfx.play('unlock');
  toast(`已佩戴「${titleName(id)}」。她瞥了一眼，没说话。`, 'ok');
}

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
    sfx.play('error');
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
    body: `「${game().goal.text}」\n确认后旧清单[整条撤下]。等级 / 晶核 / 六维保留。`,
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
    sfx.play('error');
    swapStore.setState({
      error: asFailure(r.error),
      line: '拆不动。[换个说法]再来，或者先问问我。',
    });
    return;
  }
  const g = game().goal;
  sfx.play('unlock');
  setUi({ sheet: null });
  await go('main');
  sayMain(
    goalHasMoreWindows(g)
      ? `行。旧的撤了。${g.days} 天的路，先排了 [[${g.plan.length} 单]]，做完我再往下拆。「${typed}」——别又三天热度。`
      : `行。旧的撤了，新清单 [[${g.plan.length} 单]] 已经在你手上。「${typed}」——别又三天热度。`,
  );
}
