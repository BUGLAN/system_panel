/**
 * 一单委托（计时单 / 打卡单）。移植自 flutter-final:app/lib/state/quest.dart。
 * 这里只放数据形状与存档读写；文案读数（kindLabel / timeLabel …）在 core/flow。
 */
import type { AttrMap } from '../data/attrs';
import type { Rank } from '../data/rank';
import { attrMap, bool, int, isObj, rank, str, type Json } from '../save/json';

/** main 主线 / daily 日常 / remedy 补救 */
export type QuestKind = 'main' | 'daily' | 'remedy';

export interface Quest {
  /** 单号（显示为 № 0041） */
  serial: number;
  kind: QuestKind;
  /** 主线清单里第几张（0 基；日常 / 不顶替主线的补救 = -1） */
  planIndex: number;
  /** 整条主线一共几张 */
  planTotal: number;
  /** 属于哪个目标（Goal id；日常 / 普通补救 = ''） */
  goalId: string;
  name: string;
  /** 她的附言（可以为空） */
  reason: string;
  /** 证据要求 */
  proof: string;
  /** 时限（分钟）；打卡单只作预计耗时参考 */
  minutes: number;
  rank: Rank;
  /** 六维加成，如 { 力: 1, 体: 1 } */
  attrs: AttrMap;
  /** 「她替你留的」日常（只影响 kindLabel 文案） */
  hinted: boolean;
  /** true = 计时单（倒计时、到点判负）；false = 打卡单（不计时，当天内随时交） */
  timed: boolean;
}

const KINDS: readonly QuestKind[] = ['main', 'daily', 'remedy'];

export function questToJson(q: Quest): Json {
  return {
    serial: q.serial,
    kind: q.kind,
    planIndex: q.planIndex,
    planTotal: q.planTotal,
    ...(q.goalId ? { goalId: q.goalId } : {}),
    name: q.name,
    reason: q.reason,
    proof: q.proof,
    minutes: q.minutes,
    ...(q.timed ? {} : { mode: 'checkin' }),
    rank: q.rank,
    attrs: { ...q.attrs },
    ...(q.hinted ? { hinted: true } : {}),
  };
}

/** 不是对象 → null；字段缺 / 类型不对 → 默认值 */
export function questFromJson(v: unknown): Quest | null {
  if (!isObj(v)) return null;
  const kind = str(v, 'kind', 'daily');
  return {
    serial: int(v, 'serial', 0),
    kind: (KINDS as readonly string[]).includes(kind) ? (kind as QuestKind) : 'daily',
    planIndex: int(v, 'planIndex', -1),
    planTotal: int(v, 'planTotal', 0),
    goalId: str(v, 'goalId', ''),
    name: str(v, 'name', ''),
    reason: str(v, 'reason', ''),
    proof: str(v, 'proof', ''),
    minutes: int(v, 'minutes', 15),
    rank: rank(v, 'rank', 'F'),
    attrs: attrMap(v, 'attrs', {}),
    hinted: bool(v, 'hinted', false),
    timed: v['mode'] !== 'checkin',
  };
}
