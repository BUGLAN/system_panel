/**
 * 存档主档的读写：备份滚动、坏档保护、冻结。
 * 移植自 flutter-final:app/lib/state/save_file.dart（G1.1）。
 *
 *  - 每次写盘前把**上一份好档**滚进 save.bak（只滚能解析的串，坏档绝不进 bak）；
 *    bak 与主档在同一个事务里写，不会出现半截状态
 *  - 主档读坏 → 原串先另存 save.corrupt → 退回 bak 并立刻把它写回主档 → bak 也不行才给空白档
 *  - 没有主档 = 没有档，不去翻 bak（否则「重置」掉的旧档会复活）
 *  - 重置 / 导入时冻结：之后的自动存档一律跳过，免得把旧内存状态写回去
 */
import { freshSave, parseSave, stringifySave, type SaveData } from '../core/save/saveData';
import { KV, type HostDb } from './db';

/** 读档走的是哪条路 */
export type SaveSource = 'primary' | 'backup' | 'none' | 'corrupt';

export interface SaveLoad {
  data: SaveData;
  source: SaveSource;
}

export class SaveRepo {
  private frozen = false;
  /** 已知能解析的最近一份主档串（首次读到的 / 上次成功写出去的），下次存盘滚进 bak */
  private lastGood: string | null = null;
  /** 已知 bak 里现在是什么（相同就不重写） */
  private bakMirror: string | null = null;

  constructor(
    private readonly db: HostDb,
    private readonly clock: () => number = Date.now,
  ) {}

  get isFrozen(): boolean {
    return this.frozen;
  }

  private async getStr(key: string): Promise<string | undefined> {
    const row = await this.db.kv.get(key);
    return typeof row?.value === 'string' ? row.value : undefined;
  }

  async loadDetailed(): Promise<SaveLoad> {
    const now = this.clock();
    let raw: string | undefined;
    try {
      raw = await this.getStr(KV.save);
    } catch (e) {
      // 存储本身读不出来（不是档坏了）—— 不碰 corrupt / bak，照旧给默认
      console.error('[save] 读档抛异常', e);
      return { data: freshSave(now), source: 'none' };
    }
    if (raw === undefined) return { data: freshSave(now), source: 'none' };

    const main = parseSave(raw, now);
    if (main) {
      this.lastGood = raw;
      return { data: main, source: 'primary' };
    }

    // 主档坏了：先把原串留一份（空串没得留），再退回 bak
    if (raw) {
      try {
        await this.db.kv.put({ key: KV.saveCorrupt, value: raw });
      } catch (e) {
        console.error('[save] 坏档另存失败', e);
      }
    }
    let bak: string | undefined;
    try {
      bak = await this.getStr(KV.saveBak);
    } catch {
      bak = undefined;
    }
    const restored = bak === undefined ? null : parseSave(bak, now);
    if (restored && bak !== undefined) {
      try {
        await this.db.kv.put({ key: KV.save, value: bak });
      } catch (e) {
        console.error('[save] 备份写回主档失败', e);
      }
      this.lastGood = bak;
      this.bakMirror = bak;
      return { data: restored, source: 'backup' };
    }
    return { data: freshSave(now), source: 'corrupt' };
  }

  async load(): Promise<SaveData> {
    return (await this.loadDetailed()).data;
  }

  /** 存盘：先把上一份好档滚进 bak，再写主档（同一事务）。冻结时静默跳过。 */
  async save(data: SaveData): Promise<void> {
    if (this.frozen) return;
    const raw = stringifySave(data, this.clock());
    const prev = this.lastGood;
    const rollBak = prev !== null && prev !== this.bakMirror;
    await this.db.transaction('rw', this.db.kv, async () => {
      if (rollBak && prev !== null) await this.db.kv.put({ key: KV.saveBak, value: prev });
      await this.db.kv.put({ key: KV.save, value: raw });
    });
    if (rollBak) this.bakMirror = prev;
    this.lastGood = raw;
  }

  /** 冻结（重置 / 导入时）：之后的 save() 一律跳过 */
  freeze(): void {
    this.frozen = true;
  }

  /** 重置后重新绑定前解冻；同时忘掉内存里的旧好档，免得被滚进新 bak */
  unfreeze(): void {
    this.frozen = false;
  }

  /** 忘掉内存里记着的好档（重置后调用） */
  forget(): void {
    this.lastGood = null;
    this.bakMirror = null;
  }

  /** 调试用：直接读原串 */
  async rawRead(key: string = KV.save): Promise<string | undefined> {
    return this.getStr(key);
  }
}
