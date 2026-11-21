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

// ── 拆解任务（docs/05 第 1.5 节：提交任务 → SSE 收进度 → 完成 / 失败）──────────

/** 加载卡的分步进度：0 匹配 → 1 拆解（含段进度）→ 2 校验 */
export interface PlanProgress {
  stage: 0 | 1 | 2;
  segDone?: number;
  segTotal?: number;
}

/** bind 首目标 / retry 重试记着的目标 / swap 换目标 / resume 当场补拆 / window 续拆 / finale 收官铸下一条 */
export type PlanJobKind = 'bind' | 'retry' | 'swap' | 'resume' | 'window' | 'finale';

export interface PlanJobView {
  id: string;
  kind: PlanJobKind;
  status: 'running' | 'done' | 'failed';
  progress: PlanProgress;
  /** 失败时：PlanFailureCode + 细节（失败卡按 code 出标题和她那句） */
  failure: { code: string; detail: string } | null;
  /** 成功落库后的最新状态 */
  state: StateView | null;
  startedAt: number;
  finishedAt: number | null;
}

/** 匹配类目的结果（绑定仪式第一步） */
export interface MatchView {
  catId: string;
  short: string;
  days: number;
  quota: number;
}
