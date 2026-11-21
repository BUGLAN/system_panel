/**
 * 服务端权威的流程执行：锁内 读档 → 换日 → 到点检查 → 跑意图 → 改了才写回 + 追加流水。
 * 「现在几点」「随机数」都以服务器为准；时区取账号的。
 */
import { checkTimeout } from '@host/core/flow/settle';
import { QuestFlow } from '@host/core/flow/questFlow';
import { saveToJson, type SaveData } from '@host/core/save/saveData';
import type { FlowEvent, SaveSource, StateView } from '@host/core/api/types';
import type { AuthUser } from '../auth/accounts';
import type { Deps } from '../http/context';
import { ApiError } from '../http/errors';
import { appendHistory } from '../repo/history';
import { loadSave, touchSeen, writeSave } from '../repo/saves';

export interface FlowRun<T> {
  value: T;
  state: StateView;
  events: FlowEvent[];
  /** 这次之前「最近一次来过」的时刻（开机问候用） */
  prevSeen: number | null;
}

export function stateView(o: {
  save: SaveData;
  version: number;
  now: number;
  tz: string;
  source: SaveSource;
}): StateView {
  return {
    version: o.version,
    serverNow: o.now,
    tz: o.tz,
    source: o.source,
    save: saveToJson(o.save),
  };
}

/**
 * 时间驱动的事：换日（同一天幂等）+ 计时单到点（护盾碎 → 顺延后仍过点 → 判负，最多两轮）。
 * 与旧版「杀进程重开后第一拍」的行为一致。
 */
export function housekeep(f: QuestFlow, now: number): FlowEvent[] {
  const out: FlowEvent[] = [];
  if (f.rollDay(now)) out.push({ kind: 'rollDay' });
  for (let i = 0; i < 2; i++) {
    const r = checkTimeout(f, now);
    if (r.kind === 'none') break;
    if (r.kind === 'shield') out.push({ kind: 'shield', extendMin: r.extendMin });
    else out.push({ kind: 'timeout', outcome: r.outcome });
  }
  return out;
}

/** 在锁内跑一段流程；fn 抛 ApiError 时它做的改动作废（但换日 / 到点的结论照样落盘） */
export async function runFlow<T>(
  deps: Deps,
  user: AuthUser,
  fn: (f: QuestFlow, now: number) => T,
  o: { touch?: boolean } = {},
): Promise<FlowRun<T>> {
  const out = await deps.locks.run(user.id, () => {
    const db = deps.dbh.db;
    const now = deps.now();
    // 读档在事务外：坏档的留底 / 用备份恢复要落盘，不能被后面的回滚带走
    const loaded = loadSave(db, user.id, now);
    return db.transaction(() => {
      const opts = { rnd: deps.rnd, tz: user.tz };
      const base = new QuestFlow(loaded.save, opts);
      const events = housekeep(base, now);
      // 意图跑在副本上：被拒时副本整个丢掉，只留换日 / 到点的结果
      const g = new QuestFlow(base.save, opts);
      let value = undefined as T;
      let pending: ApiError | null = null;
      try {
        value = fn(g, now);
      } catch (e) {
        if (!(e instanceof ApiError)) throw e;
        pending = e;
      }
      const final = pending ? base : g;
      const changed = base.changed || (!pending && g.changed);
      const entries = [...base.history, ...(pending ? [] : g.history)];
      let version = loaded.version;
      if (changed) {
        version = writeSave(db, user.id, final.save, now);
        appendHistory(db, user.id, entries);
      }
      const prevSeen = loaded.lastSeenAt;
      if (o.touch !== false) touchSeen(db, user.id, now);
      const state = stateView({
        save: final.save,
        version,
        now,
        tz: user.tz,
        source: loaded.source,
      });
      return { value, state, events, prevSeen, pending, bumped: version !== loaded.version };
    });
  });
  if (out.bumped) deps.bus.publish(user.id, { type: 'state', version: out.state.version });
  if (out.pending) {
    // 拒绝也带上最新状态（前端据此刷新）和顺带发生的事
    const p = out.pending;
    throw new ApiError(p.status, p.code, p.message, {
      ...(p.extra ?? {}),
      state: out.state,
      events: out.events,
    });
  }
  return { value: out.value, state: out.state, events: out.events, prevSeen: out.prevSeen };
}
