/**
 * 在途的视觉校验登记：交单时最多等 20 秒（等不到的按未校验算）。
 * 校验本体在证据模块里发起，这里只管「谁还没回来」。
 */
export const SUBMIT_WAIT_MS = 20_000;

export class CheckRegistry {
  private readonly inflight = new Map<string, Promise<void>>();

  private key(userId: string, id: string): string {
    return `${userId}:${id}`;
  }

  track(userId: string, id: string, job: Promise<void>): void {
    const k = this.key(userId, id);
    const p = job.finally(() => {
      if (this.inflight.get(k) === p) this.inflight.delete(k);
    });
    this.inflight.set(k, p);
  }

  pending(userId: string, ids: string[]): string[] {
    return ids.filter((id) => this.inflight.has(this.key(userId, id)));
  }

  /** 等这些 id 的校验，最多 ms 毫秒；返回是否全部按时回来 */
  async waitFor(userId: string, ids: string[], ms = SUBMIT_WAIT_MS): Promise<boolean> {
    const jobs = ids
      .map((id) => this.inflight.get(this.key(userId, id)))
      .filter((p): p is Promise<void> => !!p);
    if (!jobs.length) return true;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const timeout = new Promise<false>((r) => (timer = setTimeout(() => r(false), ms)));
    try {
      return await Promise.race([Promise.allSettled(jobs).then(() => true as const), timeout]);
    } finally {
      clearTimeout(timer);
    }
  }
}
