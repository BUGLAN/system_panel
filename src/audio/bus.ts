/**
 * Web Audio 音效总线（第 7 步，按 build-game-audio-feedback skill 设计）：
 *  - 第一次用户手势时才建 AudioContext 并解锁；iOS 支持时设 navigator.audioSession.type = 'ambient'
 *    （跟随静音键、和别的 App 混音，不打断用户在听的歌）
 *  - 素材启动时预取解码（SW 预缓存，断网也有声）
 *  - 主音量 / 静音；界面音走单独的总线，关键音发声时压低它
 *  - 同时发声上限 8 路，按优先级抢占（voices.ts）；播完 / 被挤掉立刻断开释放
 *  - 按住认输的循环音：音高随进度推；底噪只在大厅、前台、没静音时响，切后台就停
 */
import type { SfxBus, SfxName } from './sfx';
import { SFX_TIER, VoicePool } from './voices';

const FILES: Record<SfxName | 'hold' | 'ambient', string> = {
  press: 'press.mp3',
  soft: 'soft.mp3',
  swipe: 'swipe.mp3',
  whoosh: 'whoosh.mp3',
  type: 'type.mp3',
  tick: 'tick.mp3',
  deal: 'deal.mp3',
  success: 'success.mp3',
  error: 'error.mp3',
  coin: 'coin.mp3',
  buy: 'buy.mp3',
  stamp: 'stamp.mp3',
  crit: 'crit.mp3',
  levelup: 'levelup.mp3',
  unlock: 'unlock.mp3',
  fail: 'fail.mp3',
  boot: 'boot.mp3',
  scan: 'scan.mp3',
  shield: 'shield.mp3',
  hold: 'hold.wav',
  ambient: 'ambient.wav',
};

/** 各层的相对音量 */
const TIER_GAIN = { critical: 1, event: 0.8, ui: 0.5, texture: 0.35 } as const;
const AMBIENT_GAIN = 0.14;

type Key = keyof typeof FILES;

interface Playing {
  src: AudioBufferSourceNode;
  gain: GainNode;
}

export function createAudioBus(base = '/audio/'): SfxBus {
  let ctx: AudioContext | null = null;
  let master: GainNode | null = null;
  let uiBus: GainNode | null = null;
  let fxBus: GainNode | null = null;
  const buffers = new Map<Key, AudioBuffer>();
  const pool = new VoicePool();
  const playing = new Map<number, Playing>();
  let muted = false;
  let volume = 0.8;
  let foreground = true;
  let wantAmbient = false;
  let amb: Playing | null = null;
  let hold: (Playing & { rate: number }) | null = null;
  let loading: Promise<void> | null = null;

  const applyVolume = () => {
    if (!ctx || !master) return;
    master.gain.setTargetAtTime(muted ? 0 : volume, ctx.currentTime, 0.02);
  };

  function ensure(): AudioContext | null {
    if (ctx) return ctx;
    const AC = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!AC) return null;
    try {
      const session = (navigator as Navigator & { audioSession?: { type: string } }).audioSession;
      if (session) session.type = 'ambient';
    } catch {
      /* 老版本没有就算了 */
    }
    ctx = new AC();
    const comp = ctx.createDynamicsCompressor();
    comp.threshold.value = -12;
    comp.ratio.value = 4;
    master = ctx.createGain();
    uiBus = ctx.createGain();
    fxBus = ctx.createGain();
    uiBus.connect(master);
    fxBus.connect(master);
    master.connect(comp);
    comp.connect(ctx.destination);
    applyVolume();
    loading ??= load();
    return ctx;
  }

  async function load(): Promise<void> {
    const c = ctx;
    if (!c) return;
    await Promise.all(
      (Object.keys(FILES) as Key[]).map(async (k) => {
        try {
          const r = await fetch(base + FILES[k]);
          const data = await r.arrayBuffer();
          buffers.set(k, await c.decodeAudioData(data));
        } catch (e) {
          console.warn('[audio] 素材读不出来', k, e);
        }
      }),
    );
    syncAmbient();
  }

  function release(id: number): void {
    const p = playing.get(id);
    if (!p) return;
    playing.delete(id);
    pool.remove(id);
    try {
      p.src.disconnect();
      p.gain.disconnect();
    } catch {
      /* 已经断开 */
    }
  }

  function duck(): void {
    if (!ctx || !uiBus) return;
    const t = ctx.currentTime;
    uiBus.gain.cancelScheduledValues(t);
    uiBus.gain.setTargetAtTime(0.3, t, 0.01);
    uiBus.gain.setTargetAtTime(1, t + 0.45, 0.12);
  }

  function syncAmbient(): void {
    const on = wantAmbient && foreground && !muted && !!ctx && ctx.state === 'running';
    if (on && !amb && ctx && fxBus) {
      const b = buffers.get('ambient');
      if (!b) return;
      const src = ctx.createBufferSource();
      src.buffer = b;
      src.loop = true;
      const gain = ctx.createGain();
      gain.gain.value = 0;
      gain.gain.setTargetAtTime(AMBIENT_GAIN, ctx.currentTime, 0.4);
      src.connect(gain).connect(fxBus);
      src.start();
      amb = { src, gain };
    } else if (!on && amb && ctx) {
      const a = amb;
      amb = null;
      a.gain.gain.setTargetAtTime(0, ctx.currentTime, 0.12);
      setTimeout(() => {
        try {
          a.src.stop();
          a.src.disconnect();
          a.gain.disconnect();
        } catch {
          /* 已停 */
        }
      }, 600);
    }
  }

  return {
    unlock() {
      const c = ensure();
      if (c && c.state === 'suspended' && foreground) void c.resume().then(syncAmbient);
    },
    play(name) {
      if (muted || !ctx || ctx.state !== 'running' || !uiBus || !fxBus) return;
      const b = buffers.get(name);
      if (!b) return;
      const now = performance.now();
      const d = pool.decide(name, now);
      if (!d.play) return;
      if (d.evict) {
        const ev = playing.get(d.evict.id);
        try {
          ev?.src.stop();
        } catch {
          /* 已停 */
        }
        release(d.evict.id);
      }
      const tier = SFX_TIER[name];
      if (tier === 'critical') duck();
      const src = ctx.createBufferSource();
      src.buffer = b;
      if (tier === 'texture' || name === 'press') src.playbackRate.value = 0.96 + Math.random() * 0.08;
      const gain = ctx.createGain();
      gain.gain.value = TIER_GAIN[tier];
      src.connect(gain).connect(tier === 'ui' || tier === 'texture' ? uiBus : fxBus);
      const v = pool.add(name, now);
      playing.set(v.id, { src, gain });
      src.onended = () => release(v.id);
      src.start();
    },
    holdStart() {
      if (muted || !ctx || ctx.state !== 'running' || !fxBus || hold) return;
      const b = buffers.get('hold');
      if (!b) return;
      const src = ctx.createBufferSource();
      src.buffer = b;
      src.loop = true;
      const gain = ctx.createGain();
      gain.gain.value = 0;
      gain.gain.setTargetAtTime(0.5, ctx.currentTime, 0.04);
      src.connect(gain).connect(fxBus);
      src.start();
      hold = { src, gain, rate: 1 };
    },
    holdSet(p) {
      if (!hold || !ctx) return;
      hold.src.playbackRate.setTargetAtTime(1 + p * 4.6, ctx.currentTime, 0.03);
    },
    holdStop() {
      if (!hold || !ctx) return;
      const h = hold;
      hold = null;
      h.gain.gain.setTargetAtTime(0, ctx.currentTime, 0.03);
      setTimeout(() => {
        try {
          h.src.stop();
          h.src.disconnect();
          h.gain.disconnect();
        } catch {
          /* 已停 */
        }
      }, 200);
    },
    setMuted(m) {
      muted = m;
      applyVolume();
      syncAmbient();
    },
    setVolume(v) {
      volume = Math.min(1, Math.max(0, v));
      applyVolume();
    },
    setForeground(v) {
      foreground = v;
      if (!ctx) return;
      if (v) void ctx.resume().then(syncAmbient);
      else {
        syncAmbient();
        // 切后台：停底噪、挂起整个音频上下文（省电，也不会在后台出声）
        setTimeout(() => {
          if (!foreground && ctx?.state === 'running') void ctx.suspend();
        }, 300);
      }
    },
    ambient(on) {
      wantAmbient = on;
      syncAmbient();
    },
  };
}
