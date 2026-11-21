import { describe, expect, test } from 'vitest';
import { LlmClient, failureText, parseCompletion } from '../../src/agent/llmClient';
import { chatEndpoint } from '../../src/agent/settings';
import { fakeClient, fakeEndpoint } from './fakeLlm';

const messages = [{ role: 'user' as const, text: 'hi' }];

describe('请求与解析', () => {
  test('端点补全到 /chat/completions；尾斜杠容忍', () => {
    expect(chatEndpoint('https://a.b/v1/')).toBe('https://a.b/v1/chat/completions');
    expect(chatEndpoint('https://a.b/v1/chat/completions')).toBe('https://a.b/v1/chat/completions');
  });

  test('请求体：model / messages / tools / temperature；不发 max_tokens 和 reasoning_effort', async () => {
    const ep = fakeEndpoint([{ text: '[smug]哼。' }]);
    const r = await fakeClient(ep).chat({
      messages,
      tools: [{ name: 't', description: 'd', parameters: { type: 'object' } }],
    });
    expect(r).toMatchObject({ ok: true, text: '[smug]哼。' });
    const body = ep.calls[0]!;
    expect(body).toMatchObject({ model: 'test-model', temperature: 0.8 });
    expect(body['tools']).toHaveLength(1);
    expect('max_tokens' in body).toBe(false);
    expect('reasoning_effort' in body).toBe(false);
  });

  test('图片消息走 image_url 结构', async () => {
    const ep = fakeEndpoint([{ text: '{}' }]);
    await fakeClient(ep).chat({
      messages: [{ role: 'user', text: '看图', images: ['data:image/jpeg;base64,AAAA'] }],
    });
    const m = (ep.calls[0]!['messages'] as Array<{ content: unknown }>)[0]!;
    expect(m.content).toEqual([
      { type: 'text', text: '看图' },
      { type: 'image_url', image_url: { url: 'data:image/jpeg;base64,AAAA' } },
    ]);
  });

  test('tool_calls 解析：arguments 字符串 JSON 解成对象；坏 JSON → 空对象', () => {
    const r = parseCompletion(
      JSON.stringify({
        choices: [
          {
            message: {
              content: null,
              tool_calls: [
                { id: 'a', function: { name: 'x', arguments: '{"n":1}' } },
                { id: 'b', function: { name: 'y', arguments: '{bad' } },
              ],
            },
          },
        ],
      }),
    );
    expect(r).toMatchObject({
      ok: true,
      text: '',
      toolCalls: [
        { name: 'x', arguments: { n: 1 } },
        { name: 'y', arguments: {} },
      ],
    });
  });

  test('2xx 但结构不对 → badResponse', () => {
    expect(parseCompletion('nope')).toMatchObject({ ok: false, failure: 'badResponse' });
    expect(parseCompletion('{"choices":[]}')).toMatchObject({ ok: false, failure: 'badResponse' });
  });
});

describe('失败分类（docs/00 第六节）', () => {
  test('没填 Key / 端点 / 模型 → noKey，不发请求', async () => {
    const ep = fakeEndpoint([{ text: 'x' }]);
    const c = new LlmClient({ base: 'https://x/v1', apiKey: '', model: 'm' }, { fetch: ep.fetch });
    expect(await c.chat({ messages })).toMatchObject({ ok: false, failure: 'noKey' });
    expect(ep.calls).toHaveLength(0);
  });

  test('没同意告知页 → noConsent，零请求', async () => {
    const ep = fakeEndpoint([{ text: 'x' }]);
    expect(await fakeClient(ep, { consent: false }).chat({ messages })).toMatchObject({
      failure: 'noConsent',
    });
    expect(ep.calls).toHaveLength(0);
  });

  test('503 重试 1 次后成功；504 连两次 → httpError 且写明已重试', async () => {
    const ok = fakeEndpoint([{ status: 503 }, { text: '好' }]);
    expect(await fakeClient(ok).chat({ messages })).toMatchObject({ ok: true, text: '好' });
    expect(ok.calls).toHaveLength(2);
    const bad = fakeEndpoint([{ status: 504 }, { status: 504 }]);
    const r = await fakeClient(bad).chat({ messages });
    expect(r).toMatchObject({ ok: false, failure: 'httpError', status: 504 });
    if (!r.ok) expect(r.detail).toContain('已重试 1 次');
    expect(bad.calls).toHaveLength(2);
  });

  test('400 / 401 / 500 不重试', async () => {
    for (const status of [400, 401, 500]) {
      const ep = fakeEndpoint([{ status }, { text: 'never' }]);
      const r = await fakeClient(ep).chat({ messages, temperature: undefined });
      expect(r).toMatchObject({ ok: false, failure: 'httpError', status });
      expect(ep.calls, String(status)).toHaveLength(1);
    }
  });

  test('超时一律不重试', async () => {
    const ep = fakeEndpoint([{ throw: 'abort' }, { text: 'never' }]);
    const r = await fakeClient(ep).chat({ messages, timeoutMs: 20 });
    expect(r).toMatchObject({ ok: false, failure: 'timeout' });
    expect(ep.calls).toHaveLength(1);
  });

  test('断网重试 1 次；仍不通 → network', async () => {
    const ep = fakeEndpoint([{ throw: 'network' }, { throw: 'network' }]);
    const r = await fakeClient(ep, { online: false }).chat({ messages });
    expect(r).toMatchObject({ ok: false, failure: 'network' });
    expect(ep.calls).toHaveLength(2);
    const ep2 = fakeEndpoint([{ throw: 'network' }, { text: '回来了' }]);
    expect(await fakeClient(ep2, { online: false }).chat({ messages })).toMatchObject({ ok: true });
  });

  test('在线但 fetch 报错、no-cors 探测通 → cors（不重试，提示写清楚）', async () => {
    const ep = fakeEndpoint([{ throw: 'network' }], { corsOpen: true });
    const r = await fakeClient(ep, { online: true }).chat({ messages });
    expect(r).toMatchObject({ ok: false, failure: 'cors' });
    expect(ep.noCorsProbes).toBe(1);
    expect(ep.calls).toHaveLength(1);
    if (!r.ok) expect(failureText(r)).toContain('CORS');
  });

  test('服务商拒温度（400 提到 temperature）→ 去掉温度再试一次', async () => {
    const ep = fakeEndpoint([
      { status: 400, text: 'Unsupported value: temperature' },
      { text: '好' },
    ]);
    const r = await fakeClient(ep).chat({ messages, temperature: 0.7 });
    expect(r).toMatchObject({ ok: true });
    expect(ep.calls[0]!['temperature']).toBe(0.7);
    expect('temperature' in ep.calls[1]!).toBe(false);
  });
});
