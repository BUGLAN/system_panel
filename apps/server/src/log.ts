/**
 * 小日志器：一行一条 JSON。统一脱敏——Key、Cookie、口令、图片内容一律不进日志。
 */
const SECRET_KEYS =
  /^(authorization|cookie|set-cookie|password|old|next|apikey|api_key|key|key_enc|token|invite|data|raw|image|images|file)$/i;
const SK = /sk-[A-Za-z0-9_-]{8,}/g;
const DATA_URL = /data:[a-z]+\/[a-z0-9.+-]+;base64,[A-Za-z0-9+/=]+/gi;

/** 递归脱敏（只做浅层结构，够日志用） */
export function redact(v: unknown, depth = 0): unknown {
  if (typeof v === 'string') return v.replace(SK, 'sk-***').replace(DATA_URL, 'data:***');
  if (depth > 4 || v === null || typeof v !== 'object') return v;
  if (Array.isArray(v)) return v.slice(0, 20).map((x) => redact(x, depth + 1));
  const out: Record<string, unknown> = {};
  for (const [k, x] of Object.entries(v))
    out[k] = SECRET_KEYS.test(k) ? '***' : redact(x, depth + 1);
  return out;
}

type Level = 'info' | 'warn' | 'error';

let quiet = false;
/** 测试里静音 */
export function setLogQuiet(q: boolean): void {
  quiet = q;
}

function write(level: Level, msg: string, extra?: Record<string, unknown>): void {
  if (quiet) return;
  const line = JSON.stringify({
    t: new Date().toISOString(),
    level,
    msg: redact(msg),
    ...(extra ? (redact(extra) as Record<string, unknown>) : {}),
  });
  if (level === 'error') console.error(line);
  else console.log(line);
}

export const log = {
  info: (msg: string, extra?: Record<string, unknown>) => write('info', msg, extra),
  warn: (msg: string, extra?: Record<string, unknown>) => write('warn', msg, extra),
  error: (msg: string, extra?: Record<string, unknown>) => write('error', msg, extra),
};

/** 把异常压成可以进日志的样子（只留类型和消息） */
export function errInfo(e: unknown): Record<string, unknown> {
  if (e instanceof Error) return { err: e.name, message: e.message };
  return { err: String(e) };
}
