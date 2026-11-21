/**
 * 健康检查（不需登录）：库能查就是好的。给 Docker HEALTHCHECK / 反代探活用。
 */
import { Hono } from 'hono';
import type { AppEnv } from '../http/context';

export const healthRoute = new Hono<AppEnv>().get('/', (c) => {
  let db = 'ok';
  try {
    c.var.deps.dbh.sqlite.prepare('select 1').get();
  } catch {
    db = 'down';
  }
  return c.json({ ok: db === 'ok', db }, db === 'ok' ? 200 : 503);
});
