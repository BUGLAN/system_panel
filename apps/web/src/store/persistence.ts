/**
 * 把存档状态接到磁盘：读档 → hydrate → arm 自动存档；之后 `game` 引用一变就请求存一次。
 * 切后台（页面隐藏）时立刻补一次，顺带盖上 lastSeen。
 */
import { createAutosave, type Autosave } from './autosave';
import type { GameStore } from './gameStore';
import type { SaveRepo, SaveSource } from './saveRepo';

export interface Persistence {
  autosave: Autosave;
  /** 读档并开始自动存档 */
  boot(): Promise<SaveSource>;
  /** 等在途写入落盘 */
  flush(): Promise<void>;
  /** 停止订阅（测试 / 热更新用） */
  stop(): void;
}

/** 只用到 document 的这一小块（测试里可以塞假的） */
export interface VisibilitySource {
  readonly visibilityState: DocumentVisibilityState;
  addEventListener(type: 'visibilitychange', fn: () => void): void;
  removeEventListener(type: 'visibilitychange', fn: () => void): void;
}

export function createPersistence(
  store: GameStore,
  repo: SaveRepo,
  doc: VisibilitySource | null = typeof document === 'undefined' ? null : document,
): Persistence {
  const autosave = createAutosave({
    read: () => store.getState().game,
    write: (g) => repo.save(g),
  });

  const unsub = store.subscribe((s, prev) => {
    if (s.loaded && s.game !== prev.game) autosave.request();
  });

  const onHidden = () => {
    if (doc?.visibilityState === 'hidden') autosave.request();
  };
  doc?.addEventListener('visibilitychange', onHidden);

  return {
    autosave,
    async boot() {
      const { data, source } = await repo.loadDetailed();
      store.getState().hydrate(data, source);
      autosave.arm();
      return source;
    },
    flush: () => autosave.flush(),
    stop() {
      unsub();
      doc?.removeEventListener('visibilitychange', onHidden);
    },
  };
}
