/**
 * 接口测试脚手架：内存 SQLite + app.request()，带一个按用户分开的 Cookie 罐子。
 */
import { createApp } from '../src/app';
import { createInvite, createUser } from '../src/auth/accounts';
import { testConfig, type Config } from '../src/config';
import { openDb } from '../src/db/client';
import { makeDeps } from '../src/deps';
import type { Deps } from '../src/http/context';
import { setLogQuiet } from '../src/log';
import { loadSave, writeSave } from '../src/repo/saves';
import type { SaveData } from '@host/core/save/saveData';

setLogQuiet(true);

export const ORIGIN = 'http://localhost:5173';
export const T0 = Date.UTC(2026, 10, 21, 2, 0, 0); // 北京时间 2026-11-21 10:00

export interface TestServer {
  deps: Deps;
  clock: { t: number };
  app: ReturnType<typeof createApp>;
  client(): Client;
  /** 直接建一个已登录的用户 */
  login(username?: string, tz?: string): Promise<Client>;
  invite(): string;
  /** 直接把一份存档写进某用户名下 */
  seed(c: Client, save: SaveData): void;
  /** 读某用户当前的存档 */
  saveOf(c: Client): SaveData;
}

export interface Client {
  cookie: string;
  /** login() 建出来的才有 */
  userId: string;
  req(
    method: string,
    path: string,
    body?: unknown,
    headers?: Record<string, string>,
  ): Promise<Response>;
  json<T = Record<string, unknown>>(
    method: string,
    path: string,
    body?: unknown,
  ): Promise<{ status: number; body: T }>;
}

export function testServer(over: Partial<Config> = {}): TestServer {
  const clock = { t: T0 };
  const dbh = openDb(':memory:');
  const deps: Deps = makeDeps(testConfig({ origin: ORIGIN, ...over }), dbh, {
    now: () => clock.t,
    rnd: () => 0.99,
  });
  const app = createApp(deps);

  const client = (): Client => {
    const c: Client = {
      cookie: '',
      userId: '',
      async req(method, path, body, headers = {}) {
        const h: Record<string, string> = { ...headers };
        if (method !== 'GET' && !('origin' in h)) h['origin'] = ORIGIN;
        if (c.cookie) h['cookie'] = c.cookie;
        let payload: RequestInit['body'];
        if (body instanceof FormData) payload = body;
        else if (body !== undefined) {
          h['content-type'] = 'application/json';
          payload = JSON.stringify(body);
        }
        const res = await app.request(path, { method, headers: h, body: payload });
        const set = res.headers.getSetCookie();
        for (const s of set) {
          const [pair] = s.split(';');
          if (!pair) continue;
          const [, value] = pair.split('=');
          c.cookie = value ? pair : '';
        }
        return res;
      },
      async json(method, path, body) {
        const res = await c.req(method, path, body);
        return { status: res.status, body: (await res.json()) as never };
      },
    };
    return c;
  };

  return {
    deps,
    clock,
    app,
    client,
    invite: () => createInvite(dbh.db, { now: clock.t }),
    seed: (c, save) => void writeSave(dbh.db, c.userId, save, clock.t),
    saveOf: (c) => loadSave(dbh.db, c.userId, clock.t).save,
    async login(username = 'alice', tz = 'Asia/Shanghai') {
      const u = await createUser(dbh.db, { username, password: 'password123', tz, now: clock.t });
      const c = client();
      c.userId = u.id;
      const r = await c.json('POST', '/api/auth/login', { username, password: 'password123' });
      if (r.status !== 200) throw new Error(`登录失败 ${r.status}`);
      return c;
    },
  };
}
