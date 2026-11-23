import { describe, expect, test } from 'vitest';
import { LINES, defaultHold, fillLine, mainlineLine, pickBySeed } from '../src/data/lines';
import { awayKind, awayLine, awayText } from '../src/time/away';
import { fmtClock, fmtDur, fmtMin } from '../src/format';
import { summarizeWeek, historyFromRow } from '../src/flow/history';
import type { HistoryEntry } from '../src/flow/types';
import { T0 } from './fixtures';

const MIN = 60_000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;

describe('台词的高亮与填空', () => {
  test('页面字幕带 [[…]] 高亮', () => {
    for (const s of [LINES.holding, LINES.askGoal, mainlineLine(5, 10)]) {
      expect(s).toMatch(/\[\[.+?\]\]/);
    }
  });

  test('台词里不再提已拿掉的玩法（晶核 / 暴击 / 道具 / 补救）', () => {
    const all = JSON.stringify(LINES);
    for (const w of ['晶核', '暴击', '护盾', '双倍卡', '补救', '◈']) expect(all).not.toContain(w);
  });

  test('fillLine 换掉全部 {key}；pickBySeed 同种子稳定', () => {
    expect(fillLine(LINES.holding, { n: 3 })).toBe('我手里有 [[3]] 单。都是给你的。');
    const a = pickBySeed(LINES.poke, 'lv3|st2');
    expect(pickBySeed(LINES.poke, 'lv3|st2')).toBe(a);
  });

  test('默认停顿 = clamp(420 + 字数 × 42, 900, 2400)，高亮标记不计字数', () => {
    expect(defaultHold('嗯。')).toBe(900);
    expect(defaultHold('一二三四五六七八九十一二三四五')).toBe(420 + 15 * 42);
    expect(defaultHold('长'.repeat(100))).toBe(2400);
    expect(defaultHold('[[一二三四五六七八九十一二三四五]]')).toBe(420 + 15 * 42);
  });
});

describe('离开多久（away）', () => {
  test('不到 1 分钟不吭声；10 分钟 / 2 小时 / 20 小时 / 48 小时分档', () => {
    expect(awayLine(59_000)).toBeNull();
    expect(awayKind(5 * MIN)).toBe('back10m');
    expect(awayKind(30 * MIN)).toBe('back2h');
    expect(awayKind(5 * HOUR)).toBe('back12h');
    expect(awayKind(30 * HOUR)).toBe('back36h');
    expect(awayKind(49 * HOUR)).toBe('backLong');
  });

  test('填变量：back2h 用 fmtDur，backLong 天数四舍五入；不留花括号', () => {
    expect(awayText('back2h', 90 * MIN)).toBe('离开了 [[1 小时 30 分]]。去干正事了吧。');
    expect(awayText('backLong', 3.6 * DAY)).toContain('[[4]] 天');
    for (const ms of [5 * MIN, 30 * MIN, 5 * HOUR, 30 * HOUR, 80 * HOUR]) {
      expect(awayLine(ms)).not.toMatch(/[{}]/);
    }
  });
});

describe('格式', () => {
  test('fmtClock / fmtMin / fmtDur', () => {
    expect(fmtClock(65_000)).toBe('01:05');
    expect(fmtClock(3_725_000)).toBe('1:02:05');
    expect([fmtMin(25), fmtMin(60), fmtMin(90)]).toEqual(['25 分钟', '1 小时', '1 小时 30 分']);
    expect([
      fmtDur(30_000),
      fmtDur(150_000),
      fmtDur(120_000),
      fmtDur(3 * HOUR),
      fmtDur(50 * HOUR),
    ]).toEqual(['30 秒', '2 分 30 秒', '2 分', '3 小时', '2 天']);
  });
});

describe('7 天战报', () => {
  const e = (at: number, over: Partial<HistoryEntry> = {}): HistoryEntry => ({
    at,
    name: 'x',
    rank: 'E',
    exp: 1,
    streak: 1,
    result: 'clear',
    ...over,
  });

  test('7 日窗口 / 完成数 / 出账 / 连胜峰；旧版认输记录不算完成', () => {
    const all = [
      e(T0 - 9 * DAY),
      e(T0 - 6 * DAY, { streak: 4 }),
      e(T0 - DAY, { result: 'quit', exp: 0 }),
      e(T0, { exp: 4 }),
    ];
    const s = summarizeWeek(all, T0);
    expect(s.doneCount).toBe(2);
    expect([s.totalExp, s.bestStreak]).toEqual([5, 4]);
    expect(s.dayDone).toEqual([1, 0, 0, 0, 0, 0, 1]);
    expect(s.recent.map((x) => x.at)).toEqual([T0, T0 - DAY, T0 - 6 * DAY, T0 - 9 * DAY]);
  });

  test('空表全零；坏行读成默认', () => {
    const s = summarizeWeek([], T0);
    expect([s.doneCount, s.totalExp]).toEqual([0, 0]);
    expect(historyFromRow('x')).toBeNull();
    expect(historyFromRow({ rank: 'Z', result: 'weird' })).toMatchObject({
      rank: 'F',
      result: 'clear',
    });
  });
});
