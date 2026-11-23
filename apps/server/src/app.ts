/**
 * Hono 应用装配：依赖注入 → 错误格式 → 请求日志 → 写接口 Origin 校验 → 会话 → 路由。
 * 生产环境另由 main.ts 托管前端静态文件（见 static.ts）。
 */
import { Hono } from 'hono';
import { sessionUser } from './auth/accounts';
import { ApiError, forbidden, notFound, unauthorized } from './http/errors';
import type { AppEnv, Deps } from './http/context';
import { errInfo, log } from './log';
import { authRoutes, meRoute, readSessionCookie } from './routes/auth';
import { dataRoutes } from './routes/data';
import { evidenceRoutes } from './routes/evidence';
import { flowRoutes } from './routes/flow';
import { healthRoute } from './routes/health';
import { consentRoutes, llmRoutes } from './routes/llm';
import { planRoutes } from './routes/plan';
import { streamRoute } from './routes/stream';

/** 不需要登录的接口 */
const PUBLIC = new Set([
  '/api/health',
  '/api/auth/login',
  '/api/auth/register',
  '/api/auth/logout',
]);

const SAFE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);

export function createApp(deps: Deps): Hono<AppEnv> {
  const app = new Hono<AppEnv>();

  app.onError((e, c) => {
    if (e instanceof ApiError) {
      return c.json({ ok: false, code: e.code, message: e.message, ...(e.extra ?? {}) }, e.status);
    }
    log.error('未处理的异常', { path: c.req.path, ...errInfo(e) });
    return c.json({ ok: false, code: 'internal', message: '服务器出了点问题，稍后再试。' }, 500);
  });
  app.notFound((c) => c.json({ ok: false, code: 'not_found', message: '找不到。' }, 404));

  app.use('*', async (c, next) => {
    c.set('deps', deps);
    c.set('user', null);
    c.set('token', '');
    const t0 = performance.now();
    await next();
    if (c.req.path.startsWith('/api/') && deps.config.env !== 'test') {
      log.info('req', {
        m: c.req.method,
        p: c.req.path,
        s: c.res.status,
        ms: Math.round(performance.now() - t0),
        u: c.get('user')?.id ?? null,
      });
    }
  });

  app.use('/api/*', async (c, next) => {
    // 写接口：Origin 必须是本站（SameSite=Lax 之外再挡一层 CSRF）
    if (!SAFE_METHODS.has(c.req.method)) {
      const origin = c.req.header('origin');
      const site = c.req.header('sec-fetch-site');
      const ok = origin ? origin === deps.config.origin : site === 'same-origin';
      if (!ok) throw forbidden('请求来源不对。', 'bad_origin');
    }
    const token = readSessionCookie(c);
    if (token) {
      const u = sessionUser(deps.dbh.db, token, deps.now());
      if (u) {
        c.set('user', u);
        c.set('token', token);
      }
    }
    if (!c.get('user') && !PUBLIC.has(c.req.path)) throw unauthorized();
    await next();
    // API 响应默认不缓存（Service Worker 与浏览器都不许存）；证据图自己声明 private 缓存
    if (!c.res.headers.get('Cache-Control')) c.header('Cache-Control', 'no-store');
  });

  app.route('/api/health', healthRoute);
  app.route('/api/auth', authRoutes);
  app.route('/api/me', meRoute);
  app.route('/api', flowRoutes);
  app.route('/api/llm', llmRoutes);
  app.route('/api/consent', consentRoutes);
  app.route('/api/plan', planRoutes);
  app.route('/api/stream', streamRoute);
  app.route('/api/evidence', evidenceRoutes);
  app.route('/api/data', dataRoutes);

  app.all('/api/*', () => {
    throw notFound();
  });

  return app;
}
