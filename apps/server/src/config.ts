/**
 * 服务端配置：只从环境变量读（密钥绝不写进代码 / 产物）。
 * 开发环境给出能跑起来的默认值；生产环境缺关键项直接拒绝启动。
 */
import { resolve } from 'node:path';

export interface LlmDefaults {
  base: string;
  apiKey: string;
  textModel: string;
  visionModel: string;
}

export interface Quotas {
  /** 每人每分钟（文本 / 视觉各算各的） */
  ratePerMin: number;
  /** 用服务器默认 Key 时的每日上限 */
  dailyText: number;
  dailyVision: number;
}

export interface Config {
  env: 'production' | 'development' | 'test';
  port: number;
  host: string;
  /** 数据目录：app.db、uploads/、snapshots/ */
  dataDir: string;
  /** 备份目录（npm run admin -- backup） */
  backupDir: string;
  /** 前端构建产物目录（生产环境由服务端托管） */
  webDist: string;
  /** 站点源（Origin 校验、Cookie Secure 都靠它），如 https://host.example.com */
  origin: string;
  /** 反代后面：信 X-Forwarded-For */
  trustProxy: boolean;
  /** 加密用户 Key 的密钥（32 字节） */
  encryptionKey: Buffer;
  llm: LlmDefaults;
  quotas: Quotas;
}

/** 环境变量缺失 / 不合法 */
export class ConfigError extends Error {
  override name = 'ConfigError';
}

type EnvLike = Record<string, string | undefined>;

function num(env: EnvLike, k: string, def: number): number {
  const v = env[k];
  if (v === undefined || v === '') return def;
  const n = Number(v);
  if (!Number.isFinite(n) || n < 0) throw new ConfigError(`${k} 必须是非负数字`);
  return Math.trunc(n);
}

function key32(raw: string | undefined, isProd: boolean): Buffer {
  if (!raw) {
    if (isProd)
      throw new ConfigError(
        '缺少 APP_ENCRYPTION_KEY（32 字节 Base64，用 `openssl rand -base64 32` 生成）',
      );
    // 开发 / 测试：固定的假密钥，只用于本机
    return Buffer.alloc(32, 7);
  }
  const b = Buffer.from(raw, 'base64');
  if (b.length !== 32) throw new ConfigError('APP_ENCRYPTION_KEY 解出来必须正好 32 字节');
  return b;
}

export function loadConfig(env: EnvLike = process.env): Config {
  const e = env['NODE_ENV'];
  const kind: Config['env'] =
    e === 'production' ? 'production' : e === 'test' ? 'test' : 'development';
  const isProd = kind === 'production';
  const origin = (env['APP_ORIGIN'] ?? '').trim().replace(/\/+$/, '');
  if (isProd && !/^https:\/\//.test(origin))
    throw new ConfigError('生产环境必须设置 APP_ORIGIN，且是 https:// 开头的站点地址');
  return {
    env: kind,
    port: num(env, 'PORT', 8787),
    host: env['HOST'] || (isProd ? '0.0.0.0' : '127.0.0.1'),
    dataDir: resolve(env['DATA_DIR'] || './data'),
    backupDir: resolve(env['BACKUP_DIR'] || './backups'),
    webDist: resolve(env['WEB_DIST'] || './apps/web/dist'),
    origin: origin || 'http://localhost:5173',
    trustProxy: env['TRUST_PROXY'] === '1' || env['TRUST_PROXY'] === 'true',
    encryptionKey: key32(env['APP_ENCRYPTION_KEY'], isProd),
    llm: {
      base: (env['LLM_BASE_URL'] ?? '').trim(),
      apiKey: (env['LLM_API_KEY'] ?? '').trim(),
      textModel: (env['LLM_TEXT_MODEL'] ?? '').trim(),
      visionModel: (env['LLM_VISION_MODEL'] ?? '').trim(),
    },
    quotas: {
      ratePerMin: num(env, 'LLM_RATE_PER_MIN', 10),
      dailyText: num(env, 'LLM_DAILY_TEXT', 150),
      dailyVision: num(env, 'LLM_DAILY_VISION', 60),
    },
  };
}

/** 测试用：在默认值上覆盖几项 */
export function testConfig(over: Partial<Config> = {}): Config {
  return { ...loadConfig({ NODE_ENV: 'test', DATA_DIR: '/nonexistent-test-data' }), ...over };
}
