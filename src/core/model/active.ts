/**
 * 正在执行的那一单 + 它的证据。移植自 flutter-final:app/lib/state/quest_flow.dart 的
 * ActiveQuest 与 agent/vision_core.dart 的 EvidenceShot。
 * 照片本体（压缩后的 JPEG Blob）存在 IndexedDB 的 evidence 表，这里只存 id 与校验状态。
 */
import { bool, int, isObj, str, arr, type Json } from '../save/json';
import { questFromJson, questToJson, type Quest } from './quest';

/**
 * verified 判真 / unsure 拿不准，照收 / unverified 没校验成，照收 / mismatch 不符，拒收
 */
export type EvidenceStatus = 'verified' | 'unsure' | 'unverified' | 'mismatch';

const STATUSES: readonly EvidenceStatus[] = ['verified', 'unsure', 'unverified', 'mismatch'];

/** 收不收：只有「不符」拒收 */
export function evidenceAccepted(s: EvidenceStatus): boolean {
  return s !== 'mismatch';
}

export interface EvidenceShot {
  /** 同时是 evidence 表里照片的主键 */
  id: string;
  status: EvidenceStatus;
  /** 校验结论附言（拒收原因 / 拿不准的理由） */
  note: string;
  /** 入槽时刻（epoch ms） */
  takenAt: number;
}

export interface ActiveQuest {
  task: Quest;
  /** 接单时刻（epoch ms）：计时 = 现在 − startAt，不是累加 */
  startAt: number;
  /** 本单已装载的道具 */
  dbl: boolean;
  crit: boolean;
  shield: boolean;
  /**
   * 护盾顺延的时长（毫秒，docs/01 Q3）：计时单到点时护盾碎掉、不判负，
   * 截止时间顺延 ceil(时长 ÷ 2) 分钟。0 = 没顺延过。
   */
  extraMs: number;
  evidence: EvidenceShot[];
  /** 交单即封存：之后迟到的校验结论一律丢弃（运行时字段，不进存档） */
  sealed: boolean;
}

export function evidenceToJson(e: EvidenceShot): Json {
  return { id: e.id, status: e.status, note: e.note, takenAt: e.takenAt };
}

export function evidenceFromJson(v: unknown): EvidenceShot | null {
  if (!isObj(v)) return null;
  const id = str(v, 'id', '');
  if (!id) return null;
  const status = str(v, 'status', 'unverified');
  return {
    id,
    status: (STATUSES as readonly string[]).includes(status)
      ? (status as EvidenceStatus)
      : 'unverified',
    note: str(v, 'note', ''),
    takenAt: int(v, 'takenAt', 0),
  };
}

export function activeToJson(a: ActiveQuest): Json {
  return {
    task: questToJson(a.task),
    startAt: a.startAt,
    ...(a.dbl ? { dbl: true } : {}),
    ...(a.crit ? { crit: true } : {}),
    ...(a.shield ? { shield: true } : {}),
    ...(a.extraMs > 0 ? { extraMs: a.extraMs } : {}),
    evidence: a.evidence.map(evidenceToJson),
  };
}

/** 形状不对 = 没有执行中的单 */
export function activeFromJson(v: unknown, now: number): ActiveQuest | null {
  if (!isObj(v)) return null;
  const task = questFromJson(v['task']);
  if (!task) return null;
  return {
    task,
    startAt: int(v, 'startAt', now),
    dbl: bool(v, 'dbl', false),
    crit: bool(v, 'crit', false),
    shield: bool(v, 'shield', false),
    extraMs: Math.max(0, int(v, 'extraMs', 0)),
    evidence: arr(v, 'evidence')
      .map(evidenceFromJson)
      .filter((e): e is EvidenceShot => e !== null),
    sealed: false,
  };
}
