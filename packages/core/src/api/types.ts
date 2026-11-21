/**
 * 前后端共用的接口契约（只有类型，不含实现）。
 * 服务端是权威：前端只发「意图」，拿回整份最新状态 + 这次顺带发生的事件。
 */
import type { FailOutcome, QuestResult } from '../flow/types';
import type { Json } from '../save/json';

/** 读档走的是哪条路（backup = 主档坏了、已用备份恢复） */
export type SaveSource = 'primary' | 'backup' | 'none';

export interface StateView {
  /** 存档版本号：每写一次 +1 */
  version: number;
  /** 服务器时间（前端据此校时，计时走秒用） */
  serverNow: number;
  /** 账号时区（换日 / 连胜 / 补签按它算） */
  tz: string;
  source: SaveSource;
  /** saveToJson 的产物 */
  save: Json;
}

/** 懒判定顺带发生的事（与旧版每秒回调里的分支一一对应） */
export type FlowEvent =
  | { kind: 'rollDay' }
  /** 计时单到点，护盾挡下：截止顺延 extendMin 分钟 */
  | { kind: 'shield'; extendMin: number }
  /** 计时单到点判负 */
  | { kind: 'timeout'; outcome: FailOutcome };

export interface IntentOk {
  ok: true;
  state: StateView;
  events: FlowEvent[];
}

export interface ApiFail {
  ok: false;
  code: string;
  message: string;
  /** 409 stale 时附带最新状态 */
  state?: StateView;
  retryAfterSec?: number;
}

export interface SubmitOk extends IntentOk {
  result: QuestResult;
  /** 这一单走完了窗口 / 收官：续拆任务 id（前端等它结束再演结算） */
  followUp: { jobId: string } | null;
}

export interface GiveUpOk extends IntentOk {
  outcome: FailOutcome;
}

/** 写意图去重用的请求头 */
export const INTENT_HEADER = 'x-intent-id';
