/** 假的 OpenAI 兼容端点：按顺序吐脚本回复，记录每次请求体 */
import type { FetchLike } from '../../src/agent/llmClient';
import { LlmClient } from '../../src/agent/llmClient';
import { RANKS, rankIndex, type Rank } from '@host/core/data/rank';

export type ScriptedReply =
  | { status?: number; text?: string; tools?: Array<{ name: string; args: unknown }>; raw?: string }
  | { throw: 'network' | 'abort' };

export type Scripted = ScriptedReply | ((body: Record<string, unknown>) => ScriptedReply);

export interface FakeEndpoint {
  fetch: FetchLike;
  calls: Array<Record<string, unknown>>;
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

export function fakeEndpoint(script: Scripted[]): FakeEndpoint {
  const ep: FakeEndpoint = { calls: [], fetch: async () => new Response('') };
  let i = 0;
  ep.fetch = async (_url, init) => {
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
  over: { consent?: boolean; gate?: () => string | null; timeoutMs?: number } = {},
): LlmClient {
  return new LlmClient(
    { base: 'https://llm.test/v1', apiKey: 'sk-test', model: 'test-model', temperature: 0.8 },
    {
      fetch: ep.fetch,
      consent: () => over.consent ?? true,
      ...(over.gate ? { gate: over.gate } : {}),
      retryDelayMs: 0,
      ...(over.timeoutMs ? { timeoutMs: over.timeoutMs } : {}),
    },
  );
}

// ── 拆解脚本：按请求正文自动交一份合规的清单 / 匹配结果 ──────────────

export const ladder = (n: number, lo: Rank, hi: Rank, lastS = false): Rank[] =>
  Array.from({ length: n }, (_, i) => {
    if (lastS && i === n - 1) return 'S';
    const l = rankIndex(lo);
    const h = rankIndex(hi === 'S' && lastS ? 'A' : hi);
    return RANKS[Math.min(h, l + Math.floor(((h - l) * i) / Math.max(1, n - 1)))] as Rank;
  });

export const tasks = (ranks: Rank[], mode?: string) =>
  ranks.map((r, i) => ({
    short: `第${i + 1}`,
    title: `骑车 ${10 + i} 分钟`,
    proof: '轨迹截图',
    minutes: 10,
    rank: r,
    ...(mode ? { mode } : {}),
  }));

/** 按请求里的「第 a~b 张 / 区间」自动交一份合规的 set_plan */
export const autoPlan: Scripted = (body) => {
  const msgs = body['messages'] as Array<{ content: string }>;
  const user = String(msgs[msgs.length - 1]?.content ?? '');
  const all = msgs.map((m) => String(m.content)).join('\n');
  const seg = /你只负责第 \d+ 份：第 (\d+)~(\d+) 张，共 (\d+) 张/.exec(all);
  const range =
    /本段档位只能在 ([FEDCBAS])~([FEDCBAS]) 之间/.exec(all) ??
    /档位只能在 ([FEDCBAS])~([FEDCBAS]) 之间/.exec(all);
  const count = seg
    ? Number(seg[3])
    : Number(/正好 (\d+) 张|共 (\d+) 张\*\*/.exec(all)?.[1] ?? /共 (\d+) 张\*\*/.exec(all)?.[1]);
  const lo = (range?.[1] ?? 'E') as Rank;
  const hi = (range?.[2] ?? 'C') as Rank;
  const lastS = /必须 S 级/.test(all) && !/本段不含兑现单/.test(all);
  void user;
  return {
    text: '',
    tools: [{ name: 'set_plan', args: { tasks: tasks(ladder(count, lo, hi, lastS)) } }],
  };
};

export const matchReply = (id = 'run', days = 30, quota = 0): Scripted => ({
  text: '',
  tools: [{ name: 'set_goal_category', args: { id, short: '骑车', days, quota } }],
});
