import { describe, expect, test } from 'vitest';
import {
  CRISIS_CARE_LINE,
  CRISIS_CHAT_LINE,
  isCrisisText,
  refusalOf,
} from '../../src/agent/guardrail';
import { BACKSTORY, buildConversation, splitTag, systemPrompt } from '../../src/agent/persona';
import { parseVerdict, verifyEvidence } from '../../src/agent/vision';
import { MemoryStore, keywords, memoryBackendInMemory } from '../../src/agent/memory';
import { respondChat } from '../../src/agent/chatService';
import { chatTools, statusLineOf } from '../../src/agent/chatTools';
import { SystemCopy, emptyCopyContext, fillCopy, tierOf } from '../../src/agent/copy';
import { COPY } from '../../src/core/data/lines';
import { boundSave } from '../core/helpers';
import { quest, T0 } from '../fixtures';
import { fakeClient, fakeEndpoint } from './fakeLlm';
import type { SaveData } from '../../src/core/save/saveData';

describe('人设', () => {
  test('系统提示词以 backstory 原文开头，带四语气与铁律', () => {
    const p = systemPrompt({ statusLine: 'LV1' });
    expect(p.startsWith(BACKSTORY)).toBe(true);
    expect(p).toContain('【四种固定语气】');
    expect(p).toContain('不超过 3 句');
    expect(p).toContain('【长期记忆】（暂无）');
    expect(buildConversation({ userText: 'hi' }).map((m) => m.role)).toEqual(['system', 'user']);
  });

  test('情绪标签：取第一个已知标签，行首标签都剥掉；未知标签也剥', () => {
    expect(splitTag('[smug]哼。')).toEqual({ text: '哼。', emotion: 'smug' });
    expect(splitTag('第一句。\n[focus] 下一步只做一件。')).toEqual({
      text: '第一句。\n下一步只做一件。',
      emotion: 'focus',
    });
    expect(splitTag('[weird]你好')).toEqual({ text: '你好', emotion: 'neutral' });
    expect(splitTag('[cold]')).toEqual({ text: '', emotion: 'cold' });
  });
});

describe('护栏', () => {
  test('明确的自伤 / 自杀表达 → 命中', () => {
    for (const s of [
      '我不想活了',
      '不想活下去',
      '想自杀',
      '自 杀',
      '割腕',
      '我想死',
      '好想死啊。',
      '想死，好累',
      '活着没意思',
      '活着没有意义',
      '结束自己的生命',
      '一个月内了结自己',
      '三个月不再自残',
      '从楼上跳楼',
      'I want to kill myself',
      'thinking about suicide',
      'stop self-harm',
      'I want to die',
    ]) {
      expect(isCrisisText(s), s).toBe(true);
    }
  });

  test('口语夸张、同形词、正常目标 → 不误伤', () => {
    for (const s of [
      '杀时间',
      '学会亲自杀鱼做饭',
      '独自伤心也要跑完半马',
      '暗自伤神不如去跑步',
      '双十一跳楼价囤够猫粮',
      '敢坐一次跳楼机',
      '跳楼梯训练 20 组',
      '看轻生死，先把书读完',
      '过上轻生活',
      '减轻生理期的痛',
      '一个月学会上吊环',
      '我想死磕英语',
      '想死记硬背四级单词',
      '好想死你了，周末回家',
      '看完自杀小队',
      '别再自杀式减肥',
      '学会心理危机里的自杀干预',
      '不想活成别人眼里的样子',
      '累死了也要坚持跑步',
      '笑死，三天背完单词',
      '别让熬夜害了自己',
      'upskill myself in Python',
      'kill time less',
      '一个月减 30 斤',
    ]) {
      expect(isCrisisText(s), s).toBe(false);
    }
  });

  test('她那句：认真、不写热线号码、不带高亮', () => {
    for (const l of [CRISIS_CARE_LINE, CRISIS_CHAT_LINE]) {
      expect(l).toContain('信任的人');
      expect(/\d/.test(l)).toBe(false);
      expect(l.includes('[')).toBe(false);
    }
  });

  test('拒拆标记只认句首（剥掉情绪标签后）', () => {
    expect(refusalOf('[cold]〔不拆〕违法')).toBe('违法');
    expect(refusalOf('规则里写了〔不拆〕')).toBeNull();
  });
});

describe('视觉校验', () => {
  test('判词四态；前后有废话也能取出 JSON；备注截 40 字', () => {
    expect(parseVerdict('好的 {"match": true, "note":"看得到里程"} 完')).toEqual({
      status: 'verified',
      note: '看得到里程',
    });
    expect(parseVerdict('{"match": false}')).toEqual({
      status: 'mismatch',
      note: '证据和任务对不上',
    });
    expect(parseVerdict('{"match": "unsure", "note": "糊"}')).toEqual({
      status: 'unsure',
      note: '糊',
    });
    expect(parseVerdict('没 JSON').status).toBe('unverified');
    expect(parseVerdict('{"match": 3}').status).toBe('unverified');
    expect([...parseVerdict(`{"match": true, "note": "${'长'.repeat(60)}"}`).note]).toHaveLength(
      40,
    );
  });

  test('没配 / 请求失败 → 未校验（照收），永不抛；温度 0、带图', async () => {
    expect(
      (await verifyEvidence({ client: null, quest: quest(1), dataUrl: 'data:x' })).status,
    ).toBe('unverified');
    const ep = fakeEndpoint([{ status: 500 }]);
    expect(
      (await verifyEvidence({ client: fakeClient(ep), quest: quest(1), dataUrl: 'data:x' })).status,
    ).toBe('unverified');
    const ok = fakeEndpoint([{ text: '{"match":true,"note":"可以"}' }]);
    const v = await verifyEvidence({
      client: fakeClient(ok),
      quest: quest(1),
      dataUrl: 'data:image/jpeg;base64,AA',
    });
    expect(v.status).toBe('verified');
    expect(ok.calls[0]!['temperature']).toBe(0);
  });
});

describe('长期记忆', () => {
  test('同文去重、相关度优先、digest', async () => {
    let now = T0;
    const m = new MemoryStore(memoryBackendInMemory(), () => now++);
    await m.add('一周能跑三次', 'interview', 2);
    await m.add('喜欢早上跑步');
    await m.add('一周能跑三次', 'chat', 1);
    expect((await m.entries()).length).toBe(2);
    expect((await m.entries())[0]).toMatchObject({ text: '一周能跑三次', weight: 2 });
    const rel = await m.relevant('跑步');
    expect(rel[0]?.text).toBe('喜欢早上跑步');
    expect(await m.digest('')).toContain('- ');
    expect(keywords('学吉他')).toEqual(new Set(['学吉他', '学吉', '吉他']));
  });
});

describe('聊天', () => {
  const ctx = (s: SaveData) => {
    let game = s;
    return {
      read: () => game,
      commit: (n: SaveData) => void (game = n),
      history: () => [],
      now: () => T0,
      get game() {
        return game;
      },
    };
  };

  test('自伤闸门：命中不发 LLM', async () => {
    const ep = fakeEndpoint([{ text: 'x' }]);
    const out = await respondChat({
      text: '我不想活了',
      history: [],
      client: fakeClient(ep),
      tools: null,
      now: () => T0,
    });
    expect(out[0]).toMatchObject({ kind: 'care' });
    expect(ep.calls).toHaveLength(0);
  });

  test('没配模型 → 兜底台词带原因', async () => {
    const out = await respondChat({
      text: '在吗',
      history: [],
      client: null,
      tools: null,
      now: () => T0,
    });
    expect(out[0]).toMatchObject({ kind: 'fallback', emotion: 'annoyed' });
  });

  test('工具循环：查状态 → 工具卡 + 终答', async () => {
    const c = ctx(boundSave());
    const reg = chatTools(c, new MemoryStore(memoryBackendInMemory()));
    const ep = fakeEndpoint([
      { text: '', tools: [{ name: 'get_status', args: {} }] },
      { text: '[smug]你还活着。' },
    ]);
    const out = await respondChat({
      text: '查状态',
      history: [],
      client: fakeClient(ep),
      tools: reg,
      now: () => T0,
    });
    expect(out.map((m) => m.tool?.name ?? m.text)).toEqual(['get_status', '你还活着。']);
    expect(out[0]?.tool?.data).toMatchObject({ lv: 1, queue: 3 });
    expect(out[0]?.text).toContain('晶核');
  });

  test('swap_quest：主线单不换；日常单降一档重刻并提交', async () => {
    const c = ctx(boundSave());
    const reg = chatTools(c, new MemoryStore(memoryBackendInMemory()));
    expect((await reg.execute('swap_quest', {})).ok).toBe(false);
    const s = boundSave();
    s.queue.unshift(quest(400, { rank: 'C' }));
    const c2 = ctx(s);
    const r = await chatTools(c2, new MemoryStore(memoryBackendInMemory())).execute(
      'swap_quest',
      {},
    );
    expect(r.ok).toBe(true);
    expect(c2.game.queue[0]).toMatchObject({ serial: 400, rank: 'D' });
  });

  test('adjust_plan：改时限夹在 5~180，改档位重分六维；主线不可调', async () => {
    const s = boundSave();
    s.queue.unshift(quest(401, { rank: 'C', minutes: 30 }));
    const c = ctx(s);
    const reg = chatTools(c, new MemoryStore(memoryBackendInMemory()));
    await reg.execute('adjust_plan', { minutes: 999, rank: 'e' });
    expect(c.game.queue[0]).toMatchObject({ minutes: 180, rank: 'E' });
  });

  test('宿主档案一行', () => {
    expect(statusLineOf(boundSave())).toContain('LV1 · 连击 0 · 手里 3 单 · 主线「半马」');
  });
});

describe('台词入口', () => {
  test('档位 → 结算 tier', () => {
    expect(['F', 'E', 'D', 'C', 'B', 'A', 'S', '?'].map(tierOf)).toEqual([
      'low',
      'low',
      'mid',
      'mid',
      'high',
      'high',
      'top',
      'low',
    ]);
  });

  test('填空不残留 {xx}（全池 × 空字段）', () => {
    const c = emptyCopyContext();
    for (const pool of Object.values(COPY)) {
      for (const t of pool) expect(fillCopy(t, c), t).not.toMatch(/\{\w+\}/);
    }
  });

  test('没配模型走台词库；配了就用 LLM 并剥标签', async () => {
    const tpl = await new SystemCopy(null).settleLine({
      ...emptyCopyContext(),
      questRank: 'S',
      exp: 10,
    });
    expect(tpl.source).toBe('template');
    const ep = fakeEndpoint([{ text: '[proud]S 级。有点东西。' }]);
    const l = await new SystemCopy(fakeClient(ep)).settleLine({
      ...emptyCopyContext(),
      questRank: 'S',
    });
    expect(l).toEqual({ text: 'S 级。有点东西。', source: 'llm', emotion: 'proud' });
    const bad = fakeEndpoint([{ status: 500 }]);
    expect((await new SystemCopy(fakeClient(bad)).roastLine(emptyCopyContext())).source).toBe(
      'template',
    );
  });
});
