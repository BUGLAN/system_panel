/**
 * 日常委托（产品内容，不是拆解兜底）：每日单数、候选池、挑单、档位、落单、换日队列手术。
 * 移植自 flutter-final:app/lib/state/goal_gen.dart（周期任务生成部分）。
 */
import type { AttrKey } from '../data/attrs';
import type { DailyTemplate } from '../data/categoryTypes';
import { DAILY_COMMON } from '../data/dailyCommon';
import { RANK_ATTR_POINTS, RANKS, rankIndex, type Rank } from '../data/rank';
import type { Quest } from '../model/quest';
import { categoryOf } from './categories';
import { splitAttrs } from './split';

/** 随机源（可注入，测试钉死） */
export type Rnd = () => number;

export const nextInt = (rnd: Rnd, n: number) => Math.floor(rnd() * n);

export function shuffle<T>(arr: readonly T[], rnd: Rnd): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = nextInt(rnd, i + 1);
    [a[i], a[j]] = [a[j] as T, a[i] as T];
  }
  return a;
}

/** 每日日常单数：lv≥5 或连胜≥3 → 2，否则 1 */
export function dailyCountFor(level: number, streak: number): number {
  return level >= 5 || streak >= 3 ? 2 : 1;
}

/** 日常单的日上限（主线 / 补救单不占） */
export const DAILY_CAP = 6;
export const DAILY_CANDIDATE_MIN = 4;
export const DAILY_CANDIDATE_MAX = 6;

/** 日常池：类目专属在前、通用池补位 */
export function dailyPoolFor(catId: string): DailyTemplate[] {
  return [...categoryOf(catId).daily, ...DAILY_COMMON];
}

/** 候选池：随机去重出 4~6 个 */
export function genDailyCandidates(catId: string, rnd: Rnd, n?: number): DailyTemplate[] {
  const pool = dailyPoolFor(catId);
  const want = Math.min(
    pool.length,
    Math.max(
      0,
      n ?? DAILY_CANDIDATE_MIN + nextInt(rnd, DAILY_CANDIDATE_MAX - DAILY_CANDIDATE_MIN + 1),
    ),
  );
  return shuffle(pool, rnd).slice(0, want);
}

/** 最弱的一维（并列取先出现的） */
export function weakestAttr(attrs: Partial<Record<AttrKey, number>>): [AttrKey, number] {
  const entries = Object.entries(attrs) as Array<[AttrKey, number]>;
  if (!entries.length) return ['体', 0];
  return entries.reduce((a, b) => (b[1] < a[1] ? b : a));
}

/** 从候选里挑 n 个：第一单专治最弱维，第二单贴主线（类目倾向命中），其余随缘 */
export function pickDailies(o: {
  candidates: DailyTemplate[];
  attrs: Partial<Record<AttrKey, number>>;
  goalCatId: string;
  n: number;
  rnd: Rnd;
}): DailyTemplate[] {
  const [weak] = weakestAttr(o.attrs);
  const tilt = Object.keys(categoryOf(o.goalCatId).tilt) as AttrKey[];
  const out: DailyTemplate[] = [];
  const used = new Set<string>();
  const take = (pred: (d: DailyTemplate) => boolean): boolean => {
    const cand = o.candidates.filter((d) => !used.has(d.title) && pred(d));
    if (!cand.length) return false;
    const d = cand[nextInt(o.rnd, cand.length)] as DailyTemplate;
    used.add(d.title);
    out.push(d);
    return true;
  };
  const plan: Array<(d: DailyTemplate) => boolean> = [
    (d) => (d.attrs[weak] ?? 0) > 0,
    (d) => tilt.some((k) => (d.attrs[k] ?? 0) > 0),
  ];
  for (let i = 0; i < o.n; i++) {
    const pred = plan[i] ?? (() => true);
    if (!(take(pred) || take(() => true))) break;
  }
  return out;
}

/** 日常档位：lv≥4 30% 提一档、lv≥8 再 20%；封顶 lv<8 到 D、lv≥8 到 C；新生成不出 F */
export function dailyRankFor(base: Rank, level: number, rnd: Rnd): Rank {
  let i = rankIndex(base);
  if (level >= 4 && rnd() < 0.3) i = Math.min(RANKS.length - 1, i + 1);
  if (level >= 8 && rnd() < 0.2) i = Math.min(RANKS.length - 1, i + 1);
  const cap = level >= 8 ? 3 : 2;
  return RANKS[Math.max(1, Math.min(i, cap))] as Rank;
}

/** 模板 → 一张日常单（六维按档位点数重分） */
export function dailyQuestFrom(
  t: DailyTemplate,
  o: { serial: number; level: number; rnd: Rnd; rank?: Rank },
): Quest {
  const rank = o.rank ?? dailyRankFor(t.rank, o.level, o.rnd);
  return {
    serial: o.serial,
    kind: 'daily',
    planIndex: -1,
    planTotal: 0,
    goalId: '',
    name: t.title,
    reason: '',
    proof: t.proof,
    minutes: t.minutes,
    rank,
    attrs: splitAttrs(t.attrs, RANK_ATTR_POINTS[rank]),
    hinted: false,
    timed: t.timed ?? true,
  };
}

/**
 * 换日的队列手术：隔夜日常与主线作废（主线随后由在手窗口重钉），
 * 补救单只留未过期的，补发当日日常（日上限 6）。
 */
export function rollDayQueue(o: {
  overnight: Quest[];
  fresh: Quest[];
  remedyDeadline: number | null;
  now: number;
}): Quest[] {
  const out = o.overnight.filter(
    (q) => q.kind === 'remedy' && (o.remedyDeadline === null || o.remedyDeadline >= o.now),
  );
  const usedDaily = out.filter((q) => q.kind === 'daily').length;
  const room = Math.max(0, DAILY_CAP - usedDaily);
  return [...out, ...o.fresh.slice(0, room)];
}
