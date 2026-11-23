/**
 * 本机缓存：偏好 + 离线只读缓存（按用户名分键）。所有读写都吞异常——隐私模式 / 存储被清时照常能跑。
 */
import type { MeView, StateView } from '@host/core/api/types';
import type { HistoryEntry } from '@host/core/flow/types';
import { isObj } from '@host/core/save/json';
import { appDb, type HostDb } from './db';

export interface Prefs {
  /** 看过「添加到主屏幕」引导 */
  installHintSeen: boolean;
}

export const defaultPrefs = (): Prefs => ({ installHintSeen: false });

const K = {
  prefs: 'prefs',
  lastUser: 'lastUser',
  me: (u: string) => `me:${u}`,
  state: (u: string) => `state:${u}`,
  history: (u: string) => `history:${u}`,
};

async function get(db: HostDb, key: string): Promise<unknown> {
  try {
    return (await db.kv.get(key))?.value;
  } catch {
    return undefined;
  }
}

async function put(db: HostDb, key: string, value: unknown): Promise<void> {
  try {
    await db.kv.put({ key, value });
  } catch {
    // 存不了就算了：缓存只是锦上添花
  }
}

export async function loadPrefs(db: HostDb = appDb()): Promise<Prefs> {
  const v = await get(db, K.prefs);
  const d = defaultPrefs();
  if (!isObj(v)) return d;
  return {
    installHintSeen:
      typeof v['installHintSeen'] === 'boolean' ? v['installHintSeen'] : d.installHintSeen,
  };
}

export const savePrefs = (p: Prefs, db: HostDb = appDb()) => put(db, K.prefs, { ...p });

/** 最近一次登录的账号（断网开机时用它的缓存） */
export async function cachedMe(db: HostDb = appDb()): Promise<MeView | null> {
  const u = await get(db, K.lastUser);
  if (typeof u !== 'string') return null;
  const me = await get(db, K.me(u));
  return isObj(me) && me['username'] === u ? (me as unknown as MeView) : null;
}

export async function rememberMe(me: MeView, db: HostDb = appDb()): Promise<void> {
  await put(db, K.lastUser, me.username);
  await put(db, K.me(me.username), me);
}

export async function cachedState(user: string, db: HostDb = appDb()): Promise<StateView | null> {
  const v = await get(db, K.state(user));
  return isObj(v) && isObj(v['save']) && typeof v['version'] === 'number'
    ? (v as unknown as StateView)
    : null;
}

export const cacheState = (user: string, s: StateView, db: HostDb = appDb()) =>
  put(db, K.state(user), s);

export async function cachedHistory(user: string, db: HostDb = appDb()): Promise<HistoryEntry[]> {
  const v = await get(db, K.history(user));
  return Array.isArray(v) ? (v as HistoryEntry[]) : [];
}

export const cacheHistory = (user: string, h: HistoryEntry[], db: HostDb = appDb()) =>
  put(db, K.history(user), h);

/** 退出登录：清掉这个用户在本机的缓存（偏好留着） */
export async function forgetUser(user: string, db: HostDb = appDb()): Promise<void> {
  try {
    await db.kv.bulkDelete([K.me(user), K.state(user), K.history(user), K.lastUser]);
  } catch {
    // 同上
  }
}
