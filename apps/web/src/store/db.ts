/**
 * 本机数据库（IndexedDB / Dexie）——服务端版只剩两样东西：
 *  - 偏好（静音 / 音量 / 看过安装引导）：本来就是「这台设备」的设置，不上服务器
 *  - 离线只读缓存：最近一次的状态、流水、账号（按用户名分键，退出登录清掉）
 * 业务数据的真源在服务器。库名换了新的：旧版 PWA 的本机数据库原样留着，不碰（要迁就「导出 → 登录后导入」）。
 */
import Dexie, { type Table } from 'dexie';

export interface KvRow {
  key: string;
  value: unknown;
}

export class HostDb extends Dexie {
  kv!: Table<KvRow, string>;

  constructor(name = 'host-system-server') {
    super(name);
    this.version(1).stores({ kv: '&key' });
  }
}

let shared: HostDb | null = null;

export function appDb(): HostDb {
  shared ??= new HostDb();
  return shared;
}
