/**
 * 随机 token / id 与哈希：会话 token、邀请码都只存哈希。
 */
import { createHash, randomBytes } from 'node:crypto';

export const sha256 = (s: string | Uint8Array) => createHash('sha256').update(s).digest('hex');

/** URL 安全的随机串 */
export const randomToken = (bytes = 32) => randomBytes(bytes).toString('base64url');

/** 短随机 id（用户、证据） */
export const randomId = (bytes = 12) => randomBytes(bytes).toString('base64url');

/** 邀请码：去掉易混字符，按 4 位分组，方便口头 / 聊天里转述 */
const INVITE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
export function newInviteCode(): string {
  const b = randomBytes(16);
  let s = '';
  for (let i = 0; i < 16; i++) s += INVITE_ALPHABET[(b[i] as number) % INVITE_ALPHABET.length];
  return s.match(/.{4}/g)!.join('-');
}

/** 宿主手打的邀请码：去空白、转大写、补上分隔符后再哈希 */
export function normalizeInvite(raw: string): string {
  const s = raw.toUpperCase().replace(/[^A-Z0-9]/g, '');
  return (s.match(/.{1,4}/g) ?? []).join('-');
}
