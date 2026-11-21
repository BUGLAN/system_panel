/**
 * 首启告知的同意记录：跟账号走，重置存档不清。
 * 告知文案有实质修改时 CONSENT_VERSION +1，已同意的人要重签。
 */
import { eq } from 'drizzle-orm';
import type { Db } from '../db/client';
import { consents } from '../db/schema';

import { CONSENT_VERSION } from '@host/core/api/types';

/** v2：数据改存服务器、经服务器转发给模型服务商（docs/05 Q5） */
export { CONSENT_VERSION };

export interface ConsentRecord {
  version: number;
  at: number;
}

export function consentOf(db: Db, userId: string): ConsentRecord | null {
  const r = db.select().from(consents).where(eq(consents.userId, userId)).get();
  return r ? { version: r.version, at: r.at } : null;
}

export function hasConsent(db: Db, userId: string): boolean {
  return consentOf(db, userId)?.version === CONSENT_VERSION;
}

export function giveConsent(db: Db, userId: string, at: number): ConsentRecord {
  const rec = { version: CONSENT_VERSION, at };
  db.insert(consents)
    .values({ userId, ...rec })
    .onConflictDoUpdate({ target: consents.userId, set: rec })
    .run();
  return rec;
}

export function withdrawConsent(db: Db, userId: string): void {
  db.delete(consents).where(eq(consents.userId, userId)).run();
}
