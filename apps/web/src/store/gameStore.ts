/**
 * 存档镜像（Zustand）。整份存档放在 `game` 里；服务端每回一份新状态就整体替换引用。
 * 界面层只读，改存档只走 store/game.ts 的 intent()。
 */
import { createStore, type StoreApi } from 'zustand/vanilla';
import { useStore } from 'zustand';
import { freshSave, type SaveData } from '@host/core/save/saveData';
import type { SaveSource } from '@host/core/api/types';

export interface GameState {
  game: SaveData;
  /** 读档完成了吗（之前界面只显示开机屏，不许改存档） */
  loaded: boolean;
  /** 读档走的哪条路（服务端主档坏了、用备份恢复时界面要提示一句） */
  source: SaveSource | null;
  hydrate(game: SaveData, source: SaveSource): void;
  setGame(next: SaveData | ((g: SaveData) => SaveData)): void;
}

export type GameStore = StoreApi<GameState>;

export function createGameStore(now: number = Date.now()): GameStore {
  return createStore<GameState>()((set) => ({
    game: freshSave(now),
    loaded: false,
    source: null,
    hydrate(game, source) {
      set({ game, source, loaded: true });
    },
    setGame(next) {
      set((s) => ({ game: typeof next === 'function' ? next(s.game) : next }));
    },
  }));
}

/** App 运行时共用的那一个 */
export const gameStore: GameStore = createGameStore();

export function useGame<T>(selector: (s: GameState) => T): T {
  return useStore(gameStore, selector);
}
