/**
 * OpenAI 兼容 /chat/completions 客户端（服务端调用；Key 不再进浏览器）。
 * 移植自 flutter-final:app/lib/agent/llm_client.dart，按 docs/00 第六节、docs/05 第 1.5 节调整：
 *
 *  - 失败分类：noKey / noConsent / quota / network / timeout / httpError / badResponse
 *    （cors 只在旧的浏览器直连版出现，服务端不会再产生，类型保留）
 *  - 重试：502 / 503 / 504 和断网重试 1 次，间隔 800ms；超时一律不重试
 *  - 不发 reasoning_effort / max_tokens：用户自配的服务商千差万别，这两个参数在不少
 *    模型上会直接 400（推理模型拒 max_tokens），留给服务商默认值
 *  - 服务商拒温度（400 且报错里提到 temperature）时去掉温度再试一次
 *  - 同意闸门：没同意首启告知页 → 零请求
 *  - 额度闸门：超了限速 / 每日上限 → quota，零请求（重试不重复计数）
 */
import { chatEndpoint } from './settings';

export type LlmFailure =
  'noKey' | 'noConsent' | 'quota' | 'network' | 'cors' | 'timeout' | 'httpError' | 'badResponse';

export interface LlmMessage {
  role: 'system' | 'user' | 'assistant';
  text: string;
  /** data: URL（视觉校验用） */
  images?: string[];
}

export interface LlmTool {
  name: string;
  description: string;
  parameters: Record<string, unknown>;
}

export interface LlmToolCall {
  id: string;
  name: string;
  arguments: Record<string, unknown>;
}

export type LlmReply =
  | { ok: true; text: string; toolCalls: LlmToolCall[]; model: string | null }
  | { ok: false; failure: LlmFailure; detail: string; status?: number };

export interface LlmConfig {
  base: string;
  apiKey: string;
  model: string;
  temperature?: number;
}

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;

export interface LlmClientOptions {
  fetch?: FetchLike;
  /** 同意闸门：返回 false = 没同意，请求不发 */
  consent?: () => boolean | Promise<boolean>;
  /** 额度闸门：返回一句原因 = 超额，请求不发；null = 放行（每次 chat 只问一次） */
  gate?: () => string | null | Promise<string | null>;
  /** 重试间隔（测试里设 0） */
  retryDelayMs?: number;
  /** 默认超时 */
  timeoutMs?: number;
}

export const RETRY_STATUSES = new Set([502, 503, 504]);

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

function snippet(s: string, n = 160): string {
  const t = s.replace(/\s+/g, ' ').trim();
  return t.length > n ? `${t.slice(0, n)}…` : t;
}

function messageToWire(m: LlmMessage): Record<string, unknown> {
  if (!m.images?.length) return { role: m.role, content: m.text };
  return {
    role: m.role,
    content: [
      { type: 'text', text: m.text },
      ...m.images.map((url) => ({ type: 'image_url', image_url: { url } })),
    ],
  };
}

function decodeArgs(raw: unknown): Record<string, unknown> {
  if (raw && typeof raw === 'object' && !Array.isArray(raw)) return raw as Record<string, unknown>;
  if (typeof raw !== 'string' || !raw.trim()) return {};
  try {
    const v: unknown = JSON.parse(raw);
    return v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

/** 解析 2xx 响应体 */
export function parseCompletion(body: string): LlmReply {
  let v: unknown;
  try {
    v = JSON.parse(body);
  } catch {
    return { ok: false, failure: 'badResponse', detail: '响应不是 JSON' };
  }
  if (!v || typeof v !== 'object')
    return { ok: false, failure: 'badResponse', detail: '响应不是 JSON 对象' };
  const o = v as Record<string, unknown>;
  const choices = o['choices'];
  if (!Array.isArray(choices) || !choices.length) {
    return { ok: false, failure: 'badResponse', detail: '响应缺少 choices' };
  }
  const first = choices[0] as Record<string, unknown> | undefined;
  const msg = first?.['message'];
  if (!msg || typeof msg !== 'object')
    return { ok: false, failure: 'badResponse', detail: '响应缺少 message' };
  const m = msg as Record<string, unknown>;
  const content = m['content'];
  let text = '';
  if (typeof content === 'string') text = content;
  else if (Array.isArray(content)) {
    text = content
      .map((p) =>
        p && typeof p === 'object' && typeof (p as { text?: unknown }).text === 'string'
          ? (p as { text: string }).text
          : '',
      )
      .join('');
  }
  const toolCalls: LlmToolCall[] = [];
  const raw = m['tool_calls'];
  if (Array.isArray(raw)) {
    for (const c of raw) {
      if (!c || typeof c !== 'object') continue;
      const fn = (c as Record<string, unknown>)['function'];
      if (!fn || typeof fn !== 'object') continue;
      const f = fn as Record<string, unknown>;
      toolCalls.push({
        id: String((c as Record<string, unknown>)['id'] ?? ''),
        name: String(f['name'] ?? ''),
        arguments: decodeArgs(f['arguments']),
      });
    }
  }
  return { ok: true, text, toolCalls, model: typeof o['model'] === 'string' ? o['model'] : null };
}

export const CORS_HINT = '服务商拒绝了跨域请求。';

export class LlmClient {
  private readonly fetchImpl: FetchLike;
  private readonly consent: () => boolean | Promise<boolean>;
  private readonly gate: () => string | null | Promise<string | null>;
  private readonly retryDelayMs: number;
  readonly timeoutMs: number;

  constructor(
    readonly config: LlmConfig,
    opts: LlmClientOptions = {},
  ) {
    this.fetchImpl = opts.fetch ?? ((i, init) => fetch(i, init));
    this.consent = opts.consent ?? (() => true);
    this.gate = opts.gate ?? (() => null);
    this.retryDelayMs = opts.retryDelayMs ?? 800;
    this.timeoutMs = opts.timeoutMs ?? 45_000;
  }

  get configured(): boolean {
    return !!(this.config.apiKey.trim() && this.config.base.trim() && this.config.model.trim());
  }

  /** 测试连接：一句话 ping */
  ping(timeoutMs = 20_000): Promise<LlmReply> {
    return this.chat({
      messages: [
        { role: 'system', text: '你是系统娘小祥，只用一句话回答，不要解释。' },
        { role: 'user', text: 'ping' },
      ],
      temperature: 0,
      timeoutMs,
    });
  }

  async chat(o: {
    messages: LlmMessage[];
    tools?: LlmTool[];
    temperature?: number;
    timeoutMs?: number;
    signal?: AbortSignal;
  }): Promise<LlmReply> {
    let allowed: boolean;
    try {
      allowed = await this.consent();
    } catch {
      allowed = false;
    }
    if (!allowed)
      return { ok: false, failure: 'noConsent', detail: '还没同意告知页：请求没有发出' };
    if (!this.config.apiKey.trim()) return { ok: false, failure: 'noKey', detail: '没填 API Key' };
    if (!this.config.base.trim()) return { ok: false, failure: 'noKey', detail: '没填端点地址' };
    if (!this.config.model.trim()) return { ok: false, failure: 'noKey', detail: '没填模型名' };
    let blocked: string | null;
    try {
      blocked = await this.gate();
    } catch {
      blocked = '额度检查失败';
    }
    if (blocked) return { ok: false, failure: 'quota', detail: blocked };

    const temp = o.temperature ?? this.config.temperature;
    const first = await this.send(o, temp);
    // 有的模型只接受默认温度：报错里点名 temperature 时去掉它再来一次
    if (
      !first.ok &&
      first.status === 400 &&
      temp !== undefined &&
      /temperature/i.test(first.detail)
    ) {
      return this.send(o, undefined);
    }
    return first;
  }

  private async send(
    o: { messages: LlmMessage[]; tools?: LlmTool[]; timeoutMs?: number; signal?: AbortSignal },
    temperature: number | undefined,
  ): Promise<LlmReply> {
    const url = chatEndpoint(this.config.base);
    const body = JSON.stringify({
      model: this.config.model.trim(),
      messages: o.messages.map(messageToWire),
      ...(o.tools?.length
        ? {
            tools: o.tools.map((t) => ({
              type: 'function',
              function: { name: t.name, description: t.description, parameters: t.parameters },
            })),
          }
        : {}),
      ...(temperature !== undefined ? { temperature } : {}),
    });
    const limit = o.timeoutMs ?? this.timeoutMs;
    let tried = 0;
    let last: LlmReply = { ok: false, failure: 'network', detail: '网络错误' };
    const withRetries = (d: string) => (tried > 0 ? `${d}（已重试 ${tried} 次）` : d);

    for (let attempt = 0; attempt <= 1; attempt++) {
      tried = attempt;
      const ctl = new AbortController();
      let timedOut = false;
      const timer = setTimeout(() => {
        timedOut = true;
        ctl.abort();
      }, limit);
      const onOuterAbort = () => ctl.abort();
      o.signal?.addEventListener('abort', onOuterAbort);
      try {
        const resp = await this.fetchImpl(url, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${this.config.apiKey.trim()}`,
          },
          body,
          signal: ctl.signal,
        });
        const text = await resp.text();
        if (RETRY_STATUSES.has(resp.status) && attempt < 1) {
          last = {
            ok: false,
            failure: 'httpError',
            status: resp.status,
            detail: `HTTP ${resp.status}：${snippet(text)}`,
          };
          await sleep(this.retryDelayMs);
          continue;
        }
        if (resp.status < 200 || resp.status >= 300) {
          return {
            ok: false,
            failure: 'httpError',
            status: resp.status,
            detail: withRetries(`HTTP ${resp.status}：${snippet(text)}`),
          };
        }
        return parseCompletion(text);
      } catch (e) {
        if (timedOut) {
          return {
            ok: false,
            failure: 'timeout',
            detail: withRetries(`请求超时（>${Math.round(limit / 1000)} 秒）`),
          };
        }
        if (o.signal?.aborted) return { ok: false, failure: 'network', detail: '请求被取消' };
        last = {
          ok: false,
          failure: 'network',
          detail: `网络不可达：${e instanceof Error ? e.message : String(e)}`,
        };
        if (attempt < 1) {
          await sleep(this.retryDelayMs);
          continue;
        }
      } finally {
        clearTimeout(timer);
        o.signal?.removeEventListener('abort', onOuterAbort);
      }
    }
    return last.ok ? last : { ...last, detail: withRetries(last.detail) };
  }
}

/** 失败原因 → 给宿主看的一句（测试连接 / 设置页用） */
export function failureText(r: Extract<LlmReply, { ok: false }>): string {
  switch (r.failure) {
    case 'noKey':
      return `没配好：${r.detail}`;
    case 'noConsent':
      return '还没同意首启告知页，请求不会发出。';
    case 'quota':
      return `额度：${r.detail}`;
    case 'network':
      return `网络不通：${r.detail}`;
    case 'cors':
      return CORS_HINT;
    case 'timeout':
      return `超时：${r.detail}`;
    case 'httpError':
      return `服务商报错 ${r.detail}`;
    case 'badResponse':
      return `回包看不懂：${r.detail}`;
  }
}
