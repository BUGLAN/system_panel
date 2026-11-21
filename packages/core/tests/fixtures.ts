/** 测试用的样例数据 */
import type { Goal, PlanTask } from '../src/model/goal';
import type { Quest } from '../src/model/quest';
import { freshSave, type SaveData } from '../src/save/saveData';

/** 2026-11-21 10:00 本地时间 */
export const T0 = new Date(2026, 10, 21, 10, 0, 0).getTime();

export function planTask(i: number, over: Partial<PlanTask> = {}): PlanTask {
  return {
    index: i,
    short: `第${i + 1}步`,
    title: `慢跑 ${i + 1} 公里`,
    proof: '跑步 App 截图',
    minutes: 20 + i * 5,
    rank: 'E',
    attrs: { 力: 1 },
    state: 'todo',
    finalTask: false,
    heldMs: null,
    doneAt: null,
    timed: true,
    grade: null,
    ...over,
  };
}

export function goal(over: Partial<Goal> = {}): Goal {
  return {
    text: '三个月跑完半马',
    short: '半马',
    at: T0,
    plan: [
      planTask(0, { state: 'done', heldMs: 754_000, doneAt: T0 + 1000, grade: 'A' }),
      planTask(1, { timed: false, rank: 'D' }),
      planTask(2),
    ],
    cat: 'run',
    days: 90,
    interview: { level: '能跑 2 公里', freq: '一周三次' },
    uid: '',
    planTotal: 40,
    quota: 0,
    ...over,
  };
}

export function quest(serial: number, over: Partial<Quest> = {}): Quest {
  return {
    serial,
    kind: 'daily',
    planIndex: -1,
    planTotal: 0,
    goalId: '',
    name: '出门走 3000 步',
    reason: '今天的。我挑过了。',
    proof: '步数截图',
    minutes: 30,
    rank: 'E',
    attrs: { 体: 1, 敏: 1 },
    hinted: false,
    timed: true,
    ...over,
  };
}

/** 一份「已绑定、手里有单、正在执行」的存档 */
export function sampleSave(): SaveData {
  const s = freshSave(T0);
  const g = goal();
  return {
    ...s,
    host: {
      ...s.host,
      lv: 3,
      exp: 7,
      coins: 26,
      streak: 3,
      bestStreak: 4,
      title: 'first',
      ownedTitles: ['bind', 'first'],
      attrs: { 力: 5, 体: 2, 智: 1, 知: 0, 魅: 1, 敏: 0 },
      doneCount: 6,
      critCount: 1,
      failCount: 1,
      items: { dbl: 1, crit: 0, shield: 2, patch: 0 },
      totalExp: 49,
    },
    goal: g,
    queue: [quest(52), quest(53, { kind: 'main', goalId: `g${T0}`, planIndex: 2, planTotal: 40 })],
    active: {
      task: quest(51, {
        kind: 'main',
        goalId: `g${T0}`,
        planIndex: 1,
        planTotal: 40,
        timed: false,
      }),
      startAt: T0 + 5000,
      dbl: true,
      crit: false,
      shield: true,
      extraMs: 600_000,
      evidence: [
        { id: 'ev1', status: 'verified', note: '看得到里程', takenAt: T0 + 6000 },
        { id: 'ev2', status: 'unsure', note: '有点糊', takenAt: T0 + 7000 },
      ],
      sealed: false,
    },
    meta: {
      ...s.meta,
      nextSerial: 54,
      lastDoneDay: '2026-11-20',
      brokenStreak: 0,
      missedDay: null,
      retreatDay: '2026-11-21',
      retreatToday: 1,
      retreatTotal: 2,
      titleBeforeShame: null,
      remedyOffer: null,
      remedyDeadline: null,
      lastRollDay: '2026-11-21',
    },
  };
}
