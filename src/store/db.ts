/**
 * 本机数据库（IndexedDB / Dexie）。
 *
 *  kv        存档主档 / 备份 / 坏档原串、同意记录、LLM 设置、偏好
 *  chat      聊天记录
 *  history   流水（结算 / 认输）
 *  memory    长期记忆
 *  evidence  证据照片（压缩后的 JPEG Blob）
 *  snapshots 导入前的整份快照
 *
 * 「重置存档」清：存档三件套、chat、history、memory、evidence、snapshots；
 * 不清：同意记录、LLM 设置、偏好（音量等）。
 */
import Dexie, { type Table } from 'dexie';
import type { BackupBundle } from '../core/save/bundle';

export const KV = {
  save: 'save',
  saveBak: 'save.bak',
  saveCorrupt: 'save.corrupt',
  consent: 'consent',
  llm: 'llm',
  prefs: 'prefs',
} as const;

export interface KvRow {
  key: string;
  value: unknown;
}

/** 聊天 / 流水的一行（具体字段由各自模块定义） */
export interface LogRow {
  seq?: number;
  at: number;
  [k: string]: unknown;
}

export interface MemoryRow {
  id: string;
  at: number;
  [k: string]: unknown;
}

export interface EvidenceRow {
  id: string;
  blob: Blob;
  type: string;
  takenAt: number;
}

export interface SnapshotRow {
  key: string;
  at: number;
  bundle: BackupBundle;
}

export class HostDb extends Dexie {
  kv!: Table<KvRow, string>;
  chat!: Table<LogRow, number>;
  history!: Table<LogRow, number>;
  memory!: Table<MemoryRow, string>;
  evidence!: Table<EvidenceRow, string>;
  snapshots!: Table<SnapshotRow, string>;

  constructor(name = 'host-system') {
    super(name);
    this.version(1).stores({
      kv: '&key',
      chat: '++seq, at',
      history: '++seq, at',
      memory: '&id, at',
      evidence: '&id, takenAt',
      snapshots: '&key',
    });
  }
}

let shared: HostDb | null = null;

/** App 运行时共用的那一个库 */
export function appDb(): HostDb {
  shared ??= new HostDb();
  return shared;
}
