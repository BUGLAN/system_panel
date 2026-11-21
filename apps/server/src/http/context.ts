/**
 * 应用依赖与 Hono 上下文类型。所有路由从 c.var.deps 拿依赖（测试里换成内存库 / 假时钟 / 假 fetch）。
 */
import type { Context } from 'hono';
import type { Config } from '../config';
import type { DbHandle } from '../db/client';
import type { AuthUser } from '../auth/accounts';
import type { RateLimiter } from './rateLimit';
import { unauthorized } from './errors';

export interface Deps {
  config: Config;
  dbh: DbHandle;
  now: () => number;
  limiter: RateLimiter;
}

export interface AppEnv {
  Variables: {
    deps: Deps;
    user: AuthUser | null;
    /** 当前会话 token（退出 / 改密码时用） */
    token: string;
  };
}

export type Ctx = Context<AppEnv>;

/** 必须登录的路由里取当前用户 */
export function me(c: Ctx): AuthUser {
  const u = c.get('user');
  if (!u) throw unauthorized();
  return u;
}

/** 客户端 IP：只有 TRUST_PROXY 时才信 X-Forwarded-For */
export function clientIp(c: Ctx, fallback: string): string {
  if (c.var.deps.config.trustProxy) {
    const xff = c.req.header('x-forwarded-for');
    const first = xff?.split(',')[0]?.trim();
    if (first) return first;
  }
  return fallback;
}
