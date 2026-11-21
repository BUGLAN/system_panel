/**
 * 交单（docs/05 第 3.2 节）：
 *   确认是这一单 → 不持锁等在途校验（≤20 秒，等不到的按未校验）→ 重新拿锁：没证据不收 → 封存 → 结算 → 落盘
 *   → 窗口走完 / 收官：起续拆 / 收官任务，把任务 id 带回（前端先等任务、再演结算，与 G4.1 一致）
 */
import { settle } from '@host/core/flow/settle';
import type { QuestFlow } from '@host/core/flow/questFlow';
import type { AuthUser } from '../auth/accounts';
import type { Deps } from '../http/context';
import { rejected, stale } from '../http/intent';
import { runFlow } from './runner';

/** 执行中那一单必须就是前端以为的那一单 */
export function activeIs(f: QuestFlow, serial: number, gone: string): void {
  if (!f.active || f.active.task.serial !== serial) throw stale(gone);
}

export async function submitQuest(
  deps: Deps,
  user: AuthUser,
  serial: number,
): Promise<Record<string, unknown>> {
  const pre = await runFlow(deps, user, (f) => {
    activeIs(f, serial, '这一单已经交过了。');
    return f.active!.evidence.map((e) => e.id);
  });
  await deps.checks.waitFor(user.id, pre.value);
  const r = await runFlow(deps, user, (f, now) => {
    activeIs(f, serial, '这一单已经交过了。');
    if (!f.active!.evidence.length) throw rejected('没有证据，她不收。先上传截图。');
    return settle(f, { now });
  });
  const result = r.value;
  const followUp =
    result.windowEnd || result.finale
      ? deps.followUp(user, result.windowEnd ? 'window' : 'finale')
      : null;
  return { state: r.state, events: [...pre.events, ...r.events], result, followUp };
}
