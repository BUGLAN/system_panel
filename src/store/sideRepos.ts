/**
 * 存档之外的本机数据：LLM 设置、同意记录、偏好、长期记忆、聊天记录、流水、证据照片。
 * 都是独立的表 / 键：重置存档清的是记忆、聊天、流水、照片；LLM 设置、同意、偏好保留。
 */
import { emptySettings, settingsFromJson, type LlmSettings } from '../agent/settings';
import { chatFromRow, CHAT_HISTORY_MAX, type ChatMessage } from '../agent/chatService';
import type { MemoryBackend, MemoryEntry } from '../agent/memory';
import { HISTORY_MAX, historyFromRow } from '../core/flow/history';
import type { HistoryEntry } from '../core/flow/types';
import { isObj } from '../core/save/json';
import { KV, type HostDb } from './db';

// ── LLM 设置 ──────────────────────────────────────────────

export async function loadLlmSettings(db: HostDb): Promise<LlmSettings> {
  try {
    return settingsFromJson((await db.kv.get(KV.llm))?.value);
  } catch {
    return emptySettings();
  }
}

export async function saveLlmSettings(db: HostDb, s: LlmSettings): Promise<void> {
  await db.kv.put({ key: KV.llm, value: { ...s } });
}

// ── 同意记录（首启告知页）──────────────────────────────────

/** 告知页文案有实质修改时加一，已同意的人要重签 */
export const CONSENT_VERSION = 1;

export interface ConsentRecord {
  version: number;
  at: number;
}

export async function loadConsent(db: HostDb): Promise<ConsentRecord | null> {
  try {
    const v = (await db.kv.get(KV.consent))?.value;
    if (!isObj(v) || typeof v['version'] !== 'number' || typeof v['at'] !== 'number') return null;
    return { version: v['version'], at: v['at'] };
  } catch {
    return null;
  }
}

export function consentValid(c: ConsentRecord | null): boolean {
  return !!c && c.version === CONSENT_VERSION;
}

export async function saveConsent(db: HostDb, at: number): Promise<ConsentRecord> {
  const rec = { version: CONSENT_VERSION, at };
  await db.kv.put({ key: KV.consent, value: rec });
  return rec;
}

export async function withdrawConsent(db: HostDb): Promise<void> {
  await db.kv.delete(KV.consent);
}

// ── 偏好（音量等，重置不清）────────────────────────────────

export interface Prefs {
  muted: boolean;
  volume: number;
  /** 看过「添加到主屏幕」引导 */
  installHintSeen: boolean;
}

export const defaultPrefs = (): Prefs => ({ muted: false, volume: 0.8, installHintSeen: false });

export async function loadPrefs(db: HostDb): Promise<Prefs> {
  const d = defaultPrefs();
  try {
    const v = (await db.kv.get(KV.prefs))?.value;
    if (!isObj(v)) return d;
    return {
      muted: typeof v['muted'] === 'boolean' ? v['muted'] : d.muted,
      volume: typeof v['volume'] === 'number' ? Math.min(1, Math.max(0, v['volume'])) : d.volume,
      installHintSeen: v['installHintSeen'] === true,
    };
  } catch {
    return d;
  }
}

export async function savePrefs(db: HostDb, p: Prefs): Promise<void> {
  await db.kv.put({ key: KV.prefs, value: { ...p } });
}

// ── 长期记忆 ──────────────────────────────────────────────

export function memoryBackend(db: HostDb): MemoryBackend {
  return {
    async all() {
      const rows = await db.memory.toArray();
      return rows
        .filter((r) => typeof r['text'] === 'string')
        .map((r): MemoryEntry => ({
          id: r.id,
          text: r['text'] as string,
          at: r.at,
          source: (['interview', 'chat', 'tool', 'milestone'] as const).includes(
            r['source'] as never,
          )
            ? (r['source'] as MemoryEntry['source'])
            : 'chat',
          weight: typeof r['weight'] === 'number' ? r['weight'] : 1,
        }));
    },
    async put(e) {
      await db.memory.put({ ...e });
    },
    async remove(ids) {
      await db.memory.bulkDelete(ids);
    },
    async clear() {
      await db.memory.clear();
    },
  };
}

// ── 聊天记录 ──────────────────────────────────────────────

export async function loadChat(db: HostDb): Promise<ChatMessage[]> {
  try {
    const rows = await db.chat.orderBy('seq').toArray();
    return rows.map(chatFromRow).filter((m): m is ChatMessage => m !== null);
  } catch {
    return [];
  }
}

export async function appendChat(db: HostDb, msgs: ChatMessage[]): Promise<void> {
  if (!msgs.length) return;
  await db.transaction('rw', db.chat, async () => {
    await db.chat.bulkAdd(msgs.map((m) => ({ ...m })));
    const n = await db.chat.count();
    if (n > CHAT_HISTORY_MAX) {
      const old = await db.chat
        .orderBy('seq')
        .limit(n - CHAT_HISTORY_MAX)
        .primaryKeys();
      await db.chat.bulkDelete(old);
    }
  });
}

// ── 流水 ─────────────────────────────────────────────────

export async function loadHistory(db: HostDb): Promise<HistoryEntry[]> {
  try {
    const rows = await db.history.orderBy('seq').toArray();
    return rows.map(historyFromRow).filter((e): e is HistoryEntry => e !== null);
  } catch {
    return [];
  }
}

export async function appendHistory(db: HostDb, entries: HistoryEntry[]): Promise<void> {
  if (!entries.length) return;
  await db.transaction('rw', db.history, async () => {
    await db.history.bulkAdd(entries.map((e) => ({ ...e })));
    const n = await db.history.count();
    if (n > HISTORY_MAX) {
      const old = await db.history
        .orderBy('seq')
        .limit(n - HISTORY_MAX)
        .primaryKeys();
      await db.history.bulkDelete(old);
    }
  });
}

// ── 证据照片 ─────────────────────────────────────────────

export async function putEvidence(
  db: HostDb,
  id: string,
  blob: Blob,
  takenAt: number,
): Promise<void> {
  await db.evidence.put({ id, blob, type: blob.type || 'image/jpeg', takenAt });
}

export async function getEvidence(db: HostDb, id: string): Promise<Blob | null> {
  try {
    return (await db.evidence.get(id))?.blob ?? null;
  } catch {
    return null;
  }
}
