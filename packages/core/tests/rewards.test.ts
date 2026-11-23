import { describe, expect, test } from 'vitest';
import { RANKS } from '../src/data/rank';
import { EXP_BY_RANK, expFor, needFor } from '../src/data/rewards';
import { lootText } from '../src/flow/questText';
import { settle } from '../src/flow/settle';
import { QuestFlow } from '../src/flow/questFlow';
import { freshSave } from '../src/save/saveData';
import { quest, T0 } from './fixtures';

describe('奖励表逐档（数值一个都不许改）', () => {
  test('经验：F0 / E1 / D2 / C4 / B6 / A8 / S10', () => {
    expect(RANKS.map((r) => EXP_BY_RANK[r])).toEqual([0, 1, 2, 4, 6, 8, 10]);
    expect(RANKS.map(expFor)).toEqual([0, 1, 2, 4, 6, 8, 10]);
  });
  test('升级曲线 need(lv) = 12 + lv×6（lv1=18 … lv5=42 … lv10=72）', () => {
    expect([1, 2, 5, 10].map(needFor)).toEqual([18, 24, 42, 72]);
  });
});

describe('显示 = 结算（全档位交叉断言）', () => {
  for (const rank of RANKS) {
    test(`${rank} 级：卡面读数与入账一致`, () => {
      const q = quest(41, { rank, goalId: 'other' });
      const s = freshSave(T0);
      s.host.lv = 30; // 等级够高，不触发升级，余额读数直观
      const f = new QuestFlow(s);
      f.queue.push(q);
      f.accept(q, T0);
      const r = settle(f, { now: T0 + 60_000 });
      expect(lootText(q)).toBe(`EXP +${r.exp}`);
      expect(f.host.totalExp).toBe(r.exp);
    });
  }
});
