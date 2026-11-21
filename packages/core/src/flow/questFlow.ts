/**
 * 业务唯一真源：队列 / 接单 / 道具 / 暴击率 / 证据 / 换一个 / 补给 / 佩戴 / 补签 / 换日。
 * 结算与认输在 settle.ts。移植自 flutter-final:app/lib/state/quest_flow.dart。
 *
 * 用法：`const f = new QuestFlow(game, { rnd })` 拿到存档的**深拷贝**，调方法就地改，
 * 最后读 `f.save` 拿新存档；`f.changed` 为真才需要提交（= 旧版的 onChanged 通知）。
 * 数值只能经结算进档案。
 */
import { attrName } from '../data/attrs';
import { itemById, type ItemId } from '../data/items';
import { RANK_ATTR_POINTS, rankShift, type Rank } from '../data/rank';
import { critChance } from '../data/rewards';
import { fmtDur } from '../format';
import {
  dailyCountFor,
  dailyQuestFrom,
  genDailyCandidates,
  pickDailies,
  rollDayQueue,
  weakestAttr,
  type Rnd,
} from '../goal/daily';
import { splitAttrs } from '../goal/split';
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
import { addDays, dayKey, daysBetween } from '../time/day';
import type { EvidenceApply, HistoryEntry, RetreatOutcome } from './types';

/** 执行页最多挂 3 张证据 */
export const MAX_EVIDENCE = 3;
/** 队列里同时挂几张还没做完的计划单 */
export const PLAN_PUBLISH_WINDOW = 3;

export type PatchStatus = { ok: true; restoreTo: number } | { ok: false; reason: string };

export class QuestFlow {
  readonly save: SaveData;
  readonly rnd: Rnd;
  /** 宿主账号的时区（换日 / 连胜 / 补签按它算「哪一天」；缺省 = 运行环境本地时区） */
  readonly tz: string | undefined;
  /** 改过存档字段（= 旧版 onChanged） */
  changed = false;
  /** 待追加的流水（store 提交后写进 history 表） */
  readonly history: HistoryEntry[] = [];

  constructor(game: SaveData, opts: { rnd?: Rnd; tz?: string } = {}) {
    this.save = structuredClone(game);
    this.rnd = opts.rnd ?? Math.random;
    this.tz = opts.tz;
  }

  get host(): HostState {
    return this.save.host;
  }
  set host(h: HostState) {
    this.save.host = h;
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

  /** 顶替当前主线某一环的补救单 */
  isPlanRemedy(q: Quest): boolean {
    return q.kind === 'remedy' && q.goalId === goalId(this.goal) && q.planIndex >= 0;
  }

  /** 当前主线的单（含顶替某一环的补救单）占着在手窗口 */
  private holdsPlanSlot(q: Quest): boolean {
    return (q.kind === 'main' && q.goalId === goalId(this.goal)) || this.isPlanRemedy(q);
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
      kind: 'main',
      planIndex: i,
      planTotal: goalTotalTasks(this.goal),
      goalId: goalId(this.goal),
      name: t.title,
      reason: this.reasonForMain(i),
      proof: t.proof,
      minutes: t.minutes,
      rank: t.rank,
      attrs: Object.keys(t.attrs).length
        ? { ...t.attrs }
        : splitAttrs({ 体: 1 }, RANK_ATTR_POINTS[t.rank]),
      hinted: false,
      timed: t.timed,
    };
  }

  /** 日常：按类目池挑单（第一单专治最弱维、第二单贴主线） */
  genDailies(n: number): Quest[] {
    const catId = this.goal.cat || 'gen';
    const picks = pickDailies({
      candidates: genDailyCandidates(catId, this.rnd),
      attrs: this.host.attrs,
      goalCatId: catId,
      n,
      rnd: this.rnd,
    });
    return picks.map((t) =>
      dailyQuestFrom(t, { serial: this.nextSerial(), level: this.host.lv, rnd: this.rnd }),
    );
  }

  /** 当天该发几张日常就发几张 */
  genTodaysDailies(): Quest[] {
    return this.genDailies(dailyCountFor(this.host.lv, this.host.streak));
  }

  reasonForMain(i: number): string {
    if (i > 0 && i < this.goal.plan.length) {
      const held = this.goal.plan[i - 1]?.heldMs;
      if (held !== null && held !== undefined)
        return `上一张你用了 ${fmtDur(held)}。这一张，我加了点码。`;
    }
    return `你说要「${this.goal.text}」。那就从这一步开始。`;
  }

  reasonForRemedy(): string {
    return '补救。做完一半，就当那一笔没输。';
  }

  reasonFor(q: Quest): string {
    if (q.kind === 'main') return this.reasonForMain(q.planIndex);
    if (q.kind === 'remedy') return this.reasonForRemedy();
    if (q.hinted) return '昨天说好的那张。我替你留着呢。';
    const [wk, wv] = weakestAttr(this.host.attrs);
    if ((q.attrs[wk] ?? 0) > 0) return `你的${attrName(wk)}只有 ${wv}。这一单，专门治它。`;
    if (this.host.streak >= 2) return `连击 ${this.host.streak} 天。别断在这一单上。`;
    return '今天的。我挑过了。';
  }

  // ── 在手窗口 ──────────────────────────────────────────────

  /** 计划单补发：保持在手 [window] 张，幂等；主线单按清单顺序排到队首 */
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
      const gid = goalId(this.goal);
      const isMain = (q: Quest) => q.kind === 'main' && q.goalId === gid;
      const mains = this.queue.filter(isMain).sort((a, b) => a.planIndex - b.planIndex);
      const rest = this.queue.filter((q) => !isMain(q));
      this.queue.splice(0, this.queue.length, ...mains, ...rest);
      this.notify();
    }
    return out;
  }

  /** 单独把清单第 i 张派出来；已经在手就返回那一张（正被补救单顶着 → 返回补救单） */
  publishPlanTask(i: number): Quest | null {
    const t = goalTaskAt(this.goal, i);
    if (!t || !planTaskOpen(t)) return null;
    const gid = goalId(this.goal);
    for (const q of this.queue) {
      if (q.kind === 'main' && q.goalId === gid && q.planIndex === i) return q;
      if (this.isPlanRemedy(q) && q.planIndex === i) return q;
    }
    const q = this.planTask(i);
    this.queue.push(q);
    this.notify();
    return q;
  }

  /** 主线单只能接清单里第一张没完成的（E1.3）；补救 / 日常不锁 */
  isMainLocked(q: Quest): boolean {
    if (q.kind !== 'main' || q.goalId !== goalId(this.goal)) return false;
    const first = goalFirstOpenIndex(this.goal);
    return first >= 0 && q.planIndex !== first;
  }

  /** 当前目标的计划补回手上 + 当天日常；空目标什么都不种 */
  seedForCurrentGoal(): void {
    if (this.goal.plan.length === 0) return;
    this.publishPlanTasks();
    this.queue.push(...this.genTodaysDailies());
    this.notify();
  }

  /** 拆解失败「先跳过」：记住目标 + 先发当天日常（重复跳过不叠发） */
  skipPlan(text: string, dailies?: Quest[]): Quest[] {
    const t = text.trim();
    if (t) this.save.pendingGoal = t;
    const out: Quest[] = [];
    if (!this.queue.some((q) => q.kind === 'daily')) {
      const d = dailies && dailies.length ? dailies : this.genDailies(1);
      this.queue.push(...d);
      out.push(...d);
    }
    this.notify();
    return out;
  }

  /** 换目标 / 首次立目标落库：旧主线单撤下、新主线进在手窗口、日常保留 */
  newGoal(next: Goal): Quest {
    if (next.plan.length === 0)
      throw new Error(`newGoal：目标「${next.text}」没有任务清单，不能落库`);
    this.removeMainQuests();
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
    this.removeMainQuests();
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

  private removeMainQuests(): void {
    const keep = this.queue.filter((q) => q.kind !== 'main');
    this.queue.splice(0, this.queue.length, ...keep);
  }

  // ── 接单 / 道具 / 证据 ────────────────────────────────────

  /** 接单：出队 + 记 startAt */
  accept(t: Quest, now: number): void {
    const keep = this.queue.filter((q) => q.serial !== t.serial);
    this.queue.splice(0, this.queue.length, ...keep);
    this.active = {
      task: t,
      startAt: now,
      dbl: false,
      crit: false,
      shield: false,
      extraMs: 0,
      evidence: [],
      sealed: false,
    };
    this.notify();
  }

  /** 这一单能不能装这件道具（不能就给原因） */
  itemBlock(id: ItemId): string | null {
    const a = this.active;
    if (!a) return '没有执行中的单。';
    if (id !== 'dbl' && id !== 'crit' && id !== 'shield') return '这件道具不在执行中用。';
    if (a[id]) return '已经装上了。';
    if (id === 'shield' && !a.task.timed) return '打卡单用不上。';
    if (id === 'shield' && a.extraMs > 0) return '这一单的护盾已经碎过了。';
    if ((this.host.items[id] ?? 0) <= 0) return '手里没有。';
    return null;
  }

  /** 装载执行类道具：扣库存 + 挂到本单 */
  useItem(id: ItemId): boolean {
    if (this.itemBlock(id) !== null) return false;
    const a = this.active as ActiveQuest;
    this.host.items[id] = (this.host.items[id] ?? 0) - 1;
    if (id === 'dbl') a.dbl = true;
    else if (id === 'crit') a.crit = true;
    else a.shield = true;
    this.notify();
    return true;
  }

  private count(st: EvidenceStatus): number {
    return this.active?.evidence.filter((e) => e.status === st).length ?? 0;
  }

  /** 暴击率（含证据加成）；没有执行中的单 = 0 */
  critChance(): number {
    const a = this.active;
    if (!a) return 0;
    return critChance({
      verified: this.count('verified'),
      unverified: this.count('unverified'),
      unsure: this.count('unsure'),
      streak: this.host.streak,
      critItem: a.crit,
    });
  }

  /** 暴击率底值（不含证据加成；执行页自己加证据那部分，免得双计） */
  critBase(): number {
    const a = this.active;
    if (!a) return 0;
    return critChance({ streak: this.host.streak, critItem: a.crit });
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

  // ── 换一个 / 补给 / 佩戴 / 补签 ──────────────────────────

  /** 同一张单换个档重刻：六维按新档点数重分 */
  private reRank(q: Quest, rank: Rank, reason?: string): Quest {
    return {
      ...q,
      rank,
      reason: reason ?? q.reason,
      attrs: splitAttrs(q.attrs, RANK_ATTR_POINTS[rank]),
    };
  }

  /**
   * 「换一个」：当日计数（跨天归零）与累计各 +1；累计 ≥3 且没戴过 → 强制佩戴「口头巨人」；
   * 非 F 级同一张单降一档重刻；F 级还退 → 换另一张 F 日常顶位。不在手里 → null。
   */
  retreat(t: Quest, now: number): RetreatOutcome | null {
    const idx = this.queue.findIndex((q) => q.serial === t.serial);
    if (idx < 0) return null;
    const today = dayKey(now, this.tz);
    const m = this.meta;
    if (m.retreatDay !== today) {
      m.retreatDay = today;
      m.retreatToday = 0;
    }
    m.retreatToday++;
    m.retreatTotal++;
    let shame = false;
    if (m.retreatTotal >= 3 && !this.host.ownedTitles.includes('mouth')) {
      m.titleBeforeShame = this.host.title;
      this.host.ownedTitles = [...new Set([...this.host.ownedTitles, 'mouth'])];
      this.host.title = 'mouth';
      shame = true;
    }
    let replacement: Quest | null = null;
    if (t.rank === 'F') {
      const gen = this.genDailies(1)[0];
      if (gen) replacement = this.reRank(gen, 'F', this.reasonFor(gen));
    } else {
      replacement = this.reRank(t, rankShift(t.rank, -1));
    }
    if (replacement) this.queue[idx] = replacement;
    this.notify();
    return { task: t, replacement, count: m.retreatToday, total: m.retreatTotal, shame };
  }

  /** 买不了的原因（等级不够 / 晶核不够），能买 = null */
  buyBlock(id: string): string | null {
    const it = itemById(id);
    if (!it) return '没有这件道具。';
    if (it.lv > 0 && this.host.lv < it.lv) return `LV${it.lv} 解锁。`;
    if (this.host.coins < it.price) return '晶核不够。';
    return null;
  }

  buy(id: string): boolean {
    if (this.buyBlock(id) !== null) return false;
    const it = itemById(id);
    if (!it) return false;
    this.host.coins -= it.price;
    this.host.items[id] = (this.host.items[id] ?? 0) + 1;
    this.notify();
    return true;
  }

  /**
   * 补签券能不能用（docs/01 Q4）：只补「只断了一天、且就是昨天」的那一天。
   * 断签记录由换日时的 checkStreak 写入。
   */
  patchStatus(now: number): PatchStatus {
    if ((this.host.items['patch'] ?? 0) <= 0) return { ok: false, reason: '手里没有补签券。' };
    const m = this.meta;
    if (m.brokenStreak <= 0) return { ok: false, reason: '没断签，用不上。' };
    if (m.missedDay === null) return { ok: false, reason: '断了不止一天，补不回来。' };
    const today = dayKey(now, this.tz);
    if (m.missedDay !== addDays(today, -1)) return { ok: false, reason: '过了补签的那一天。' };
    const doneToday = m.lastDoneDay === today;
    return { ok: true, restoreTo: m.brokenStreak + 1 + (doneToday ? 1 : 0) };
  }

  /** 用补签券：连胜恢复为断前 +1（今天已完成再 +1），最近完成日接上 */
  usePatch(now: number): boolean {
    const st = this.patchStatus(now);
    if (!st.ok) return false;
    const m = this.meta;
    const today = dayKey(now, this.tz);
    this.host.items['patch'] = (this.host.items['patch'] ?? 0) - 1;
    this.host.streak = st.restoreTo;
    this.host.bestStreak = Math.max(this.host.bestStreak, st.restoreTo);
    if (m.lastDoneDay !== today) m.lastDoneDay = m.missedDay;
    m.brokenStreak = 0;
    m.missedDay = null;
    this.notify();
    return true;
  }

  /** 佩戴称号：未解锁 / 「口头巨人」生效中 → false */
  equip(id: string): boolean {
    if (!this.host.ownedTitles.includes(id)) return false;
    if (this.host.title === 'mouth') return false;
    this.host.title = id;
    this.notify();
    return true;
  }

  /** 领补救单：现在做 = 插回队首，先放委托板 = 排队尾 */
  takeRemedy(now: boolean): Quest | null {
    const r = this.meta.remedyOffer;
    if (!r) return null;
    this.meta.remedyOffer = null;
    this.meta.remedyDeadline = null;
    const keep = this.queue.filter((q) => q.serial !== r.serial);
    this.queue.splice(0, this.queue.length, ...keep);
    if (now) this.queue.unshift(r);
    else this.queue.push(r);
    this.notify();
    return r;
  }

  // ── 换日与连胜 ────────────────────────────────────────────

  /**
   * 断签检查（docs/01 Q4）：最近完成日在前天或更早、连胜还挂着 → 当场归零，
   * 记下断前的值；只断了昨天一天时记 missedDay = 昨天（补签券只补这一天）。
   */
  checkStreak(now: number): boolean {
    const today = dayKey(now, this.tz);
    const m = this.meta;
    const last = m.lastDoneDay;
    if (last === null || this.host.streak <= 0) return false;
    const gap = daysBetween(last, today);
    if (gap < 2) return false;
    m.brokenStreak = this.host.streak;
    m.missedDay = gap === 2 ? addDays(today, -1) : null;
    this.host.streak = 0;
    this.notify();
    return true;
  }

  /**
   * 换日：同一天反复进出不重发。清掉过期的断签记录 → 断签检查 →
   * 队列手术（隔夜日常与主线作废、补救单只留未过期的、补发当日日常）→ 主线重钉。
   */
  rollDay(now: number): boolean {
    const today = dayKey(now, this.tz);
    const m = this.meta;
    if (m.lastRollDay === today) return false;
    m.lastRollDay = today;
    // 补签只在断签被发现的那一天可用：新的一天先把旧记录清掉
    m.brokenStreak = 0;
    m.missedDay = null;
    this.checkStreak(now);
    if (this.goal.plan.length === 0 && !this.canRetryPlan) {
      this.notify();
      return true;
    }
    const next = rollDayQueue({
      overnight: this.queue,
      fresh: this.genTodaysDailies(),
      remedyDeadline: m.remedyDeadline,
      now,
    });
    this.queue.splice(0, this.queue.length, ...next);
    this.publishPlanTasks();
    this.notify();
    return true;
  }
}
