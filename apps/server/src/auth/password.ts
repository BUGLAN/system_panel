/**
 * 口令：argon2id（@node-rs/argon2 默认参数：m=19MiB t=2 p=1）。
 */
import { hash, verify } from '@node-rs/argon2';

/** Algorithm.Argon2id（库里是 const enum，verbatimModuleSyntax 下不能直接引用） */
const ARGON2ID = 2;

export const PASSWORD_MIN = 8;
export const PASSWORD_MAX = 128;

export function passwordProblem(p: string): string | null {
  if (p.length < PASSWORD_MIN) return `密码至少 ${PASSWORD_MIN} 位。`;
  if (p.length > PASSWORD_MAX) return `密码最多 ${PASSWORD_MAX} 位。`;
  return null;
}

export function hashPassword(p: string): Promise<string> {
  return hash(p, { algorithm: ARGON2ID });
}

export async function verifyPassword(stored: string, p: string): Promise<boolean> {
  try {
    return await verify(stored, p);
  } catch {
    return false;
  }
}

/** 用户不存在时也算一次哈希，避免靠响应时间猜用户名 */
let dummy: Promise<string> | null = null;
export async function burnPasswordTime(p: string): Promise<void> {
  dummy ??= hashPassword('dummy-password-for-timing');
  await verifyPassword(await dummy, p);
}
