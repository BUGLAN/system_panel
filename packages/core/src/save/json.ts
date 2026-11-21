/**
 * 读档用的取值小工具：字段缺失或类型不对一律走默认值（「在默认值上合并」）。
 * 存档只会由本 App 自己写出，但导入的文件可能被手改过，所以每个字段都按不可信读。
 */
import { isAttrKey, type AttrMap } from '../data/attrs';
import { isRank, type Rank } from '../data/rank';

export type Json = Record<string, unknown>;

export function isObj(v: unknown): v is Json {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

export function str(j: Json, k: string, def: string): string {
  const v = j[k];
  return typeof v === 'string' ? v : def;
}

export function strOrNull(j: Json, k: string): string | null {
  const v = j[k];
  return typeof v === 'string' ? v : null;
}

export function int(j: Json, k: string, def: number): number {
  const v = j[k];
  return typeof v === 'number' && Number.isFinite(v) ? Math.trunc(v) : def;
}

export function intOrNull(j: Json, k: string): number | null {
  const v = j[k];
  return typeof v === 'number' && Number.isFinite(v) ? Math.trunc(v) : null;
}

export function bool(j: Json, k: string, def: boolean): boolean {
  const v = j[k];
  return typeof v === 'boolean' ? v : def;
}

export function rank(j: Json, k: string, def: Rank): Rank {
  const v = j[k];
  return isRank(v) ? v : def;
}

export function arr(j: Json, k: string): unknown[] {
  const v = j[k];
  return Array.isArray(v) ? v : [];
}

export function strList(j: Json, k: string, def: string[]): string[] {
  const v = j[k];
  if (!Array.isArray(v)) return def;
  return v.filter((x): x is string => typeof x === 'string');
}

/** 六维加成 / 六维数值：只收认得的键和整数值 */
export function attrMap(j: Json, k: string, def: AttrMap): AttrMap {
  const v = j[k];
  if (!isObj(v)) return def;
  const out: AttrMap = {};
  for (const [key, val] of Object.entries(v)) {
    if (isAttrKey(key) && typeof val === 'number' && Number.isFinite(val)) {
      out[key] = Math.trunc(val);
    }
  }
  return out;
}

/** 字符串 → 整数的映射（道具持有数） */
export function intMap(j: Json, k: string, def: Record<string, number>): Record<string, number> {
  const v = j[k];
  if (!isObj(v)) return def;
  const out: Record<string, number> = {};
  for (const [key, val] of Object.entries(v)) {
    if (typeof val === 'number' && Number.isFinite(val)) out[key] = Math.trunc(val);
  }
  return out;
}

/** 字符串 → 字符串的映射（访谈答案） */
export function strMap(j: Json, k: string, def: Record<string, string>): Record<string, string> {
  const v = j[k];
  if (!isObj(v)) return def;
  const out: Record<string, string> = {};
  for (const [key, val] of Object.entries(v)) {
    if (typeof val === 'string') out[key] = val;
  }
  return out;
}
