/**
 * 音效总线的对外接口。界面只认事件名；具体怎么发声（素材、优先级、并发上限、解锁）
 * 在 audio/bus.ts 里实现，第 7 步接入前这里全是静音的空实现。
 */
export type SfxName =
  /** 按下（基础按钮组件自己负责） */
  | 'press'
  | 'soft'
  | 'swipe'
  | 'whoosh'
  | 'type'
  | 'tick'
  | 'deal'
  | 'success'
  | 'error'
  | 'coin'
  | 'buy'
  | 'stamp'
  | 'crit'
  | 'levelup'
  | 'unlock'
  | 'fail'
  | 'boot'
  | 'scan'
  | 'shield';

export interface SfxBus {
  play(name: SfxName): void;
  holdStart(): void;
  holdSet(p: number): void;
  holdStop(): void;
  /** 第一次用户手势时解锁音频 */
  unlock(): void;
  setMuted(m: boolean): void;
  setVolume(v: number): void;
  /** 前后台切换：后台停底噪 */
  setForeground(v: boolean): void;
  ambient(on: boolean): void;
}

const silent: SfxBus = {
  play() {},
  holdStart() {},
  holdSet() {},
  holdStop() {},
  unlock() {},
  setMuted() {},
  setVolume() {},
  setForeground() {},
  ambient() {},
};

let bus: SfxBus = silent;

/** 第 7 步装上真正的总线 */
export function installSfx(b: SfxBus): void {
  bus = b;
}

export const sfx: SfxBus = {
  play: (n) => bus.play(n),
  holdStart: () => bus.holdStart(),
  holdSet: (p) => bus.holdSet(p),
  holdStop: () => bus.holdStop(),
  unlock: () => bus.unlock(),
  setMuted: (m) => bus.setMuted(m),
  setVolume: (v) => bus.setVolume(v),
  setForeground: (v) => bus.setForeground(v),
  ambient: (on) => bus.ambient(on),
};
