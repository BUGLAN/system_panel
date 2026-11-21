/**
 * 管理员命令行（在服务器上跑）：
 *   npm run admin -- create-admin <用户名> [--tz Asia/Shanghai]   第一个管理员（密码从终端输入）
 *   npm run admin -- invite [--days 7] [--note 名字]               生成一次性邀请码
 *   npm run admin -- invites                                       列出还没用的邀请码（只有备注和期限）
 *   npm run admin -- reset-password <用户名>                       重置密码（该用户所有设备下线）
 *   npm run admin -- disable <用户名> / enable <用户名>             停用 / 恢复账号
 *   npm run admin -- users                                         列出账号
 *   npm run admin -- backup [--keep 14]                            在线备份数据库 + 上传目录
 * Docker 里：docker compose exec app node dist/cli.mjs <命令>
 * 密码也可用环境变量 ADMIN_PASSWORD 传入（脚本化时）。
 */
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { createInterface } from 'node:readline';
import { eq } from 'drizzle-orm';
import {
  createInvite,
  createUser,
  findUserByName,
  openInvites,
  revokeUserSessions,
  setPassword,
} from '../auth/accounts';
import { loadConfig } from '../config';
import { openDb } from '../db/client';
import { users } from '../db/schema';
import { runBackup } from './backup';

function arg(name: string, def?: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : def;
}

async function askPassword(prompt: string): Promise<string> {
  const env = process.env['ADMIN_PASSWORD'];
  if (env) return env;
  const rl = createInterface({ input: process.stdin, output: process.stdout, terminal: true });
  // 输入时不回显
  const out = rl as unknown as { _writeToOutput?: (s: string) => void; output: NodeJS.WriteStream };
  let asking = true;
  out._writeToOutput = (s: string) => {
    if (!asking) out.output.write(s);
    else if (s.includes(prompt)) out.output.write(prompt);
  };
  const p = await new Promise<string>((r) => rl.question(prompt, r));
  asking = false;
  rl.close();
  process.stdout.write('\n');
  return p;
}

function fmt(ms: number): string {
  return new Date(ms).toLocaleString('zh-CN', { hour12: false });
}

async function main(): Promise<void> {
  const [cmd, name] = process.argv
    .slice(2)
    .filter((a, i, all) => !a.startsWith('--') && !all[i - 1]?.startsWith('--'));
  const config = loadConfig();
  mkdirSync(config.dataDir, { recursive: true });
  const dbh = openDb(join(config.dataDir, 'app.db'));
  const db = dbh.db;
  const now = Date.now();
  try {
    switch (cmd) {
      case 'create-admin': {
        if (!name) throw new Error('用法：create-admin <用户名>');
        const tz = arg('tz', Intl.DateTimeFormat().resolvedOptions().timeZone) as string;
        const pw = await askPassword('设置密码（至少 8 位）：');
        const u = await createUser(db, { username: name, password: pw, tz, role: 'admin', now });
        console.log(`✓ 管理员「${u.username}」已创建（时区 ${u.tz}）`);
        break;
      }
      case 'invite': {
        const days = Number(arg('days', '7'));
        const code = createInvite(db, { now, days, note: arg('note', '') ?? '' });
        console.log(`邀请码（${days} 天内有效，只能用一次）：\n\n  ${code}\n`);
        break;
      }
      case 'invites': {
        const list = openInvites(db, now);
        if (!list.length) console.log('没有可用的邀请码。');
        for (const i of list) console.log(`· ${i.note || '（无备注）'}  到期 ${fmt(i.expiresAt)}`);
        break;
      }
      case 'reset-password': {
        if (!name) throw new Error('用法：reset-password <用户名>');
        const u = findUserByName(db, name);
        if (!u) throw new Error(`没有用户「${name}」`);
        const pw = await askPassword(`给「${u.username}」设新密码：`);
        await setPassword(db, u.id, pw);
        revokeUserSessions(db, u.id);
        console.log('✓ 已重置，该用户所有设备需要重新登录');
        break;
      }
      case 'disable':
      case 'enable': {
        if (!name) throw new Error(`用法：${cmd} <用户名>`);
        const u = findUserByName(db, name);
        if (!u) throw new Error(`没有用户「${name}」`);
        db.update(users)
          .set({ disabled: cmd === 'disable' })
          .where(eq(users.id, u.id))
          .run();
        if (cmd === 'disable') revokeUserSessions(db, u.id);
        console.log(`✓ 「${u.username}」已${cmd === 'disable' ? '停用' : '恢复'}`);
        break;
      }
      case 'users': {
        for (const u of db.select().from(users).all())
          console.log(
            `· ${u.username}  ${u.role}  ${u.tz}  ${u.disabled ? '已停用' : ''}  注册于 ${fmt(u.createdAt)}`,
          );
        break;
      }
      case 'backup': {
        const out = await runBackup(dbh, config, { keep: Number(arg('keep', '14')), now });
        console.log(`✓ 备份完成：${out}`);
        break;
      }
      default:
        console.log(
          '命令：create-admin / invite / invites / reset-password / disable / enable / users / backup',
        );
        process.exitCode = cmd ? 1 : 0;
    }
  } finally {
    dbh.close();
  }
}

main().catch((e: unknown) => {
  console.error(`✗ ${e instanceof Error ? e.message : String(e)}`);
  process.exit(1);
});
