/**
 * 状态与意图（服务端跑 QuestFlow，docs/05 第 3.2 节）。
 * 拦截文案与前端旧编排器（store/actions/exec.ts、goals.ts）一字不差，前端照样念出来。
 */
import { Hono } from 'hono';
import { z } from 'zod';
import { itemById, type ItemId } from '@host/core/data/items';
import { fail } from '@host/core/flow/settle';
import type { QuestFlow } from '@host/core/flow/questFlow';
import { DAILY_CAP } from '@host/core/goal/daily';
import { goalFirstOpenIndex } from '@host/core/model/goal';
import { pad2 } from '@host/core/format';
import { dayKey } from '@host/core/time/day';
import { me, type AppEnv, type Ctx } from '../http/context';
import { intent, rejected, stale } from '../http/intent';
import { body } from '../http/zod';
import { runFlow } from '../flow/runner';
import { listHistory } from '../repo/history';
import { activeIs, submitQuest } from '../flow/submit';

const Serial = z.object({ serial: z.number().int().nonnegative() });
const Item = z.object({ item: z.string().min(1).max(20) });
const Title = z.object({ title: z.string().min(1).max(40) });
const Remedy = z.object({ now: z.boolean() });
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
  /** 计时单到点检查（结论都在 events 里） */
  .post('/flow/tick', (c) => flowIntent(c, () => undefined))
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
  .post('/flow/equip', async (c) => {
    const { item } = await body(c, Item);
    return flowIntent(c, (f) => {
      const why = f.itemBlock(item as ItemId);
      if (why) {
        if (!f.active) throw stale(why);
        throw rejected(`${itemById(item)?.name ?? ''}：${why}`);
      }
      f.useItem(item as ItemId);
    });
  })
  .post('/flow/submit', async (c) => {
    const { serial } = await body(c, Serial);
    return intent(c, () => submitQuest(c.var.deps, me(c), serial));
  })
  .post('/flow/give-up', async (c) => {
    const { serial } = await body(c, Serial);
    return flowIntent(
      c,
      (f, now) => {
        activeIs(f, serial, '这一单已经不在执行了。');
        const out = fail(f, { now, how: 'quit' });
        if (!out) throw stale('这一单已经不在执行了。');
        return out;
      },
      (outcome) => ({ outcome }),
    );
  })
  .post('/flow/take-remedy', async (c) => {
    const b = await body(c, Remedy);
    return flowIntent(
      c,
      (f) => f.takeRemedy(b.now),
      (quest) => ({ quest }),
    );
  })
  .post('/flow/refill', (c) =>
    flowIntent(
      c,
      (f) => {
        const inQueue = f.queue.filter((q) => q.kind === 'daily').length;
        const room = Math.max(0, DAILY_CAP - inQueue);
        if (room === 0) throw rejected('今天的日常已经给满了。');
        const added = f.genDailies(Math.min(2, room));
        f.queue.push(...added);
        f.notify();
        return added.length;
      },
      (added) => ({ added }),
    ),
  )
  .post('/flow/buy', async (c) => {
    const { item } = await body(c, Item);
    return flowIntent(c, (f) => {
      const why = f.buyBlock(item);
      if (why) throw rejected(why);
      f.buy(item);
    });
  })
  .post('/flow/patch', (c) =>
    flowIntent(c, (f, now) => {
      const st = f.patchStatus(now);
      if (!st.ok) throw rejected(st.reason);
      f.usePatch(now);
    }),
  )
  .post('/flow/wear', async (c) => {
    const { title } = await body(c, Title);
    return flowIntent(c, (f) => {
      const h = f.host;
      if (!h.ownedTitles.includes(title)) throw rejected('还没解锁。');
      if (h.title === 'mouth') throw rejected('「口头巨人」摘不掉。完成一单再说。');
      if (h.title !== title) f.equip(title);
    });
  })
  /** 拆解失败「先跳过」：记住目标、先发当天日常（C5） */
  .post('/flow/skip-plan', async (c) => {
    const { text } = await body(c, Skip);
    const u = me(c);
    return flowIntent(c, (f, now) => {
      f.skipPlan(text);
      f.meta.lastRollDay = dayKey(now, u.tz);
    });
  });
