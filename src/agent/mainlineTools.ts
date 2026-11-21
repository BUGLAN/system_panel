/**
 * 拆解与匹配的交卷工具：set_plan / set_goal_category。
 * 移植自 flutter-final:app/lib/agent/mainline_tool.dart。
 * 规则校验在工具里跑：不合规折成形状错，让代理把原因回填给模型重交。
 */
import { CATEGORY_IDS, categoryOf, isCategoryId } from '../core/goal/categories';
import type { GoalCategory } from '../core/data/categoryTypes';
import { RANKS } from '../core/data/rank';
import {
  PLAN_MAX_TASKS,
  PLAN_MIN_TASKS,
  validatePlan,
  validatePlanSegment,
  validatePlanWindow,
  windowCount,
  windowIndex,
  windowIsLast,
  windowIsWhole,
  windowTo,
  segmentTo,
  type PlanSegment,
  type PlanWindow,
  type TaskSpec,
} from '../core/goal/plan';
import { PlanRuleError, PlanShapeError } from '../core/goal/planFailure';
import { PLAN_SCHEMA_GUARD } from './guardrail';
import { objSchema, toolOk, type AgentTool } from './tools';

export interface PlanDraft {
  tasks: TaskSpec[] | null;
  attempts: number;
}

export const newPlanDraft = (): PlanDraft => ({ tasks: null, attempts: 0 });

export const TASK_MODES = ['timed', 'checkin'] as const;

/** mode：checkin → 打卡单；缺省 / 非法 → 计时单（大小写与空白都容忍） */
export function parseTaskMode(raw: unknown): boolean {
  return (
    String(raw ?? '')
      .trim()
      .toLowerCase() !== 'checkin'
  );
}

const str = (v: unknown) =>
  typeof v === 'string' ? v.trim() : v === null || v === undefined ? '' : String(v);

export function setPlanSchema(taskCount: number): Record<string, unknown> {
  return objSchema(
    {
      tasks: {
        type: 'array',
        minItems: taskCount,
        maxItems: taskCount,
        description:
          `正好 ${taskCount} 张，一张一天，按时间先后排。` +
          '每一张都是**一次能做完**的具体动作（不要写「坚持一个月」这种跨度几周的事，' +
          '也不要写「努力」「拆解目标」这类空话）。' +
          '**必须贴着目标本身写**：目标里的动作、次数、周期要出现在题面上' +
          '（例：「两周骑 10 次」就要写出骑多久/骑多远，而不是「把目标写在纸上」）。' +
          '难度与耗时逐张递增，档位不许倒退；最后一张是**兑现单**：' +
          'S 级、一次能证明目标达成的验证动作。' +
          '访谈答案里他亲口说的数字（能跑多远、一周几次、几点睡）必须用进题面。' +
          PLAN_SCHEMA_GUARD,
        items: objSchema(
          {
            short: { type: 'string', description: '短标签，不超过 4 个字，显示在进度带上' },
            title: { type: 'string', description: '一句话行动，不超过 20 字，写清做什么、做多久' },
            proof: {
              type: 'string',
              description: '要拍什么当证据（截图/照片/录音），不超过 10 字',
            },
            minutes: {
              type: 'integer',
              description:
                '预计耗时（分钟）。**必须在该档位上限内**：F≤20 / E≤30 / D≤40 / C≤60 / B≤90 / A≤120 / S≤180',
            },
            rank: {
              type: 'string',
              enum: [...RANKS],
              description: '难度档位 F~S（F 最轻、S 最重）',
            },
            mode: {
              type: 'string',
              enum: [...TASK_MODES],
              description:
                '计时 timed / 打卡 checkin。一天内分散完成、或瞬间就能完成的动作' +
                '（称重、拍三餐、量腰围、早睡打卡）标 checkin：不计时、随时交证据；' +
                '需要连续投入一段时间的（跑步、练琴、刷题）标 timed。缺省按 timed',
            },
          },
          ['short', 'title', 'proof', 'minutes', 'rank'],
        ),
      },
    },
    ['tasks'],
  );
}

export function setPlanTool(o: {
  goalText: string;
  taskCount: number;
  days: number;
  draft: PlanDraft;
  firstGoal?: boolean;
  quota?: number;
  segment?: PlanSegment | null;
  window?: PlanWindow | null;
}): AgentTool {
  const seg = o.segment ?? null;
  const win = o.window && !windowIsWhole(o.window) ? o.window : null;
  const description =
    seg === null && win !== null
      ? `交宿主目标「${o.goalText}」（期限 ${o.days} 天、共 ${win.total} 张，滚动生成）的` +
        `第 ${windowIndex(win) + 1}/${windowCount(win)} 段：第 ${win.from}~${windowTo(win)} 张，` +
        `必须正好 ${o.taskCount} 张。档位只能 ${win.lo}~${win.hi}、逐张不许倒退；` +
        `${windowIsLast(win) ? '最后一张是 S 级兑现单。' : '本段没有兑现单。'}` +
        '宿主现状与记忆已在系统提示里，直接据此拆。每张 minutes 必须在该档位上限内。'
      : seg === null
        ? `把宿主的目标「${o.goalText}」（期限 ${o.days} 天）拆成 ${o.taskCount} 张任务、交上来当计划。` +
          '他的现状（等级/连败/最弱维）与记忆已在系统提示的宿主档案里，直接据此拆，不必再查。' +
          `必须正好 ${o.taskCount} 张。` +
          `${o.firstGoal ? '这是**首目标**：档位只能是 E/D/C。' : '档位不许倒退，最后一张必须是 S 级兑现单。'}` +
          '每张 minutes 必须在该档位上限内。'
        : `交宿主目标「${o.goalText}」（期限 ${o.days} 天、共 ${seg.total} 张）的` +
          `第 ${seg.index + 1}/${seg.count} 段：第 ${seg.from}~${segmentTo(seg)} 张，` +
          `必须正好 ${o.taskCount} 张。档位只能 ${seg.lo}~${seg.hi}、段内不许倒退；` +
          `${seg.last ? '最后一张是 S 级兑现单。' : '本段没有兑现单。'}` +
          '宿主现状与记忆已在系统提示里，直接据此拆。每张 minutes 必须在该档位上限内。';

  return {
    name: 'set_plan',
    description,
    parameters: setPlanSchema(o.taskCount),
    run(args) {
      o.draft.attempts++;
      const raw = args['tasks'];
      if (!Array.isArray(raw) || raw.length === 0) {
        throw new PlanShapeError(-1, 'tasks', `tasks 必须是数组，且正好 ${o.taskCount} 张`);
      }
      if (raw.length !== o.taskCount) {
        throw new PlanShapeError(
          -1,
          'tasks',
          `计划要正好 ${o.taskCount} 张，模型给了 ${raw.length} 张`,
        );
      }
      const out: TaskSpec[] = raw.map((item: unknown, i) => {
        if (!item || typeof item !== 'object' || Array.isArray(item)) {
          throw new PlanShapeError(i, 'tasks', `第 ${i + 1} 张不是对象`);
        }
        const it = item as Record<string, unknown>;
        const short = str(it['short']);
        const title = str(it['title']);
        const proof = str(it['proof']);
        const rank = str(it['rank']).toUpperCase();
        const mr = it['minutes'];
        const minutes = typeof mr === 'number' ? Math.trunc(mr) : Number.parseInt(str(mr), 10);
        if (!short) throw new PlanShapeError(i, 'short', `第 ${i + 1} 张的 short 是空的`);
        if (!title) throw new PlanShapeError(i, 'title', `第 ${i + 1} 张的 title 是空的`);
        if (!proof) throw new PlanShapeError(i, 'proof', `第 ${i + 1} 张的 proof 是空的`);
        if (!(RANKS as readonly string[]).includes(rank)) {
          throw new PlanShapeError(
            i,
            'rank',
            `第 ${i + 1} 张的 rank「${str(it['rank'])}」不是 ${RANKS.join('/')}`,
          );
        }
        if (!Number.isFinite(minutes) || minutes <= 0) {
          throw new PlanShapeError(
            i,
            'minutes',
            `第 ${i + 1} 张的 minutes 不是正整数（收到 ${String(mr)}）`,
          );
        }
        return { short, title, proof, minutes, rank, timed: parseTaskMode(it['mode']) };
      });
      try {
        if (seg) validatePlanSegment(seg, out);
        else if (o.window) validatePlanWindow(o.window, out);
        else
          validatePlan({
            days: o.days,
            tasks: out,
            quota: o.quota ?? 0,
            firstGoal: o.firstGoal ?? false,
          });
      } catch (e) {
        if (e instanceof PlanRuleError) throw new PlanShapeError(-1, 'tasks', e.detail);
        throw e;
      }
      o.draft.tasks = out;
      const first = out[0];
      const last = out[out.length - 1];
      return toolOk(
        `计划收下了：${o.taskCount} 张，${first?.short ?? ''} → … → ${last?.short ?? ''}。拿去用一句话告诉他为什么这么排。`,
      );
    },
  };
}

// ── 目标匹配（类别 / 天幕短字 / 期限 / 次数配额）────────────────

export interface GoalMatch {
  cat: GoalCategory;
  short: string;
  days: number;
  quota: number;
}

export interface GoalMatchDraft {
  match: GoalMatch | null;
  attempts: number;
}

export const newMatchDraft = (): GoalMatchDraft => ({ match: null, attempts: 0 });

export function setGoalCategorySchema(): Record<string, unknown> {
  return objSchema(
    {
      id: {
        type: 'string',
        enum: [...CATEGORY_IDS],
        description:
          '目标类型。按目标**真正的动作**选，不要因为词表里没有就选 gen：' +
          '骑行/游泳/爬山都算 run（耐力运动）；球类/格斗算 fit；' +
          '学乐器（吉他/钢琴/尤克里里/架子鼓）、画画/素描/水彩、舞蹈、书法、摄影' +
          '这类**靠反复练习学会的手艺**算 skill（「三个月学会弹吉他」「学会画画」都是 skill）；' +
          'make 只留「做出一个东西」（写完一篇小说、剪一支视频、做一套作品集）；' +
          '背单词、四六级/雅思/托福、学一门外语、练口语听力都算 lang' +
          '（「两月背完四级词汇」是 lang，不是 exam）；' +
          'exam 只留考研/考公/考证/期末这类**整门考试备考**；' +
          '读书算 exam；只有确实无法归类才用 gen。',
      },
      short: {
        type: 'string',
        description:
          '天幕上的大字，不超过 4 个字，取目标里最有辨识度的那个词（如「骑自行车」「半马」）',
      },
      days: {
        type: 'integer',
        description:
          '期限天数。按目标里写的周期读：一周 7 / 两周 14 / 一个月 30 / ' +
          '三个月 90 / 半年 180 / 一年 365；没写周期就按这件事**合理需要多久**给一个，不要留空。' +
          '减重类没写周期时，按每周最多减约 1 公斤（2 斤）推算。',
      },
      quota: {
        type: 'integer',
        description:
          '目标自带的**次数配额**：目标里写「10 次」就给 10，「每周 3 次」按总次数给；' +
          '不是次数型目标（如「三个月跑完半马」）就给 0。⚠️ 清单条数按它算，所以填错会直接改变计划规模。',
      },
    },
    ['id', 'short', 'days', 'quota'],
  );
}

const intOf = (v: unknown): number | null => {
  if (typeof v === 'number' && Number.isFinite(v)) return Math.trunc(v);
  const n = Number.parseInt(String(v ?? ''), 10);
  return Number.isFinite(n) ? n : null;
};

export function setGoalCategoryTool(o: { goalText: string; draft: GoalMatchDraft }): AgentTool {
  return {
    name: 'set_goal_category',
    description: `判断宿主的目标「${o.goalText}」属于哪一类、天幕短字写什么、期限多少天。先看清目标本身的动作与周期，再交上来。`,
    parameters: setGoalCategorySchema(),
    run(args) {
      o.draft.attempts++;
      const id = str(args['id']);
      if (!isCategoryId(id)) {
        throw new PlanShapeError(
          -1,
          'id',
          `类别「${id}」不在可选列表里。必须从这几个 id 里选一个：${CATEGORY_IDS.join(' / ')}`,
        );
      }
      const short = str(args['short']);
      if (!short) throw new PlanShapeError(-1, 'short', '天幕短字是空的');
      const days = intOf(args['days']);
      if (days === null)
        throw new PlanShapeError(-1, 'days', `期限不是整数（收到 ${String(args['days'])}）`);
      if (days < PLAN_MIN_TASKS || days > PLAN_MAX_TASKS) {
        throw new PlanShapeError(
          -1,
          'days',
          `期限 ${days} 天不在 ${PLAN_MIN_TASKS}~${PLAN_MAX_TASKS} 之间`,
        );
      }
      const quota = intOf(args['quota']);
      if (quota === null || quota < 0)
        throw new PlanShapeError(
          -1,
          'quota',
          `次数配额不是非负整数（收到 ${String(args['quota'])}）`,
        );
      if (quota > PLAN_MAX_TASKS)
        throw new PlanShapeError(-1, 'quota', `次数配额 ${quota} 超过上限 ${PLAN_MAX_TASKS}`);
      const cat = categoryOf(id);
      o.draft.match = { cat, short, days, quota };
      return toolOk(
        `记下了：${cat.label}（${cat.id}）· 天幕「${short}」· 期限 ${days} 天 · 次数配额 ${quota === 0 ? '无' : `${quota} 次`}。`,
      );
    },
  };
}
