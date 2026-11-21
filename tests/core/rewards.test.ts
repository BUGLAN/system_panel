import { describe, expect, test } from 'vitest';
import { RANKS, type Rank } from '../../src/core/data/rank';
import {
  COIN_BY_RANK,
  EXP_BY_RANK,
  critChance,
  evidenceCritBonus,
  needFor,
  payout,
} from '../../src/core/data/rewards';
import { lootText, lootTextOf } from '../../src/core/flow/questText';
import { settle } from '../../src/core/flow/settle';
import { QuestFlow } from '../../src/core/flow/questFlow';
import { freshSave } from '../../src/core/save/saveData';
import { quest, T0 } from '../fixtures';
import { fixed } from './helpers';

describe('奖励表逐档（数值一个都不许改）', () => {
  test('经验：F0 / E1 / D2 / C4 / B6 / A8 / S10', () => {
    expect(RANKS.map((r) => EXP_BY_RANK[r])).toEqual([0, 1, 2, 4, 6, 8, 10]);
  });
  test('晶核：F3 / E5 / D5 / C5 / B7 / A10 / S20', () => {
    expect(RANKS.map((r) => COIN_BY_RANK[r])).toEqual([3, 5, 5, 5, 7, 10, 20]);
  });
  test('升级曲线 need(lv) = 12 + lv×6（lv1=18 … lv5=42 … lv10=72）', () => {
    expect([1, 2, 5, 10].map(needFor)).toEqual([18, 24, 42, 72]);
  });
});

describe('结算乘区', () => {
  test('普通单 = 表值：E → EXP 1 / 晶核 5', () => {
    expect(payout({ rank: 'E', crit: false, dbl: false })).toEqual({ baseExp: 1, exp: 1, coin: 5 });
  });
  test('暴击 ×2：经验与晶核都翻倍', () => {
    expect(payout({ rank: 'C', crit: true, dbl: false })).toEqual({ baseExp: 4, exp: 8, coin: 10 });
  });
  test('双倍卡 ×2 只吃经验；与暴击可叠 ×4', () => {
    expect(payout({ rank: 'C', crit: false, dbl: true })).toEqual({ baseExp: 4, exp: 8, coin: 5 });
    expect(payout({ rank: 'C', crit: true, dbl: true })).toEqual({ baseExp: 4, exp: 16, coin: 10 });
  });
  test('补救单 ×0.5（D：EXP 2→1、晶核 5→2.5→3），暴击在其上再翻', () => {
    expect(payout({ rank: 'D', crit: false, dbl: false, remedy: true })).toEqual({
      baseExp: 1,
      exp: 1,
      coin: 3,
    });
    expect(payout({ rank: 'D', crit: true, dbl: false, remedy: true })).toEqual({
      baseExp: 1,
      exp: 2,
      coin: 6,
    });
  });
  test('补救单 EXP 保底 1（F 级减半后原本是 0，E2.4）', () => {
    expect(payout({ rank: 'F', crit: false, dbl: false, remedy: true })).toEqual({
      baseExp: 1,
      exp: 1,
      coin: 2,
    });
    expect(payout({ rank: 'E', crit: false, dbl: false, remedy: true }).exp).toBe(1);
  });
  test('F 档非补救：经验 0，晶核照给 3', () => {
    expect(payout({ rank: 'F', crit: false, dbl: false })).toEqual({ baseExp: 0, exp: 0, coin: 3 });
  });
});

describe('显示 = 结算（全档位 × 暴击 × 双倍 × 补救 交叉断言）', () => {
  const combos: Array<[Rank, boolean, boolean, boolean]> = [];
  for (const r of RANKS) {
    for (const crit of [false, true]) {
      for (const dbl of [false, true]) {
        for (const remedy of [false, true]) combos.push([r, crit, dbl, remedy]);
      }
    }
  }

  test.each(combos)('%s 暴击=%s 双倍=%s 补救=%s', (rank, crit, dbl, remedy) => {
    const s = freshSave(T0);
    const f = new QuestFlow(s, { rnd: fixed(0.5) });
    const q = quest(60, { rank, kind: remedy ? 'remedy' : 'daily', attrs: {} });
    f.queue.push(q);
    f.accept(q, T0);
    if (dbl) {
      f.host.items['dbl'] = 1;
      f.useItem('dbl');
    }
    const res = settle(f, { now: T0 + 30 * 60_000, forceCrit: crit });
    const shown = lootTextOf({ rank, remedy, crit, dbl });
    expect(shown).toBe(`EXP +${res.exp} · 晶核 +${res.coin}`);
    expect(f.host.coins).toBe(res.coin);
    expect(f.host.totalExp).toBe(res.exp);
  });

  test('队列里的裸单读数：C 级 EXP +4 · 晶核 +5；D 级补救 EXP +1 · 晶核 +3', () => {
    expect(lootText(quest(1, { rank: 'C' }))).toBe('EXP +4 · 晶核 +5');
    expect(lootText(quest(1, { rank: 'D', kind: 'remedy' }))).toBe('EXP +1 · 晶核 +3');
  });
});

describe('暴击率', () => {
  test('底 6% + 连胜 1%/天（≤10）+ 芯片 25%，封顶 85%', () => {
    expect(critChance({})).toBeCloseTo(0.06);
    expect(critChance({ streak: 6 })).toBeCloseTo(0.12);
    expect(critChance({ streak: 30 })).toBeCloseTo(0.16);
    expect(critChance({ critItem: true })).toBeCloseTo(0.31);
    expect(critChance({ verified: 3, streak: 10, critItem: true })).toBeCloseTo(0.62);
    expect(critChance({ verified: 30, critItem: true, streak: 99 })).toBe(0.85);
  });
  test('证据：已校验 7%/张，拿不准与未校验各 4%/张', () => {
    expect(evidenceCritBonus({ verified: 1, unverified: 1 })).toBeCloseTo(0.11);
    expect(evidenceCritBonus({ verified: 0, unverified: 1, unsure: 1 })).toBeCloseTo(0.08);
    expect(critChance({ verified: 1, unverified: 1 })).toBeCloseTo(0.17);
  });
});
