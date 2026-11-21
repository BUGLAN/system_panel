/**
 * 服务端入口：读配置 → 开库（迁移）→ 装配应用 → 托管前端 → 监听。
 */
import { serve } from '@hono/node-server';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { createApp } from './app';
import { purgeExpiredSessions } from './auth/accounts';
import { ConfigError, loadConfig } from './config';
import { openDb } from './db/client';
import { RateLimiter } from './http/rateLimit';
import { errInfo, log } from './log';
import { mountStatic } from './static';

function start(): void {
  let config;
  try {
    config = loadConfig();
  } catch (e) {
    if (e instanceof ConfigError) {
      log.error(`配置不对：${e.message}`);
      process.exit(1);
    }
    throw e;
  }
  mkdirSync(config.dataDir, { recursive: true });
  const dbh = openDb(join(config.dataDir, 'app.db'));
  const app = createApp({ config, dbh, now: Date.now, limiter: new RateLimiter() });
  const hasWeb = mountStatic(app, config.webDist);

  const sweep = setInterval(() => purgeExpiredSessions(dbh.db, Date.now()), 6 * 3_600_000);
  sweep.unref();

  const server = serve({ fetch: app.fetch, port: config.port, hostname: config.host }, (info) => {
    log.info('服务已启动', {
      addr: `${info.address}:${info.port}`,
      env: config.env,
      web: hasWeb ? config.webDist : '（未托管前端）',
      llmDefault: !!(config.llm.base && config.llm.apiKey),
    });
  });

  const stop = (sig: string) => {
    log.info(`收到 ${sig}，正在退出`);
    server.close(() => {
      dbh.close();
      process.exit(0);
    });
    setTimeout(() => process.exit(0), 5_000).unref();
  };
  process.on('SIGTERM', () => stop('SIGTERM'));
  process.on('SIGINT', () => stop('SIGINT'));
}

try {
  start();
} catch (e) {
  log.error('启动失败', errInfo(e));
  process.exit(1);
}
