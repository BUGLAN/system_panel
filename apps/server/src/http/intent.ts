/**
 * 写意图的统一出口：去重（x-intent-id）+ ApiError → { ok:false, code, message, state? }。
 */
import type { ContentfulStatusCode } from 'hono/utils/http-status';
import { INTENT_HEADER } from '@host/core/api/types';
import { me, type Ctx } from './context';
import { ApiError } from './errors';

export async function intent(
  c: Ctx,
  run: () => Promise<Record<string, unknown>>,
): Promise<Response> {
  const u = me(c);
  const id = c.req.header(INTENT_HEADER)?.slice(0, 64) ?? '';
  const key = id ? `${u.id}:${c.req.path}:${id}` : null;
  const r = await c.var.deps.intents.once(key, async () => {
    try {
      return { status: 200, body: { ok: true, ...(await run()) } };
    } catch (e) {
      if (!(e instanceof ApiError)) throw e;
      return {
        status: e.status,
        body: { ok: false, code: e.code, message: e.message, ...(e.extra ?? {}) },
      };
    }
  });
  return c.json(r.body as Record<string, unknown>, r.status as ContentfulStatusCode);
}

/** 409：前端看到的已经不是最新的了（附最新状态由 runFlow 统一补上） */
export const stale = (message: string) => new ApiError(409, 'stale', message);
/** 422：规则不允许（原因念给宿主听） */
export const rejected = (message: string) => new ApiError(422, 'rejected', message);
