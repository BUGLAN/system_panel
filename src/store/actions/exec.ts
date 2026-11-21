/**
 * 接单 → 执行 → 交单 / 认输 / 超时 的编排。
 *  - 所有接单入口先弹「接单前简报」，点【开始计时】才记 startAt（B6）
 *  - 交单：先等在途校验（≤20s）→ 没证据不收 → 结算（当场落盘）→ 窗口走完 / 收官再续拆 → 结算演出
 *  - 认输 / 超时：补救单顶替这一环（主线）；护盾在计时单到点时挡一次（docs/01 Q3）
 */
import { createStore } from 'zustand/vanilla';
import { useStore } from 'zustand';
import { LINES, fillLine } from '../../core/data/lines';
import { itemById, type ItemId } from '../../core/data/items';
import { goalFirstOpenIndex } from '../../core/model/goal';
import type { Quest } from '../../core/model/quest';
import type { QuestResult } from '../../core/flow/types';
import { checkTimeout, fail, settle } from '../../core/flow/settle';
import { QuestFlow } from '../../core/flow/questFlow';
import { dayKey } from '../../core/time/day';
import { pad2 } from '../../core/format';
import type { PlanFailure } from '../../core/goal/planFailure';
import { sfx } from '../../audio/sfx';
import { haptic } from '../../ui/haptics';
import { flash, shake } from '../../ui/fx/fx';
import { commitFlow, game, now, runFlow } from '../game';
import { sayHome, sayMain, sayWatch, setUi, toast, uiStore } from '../uiStore';
import { evidenceStore, evidenceUrl, resetEvidenceUi, waitForChecks } from './evidence';
import { go } from './nav';
import { followUpPlan } from './plan';
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
  const f = new QuestFlow(g);
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
  runFlow((f) => f.accept(q, now()));
  resetEvidenceUi();
  setUi({ briefing: null });
  sfx.play('stamp');
  haptic.tap();
  await go('exec');
  sayWatch(q.timed ? '任务开始。我会[一直]看着你。' : '打卡单不计时。做完拍下来，今天之内交。');
}

export function equipItem(id: ItemId): void {
  const f = new QuestFlow(game());
  const why = f.itemBlock(id);
  const it = itemById(id);
  if (why) {
    sfx.play('error');
    toast(`${it?.name ?? ''}：${why}`, 'err');
    return;
  }
  f.useItem(id);
  commitFlow(f);
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
  const a0 = game().active;
  if (!a0) return;
  await waitForChecks(a0.evidence.map((e) => e.id));
  const a = game().active;
  if (!a || a.task.serial !== a0.task.serial) return;
  if (!a.evidence.length) {
    sfx.play('error');
    haptic.fail();
    shake(5, 300);
    toast('没有证据，她不收。先上传截图。', 'err');
    sayWatch('空手来交差？先[上传截图]。');
    return;
  }
  execStore.setState({ settling: true });
  try {
    const firstId = a.evidence[0]?.id ?? null;
    const evUrl = firstId ? await evidenceUrl(firstId) : null;
    const f = new QuestFlow(game());
    const result = settle(f, { now: now() });
    commitFlow(f); // G4.1：结清就落盘，之后再去拆
    let followUpError: PlanFailure | null = null;
    if (result.windowEnd || result.finale) {
      followUpError = await followUpPlan(result.windowEnd ? 'window' : 'finale');
      if (!followUpError && result.windowEnd) result.windowNext = true;
    }
    result.empty = game().queue.length === 0;
    setUi({ show: { kind: 'verdict', result, evidenceUrl: evUrl, line: verdictLine(result), followUpError } });
  } finally {
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
    const today = dayKey(now());
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
  if (r.titles.length) setUi({ achQueue: [...uiStore.getState().achQueue, ...r.titles], archiveDot: true });
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

/** 按住认输满了 */
export async function giveUp(): Promise<void> {
  const r = runFlow((f) => fail(f, { now: now(), how: 'quit' }));
  if (!r) return;
  sfx.play('fail');
  haptic.fail();
  flash('fail');
  shake(10, 500);
  resetEvidenceUi();
  setUi({ show: { kind: 'fail', outcome: r, line: '认输也是一种勇气。不过，别养成习惯。' } });
}

/** 失败页：【接下补救单 · 现在做】→ 回大厅直接弹简报（B5） */
export async function takeRemedyNow(): Promise<void> {
  const q = runFlow((f) => f.takeRemedy(true));
  setUi({ show: null });
  await go('home', { noHist: true });
  if (q) setUi({ briefing: q });
}

/** 失败页：「先放委托板，回大厅」 */
export async function takeRemedyLater(): Promise<void> {
  runFlow((f) => f.takeRemedy(false));
  setUi({ show: null });
  await go('home', { noHist: true });
  sayHome('补救单放委托板上了。[24 小时]，别让它过期。');
}

// ── 每秒：计时单到点 → 护盾挡一次 / 超时判负 ──────────────────

onSecond((t) => {
  const a = game().active;
  if (!a || !a.task.timed) return;
  if (execStore.getState().settling || evidenceStore.getState().waiting) return;
  if (uiStore.getState().show) return;
  const f = new QuestFlow(game());
  const out = checkTimeout(f, t);
  if (out.kind === 'none') return;
  commitFlow(f);
  if (out.kind === 'shield') {
    sfx.play('shield');
    flash();
    toast(`护盾碎了：再给你 ${out.extendMin} 分钟。`, 'ok');
    sayWatch(fillLine(LINES.shieldBreak, { m: `${out.extendMin} 分钟` }));
    return;
  }
  sfx.play('fail');
  haptic.fail();
  flash('fail');
  resetEvidenceUi();
  setUi({ show: { kind: 'fail', outcome: out.outcome, line: '时间到了。……下次别拖到最后一秒。' } });
});
