import { readFileSync } from 'node:fs';
import { describe, expect, test } from 'vitest';
import { COLORS, GRADE_COLORS, MOTION, RANK_COLORS, easeOutCubic } from '../../src/design/tokens';
import { RANKS } from '@host/core/data/rank';

const css = readFileSync(new URL('../../src/design/tokens.css', import.meta.url), 'utf8');

function cssVar(name: string): string {
  const m = new RegExp(`--${name}:\\s*([^;]+);`).exec(css);
  if (!m?.[1]) throw new Error(`tokens.css 里没有 --${name}`);
  return m[1].trim().toLowerCase();
}

describe('设计令牌：CSS 是唯一源，TS 镜像与它一致', () => {
  test('底色与强调色（docs/00 第四节）', () => {
    expect(cssVar('bg')).toBe('#06050c');
    expect(cssVar('acid')).toBe('#d6ff3d');
    expect(cssVar('cyan')).toBe('#3be8ff');
    expect(cssVar('hot')).toBe('#ff3b7a');
    expect(cssVar('violet')).toBe('#8f6bff');
    expect(cssVar('gold')).toBe('#ffcc4d');
    expect(cssVar('mint')).toBe('#3dffa8');
  });

  test('TS 侧颜色逐项等于 CSS 变量', () => {
    const map: Record<string, string> = {
      bg: 'bg',
      ink: 'ink',
      acid: 'acid',
      hot: 'hot',
      cyan: 'cyan',
      violet: 'violet',
      gold: 'gold',
      mint: 'mint',
      txt: 'txt',
      dim: 'dim',
      dim2: 'dim2',
      onAccent: 'on-accent',
      flame: 'flame',
      flameCore: 'flame-core',
    };
    for (const [k, v] of Object.entries(map)) {
      expect(COLORS[k as keyof typeof COLORS], k).toBe(cssVar(v));
    }
  });

  test('稀有度色谱 = flutter-final Ref.rank（E 薄荷 / D 青 / C 紫 / B 金 / A 品红 / S 白 / F 灰）', () => {
    const ref = {
      F: '#9aa3b2',
      E: '#3dffa8',
      D: '#3be8ff',
      C: '#8f6bff',
      B: '#ffcc4d',
      A: '#ff3b7a',
      S: '#ffffff',
    };
    for (const r of RANKS) {
      expect(RANK_COLORS[r], r).toBe(ref[r]);
      expect(cssVar(`rank-${r.toLowerCase()}`), r).toBe(ref[r]);
    }
  });

  test('评级色：S 白 / A acid / B cyan / C hot（docs/50 A13）', () => {
    for (const [g, c] of Object.entries(GRADE_COLORS)) {
      expect(cssVar(`grade-${g.toLowerCase()}`)).toBe(c);
    }
    expect(GRADE_COLORS.A).toBe(COLORS.acid);
    expect(GRADE_COLORS.C).toBe(COLORS.hot);
  });

  test('字体族不引外链字体名之外的东西，三套都在', () => {
    expect(cssVar('fd')).toContain('chakra petch');
    expect(cssVar('fc')).toContain('noto sans sc variable');
    expect(cssVar('fm')).toContain('jetbrains mono variable');
    expect(css).not.toContain('fonts.googleapis.com');
  });

  test('动效参数（不许凭感觉改）', () => {
    expect(MOTION.spring).toMatchObject({ stiffness: 100, damping: 20 });
    expect(MOTION.springOvershoot).toBe(1.08);
    expect(MOTION.flash).toMatchObject({ opacity: 0.16, ms: 180 });
    expect(MOTION.countUpMs).toBe(800);
    expect(MOTION.critFreezeMs).toBe(200);
    expect(MOTION.critStampFrom).toBe(2.2);
    expect([MOTION.expBarMs, MOTION.expBarFillMs, MOTION.expBarRefillMs]).toEqual([520, 360, 420]);
    expect([MOTION.settleMaxMs, MOTION.levelUpMaxMs, MOTION.publishMaxMs]).toEqual([
      1600, 2000, 800,
    ]);
    expect(MOTION.failBrightness).toBeCloseTo(1 / 3);
    expect(MOTION.typeMsPerChar).toBe(34);
  });

  test('ease-out cubic：两端钉住、中段先快后慢', () => {
    expect(easeOutCubic(0)).toBe(0);
    expect(easeOutCubic(1)).toBe(1);
    expect(easeOutCubic(0.5)).toBeCloseTo(0.875);
    expect(easeOutCubic(2)).toBe(1);
  });
});
