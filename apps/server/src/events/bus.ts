/**
 * 用户事件总线：服务端发生的事（存档版本变了、拆解进度、视觉校验结论）推给这个用户的所有在线页面（SSE）。
 * 进程内实现（单进程部署）。
 */
export type BusEvent =
  | { type: 'state'; version: number }
  | { type: 'job'; job: unknown }
  | { type: 'verdict'; verdict: unknown };

type Listener = (e: BusEvent) => void;

export class EventBus {
  private readonly subs = new Map<string, Set<Listener>>();

  subscribe(userId: string, fn: Listener): () => void {
    let set = this.subs.get(userId);
    if (!set) {
      set = new Set();
      this.subs.set(userId, set);
    }
    set.add(fn);
    return () => {
      set.delete(fn);
      if (!set.size) this.subs.delete(userId);
    };
  }

  publish(userId: string, e: BusEvent): void {
    for (const fn of this.subs.get(userId) ?? []) {
      try {
        fn(e);
      } catch {
        // 某个连接坏了不影响别人
      }
    }
  }

  listeners(userId: string): number {
    return this.subs.get(userId)?.size ?? 0;
  }
}
