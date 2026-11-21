/**
 * 跨表的整份数据操作：重置、导出、导入。
 *
 *  - 重置：清存档三件套、聊天、流水、长期记忆、证据照片、导入前快照；不清 LLM 设置与同意记录
 *  - 导出：范围与重置一致；证据照片转 Base64
 *  - 导入：先校验格式和版本号（不合格就拒绝、不动现有数据）→ 把当前数据存一份快照 →
 *    冻结存档 → 整体覆盖。调用方随后重新载入页面。
 */
import {
  BUNDLE_APP,
  BUNDLE_KIND,
  BUNDLE_VERSION,
  base64ToBytes,
  bytesToBase64,
  checkBundle,
  type BackupBundle,
  type BundleCheck,
} from '../core/save/bundle';
import { freshSave, saveToJson, stringifySave, type SaveData } from '../core/save/saveData';
import type { Json } from '../core/save/json';
import { KV, type EvidenceRow, type HostDb, type LogRow, type MemoryRow } from './db';
import type { SaveRepo } from './saveRepo';

/** 导入前快照在 snapshots 表里的键 */
export const PRE_IMPORT_KEY = 'preImport';

export class DataRepo {
  constructor(
    private readonly db: HostDb,
    private readonly saves: SaveRepo,
    private readonly clock: () => number = Date.now,
  ) {}

  /** 重置存档。存档仓库保持冻结，调用方重新绑定前再 unfreeze()。 */
  async wipe(): Promise<SaveData> {
    this.saves.freeze();
    const { db } = this;
    await db.transaction(
      'rw',
      [db.kv, db.chat, db.history, db.memory, db.evidence, db.snapshots],
      async () => {
        await db.kv.bulkDelete([KV.saveBak, KV.saveCorrupt, KV.save]);
        await Promise.all([
          db.chat.clear(),
          db.history.clear(),
          db.memory.clear(),
          db.evidence.clear(),
          db.snapshots.clear(),
        ]);
      },
    );
    this.saves.forget();
    return freshSave(this.clock());
  }

  /**
   * 导出整份数据。[current] 传内存里的最新存档（盘上的主档可能还差一拍）；
   * 从没绑定过也照样导出（save 为 null 时导出空档）。
   */
  async exportBundle(current: SaveData | null): Promise<BackupBundle> {
    const { db } = this;
    const [chat, history, memory, evidence] = await Promise.all([
      db.chat.orderBy('seq').toArray(),
      db.history.orderBy('seq').toArray(),
      db.memory.toArray(),
      db.evidence.toArray(),
    ]);
    const shots = await Promise.all(
      evidence.map(async (e) => ({
        id: e.id,
        type: e.type || e.blob.type || 'image/jpeg',
        takenAt: e.takenAt,
        data: bytesToBase64(new Uint8Array(await e.blob.arrayBuffer())),
      })),
    );
    return {
      app: BUNDLE_APP,
      kind: BUNDLE_KIND,
      version: BUNDLE_VERSION,
      exportedAt: this.clock(),
      save: current ? saveToJson(current) : null,
      chat: chat as Json[],
      history: history as Json[],
      memory: memory as Json[],
      evidence: shots,
    };
  }

  /** 导出成文件文本 */
  async exportText(current: SaveData | null): Promise<string> {
    return JSON.stringify(await this.exportBundle(current));
  }

  /**
   * 导入。校验不过 → 原样返回原因，什么都不动。
   * 通过 → 当前数据先存一份快照（snapshots.preImport），再整体覆盖；存档仓库保持冻结。
   */
  async importBundle(raw: unknown, current: SaveData | null): Promise<BundleCheck> {
    const now = this.clock();
    const check = checkBundle(raw, now);
    if (!check.ok) return check;
    const { bundle, save } = check.value;

    const snapshot = await this.exportBundle(current);
    await this.db.snapshots.put({ key: PRE_IMPORT_KEY, at: now, bundle: snapshot });

    this.saves.freeze();
    const { db } = this;
    const evidenceRows: EvidenceRow[] = bundle.evidence.map((e) => ({
      id: e.id,
      type: e.type,
      takenAt: e.takenAt,
      blob: new Blob([base64ToBytes(e.data) as Uint8Array<ArrayBuffer>], { type: e.type }),
    }));
    try {
      // 同一个事务：写到一半失败会整体回滚，现有数据原样保留
      await db.transaction('rw', [db.kv, db.chat, db.history, db.memory, db.evidence], async () => {
        await db.kv.bulkDelete([KV.saveBak, KV.saveCorrupt, KV.save]);
        await Promise.all([
          db.chat.clear(),
          db.history.clear(),
          db.memory.clear(),
          db.evidence.clear(),
        ]);
        if (save) await db.kv.put({ key: KV.save, value: stringifySave(save, now) });
        await db.chat.bulkPut(bundle.chat as LogRow[]);
        await db.history.bulkPut(bundle.history as LogRow[]);
        await db.memory.bulkPut(bundle.memory as MemoryRow[]);
        await db.evidence.bulkPut(evidenceRows);
      });
    } catch (e) {
      console.error('[import] 写入失败，已回滚', e);
      this.saves.unfreeze();
      return { ok: false, reason: '写入本机数据库失败，现有数据没有动。可以再试一次。' };
    }
    this.saves.forget();
    return check;
  }

  /** 导入前的快照（没有 = null） */
  async preImportSnapshot(): Promise<BackupBundle | null> {
    const row = await this.db.snapshots.get(PRE_IMPORT_KEY);
    return row?.bundle ?? null;
  }
}
