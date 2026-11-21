/**
 * 运行时单例装配：一个库、一个存档仓库、一份自动存档。
 * 测试不走这里，各自 new 自己的 HostDb / SaveRepo。
 */
import { appDb } from './db';
import { DataRepo } from './dataRepo';
import { gameStore } from './gameStore';
import { createPersistence } from './persistence';
import { SaveRepo } from './saveRepo';

export const saveRepo = new SaveRepo(appDb());
export const dataRepo = new DataRepo(appDb(), saveRepo);
export const persistence = createPersistence(gameStore, saveRepo);
