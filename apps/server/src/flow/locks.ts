/**
 * 每用户串行：同一用户的「读档 → 跑流程 → 写回」排队执行（进程内 Promise 链）。
 * 只在这一小段持锁；等 LLM / 等视觉校验时不持锁，回来后重新拿锁、重读最新存档。
 */
export class UserLocks {
  private readonly tails = new Map<string, Promise<unknown>>();

  async run<T>(userId: string, fn: () => T | Promise<T>): Promise<T> {
    const prev = this.tails.get(userId) ?? Promise.resolve();
    let release!: () => void;
    const mine = new Promise<void>((r) => (release = r));
    const tail = prev.then(() => mine);
    this.tails.set(userId, tail);
    try {
      await prev;
      return await fn();
    } finally {
      release();
      if (this.tails.get(userId) === tail) this.tails.delete(userId);
    }
  }
}
