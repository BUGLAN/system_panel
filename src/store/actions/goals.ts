/**
 * 委托板「再要一批」、补给购买 / 补签、名牒佩戴、换目标。
 */
import { createStore } from 'zustand/vanilla';
import { useStore } from 'zustand';
import { asPlanFailure, buildGoalWithAgent } from '../../agent/goalBuilder';
import { statusLineOf } from '../../agent/chatTools';
import { CRISIS_CARE_LINE, isCrisisText } from '../../agent/guardrail';
import { itemById } from '../../core/data/items';
import { titleName } from '../../core/data/titles';
import { isVagueGoal } from '../../core/goal/categories';
import { DAILY_CAP } from '../../core/goal/daily';
import type { PlanFailure } from '../../core/goal/planFailure';
import { goalHasMoreWindows } from '../../core/model/goal';
import { sfx } from '../../audio/sfx';
import { game, now, runFlow } from '../game';
import { memory, textClientAny } from '../services';
import { confirmBox, sayMain, setUi, toast } from '../uiStore';
import { resetBind, setBindText } from './bind';
import { go } from './nav';
import { withPlanJob } from './planJob';

/** 委托板清空后「再要一批委托」：补 2 张日常（日上限 6） */
export function refillDailies(): void {
  const inQueue = game().queue.filter((q) => q.kind === 'daily').length;
  const room = Math.max(0, DAILY_CAP - inQueue);
  if (room === 0) {
    toast('今天的日常已经给满了。', 'err');
    return;
  }
  runFlow((f) => {
    f.queue.push(...f.genDailies(Math.min(2, room)));
    f.notify();
  });
  sfx.play('success');
  toast('她叹了口气，又塞给你几单。', 'ok');
}

export function buyItem(id: string): boolean {
  const it = itemById(id);
  const ok = runFlow((f) => {
    const why = f.buyBlock(id);
    if (why) {
      sfx.play('error');
      toast(why === '晶核不够。' ? '钱包比你的决心还薄。' : `${it?.name ?? ''}：${why}`, 'err');
      return false;
    }
    return f.buy(id);
  });
  if (ok) {
    sfx.play('buy');
    toast(`${it?.name ?? ''} ×1 入库。别浪费。`, 'ok');
  }
  return ok;
}

export function applyPatchTicket(): boolean {
  const t = now();
  const r = runFlow((f) => {
    const st = f.patchStatus(t);
    if (!st.ok) {
      sfx.play('error');
      toast(st.reason, 'err');
      return false;
    }
    return f.usePatch(t);
  });
  if (r) {
    sfx.play('success');
    toast(`补签成功，连胜回到 ${game().host.streak} 天。这叫补救，不叫作弊。`, 'ok');
  }
  return r;
}

export function wearTitle(id: string): void {
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
  runFlow((f) => f.equip(id));
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
  const prevId = game().goal.at;
  swapStore.setState({ error: null, line: '……行，让我把这条拆开。' });
  const r = await withPlanJob({ kind: 'swap', title: '换一条主线' }, (onProgress) =>
    buildGoalWithAgent({
      client: textClientAny(),
      text: typed,
      at: now(),
      statusLine: statusLineOf(game()),
      digest: (q) => memory().digest(q),
      onProgress,
    }),
  );
  if (!r) return;
  if (!r.ok) {
    sfx.play('error');
    swapStore.setState({ error: asPlanFailure(r.error), line: '拆不动。[换个说法]再来，或者先问问我。' });
    return;
  }
  if (game().goal.at !== prevId) return; // 等待期间目标变了：作废
  const g = r.value.goal;
  runFlow((f) => f.newGoal(g));
  sfx.play('unlock');
  setUi({ sheet: null });
  await go('main');
  sayMain(
    goalHasMoreWindows(g)
      ? `行。旧的撤了。${g.days} 天的路，先排了 [[${g.plan.length} 单]]，做完我再往下拆。「${typed}」——别又三天热度。`
      : `行。旧的撤了，新清单 [[${g.plan.length} 单]] 已经在你手上。「${typed}」——别又三天热度。`,
  );
}
