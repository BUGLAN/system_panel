/**
 * 聊天消息的形状与常量（前端渲染、服务端落库共用）。
 */
import type { Emotion } from './persona';

export const CHAT_MAX_CHARS = 200;
export const CHAT_MAX_TOOL_ROUNDS = 3;
export const CHAT_TIMEOUT_MS = 45_000;
export const CHAT_CONTEXT_TURNS = 12;
export const CHAT_HISTORY_MAX = 200;

export interface ChatToolCard {
  name: string;
  ok: boolean;
  message: string;
  data?: Record<string, unknown>;
}

export interface ChatMessage {
  id: string;
  from: 'host' | 'sys';
  text: string;
  at: number;
  emotion: Emotion;
  /** 工具回执（渲染成卡片，不念原文） */
  tool?: ChatToolCard;
  /** fallback = 连不上时的兜底台词；care = 自伤闸门的认真回应 */
  kind?: 'fallback' | 'care';
}

export const FALLBACK_LINES: readonly string[] = [
  '线路断了。……正好，省得你拿「在聊」当「在做」。先把今天那单交了。',
  '这会儿连不上我。连不上也得干活——你手里那单不会自己完成。',
  '……嘴暂时借不到网。跑步、背书、收拾屋子，挑一样，现在。',
  '回复晚点补。不过「等回复」不在今天的清单里，你的单在。',
  '信号不好，听不清。目标可没信号问题——它还在原地等你。',
];

let seq = 0;
const newId = (now: number) => `c${now.toString(36)}_${seq++}`;

export const clampChat = (s: string) => (s.length > 300 ? s.slice(0, 300) : s);

export function hostMessage(text: string, now: number): ChatMessage {
  return { id: newId(now), from: 'host', text, at: now, emotion: 'neutral' };
}

export function sysMessage(
  text: string,
  now: number,
  extra: Partial<ChatMessage> = {},
): ChatMessage {
  return { id: newId(now), from: 'sys', text, at: now, emotion: 'neutral', ...extra };
}

/** 读一行聊天记录（坏行 = null） */
export function chatFromRow(v: unknown): ChatMessage | null {
  if (!v || typeof v !== 'object') return null;
  const o = v as Record<string, unknown>;
  if (typeof o['text'] !== 'string') return null;
  return {
    id: typeof o['id'] === 'string' ? o['id'] : newId(0),
    from: o['from'] === 'sys' ? 'sys' : 'host',
    text: o['text'],
    at: typeof o['at'] === 'number' ? o['at'] : 0,
    emotion: typeof o['emotion'] === 'string' ? (o['emotion'] as Emotion) : 'neutral',
    ...(o['tool'] && typeof o['tool'] === 'object' ? { tool: o['tool'] as ChatToolCard } : {}),
    ...(o['kind'] === 'fallback' || o['kind'] === 'care' ? { kind: o['kind'] } : {}),
  };
}
