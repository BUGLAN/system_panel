import { describe, expect, test } from 'vitest';
import {
  FIRST_SERIAL,
  SAVE_VERSION,
  freshSave,
  parseSave,
  saveFromJson,
  saveToJson,
  stringifySave,
} from '../src/save/saveData';
import { goalId } from '../src/model/goal';
import { addDays, dayKey, daysBetween, isDayKey } from '../src/time/day';
import { T0, goal, quest, sampleSave } from './fixtures';

const roundtrip = (s = sampleSave()) => parseSave(stringifySave(s, T0 + 99), T0);

describe('存取往返', () => {
  test('存进去再读出来，逐字段一致（lastSeen 盖成存盘时刻）', () => {
    const s = sampleSave();
    const back = roundtrip(s);
    expect(back).toEqual({ ...s, lastSeen: T0 + 99 });
  });

  test('计划单的状态、用时、评级、打卡标记都能回来', () => {
    const back = roundtrip();
    const [t0, t1] = back!.goal.plan;
    expect(t0).toMatchObject({ state: 'done', heldMs: 754_000, doneAt: T0 + 1000, grade: 'A' });
    expect(t1).toMatchObject({ state: 'todo', timed: false, rank: 'D', grade: null });
  });

  test('执行中单据：道具标记、护盾顺延、证据状态都在；sealed 不进档', () => {
    const s = sampleSave();
    s.active!.sealed = true;
    const back = roundtrip(s)!;
    expect(back.active).toMatchObject({ dbl: true, shield: true, extraMs: 600_000, sealed: false });
    expect(back.active!.evidence.map((e) => e.status)).toEqual(['verified', 'unsure']);
    expect(back.active!.task.timed).toBe(false);
  });

  test('运行时字段入档（旧版漏存导致重启后连胜被算成 1）', () => {
    const back = roundtrip()!;
    expect(back.meta).toMatchObject({
      lastDoneDay: '2026-11-20',
      retreatTotal: 2,
      lastRollDay: '2026-11-21',
    });
  });

  test('打卡单只写 mode: checkin，计时单不写', () => {
    const j = saveToJson(sampleSave());
    const active = j['active'] as { task: Record<string, unknown> };
    expect(active.task['mode']).toBe('checkin');
    const q0 = (j['queue'] as Record<string, unknown>[])[0]!;
    expect('mode' in q0).toBe(false);
  });

  test('全新档 = 未绑定：没有目标、没有队列、单号从 41 起', () => {
    const f = freshSave(T0);
    expect(f.goal.plan).toEqual([]);
    expect(f.queue).toEqual([]);
    expect(f.active).toBeNull();
    expect(f.meta.nextSerial).toBe(FIRST_SERIAL);
    expect(f.v).toBe(SAVE_VERSION);
    expect(roundtrip(f)).toEqual({ ...f, lastSeen: T0 + 99 });
  });
});

describe('在默认值上合并', () => {
  test('缺字段走默认，不崩', () => {
    const s = saveFromJson({ host: { lv: 4 } }, T0)!;
    expect(s.host.lv).toBe(4);
    expect(s.host.coins).toBe(0);
    expect(s.host.items).toEqual({ dbl: 0, crit: 0, shield: 0, patch: 0 });
    expect(s.goal.plan).toEqual([]);
    expect(s.meta.nextSerial).toBe(FIRST_SERIAL);
  });

  test('类型不对的字段也走默认（不抛）', () => {
    const s = saveFromJson(
      {
        host: { lv: 'x', coins: -5, attrs: { 力: 'a', 魅: 3, 乱: 9 }, ownedTitles: [1, 'first'] },
        queue: [42, { serial: 'x', kind: 'weird', rank: 'Z' }],
        active: { task: 'nope' },
        meta: { lastDoneDay: '昨天', retreatTotal: 'many' },
      },
      T0,
    )!;
    expect(s.host.lv).toBe(1);
    expect(s.host.coins).toBe(0);
    expect(s.host.attrs).toEqual({ 力: 0, 体: 0, 智: 0, 知: 0, 魅: 3, 敏: 0 });
    expect(s.host.ownedTitles).toEqual(['first']);
    expect(s.queue).toHaveLength(1);
    expect(s.queue[0]).toMatchObject({ kind: 'daily', rank: 'F', minutes: 15, timed: true });
    expect(s.active).toBeNull();
    expect(s.meta.lastDoneDay).toBeNull();
    expect(s.meta.retreatTotal).toBe(0);
  });

  test('整个串读坏 / 是数组不是对象 / 空串 → null（交给仓库层走坏档流程）', () => {
    expect(parseSave('{bad json', T0)).toBeNull();
    expect(parseSave('[1,2,3]', T0)).toBeNull();
    expect(parseSave('', T0)).toBeNull();
    expect(parseSave('null', T0)).toBeNull();
  });

  test('版本号比本 App 新 → 读不懂', () => {
    expect(saveFromJson({ v: SAVE_VERSION + 1 }, T0)).toBeNull();
    expect(saveFromJson({ v: 0 }, T0)).toBeNull();
  });

  test('单号兜底：下一张单号一定大于存档里任何一张', () => {
    const s = saveFromJson(
      {
        queue: [{ serial: 90 }],
        active: { task: { serial: 120 }, startAt: T0 },
        meta: { nextSerial: 60, remedyOffer: { serial: 130, kind: 'remedy' } },
      },
      T0,
    )!;
    expect(s.meta.nextSerial).toBe(131);
  });

  test('有主线时丢掉记着的待拆目标（防脏档）；没主线时保留', () => {
    const withPlan = saveFromJson(
      { goal: saveToJson(sampleSave())['goal'], pendingGoal: '学吉他' },
      T0,
    )!;
    expect(withPlan.pendingGoal).toBe('');
    const noPlan = saveFromJson({ pendingGoal: '  学吉他 ' }, T0)!;
    expect(noPlan.pendingGoal).toBe('学吉他');
  });

  test('目标期限缺失时按清单条数兜底；目标身份按立目标时刻推', () => {
    const g = goal({ days: 0 });
    const s = saveFromJson(
      { goal: { ...(saveToJson({ ...sampleSave(), goal: g })['goal'] as object), days: 0 } },
      T0,
    )!;
    expect(s.goal.days).toBe(g.plan.length);
    expect(goalId(s.goal)).toBe(`g${T0}`);
    expect(goalId({ ...s.goal, uid: 'demo' })).toBe('demo');
  });

  test('队列里的单字段齐全往返', () => {
    const q = quest(77, { kind: 'remedy', hinted: true, reason: '', attrs: { 智: 2 } });
    const s = roundtrip({ ...sampleSave(), queue: [q] })!;
    expect(s.queue[0]).toEqual(q);
  });
});

describe('日历日工具', () => {
  test('dayKey 按本地日历日', () => {
    expect(dayKey(T0)).toBe('2026-11-21');
    expect(dayKey(new Date(2026, 0, 1, 0, 0, 1).getTime())).toBe('2026-01-01');
    expect(isDayKey('2026-11-21')).toBe(true);
    expect(isDayKey('2026/11/21')).toBe(false);
  });

  test('相差天数与加减天，跨月跨年都对', () => {
    expect(daysBetween('2026-11-20', '2026-11-21')).toBe(1);
    expect(daysBetween('2026-11-21', '2026-11-21')).toBe(0);
    expect(daysBetween('2026-12-31', '2027-01-01')).toBe(1);
    expect(daysBetween('2026-03-01', '2026-02-27')).toBe(-2);
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01');
    expect(addDays('2026-03-01', -1)).toBe('2026-02-28');
  });
});
