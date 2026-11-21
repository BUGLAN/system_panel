/**
 * 聊天：人设 + 近 12 轮上下文 + 相关记忆 + 工具循环（最多 3 轮）。
 * 移植自 flutter-final:app/lib/chat/chat_service.dart。
 * 发送前先过本地自伤闸门：命中就不发 LLM，她认真回一句。
 */
import { pickBySeed } from '@host/core/data/lines';
import { CRISIS_CHAT_LINE, isCrisisText } from './guardrail';
import type { LlmClient } from './llmClient';
import type { MemoryStore } from './memory';
import { buildConversation, splitTag, type Emotion, type WireMessage } from './persona';
import type { ToolRegistry } from './tools';

/** 聊天输入上限（只数已上屏的字） */
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

const clamp = (s: string) => (s.length > 300 ? s.slice(0, 300) : s);

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

function fallback(seed: string, why: string, now: number): ChatMessage {
  const line = pickBySeed(FALLBACK_LINES, `${seed}|${FALLBACK_LINES.length}`);
  const short = why.length > 60 ? `${why.slice(0, 60)}…` : why;
  return sysMessage(`${line}（${short}）`, now, { emotion: 'annoyed', kind: 'fallback' });
}

export async function respondChat(o: {
  text: string;
  history: ChatMessage[];
  client: LlmClient | null;
  tools: ToolRegistry | null;
  memory?: MemoryStore | null;
  statusLine?: string;
  scenario?: string;
  now: () => number;
}): Promise<ChatMessage[]> {
  const text = o.text.trim();
  if (isCrisisText(text)) {
    return [sysMessage(CRISIS_CHAT_LINE, o.now(), { emotion: 'focus', kind: 'care' })];
  }
  if (!o.client?.configured)
    return [fallback(text, '还没配好模型（去设置里填端点、Key、模型）', o.now())];
  try {
    const wire: WireMessage[] = o.history
      .filter((m) => !m.tool)
      .slice(-CHAT_CONTEXT_TURNS)
      .map((m) => ({ role: m.from === 'host' ? 'user' : 'assistant', text: m.text }));
    const digest = o.memory ? await o.memory.digest(text) : '';
    const msgs = buildConversation({
      userText: text,
      history: wire,
      ...(o.statusLine ? { statusLine: o.statusLine } : {}),
      memoryDigest: digest,
      ...(o.scenario ? { scenario: o.scenario } : {}),
    });
    const out: ChatMessage[] = [];
    for (let round = 0; round < CHAT_MAX_TOOL_ROUNDS; round++) {
      const r = await o.client.chat({
        messages: msgs.map((m) => ({ role: m.role, text: m.text })),
        ...(o.tools?.size ? { tools: o.tools.defs() } : {}),
        timeoutMs: CHAT_TIMEOUT_MS,
      });
      if (!r.ok) {
        out.push(fallback(text, r.detail, o.now()));
        return out;
      }
      if (!r.toolCalls.length || !o.tools) {
        const t = splitTag(r.text);
        if (!t.text) {
          out.push(fallback(text, '正文为空', o.now()));
          return out;
        }
        out.push(sysMessage(clamp(t.text), o.now(), { emotion: t.emotion }));
        return out;
      }
      const receipts: string[] = [];
      for (const c of r.toolCalls) {
        const oc = await o.tools.execute(c.name, c.arguments);
        receipts.push(`${c.name}：${oc.message}`);
        out.push(
          sysMessage(oc.message, o.now(), {
            tool: {
              name: c.name,
              ok: oc.ok,
              message: oc.message,
              ...(oc.data ? { data: oc.data } : {}),
            },
          }),
        );
      }
      msgs.push({ role: 'assistant', text: r.text.trim() || '（正在翻你的档案……）' });
      msgs.push({
        role: 'user',
        text: `〔系统回执 · 刚才的工具调用结果，供你作答〕\n${receipts.join('\n')}`,
      });
    }
    out.push(fallback(text, `工具循环 ${CHAT_MAX_TOOL_ROUNDS} 轮用尽仍没有终答`, o.now()));
    return out;
  } catch (e) {
    return [fallback(text, `异常：${e instanceof Error ? e.message : String(e)}`, o.now())];
  }
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
