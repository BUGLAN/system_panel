import { beforeEach, describe, expect, test } from 'vitest';
import { HostDb } from '../../src/store/db';
import {
  CONSENT_VERSION,
  appendChat,
  appendHistory,
  consentValid,
  loadChat,
  loadConsent,
  loadHistory,
  loadLlmSettings,
  loadPrefs,
  memoryBackend,
  saveConsent,
  saveLlmSettings,
  savePrefs,
  withdrawConsent,
} from '../../src/store/sideRepos';
import { MemoryStore } from '../../src/agent/memory';
import { hostMessage, sysMessage } from '../../src/agent/chatService';
import { T0 } from '@host/core/testing/fixtures';

let n = 0;
let db: HostDb;
beforeEach(() => {
  db = new HostDb(`side-${n++}`);
});

describe('LLM 设置 / 同意 / 偏好', () => {
  test('LLM 设置往返；缺省全空（没有任何默认 Key / 端点）', async () => {
    const d = await loadLlmSettings(db);
    expect([d.base, d.apiKey, d.textModel, d.visionModel]).toEqual(['', '', '', '']);
    await saveLlmSettings(db, {
      ...d,
      base: 'https://x/v1',
      apiKey: 'sk',
      textModel: 'a',
      visionModel: 'b',
      temperature: 5,
    });
    const back = await loadLlmSettings(db);
    expect(back).toMatchObject({ base: 'https://x/v1', textModel: 'a', temperature: 2 });
  });

  test('同意：版本对得上才算；撤回后无效', async () => {
    expect(consentValid(await loadConsent(db))).toBe(false);
    await saveConsent(db, T0);
    expect(await loadConsent(db)).toEqual({ version: CONSENT_VERSION, at: T0 });
    expect(consentValid({ version: CONSENT_VERSION + 1, at: T0 })).toBe(false);
    await withdrawConsent(db);
    expect(await loadConsent(db)).toBeNull();
  });

  test('偏好：音量夹 0~1', async () => {
    await savePrefs(db, { muted: true, volume: 3, installHintSeen: true });
    expect(await loadPrefs(db)).toEqual({ muted: true, volume: 1, installHintSeen: true });
  });
});

describe('记忆 / 聊天 / 流水', () => {
  test('记忆走 IndexedDB 后端', async () => {
    const m = new MemoryStore(memoryBackend(db), () => T0);
    await m.add('一周三次', 'interview', 2);
    expect(await new MemoryStore(memoryBackend(db)).digest('一周')).toBe('- 一周三次');
  });

  test('聊天往返（含工具卡）；超 200 条删最旧', async () => {
    await appendChat(db, [
      hostMessage('查状态', T0),
      sysMessage('LV1', T0, { tool: { name: 'get_status', ok: true, message: 'LV1' } }),
    ]);
    const back = await loadChat(db);
    expect(back.map((m) => [m.from, m.tool?.name ?? null])).toEqual([
      ['host', null],
      ['sys', 'get_status'],
    ]);
    await appendChat(
      db,
      Array.from({ length: 205 }, (_, i) => hostMessage(`m${i}`, T0 + i)),
    );
    const all = await loadChat(db);
    expect(all).toHaveLength(200);
    expect(all[all.length - 1]?.text).toBe('m204');
  });

  test('流水往返；按时间旧 → 新', async () => {
    await appendHistory(db, [
      {
        at: T0,
        name: 'a',
        rank: 'E',
        kind: 'daily',
        exp: 1,
        coin: 5,
        streak: 1,
        result: 'clear',
        attrs: { 力: 1 },
      },
      {
        at: T0 + 1,
        name: 'b',
        rank: 'D',
        kind: 'main',
        exp: 0,
        coin: 0,
        streak: 1,
        result: 'quit',
        attrs: {},
      },
    ]);
    expect((await loadHistory(db)).map((e) => e.name)).toEqual(['a', 'b']);
  });
});
