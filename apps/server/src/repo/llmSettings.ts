/**
 * 每个用户的模型设置（docs/05 第 1.5 节）：
 *  - useOwn = false：端点 / Key / 模型整套走服务器默认（环境变量）
 *  - useOwn = true：整套用自己填的（不允许「服务器的 Key + 自选模型」）
 *  - 温度、视觉校验开关是个人设置，两种模式都生效
 * Key 加密存库，接口永远不回明文（只回 hasOwnKey + 末 4 位）。
 */
import { eq } from 'drizzle-orm';
import type { Config } from '../config';
import type { Db } from '../db/client';
import { llmSettings } from '../db/schema';
import { decryptSecret, encryptSecret, keyHint } from '../llm/crypto';

export const DEFAULT_TEMPERATURE = 0.8;

export interface StoredSettings {
  useOwn: boolean;
  base: string;
  keyEnc: string;
  keyHint: string;
  textModel: string;
  visionModel: string;
  temperature: number;
  visionEnabled: boolean;
}

/** 给前端看的（没有 Key） */
export interface SettingsView {
  useOwn: boolean;
  base: string;
  hasOwnKey: boolean;
  keyHint: string;
  textModel: string;
  visionModel: string;
  temperature: number;
  visionEnabled: boolean;
  /** 服务器默认配好了没有（文本 / 视觉） */
  serverDefault: { text: boolean; vision: boolean };
}

/** 实际调用用的一套 */
export interface Effective {
  mode: 'own' | 'server';
  base: string;
  apiKey: string;
  textModel: string;
  visionModel: string;
  temperature: number;
  visionEnabled: boolean;
}

export function defaults(): StoredSettings {
  return {
    useOwn: false,
    base: '',
    keyEnc: '',
    keyHint: '',
    textModel: '',
    visionModel: '',
    temperature: DEFAULT_TEMPERATURE,
    visionEnabled: true,
  };
}

export function loadSettings(db: Db, userId: string): StoredSettings {
  const r = db.select().from(llmSettings).where(eq(llmSettings.userId, userId)).get();
  if (!r) return defaults();
  const { userId: _u, ...rest } = r;
  return rest;
}

export function settingsView(s: StoredSettings, cfg: Config): SettingsView {
  const d = cfg.llm;
  return {
    useOwn: s.useOwn,
    base: s.base,
    hasOwnKey: !!s.keyEnc,
    keyHint: s.keyHint,
    textModel: s.textModel,
    visionModel: s.visionModel,
    temperature: s.temperature,
    visionEnabled: s.visionEnabled,
    serverDefault: {
      text: !!(d.base && d.apiKey && d.textModel),
      vision: !!(d.base && d.apiKey && d.visionModel),
    },
  };
}

export interface SettingsInput {
  useOwn: boolean;
  base: string;
  /** undefined = 不改；'' = 清掉 */
  apiKey?: string | undefined;
  textModel: string;
  visionModel: string;
  temperature: number;
  visionEnabled: boolean;
}

/** 表单 + 已存的 → 新的一份（Key 留空 = 不改） */
export function mergeInput(prev: StoredSettings, i: SettingsInput, key: Buffer): StoredSettings {
  const k = i.apiKey;
  return {
    useOwn: i.useOwn,
    base: i.base.trim(),
    keyEnc: k === undefined ? prev.keyEnc : k.trim() ? encryptSecret(k.trim(), key) : '',
    keyHint: k === undefined ? prev.keyHint : k.trim() ? keyHint(k) : '',
    textModel: i.textModel.trim(),
    visionModel: i.visionModel.trim(),
    temperature: Math.min(2, Math.max(0, i.temperature)),
    visionEnabled: i.visionEnabled,
  };
}

export function saveSettings(db: Db, userId: string, s: StoredSettings): void {
  db.insert(llmSettings)
    .values({ userId, ...s })
    .onConflictDoUpdate({ target: llmSettings.userId, set: s })
    .run();
}

export function effective(s: StoredSettings, cfg: Config): Effective {
  const common = { temperature: s.temperature, visionEnabled: s.visionEnabled };
  if (s.useOwn) {
    return {
      mode: 'own',
      base: s.base,
      apiKey: s.keyEnc ? (decryptSecret(s.keyEnc, cfg.encryptionKey) ?? '') : '',
      textModel: s.textModel,
      visionModel: s.visionModel,
      ...common,
    };
  }
  return { mode: 'server', ...cfg.llm, ...common };
}
