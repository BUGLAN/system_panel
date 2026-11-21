/**
 * 调服务端：同源 fetch（会话 Cookie 自动带上）。
 *  - 写请求带 x-intent-id（网络重试不会被执行两次）
 *  - 断网 / 连不上 → ApiError(code 'offline')，界面统一提示「需要联网」
 *  - 响应里带 state 的（成功或 409 / 422）都先交给 onState 落到本地
 *  - 401 → onUnauthorized（回登录页）
 */
import { INTENT_HEADER, type StateView } from '@host/core/api/types';

export class ApiError extends Error {
  override name = 'ApiError';
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly body: Record<string, unknown> = {},
  ) {
    super(message);
  }
  get offline(): boolean {
    return this.code === 'offline';
  }
}

export const OFFLINE_TEXT = '需要联网。连上网再试。';

type Hooks = {
  onState?: (s: StateView) => void;
  onUnauthorized?: () => void;
  onOnline?: (online: boolean) => void;
};
const hooks: Hooks = {};
export function setApiHooks(h: Hooks): void {
  Object.assign(hooks, h);
}

let seq = 0;
const intentId = () =>
  `${Date.now().toString(36)}-${(seq++).toString(36)}-${Math.random().toString(36).slice(2, 8)}`;

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;
let fetchImpl: FetchLike = (i, init) => fetch(i, init);
/** 测试用 */
export function setFetch(f: FetchLike): void {
  fetchImpl = f;
}

export async function api<T = Record<string, unknown>>(
  method: 'GET' | 'POST' | 'PUT' | 'DELETE',
  path: string,
  body?: unknown,
): Promise<T> {
  const headers: Record<string, string> = {};
  let payload: BodyInit | undefined;
  if (body instanceof FormData) payload = body;
  else if (body !== undefined) {
    headers['Content-Type'] = 'application/json';
    payload = JSON.stringify(body);
  }
  if (method !== 'GET') headers[INTENT_HEADER] = intentId();
  let res: Response;
  try {
    res = await fetchImpl(path, { method, headers, body: payload, credentials: 'same-origin' });
  } catch {
    hooks.onOnline?.(false);
    throw new ApiError(0, 'offline', OFFLINE_TEXT);
  }
  hooks.onOnline?.(true);
  let json: Record<string, unknown>;
  try {
    json = (await res.json()) as Record<string, unknown>;
  } catch {
    // 反代 / 服务挂了回的 HTML 错误页
    if (res.status >= 500 || res.status === 0)
      throw new ApiError(res.status, 'offline', OFFLINE_TEXT);
    throw new ApiError(res.status, 'bad_response', '服务器回的看不懂。稍后再试。');
  }
  const state = json['state'] as StateView | undefined;
  if (state && typeof state === 'object' && typeof state.version === 'number')
    hooks.onState?.(state);
  if (!res.ok || json['ok'] === false) {
    if (res.status === 401) hooks.onUnauthorized?.();
    const msg = typeof json['message'] === 'string' ? json['message'] : `出错了（${res.status}）。`;
    const code = typeof json['code'] === 'string' ? json['code'] : 'error';
    throw new ApiError(res.status, code, msg, json);
  }
  return json as T;
}

/** 把任意异常压成一句给宿主看的话 */
export function errText(e: unknown): string {
  if (e instanceof ApiError) return e.message;
  return e instanceof Error ? e.message : String(e);
}
