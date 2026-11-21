/**
 * 发声调度（纯逻辑，可单测）：事件 → 层级 / 优先级，同时发声上限，抢占与节流。
 *
 *  - critical（结算印章 / 暴击 / 升级 / 失败 / 护盾）永远能发声；发声期间压低界面音
 *  - 满了：抢占优先级最低、最早开始的那一路；新音比所有在播的都低 → 丢掉新音
 *  - texture（打字）在关键音发声时直接静掉；同名音有最小间隔与同时路数上限
 */
import type { SfxName } from './sfx';

export type Tier = 'critical' | 'event' | 'ui' | 'texture';

export const TIER_PRIORITY: Record<Tier, number> = { critical: 3, event: 2, ui: 1, texture: 0 };

export const SFX_TIER: Record<SfxName, Tier> = {
  stamp: 'critical',
  crit: 'critical',
  levelup: 'critical',
  fail: 'critical',
  shield: 'critical',
  success: 'event',
  error: 'event',
  coin: 'event',
  buy: 'event',
  unlock: 'event',
  boot: 'event',
  deal: 'event',
  press: 'ui',
  soft: 'ui',
  swipe: 'ui',
  whoosh: 'ui',
  tick: 'ui',
  scan: 'ui',
  type: 'texture',
};

/** 同名音的最小间隔（毫秒）与同时路数 */
const MIN_GAP: Partial<Record<SfxName, number>> = { type: 28, press: 30, tick: 40, coin: 50, soft: 40 };
const MAX_SAME = 3;

export const MAX_VOICES = 8;

export interface Voice {
  id: number;
  name: SfxName;
  prio: number;
  startedAt: number;
}

export type Decision = { play: false } | { play: true; evict: Voice | null };

export class VoicePool {
  readonly voices: Voice[] = [];
  private lastAt = new Map<SfxName, number>();
  private seq = 0;

  constructor(private readonly cap = MAX_VOICES) {}

  get criticalPlaying(): boolean {
    return this.voices.some((v) => v.prio === TIER_PRIORITY.critical);
  }

  /** 要不要播；要抢占的话返回被挤掉的那一路（调用方负责停掉它） */
  decide(name: SfxName, now: number): Decision {
    const tier = SFX_TIER[name];
    const prio = TIER_PRIORITY[tier];
    const gap = MIN_GAP[name];
    const last = this.lastAt.get(name);
    if (gap !== undefined && last !== undefined && now - last < gap) return { play: false };
    if (tier === 'texture' && this.criticalPlaying) return { play: false };
    if (this.voices.filter((v) => v.name === name).length >= MAX_SAME) {
      const oldest = this.voices.filter((v) => v.name === name).sort((a, b) => a.startedAt - b.startedAt)[0];
      return { play: true, evict: oldest ?? null };
    }
    if (this.voices.length < this.cap) return { play: true, evict: null };
    const victim = [...this.voices].sort((a, b) => a.prio - b.prio || a.startedAt - b.startedAt)[0];
    if (!victim || victim.prio > prio) return { play: false };
    return { play: true, evict: victim };
  }

  /** 真的开播了：登记 */
  add(name: SfxName, now: number): Voice {
    const v: Voice = { id: ++this.seq, name, prio: TIER_PRIORITY[SFX_TIER[name]], startedAt: now };
    this.voices.push(v);
    this.lastAt.set(name, now);
    return v;
  }

  /** 播完 / 被挤掉：释放 */
  remove(id: number): void {
    const i = this.voices.findIndex((v) => v.id === id);
    if (i >= 0) this.voices.splice(i, 1);
  }
}
