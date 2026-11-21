import { describe, expect, it } from 'vitest';
import { eq } from 'drizzle-orm';
import { INVITE_TTL_DAYS, SESSION_TTL_MS } from '../src/auth/accounts';
import { sessions, users } from '../src/db/schema';
import { ORIGIN, testServer } from './helpers';

const reg = (invite: string, username = 'bob', password = 'password123') => ({
  username,
  password,
  invite,
  tz: 'Asia/Shanghai',
});

describe('注册（邀请码）', () => {
  it('没有 / 错的邀请码不能注册', async () => {
    const s = testServer();
    const c = s.client();
    expect((await c.json('POST', '/api/auth/register', reg('AAAA-BBBB-CCCC-DDDD'))).status).toBe(
      403,
    );
    expect(
      (
        await c.json('POST', '/api/auth/register', {
          username: 'bob',
          password: 'password123',
          tz: 'UTC',
        })
      ).status,
    ).toBe(400);
  });

  it('邀请码一次性：用过就失效；手打小写 / 不带横杠也认', async () => {
    const s = testServer();
    const code = s.invite();
    const sloppy = code.toLowerCase().replace(/-/g, ' ');
    const r1 = await s
      .client()
      .json<{ me: { username: string; tz: string } }>('POST', '/api/auth/register', reg(sloppy));
    expect(r1.status).toBe(200);
    expect(r1.body.me).toMatchObject({ username: 'bob', tz: 'Asia/Shanghai' });
    const r2 = await s
      .client()
      .json<{ code: string }>('POST', '/api/auth/register', reg(code, 'carol'));
    expect(r2.status).toBe(403);
    expect(r2.body.code).toBe('bad_invite');
  });

  it('过期的邀请码拒收', async () => {
    const s = testServer();
    const code = s.invite();
    s.clock.t += INVITE_TTL_DAYS * 86_400_000 + 1;
    expect((await s.client().json('POST', '/api/auth/register', reg(code))).status).toBe(403);
  });

  it('用户名大小写不敏感唯一；用户名 / 密码 / 时区不合格给中文原因', async () => {
    const s = testServer();
    await s.client().json('POST', '/api/auth/register', reg(s.invite(), 'Bob'));
    const dup = await s
      .client()
      .json<{ code: string }>('POST', '/api/auth/register', reg(s.invite(), 'bob'));
    expect(dup.body.code).toBe('username_taken');
    const short = await s
      .client()
      .json<{ message: string }>('POST', '/api/auth/register', reg(s.invite(), 'x'));
    expect(short.body.message).toMatch(/用户名/);
    const weak = await s
      .client()
      .json<{ message: string }>('POST', '/api/auth/register', reg(s.invite(), 'dave', '123'));
    expect(weak.body.message).toMatch(/至少 8 位/);
    const badTz = await s
      .client()
      .json('POST', '/api/auth/register', { ...reg(s.invite(), 'erin'), tz: 'Mars/Base' });
    expect(badTz.status).toBe(400);
  });

  it('注册成功即登录：/api/me 拿到自己', async () => {
    const s = testServer();
    const c = s.client();
    await c.json('POST', '/api/auth/register', reg(s.invite()));
    const me = await c.json<{ me: { username: string; consent: unknown } }>('GET', '/api/me');
    expect(me.status).toBe(200);
    expect(me.body.me.username).toBe('bob');
    expect(me.body.me.consent).toBeNull();
  });
});

describe('登录与会话', () => {
  it('Cookie：httpOnly + SameSite=Lax；https 站点加 Secure 与 __Host- 前缀', async () => {
    const s = testServer({ origin: 'https://host.example.com' });
    s.invite();
    const c = s.client();
    const res = await c.req('POST', '/api/auth/register', reg(s.invite()), {
      origin: 'https://host.example.com',
    });
    const set = res.headers.get('set-cookie') ?? '';
    expect(set).toMatch(/^__Host-sid=/);
    expect(set).toMatch(/HttpOnly/i);
    expect(set).toMatch(/Secure/i);
    expect(set).toMatch(/SameSite=Lax/i);
    expect(set).toMatch(/Path=\//);
  });

  it('错密码 / 不存在的用户：同一句话', async () => {
    const s = testServer();
    await s.login('alice');
    const a = await s
      .client()
      .json<{ message: string }>('POST', '/api/auth/login', {
        username: 'alice',
        password: 'wrongpass1',
      });
    const b = await s
      .client()
      .json<{ message: string }>('POST', '/api/auth/login', {
        username: 'nobody',
        password: 'wrongpass1',
      });
    expect(a.status).toBe(401);
    expect(b.status).toBe(401);
    expect(a.body.message).toBe(b.body.message);
  });

  it('没登录访问业务接口 → 401；退出后会话作废', async () => {
    const s = testServer();
    expect((await s.client().json('GET', '/api/me')).status).toBe(401);
    const c = await s.login();
    const stolen = c.cookie;
    await c.json('POST', '/api/auth/logout');
    const thief = s.client();
    thief.cookie = stolen;
    expect((await thief.json('GET', '/api/me')).status).toBe(401);
  });

  it('会话 30 天过期；期间使用会滑动续期', async () => {
    const s = testServer();
    const c = await s.login();
    s.clock.t += SESSION_TTL_MS - 3_600_000;
    expect((await c.json('GET', '/api/me')).status).toBe(200); // 续期
    s.clock.t += SESSION_TTL_MS - 3_600_000;
    expect((await c.json('GET', '/api/me')).status).toBe(200);
    s.clock.t += SESSION_TTL_MS + 1;
    expect((await c.json('GET', '/api/me')).status).toBe(401);
  });

  it('停用的账号：现有会话立即失效', async () => {
    const s = testServer();
    const c = await s.login();
    s.deps.dbh.db.update(users).set({ disabled: true }).run();
    expect((await c.json('GET', '/api/me')).status).toBe(401);
  });

  it('改密码：旧密码要对；改完其他设备下线、这台留着', async () => {
    const s = testServer();
    const a = await s.login();
    const b = s.client();
    await b.json('POST', '/api/auth/login', { username: 'alice', password: 'password123' });
    expect(
      (await a.json('POST', '/api/auth/password', { old: 'nope-nope', next: 'newpass456' })).status,
    ).toBe(403);
    expect(
      (await a.json('POST', '/api/auth/password', { old: 'password123', next: 'newpass456' }))
        .status,
    ).toBe(200);
    expect((await a.json('GET', '/api/me')).status).toBe(200);
    expect((await b.json('GET', '/api/me')).status).toBe(401);
    const again = await s
      .client()
      .json('POST', '/api/auth/login', { username: 'alice', password: 'newpass456' });
    expect(again.status).toBe(200);
    expect(
      s.deps.dbh.db
        .select()
        .from(sessions)
        .where(eq(sessions.userId, s.deps.dbh.db.select().from(users).get()!.id))
        .all().length,
    ).toBe(2);
  });
});

describe('CSRF 与限流', () => {
  it('写接口 Origin 不对 → 403；没有 Origin 但 Sec-Fetch-Site 同源 → 放行', async () => {
    const s = testServer();
    const c = await s.login();
    expect(
      (await c.req('POST', '/api/auth/logout', undefined, { origin: 'https://evil.example' }))
        .status,
    ).toBe(403);
    const ok = await c.req(
      'POST',
      '/api/auth/password',
      { old: 'password123', next: 'newpass456' },
      { origin: '', 'sec-fetch-site': 'same-origin' },
    );
    expect(ok.status).not.toBe(403);
    expect(ORIGIN).toBe(s.deps.config.origin);
  });

  it('同一用户名一分钟内错 5 次后 → 429，带等待秒数；过了窗口恢复', async () => {
    const s = testServer();
    await s.login();
    const c = s.client();
    for (let i = 0; i < 5; i++)
      await c.json('POST', '/api/auth/login', { username: 'alice', password: 'wrongpass1' });
    const r = await c.json<{ retryAfterSec: number; message: string }>('POST', '/api/auth/login', {
      username: 'alice',
      password: 'password123',
    });
    expect(r.status).toBe(429);
    expect(r.body.retryAfterSec).toBeGreaterThan(0);
    expect(r.body.message).toMatch(/秒后再试/);
    s.clock.t += 61_000;
    expect(
      (await c.json('POST', '/api/auth/login', { username: 'alice', password: 'password123' }))
        .status,
    ).toBe(200);
  });

  it('同一 IP 一小时最多注册 5 次', async () => {
    const s = testServer();
    for (let i = 0; i < 5; i++) await s.client().json('POST', '/api/auth/register', reg('bad'));
    expect((await s.client().json('POST', '/api/auth/register', reg(s.invite()))).status).toBe(429);
  });

  it('健康检查不需登录；API 响应不缓存；未知接口 404', async () => {
    const s = testServer();
    const res = await s.client().req('GET', '/api/health');
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, db: 'ok' });
    const c = await s.login();
    const me = await c.req('GET', '/api/me');
    expect(me.headers.get('cache-control')).toBe('no-store');
    expect((await c.req('GET', '/api/nope')).status).toBe(404);
  });
});
