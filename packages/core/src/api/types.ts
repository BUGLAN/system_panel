/**
 * 前后端共用的接口契约（只有类型，不含实现）。
 * 服务端是权威：前端只发「意图」，拿回整份最新状态 + 这次顺带发生的事件。
 */
import type { QuestResult } from '../flow/types';
import type { Json } from '../save/json';

/** 读档走的是哪条路（backup = 主档坏了、已用备份恢复） */
export type SaveSource = 'primary' | 'backup' | 'none';

export interface StateView {
  /** 存档版本号：每写一次 +1 */
  version: number;
  /** 服务器时间（前端据此校时） */
  serverNow: number;
  /** 账号时区（换日 / 连胜按它算） */
  tz: string;
  source: SaveSource;
  /** saveToJson 的产物 */
  save: Json;
}

/** 懒判定顺带发生的事 */
export type FlowEvent = { kind: 'rollDay' };

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

// ── 账号 / 设置 / 证据（前端看到的形状）─────────────────────────

/** 告知文案有实质修改时 +1，已同意的人要重签（v2：数据改存服务器） */
export const CONSENT_VERSION = 2;

export interface MeView {
  username: string;
  role: 'admin' | 'user';
  tz: string;
  consent: { version: number; at: number } | null;
}

/** 模型设置（接口永远不回 Key 明文） */
export interface LlmSettingsView {
  useOwn: boolean;
  base: string;
  hasOwnKey: boolean;
  /** 末 4 位：…abcd */
  keyHint: string;
  textModel: string;
  visionModel: string;
  temperature: number;
  visionEnabled: boolean;
  /** 服务器默认配好了没有 */
  serverDefault: { text: boolean; vision: boolean };
}

export interface LlmSettingsForm {
  useOwn: boolean;
  base: string;
  /** 不传 = 不改；空串 = 清掉 */
  apiKey?: string;
  textModel: string;
  visionModel: string;
  temperature: number;
  visionEnabled: boolean;
}

export interface ProbeLine {
  ok: boolean;
  line: string;
}

export interface LlmTestView {
  mode: 'own' | 'server';
  text: ProbeLine;
  vision: ProbeLine;
}

export interface UsageView {
  day: string;
  used: { text: number; vision: number };
  /** null = 不限（自己的 Key / 管理员） */
  limits: { text: number; vision: number } | null;
}

/** 后台视觉校验的结论（SSE verdict） */
export interface VerdictEvent {
  id: string;
  serial: number;
  /** kept 照收 / rejected 不符撤槽 / gone 已交单或已撤，结论丢弃 */
  result: 'kept' | 'rejected' | 'gone';
  status: string;
  note: string;
}
