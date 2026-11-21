/**
 * 长期记忆：访谈答案 + remember 工具写入；按关键词（含中文二元组）取相关的 ≤8 条注入提示词。
 * 移植自 flutter-final:app/lib/agent/memory.dart。存储由调用方注入（IndexedDB / 内存）。
 */
export type MemorySource = 'interview' | 'chat' | 'tool' | 'milestone';

export interface MemoryEntry {
  id: string;
  text: string;
  at: number;
  source: MemorySource;
  weight: number;
}

export interface MemoryBackend {
  all(): Promise<MemoryEntry[]>;
  put(e: MemoryEntry): Promise<void>;
  remove(ids: string[]): Promise<void>;
  clear(): Promise<void>;
}

export const MEMORY_MAX = 200;
export const MEMORY_INJECT_LIMIT = 8;

let seq = 0;
function newId(now: number): string {
  seq = (seq + 1) % 0xffff;
  return `${now.toString(36)}-${seq}`;
}

/** 关键词：整词 + 中文 / 字母的二元组 */
export function keywords(text: string): Set<string> {
  const t = text
    .toLowerCase()
    .replace(/[^\w一-鿿]+/g, ' ')
    .trim();
  const out = new Set<string>();
  for (const term of t.split(' ')) {
    if (!term) continue;
    out.add(term);
    const cs = [...term];
    for (let i = 0; i + 2 <= cs.length; i++) out.add(cs.slice(i, i + 2).join(''));
  }
  return out;
}

export class MemoryStore {
  constructor(
    private readonly backend: MemoryBackend,
    private readonly clock: () => number = Date.now,
  ) {}

  /** 新 → 旧 */
  async entries(): Promise<MemoryEntry[]> {
    try {
      return (await this.backend.all()).sort((a, b) => b.at - a.at);
    } catch {
      return [];
    }
  }

  /** 写一条：同文去重（刷新时间、取较高权重）；超 200 条按「低权重、最旧」淘汰 */
  async add(text: string, source: MemorySource = 'chat', weight = 1): Promise<MemoryEntry> {
    const clean = text.trim();
    if (!clean) throw new Error('记忆内容不能为空');
    const now = this.clock();
    const all = await this.entries();
    const dup = all.find((e) => e.text === clean);
    const entry: MemoryEntry = dup
      ? { ...dup, at: now, weight: Math.max(dup.weight, weight) }
      : { id: newId(now), text: clean, at: now, source, weight };
    await this.backend.put(entry);
    const merged = [entry, ...all.filter((e) => e.id !== entry.id)];
    if (merged.length > MEMORY_MAX) {
      const doomed = [...merged]
        .sort((a, b) => a.weight - b.weight || a.at - b.at)
        .slice(0, merged.length - MEMORY_MAX)
        .map((e) => e.id);
      await this.backend.remove(doomed);
    }
    return entry;
  }

  async clear(): Promise<void> {
    await this.backend.clear();
  }

  /** 相关的几条：关键词命中优先，不够用最近的补 */
  async relevant(
    query: string | null | undefined,
    limit = MEMORY_INJECT_LIMIT,
  ): Promise<MemoryEntry[]> {
    const all = await this.entries();
    const q = (query ?? '').trim();
    if (!q || !all.length) return all.slice(0, limit);
    const keys = keywords(q);
    const hits = all.filter((e) => [...keywords(e.text)].some((k) => keys.has(k)));
    const out = hits.slice(0, limit);
    for (const e of all) {
      if (out.length >= limit) break;
      if (!out.includes(e)) out.push(e);
    }
    return out;
  }

  /** 注入提示词的摘要 */
  async digest(query: string | null | undefined, limit = MEMORY_INJECT_LIMIT): Promise<string> {
    const rel = await this.relevant(query, limit);
    return rel.map((e) => `- ${e.text}`).join('\n');
  }
}

/** 内存版后端（测试 / 没有 IndexedDB 时） */
export function memoryBackendInMemory(): MemoryBackend {
  const map = new Map<string, MemoryEntry>();
  return {
    all: async () => [...map.values()],
    put: async (e) => void map.set(e.id, e),
    remove: async (ids) => ids.forEach((id) => map.delete(id)),
    clear: async () => map.clear(),
  };
}
