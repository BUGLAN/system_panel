/**
 * 拆解任务（替代前端的 withPlanJob）：同一用户同时只跑一件；进度、完成、失败都推 SSE。
 *  - 等 LLM 时不持锁；拆好后在锁内重读最新存档、核对前提（还是那条目标 / 还没有主线…）再落库，
 *    前提不成立 → 这次结果作废（= 旧版「迟到回包按 token 丢弃」）
 *  - 失败分类与失败卡沿用 PlanFailure（noKey / network / timeout / httpError / quota / 拒拆…）
 *  - 任务状态只在内存：服务重启 = 在跑的任务丢了，前端按「网络断了」失败卡处理、可重试
 */
import type { PlanJobKind, PlanJobView, PlanProgress } from '@host/core/api/types';
import { goalWindowExhausted, goalId, type Goal } from '@host/core/model/goal';
import { PlanFailure } from '@host/core/goal/planFailure';
import type { AuthUser } from '../auth/accounts';
import { randomId } from '../auth/tokens';
import type { Deps } from '../http/context';
import { errInfo, log } from '../log';
import { landFirstGoal } from './land';
import {
  asPlanFailure,
  buildGoalWithAgent,
  extendGoalWithAgent,
  mintNextGoal,
} from '../agent/goalBuilder';
import { statusLineOf } from '../agent/chatTools';
import type { GoalMatch } from '../agent/mainlineTools';
import { llmFor } from '../llm/gateway';
import { runFlow } from '../flow/runner';
import { loadSave } from '../repo/saves';
import { memoryFor } from '../repo/memory';

export interface JobInput {
  /** bind / swap：目标原文 */
  text?: string;
  /** bind：访谈答案 */
  answers?: Record<string, string>;
}

/** 完成的任务留 10 分钟（刷新页面 / 另一台设备还能读到结论） */
const KEEP_MS = 10 * 60_000;

/** 等待期间存档变了，这次拆出来的作废 */
const discarded = () => new PlanFailure('badResponse', '等待期间目标变了，这次拆出来的作废了。');

interface Job extends PlanJobView {
  userId: string;
}

export class PlanJobs {
  private readonly jobs = new Map<string, Job>();
  /** 绑定仪式第一步匹配出的类目：拆第一段时直接用（同一句目标），不再匹配一次 */
  private readonly matches = new Map<string, { text: string; match: GoalMatch; at: number }>();

  constructor(private readonly deps: Deps) {}

  rememberMatch(userId: string, text: string, match: GoalMatch): void {
    this.matches.set(userId, { text, match, at: this.deps.now() });
  }

  private matchFor(userId: string, text: string): GoalMatch | undefined {
    const m = this.matches.get(userId);
    return m && m.text === text && this.deps.now() - m.at < 3_600_000 ? m.match : undefined;
  }

  private view(j: Job): PlanJobView {
    const { userId: _u, ...v } = j;
    return v;
  }

  private sweep(): void {
    const t = this.deps.now();
    for (const [id, j] of this.jobs)
      if (j.finishedAt !== null && t - j.finishedAt > KEEP_MS) this.jobs.delete(id);
  }

  running(userId: string): PlanJobView | null {
    for (const j of this.jobs.values())
      if (j.userId === userId && j.status === 'running') return this.view(j);
    return null;
  }

  /** 正在跑的，或者最近一件（刷新页面后接上） */
  current(userId: string): PlanJobView | null {
    this.sweep();
    let last: Job | null = null;
    for (const j of this.jobs.values()) {
      if (j.userId !== userId) continue;
      if (j.status === 'running') return this.view(j);
      if (!last || j.startedAt > last.startedAt) last = j;
    }
    return last ? this.view(last) : null;
  }

  /** 按 id 取；不是你的 = 没有 */
  get(userId: string, id: string): PlanJobView | null {
    const j = this.jobs.get(id);
    return j && j.userId === userId ? this.view(j) : null;
  }

  /** 等它结束（测试 / 内部用） */
  readonly done = new Map<string, Promise<void>>();

  /** 起一件；已经有一件在跑就返回那一件（不收第二次） */
  start(user: AuthUser, kind: PlanJobKind, input: JobInput = {}): PlanJobView {
    const busy = this.running(user.id);
    if (busy) return busy;
    this.sweep();
    const j: Job = {
      id: randomId(),
      userId: user.id,
      kind,
      status: 'running',
      progress: { stage: kind === 'window' || kind === 'finale' || kind === 'resume' ? 1 : 0 },
      failure: null,
      state: null,
      startedAt: this.deps.now(),
      finishedAt: null,
    };
    this.jobs.set(j.id, j);
    this.emit(j);
    const p = this.work(user, j, input)
      .then((state) => {
        j.status = 'done';
        j.state = state;
      })
      .catch((e: unknown) => {
        const f = asPlanFailure(e);
        if (!(e instanceof PlanFailure)) log.error('拆解任务意外异常', { kind, ...errInfo(e) });
        j.status = 'failed';
        j.failure = { code: f.code, detail: f.detail };
      })
      .finally(() => {
        j.finishedAt = this.deps.now();
        this.emit(j);
        this.done.delete(j.id);
      });
    this.done.set(j.id, p);
    return this.view(j);
  }

  private emit(j: Job): void {
    this.deps.bus.publish(j.userId, { type: 'job', job: this.view(j) });
  }

  private async work(user: AuthUser, j: Job, input: JobInput) {
    const deps = this.deps;
    const llm = llmFor(deps, user);
    const mem = memoryFor(deps.dbh.db, user.id, deps.now);
    const digest = (q: string) => mem.digest(q);
    const onProgress = (p: PlanProgress) => {
      j.progress = p;
      this.emit(j);
    };
    const snap = loadSave(deps.dbh.db, user.id, deps.now()).save;

    switch (j.kind) {
      case 'bind':
      case 'retry': {
        const text = j.kind === 'bind' ? (input.text ?? '').trim() : snap.pendingGoal;
        if (!text) throw new PlanFailure('badGoal', '没有可拆的目标。');
        const match = j.kind === 'bind' ? this.matchFor(user.id, text) : undefined;
        const { goal } = await buildGoalWithAgent({
          client: llm.text,
          text,
          at: deps.now(),
          firstGoal: true,
          ...(input.answers ? { answers: input.answers } : {}),
          ...(match ? { match } : {}),
          ...(j.kind === 'retry' ? { digest } : {}),
          onProgress,
        });
        return landFirstGoal(deps, user, goal, j.kind === 'bind' ? (input.answers ?? {}) : {}, mem);
      }
      case 'swap': {
        const text = (input.text ?? '').trim();
        const prevAt = snap.goal.at;
        const { goal } = await buildGoalWithAgent({
          client: llm.text,
          text,
          at: deps.now(),
          statusLine: statusLineOf(snap),
          digest,
          onProgress,
        });
        const r = await runFlow(deps, user, (f) => {
          if (f.goal.at !== prevAt || f.goal.plan.length === 0) throw discarded();
          f.newGoal(goal);
        });
        return r.state;
      }
      case 'resume':
      case 'window':
      case 'finale': {
        const g0 = snap.goal;
        if (g0.plan.length === 0) throw new PlanFailure('badGoal', '还没有主线，没得续拆。');
        const kind = j.kind === 'resume' ? (goalWindowExhausted(g0) ? 'window' : 'finale') : j.kind;
        const statusLine = statusLineOf(snap);
        let next: Goal;
        if (kind === 'window') {
          next = await extendGoalWithAgent({
            client: llm.text,
            goal: g0,
            now: deps.now(),
            statusLine,
            digest,
            onProgress,
          });
        } else {
          next = await mintNextGoal({ client: llm.text, prev: g0, statusLine, digest, onProgress });
        }
        const r = await runFlow(deps, user, (f) => {
          if (goalId(f.goal) !== goalId(g0) || f.goal.plan.length !== g0.plan.length)
            throw discarded();
          if (kind === 'window') f.applyNextWindow(next);
          else f.applyNextGoal(next);
        });
        return r.state;
      }
    }
  }
}
