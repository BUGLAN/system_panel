/**
 * 拆解：匹配类目（同步，≤30s 级）/ 起拆解任务 / 读任务（刷新后接上进度）。
 * 入口先过本地自伤闸门（命中不调 LLM、不计用量）与「太空了」检查。
 */
import { Hono } from 'hono';
import { z } from 'zod';
import type { MatchView } from '@host/core/api/types';
import { interviewCardsFor, isVagueGoal } from '@host/core/goal/categories';
import { asPlanFailure } from '../agent/goalBuilder';
import { CRISIS_CARE_LINE, isCrisisText } from '../agent/guardrail';
import { matchGoal } from '../agent/planAgent';
import { me, type AppEnv } from '../http/context';
import { ApiError, notFound } from '../http/errors';
import { rejected } from '../http/intent';
import { body } from '../http/zod';
import { llmFor } from '../llm/gateway';
import { loadSave } from '../repo/saves';

/** 目标与访谈「自己写」上限 50 字（按字符数，不按字节） */
const GOAL_MAX = 50;
const chars = (s: string) => [...s].length;
const GoalText = z
  .string()
  .trim()
  .min(1, '先说一句目标。')
  .refine((s) => chars(s) <= GOAL_MAX, `目标最多 ${GOAL_MAX} 字。`);

const Match = z.object({ text: GoalText });
const Job = z.object({
  kind: z.enum(['bind', 'retry', 'swap', 'resume']),
  text: GoalText.optional(),
  answers: z
    .record(
      z.string().max(40),
      z
        .string()
        .trim()
        .refine((s) => chars(s) <= GOAL_MAX, `答案最多 ${GOAL_MAX} 字。`),
    )
    .optional(),
});

/** 自伤闸门 / 太空了：前端也会先拦，这里兜底 */
function gateGoal(text: string): void {
  if (isCrisisText(text)) throw new ApiError(422, 'crisis', CRISIS_CARE_LINE);
  if (isVagueGoal(text)) throw rejected('太空了。说点具体的——[一句话]。');
}

export const planRoutes = new Hono<AppEnv>()
  .post('/match', async (c) => {
    const u = me(c);
    const { text } = await body(c, Match);
    gateGoal(text);
    const deps = c.var.deps;
    try {
      const m = await matchGoal({ client: llmFor(deps, u).text, goalText: text });
      deps.jobs.rememberMatch(u.id, text, m);
      const lv = loadSave(deps.dbh.db, u.id, deps.now()).save.host.lv;
      const match: MatchView = { catId: m.cat.id, short: m.short, days: m.days, quota: m.quota };
      return c.json({ ok: true, match, cards: interviewCardsFor(m.cat, lv) });
    } catch (e) {
      const f = asPlanFailure(e);
      throw new ApiError(502, 'plan_failed', f.detail, {
        failure: { code: f.code, detail: f.detail },
      });
    }
  })
  .post('/jobs', async (c) => {
    const u = me(c);
    const b = await body(c, Job);
    if ((b.kind === 'bind' || b.kind === 'swap') && !b.text) throw rejected('先说一句目标。');
    if (b.text) gateGoal(b.text);
    const job = c.var.deps.jobs.start(u, b.kind, {
      ...(b.text ? { text: b.text } : {}),
      ...(b.answers ? { answers: b.answers } : {}),
    });
    return c.json({ ok: true, job });
  })
  .get('/jobs/current', (c) => c.json({ ok: true, job: c.var.deps.jobs.current(me(c).id) }))
  .get('/jobs/:id', (c) => {
    const job = c.var.deps.jobs.get(me(c).id, c.req.param('id'));
    if (!job) throw notFound('这件拆解任务不在了（可能服务刚重启过）。');
    return c.json({ ok: true, job });
  });
