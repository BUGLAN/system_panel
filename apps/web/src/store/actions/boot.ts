/**
 * 开机：读偏好 → 我是谁（登录态）→ 拉状态（服务端顺带换日 / 到点判定）→ 等宿主点「唤醒」→ 决定进哪一页。
 *  - 没登录 → 登录页
 *  - 没同意告知页 → 告知页
 *  - 没主线也没记着的目标 → 绑定仪式
 *  - 有执行中的单 → 直接回执行页（计时按服务器的 startAt 推导）
 *  - 其余 → 大厅，她按离开时长说一句
 * 断网：用本机缓存的最后一份状态只读进大厅；写操作提示「需要联网」。
 */
import type { MeView } from '@host/core/api/types';
import { LINES, fillLine } from '@host/core/data/lines';
import { awayLine } from '@host/core/time/away';
import { ApiError, api, setApiHooks } from '../api';
import { cachedMe, cachedState } from '../cache';
import { applyState, game, historyAll, now, refreshState, syncStore } from '../game';
import { hasConsent, loadServices, setMe } from '../services';
import { closeStream, openStream } from '../stream';
import { sayHome, setUi, toast, uiStore, type Scene } from '../uiStore';
import { resumeRunningJob } from './plan';
import { go } from './nav';
import { startSession } from './session';

let ready: Promise<void> | null = null;
let prevSeen: number | null = null;

/** 登录之后（或开机已登录）：拉状态与流水 */
export async function loadAccount(m: MeView): Promise<void> {
  setMe(m);
  const r = await refreshState(true);
  if (r) prevSeen = r.prevSeen;
  else {
    const cached = await cachedState(m.username);
    if (cached) applyState(cached, { force: true, fromCache: true });
  }
  void historyAll();
  openStream();
}

export function bootData(): Promise<void> {
  ready ??= (async () => {
    await loadServices();
    let m: MeView | null = null;
    try {
      m = (await api<{ me: MeView }>('GET', '/api/me')).me;
    } catch (e) {
      if (e instanceof ApiError && e.offline) m = await cachedMe();
    }
    if (m) await loadAccount(m);
    startSession();
  })();
  return ready;
}

/** 开机日志（{host} 换成宿主名 + 等级） */
export function bootLines(): string[] {
  const h = game().host;
  return LINES.bootLog.map((l) => fillLine(l, { host: `${h.name} · LV${h.lv}` }));
}

export function wakeTarget(): Scene {
  const g = game();
  if (!syncStore.getState().me) return 'auth';
  if (!hasConsent()) return 'consent';
  if (g.goal.plan.length === 0 && !g.pendingGoal) return 'onboard';
  if (g.active) return 'exec';
  return 'home';
}

/** 唤醒之后的第一句 */
export function greet(): void {
  const g = game();
  const s = syncStore.getState();
  if (s.source === 'backup')
    setTimeout(() => toast('存档主档坏了，已经用上一份备份恢复。', 'err'), 900);
  if (!s.online) setTimeout(() => toast('现在没联网：只能看，不能改。', 'err'), 900);
  if (g.active) {
    setTimeout(() => toast('欢迎回来。你还有一单在计时。', 'ok'), 900);
    return;
  }
  const away = prevSeen === null ? 0 : now() - prevSeen;
  sayHome(awayLine(away) ?? LINES.back10m);
}

export function enterAfterBoot(): void {
  const target = wakeTarget();
  setUi({ scene: target, hist: [] });
  if (target === 'home' || target === 'exec') greet();
  if (target !== 'auth') void continueRunningJob();
}

/** 刷新前有一件拆解还在跑：接上加载卡；拆好了且还停在绑定页就进大厅 */
async function continueRunningJob(): Promise<void> {
  const r = await resumeRunningJob();
  if (r === 'done' && uiStore.getState().scene === 'onboard' && game().goal.plan.length > 0)
    await go('home');
}

/** 登录 / 注册成功：进该去的那一页 */
export async function afterLogin(m: MeView): Promise<void> {
  await loadAccount(m);
  const target = wakeTarget();
  await go(target, { noHist: true });
  if (target === 'home' || target === 'exec') greet();
}

/** 会话失效（别处改了密码 / 被停用）：回登录页 */
setApiHooks({
  onUnauthorized: () => {
    if (!syncStore.getState().me) return;
    syncStore.setState({ me: null });
    closeStream();
    const ui = uiStore.getState();
    if (ui.scene !== 'boot' && ui.scene !== 'auth') {
      setUi({ sheet: null, show: null, briefing: null, chatOpen: false, planJob: null });
      void go('auth', { noHist: true });
      toast('登录过期了，重新登录一下。', 'err');
    }
  },
});
