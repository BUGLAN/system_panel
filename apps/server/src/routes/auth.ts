/**
 * 账号：注册（邀请码）/ 登录 / 退出 / 改密码 / 我是谁。
 * 会话 Cookie：httpOnly + SameSite=Lax；站点是 https 时加 Secure 并用 __Host- 前缀。
 */
import { Hono } from 'hono';
import { deleteCookie, getCookie, setCookie } from 'hono/cookie';
import { getConnInfo } from '@hono/node-server/conninfo';
import { z } from 'zod';
import {
  SESSION_TTL_MS,
  createSession,
  findUserByName,
  registerWithInvite,
  revokeSession,
  revokeUserSessions,
  setPassword,
  type AuthUser,
} from '../auth/accounts';
import { burnPasswordTime, verifyPassword } from '../auth/password';
import type { Config } from '../config';
import { clientIp, me, type AppEnv, type Ctx } from '../http/context';
import { ApiError, tooMany, unauthorized } from '../http/errors';
import { body } from '../http/zod';
import { consentOf } from '../repo/consent';

export function cookieName(cfg: Config): string {
  return cfg.origin.startsWith('https://') ? '__Host-sid' : 'sid';
}

export function readSessionCookie(c: Ctx): string {
  return getCookie(c, cookieName(c.var.deps.config)) ?? '';
}

function putSessionCookie(c: Ctx, token: string): void {
  const cfg = c.var.deps.config;
  setCookie(c, cookieName(cfg), token, {
    httpOnly: true,
    secure: cfg.origin.startsWith('https://'),
    sameSite: 'Lax',
    path: '/',
    maxAge: Math.floor(SESSION_TTL_MS / 1000),
  });
}

function dropSessionCookie(c: Ctx): void {
  const cfg = c.var.deps.config;
  deleteCookie(c, cookieName(cfg), { path: '/', secure: cfg.origin.startsWith('https://') });
}

function ipOf(c: Ctx): string {
  let remote = 'unknown';
  try {
    remote = getConnInfo(c).remote.address ?? 'unknown';
  } catch {
    // app.request() 测试里没有真实连接
  }
  return clientIp(c, remote);
}

function limit(c: Ctx, key: string, n: number, windowMs: number, what: string): void {
  const wait = c.var.deps.limiter.hit(key, n, windowMs);
  if (wait > 0) throw tooMany(`${what}太频繁了，${wait} 秒后再试。`, wait);
}

/** 我是谁（含同意记录） */
export function meView(c: Ctx, u: AuthUser) {
  return {
    username: u.username,
    role: u.role,
    tz: u.tz,
    consent: consentOf(c.var.deps.dbh.db, u.id),
  };
}

const Register = z.object({
  username: z.string().trim().min(1).max(40),
  password: z.string().min(1).max(256),
  invite: z.string().trim().min(1).max(64),
  tz: z.string().trim().min(1).max(64),
});
const Login = z.object({
  username: z.string().trim().min(1).max(40),
  password: z.string().min(1).max(256),
});
const ChangePassword = z.object({
  old: z.string().min(1).max(256),
  next: z.string().min(1).max(256),
});

export const authRoutes = new Hono<AppEnv>()
  .post('/register', async (c) => {
    const ip = ipOf(c);
    limit(c, `reg:${ip}`, 5, 3_600_000, '注册');
    const b = await body(c, Register);
    const { dbh, now } = c.var.deps;
    const u = await registerWithInvite(dbh.db, { ...b, now: now() });
    putSessionCookie(c, createSession(dbh.db, u.id, now(), c.req.header('user-agent')));
    return c.json({ ok: true, me: meView(c, u) });
  })
  .post('/login', async (c) => {
    const ip = ipOf(c);
    limit(c, `login-ip:${ip}`, 20, 60_000, '登录');
    const b = await body(c, Login);
    const nameKey = `login-user:${b.username.toLowerCase()}`;
    limit(c, nameKey, 5, 60_000, '登录');
    const { dbh, now, limiter } = c.var.deps;
    const row = findUserByName(dbh.db, b.username);
    if (!row || row.disabled) {
      await burnPasswordTime(b.password);
      throw unauthorized('用户名或密码不对。');
    }
    if (!(await verifyPassword(row.passHash, b.password))) throw unauthorized('用户名或密码不对。');
    limiter.reset(nameKey);
    putSessionCookie(c, createSession(dbh.db, row.id, now(), c.req.header('user-agent')));
    const u: AuthUser = { id: row.id, username: row.username, role: row.role, tz: row.tz };
    return c.json({ ok: true, me: meView(c, u) });
  })
  .post('/logout', (c) => {
    const token = c.get('token');
    if (token) revokeSession(c.var.deps.dbh.db, token);
    dropSessionCookie(c);
    return c.json({ ok: true });
  })
  .post('/password', async (c) => {
    const u = me(c);
    limit(c, `pw:${u.id}`, 5, 60_000, '改密码');
    const b = await body(c, ChangePassword);
    const { dbh } = c.var.deps;
    const row = findUserByName(dbh.db, u.username);
    if (!row || !(await verifyPassword(row.passHash, b.old)))
      throw new ApiError(403, 'bad_password', '旧密码不对。');
    await setPassword(dbh.db, u.id, b.next);
    // 改完：其他设备全部下线，这一台留着
    revokeUserSessions(dbh.db, u.id, c.get('token'));
    return c.json({ ok: true });
  });

export const meRoute = new Hono<AppEnv>().get('/', (c) =>
  c.json({ ok: true, me: meView(c, me(c)) }),
);
