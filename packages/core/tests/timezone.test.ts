import { describe, expect, it } from 'vitest';
import { QuestFlow } from '../src/flow/questFlow';
import { settle } from '../src/flow/settle';
import { addDays, dayKey, isTimeZone } from '../src/time/day';
import { boundSave, fixed } from './helpers';

// UTC 2026-11-21 17:30 = 上海 11-22 01:30 = 洛杉矶 11-21 09:30
const AT = Date.UTC(2026, 10, 21, 17, 30);

describe('日历日按账号时区算（docs/05 Q1）', () => {
  it('同一时刻，不同时区是不同的「今天」', () => {
    expect(dayKey(AT, 'Asia/Shanghai')).toBe('2026-11-22');
    expect(dayKey(AT, 'America/Los_Angeles')).toBe('2026-11-21');
    expect(dayKey(AT, 'UTC')).toBe('2026-11-21');
  });

  it('夏令时切换那天也是正常的日历日', () => {
    // 2026-11-01 洛杉矶 02:00 回拨；当天 23:59 仍是 11-01
    expect(dayKey(Date.UTC(2026, 10, 2, 7, 59), 'America/Los_Angeles')).toBe('2026-11-01');
    expect(dayKey(Date.UTC(2026, 10, 2, 8, 1), 'America/Los_Angeles')).toBe('2026-11-02');
  });

  it('认得 IANA 时区名，乱写的不认', () => {
    expect(isTimeZone('Asia/Shanghai')).toBe(true);
    expect(isTimeZone('Mars/Base')).toBe(false);
    expect(isTimeZone('')).toBe(false);
    expect(isTimeZone(8)).toBe(false);
  });

  it('结算记的「最近完成日」跟着时区走', () => {
    const run = (tz: string) => {
      const f = new QuestFlow(boundSave(), { rnd: fixed(0.99), tz });
      f.accept(f.head!, AT - 60_000);
      settle(f, { now: AT });
      return f.meta.lastDoneDay;
    };
    expect(run('Asia/Shanghai')).toBe('2026-11-22');
    expect(run('America/Los_Angeles')).toBe('2026-11-21');
  });

  it('换日只在账号时区的 0 点之后发生；断签判定同口径', () => {
    const s = boundSave();
    s.host.streak = 3;
    s.meta.lastDoneDay = '2026-11-20';
    s.meta.lastRollDay = '2026-11-21';
    // 上海已经是 22 号：昨天（21）没做 → 断签当场归零，可补 21 号
    const sh = new QuestFlow(s, { tz: 'Asia/Shanghai' });
    expect(sh.rollDay(AT)).toBe(true);
    expect(sh.host.streak).toBe(0);
    expect(sh.meta.missedDay).toBe('2026-11-21');
    // 洛杉矶还是 21 号：同一天，不换日、不断签
    const la = new QuestFlow(s, { tz: 'America/Los_Angeles' });
    expect(la.rollDay(AT)).toBe(false);
    expect(la.host.streak).toBe(3);
    expect(addDays('2026-11-21', 1)).toBe('2026-11-22');
  });

  it('补签可用性按账号时区判断「昨天」', () => {
    const s = boundSave();
    s.host.items['patch'] = 1;
    s.meta.brokenStreak = 4;
    s.meta.missedDay = '2026-11-21';
    expect(new QuestFlow(s, { tz: 'Asia/Shanghai' }).patchStatus(AT)).toEqual({
      ok: true,
      restoreTo: 5,
    });
    expect(new QuestFlow(s, { tz: 'America/Los_Angeles' }).patchStatus(AT)).toEqual({
      ok: false,
      reason: '过了补签的那一天。',
    });
  });
});
