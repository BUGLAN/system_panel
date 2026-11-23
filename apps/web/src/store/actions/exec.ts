/**
 * 接单 → 执行 → 交单 的编排（规则都在服务端跑，这里管界面节奏与演出）。
 *  - 所有接单入口先弹「接单前简报」，点【开始】才记 startAt（服务器时间，B6）；不计时、不判超时
 *  - 交单：服务端等在途校验（≤20s）→ 没证据不收 → 结算落库 → 窗口走完 / 收官起续拆任务 → 等任务 → 结算演出
 */
import { createStore } from 'zustand/vanilla';
import { useStore } from 'zustand';
import type { SubmitOk } from '@host/core/api/types';
import { goalFirstOpenIndex } from '@host/core/model/goal';
import type { Quest } from '@host/core/model/quest';
import type { QuestResult } from '@host/core/flow/types';
import { dayKey } from '@host/core/time/day';
import { pad2 } from '@host/core/format';
import type { PlanFailure } from '@host/core/goal/planFailure';
import { haptic } from '../../ui/haptics';
import { shake } from '../../ui/fx/fx';
import { flowOf, game, intent, now, tz } from '../game';
import { onStream, setActiveReader } from '../stream';
import { sayHome, sayMain, sayWatch, setUi, toast, uiStore } from '../uiStore';
import { evidenceStore, evidenceUrl, resetEvidenceUi } from './evidence';
import { go } from './nav';
import { awaitFollowUp } from './plan';

export interface ExecState {
  settling: boolean;
}
export const execStore = createStore<ExecState>()(() => ({ settling: false }));
export const useExec = <T>(sel: (s: ExecState) => T) => useStore(execStore, sel);

/** 点了一张单：执行中有单就回执行页；主线没解封就拦一句；否则弹简报 */
export function openBriefing(q: Quest): void {
  const g = game();
  if (g.active) {
    toast('你手上还有一单没交差。', 'err');
    void go('exec');
    return;
  }
  const f = flowOf(g);
  if (f.isMainLocked(q)) {
    const first = goalFirstOpenIndex(g.goal);
    toast(`主线第 ${pad2(q.planIndex + 1)} 单还没解封：先做第 ${pad2(first + 1)} 单。`, 'err');
    return;
  }
  setUi({ briefing: q });
}

/** 大厅点「委托」：执行中 → 回执行页；手上有当前这一张 → 弹简报 */
export function openCurrentQuest(): boolean {
  const g = game();
  if (g.active) {
    void go('exec');
    return true;
  }
  const q = g.queue[0];
  if (!q) return false;
  openBriefing(q);
  return true;
}

/** 简报里点【开始】 */
export async function startQuest(q: Quest): Promise<void> {
  if (game().active) return;
  if (!game().queue.some((x) => x.serial === q.serial)) {
    toast('这张单已经不在她手里了。', 'err');
    setUi({ briefing: null });
    return;
  }
  const r = await intent('/api/flow/accept', { serial: q.serial });
  if (!r.ok) {
    toast(r.err.message, 'err');
    if (r.err.code === 'stale') setUi({ briefing: null });
    return;
  }
  resetEvidenceUi();
  setUi({ briefing: null });
  haptic.tap();
  await go('exec');
  sayWatch('去做吧。做完拍下来交给我，我会[一直]看着你。');
}

export function minimize(): void {
  toast('这一单先挂着。做完回来交。');
  void go('home');
}

/** 验收评语：证据核上了 / 没核上 */
export function verdictLine(r: QuestResult): string {
  if (r.verified > 0) return '……行吧，挑不出毛病。[我没有在夸你]。';
  return '证据我没核上。先收下了，下次拍清楚点。';
}

/** 【提交任务】 */
export async function submitQuest(): Promise<void> {
  if (execStore.getState().settling || evidenceStore.getState().waiting) return;
  const a = game().active;
  if (!a) return;
  if (!a.evidence.length) {
    haptic.fail();
    shake(5, 300);
    toast('没有证据，她不收。先上传截图。', 'err');
    sayWatch('空手来交差？先[上传截图]。');
    return;
  }
  // 有在途校验：服务端最多等 20 秒，这期间主键显示「她在验证据…」
  const checking = evidenceStore.getState().checking.length > 0;
  evidenceStore.setState({ waiting: checking });
  execStore.setState({ settling: true });
  try {
    const firstId = a.evidence[0]?.id ?? null;
    const r = await intent<SubmitOk & Record<string, unknown>>('/api/flow/submit', {
      serial: a.task.serial,
    });
    evidenceStore.setState({ waiting: false, checking: [] });
    if (!r.ok) {
      if (r.err.code === 'rejected') {
        haptic.fail();
        shake(5, 300);
        sayWatch('空手来交差？先[上传截图]。');
      }
      toast(r.err.message, 'err');
      return;
    }
    const result = r.r.result;
    const evUrl = firstId ? await evidenceUrl(firstId) : null;
    let followUpError: PlanFailure | null = null;
    if (r.r.followUp) {
      followUpError = await awaitFollowUp(
        r.r.followUp.jobId,
        result.windowEnd ? 'window' : 'finale',
      );
      if (!followUpError && result.windowEnd) result.windowNext = true;
    }
    result.empty = game().queue.length === 0;
    setUi({
      show: {
        kind: 'verdict',
        result,
        evidenceUrl: evUrl,
        line: verdictLine(result),
        followUpError,
      },
    });
  } finally {
    evidenceStore.setState({ waiting: false });
    execStore.setState({ settling: false });
  }
}

let lastLevelUpDay: string | null = null;

/** 结算演出里点【收下】 */
export async function closeVerdict(): Promise<void> {
  const show = uiStore.getState().show;
  if (!show || show.kind !== 'verdict') return;
  const r = show.result;
  setUi({ show: null });
  if (r.ups.length) {
    const today = dayKey(now(), tz());
    const brief = lastLevelUpDay === today;
    lastLevelUpDay = today;
    pendingAfter = { r, err: show.followUpError };
    setUi({ show: { kind: 'levelup', from: r.beforeLv, to: r.afterLv, brief } });
    return;
  }
  await afterSettle(r, show.followUpError);
}

/** 升级叠层点掉之后 */
export async function closeLevelUp(): Promise<void> {
  setUi({ show: null });
  const p = pendingAfter;
  pendingAfter = null;
  if (p) await afterSettle(p.r, p.err);
}

/** 结算演出 → 升级叠层 → 收尾，中间这一拍记着结果 */
let pendingAfter: { r: QuestResult; err: PlanFailure | null } | null = null;

async function afterSettle(r: QuestResult, followUpError: PlanFailure | null): Promise<void> {
  if (r.planClear >= 0) {
    setUi({ mainJustDone: r.planClear });
    await go('main', { noHist: true });
    if (followUpError) sayMain('这一单记上了。下一段没拆出来——[重试拆解]在这儿。');
    else if (r.finale) sayMain('整条主线走完了。下一条，我已经排好了。');
    else if (r.windowNext) sayMain('这一段走完了。下一段接上了，[别停]。');
    return;
  }
  await go('home', { noHist: true });
  if (r.empty) sayHome('收工。这一张清掉了。');
}

// ── 另一台设备改了存档：本地已同步；执行页上的这一单没了就回大厅 ──────────

setActiveReader(() => game().active?.task.serial ?? null);
onStream({
  remote: (prev) => {
    const ui = uiStore.getState();
    if (ui.show) return;
    const g = game();
    // 另一台设备重置了存档：回绑定仪式
    if (
      g.goal.plan.length === 0 &&
      !g.pendingGoal &&
      !g.active &&
      !['onboard', 'auth', 'consent', 'boot'].includes(ui.scene)
    ) {
      resetEvidenceUi();
      setUi({ sheet: null, briefing: null });
      void go('onboard', { noHist: true });
      toast('另一台设备刚重置了存档。');
      return;
    }
    if (prev === null || g.active?.task.serial === prev) return;
    resetEvidenceUi();
    if (ui.scene === 'exec') void go('home', { noHist: true });
    toast('另一台设备刚改过存档，已同步。');
  },
});
