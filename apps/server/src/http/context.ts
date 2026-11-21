/**
 * 应用依赖与 Hono 上下文类型。所有路由从 c.var.deps 拿依赖（测试里换成内存库 / 假时钟 / 假 fetch）。
 */
import type { Context } from 'hono';
import type { Config } from '../config';
import type { DbHandle } from '../db/client';
import type { AuthUser } from '../auth/accounts';
import type { EventBus } from '../events/bus';
import type { UserLocks } from '../flow/locks';
import type { CheckRegistry } from '../evidence/checks';
import type { PlanJobs } from '../jobs/planJobs';
import type { IntentCache } from './intents';
import type { RateLimiter } from './rateLimit';
import { unauthorized } from './errors';

export interface Deps {
  config: Config;
  dbh: DbHandle;
  now: () => number;
  /** 暴击等随机数（服务端取；测试里可固定） */
  rnd: () => number;
  limiter: RateLimiter;
  locks: UserLocks;
  bus: EventBus;
  intents: IntentCache;
  /** 在途的视觉校验 */
  checks: CheckRegistry;
  /**
   * 结算后的跟进：窗口走完续拆 / 收官铸下一条，起一个拆解任务、返回任务 id；
   * 没配拆解模块（第 2 步之前 / 测试）时返回 null。
   */
  followUp: (user: AuthUser, kind: 'window' | 'finale') => { jobId: string } | null;
  /** 拆解任务 */
  jobs: PlanJobs;
  /** 调 LLM 用的 fetch（测试里换成假端点） */
  fetch: (input: string, init?: RequestInit) => Promise<Response>;
  /** LLM 重试间隔（测试里设 0；缺省 800ms） */
  llmRetryDelayMs?: number;
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
