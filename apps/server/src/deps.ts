/**
 * 依赖装配（main 与测试共用）。
 */
import type { Config } from './config';
import type { DbHandle } from './db/client';
import { CheckRegistry } from './evidence/checks';
import { EventBus } from './events/bus';
import { UserLocks } from './flow/locks';
import type { Deps } from './http/context';
import { IntentCache } from './http/intents';
import { PlanJobs } from './jobs/planJobs';
import { RateLimiter } from './http/rateLimit';

export function makeDeps(config: Config, dbh: DbHandle, over: Partial<Deps> = {}): Deps {
  const now = over.now ?? Date.now;
  const deps: Deps = {
    config,
    dbh,
    now,
    limiter: new RateLimiter(now),
    locks: new UserLocks(),
    bus: new EventBus(),
    intents: new IntentCache(now),
    checks: new CheckRegistry(),
    followUp: () => null,
    fetch: (i, init) => fetch(i, init),
    jobs: null as unknown as PlanJobs,
    ...over,
  };
  deps.jobs = over.jobs ?? new PlanJobs(deps);
  // 交单后窗口走完 / 收官：起续拆 / 收官任务
  if (!over.followUp) deps.followUp = (user, kind) => ({ jobId: deps.jobs.start(user, kind).id });
  return deps;
}
