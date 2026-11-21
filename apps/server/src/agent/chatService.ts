/**
 * 聊天：人设 + 近 12 轮上下文 + 相关记忆 + 工具循环（最多 3 轮）。
 * 移植自 flutter-final:app/lib/chat/chat_service.dart。
 * 发送前先过本地自伤闸门：命中就不发 LLM，她认真回一句。
 */
import { pickBySeed } from '@host/core/data/lines';
import { CRISIS_CHAT_LINE, isCrisisText } from '@host/core/agent/guardrail';
import {
  CHAT_CONTEXT_TURNS,
  CHAT_MAX_TOOL_ROUNDS,
  CHAT_TIMEOUT_MS,
  FALLBACK_LINES,
  clampChat,
  sysMessage,
  type ChatMessage,
} from '@host/core/agent/chat';
import { buildConversation, splitTag, type WireMessage } from '@host/core/agent/persona';
import type { LlmClient } from './llmClient';
import type { MemoryStore } from './memory';
import type { ToolRegistry } from './tools';

export {
  CHAT_HISTORY_MAX,
  CHAT_MAX_CHARS,
  chatFromRow,
  hostMessage,
  sysMessage,
  type ChatMessage,
  type ChatToolCard,
} from '@host/core/agent/chat';

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
        out.push(sysMessage(clampChat(t.text), o.now(), { emotion: t.emotion }));
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
