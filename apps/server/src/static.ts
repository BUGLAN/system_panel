/**
 * 生产环境托管前端构建产物：
 *  - /assets/*（带哈希）长缓存；index.html / sw.js / manifest 不缓存（新版本才能及时生效）
 *  - 不是 /api、也不是文件的 GET → index.html（SPA，场景由前端状态机驱动）
 */
import { serveStatic } from '@hono/node-server/serve-static';
import type { Hono } from 'hono';
import { existsSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import type { AppEnv } from './http/context';

const NO_CACHE =
  /^\/(index\.html|sw\.js|registerSW\.js|manifest\.webmanifest|workbox-[\w-]+\.js)?$/;

export function mountStatic(app: Hono<AppEnv>, webDist: string): boolean {
  const indexFile = join(webDist, 'index.html');
  if (!existsSync(indexFile)) return false;
  const root = relative(process.cwd(), webDist) || '.';

  app.use('*', async (c, next) => {
    await next();
    if (c.req.path.startsWith('/api/')) return;
    c.header('X-Content-Type-Options', 'nosniff');
    c.header('Referrer-Policy', 'same-origin');
    c.header('X-Frame-Options', 'DENY');
    if (c.req.path.startsWith('/assets/'))
      c.header('Cache-Control', 'public, max-age=31536000, immutable');
    else if (NO_CACHE.test(c.req.path)) c.header('Cache-Control', 'no-cache');
  });
  app.use('*', async (c, next) => {
    if (c.req.path.startsWith('/api/')) return next();
    return serveStatic({ root })(c, next);
  });
  const html = readFileSync(indexFile, 'utf8');
  app.get('*', (c) => {
    if (c.req.path.startsWith('/api/')) return c.notFound();
    c.header('Cache-Control', 'no-cache');
    return c.html(html);
  });
  return true;
}
