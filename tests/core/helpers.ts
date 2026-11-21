/** 核心逻辑测试的小工具 */
import { categoryOf } from '../../src/core/goal/categories';
import { buildPlanTasks, type TaskSpec } from '../../src/core/goal/plan';
import { QuestFlow } from '../../src/core/flow/questFlow';
import type { Goal } from '../../src/core/model/goal';
import { freshSave, type SaveData } from '../../src/core/save/saveData';
import type { Rank } from '../../src/core/data/rank';
import { T0 } from '../fixtures';

export const DAY = 86_400_000;

/** 可复现的随机源 */
export function seeded(seed = 1): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** 固定值随机源（暴击判定用：返回 0.99 = 必不暴击） */
export const fixed = (v: number) => () => v;

export function specs(ranks: Rank[], over: Partial<TaskSpec> = {}): TaskSpec[] {
  return ranks.map((r, i) => ({
    short: `第${i + 1}步`,
    title: `跑 ${i + 1} 公里`,
    proof: '跑步 App 截图',
    minutes: 20,
    rank: r,
    ...over,
  }));
}

/** 一条 run 类主线：清单 = ranks，整条一共 total 张 */
export function runGoal(ranks: Rank[], total = ranks.length, uid = 'g-run'): Goal {
  return {
    text: '三个月跑完半马',
    short: '半马',
    at: T0,
    plan: buildPlanTasks({ cat: categoryOf('run'), tasks: specs(ranks), total }),
    cat: 'run',
    days: total,
    interview: {},
    uid,
    planTotal: total,
    quota: 0,
  };
}

/** 已绑定的存档：主线发到在手窗口、没有日常 */
export function boundSave(goal: Goal = runGoal(['E', 'E', 'D', 'C', 'S'])): SaveData {
  const s = freshSave(T0);
  s.goal = goal;
  const f = new QuestFlow(s, { rnd: seeded() });
  f.publishPlanTasks();
  return f.save;
}

/** 接下队首那一单 */
export function flowWithActive(
  save: SaveData = boundSave(),
  rnd = fixed(0.99),
  at = T0,
): QuestFlow {
  const f = new QuestFlow(save, { rnd });
  f.accept(f.head!, at);
  return f;
}
