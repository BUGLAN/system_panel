#!/usr/bin/env node
/**
 * 宿主养成系统 · 音效离线合成（零依赖，同 seed 逐字节可复现）
 *
 *   node tools/audio/gen-sfx.mjs            # 合成 wav → tools/audio/.out/，再用 ffmpeg 转 mp3 → public/audio/
 *   node tools/audio/gen-sfx.mjs --wav-only # 只出 wav（没装 ffmpeg 时）
 *   node tools/audio/gen-sfx.mjs --list     # 列清单
 *
 * 设计原则（build-game-audio-feedback）：按事件分层、关键反馈更响更长、界面音短而轻、
 * 失败更短更暗更安静；所有素材 44.1kHz 单声道，主链路软限幅，峰值统一到 -1dBFS 以下。
 */
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SR = 44100;
const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const OUT_WAV = join(ROOT, 'tools', 'audio', '.out');
const OUT_MP3 = join(ROOT, 'public', 'audio');

// ── 可复现的随机 ──────────────────────────────────────────
let seed = 20261121;
const rnd = () => {
  seed = (seed + 0x6d2b79f5) >>> 0;
  let t = seed;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};

// ── 基础件 ───────────────────────────────────────────────
const buf = (sec) => new Float32Array(Math.ceil(sec * SR));

/** 振荡器：f / f2 指数扫频，env：attack + 指数衰减 */
function tone(
  out,
  { f = 440, f2 = 0, t = 0.12, type = 'sine', v = 0.25, at = 0.004, delay = 0, det = 0 },
) {
  const n0 = Math.floor(delay * SR);
  const n = Math.floor(t * SR);
  let ph = 0;
  for (let i = 0; i < n && n0 + i < out.length; i++) {
    const k = i / n;
    const fr = (f2 ? f * Math.pow(f2 / f, k) : f) * Math.pow(2, det / 1200);
    ph += fr / SR;
    const x = ph % 1;
    let s;
    if (type === 'sine') s = Math.sin(2 * Math.PI * x);
    else if (type === 'square') s = x < 0.5 ? 0.8 : -0.8;
    else if (type === 'saw') s = 2 * x - 1;
    else s = 1 - 4 * Math.abs(x - 0.5); // triangle
    const atk = Math.min(1, i / Math.max(1, at * SR));
    const env = atk * Math.exp(-5.2 * k) * (1 - Math.pow(k, 6));
    out[n0 + i] += s * env * v;
  }
}

/** 噪声 + 二阶滤波（RBJ biquad），截止频率可扫 */
function noise(
  out,
  { t = 0.2, v = 0.3, f = 1200, f2 = 0, q = 1, type = 'bandpass', delay = 0, at = 0.002 },
) {
  const n0 = Math.floor(delay * SR);
  const n = Math.floor(t * SR);
  let x1 = 0;
  let x2 = 0;
  let y1 = 0;
  let y2 = 0;
  for (let i = 0; i < n && n0 + i < out.length; i++) {
    const k = i / n;
    const fc = Math.min(SR * 0.45, f2 ? f * Math.pow(f2 / f, k) : f);
    const w = (2 * Math.PI * fc) / SR;
    const al = Math.sin(w) / (2 * q);
    const cw = Math.cos(w);
    let b0, b1, b2;
    if (type === 'lowpass') [b0, b1, b2] = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2];
    else if (type === 'highpass') [b0, b1, b2] = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2];
    else [b0, b1, b2] = [al, 0, -al];
    const a0 = 1 + al;
    const a1 = -2 * cw;
    const a2 = 1 - al;
    const x0 = rnd() * 2 - 1;
    const y0 = (b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0;
    x2 = x1;
    x1 = x0;
    y2 = y1;
    y1 = y0;
    const atk = Math.min(1, i / Math.max(1, at * SR));
    out[n0 + i] += y0 * atk * Math.exp(-4.5 * k) * (1 - Math.pow(k, 6)) * v;
  }
}

const chord = (out, fs, o) =>
  fs.forEach((f, i) => tone(out, { ...o, f, delay: (o.delay ?? 0) + (o.step ?? 0) * i }));

/** 主链路：软限幅 + 峰值归一（-1dBFS） + 首尾 2ms 淡入淡出（无爆音） */
function master(x, gain = 1, peak = 0.89) {
  let m = 0;
  for (let i = 0; i < x.length; i++) {
    x[i] = Math.tanh(x[i] * gain * 1.4) / 1.4;
    m = Math.max(m, Math.abs(x[i]));
  }
  const g = m > 0 ? peak / m : 1;
  const fade = Math.floor(0.002 * SR);
  for (let i = 0; i < x.length; i++) {
    let e = 1;
    if (i < fade) e = i / fade;
    if (i > x.length - fade) e = (x.length - i) / fade;
    x[i] *= g * e;
  }
  return x;
}

/** 无缝循环：首尾交叉淡化 */
function loopify(x, xf = 0.25) {
  const n = Math.floor(xf * SR);
  const out = x.slice(0, x.length - n);
  for (let i = 0; i < n; i++) {
    const k = i / n;
    out[i] = out[i] * k + x[x.length - n + i] * (1 - k);
  }
  return out;
}

function wav(x, sr = SR) {
  const b = Buffer.alloc(44 + x.length * 2);
  b.write('RIFF', 0);
  b.writeUInt32LE(36 + x.length * 2, 4);
  b.write('WAVEfmt ', 8);
  b.writeUInt32LE(16, 16);
  b.writeUInt16LE(1, 20);
  b.writeUInt16LE(1, 22);
  b.writeUInt32LE(sr, 24);
  b.writeUInt32LE(sr * 2, 28);
  b.writeUInt16LE(2, 32);
  b.writeUInt16LE(16, 34);
  b.write('data', 36);
  b.writeUInt32LE(x.length * 2, 40);
  for (let i = 0; i < x.length; i++)
    b.writeInt16LE(Math.round(Math.max(-1, Math.min(1, x[i])) * 32767), 44 + i * 2);
  return b;
}

// ── 事件表：名字 · 层级 · 合成 ─────────────────────────────
// 层级：critical 结算 / 暴击 / 升级 / 失败 / 护盾；event 成功 / 错误 / 解锁 / 购买 / 晶核 / 开机 / 发牌；
//       ui 按下 / 轻点 / 切换 / 转场 / 扫描 / 刻度；texture 打字；loop 按住 / 底噪
export const SFX = {
  press: [
    'ui',
    () => {
      const x = buf(0.07);
      tone(x, { f: 1500, f2: 2100, t: 0.035, type: 'square', v: 0.05 });
      tone(x, { f: 220, f2: 110, t: 0.06, type: 'triangle', v: 0.22 });
      return master(x, 1, 0.55);
    },
  ],
  soft: [
    'ui',
    () => {
      const x = buf(0.06);
      tone(x, { f: 1400, f2: 1900, t: 0.045, type: 'sine', v: 0.2 });
      return master(x, 1, 0.45);
    },
  ],
  swipe: [
    'ui',
    () => {
      const x = buf(0.14);
      noise(x, { t: 0.13, v: 0.5, f: 3200, f2: 900, q: 0.7 });
      tone(x, { f: 520, f2: 780, t: 0.06, type: 'triangle', v: 0.1 });
      return master(x, 1, 0.5);
    },
  ],
  whoosh: [
    'ui',
    () => {
      const x = buf(0.5);
      noise(x, { t: 0.42, v: 0.7, f: 260, f2: 5200, q: 0.6, at: 0.08 });
      tone(x, { f: 140, f2: 55, t: 0.36, type: 'sine', v: 0.25 });
      return master(x, 1, 0.55);
    },
  ],
  tick: [
    'ui',
    () => {
      const x = buf(0.03);
      tone(x, { f: 2600, t: 0.022, type: 'square', v: 0.12 });
      return master(x, 1, 0.35);
    },
  ],
  scan: [
    'ui',
    () => {
      const x = buf(0.32);
      for (let i = 0; i < 4; i++)
        tone(x, {
          f: 1700 + i * 180,
          f2: 2300 + i * 180,
          t: 0.05,
          type: 'square',
          v: 0.06,
          delay: i * 0.07,
        });
      return master(x, 1, 0.45);
    },
  ],
  type: [
    'texture',
    () => {
      const x = buf(0.025);
      tone(x, { f: 1150 + rnd() * 400, t: 0.018, type: 'square', v: 0.1 });
      return master(x, 1, 0.22);
    },
  ],
  deal: [
    'event',
    () => {
      const x = buf(0.22);
      noise(x, { t: 0.09, v: 0.5, f: 4200, f2: 1500, q: 0.9 });
      tone(x, { f: 660, f2: 990, t: 0.12, type: 'triangle', v: 0.16, delay: 0.04 });
      return master(x, 1, 0.6);
    },
  ],
  success: [
    'event',
    () => {
      const x = buf(0.62);
      chord(x, [523.25, 659.25, 783.99, 1046.5], {
        t: 0.24,
        type: 'triangle',
        v: 0.18,
        step: 0.06,
      });
      chord(x, [1046.5, 1318.5], { t: 0.36, type: 'sine', v: 0.08, delay: 0.24, step: 0.05 });
      return master(x, 1, 0.7);
    },
  ],
  error: [
    'event',
    () => {
      const x = buf(0.38);
      tone(x, { f: 170, f2: 125, t: 0.16, type: 'saw', v: 0.16 });
      tone(x, { f: 120, f2: 82, t: 0.24, type: 'square', v: 0.1, delay: 0.1 });
      return master(x, 1, 0.6);
    },
  ],
  coin: [
    'event',
    () => {
      const x = buf(0.3);
      tone(x, { f: 987.77, t: 0.07, type: 'square', v: 0.09 });
      tone(x, { f: 1318.5, t: 0.22, type: 'square', v: 0.09, delay: 0.065 });
      return master(x, 1, 0.55);
    },
  ],
  buy: [
    'event',
    () => {
      const x = buf(0.6);
      tone(x, { f: 987.77, t: 0.07, type: 'square', v: 0.08 });
      tone(x, { f: 1318.5, t: 0.2, type: 'square', v: 0.08, delay: 0.065 });
      chord(x, [659.25, 880, 1318.5], {
        t: 0.2,
        type: 'triangle',
        v: 0.12,
        step: 0.05,
        delay: 0.16,
      });
      noise(x, { t: 0.3, v: 0.12, f: 6000, type: 'highpass', delay: 0.16 });
      return master(x, 1, 0.7);
    },
  ],
  unlock: [
    'event',
    () => {
      const x = buf(0.9);
      chord(x, [783.99, 987.77, 1174.7, 1568, 1975.5], {
        t: 0.42,
        type: 'sine',
        v: 0.12,
        step: 0.06,
      });
      noise(x, { t: 0.6, v: 0.08, f: 8000, type: 'highpass', delay: 0.05 });
      return master(x, 1, 0.7);
    },
  ],
  boot: [
    'event',
    () => {
      const x = buf(1.5);
      tone(x, { f: 60, f2: 180, t: 1.1, type: 'saw', v: 0.08, at: 0.2 });
      chord(x, [261.63, 392, 523.25, 783.99], {
        t: 0.9,
        type: 'triangle',
        v: 0.11,
        step: 0.12,
        delay: 0.3,
      });
      noise(x, { t: 1.0, v: 0.15, f: 200, f2: 6000, delay: 0.2, at: 0.3 });
      return master(x, 1, 0.75);
    },
  ],
  stamp: [
    'critical',
    () => {
      const x = buf(0.5);
      tone(x, { f: 115, f2: 38, t: 0.42, type: 'sine', v: 0.8 });
      noise(x, { t: 0.16, v: 0.55, f: 900, type: 'lowpass' });
      tone(x, { f: 55, t: 0.28, type: 'square', v: 0.07 });
      return master(x, 1.2, 0.9);
    },
  ],
  crit: [
    'critical',
    () => {
      const x = buf(1.0);
      noise(x, { t: 0.55, v: 0.5, f: 400, f2: 8000, q: 0.5, at: 0.05 });
      tone(x, { f: 200, f2: 1600, t: 0.42, type: 'saw', v: 0.14 });
      tone(x, { f: 115, f2: 38, t: 0.42, type: 'sine', v: 0.7, delay: 0.05 });
      chord(x, [1568, 2093, 2637], { t: 0.5, type: 'sine', v: 0.09, step: 0.04, delay: 0.34 });
      return master(x, 1.2, 0.92);
    },
  ],
  levelup: [
    'critical',
    () => {
      const x = buf(1.9);
      [523.25, 659.25, 783.99, 1046.5, 783.99, 1046.5, 1318.5, 1568].forEach((f, i) =>
        tone(x, { f, t: 0.2, type: 'square', v: 0.07, delay: i * 0.075 }),
      );
      chord(x, [523.25, 659.25, 783.99, 1046.5], {
        t: 1.15,
        type: 'triangle',
        v: 0.11,
        delay: 0.62,
      });
      noise(x, { t: 1.1, v: 0.1, f: 7000, type: 'highpass', delay: 0.6, at: 0.2 });
      return master(x, 1, 0.85);
    },
  ],
  // 失败：更短、更暗、更安静（峰值压到成功的约 1/2，且全部低通）
  fail: [
    'critical',
    () => {
      const x = buf(0.9);
      chord(x, [392, 329.63, 261.63, 196], { t: 0.36, type: 'triangle', v: 0.1, step: 0.13 });
      noise(x, { t: 0.7, v: 0.14, f: 600, f2: 120, type: 'lowpass' });
      return master(x, 1, 0.45);
    },
  ],
  shield: [
    'critical',
    () => {
      const x = buf(0.8);
      for (let i = 0; i < 5; i++)
        noise(x, { t: 0.08, v: 0.35, f: 5000 + rnd() * 3000, type: 'highpass', delay: i * 0.035 });
      chord(x, [2093, 1568, 1174.7, 880], { t: 0.3, type: 'sine', v: 0.1, step: 0.07, delay: 0.1 });
      tone(x, { f: 330, f2: 660, t: 0.35, type: 'triangle', v: 0.12, delay: 0.35 });
      return master(x, 1, 0.8);
    },
  ],
  hold: [
    'loop',
    () => {
      // 90Hz 锯齿 + 慢颤音，1 秒无缝；音高由 playbackRate 推（90 → 约 500Hz）
      const x = buf(1.25);
      let ph = 0;
      for (let i = 0; i < x.length; i++) {
        const f = 90 * (1 + 0.01 * Math.sin((2 * Math.PI * 6 * i) / SR));
        ph += f / SR;
        x[i] = ((ph % 1) * 2 - 1) * 0.25;
      }
      return master(loopify(x), 1, 0.4);
    },
  ],
  ambient: [
    'loop',
    () => {
      // 低频暗垫：两个失谐正弦 + 慢呼吸 + 极轻的风声，4 秒无缝
      const x = buf(4.5);
      for (let i = 0; i < x.length; i++) {
        const t = i / SR;
        const lfo = 0.6 + 0.4 * Math.sin((2 * Math.PI * t) / 4);
        x[i] =
          (Math.sin(2 * Math.PI * 55 * t) * 0.5 +
            Math.sin(2 * Math.PI * 82.6 * t) * 0.3 +
            Math.sin(2 * Math.PI * 110.3 * t) * 0.12) *
          lfo *
          0.3;
      }
      const air = buf(4.5);
      let y = 0;
      for (let i = 0; i < air.length; i++) {
        y += (rnd() * 2 - 1 - y) * 0.02;
        air[i] = y * 0.6;
      }
      for (let i = 0; i < x.length; i++) x[i] += air[i];
      return master(loopify(x, 0.5), 1, 0.35);
    },
  ],
};

// ── 主程序 ───────────────────────────────────────────────
const args = new Set(process.argv.slice(2));
if (args.has('--list')) {
  for (const [k, [tier]] of Object.entries(SFX)) console.log(`${k}\t${tier}`);
  process.exit(0);
}
mkdirSync(OUT_WAV, { recursive: true });
mkdirSync(OUT_MP3, { recursive: true });
/** 2:1 抽取（底噪只有低频，够用；循环素材体积减半） */
const halve = (x) => {
  const o = new Float32Array(Math.floor(x.length / 2));
  for (let i = 0; i < o.length; i++) o[i] = (x[2 * i] + x[2 * i + 1]) / 2;
  return o;
};
for (const [name, [tier, make]] of Object.entries(SFX)) {
  const x = make();
  const w = join(OUT_WAV, `${name}.wav`);
  writeFileSync(w, wav(x));
  if (tier === 'loop') {
    // 循环素材直接出 wav：mp3 的编码器补帧会在循环点留下接缝
    writeFileSync(
      join(OUT_MP3, `${name}.wav`),
      name === 'ambient' ? wav(halve(x), SR / 2) : wav(x),
    );
  } else if (!args.has('--wav-only')) {
    execFileSync('ffmpeg', [
      '-y',
      '-loglevel',
      'error',
      '-i',
      w,
      '-codec:a',
      'libmp3lame',
      '-q:a',
      '4',
      '-ac',
      '1',
      join(OUT_MP3, `${name}.mp3`),
    ]);
  }
  console.log(`${name.padEnd(8)} ${(x.length / SR).toFixed(2)}s`);
}
