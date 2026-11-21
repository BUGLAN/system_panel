/**
 * 聊天：读记录 / 发一句（自伤闸门 → LLM 工具循环）/ 查状态（本地工具，不调模型）。
 * 会改存档的工具（swap_quest / adjust_plan）在服务端执行：读最新档 → 算 → 写回（同步一拍内完成）。
 */
import { Hono } from 'hono';
import { z } from 'zod';
import type { SaveData } from '@host/core/save/saveData';
import { CHAT_MAX_CHARS, hostMessage, respondChat, type ChatMessage } from '../agent/chatService';
import { chatTools, statusLineOf } from '../agent/chatTools';
import type { AuthUser } from '../auth/accounts';
import { me, type AppEnv, type Deps } from '../http/context';
import { llmFor } from '../llm/gateway';
import { appendChat, listChat } from '../repo/chat';
import { listHistory } from '../repo/history';
import { memoryFor } from '../repo/memory';
import { loadSave, writeSave } from '../repo/saves';
import { stateView } from '../flow/runner';

const Send = z.object({
  text: z
    .string()
    .trim()
    .min(1)
    .refine((s) => [...s].length <= CHAT_MAX_CHARS, `一次最多 ${CHAT_MAX_CHARS} 字。`),
  /** 宿主在哪一页打开的聊天（场景标题） */
  scene: z.string().max(20).default('大厅'),
});

/** 工具读写存档的上下文；改过存档就记下来，回给前端最新状态 */
function toolCtx(deps: Deps, user: AuthUser) {
  const db = deps.dbh.db;
  let changed = false;
  return {
    get changed() {
      return changed;
    },
    ctx: {
      read: (): SaveData => loadSave(db, user.id, deps.now()).save,
      commit: (next: SaveData) => {
        const version = writeSave(db, user.id, next, deps.now());
        changed = true;
        deps.bus.publish(user.id, { type: 'state', version });
      },
      history: () => listHistory(db, user.id),
      now: deps.now,
      tz: user.tz,
    },
  };
}

function currentState(deps: Deps, user: AuthUser) {
  const l = loadSave(deps.dbh.db, user.id, deps.now());
  return stateView({
    save: l.save,
    version: l.version,
    now: deps.now(),
    tz: user.tz,
    source: l.source,
  });
}

export const chatRoutes = new Hono<AppEnv>()
  .get('/', (c) => c.json({ ok: true, messages: listChat(c.var.deps.dbh.db, me(c).id) }))
  .post('/', async (c) => {
    const u = me(c);
    const deps = c.var.deps;
    let raw: unknown;
    try {
      raw = await c.req.json();
    } catch {
      raw = null;
    }
    const b = Send.safeParse(raw);
    if (!b.success)
      return c.json(
        { ok: false, code: 'bad_request', message: b.error.issues[0]?.message ?? '参数不对' },
        400,
      );
    const db = deps.dbh.db;
    const history = listChat(db, u.id);
    const mine = hostMessage(b.data.text, deps.now());
    appendChat(db, u.id, [mine]);
    const llm = llmFor(deps, u);
    const mem = memoryFor(db, u.id, deps.now);
    const t = toolCtx(deps, u);
    const out: ChatMessage[] = await respondChat({
      text: b.data.text,
      history,
      client: llm.text,
      tools: chatTools(t.ctx, mem),
      memory: mem,
      statusLine: statusLineOf(t.ctx.read()),
      scenario: `宿主在「${b.data.scene}」页打开了聊天。`,
      now: deps.now,
    });
    appendChat(db, u.id, out);
    return c.json({
      ok: true,
      messages: [mine, ...out],
      ...(t.changed ? { state: currentState(deps, u) } : {}),
    });
  })
  .post('/status', async (c) => {
    const u = me(c);
    const deps = c.var.deps;
    const t = toolCtx(deps, u);
    const reg = chatTools(t.ctx, memoryFor(deps.dbh.db, u.id, deps.now));
    const oc = await reg.execute('get_status', {});
    const now = deps.now();
    const msgs: ChatMessage[] = [
      hostMessage('查状态', now),
      {
        id: `s${now.toString(36)}`,
        from: 'sys',
        text: oc.message,
        at: now,
        emotion: 'neutral',
        tool: {
          name: 'get_status',
          ok: oc.ok,
          message: oc.message,
          ...(oc.data ? { data: oc.data } : {}),
        },
      },
    ];
    appendChat(deps.dbh.db, u.id, msgs);
    return c.json({ ok: true, messages: msgs });
  });
