/**
 * 表结构（Drizzle / SQLite）。所有业务表都挂 user_id（删用户级联删除），
 * 查询一律经过 repo 层、按当前用户过滤（docs/05 第 2 节）。
 * 改了这里要跑 `npm run db:generate` 生成迁移并一起提交。
 */
import { sql } from 'drizzle-orm';
import { index, integer, primaryKey, real, sqliteTable, text } from 'drizzle-orm/sqlite-core';

const now = sql`(unixepoch() * 1000)`;

export const users = sqliteTable('users', {
  id: text('id').primaryKey(),
  /** 唯一，大小写不敏感（存规范化后的小写形式在 username_key） */
  username: text('username').notNull(),
  usernameKey: text('username_key').notNull().unique(),
  passHash: text('pass_hash').notNull(),
  role: text('role', { enum: ['admin', 'user'] })
    .notNull()
    .default('user'),
  /** IANA 时区：换日 / 连胜 / 补签 / 每日额度按它算「哪一天」 */
  tz: text('tz').notNull(),
  disabled: integer('disabled', { mode: 'boolean' }).notNull().default(false),
  createdAt: integer('created_at').notNull().default(now),
});

export const sessions = sqliteTable(
  'sessions',
  {
    /** sha256(token)；token 本身只在 Cookie 里 */
    id: text('id').primaryKey(),
    userId: text('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    createdAt: integer('created_at').notNull(),
    expiresAt: integer('expires_at').notNull(),
    renewedAt: integer('renewed_at').notNull(),
    ua: text('ua').notNull().default(''),
  },
  (t) => [index('sessions_user').on(t.userId)],
);

export const invites = sqliteTable('invites', {
  /** sha256(邀请码) */
  codeHash: text('code_hash').primaryKey(),
  note: text('note').notNull().default(''),
  createdAt: integer('created_at').notNull(),
  expiresAt: integer('expires_at').notNull(),
  usedBy: text('used_by').references(() => users.id, { onDelete: 'set null' }),
  usedAt: integer('used_at'),
});

export const saves = sqliteTable('saves', {
  userId: text('user_id')
    .primaryKey()
    .references(() => users.id, { onDelete: 'cascade' }),
  /** stringifySave 的串（主档） */
  data: text('data').notNull(),
  /** 上一份好串（写前滚动） */
  bak: text('bak'),
  schemaV: integer('schema_v').notNull(),
  /** 每写一次 +1 */
  version: integer('version').notNull(),
  updatedAt: integer('updated_at').notNull(),
  /** 最近一次带登录态的请求（「你走了多久」） */
  lastSeenAt: integer('last_seen_at'),
});

export const saveCorrupt = sqliteTable('save_corrupt', {
  id: integer('id').primaryKey({ autoIncrement: true }),
  userId: text('user_id')
    .notNull()
    .references(() => users.id, { onDelete: 'cascade' }),
  raw: text('raw').notNull(),
  at: integer('at').notNull(),
});

export const history = sqliteTable(
  'history',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    userId: text('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    at: integer('at').notNull(),
    data: text('data').notNull(),
  },
  (t) => [index('history_user_at').on(t.userId, t.at)],
);

export const chat = sqliteTable(
  'chat',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    userId: text('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    at: integer('at').notNull(),
    data: text('data').notNull(),
  },
  (t) => [index('chat_user').on(t.userId, t.id)],
);

export const memory = sqliteTable(
  'memory',
  {
    id: text('id').notNull(),
    userId: text('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    text: text('text').notNull(),
    at: integer('at').notNull(),
    source: text('source').notNull(),
    weight: integer('weight').notNull(),
  },
  (t) => [primaryKey({ columns: [t.userId, t.id] })],
);

export const evidence = sqliteTable(
  'evidence',
  {
    /** 存档里 EvidenceShot.id（新拍的由服务端生成；导入的沿用原 id，所以按用户唯一） */
    id: text('id').notNull(),
    userId: text('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    /** 相对 uploads/ 的路径：<userId>/<id>.jpg */
    file: text('file').notNull(),
    mime: text('mime').notNull(),
    bytes: integer('bytes').notNull(),
    sha256: text('sha256').notNull(),
    takenAt: integer('taken_at').notNull(),
    questSerial: integer('quest_serial').notNull().default(0),
    status: text('status').notNull().default('unverified'),
    note: text('note').notNull().default(''),
  },
  (t) => [primaryKey({ columns: [t.userId, t.id] })],
);

export const llmSettings = sqliteTable('llm_settings', {
  userId: text('user_id')
    .primaryKey()
    .references(() => users.id, { onDelete: 'cascade' }),
  /** 用自己的端点 + Key（整套覆盖服务器默认） */
  useOwn: integer('use_own', { mode: 'boolean' }).notNull().default(false),
  base: text('base').notNull().default(''),
  /** AES-256-GCM 密文（Base64）；空串 = 没填 */
  keyEnc: text('key_enc').notNull().default(''),
  /** 末 4 位，给宿主确认填的是哪把 */
  keyHint: text('key_hint').notNull().default(''),
  textModel: text('text_model').notNull().default(''),
  visionModel: text('vision_model').notNull().default(''),
  temperature: real('temperature').notNull().default(0.8),
  visionEnabled: integer('vision_enabled', { mode: 'boolean' }).notNull().default(true),
});

export const consents = sqliteTable('consents', {
  userId: text('user_id')
    .primaryKey()
    .references(() => users.id, { onDelete: 'cascade' }),
  version: integer('version').notNull(),
  at: integer('at').notNull(),
});

export const llmUsage = sqliteTable(
  'llm_usage',
  {
    userId: text('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    /** 用户时区的日历日 */
    day: text('day').notNull(),
    textCalls: integer('text_calls').notNull().default(0),
    visionCalls: integer('vision_calls').notNull().default(0),
  },
  (t) => [primaryKey({ columns: [t.userId, t.day] })],
);
