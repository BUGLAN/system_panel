/**
 * 聊天面板的编排：读记录、发送（自伤闸门先在本机拦一次，服务端再兜底 → LLM 工具循环）。
 * 记录存在服务器；会改存档的工具在服务端执行，回来的最新状态自动落到本地。
 */
import { createStore } from 'zustand/vanilla';
import { useStore } from 'zustand';
import { CRISIS_CHAT_LINE, isCrisisText } from '@host/core/agent/guardrail';
import { hostMessage, sysMessage, type ChatMessage } from '@host/core/agent/chat';
import { api } from '../api';
import { now } from '../game';
import { SCENES, toast, uiStore } from '../uiStore';

export interface ChatState {
  loaded: boolean;
  sending: boolean;
  messages: ChatMessage[];
}

export const chatStore = createStore<ChatState>()(() => ({
  loaded: false,
  sending: false,
  messages: [],
}));
export const useChat = <T>(sel: (s: ChatState) => T) => useStore(chatStore, sel);

export async function ensureChatLoaded(): Promise<void> {
  if (chatStore.getState().loaded) return;
  try {
    const r = await api<{ messages: ChatMessage[] }>('GET', '/api/chat');
    chatStore.setState({ loaded: true, messages: r.messages });
  } catch (e) {
    toast(e instanceof Error ? e.message : '聊天记录读不出来。', 'err');
  }
}

export function clearChatState(): void {
  chatStore.setState({ loaded: false, sending: false, messages: [] });
}

function push(msgs: ChatMessage[]): void {
  chatStore.setState((s) => ({ messages: [...s.messages, ...msgs].slice(-200) }));
}

export async function sendChat(text: string): Promise<void> {
  const t = text.trim();
  if (!t || chatStore.getState().sending) return;
  await ensureChatLoaded();
  // 本机先拦：命中就当场回应（服务端也会拦，并把这两句记进记录）
  if (isCrisisText(t)) {
    push([
      hostMessage(t, now()),
      sysMessage(CRISIS_CHAT_LINE, now(), { emotion: 'focus', kind: 'care' }),
    ]);
  }
  const optimistic = isCrisisText(t) ? null : hostMessage(t, now());
  if (optimistic) push([optimistic]);
  chatStore.setState({ sending: true });
  try {
    const scene = SCENES[uiStore.getState().scene];
    const r = await api<{ messages: ChatMessage[] }>('POST', '/api/chat', {
      text: t,
      scene: scene.title,
    });
    // 服务端回的第一条是宿主这句（已落库），换掉本机先放上去的那条
    const [mine, ...rest] = r.messages;
    chatStore.setState((s) => ({
      messages: s.messages.map((m) => (optimistic && m.id === optimistic.id && mine ? mine : m)),
    }));
    if (!isCrisisText(t)) push(rest);
  } catch (e) {
    toast(e instanceof Error ? e.message : '没发出去。', 'err');
  } finally {
    chatStore.setState({ sending: false });
  }
}

/** 快捷查状态（服务端本地工具，不调模型） */
export async function quickStatus(): Promise<void> {
  await ensureChatLoaded();
  try {
    const r = await api<{ messages: ChatMessage[] }>('POST', '/api/chat/status');
    push(r.messages);
  } catch (e) {
    toast(e instanceof Error ? e.message : '查不到。', 'err');
  }
}
