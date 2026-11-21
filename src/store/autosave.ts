/**
 * 自动存档：任何改动存档字段的操作完成后请求一次，同一拍（microtask）里的多次请求合并，
 * 写盘排成串行链；真正写的时候读**那一刻的最新状态**，所以写入期间的新改动只会再写一次。
 * 读档完成（arm）之前的请求一律忽略，免得把默认空档写进去。
 * 移植自 flutter-final 的 `_requestSave`（docs/50 F2）。
 */
export interface Autosave {
  /** 读档完成后调用，之后的请求才生效 */
  arm(): void;
  /** 停止写盘（重置 / 导入时） */
  disarm(): void;
  readonly armed: boolean;
  /** 请求存一次（同一拍合并） */
  request(): void;
  /** 等所有已请求的写入落盘 */
  flush(): Promise<void>;
}

export interface AutosaveOptions<T> {
  read: () => T;
  write: (value: T) => Promise<void>;
  onError?: (e: unknown) => void;
}

export function createAutosave<T>(opts: AutosaveOptions<T>): Autosave {
  let armed = false;
  let dirty = false;
  let tickQueued = false;
  let chain: Promise<void> = Promise.resolve();

  async function drain(): Promise<void> {
    if (!dirty || !armed) return;
    dirty = false;
    const value = opts.read();
    try {
      await opts.write(value);
    } catch (e) {
      (opts.onError ?? ((err) => console.error('[autosave] 写盘失败', err)))(e);
    }
  }

  return {
    arm() {
      armed = true;
    },
    disarm() {
      armed = false;
      dirty = false;
    },
    get armed() {
      return armed;
    },
    request() {
      if (!armed) return;
      dirty = true;
      if (tickQueued) return;
      tickQueued = true;
      queueMicrotask(() => {
        tickQueued = false;
        chain = chain.then(drain);
      });
    },
    flush() {
      // 先让同一拍里排着的请求进链，再等链跑完
      return new Promise<void>((r) => queueMicrotask(r)).then(() => chain);
    },
  };
}
