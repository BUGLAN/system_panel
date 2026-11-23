/**
 * 一单委托（都是主线单：清单里的某一张）。移植自 flutter-final:app/lib/state/quest.dart，
 * 计时、日常、补救、六维都已拿掉。文案读数（kindLabel …）在 core/flow。
 */
import type { Rank } from '../data/rank';
import { int, isObj, rank, str, type Json } from '../save/json';

export interface Quest {
  /** 单号（显示为 № 0041） */
  serial: number;
  /** 主线清单里第几张（0 基） */
  planIndex: number;
  /** 整条主线一共几张 */
  planTotal: number;
  /** 属于哪个目标（Goal id） */
  goalId: string;
  name: string;
  /** 她的附言（可以为空） */
  reason: string;
  /** 证据要求 */
  proof: string;
  /** 预计耗时（分钟，只作参考，不计时） */
  minutes: number;
  rank: Rank;
}

export function questToJson(q: Quest): Json {
  return {
    serial: q.serial,
    planIndex: q.planIndex,
    planTotal: q.planTotal,
    ...(q.goalId ? { goalId: q.goalId } : {}),
    name: q.name,
    reason: q.reason,
    proof: q.proof,
    minutes: q.minutes,
    rank: q.rank,
  };
}

/** 旧版的日常 / 补救单（kind ≠ main）：读档时丢掉 */
export function isLegacySideQuest(v: unknown): boolean {
  return isObj(v) && typeof v['kind'] === 'string' && v['kind'] !== 'main';
}

/** 不是对象 → null；字段缺 / 类型不对 → 默认值 */
export function questFromJson(v: unknown): Quest | null {
  if (!isObj(v)) return null;
  return {
    serial: int(v, 'serial', 0),
    planIndex: int(v, 'planIndex', -1),
    planTotal: int(v, 'planTotal', 0),
    goalId: str(v, 'goalId', ''),
    name: str(v, 'name', ''),
    reason: str(v, 'reason', ''),
    proof: str(v, 'proof', ''),
    minutes: int(v, 'minutes', 15),
    rank: rank(v, 'rank', 'F'),
  };
}
