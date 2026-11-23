/**
 * 状态与意图（服务端跑 QuestFlow，docs/05 第 3.2 节）。
 * 拦截文案与前端旧编排器（store/actions/exec.ts、goals.ts）一字不差，前端照样念出来。
 */
import { Hono } from 'hono';
import { z } from 'zod';
import type { QuestFlow } from '@host/core/flow/questFlow';
import { goalFirstOpenIndex } from '@host/core/model/goal';
import { pad2 } from '@host/core/format';
import { me, type AppEnv, type Ctx } from '../http/context';
import { intent, rejected, stale } from '../http/intent';
import { body } from '../http/zod';
import { runFlow } from '../flow/runner';
import { listHistory } from '../repo/history';
import { submitQuest } from '../flow/submit';

const Serial = z.object({ serial: z.number().int().nonnegative() });
const Skip = z.object({ text: z.string().max(200) });

/** 跑一个意图并回 { state, events, ...extra } */
async function flowIntent<T>(
  c: Ctx,
  fn: (f: QuestFlow, now: number) => T,
  shape: (v: T) => Record<string, unknown> = () => ({}),
): Promise<Response> {
  return intent(c, async () => {
    const r = await runFlow(c.var.deps, me(c), fn);
    return { state: r.state, events: r.events, ...shape(r.value) };
  });
}

export const flowRoutes = new Hono<AppEnv>()
  /** 读状态（开机 / 回前台 / 跨 0 点）；boot=1 时带上「上次来过」 */
  .get('/state', async (c) => {
    const r = await runFlow(c.var.deps, me(c), () => undefined);
    return c.json({
      ok: true,
      state: r.state,
      events: r.events,
      ...(c.req.query('boot') ? { prevSeen: r.prevSeen } : {}),
    });
  })
  /** 流水（档案 / 战报）：旧 → 新 */
  .get('/history', (c) => c.json({ ok: true, entries: listHistory(c.var.deps.dbh.db, me(c).id) }))
  .post('/flow/accept', async (c) => {
    const { serial } = await body(c, Serial);
    return flowIntent(c, (f, now) => {
      if (f.active) throw stale('你手上还有一单没交差。');
      const q = f.queue.find((x) => x.serial === serial);
      if (!q) throw stale('这张单已经不在她手里了。');
      if (f.isMainLocked(q)) {
        const first = goalFirstOpenIndex(f.goal);
        throw rejected(
          `主线第 ${pad2(q.planIndex + 1)} 单还没解封：先做第 ${pad2(first + 1)} 单。`,
        );
      }
      f.accept(q, now);
    });
  })
  .post('/flow/submit', async (c) => {
    const { serial } = await body(c, Serial);
    return intent(c, () => submitQuest(c.var.deps, me(c), serial));
  })
  /** 拆解失败「先跳过」：记住目标，之后在大厅重试（C5） */
  .post('/flow/skip-plan', async (c) => {
    const { text } = await body(c, Skip);
    return flowIntent(c, (f) => f.skipPlan(text));
  });
