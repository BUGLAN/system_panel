/**
 * 业务唯一真源：在手的主线单 / 接单 / 证据 / 换日与连胜。结算在 settle.ts。
 * 移植自 flutter-final:app/lib/state/quest_flow.dart（计时、道具、日常、补救、换一个都已拿掉）。
 *
 * 用法：`const f = new QuestFlow(game, { tz })` 拿到存档的**深拷贝**，调方法就地改，
 * 最后读 `f.save` 拿新存档；`f.changed` 为真才需要提交。数值只能经结算进档案。
 */
import { fmtDur } from '../format';
import {
  evidenceAccepted,
  type ActiveQuest,
  type EvidenceShot,
  type EvidenceStatus,
} from '../model/active';
import {
  goalFirstOpenIndex,
  goalId,
  goalTaskAt,
  goalTotalTasks,
  planTaskOpen,
  type Goal,
} from '../model/goal';
import type { HostState } from '../model/host';
import type { Quest } from '../model/quest';
import type { FlowMeta, SaveData } from '../save/saveData';
import { dayKey, daysBetween } from '../time/day';
import type { EvidenceApply, HistoryEntry } from './types';

/** 执行页最多挂 3 张证据 */
export const MAX_EVIDENCE = 3;
/** 手里同时挂几张还没做完的主线单（只发当前这一张） */
export const PLAN_PUBLISH_WINDOW = 1;

export class QuestFlow {
  readonly save: SaveData;
  /** 宿主账号的时区（换日 / 连胜按它算「哪一天」；缺省 = 运行环境本地时区） */
  readonly tz: string | undefined;
  /** 改过存档字段 */
  changed = false;
  /** 待追加的流水（提交后写进 history 表） */
  readonly history: HistoryEntry[] = [];

  constructor(game: SaveData, opts: { tz?: string } = {}) {
    this.save = structuredClone(game);
    this.tz = opts.tz;
  }

  get host(): HostState {
    return this.save.host;
  }
  get goal(): Goal {
    return this.save.goal;
  }
  set goal(g: Goal) {
    this.save.goal = g;
  }
  get queue(): Quest[] {
    return this.save.queue;
  }
  get active(): ActiveQuest | null {
    return this.save.active;
  }
  set active(a: ActiveQuest | null) {
    this.save.active = a;
  }
  get meta(): FlowMeta {
    return this.save.meta;
  }
  get head(): Quest | null {
    return this.queue[0] ?? null;
  }

  notify(): void {
    this.changed = true;
  }

  /** 发一个新单号 */
  nextSerial(): number {
    return this.meta.nextSerial++;
  }

  /** 属于当前主线的单（占着在手窗口） */
  private holdsPlanSlot(q: Quest): boolean {
    return q.goalId === goalId(this.goal) && q.planIndex >= 0;
  }

  /** 没主线、但记着一句没拆成的目标 → 大厅 / 主线页给「重试拆解」 */
  get canRetryPlan(): boolean {
    return this.goal.plan.length === 0 && this.save.pendingGoal.length > 0;
  }

  /** 清单走完、下一段 / 下一条主线没拆上、手上没执行中的单 → 给「重试拆解」 */
  get canResumePlan(): boolean {
    return this.active === null && this.goal.plan.length > 0 && goalFirstOpenIndex(this.goal) < 0;
  }

  // ── 造单 ──────────────────────────────────────────────────

  /** 清单第 i 张 → 一张主线单 */
  planTask(i: number): Quest {
    const t = this.goal.plan[i];
    if (!t) throw new Error(`planTask：清单里没有第 ${i} 张`);
    return {
      serial: this.nextSerial(),
      planIndex: i,
      planTotal: goalTotalTasks(this.goal),
      goalId: goalId(this.goal),
      name: t.title,
      reason: this.reasonForMain(i),
      proof: t.proof,
      minutes: t.minutes,
      rank: t.rank,
    };
  }

  reasonForMain(i: number): string {
    if (i > 0 && i < this.goal.plan.length) {
      const held = this.goal.plan[i - 1]?.heldMs;
      if (held !== null && held !== undefined)
        return `上一张你用了 ${fmtDur(held)}。这一张，我加了点码。`;
    }
    return `你说要「${this.goal.text}」。那就从这一步开始。`;
  }

  // ── 在手窗口 ──────────────────────────────────────────────

  /** 主线单补发：保持在手 [window] 张（含执行中的那张），幂等，按清单顺序 */
  publishPlanTasks(window = PLAN_PUBLISH_WINDOW): Quest[] {
    const out: Quest[] = [];
    const act = this.active?.task ?? null;
    let inHand = this.queue.filter((q) => this.holdsPlanSlot(q)).length;
    if (act && this.holdsPlanSlot(act)) inHand++;
    for (const t of this.goal.plan) {
      if (inHand >= window) break;
      if (!planTaskOpen(t)) continue;
      const taken =
        this.queue.some((q) => this.holdsPlanSlot(q) && q.planIndex === t.index) ||
        (act !== null && this.holdsPlanSlot(act) && act.planIndex === t.index);
      if (taken) continue;
      const q = this.planTask(t.index);
      this.queue.push(q);
      out.push(q);
      inHand++;
    }
    if (out.length) {
      this.queue.sort((a, b) => a.planIndex - b.planIndex);
      this.notify();
    }
    return out;
  }

  /** 主线单只能接清单里第一张没完成的（E1.3） */
  isMainLocked(q: Quest): boolean {
    if (q.goalId !== goalId(this.goal)) return false;
    const first = goalFirstOpenIndex(this.goal);
    return first >= 0 && q.planIndex !== first;
  }

  /** 拆解失败「先跳过」：记住目标（之后在大厅重试） */
  skipPlan(text: string): void {
    const t = text.trim();
    if (t) this.save.pendingGoal = t;
    this.notify();
  }

  /** 换目标 / 首次立目标落库：旧主线单撤下、新主线进在手窗口 */
  newGoal(next: Goal): Quest {
    if (next.plan.length === 0)
      throw new Error(`newGoal：目标「${next.text}」没有任务清单，不能落库`);
    this.queue.splice(0, this.queue.length);
    this.goal = next;
    this.save.pendingGoal = '';
    const pub = this.publishPlanTasks();
    this.notify();
    const first = pub[0];
    if (!first) throw new Error(`newGoal：目标「${next.text}」落库后没有任何一张单被派出来`);
    return first;
  }

  /** 收官后铸好的下一条主线落库（与 newGoal 同语义，但允许首环已在手） */
  applyNextGoal(next: Goal): Quest | null {
    if (next.plan.length === 0) throw new Error(`收官交回的目标「${next.text}」没有任务清单`);
    this.queue.splice(0, this.queue.length);
    this.goal = next;
    const pub = this.publishPlanTasks();
    this.notify();
    return pub[0] ?? null;
  }

  /** 续拆落库：同一个目标、清单变长 */
  applyNextWindow(next: Goal): void {
    const prev = this.goal;
    if (goalId(next) !== goalId(prev) || next.plan.length <= prev.plan.length) {
      throw new Error(
        `续拆交回的目标不对：身份 ${goalId(next)}（应为 ${goalId(prev)}），清单 ${next.plan.length} 张（原 ${prev.plan.length} 张）`,
      );
    }
    this.goal = next;
    this.publishPlanTasks();
    this.notify();
  }

  // ── 接单 / 证据 ───────────────────────────────────────────

  /** 接单：出队 + 记 startAt */
  accept(t: Quest, now: number): void {
    const keep = this.queue.filter((q) => q.serial !== t.serial);
    this.queue.splice(0, this.queue.length, ...keep);
    this.active = { task: t, startAt: now, evidence: [], sealed: false };
    this.notify();
  }

  /** 挂证据：最多 3 张；判定不符的不入槽 */
  addEvidence(shot: EvidenceShot): boolean {
    const a = this.active;
    if (!a || a.sealed) return false;
    if (!evidenceAccepted(shot.status)) return false;
    if (a.evidence.length >= MAX_EVIDENCE) return false;
    a.evidence.push(shot);
    this.notify();
    return true;
  }

  /** 后台校验回来：不符撤槽 / 其余换状态照收 / 找不到或已封存 → gone */
  applyVerdict(id: string, status: EvidenceStatus, note: string): EvidenceApply {
    const a = this.active;
    if (!a || a.sealed) return 'gone';
    const i = a.evidence.findIndex((e) => e.id === id);
    if (i < 0) return 'gone';
    if (!evidenceAccepted(status)) {
      a.evidence.splice(i, 1);
      this.notify();
      return 'rejected';
    }
    a.evidence[i] = { ...(a.evidence[i] as EvidenceShot), status, note };
    this.notify();
    return 'kept';
  }

  removeEvidence(id: string): boolean {
    const a = this.active;
    if (!a || a.sealed) return false;
    const n = a.evidence.length;
    a.evidence = a.evidence.filter((e) => e.id !== id);
    if (a.evidence.length === n) return false;
    this.notify();
    return true;
  }

  // ── 换日与连胜 ────────────────────────────────────────────

  /** 断签检查：最近完成日在前天或更早、连胜还挂着 → 当场归零 */
  checkStreak(now: number): boolean {
    const today = dayKey(now, this.tz);
    const last = this.meta.lastDoneDay;
    if (last === null || this.host.streak <= 0) return false;
    if (daysBetween(last, today) < 2) return false;
    this.host.streak = 0;
    this.notify();
    return true;
  }

  /** 换日：同一天反复进出只做一次。断签检查 → 主线单补回手上 */
  rollDay(now: number): boolean {
    const today = dayKey(now, this.tz);
    if (this.meta.lastRollDay === today) return false;
    this.meta.lastRollDay = today;
    this.checkStreak(now);
    this.publishPlanTasks();
    this.notify();
    return true;
  }
}

/** 当前主线的单（含旧档里顶替某一环的补救单）：结算时划掉清单那一张 */
export function planSlotOf(goal: Goal, q: Quest): number {
  return q.goalId === goalId(goal) && goalTaskAt(goal, q.planIndex) ? q.planIndex : -1;
}
