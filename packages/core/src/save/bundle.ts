/**
 * 导出 / 导入存档的文件格式（JSON）与校验。纯逻辑，不碰 IndexedDB。
 *
 * 导出范围与「重置存档」清空的范围一致：存档、聊天记录、流水、长期记忆、证据照片；
 * 不导出 LLM 设置（含 Key）和同意记录。证据照片转成 Base64 写进 JSON。
 */
import { isObj, type Json } from './json';
import { parseSave, saveFromJson, type SaveData } from './saveData';

export const BUNDLE_APP = 'host-system';
export const BUNDLE_KIND = 'backup';
export const BUNDLE_VERSION = 1;

export interface BundleEvidence {
  id: string;
  /** MIME，只收 image/* */
  type: string;
  takenAt: number;
  /** Base64（不带 data: 前缀） */
  data: string;
}

export interface BackupBundle {
  app: typeof BUNDLE_APP;
  kind: typeof BUNDLE_KIND;
  version: number;
  exportedAt: number;
  /** 存档对象（saveToJson 的产物）；从没绑定过 = null */
  save: Json | null;
  chat: Json[];
  history: Json[];
  memory: Json[];
  evidence: BundleEvidence[];
}

/** 校验通过的包：存档已经解析好 */
export interface CheckedBundle {
  bundle: BackupBundle;
  save: SaveData | null;
}

export type BundleCheck = { ok: true; value: CheckedBundle } | { ok: false; reason: string };

const B64 = /^[A-Za-z0-9+/]*={0,2}$/;

function isBase64(s: string): boolean {
  return s.length % 4 === 0 && B64.test(s);
}

function fail(reason: string): BundleCheck {
  return { ok: false, reason };
}

function objList(v: unknown): Json[] | null {
  if (!Array.isArray(v)) return null;
  return v.every(isObj) ? (v as Json[]) : null;
}

/** 校验一个已经 JSON.parse 过的对象。不合格就给出能直接念给宿主听的原因。 */
export function checkBundle(v: unknown, now: number): BundleCheck {
  if (!isObj(v)) return fail('这不是一个存档文件。');
  if (v['app'] !== BUNDLE_APP || v['kind'] !== BUNDLE_KIND) {
    return fail('这不是「宿主养成系统」导出的存档文件。');
  }
  const ver = v['version'];
  if (typeof ver !== 'number' || !Number.isInteger(ver)) return fail('存档文件缺少版本号。');
  if (ver > BUNDLE_VERSION) {
    return fail(`这份存档来自更新版本的 App（格式 v${ver}），当前版本读不了。先更新 App 再导入。`);
  }
  if (ver < 1) return fail(`存档格式版本 v${ver} 不对。`);

  let save: SaveData | null = null;
  if (v['save'] !== null && v['save'] !== undefined) {
    save = saveFromJson(v['save'], now);
    if (!save) return fail('存档内容损坏：主档读不出来，或来自更新版本的 App。');
  }

  const lists: Array<[keyof BackupBundle & string, string]> = [
    ['chat', '聊天记录'],
    ['history', '流水'],
    ['memory', '长期记忆'],
  ];
  const parsed: Record<string, Json[]> = {};
  for (const [k, label] of lists) {
    const list = v[k] === undefined ? [] : objList(v[k]);
    if (!list) return fail(`存档内容损坏：${label}不是一个列表。`);
    // 主键要对得上表结构：长期记忆按 id，聊天 / 流水的自增序号可缺省
    const keyOk =
      k === 'memory'
        ? list.every((r) => typeof r['id'] === 'string' && r['id'] !== '')
        : list.every((r) => r['seq'] === undefined || Number.isInteger(r['seq']));
    if (!keyOk) return fail(`存档内容损坏：${label}里有读不懂的条目。`);
    parsed[k] = list;
  }

  const rawEvidence = v['evidence'] === undefined ? [] : v['evidence'];
  if (!Array.isArray(rawEvidence)) return fail('存档内容损坏：证据照片不是一个列表。');
  const evidence: BundleEvidence[] = [];
  const seen = new Set<string>();
  for (let i = 0; i < rawEvidence.length; i++) {
    const e: unknown = rawEvidence[i];
    const bad = fail(`存档内容损坏：第 ${i + 1} 张证据照片读不出来。`);
    if (!isObj(e)) return bad;
    const { id, type, takenAt, data } = e;
    if (typeof id !== 'string' || !id || seen.has(id)) return bad;
    if (typeof type !== 'string' || !type.startsWith('image/')) return bad;
    if (typeof data !== 'string' || !isBase64(data)) return bad;
    seen.add(id);
    evidence.push({ id, type, takenAt: typeof takenAt === 'number' ? takenAt : 0, data });
  }

  return {
    ok: true,
    value: {
      save,
      bundle: {
        app: BUNDLE_APP,
        kind: BUNDLE_KIND,
        version: ver,
        exportedAt: typeof v['exportedAt'] === 'number' ? v['exportedAt'] : 0,
        save: save ? (v['save'] as Json) : null,
        chat: parsed['chat'] ?? [],
        history: parsed['history'] ?? [],
        memory: parsed['memory'] ?? [],
        evidence,
      },
    },
  };
}

/** 从文件文本校验（JSON 坏也给原因） */
export function checkBundleText(text: string, now: number): BundleCheck {
  let v: unknown;
  try {
    v = JSON.parse(text);
  } catch {
    return fail('文件不是有效的 JSON，可能不完整或被改坏了。');
  }
  return checkBundle(v, now);
}

/** 导出文件名：宿主养成系统-存档-20261121-1230.json */
export function bundleFileName(now: number): string {
  const d = new Date(now);
  const p = (n: number) => String(n).padStart(2, '0');
  return `宿主养成系统-存档-${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}.json`;
}

// ── Base64 ⇄ 二进制 ────────────────────────────────────────

export function bytesToBase64(bytes: Uint8Array): string {
  let s = '';
  const CHUNK = 0x8000;
  for (let i = 0; i < bytes.length; i += CHUNK) {
    s += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
  }
  return btoa(s);
}

export function base64ToBytes(b64: string): Uint8Array {
  const s = atob(b64);
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out;
}

/** 解析存档串的便捷转发（给仓库层用，避免它直接依赖 saveData 细节） */
export { parseSave };
