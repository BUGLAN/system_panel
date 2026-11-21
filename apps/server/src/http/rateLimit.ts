/**
 * 进程内固定窗口限流（单进程部署够用；多实例不在范围内，见 AGENTS.md 已知事项）。
 */
export class RateLimiter {
  private readonly hits = new Map<string, { start: number; n: number }>();
  private sweepAt = 0;

  constructor(private readonly clock: () => number = Date.now) {}

  /**
   * 记一次；超限返回需要等待的秒数，没超返回 0。
   * 超限的那次不计入（免得越拦越久）。
   */
  hit(key: string, limit: number, windowMs: number): number {
    const t = this.clock();
    this.sweep(t, windowMs);
    const cur = this.hits.get(key);
    if (!cur || t - cur.start >= windowMs) {
      this.hits.set(key, { start: t, n: 1 });
      return 0;
    }
    if (cur.n >= limit) return Math.max(1, Math.ceil((cur.start + windowMs - t) / 1000));
    cur.n++;
    return 0;
  }

  /** 登录成功后清掉该用户名的失败计数 */
  reset(key: string): void {
    this.hits.delete(key);
  }

  private sweep(t: number, windowMs: number): void {
    if (t < this.sweepAt) return;
    this.sweepAt = t + 60_000;
    for (const [k, v] of this.hits)
      if (t - v.start >= Math.max(windowMs, 3_600_000)) this.hits.delete(k);
  }
}
