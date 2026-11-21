/**
 * 实时通道（SSE，每个已登录页面一条）：存档版本变了 / 拆解进度 / 视觉校验结论，外加 25 秒心跳。
 * 页面切后台由前端断开，回前台重连并拉一次状态补齐。
 */
import { Hono } from 'hono';
import { streamSSE } from 'hono/streaming';
import { me, type AppEnv } from '../http/context';
import { saveVersion } from '../repo/saves';

export const HEARTBEAT_MS = 25_000;

export const streamRoute = new Hono<AppEnv>().get('/', (c) => {
  const u = me(c);
  const { bus, dbh } = c.var.deps;
  return streamSSE(c, async (stream) => {
    const unsub = bus.subscribe(u.id, (e) => {
      void stream.writeSSE({ event: e.type, data: JSON.stringify(e) }).catch(() => undefined);
    });
    stream.onAbort(unsub);
    await stream.writeSSE({
      event: 'hello',
      data: JSON.stringify({ version: saveVersion(dbh.db, u.id) }),
    });
    while (!stream.aborted && !stream.closed) {
      await stream.sleep(HEARTBEAT_MS);
      if (stream.aborted || stream.closed) break;
      await stream.writeSSE({ event: 'ping', data: '' }).catch(() => undefined);
    }
    unsub();
  });
});
