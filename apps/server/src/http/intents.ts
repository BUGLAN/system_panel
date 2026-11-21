/**
 * 写意图去重：同一用户同一个 intentId（请求头 x-intent-id）10 分钟内只执行一次，
 * 重复的直接回第一次的响应（防网络重试导致买两次 / 交两次）。
 */
const TTL_MS = 10 * 60_000;
const MAX = 5_000;

interface Entry {
  at: number;
  res: Promise<{ status: number; body: unknown }>;
}

export class IntentCache {
  private readonly map = new Map<string, Entry>();

  constructor(private readonly clock: () => number = Date.now) {}

  async once(
    key: string | null,
    run: () => Promise<{ status: number; body: unknown }>,
  ): Promise<{ status: number; body: unknown }> {
    if (!key) return run();
    const t = this.clock();
    const hit = this.map.get(key);
    if (hit && t - hit.at < TTL_MS) return hit.res;
    if (this.map.size >= MAX) this.sweep(t);
    const res = run();
    this.map.set(key, { at: t, res });
    // 意外异常不缓存：下次同一个 intentId 允许重试
    res.catch(() => this.map.delete(key));
    return res;
  }

  private sweep(t: number): void {
    for (const [k, v] of this.map) if (t - v.at >= TTL_MS) this.map.delete(k);
    if (this.map.size >= MAX) this.map.clear();
  }
}
