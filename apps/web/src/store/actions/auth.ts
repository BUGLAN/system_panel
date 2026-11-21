/**
 * 账号：登录 / 注册（邀请码）/ 退出 / 改密码。
 * 注册时自动带上浏览器时区（换日、连胜、补签按它算；之后只能管理员改）。
 */
import type { MeView } from '@host/core/api/types';
import { freshSave } from '@host/core/save/saveData';
import { api } from '../api';
import { forgetUser } from '../cache';
import { now, resetHistoryCache, syncStore } from '../game';
import { gameStore } from '../gameStore';
import { closeStream } from '../stream';
import { setUi, toast } from '../uiStore';
import { afterLogin } from './boot';
import { resetBind } from './bind';
import { clearChatState } from './chat';
import { go } from './nav';
import { cancelPlanJob } from './planJob';

export function browserTz(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || 'Asia/Shanghai';
  } catch {
    return 'Asia/Shanghai';
  }
}

export async function login(username: string, password: string): Promise<void> {
  const r = await api<{ me: MeView }>('POST', '/api/auth/login', { username, password });
  await afterLogin(r.me);
}

export async function register(username: string, password: string, invite: string): Promise<void> {
  const r = await api<{ me: MeView }>('POST', '/api/auth/register', {
    username,
    password,
    invite,
    tz: browserTz(),
  });
  await afterLogin(r.me);
}

export async function logout(): Promise<void> {
  const me = syncStore.getState().me;
  try {
    await api('POST', '/api/auth/logout');
  } catch {
    // 断网也照样在本机退出
  }
  if (me) await forgetUser(me.username);
  closeStream();
  cancelPlanJob();
  syncStore.setState({ me: null, version: -1, tz: undefined, source: null });
  gameStore.getState().hydrate(freshSave(now()), 'none');
  resetHistoryCache();
  clearChatState();
  resetBind();
  setUi({ sheet: null, show: null, briefing: null, chatOpen: false });
  await go('auth', { noHist: true });
  toast('已退出。这台设备上的缓存清掉了。');
}

export async function changePassword(old: string, next: string): Promise<void> {
  await api('POST', '/api/auth/password', { old, next });
  toast('密码改好了。其他设备需要重新登录。', 'ok');
}
