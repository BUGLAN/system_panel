/**
 * 聊天面板的编排：读记录、发送（自伤闸门 → LLM 工具循环）、落库。
 */
import { createStore } from 'zustand/vanilla';
import { useStore } from 'zustand';
import { chatTools, statusLineOf } from '../../agent/chatTools';
import { hostMessage, respondChat, type ChatMessage } from '../../agent/chatService';
import { appDb } from '../db';
import { game, historySync, now, setGame } from '../game';
import { memory, textClient } from '../services';
import { appendChat, loadChat } from '../sideRepos';
import { SCENES, uiStore } from '../uiStore';

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
  const messages = await loadChat(appDb());
  chatStore.setState({ loaded: true, messages });
}

export function clearChatState(): void {
  chatStore.setState({ loaded: true, sending: false, messages: [] });
}

function push(msgs: ChatMessage[]): void {
  chatStore.setState((s) => ({ messages: [...s.messages, ...msgs].slice(-200) }));
  void appendChat(appDb(), msgs).catch((e) => console.error('[chat] 落库失败', e));
}

export async function sendChat(text: string): Promise<void> {
  const t = text.trim();
  if (!t || chatStore.getState().sending) return;
  await ensureChatLoaded();
  const history = chatStore.getState().messages;
  push([hostMessage(t, now())]);
  chatStore.setState({ sending: true });
  try {
    const client = textClient();
    const tools = client
      ? chatTools({ read: game, commit: setGame, history: historySync, now }, memory())
      : null;
    const scene = SCENES[uiStore.getState().scene];
    const out = await respondChat({
      text: t,
      history,
      client,
      tools,
      memory: memory(),
      statusLine: statusLineOf(game()),
      scenario: `宿主在「${scene.title}」页打开了聊天。`,
      now,
    });
    push(out);
  } finally {
    chatStore.setState({ sending: false });
  }
}

/** 快捷查状态（本地工具，不调模型） */
export async function quickStatus(): Promise<void> {
  await ensureChatLoaded();
  const reg = chatTools({ read: game, commit: setGame, history: historySync, now }, memory());
  const oc = await reg.execute('get_status', {});
  push([
    hostMessage('查状态', now()),
    {
      id: `s${now()}`,
      from: 'sys',
      text: oc.message,
      at: now(),
      emotion: 'neutral',
      tool: {
        name: 'get_status',
        ok: oc.ok,
        message: oc.message,
        ...(oc.data ? { data: oc.data } : {}),
      },
    },
  ]);
}
