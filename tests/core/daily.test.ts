import { describe, expect, test } from 'vitest';
import { categoryOf } from '../../src/core/goal/categories';
import {
  DAILY_CAP,
  dailyCountFor,
  dailyPoolFor,
  dailyQuestFrom,
  dailyRankFor,
  genDailyCandidates,
  pickDailies,
  rollDayQueue,
} from '../../src/core/goal/daily';
import { DAILY_COMMON } from '../../src/core/data/dailyCommon';
import { quest, T0 } from '../fixtures';
import { seeded } from './helpers';

describe('每日单数与候选池', () => {
  test('dailyCountFor：lv≥5 或连胜≥3 为 2，否则 1', () => {
    expect(dailyCountFor(1, 0)).toBe(1);
    expect(dailyCountFor(5, 0)).toBe(2);
    expect(dailyCountFor(1, 3)).toBe(2);
  });

  test('日常池：类目专属在前、通用池补位', () => {
    const pool = dailyPoolFor('run');
    expect(pool.slice(0, 8)).toEqual(categoryOf('run').daily);
    expect(pool.slice(8)).toEqual(DAILY_COMMON);
  });

  test('候选 4~6 个、互不重复（多 seed 扫描）', () => {
    for (let s = 1; s < 40; s++) {
      const c = genDailyCandidates('gen', seeded(s));
      expect(c.length).toBeGreaterThanOrEqual(4);
      expect(c.length).toBeLessThanOrEqual(6);
      expect(new Set(c.map((d) => d.title)).size).toBe(c.length);
    }
  });

  test('挑单：第一单专治最弱维，第二单贴主线', () => {
    for (let s = 1; s < 30; s++) {
      const picks = pickDailies({
        candidates: dailyPoolFor('run'),
        attrs: { 力: 5, 体: 5, 智: 5, 知: 5, 魅: 0, 敏: 5 },
        goalCatId: 'run',
        n: 2,
        rnd: seeded(s),
      });
      expect(picks[0]?.attrs['魅']).toBeGreaterThan(0);
      expect(Object.keys(picks[1]!.attrs).some((k) => ['力', '敏', '体'].includes(k))).toBe(true);
    }
  });

  test('候选里没有短板单时随缘兜底，不空手回', () => {
    const picks = pickDailies({
      candidates: [categoryOf('run').daily[0]!],
      attrs: { 魅: 0, 力: 9 },
      goalCatId: 'run',
      n: 1,
      rnd: seeded(),
    });
    expect(picks).toHaveLength(1);
  });
});

describe('日常档位与落单', () => {
  test('lv<4 不提档：F 钉回 E（新生成不出 F）、C 封到 D', () => {
    expect(dailyRankFor('F', 1, seeded())).toBe('E');
    expect(dailyRankFor('C', 1, seeded())).toBe('D');
  });

  test('lv≥8 封顶 C；lv≥4 提档不出 [E..cap]（多 seed）', () => {
    for (let s = 1; s < 60; s++) {
      expect(['E', 'D']).toContain(dailyRankFor('D', 5, seeded(s)));
      expect(['E', 'D', 'C']).toContain(dailyRankFor('C', 9, seeded(s)));
    }
  });

  test('模板 → 单：字段随模板，六维按档位点数重分，打卡标记带上', () => {
    const t = DAILY_COMMON.find((d) => d.timed === false)!;
    const q = dailyQuestFrom(t, { serial: 77, level: 1, rnd: seeded(), rank: 'D' });
    expect(q).toMatchObject({
      serial: 77,
      kind: 'daily',
      name: t.title,
      proof: t.proof,
      rank: 'D',
      timed: false,
    });
    expect(Object.values(q.attrs).reduce((s, v) => s + (v ?? 0), 0)).toBe(2);
  });
});

describe('换日队列手术', () => {
  test('隔夜日常与主线作废；补救单只留未过期的；日上限 6', () => {
    const out = rollDayQueue({
      overnight: [quest(1), quest(2, { kind: 'main' }), quest(3, { kind: 'remedy' })],
      fresh: Array.from({ length: 9 }, (_, i) => quest(10 + i)),
      remedyDeadline: T0 + 1,
      now: T0,
    });
    expect(out.map((q) => q.serial)).toEqual([3, 10, 11, 12, 13, 14, 15]);
    expect(out.filter((q) => q.kind === 'daily')).toHaveLength(DAILY_CAP);
    const expired = rollDayQueue({
      overnight: [quest(3, { kind: 'remedy' })],
      fresh: [],
      remedyDeadline: T0 - 1,
      now: T0,
    });
    expect(expired).toEqual([]);
  });
});
