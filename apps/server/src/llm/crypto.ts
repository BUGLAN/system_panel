/**
 * 用户 Key 加密：AES-256-GCM，密钥来自环境变量 APP_ENCRYPTION_KEY。
 * 密文格式：v1.<iv base64url>.<tag base64url>.<ciphertext base64url>
 */
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

export function encryptSecret(plain: string, key: Buffer): string {
  const iv = randomBytes(12);
  const c = createCipheriv('aes-256-gcm', key, iv);
  const enc = Buffer.concat([c.update(plain, 'utf8'), c.final()]);
  return [
    'v1',
    iv.toString('base64url'),
    c.getAuthTag().toString('base64url'),
    enc.toString('base64url'),
  ].join('.');
}

/** 解不开（密钥换了 / 密文坏了）→ null，按「没填 Key」处理 */
export function decryptSecret(box: string, key: Buffer): string | null {
  const [v, iv, tag, data] = box.split('.');
  if (v !== 'v1' || !iv || !tag || data === undefined) return null;
  try {
    const d = createDecipheriv('aes-256-gcm', key, Buffer.from(iv, 'base64url'));
    d.setAuthTag(Buffer.from(tag, 'base64url'));
    return Buffer.concat([d.update(Buffer.from(data, 'base64url')), d.final()]).toString('utf8');
  } catch {
    return null;
  }
}

/** 给宿主确认填的是哪把：只露末 4 位 */
export function keyHint(k: string): string {
  const t = k.trim();
  return t.length <= 8 ? '…' : `…${t.slice(-4)}`;
}
