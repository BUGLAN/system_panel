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
    state: 'todo',
    finalTask: false,
    heldMs: null,
    doneAt: null,
    ...over,
  };
}

export function goal(over: Partial<Goal> = {}): Goal {
  return {
    text: '三个月跑完半马',
    short: '半马',
    at: T0,
    plan: [
      planTask(0, { state: 'done', heldMs: 754_000, doneAt: T0 + 1000 }),
      planTask(1, { rank: 'D' }),
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
    planIndex: 2,
    planTotal: 40,
    goalId: `g${T0}`,
    name: '慢跑 3 公里',
    reason: '上一张你用了 12 分钟。这一张，我加了点码。',
    proof: '跑步 App 截图',
    minutes: 30,
    rank: 'E',
    ...over,
  };
}

/** 一份「已绑定、手里有单、正在执行」的存档（队列里那张与执行中的都属于这条主线） */
export function sampleSave(): SaveData {
  const s = freshSave(T0);
  const g = goal();
  return {
    ...s,
    host: {
      ...s.host,
      lv: 3,
      exp: 7,
      streak: 3,
      bestStreak: 4,
      doneCount: 6,
      totalExp: 49,
    },
    goal: g,
    queue: [quest(53)],
    active: {
      task: quest(51, { planIndex: 1 }),
      startAt: T0 + 5000,
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
      lastRollDay: '2026-11-21',
    },
  };
}
