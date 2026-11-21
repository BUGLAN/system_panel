import { describe, expect, test } from 'vitest';
import { MAX_VOICES, SFX_TIER, VoicePool } from '../../src/audio/voices';

describe('发声调度：优先级 / 上限 / 抢占 / 节流', () => {
  test('结算、暴击、升级、失败、护盾是关键层', () => {
    for (const n of ['stamp', 'crit', 'levelup', 'fail', 'shield'] as const)
      expect(SFX_TIER[n]).toBe('critical');
  });

  test('同时发声不超过 8 路；满了挤掉优先级最低、最早的那一路', () => {
    const p = new VoicePool();
    const names = ['swipe', 'soft', 'whoosh', 'scan', 'tick', 'success', 'coin', 'deal'] as const;
    names.forEach((n, i) => {
      const d = p.decide(n, i * 100);
      expect(d.play).toBe(true);
      p.add(n, i * 100);
    });
    expect(p.voices).toHaveLength(MAX_VOICES);
    const d = p.decide('crit', 1000);
    expect(d).toMatchObject({ play: true, evict: { name: 'swipe' } });
  });

  test('关键音不会被界面音盖掉：满员都是关键音时，界面音直接不播', () => {
    const p = new VoicePool(2);
    p.add('stamp', 0);
    p.add('crit', 1);
    expect(p.decide('press', 100)).toEqual({ play: false });
    expect(p.decide('levelup', 100)).toMatchObject({ play: true, evict: { name: 'stamp' } });
  });

  test('关键音发声时打字音静掉', () => {
    const p = new VoicePool();
    p.add('levelup', 0);
    expect(p.decide('type', 100)).toEqual({ play: false });
  });

  test('快速连点：同名音有最小间隔；同名最多 3 路，多了挤掉最早的', () => {
    const p = new VoicePool();
    p.add('press', 0);
    expect(p.decide('press', 10)).toEqual({ play: false });
    expect(p.decide('press', 40).play).toBe(true);
    p.add('press', 40);
    p.add('press', 80);
    expect(p.decide('press', 120)).toMatchObject({ play: true, evict: { startedAt: 0 } });
  });

  test('播完释放：移除后路数回落', () => {
    const p = new VoicePool();
    const v = p.add('success', 0);
    p.remove(v.id);
    expect(p.voices).toHaveLength(0);
  });
});
