/** 假的 OpenAI 兼容端点：按顺序吐脚本回复，记录每次请求体 */
import type { FetchLike } from '../../src/agent/llmClient';
import { LlmClient } from '../../src/agent/llmClient';

export type ScriptedReply =
  | { status?: number; text?: string; tools?: Array<{ name: string; args: unknown }>; raw?: string }
  | { throw: 'network' | 'abort' };

export type Scripted = ScriptedReply | ((body: Record<string, unknown>) => ScriptedReply);

export interface FakeEndpoint {
  fetch: FetchLike;
  calls: Array<Record<string, unknown>>;
  noCorsProbes: number;
}

export function completion(
  text: string,
  tools: Array<{ name: string; args: unknown }> = [],
): string {
  return JSON.stringify({
    model: 'fake',
    choices: [
      {
        message: {
          content: text,
          ...(tools.length
            ? {
                tool_calls: tools.map((t, i) => ({
                  id: `call_${i}`,
                  type: 'function',
                  function: { name: t.name, arguments: JSON.stringify(t.args) },
                })),
              }
            : {}),
        },
      },
    ],
  });
}

export function fakeEndpoint(script: Scripted[], opts: { corsOpen?: boolean } = {}): FakeEndpoint {
  const ep: FakeEndpoint = { calls: [], noCorsProbes: 0, fetch: async () => new Response('') };
  let i = 0;
  ep.fetch = async (_url, init) => {
    if (init?.mode === 'no-cors') {
      ep.noCorsProbes++;
      if (opts.corsOpen) return new Response(null, { status: 200 });
      throw new TypeError('Failed to fetch');
    }
    const body = JSON.parse(String(init?.body ?? '{}')) as Record<string, unknown>;
    ep.calls.push(body);
    const pick = script[Math.min(i++, script.length - 1)] as Scripted;
    const s: ScriptedReply = typeof pick === 'function' ? pick(body) : pick;
    if ('throw' in s) {
      if (s.throw === 'abort') {
        return new Promise<Response>((_, rej) => {
          init?.signal?.addEventListener('abort', () =>
            rej(new DOMException('aborted', 'AbortError')),
          );
        });
      }
      throw new TypeError('Failed to fetch');
    }
    const status = s.status ?? 200;
    return new Response(
      s.raw ??
        (status === 200 ? completion(s.text ?? '', s.tools ?? []) : `{"error":"${s.text ?? 'x'}"}`),
      {
        status,
      },
    );
  };
  return ep;
}

export function fakeClient(
  ep: FakeEndpoint,
  over: { consent?: boolean; online?: boolean; timeoutMs?: number } = {},
): LlmClient {
  return new LlmClient(
    { base: 'https://llm.test/v1', apiKey: 'sk-test', model: 'test-model', temperature: 0.8 },
    {
      fetch: ep.fetch,
      consent: () => over.consent ?? true,
      online: () => over.online ?? true,
      retryDelayMs: 0,
      ...(over.timeoutMs ? { timeoutMs: over.timeoutMs } : {}),
    },
  );
}
