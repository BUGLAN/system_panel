import { describe, expect, test } from 'vitest';
import { CATEGORIES } from '../src/data/categories';
import { DAILY_COMMON } from '../src/data/dailyCommon';
import { RANKS, rankIndex, type Rank } from '../src/data/rank';
import {
  applyBindGift,
  categoryOf,
  interviewCardsFor,
  isVagueGoal,
  memoriesFromInterview,
} from '../src/goal/categories';
import {
  buildGoalFromPlan,
  extendGoalWithWindow,
  nextPlanWindow,
  planProgressDigest,
  planSegmentsFor,
  planTaskCountFor,
  planWindowFor,
  rankCapMinutes,
  segmentTo,
  validatePlan,
  validatePlanSegment,
  validatePlanWindow,
  windowIsLast,
  windowTo,
} from '../src/goal/plan';
import { PlanRuleError } from '../src/goal/planFailure';
import { splitAttrs } from '../src/goal/split';
import { T0 } from './fixtures';
import { specs } from './helpers';

const ladder = (n: number, lo: Rank, hi: Rank): Rank[] => {
  const l = rankIndex(lo);
  const h = rankIndex(hi);
  return Array.from(
    { length: n },
    (_, i) => RANKS[l + Math.floor(((h - l) * i) / Math.max(1, n - 1))] as Rank,
  );
};

describe('类目表（11 类）', () => {
  test('id 齐全且顺序固定，gen 兜底排最后', () => {
    expect(CATEGORIES.map((c) => c.id)).toEqual([
      'run',
      'slim',
      'fit',
      'lang',
      'exam',
      'sleep',
      'skill',
      'make',
      'code',
      'bold',
      'gen',
    ]);
    expect(CATEGORIES.map((c) => c.label)).toEqual([
      '奔跑',
      '轻盈',
      '力量',
      '开口',
      '上岸',
      '早起',
      '练技能',
      '作品',
      '上线',
      '自信',
      '变强',
    ]);
  });

  test('每类 3 张访谈卡（每卡 3~4 个选项、id 全局唯一），专属日常池 ≥8 条', () => {
    const ids = new Set<string>();
    for (const c of CATEGORIES) {
      expect(c.cards).toHaveLength(3);
      for (const card of c.cards) {
        expect(card.options.length).toBeGreaterThanOrEqual(3);
        expect(card.options.length).toBeLessThanOrEqual(4);
        expect(ids.has(card.id)).toBe(false);
        ids.add(card.id);
      }
      expect(c.daily.length).toBeGreaterThanOrEqual(8);
    }
  });

  test('运动类（跑步 / 减重 / 力量）首属性是「力」= 体质；早起类留「体」= 意志（C1）', () => {
    const top = (id: string) =>
      Object.entries(categoryOf(id).tilt).sort((a, b) => (b[1] ?? 0) - (a[1] ?? 0))[0]?.[0];
    expect(['run', 'slim', 'fit'].map(top)).toEqual(['力', '力', '力']);
    expect(top('sleep')).toBe('体');
  });

  test('C2 练技能：访谈问的是「练」', () => {
    expect(categoryOf('skill').cards.map((c) => c.question)).toEqual([
      '现在什么水平？',
      '一周能练几次？',
      '想先练会什么？',
    ]);
  });

  test('通用池 30 条；整天型 6 条是打卡单（D3.3）', () => {
    expect(DAILY_COMMON).toHaveLength(30);
    const checkin = [...DAILY_COMMON, ...CATEGORIES.flatMap((c) => c.daily)]
      .filter((d) => d.timed === false)
      .map((d) => d.title);
    expect(checkin).toHaveLength(6);
    expect(checkin).toEqual(
      expect.arrayContaining([
        '喝水 6 杯，拿杯子凑数不算',
        '早睡 30 分钟，就今晚',
        '睡前不吃东西，渴了只喝水',
      ]),
    );
  });

  test('池内容合规：题面非空、时限 5~180、档位在 F~S', () => {
    for (const d of [...DAILY_COMMON, ...CATEGORIES.flatMap((c) => c.daily)]) {
      expect(d.title.trim()).not.toBe('');
      expect(d.minutes).toBeGreaterThanOrEqual(5);
      expect(d.minutes).toBeLessThanOrEqual(180);
      expect(RANKS).toContain(d.rank);
    }
  });

  test('未知类目兜底到 gen', () => {
    expect(categoryOf('???').id).toBe('gen');
  });
});

describe('空泛判定与访谈卡组', () => {
  test('黑名单整句命中；剥标点后不足 2 字也算；具体目标不拦', () => {
    for (const s of ['变优秀', '自律！', '加油~', '好', ' 。'])
      expect(isVagueGoal(s), s).toBe(true);
    for (const s of ['两周内骑自行车 10 次', '三个月学会弹吉他', '半年减重 10 斤']) {
      expect(isVagueGoal(s), s).toBe(false);
    }
  });

  test('lv1 = 类别 3 张；lv2~3 追加投入时段；lv4+ 再追加复盘卡', () => {
    const run = categoryOf('run');
    expect(interviewCardsFor(run, 1)).toHaveLength(3);
    expect(
      interviewCardsFor(run, 2)
        .map((c) => c.id)
        .slice(-1),
    ).toEqual(['common.slot']);
    expect(
      interviewCardsFor(run, 4)
        .map((c) => c.id)
        .slice(-2),
    ).toEqual(['common.slot', 'common.history']);
  });

  test('记忆导出：目标一句 + 逐卡问答，跳过未答的卡', () => {
    const mem = memoriesFromInterview({
      cat: categoryOf('run'),
      answers: { 'run.now': '3 公里以内', 'run.slot': '' },
      goalText: ' 三个月跑完半马 ',
      days: 90,
    });
    expect(mem).toEqual([
      '宿主立了新目标：「三个月跑完半马」（奔跑向，期限 90 天）。',
      '现在能跑多远？——3 公里以内。',
    ]);
  });

  test('见面礼：双倍卡 +1，原表不动', () => {
    const items = { dbl: 2 };
    expect(applyBindGift(items)).toEqual({ dbl: 3 });
    expect(items).toEqual({ dbl: 2 });
    expect(applyBindGift({})).toEqual({ dbl: 1 });
  });
});

describe('条数与窗口（C1 滚动生成）', () => {
  test('planTaskCountFor：次数配额压过期限天数，夹在 2~400', () => {
    expect(planTaskCountFor(14, 10)).toBe(10);
    expect(planTaskCountFor(90)).toBe(90);
    expect(planTaskCountFor(1)).toBe(2);
    expect(planTaskCountFor(9999)).toBe(400);
  });

  test('180 天只拆 14 张；总数更少就按总数', () => {
    expect(planWindowFor({ total: 180 })).toMatchObject({ from: 1, size: 14, lo: 'E' });
    expect(planWindowFor({ total: 10 })).toMatchObject({ from: 1, size: 10, lo: 'F', hi: 'S' });
  });

  test('一段段往下拆：序号连续、张数守恒、档位全链不倒退、只有最后一段收 S', () => {
    let planned = 0;
    let prevHi = -1;
    const lasts: boolean[] = [];
    while (planned < 180) {
      const w = planWindowFor({ total: 180, planned });
      expect(w.from).toBe(planned + 1);
      expect(rankIndex(w.lo)).toBeGreaterThanOrEqual(
        prevHi === -1 ? 0 : Math.min(prevHi, rankIndex(w.lo)),
      );
      prevHi = rankIndex(w.hi);
      lasts.push(windowIsLast(w));
      planned = windowTo(w);
    }
    expect(planned).toBe(180);
    expect(lasts.filter(Boolean)).toHaveLength(1);
    expect(lasts[lasts.length - 1]).toBe(true);
  });

  test('首目标第一段：E~C，不摆兑现单', () => {
    const w = planWindowFor({ total: 10, firstGoal: true });
    expect(w).toMatchObject({ lo: 'E', hi: 'C', size: 10 });
    expect(windowIsLast(w)).toBe(false);
  });

  test('窗口 ≤12 张一段；默认 14 张切成 2×7 并行、首尾相接', () => {
    expect(planSegmentsFor(planWindowFor({ total: 10 }))).toHaveLength(1);
    const segs = planSegmentsFor(planWindowFor({ total: 180 }));
    expect(segs.map((s) => s.size)).toEqual([7, 7]);
    expect(segs[0]?.hi).toBe(segs[1]?.lo);
    expect(segmentTo(segs[1]!)).toBe(14);
  });

  test('老口径整份 90 张：张数守恒、每段 ≤12、只有末段 last', () => {
    const segs = planSegmentsFor(planWindowFor({ total: 90, size: 90 }));
    expect(segs.reduce((s, x) => s + x.size, 0)).toBe(90);
    expect(segs.every((s) => s.size <= 12)).toBe(true);
    expect(segs.filter((s) => s.last)).toHaveLength(1);
  });

  test('档位时限上限单调递增', () => {
    const caps = RANKS.map(rankCapMinutes);
    expect(caps).toEqual([20, 30, 40, 60, 90, 120, 180]);
  });
});

describe('校验 fail fast', () => {
  test('合规清单通过；条数不对抛（不补齐、不截断）', () => {
    expect(() => validatePlan({ days: 5, tasks: specs(['E', 'D', 'C', 'B', 'S']) })).not.toThrow();
    expect(() => validatePlan({ days: 5, tasks: specs(['E', 'D', 'S']) })).toThrow(PlanRuleError);
  });

  test('字段空 / 档位非法 / 时限越界 / 档位倒退 → 抛', () => {
    const w = planWindowFor({ total: 3 });
    expect(() => validatePlanWindow(w, specs(['E', 'D', 'S'], { short: ' ' }))).toThrow(
      'short 是空的',
    );
    expect(() => validatePlanWindow(w, specs(['E', 'Z' as Rank, 'S']))).toThrow(
      '不在 F/E/D/C/B/A/S 里',
    );
    expect(() => validatePlanWindow(w, specs(['E', 'D', 'S'], { minutes: 4 }))).toThrow('越界');
    expect(() =>
      validatePlanWindow(w, [...specs(['E']), ...specs(['E'], { minutes: 31 }), ...specs(['S'])]),
    ).toThrow('越界');
    expect(() => validatePlanWindow(w, specs(['D', 'E', 'S']))).toThrow('倒退');
  });

  test('首目标第一段只许 E/D/C；非首目标末张必须是 S', () => {
    expect(() =>
      validatePlan({ days: 3, tasks: specs(['E', 'D', 'C']), firstGoal: true }),
    ).not.toThrow();
    expect(() =>
      validatePlan({ days: 3, tasks: specs(['E', 'D', 'B']), firstGoal: true }),
    ).toThrow();
    expect(() => validatePlan({ days: 3, tasks: specs(['E', 'D', 'A']) })).toThrow('必须 S 级');
  });

  test('兑现单不限最低 120 分钟，只限 S 档上限', () => {
    expect(() =>
      validatePlan({ days: 2, tasks: specs(['E', 'S'], { minutes: 30 }) }),
    ).not.toThrow();
  });

  test('分段校验：档位越区间 / 末段末张不是 S 都抛', () => {
    const segs = planSegmentsFor(planWindowFor({ total: 14 }));
    const last = segs[segs.length - 1]!;
    const ok = ladder(last.size, last.lo, last.hi);
    expect(() => validatePlanSegment(last, specs(ok))).not.toThrow();
    expect(() => validatePlanSegment(last, specs([...ok.slice(0, -1), 'A']))).toThrow();
    expect(() => validatePlanSegment(segs[0]!, specs(ladder(segs[0]!.size, 'F', 'S')))).toThrow();
  });
});

describe('铸计划与续拆', () => {
  test('首目标 3 天：E/D/C，末张不算兑现门；六维按类目倾向分', () => {
    const g = buildGoalFromPlan({
      text: '三天早睡',
      short: '',
      cat: categoryOf('sleep'),
      days: 3,
      tasks: specs(['E', 'D', 'C']),
      at: T0,
      firstGoal: true,
    });
    expect(g.short).toBe('三天早睡');
    expect(g.plan.some((t) => t.finalTask)).toBe(false);
    expect(g.plan[1]?.attrs).toEqual(splitAttrs(categoryOf('sleep').tilt, 2));
  });

  test('滚动生成：180 天只铸第一段 14 张，总张数存 planTotal；续拆接上第 15 张起', () => {
    const w = planWindowFor({ total: 180 });
    const g = buildGoalFromPlan({
      text: '半年减重 10 斤',
      short: '减重',
      cat: categoryOf('slim'),
      days: 180,
      tasks: specs(ladder(14, w.lo, w.hi)),
      at: T0,
    });
    expect([g.plan.length, g.planTotal]).toEqual([14, 180]);
    const nw = nextPlanWindow(g);
    expect(nw.from).toBe(15);
    const g2 = extendGoalWithWindow(g, categoryOf('slim'), specs(ladder(nw.size, nw.lo, nw.lo)));
    expect(g2.plan.map((t) => t.index).slice(13, 16)).toEqual([13, 14, 15]);
    expect(g2.plan[g2.plan.length - 1]?.finalTask).toBe(false);
  });

  test('空目标文本 → 抛', () => {
    expect(() =>
      buildGoalFromPlan({
        text: ' ',
        short: '',
        cat: categoryOf('run'),
        days: 2,
        tasks: specs(['E', 'S']),
        at: T0,
      }),
    ).toThrow('目标文本是空的');
  });

  test('进度摘要：第几天、已拆 / 完成、上一段收在哪', () => {
    const g = buildGoalFromPlan({
      text: '跑步',
      short: '跑步',
      cat: categoryOf('run'),
      days: 30,
      tasks: specs(ladder(14, 'E', 'D')),
      at: T0,
    });
    g.plan[0] = { ...g.plan[0]!, state: 'done', heldMs: 21 * 60_000 };
    const d = planProgressDigest(g, T0 + 86_400_000);
    expect(d).toContain('现在是第 2/30 天；已拆 14/30 张，完成 1 张。');
    expect(d).toContain('- 第 1 张 [E]「跑 1 公里」，用时 21 分钟');
    expect(d).toContain('上一段最后一张是第 14 张');
  });
});

describe('六维分配 splitAttrs', () => {
  test('按权重分、首维至少 1、余数补首维', () => {
    expect(splitAttrs({ 力: 2, 敏: 1, 体: 1 }, 1)).toEqual({ 力: 1 });
    expect(splitAttrs({ 力: 2, 敏: 1, 体: 1 }, 2)).toEqual({ 力: 1, 敏: 1 });
    expect(splitAttrs({ 力: 2, 敏: 1, 体: 1 }, 6)).toEqual({ 力: 3, 敏: 2, 体: 1 });
    expect(splitAttrs({}, 3)).toEqual({});
  });
});
