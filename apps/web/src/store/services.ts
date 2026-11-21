/**
 * 运行时服务：账号（我是谁 / 同意记录）、模型设置（服务端存，Key 不回浏览器）、本机偏好（音量等）。
 */
import { createStore } from 'zustand/vanilla';
import { useStore } from 'zustand';
import {
  CONSENT_VERSION,
  type LlmSettingsForm,
  type LlmSettingsView,
  type LlmTestView,
  type MeView,
  type UsageView,
} from '@host/core/api/types';
import { sfx } from '../audio/sfx';
import { api } from './api';
import { defaultPrefs, loadPrefs, rememberMe, savePrefs, type Prefs } from './cache';
import { syncStore } from './game';

export interface ServicesState {
  loaded: boolean;
  /** 模型设置（打开设置页时拉；没拉过 = null） */
  llm: LlmSettingsView | null;
  prefs: Prefs;
}

export const servicesStore = createStore<ServicesState>()(() => ({
  loaded: false,
  llm: null,
  prefs: defaultPrefs(),
}));

export function useServices<T>(sel: (s: ServicesState) => T): T {
  return useStore(servicesStore, sel);
}

export async function loadServices(): Promise<void> {
  const prefs = await loadPrefs();
  servicesStore.setState({ loaded: true, prefs });
  sfx.setMuted(prefs.muted);
  sfx.setVolume(prefs.volume);
}

export const me = () => syncStore.getState().me;

export function setMe(m: MeView | null): void {
  syncStore.setState({ me: m });
  if (m) void rememberMe(m);
}

export const hasConsent = () => me()?.consent?.version === CONSENT_VERSION;

export async function giveConsent(): Promise<void> {
  const r = await api<{ me: MeView }>('POST', '/api/consent');
  setMe(r.me);
}

export async function revokeConsent(): Promise<void> {
  const r = await api<{ me: MeView }>('DELETE', '/api/consent');
  setMe(r.me);
}

export async function loadLlmSettings(): Promise<LlmSettingsView | null> {
  try {
    const r = await api<{ settings: LlmSettingsView }>('GET', '/api/llm/settings');
    servicesStore.setState({ llm: r.settings });
    return r.settings;
  } catch {
    return servicesStore.getState().llm;
  }
}

export async function saveLlmSettings(f: LlmSettingsForm): Promise<LlmSettingsView> {
  const r = await api<{ settings: LlmSettingsView }>('PUT', '/api/llm/settings', f);
  servicesStore.setState({ llm: r.settings });
  return r.settings;
}

/** 由已存的设置拼一份表单（Key 不带 = 不改） */
export function formOf(s: LlmSettingsView): LlmSettingsForm {
  return {
    useOwn: s.useOwn,
    base: s.base,
    textModel: s.textModel,
    visionModel: s.visionModel,
    temperature: s.temperature,
    visionEnabled: s.visionEnabled,
  };
}

export const testLlm = (f: LlmSettingsForm) => api<LlmTestView>('POST', '/api/llm/test', f);
export const llmUsage = () => api<UsageView>('GET', '/api/llm/usage');

export async function setPrefs(p: Partial<Prefs>): Promise<void> {
  const next = { ...servicesStore.getState().prefs, ...p };
  servicesStore.setState({ prefs: next });
  sfx.setMuted(next.muted);
  sfx.setVolume(next.volume);
  await savePrefs(next);
}
