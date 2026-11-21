/**
 * LLM 设置（用户自填，存在本机 IndexedDB，浏览器直连）。
 * 前端代码和构建产物里没有任何默认 Key / 默认端点。
 */
import { isObj } from '@host/core/save/json';

export interface LlmSettings {
  /** OpenAI 兼容端点（…/v1） */
  base: string;
  apiKey: string;
  /** 文本模型（拆解 / 聊天 / 台词） */
  textModel: string;
  /** 视觉模型（证据校验） */
  visionModel: string;
  /** 温度（台词 / 聊天用；拆解 0.7、匹配 0.3、视觉 0 由调用点覆盖） */
  temperature: number;
  /** 证据视觉校验开关（G2.3） */
  visionEnabled: boolean;
}

export const DEFAULT_TEMPERATURE = 0.8;

export function emptySettings(): LlmSettings {
  return {
    base: '',
    apiKey: '',
    textModel: '',
    visionModel: '',
    temperature: DEFAULT_TEMPERATURE,
    visionEnabled: true,
  };
}

export function settingsFromJson(v: unknown): LlmSettings {
  const d = emptySettings();
  if (!isObj(v)) return d;
  const s = (k: string) => (typeof v[k] === 'string' ? (v[k] as string).trim() : '');
  const t = typeof v['temperature'] === 'number' ? (v['temperature'] as number) : d.temperature;
  return {
    base: s('base'),
    apiKey: s('apiKey'),
    textModel: s('textModel'),
    visionModel: s('visionModel'),
    temperature: Math.min(2, Math.max(0, t)),
    visionEnabled: typeof v['visionEnabled'] === 'boolean' ? v['visionEnabled'] : true,
  };
}

/** 能发文本请求了吗（端点 + Key + 文本模型都填了） */
export function textReady(s: LlmSettings): boolean {
  return !!(s.base && s.apiKey && s.textModel);
}

/** 视觉校验能用吗 */
export function visionReady(s: LlmSettings): boolean {
  return s.visionEnabled && !!(s.base && s.apiKey && s.visionModel);
}

/** 端点 → …/chat/completions */
export function chatEndpoint(base: string): string {
  let b = base.trim();
  while (b.endsWith('/')) b = b.slice(0, -1);
  if (b.endsWith('/chat/completions')) return b;
  return `${b}/chat/completions`;
}
