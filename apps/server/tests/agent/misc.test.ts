import { describe, expect, test } from 'vitest';
import { CRISIS_CARE_LINE, isCrisisText, refusalOf } from '@host/core/agent/guardrail';
import { BACKSTORY, buildConversation, splitTag, systemPrompt } from '@host/core/agent/persona';
import { parseVerdict, verifyEvidence } from '../../src/agent/vision';
import { statusLineOf } from '@host/core/agent/status';
import { boundSave } from '@host/core/testing/helpers';
import { quest } from '@host/core/testing/fixtures';
import { fakeClient, fakeEndpoint } from './fakeLlm';

describe('人设', () => {
  test('系统提示词以 backstory 原文开头，带四语气与铁律', () => {
    const p = systemPrompt({ statusLine: 'LV1' });
    expect(p.startsWith(BACKSTORY)).toBe(true);
    expect(p).toContain('【四种固定语气】');
    expect(p).toContain('不超过 3 句');
    expect(p).toContain('【宿主档案】LV1');
    expect(p).not.toContain('【长期记忆】');
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
    for (const l of [CRISIS_CARE_LINE]) {
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

describe('宿主档案一行', () => {
  test('等级、连击、主线与进度', () => {
    expect(statusLineOf(boundSave())).toBe('宿主 · LV1 · 连击 0 · 主线「半马」 · 主线进度 0/5 单');
  });
});
