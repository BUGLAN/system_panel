/**
 * 接单 → 执行 → 交单 / 认输 / 超时 的编排（规则都在服务端跑，这里管界面节奏与演出）。
 *  - 所有接单入口先弹「接单前简报」，点【开始计时】才记 startAt（服务器时间，B6）
 *  - 交单：服务端等在途校验（≤20s）→ 没证据不收 → 结算落库 → 窗口走完 / 收官起续拆任务 → 等任务 → 结算演出
 *  - 认输 / 超时：补救单顶替这一环（主线）；护盾在计时单到点时挡一次（docs/01 Q3），到点由服务端判
 */
import { createStore } from 'zustand/vanilla';
import { useStore } from 'zustand';
import type { FlowEvent, GiveUpOk, SubmitOk } from '@host/core/api/types';
import { LINES, fillLine } from '@host/core/data/lines';
import { itemById, type ItemId } from '@host/core/data/items';
import { goalFirstOpenIndex } from '@host/core/model/goal';
import type { Quest } from '@host/core/model/quest';
import type { FailOutcome, QuestResult } from '@host/core/flow/types';
import { deadlineOf } from '@host/core/flow/settle';
import { dayKey } from '@host/core/time/day';
import { pad2 } from '@host/core/format';
import type { PlanFailure } from '@host/core/goal/planFailure';
import { sfx } from '../../audio/sfx';
import { haptic } from '../../ui/haptics';
import { flash, shake } from '../../ui/fx/fx';
import { flowOf, game, intent, now, onFlowEvents, online, tz } from '../game';
import { onStream, setActiveReader } from '../stream';
import { sayHome, sayMain, sayWatch, setUi, toast, uiStore } from '../uiStore';
import { evidenceStore, evidenceUrl, resetEvidenceUi } from './evidence';
import { go } from './nav';
import { awaitFollowUp } from './plan';
import { onSecond } from './session';

export interface ExecState {
  settling: boolean;
}
export const execStore = createStore<ExecState>()(() => ({ settling: false }));
export const useExec = <T>(sel: (s: ExecState) => T) => useStore(execStore, sel);

/** 点了一张单：执行中有单就回执行页；主线没解封就拦一句；否则弹简报 */
export function openBriefing(q: Quest): void {
  const g = game();
  if (g.active) {
    sfx.play('error');
    toast('你手上还有一单没交差。', 'err');
    void go('exec');
    return;
  }
  const f = flowOf(g);
  if (f.isMainLocked(q)) {
    sfx.play('error');
    const first = goalFirstOpenIndex(g.goal);
    toast(`主线第 ${pad2(q.planIndex + 1)} 单还没解封：先做第 ${pad2(first + 1)} 单。`, 'err');
    return;
  }
  setUi({ briefing: q });
}

/** 简报里点【开始计时】/【开始 · 不计时】 */
export async function startQuest(q: Quest): Promise<void> {
  if (game().active) return;
  if (!game().queue.some((x) => x.serial === q.serial)) {
    toast('这张单已经不在她手里了。', 'err');
    setUi({ briefing: null });
    return;
  }
  const r = await intent('/api/flow/accept', { serial: q.serial });
  if (!r.ok) {
    sfx.play('error');
    toast(r.err.message, 'err');
    if (r.err.code === 'stale') setUi({ briefing: null });
    return;
  }
  resetEvidenceUi();
  setUi({ briefing: null });
  sfx.play('stamp');
  haptic.tap();
  await go('exec');
  sayWatch(q.timed ? '任务开始。我会[一直]看着你。' : '打卡单不计时。做完拍下来，今天之内交。');
}

export async function equipItem(id: ItemId): Promise<void> {
  const why = flowOf().itemBlock(id);
  const it = itemById(id);
  if (why) {
    sfx.play('error');
    toast(`${it?.name ?? ''}：${why}`, 'err');
    return;
  }
  const r = await intent('/api/flow/equip', { item: id });
  if (!r.ok) {
    sfx.play('error');
    toast(r.err.message, 'err');
    return;
  }
  sfx.play('coin');
  sayWatch(id === 'dbl' ? LINES.itemDbl : id === 'crit' ? LINES.itemCrit : LINES.itemShield);
}

export function minimize(): void {
  toast('任务在后台继续计时。她还在看着。');
  void go('home');
}

/** 评级评语（E2.2：B / C 说清原因） */
export function verdictLine(r: QuestResult): string {
  if (r.crit) return '暴击？！……咳，数据异常，我会复核的。（偷偷记下了）';
  switch (r.grade) {
    case 'S':
      return '……我无话可说。这次算你狠。';
    case 'A':
      return '……行吧，挑不出毛病。[我没有在夸你]。';
    case 'B':
      return '差一口气：证据我没核上，或者快得不像话。下次稳一点。';
    default:
      return '证据没核上，还快得离谱。这叫「到此一游」，勉强收下。';
  }
}

/** 【提交任务】 */
export async function submitQuest(): Promise<void> {
  if (execStore.getState().settling || evidenceStore.getState().waiting) return;
  const a = game().active;
  if (!a) return;
  if (!a.evidence.length) {
    sfx.play('error');
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
      sfx.play('error');
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
  if (r.titles.length)
    setUi({ achQueue: [...uiStore.getState().achQueue, ...r.titles], archiveDot: true });
  if (r.planClear >= 0) {
    setUi({ mainJustDone: r.planClear });
    await go('main', { noHist: true });
    if (followUpError) sayMain('这一单记上了。下一段没拆出来——[重试拆解]在这儿。');
    else if (r.finale) sayMain('整条主线走完了。下一条，我已经排好了。');
    else if (r.windowNext) sayMain('这一段走完了。下一段接上了，[别停]。');
    return;
  }
  if (r.empty) {
    await go('home', { noHist: true });
    sayHome('收工。今天的单清干净了。明天再来。');
    return;
  }
  await go('board', { noHist: true });
}

function showFail(outcome: FailOutcome, line: string): void {
  sfx.play('fail');
  haptic.fail();
  flash('fail');
  resetEvidenceUi();
  setUi({ show: { kind: 'fail', outcome, line } });
}

/** 按住认输满了 */
export async function giveUp(): Promise<void> {
  const a = game().active;
  if (!a) return;
  const r = await intent<GiveUpOk & Record<string, unknown>>('/api/flow/give-up', {
    serial: a.task.serial,
  });
  if (!r.ok) {
    sfx.play('error');
    toast(r.err.message, 'err');
    if (r.err.code === 'stale') void go('home');
    return;
  }
  shake(10, 500);
  showFail(r.r.outcome, '认输也是一种勇气。不过，别养成习惯。');
}

/** 失败页：【接下补救单 · 现在做】→ 回大厅直接弹简报（B5） */
export async function takeRemedyNow(): Promise<void> {
  const r = await intent<{ quest: Quest | null }>('/api/flow/take-remedy', { now: true });
  setUi({ show: null });
  await go('home', { noHist: true });
  if (!r.ok) toast(r.err.message, 'err');
  else if (r.r.quest) setUi({ briefing: r.r.quest });
}

/** 失败页：「先放委托板，回大厅」 */
export async function takeRemedyLater(): Promise<void> {
  const r = await intent('/api/flow/take-remedy', { now: false });
  setUi({ show: null });
  await go('home', { noHist: true });
  if (!r.ok) toast(r.err.message, 'err');
  else sayHome('补救单放委托板上了。[24 小时]，别让它过期。');
}

// ── 服务端判出来的事：护盾碎 / 超时判负 ─────────────────────────

onFlowEvents((events: FlowEvent[]) => {
  for (const e of events) {
    if (e.kind === 'shield') {
      sfx.play('shield');
      flash();
      toast(`护盾碎了：再给你 ${e.extendMin} 分钟。`, 'ok');
      sayWatch(fillLine(LINES.shieldBreak, { m: `${e.extendMin} 分钟` }));
    } else if (e.kind === 'timeout') {
      if (uiStore.getState().show) continue;
      showFail(e.outcome, '时间到了。……下次别拖到最后一秒。');
    }
  }
});

// ── 每秒：本地走到截止时刻 → 请服务端判（护盾挡一次 / 超时判负）──────────

let tickAt = 0;
onSecond((t) => {
  const a = game().active;
  if (!a || !a.task.timed) return;
  if (execStore.getState().settling || evidenceStore.getState().waiting) return;
  if (uiStore.getState().show) return;
  if (t < deadlineOf(a) || !online()) return;
  if (Date.now() - tickAt < 5_000) return;
  tickAt = Date.now();
  void intent('/api/flow/tick');
});

// ── 另一台设备改了存档：本地已同步；执行页上的这一单没了就回大厅 ──────────

setActiveReader(() => game().active?.task.serial ?? null);
onStream({
  remote: (prev) => {
    if (prev === null || game().active?.task.serial === prev) return;
    const ui = uiStore.getState();
    if (ui.show) return;
    resetEvidenceUi();
    if (ui.scene === 'exec') void go('home', { noHist: true });
    toast('另一台设备刚改过存档，已同步。');
  },
});
