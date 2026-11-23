/**
 * 存档模型：宿主档案 + 主线 + 她手里的队列 + 执行中单据 + 流程运行时字段。
 *
 * 规则（移植自 flutter-final:app/lib/state/save_file.dart，去掉旧档迁移）：
 *  - 在默认值上合并：缺字段 / 类型不对走默认，新增字段不会让旧档读崩
 *  - 版本号 `v`：比本 App 认识的版本新 → 视为读不懂（导入时拒收，读档时当坏档）
 *  - 旧版只活在内存里的运行时字段（最近完成日、上次换日）全部入档，
 *    否则重启后下一单的连胜会被算成 1（docs/01 第 3 节）
 *  - 旧档里已拿掉的玩法字段（晶核、道具、称号、日常 / 补救单…）读档时直接丢掉
 */
import { activeFromJson, activeToJson, type ActiveQuest } from '../model/active';
import { emptyGoal, goalFromJson, goalToJson, type Goal } from '../model/goal';
import { emptyHost, hostFromJson, hostToJson, type HostState } from '../model/host';
import { isLegacySideQuest, questFromJson, questToJson, type Quest } from '../model/quest';
import { isDayKey, type DayKey } from '../time/day';
import { arr, int, intOrNull, isObj, str, type Json } from './json';

/** 当前存档结构版本 */
export const SAVE_VERSION = 1;

/** 新单号从 41 起（与旧版一致） */
export const FIRST_SERIAL = 41;

/** 流程运行时字段（QuestFlow 的私有态，旧版没落盘的那些） */
export interface FlowMeta {
  /** 下一张单的单号 */
  nextSerial: number;
  /** 最近一次完成委托的日历日（连胜判定） */
  lastDoneDay: DayKey | null;
  /** 上次换日的日历日（同一天反复进出不重复换日） */
  lastRollDay: DayKey | null;
}

export interface SaveData {
  v: number;
  host: HostState;
  goal: Goal;
  /** 她手里还没接的单（队首 = 下一单） */
  queue: Quest[];
  active: ActiveQuest | null;
  /** 拆解失败「先跳过」时记下的那句目标（空串 = 没有） */
  pendingGoal: string;
  meta: FlowMeta;
  /** 上次离开的时刻（存盘时盖戳；回来时算「你走了多久」） */
  lastSeen: number | null;
}

export function freshMeta(): FlowMeta {
  return {
    nextSerial: FIRST_SERIAL,
    lastDoneDay: null,
    lastRollDay: null,
  };
}

/** 全新档 = 未绑定 */
export function freshSave(now: number): SaveData {
  return {
    v: SAVE_VERSION,
    host: emptyHost(),
    goal: emptyGoal(now),
    queue: [],
    active: null,
    pendingGoal: '',
    meta: freshMeta(),
    lastSeen: null,
  };
}

function dayOrNull(j: Json, k: string): DayKey | null {
  const v = j[k];
  return isDayKey(v) ? v : null;
}

function metaFromJson(v: unknown): FlowMeta {
  const def = freshMeta();
  if (!isObj(v)) return def;
  return {
    nextSerial: Math.max(FIRST_SERIAL, int(v, 'nextSerial', def.nextSerial)),
    lastDoneDay: dayOrNull(v, 'lastDoneDay'),
    lastRollDay: dayOrNull(v, 'lastRollDay'),
  };
}

function metaToJson(m: FlowMeta): Json {
  return {
    nextSerial: m.nextSerial,
    lastDoneDay: m.lastDoneDay,
    lastRollDay: m.lastRollDay,
  };
}

export function saveToJson(s: SaveData): Json {
  return {
    v: SAVE_VERSION,
    host: hostToJson(s.host),
    goal: goalToJson(s.goal),
    queue: s.queue.map(questToJson),
    ...(s.active ? { active: activeToJson(s.active) } : {}),
    ...(s.pendingGoal ? { pendingGoal: s.pendingGoal } : {}),
    meta: metaToJson(s.meta),
    ...(s.lastSeen !== null ? { lastSeen: s.lastSeen } : {}),
  };
}

/**
 * 解析存档对象。不是对象 / 版本比本 App 新 → null（读不懂）；
 * 其余字段缺 / 坏一律走默认。
 */
export function saveFromJson(v: unknown, now: number): SaveData | null {
  if (!isObj(v)) return null;
  const ver = int(v, 'v', SAVE_VERSION);
  if (ver > SAVE_VERSION || ver < 1) return null;
  const queue = arr(v, 'queue')
    .filter((q) => !isLegacySideQuest(q))
    .map(questFromJson)
    .filter((q): q is Quest => q !== null);
  const active = activeFromJson(v['active'], now);
  const meta = metaFromJson(v['meta']);
  // 单号兜底：绝不与存档里已有的单撞号
  let maxSerial = meta.nextSerial - 1;
  for (const q of queue) maxSerial = Math.max(maxSerial, q.serial);
  if (active) maxSerial = Math.max(maxSerial, active.task.serial);
  meta.nextSerial = maxSerial + 1;
  const goal = goalFromJson(v['goal'], now);
  return {
    v: SAVE_VERSION,
    host: hostFromJson(v['host']),
    goal,
    queue,
    active,
    // 已经有主线了，记着的那句就没用了（防脏档：主线 + 待拆目标并存）
    pendingGoal: goal.plan.length ? '' : str(v, 'pendingGoal', '').trim(),
    meta,
    lastSeen: intOrNull(v, 'lastSeen'),
  };
}

/** 字符串 → 存档；JSON 坏 / 读不懂 → null */
export function parseSave(raw: string, now: number): SaveData | null {
  if (!raw) return null;
  try {
    return saveFromJson(JSON.parse(raw), now);
  } catch {
    return null;
  }
}

/** 存档 → 字符串（盖上 lastSeen 时间戳） */
export function stringifySave(s: SaveData, now: number): string {
  return JSON.stringify(saveToJson({ ...s, lastSeen: now }));
}
