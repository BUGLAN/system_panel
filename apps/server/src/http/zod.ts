/**
 * 入参校验：zod 解析请求体，不合格 → 400，message 取第一条问题。
 */
import type { z } from 'zod';
import type { Ctx } from './context';
import { badRequest } from './errors';

export async function body<T extends z.ZodType>(c: Ctx, schema: T): Promise<z.infer<T>> {
  let raw: unknown;
  try {
    raw = await c.req.json();
  } catch {
    throw badRequest('请求体不是 JSON。');
  }
  const r = schema.safeParse(raw);
  if (!r.success) {
    const first = r.error.issues[0];
    const path = first?.path.join('.') ?? '';
    throw badRequest(`参数不对${path ? `（${path}）` : ''}：${first?.message ?? '格式不合'}`);
  }
  return r.data;
}
