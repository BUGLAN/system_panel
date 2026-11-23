import { describe, expect, test } from 'vitest';
import {
  LEVELUP_MAX_MS,
  SETTLE_MAX_MS,
  buildSettleTimeline,
  levelUpDurationMs,
} from '../../src/ui/fx/settleTimeline';

describe('结算时间轴（docs/00：结算 ≤1.6s、升级 ≤2s）', () => {
  const combos = [false, true].flatMap((levelUp) => [1, 2, 3].map((rows) => ({ levelUp, rows })));

  test.each(combos)('跨级=$levelUp 行数=$rows：总时长 ≤ 1.6s', (o) => {
    const t = buildSettleTimeline(o);
    expect(t.totalMs).toBeLessThanOrEqual(SETTLE_MAX_MS);
    expect(t.countMs).toBe(800);
  });

  test('经验条：不跨级 520ms；跨级 360 涨满 → 白闪 180 → 420 涨到余额', () => {
    expect(buildSettleTimeline({ rows: 2, levelUp: false }).bar).toEqual({
      kind: 'same',
      ms: 520,
    });
    expect(buildSettleTimeline({ rows: 2, levelUp: true }).bar).toEqual({
      kind: 'cross',
      fillMs: 360,
      flashMs: 180,
      refillMs: 420,
    });
  });

  test('升级叠层 ≤ 2s，同日简版更短', () => {
    expect(levelUpDurationMs(false)).toBeLessThanOrEqual(LEVELUP_MAX_MS);
    expect(levelUpDurationMs(true)).toBeLessThan(levelUpDurationMs(false));
  });
});
