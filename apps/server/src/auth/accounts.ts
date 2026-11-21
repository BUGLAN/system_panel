/**
 * 账号、会话、邀请码的数据访问。注册 = 校验邀请码 + 建用户 + 核销，同一事务。
 */
import { and, eq, gt, isNull, lt } from 'drizzle-orm';
import { isTimeZone } from '@host/core/time/day';
import type { Db } from '../db/client';
import { invites, sessions, users } from '../db/schema';
import { badRequest, forbidden } from '../http/errors';
import { hashPassword, passwordProblem } from './password';
import { newInviteCode, normalizeInvite, randomId, randomToken, sha256 } from './tokens';

export const SESSION_TTL_MS = 30 * 86_400_000;
/** 滑动续期：距上次续期超过一天才写库 */
export const SESSION_RENEW_MS = 86_400_000;
export const INVITE_TTL_DAYS = 7;

export interface AuthUser {
  id: string;
  username: string;
  role: 'admin' | 'user';
  tz: string;
}

/** 用户名：3–20 个字符，字母 / 数字 / 下划线 / 汉字 */
const USERNAME = /^[A-Za-z0-9_一-鿿]{3,20}$/u;

export function usernameProblem(u: string): string | null {
  if (!USERNAME.test(u)) return '用户名 3–20 个字，只能用字母、数字、下划线或汉字。';
  return null;
}

export const usernameKey = (u: string) => u.normalize('NFKC').toLowerCase();

export function findUserByName(db: Db, username: string) {
  return db
    .select()
    .from(users)
    .where(eq(users.usernameKey, usernameKey(username)))
    .get();
}

export function getUser(db: Db, id: string): AuthUser | null {
  const u = db.select().from(users).where(eq(users.id, id)).get();
  if (!u || u.disabled) return null;
  return { id: u.id, username: u.username, role: u.role, tz: u.tz };
}

export async function createUser(
  db: Db,
  o: { username: string; password: string; tz: string; role?: 'admin' | 'user'; now: number },
): Promise<AuthUser> {
  const why = usernameProblem(o.username) ?? passwordProblem(o.password);
  if (why) throw badRequest(why);
  if (!isTimeZone(o.tz)) throw badRequest('时区不认识。');
  if (findUserByName(db, o.username)) throw badRequest('这个用户名有人用了。', 'username_taken');
  const passHash = await hashPassword(o.password);
  const row = {
    id: randomId(),
    username: o.username,
    usernameKey: usernameKey(o.username),
    passHash,
    role: o.role ?? 'user',
    tz: o.tz,
    createdAt: o.now,
  } as const;
  db.insert(users).values(row).run();
  return { id: row.id, username: row.username, role: row.role, tz: row.tz };
}

/** 邀请码注册：码不对 / 过期 / 用过 → 拒；成功即核销（同一事务，防并发重复使用） */
export async function registerWithInvite(
  db: Db,
  o: { username: string; password: string; tz: string; invite: string; now: number },
): Promise<AuthUser> {
  const why = usernameProblem(o.username) ?? passwordProblem(o.password);
  if (why) throw badRequest(why);
  if (!isTimeZone(o.tz)) throw badRequest('时区不认识。');
  // 先把慢的哈希算好，再进同步事务
  const passHash = await hashPassword(o.password);
  const codeHash = sha256(normalizeInvite(o.invite));
  return db.transaction((tx) => {
    const inv = tx.select().from(invites).where(eq(invites.codeHash, codeHash)).get();
    if (!inv || inv.usedBy !== null || inv.usedAt !== null)
      throw forbidden('邀请码不对，或者已经用过了。', 'bad_invite');
    if (inv.expiresAt <= o.now) throw forbidden('邀请码过期了，找管理员要个新的。', 'bad_invite');
    if (
      tx
        .select()
        .from(users)
        .where(eq(users.usernameKey, usernameKey(o.username)))
        .get()
    )
      throw badRequest('这个用户名有人用了。', 'username_taken');
    const id = randomId();
    tx.insert(users)
      .values({
        id,
        username: o.username,
        usernameKey: usernameKey(o.username),
        passHash,
        role: 'user',
        tz: o.tz,
        createdAt: o.now,
      })
      .run();
    const used = tx
      .update(invites)
      .set({ usedBy: id, usedAt: o.now })
      .where(and(eq(invites.codeHash, codeHash), isNull(invites.usedAt)))
      .run();
    if (used.changes !== 1) throw forbidden('邀请码不对，或者已经用过了。', 'bad_invite');
    return { id, username: o.username, role: 'user' as const, tz: o.tz };
  });
}

export async function setPassword(db: Db, userId: string, password: string): Promise<void> {
  const why = passwordProblem(password);
  if (why) throw badRequest(why);
  const passHash = await hashPassword(password);
  db.update(users).set({ passHash }).where(eq(users.id, userId)).run();
}

// ── 会话 ──────────────────────────────────────────────────

export function createSession(db: Db, userId: string, now: number, ua = ''): string {
  const token = randomToken();
  db.insert(sessions)
    .values({
      id: sha256(token),
      userId,
      createdAt: now,
      expiresAt: now + SESSION_TTL_MS,
      renewedAt: now,
      ua: ua.slice(0, 200),
    })
    .run();
  return token;
}

/** token → 用户；过期 / 吊销 / 用户被停用 → null。顺带滑动续期。 */
export function sessionUser(db: Db, token: string, now: number): AuthUser | null {
  if (!token) return null;
  const id = sha256(token);
  const s = db.select().from(sessions).where(eq(sessions.id, id)).get();
  if (!s) return null;
  if (s.expiresAt <= now) {
    db.delete(sessions).where(eq(sessions.id, id)).run();
    return null;
  }
  const u = getUser(db, s.userId);
  if (!u) return null;
  if (now - s.renewedAt >= SESSION_RENEW_MS) {
    db.update(sessions)
      .set({ renewedAt: now, expiresAt: now + SESSION_TTL_MS })
      .where(eq(sessions.id, id))
      .run();
  }
  return u;
}

export function revokeSession(db: Db, token: string): void {
  db.delete(sessions)
    .where(eq(sessions.id, sha256(token)))
    .run();
}

/** 吊销某用户全部会话（可留下当前这一条） */
export function revokeUserSessions(db: Db, userId: string, keepToken?: string): void {
  const all = db
    .select({ id: sessions.id })
    .from(sessions)
    .where(eq(sessions.userId, userId))
    .all();
  const keep = keepToken ? sha256(keepToken) : null;
  for (const s of all) if (s.id !== keep) db.delete(sessions).where(eq(sessions.id, s.id)).run();
}

export function purgeExpiredSessions(db: Db, now: number): number {
  return db.delete(sessions).where(lt(sessions.expiresAt, now)).run().changes;
}

// ── 邀请码 ────────────────────────────────────────────────

export function createInvite(db: Db, o: { now: number; days?: number; note?: string }): string {
  const code = newInviteCode();
  db.insert(invites)
    .values({
      codeHash: sha256(code),
      note: o.note ?? '',
      createdAt: o.now,
      expiresAt: o.now + (o.days ?? INVITE_TTL_DAYS) * 86_400_000,
    })
    .run();
  return code;
}

/** 还没用、没过期的邀请码（只能看备注和期限，码本身不存） */
export function openInvites(db: Db, now: number) {
  return db
    .select({ note: invites.note, createdAt: invites.createdAt, expiresAt: invites.expiresAt })
    .from(invites)
    .where(and(isNull(invites.usedAt), gt(invites.expiresAt, now)))
    .all();
}
