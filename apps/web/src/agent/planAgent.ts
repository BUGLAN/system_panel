/**
 * 拆解代理与匹配代理：工具循环 + 分段并行。
 * 移植自 flutter-final:app/lib/agent/plan_agent.dart / goal_match_agent.dart。
 *
 * 失败一律抛 PlanFailure：形状错 / 规则错给模型看一次原因重交，轮数用尽才抛；
 * 她按护栏拒拆（〔不拆〕）→ badGoal；只说话不交工具 → noPlan。
 */
import {
  PlanFailure,
  PlanRuleError,
  PlanShapeError,
  type PlanFailureCode,
} from '@host/core/goal/planFailure';
import { PLAN_SEGMENT_CONCURRENCY, planSegmentsFor, type TaskSpec } from '@host/core/goal/plan';
import { MATCH_GUARD, refusalOf } from './guardrail';
import type { LlmClient, LlmFailure, LlmMessage } from './llmClient';
import {
  newMatchDraft,
  newPlanDraft,
  setGoalCategoryTool,
  setPlanTool,
  type GoalMatch,
} from './mainlineTools';
import { buildConversation, splitTag, type WireMessage } from './persona';
import { briefScenario, briefUserText, briefWindow, type PlanBrief } from './planBrief';
import { StrictToolRegistry } from './tools';

export const PLAN_MAX_ROUNDS = 6;
export const MATCH_MAX_ROUNDS = 4;
export const PLAN_TIMEOUT_MS = 90_000;
export const MATCH_TIMEOUT_MS = 60_000;

export function failureCodeOf(f: LlmFailure): PlanFailureCode {
  return f;
}

const clip = (s: string) => {
  const t = s.trim().replace(/\n/g, ' ');
  return t.length <= 120 ? t : `${t.slice(0, 120)}…`;
};

const toLlm = (msgs: WireMessage[]): LlmMessage[] =>
  msgs.map((m) => ({ role: m.role, text: m.text }));

/** 记忆摘要的来源（可缺省） */
export type MemoryDigest = (query: string) => Promise<string>;

export interface PlanResult {
  tasks: TaskSpec[];
  /** 她顺手说的一句（可能为空） */
  line: string | null;
}

/** 单份（一个窗口或一段）的工具循环 */
async function runPlanLoop(o: {
  client: LlmClient;
  brief: PlanBrief;
  digest?: MemoryDigest;
  signal?: AbortSignal;
}): Promise<PlanResult> {
  const seg = o.brief.segment ?? null;
  const w = briefWindow(o.brief);
  const draft = newPlanDraft();
  const tools = new StrictToolRegistry().register(
    setPlanTool({
      goalText: o.brief.goalText,
      taskCount: seg?.size ?? w.size,
      days: o.brief.days,
      draft,
      firstGoal: o.brief.firstGoal,
      segment: seg,
      window: w,
    }),
  );
  const msgs = buildConversation({
    userText: briefUserText(o.brief),
    ...(o.brief.statusLine ? { statusLine: o.brief.statusLine } : {}),
    memoryDigest: o.digest ? await o.digest(o.brief.goalText) : '',
    scenario: briefScenario(o.brief),
  });
  for (let round = 1; round <= PLAN_MAX_ROUNDS; round++) {
    const r = await o.client.chat({
      messages: toLlm(msgs),
      tools: tools.defs(),
      temperature: 0.7,
      timeoutMs: PLAN_TIMEOUT_MS,
      ...(o.signal ? { signal: o.signal } : {}),
    });
    if (!r.ok)
      throw new PlanFailure(failureCodeOf(r.failure), `第 ${round} 轮请求失败：${r.detail}`);
    if (!r.toolCalls.length) {
      const refused = draft.tasks ? null : refusalOf(r.text);
      if (refused) throw new PlanFailure('badGoal', `她不拆这个目标：${clip(refused)}`);
      if (!draft.tasks)
        throw new PlanFailure(
          'noPlan',
          `第 ${round} 轮她只说了话、没有调用 set_plan（正文：${clip(r.text)}）`,
        );
      const t = splitTag(r.text);
      return { tasks: draft.tasks, line: t.text || null };
    }
    const feed: string[] = [];
    for (const c of r.toolCalls) {
      try {
        const oc = await tools.execute(c.name, c.arguments);
        feed.push(`${c.name}：${oc.message}`);
      } catch (e) {
        if (e instanceof PlanShapeError || e instanceof PlanRuleError) {
          if (round >= PLAN_MAX_ROUNDS) throw e;
          feed.push(`${c.name} 被规则驳回：${e.detail}。请按规则重交整份计划。`);
        } else {
          throw e;
        }
      }
    }
    if (draft.tasks && r.toolCalls.every((c) => c.name === 'set_plan')) {
      const t = splitTag(r.text);
      return { tasks: draft.tasks, line: t.text || null };
    }
    msgs.push({ role: 'assistant', text: r.text.trim() || '（她正在翻宿主的档案……）' });
    msgs.push({
      role: 'user',
      text:
        `〔系统回执〕刚才的工具调用结果：\n${feed.join('\n')}` +
        (draft.tasks
          ? '\n\n（主线已收到。**现在就不要再调用任何工具**，只用一句话告诉他为什么这么排。）'
          : `\n\n（主线还没交上来：调用 set_plan 把 ${seg?.size ?? w.size} 张交上来。）`),
    });
  }
  throw new PlanFailure('noPlan', `工具循环 ${PLAN_MAX_ROUNDS} 轮用尽仍没拿到 set_plan 的任务池`);
}

/**
 * 拆一个窗口：≤12 张一次拆；更长的切段并行（每段一套独立的 set_plan），按顺序拼回。
 * onProgress(已完成段数, 总段数) 给加载卡的分步进度用。
 */
export async function generatePlanTasks(o: {
  client: LlmClient;
  brief: PlanBrief;
  digest?: MemoryDigest;
  onProgress?: (done: number, total: number) => void;
  signal?: AbortSignal;
}): Promise<{ tasks: TaskSpec[]; line: string | null }> {
  const win = briefWindow(o.brief);
  const segs = planSegmentsFor(win);
  const whole = segs.length === 1;
  const parts: Array<PlanResult | null> = segs.map(() => null);
  let done = 0;
  o.onProgress?.(0, segs.length);
  let next = 0;
  const worker = async () => {
    while (next < segs.length) {
      const i = next++;
      const seg = whole ? null : (segs[i] ?? null);
      parts[i] = await runPlanLoop({
        client: o.client,
        brief: { ...o.brief, segment: seg, window: win },
        ...(o.digest ? { digest: o.digest } : {}),
        ...(o.signal ? { signal: o.signal } : {}),
      });
      o.onProgress?.(++done, segs.length);
    }
  };
  await Promise.all(
    Array.from({ length: Math.min(PLAN_SEGMENT_CONCURRENCY, segs.length) }, worker),
  );
  return {
    tasks: parts.flatMap((p) => p?.tasks ?? []),
    line: parts.map((p) => p?.line).find((l) => !!l) ?? null,
  };
}

/** 匹配提示词（单独拎出来测「护栏条款在提示词里」） */
export function matchPrompt(goalText: string): string {
  return `宿主立了目标：「${goalText}」。\n用 set_goal_category 告诉我：它属于哪一类、天幕短字写什么、期限多少天。\n${MATCH_GUARD}`;
}

/** 匹配：类别 / 天幕短字 / 期限 / 次数配额 */
export async function matchGoal(o: {
  client: LlmClient;
  goalText: string;
  statusLine?: string;
  digest?: MemoryDigest;
  signal?: AbortSignal;
}): Promise<GoalMatch> {
  const draft = newMatchDraft();
  const tools = new StrictToolRegistry().register(
    setGoalCategoryTool({ goalText: o.goalText, draft }),
  );
  const msgs = buildConversation({
    userText: matchPrompt(o.goalText),
    ...(o.statusLine ? { statusLine: o.statusLine } : {}),
    memoryDigest: o.digest ? await o.digest(o.goalText) : '',
    scenario: '识别目标：判断类别/短字/期限，交给 set_goal_category。',
  });
  for (let round = 1; round <= MATCH_MAX_ROUNDS; round++) {
    const r = await o.client.chat({
      messages: toLlm(msgs),
      tools: tools.defs(),
      temperature: 0.3,
      timeoutMs: MATCH_TIMEOUT_MS,
      ...(o.signal ? { signal: o.signal } : {}),
    });
    if (!r.ok)
      throw new PlanFailure(failureCodeOf(r.failure), `第 ${round} 轮匹配请求失败：${r.detail}`);
    if (!r.toolCalls.length) {
      const got = draft.match;
      const refused = got ? null : refusalOf(r.text);
      if (refused) throw new PlanFailure('badGoal', `她不接这个目标：${clip(refused)}`);
      if (!got)
        throw new PlanFailure(
          'noPlan',
          `第 ${round} 轮她没调用 set_goal_category（正文：${clip(r.text)}）`,
        );
      return got;
    }
    const feed: string[] = [];
    for (const c of r.toolCalls) {
      try {
        const oc = await tools.execute(c.name, c.arguments);
        feed.push(`${c.name}：${oc.message}`);
      } catch (e) {
        if (e instanceof PlanShapeError) {
          if (round >= MATCH_MAX_ROUNDS) throw e;
          feed.push(`${c.name} 参数不合法：${e.detail}`);
        } else {
          throw e;
        }
      }
    }
    if (draft.match) return draft.match;
    msgs.push({ role: 'assistant', text: r.text.trim() || '（她在看这条目标……）' });
    msgs.push({
      role: 'user',
      text: `〔系统回执〕\n${feed.join('\n')}\n\n（还没交上来：调用 set_goal_category。）`,
    });
  }
  throw new PlanFailure(
    'noPlan',
    `匹配循环 ${MATCH_MAX_ROUNDS} 轮用尽仍没拿到 set_goal_category 的结果`,
  );
}
