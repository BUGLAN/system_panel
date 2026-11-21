import { afterEach, describe, expect, it, vi } from 'vitest';
import { saveToJson } from '@host/core/save/saveData';
import { boundSave } from '@host/core/testing/helpers';
import type { StateView } from '@host/core/api/types';
import { ApiError, api, setApiHooks, setFetch } from '../../src/store/api';
import { applyState, flowOf, game, intent, now, syncStore } from '../../src/store/game';
import {
  cacheState,
  cachedState,
  defaultPrefs,
  forgetUser,
  loadPrefs,
  rememberMe,
  savePrefs,
} from '../../src/store/cache';
import { HostDb } from '../../src/store/db';

const view = (version: number, serverNow = Date.now()): StateView => ({
  version,
  serverNow,
  tz: 'Asia/Shanghai',
  source: 'primary',
  save: saveToJson(boundSave()),
});

const reply = (status: number, body: unknown) =>
  vi.fn(async () => new Response(JSON.stringify(body), { status }));

afterEach(() => {
  setFetch((i, init) => fetch(i, init));
  syncStore.setState({ version: -1, skew: 0, me: null, online: true });
});

describe('API 客户端', () => {
  it('写请求带 x-intent-id、GET 不带；同源带 Cookie', async () => {
    const f = reply(200, { ok: true });
    setFetch(f);
    await api('GET', '/api/me');
    await api('POST', '/api/flow/tick', {});
    const [, g] = f.mock.calls[0] as unknown as [string, RequestInit];
    const [, p] = f.mock.calls[1] as unknown as [string, RequestInit];
    expect((g.headers as Record<string, string>)['x-intent-id']).toBeUndefined();
    expect((p.headers as Record<string, string>)['x-intent-id']).toMatch(/\S+/);
    expect(p.credentials).toBe('same-origin');
  });

  it('断网 → offline（念「需要联网」）；联网状态跟着变', async () => {
    setFetch(async () => {
      throw new TypeError('Failed to fetch');
    });
    const e = await api('GET', '/api/state').catch((x: unknown) => x);
    expect(e).toBeInstanceOf(ApiError);
    expect((e as ApiError).offline).toBe(true);
    expect((e as ApiError).message).toMatch(/需要联网/);
    expect(syncStore.getState().online).toBe(false);
  });

  it('409 附带的最新状态先落到本地，再抛出 stale', async () => {
    setFetch(
      reply(409, { ok: false, code: 'stale', message: '这一单已经交过了。', state: view(7) }),
    );
    const r = await intent('/api/flow/submit', { serial: 41 });
    expect(r.ok).toBe(false);
    if (!r.ok)
      expect(r.err).toMatchObject({ status: 409, code: 'stale', message: '这一单已经交过了。' });
    expect(syncStore.getState().version).toBe(7);
    expect(game().goal.plan.length).toBeGreaterThan(0);
  });

  it('401 → 回登录页的钩子', async () => {
    const hit = vi.fn();
    setApiHooks({ onUnauthorized: hit });
    setFetch(reply(401, { ok: false, code: 'unauthorized', message: '还没登录' }));
    await api('GET', '/api/me').catch(() => undefined);
    expect(hit).toHaveBeenCalledOnce();
    setApiHooks({ onUnauthorized: () => undefined });
  });

  it('反代回 HTML 错误页（502）→ 按连不上处理', async () => {
    setFetch(async () => new Response('<html>Bad Gateway</html>', { status: 502 }));
    const e = (await api('GET', '/api/state').catch((x: unknown) => x)) as ApiError;
    expect(e.offline).toBe(true);
  });
});

describe('存档镜像', () => {
  it('比本地旧的回包丢掉（乱序）；按服务器时间校时；只读推导用账号时区', () => {
    applyState(view(5, Date.now() + 60_000));
    expect(syncStore.getState().version).toBe(5);
    expect(now() - Date.now()).toBeGreaterThan(59_000);
    const before = game();
    applyState(view(4));
    expect(game()).toBe(before);
    expect(flowOf().tz).toBe('Asia/Shanghai');
  });
});

describe('本机缓存', () => {
  it('偏好：默认值、越界钳制', async () => {
    const db = new HostDb(`t-${Math.random()}`);
    expect(await loadPrefs(db)).toEqual(defaultPrefs());
    await savePrefs({ muted: true, volume: 3, installHintSeen: true }, db);
    expect(await loadPrefs(db)).toEqual({ muted: true, volume: 1, installHintSeen: true });
  });

  it('离线缓存按用户分开；退出登录清掉自己的', async () => {
    const db = new HostDb(`t-${Math.random()}`);
    await rememberMe({ username: 'alice', role: 'user', tz: 'UTC', consent: null }, db);
    await cacheState('alice', view(3), db);
    await cacheState('bob', view(9), db);
    expect((await cachedState('alice', db))?.version).toBe(3);
    await forgetUser('alice', db);
    expect(await cachedState('alice', db)).toBeNull();
    expect((await cachedState('bob', db))?.version).toBe(9);
  });
});
