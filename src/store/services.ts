/**
 * 运行时服务：LLM 设置 / 同意记录 / 偏好（各自独立存，重置不清）、长期记忆、LLM 客户端工厂。
 */
import { createStore } from 'zustand/vanilla';
import { useStore } from 'zustand';
import { LlmClient } from '../agent/llmClient';
import { MemoryStore } from '../agent/memory';
import { SystemCopy } from '../agent/copy';
import { emptySettings, textReady, visionReady, type LlmSettings } from '../agent/settings';
import { sfx } from '../audio/sfx';
import { appDb } from './db';
import {
  consentValid,
  defaultPrefs,
  loadConsent,
  loadLlmSettings,
  loadPrefs,
  memoryBackend,
  saveConsent,
  saveLlmSettings,
  savePrefs,
  withdrawConsent,
  type ConsentRecord,
  type Prefs,
} from './sideRepos';

export interface ServicesState {
  loaded: boolean;
  llm: LlmSettings;
  consent: ConsentRecord | null;
  prefs: Prefs;
}

export const servicesStore = createStore<ServicesState>()(() => ({
  loaded: false,
  llm: emptySettings(),
  consent: null,
  prefs: defaultPrefs(),
}));

export function useServices<T>(sel: (s: ServicesState) => T): T {
  return useStore(servicesStore, sel);
}

export async function loadServices(): Promise<void> {
  const db = appDb();
  const [llm, consent, prefs] = await Promise.all([
    loadLlmSettings(db),
    loadConsent(db),
    loadPrefs(db),
  ]);
  servicesStore.setState({ loaded: true, llm, consent, prefs });
  sfx.setMuted(prefs.muted);
  sfx.setVolume(prefs.volume);
}

export const hasConsent = () => consentValid(servicesStore.getState().consent);

export async function setLlmSettings(s: LlmSettings): Promise<void> {
  servicesStore.setState({ llm: s });
  await saveLlmSettings(appDb(), s);
}

export async function giveConsent(): Promise<void> {
  const rec = await saveConsent(appDb(), Date.now());
  servicesStore.setState({ consent: rec });
}

export async function revokeConsent(): Promise<void> {
  await withdrawConsent(appDb());
  servicesStore.setState({ consent: null });
}

export async function setPrefs(p: Partial<Prefs>): Promise<void> {
  const next = { ...servicesStore.getState().prefs, ...p };
  servicesStore.setState({ prefs: next });
  sfx.setMuted(next.muted);
  sfx.setVolume(next.volume);
  await savePrefs(appDb(), next);
}

function client(model: string, temperature?: number): LlmClient {
  const s = servicesStore.getState().llm;
  return new LlmClient(
    {
      base: s.base,
      apiKey: s.apiKey,
      model,
      ...(temperature !== undefined ? { temperature } : {}),
    },
    { consent: hasConsent },
  );
}

/** 文本模型客户端（端点 / Key / 模型没填全 = null，但 noKey 由调用方按失败卡处理时可用 textClientAny） */
export function textClient(): LlmClient | null {
  const s = servicesStore.getState().llm;
  return textReady(s) ? client(s.textModel, s.temperature) : null;
}

/** 不管填没填全都给一个（拆解链路要拿到 noKey 失败去走失败卡） */
export function textClientAny(): LlmClient {
  const s = servicesStore.getState().llm;
  return client(s.textModel, s.temperature);
}

/** 视觉校验客户端（开关关了 / 没配视觉模型 = null → 证据按未校验照收） */
export function visionClient(): LlmClient | null {
  const s = servicesStore.getState().llm;
  return visionReady(s) ? client(s.visionModel) : null;
}

let mem: MemoryStore | null = null;
export function memory(): MemoryStore {
  mem ??= new MemoryStore(memoryBackend(appDb()));
  return mem;
}

export function copy(): SystemCopy {
  return new SystemCopy(textClient(), memory());
}
