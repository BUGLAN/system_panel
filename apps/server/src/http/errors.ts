/**
 * 统一错误：{ ok:false, code, message }。message 是能直接念给宿主听的中文。
 */
import type { ContentfulStatusCode } from 'hono/utils/http-status';

export class ApiError extends Error {
  override name = 'ApiError';
  constructor(
    readonly status: ContentfulStatusCode,
    readonly code: string,
    message: string,
    /** 附带给前端的数据（如 409 时的最新状态） */
    readonly extra?: Record<string, unknown>,
  ) {
    super(message);
  }
}

export const badRequest = (message: string, code = 'bad_request') =>
  new ApiError(400, code, message);
export const unauthorized = (message = '还没登录，或者登录过期了。') =>
  new ApiError(401, 'unauthorized', message);
export const forbidden = (message: string, code = 'forbidden') => new ApiError(403, code, message);
/** 不存在和「不是你的」一律 404 */
export const notFound = (message = '找不到。') => new ApiError(404, 'not_found', message);
export const tooMany = (message: string, retryAfterSec: number) =>
  new ApiError(429, 'rate_limited', message, { retryAfterSec });
