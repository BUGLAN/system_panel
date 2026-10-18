#!/usr/bin/env node
/* tools/audio/gen_sfx.mjs — 离线音效烘焙器（零依赖，Node ≥ 18）
 *
 * 真源（逐条抄参数，不凭印象）：
 *   prototype/opus-v2-dir/js/audio.js
 *     Sound.play(name,x) [L70-135] · Sound.tone() [L32-52] · Sound.noise() [L53-66]
 *     Sound.ambient() [L157-171] · Voice.syllable() [L194-200] · Voice.PITCH [L183]
 *   批次③ 补件（task-18）：Sound.play('ignite',i) [L88-91] → ignite_0..ignite_7
 *   app/lib/agent/persona.dart → emotions（12 情绪，顺序即命名顺序）
 *
 * Node 里没有 Web Audio，全部手写 PCM 合成：
 *   振荡器（polyBLEP 方波/锯齿 + 正弦/三角）→ RBJ biquad → 指数包络（顺序与原型一致：
 *   source → filter → gain）→ 混音 → master 链（gain .9 / 18k lowpass / 近似压缩器）
 *   → TPDF dither → 16-bit PCM WAV。
 *
 * 确定性：同一 --seed 逐字节可复现；每个文件的随机流由 (seed, 文件名) 派生，
 * 所以增删事件不会移动别的事件的随机数。
 */
'use strict';
import { mkdirSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '..', '..');

/* ══════════════════════════ CLI ══════════════════════════ */
const argv = process.argv.slice(2);
const flag = (n) => argv.includes(`--${n}`);
const val = (n, d) => {
  const i = argv.indexOf(`--${n}`);
  return i >= 0 && argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : d;
};
const SEED = Number(val('seed', '1'));
const OUT = resolve(val('out', join(REPO, 'app', 'assets', 'audio')));
const ONLY = String(val('only', '')).split(',').map((s) => s.trim()).filter(Boolean);
const RAW = flag('raw');               // 跳过 master 链（听裸层叠加，调试用）
const LIST = flag('list');             // 只列清单不写文件

if (!Number.isFinite(SEED)) { console.error('bad --seed'); process.exit(2); }

/* ══════════════════════════ 确定性随机 ══════════════════════════ */
function mulberry32(a) {
  return function () {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function fnv1a(s) {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); }
  return h >>> 0;
}
const makeRng = (key) =>
  mulberry32((fnv1a(`${SEED}:${key}`) ^ Math.imul((SEED + 0x9e3779b9) | 0, 2654435761)) >>> 0);
const rand = (rng, a, b) => a + rng() * (b - a);

/* ══════════════════════════ DSP 基元 ══════════════════════════ */
const TAU = Math.PI * 2;

/* Web Audio 的振荡器是带限的；方波/锯齿用 polyBLEP 抗混叠，正弦/三角用理想波形 */
function polyBlep(t, dt) {
  if (dt <= 0) return 0;
  if (t < dt) { t /= dt; return t + t - t * t - 1; }
  if (t > 1 - dt) { t = (t - 1) / dt; return t * t + t + t + 1; }
  return 0;
}
function oscAt(type, phase, dt) {
  const x = phase / TAU; // 0..1（调用方保证已 wrap）
  switch (type) {
    case 'square': return (x < 0.5 ? 1 : -1) + polyBlep(x, dt) - polyBlep((x + 0.5) % 1, dt);
    case 'sawtooth': return 2 * x - 1 - polyBlep(x, dt);
    case 'triangle': return 2 * Math.abs(2 * (x - Math.floor(x + 0.5))) - 1;
    default: return Math.sin(phase);
  }
}

/* RBJ biquad。Web Audio 把 lowpass/highpass 的 Q 解释成 dB（谐振高度），bandpass 用传统 Q
   —— 照它翻译（原型只用到 lowpass .6/.7/.8/2 与 bandpass 1/1.4/2/3） */
function biquadCoefs(type, f, q, sr) {
  f = Math.max(1, Math.min(f, sr * 0.49));
  const w0 = (TAU * f) / sr, cw = Math.cos(w0), sw = Math.sin(w0);
  const qLin = type === 'bandpass' ? Math.max(1e-4, q) : Math.pow(10, q / 20);
  const alpha = sw / (2 * qLin);
  let b0, b1, b2;
  if (type === 'lowpass') { b0 = (1 - cw) / 2; b1 = 1 - cw; b2 = b0; }
  else if (type === 'highpass') { b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = b0; }
  else { b0 = alpha; b1 = 0; b2 = -alpha; } // bandpass（0 dB 峰值增益）
  const a0 = 1 + alpha, a1 = -2 * cw, a2 = 1 - alpha;
  return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0];
}
class Biquad {
  constructor(type, f, q, sr) {
    this.type = type; this.q = q; this.sr = sr;
    this.x1 = this.x2 = this.y1 = this.y2 = 0; this.f = -1;
    this.b0 = 1; this.b1 = 0; this.b2 = 0; this.a1 = 0; this.a2 = 0;
    this.setF(f);
  }
  setF(f) {
    if (f === this.f) return;
    this.f = f;
    const c = biquadCoefs(this.type, f, this.q, this.sr);
    this.b0 = c[0]; this.b1 = c[1]; this.b2 = c[2]; this.a1 = c[3]; this.a2 = c[4];
  }
  run(x) {
    const y = this.b0 * x + this.b1 * this.x1 + this.b2 * this.x2 - this.a1 * this.y1 - this.a2 * this.y2;
    this.x2 = this.x1; this.x1 = x; this.y2 = this.y1; this.y1 = y;
    return y;
  }
}

/* tone()/noise() 的包络：0.0001 →(指数)→ vol →(指数)→ 0.0001（同 exponentialRampToValueAtTime） */
function envAt(t, a, dur, vol) {
  if (t < 0 || t > dur) return 0;
  if (t <= a) return a > 0 ? 0.0001 * Math.pow(vol / 0.0001, t / a) : vol;
  return vol * Math.pow(0.0001 / vol, (t - a) / (dur - a));
}
const envPeak = (o) => (o.vol != null ? o.vol : 0.1);

/** Sound.tone({...}) 的一次调用 */
function addTone(buf, sr, o) {
  const at = o.at || 0, dur = o.dur != null ? o.dur : 0.2;
  const slide = o.slide != null ? o.slide : dur;
  const a = o.a != null ? o.a : 0.005;
  const vol = o.vol != null ? o.vol : 0.1;
  const type = o.type || 'sine';
  const f0 = o.f * (o.detune ? Math.pow(2, o.detune / 1200) : 1);
  const f2 = o.f2 != null ? Math.max(1, o.f2) : null;
  const start = Math.round(at * sr), n = Math.round(dur * sr);
  const F = o.lp || o.bp ? new Biquad(o.lp ? 'lowpass' : 'bandpass', o.lp || o.bp, o.q != null ? o.q : 0.8, sr) : null;
  let phase = 0;
  for (let i = 0; i < n; i++) {
    const idx = start + i;
    if (idx >= buf.length) break;
    const t = i / sr;
    const f = f2 ? (t <= slide ? f0 * Math.pow(f2 / f0, t / slide) : f2) : f0;
    let s = oscAt(type, phase, f / sr);
    phase += (TAU * f) / sr;
    if (phase >= TAU) phase -= TAU * Math.floor(phase / TAU);
    if (F) s = F.run(s);
    s *= envAt(t, a, dur, vol);
    if (idx >= 0) buf[idx] += s;
  }
}

/** Sound.noise({...}) 的一次调用 */
function addNoise(buf, sr, o, rng, noiseKey) {
  const at = o.at || 0, dur = o.dur != null ? o.dur : 0.2;
  const a = o.a != null ? o.a : 0.01;
  const vol = o.vol != null ? o.vol : 0.05;
  const type = o.type || 'bandpass';
  const q = o.q != null ? o.q : 1;
  const f0 = o.f != null ? o.f : 1200;
  const f2 = o.f2 != null ? o.f2 : null;
  const start = Math.round(at * sr), n = Math.round(dur * sr);
  const off = rng ? rng() : 0; // 原型 s.start(t0, Math.random())
  let st = (fnv1a(`${SEED}:${noiseKey}:${off}`) | 1) >>> 0;
  const nz = () => { st ^= st << 13; st >>>= 0; st ^= st >>> 17; st ^= st << 5; st >>>= 0; return st / 2147483648 - 1; };
  const F = new Biquad(type, f0, q, sr);
  for (let i = 0; i < n; i++) {
    const idx = start + i;
    if (idx >= buf.length) break;
    const t = i / sr;
    if (f2) F.setF(Math.max(1, f0 * Math.pow(f2 / f0, Math.min(1, t / dur))));
    let s = F.run(nz());
    s *= envAt(t, a, dur, vol);
    if (idx >= 0) buf[idx] += s;
  }
}

/* ══════════════ 层表 → 缓冲 ══════════════ */
const T = (o) => ({ kind: 'tone', ...o });
const N = (o) => ({ kind: 'noise', ...o });
const chord = (fs, o = {}) => fs.map((f, i) => T({ ...o, f, at: (o.at || 0) + (o.spread || 0) * i }));

const layerEnd = (l) => (l.at || 0) + (l.dur != null ? l.dur : 0.2);

function renderLayers(sr, layers, rng, key) {
  const end = layers.reduce((m, l) => Math.max(m, layerEnd(l)), 0) + 0.01;
  const buf = new Float32Array(Math.max(1, Math.ceil(end * sr)));
  layers.forEach((l, i) => {
    if (l.kind === 'noise') addNoise(buf, sr, l, rng, `${key}:${i}`);
    else addTone(buf, sr, l);
  });
  return buf;
}

/* ══════════════ master 链（audio.js L13-20 的近似） ══════════════
   sfx/vox → lowpass 18k → master gain .9 → DynamicsCompressor(-16dB, ratio 3.5, knee 30dB)
   近似点：压缩器无 lookahead；逐文件独立压缩（原型是全局总线，同时发声才互相压）。 */
function masterChain(buf, sr) {
  if (RAW) return buf;
  for (let i = 0; i < buf.length; i++) buf[i] *= 0.9;
  if (18000 < sr * 0.49) {
    const F = new Biquad('lowpass', 18000, 1, sr);
    for (let i = 0; i < buf.length; i++) buf[i] = F.run(buf[i]);
  }
  const threshold = -16, knee = 30, ratio = 3.5;
  const aC = Math.exp(-1 / (0.003 * sr)), rC = Math.exp(-1 / (0.25 * sr));
  let gr = 0, peak = 0;
  for (let i = 0; i < buf.length; i++) {
    const x = buf[i], ax = Math.abs(x);
    const ldb = ax > 1e-9 ? 20 * Math.log10(ax) : -120;
    const over = ldb - threshold;
    let want;
    if (over <= -knee / 2) want = 0;
    else if (over >= knee / 2) want = -(1 - 1 / ratio) * over;
    else { const t = over + knee / 2; want = -(1 - 1 / ratio) * (t * t) / (2 * knee); }
    const c = want < gr ? aC : rC;
    gr = want + (gr - want) * c;
    const y = x * Math.pow(10, gr / 20);
    buf[i] = y;
    if (Math.abs(y) > peak) peak = Math.abs(y);
  }
  return buf;
}

/* ══════════════ WAV ══════════════ */
const peakOf = (b) => { let p = 0; for (let i = 0; i < b.length; i++) { const v = Math.abs(b[i]); if (v > p) p = v; } return p; };

function writeWav(path, samples, sr, rng) {
  const n = samples.length;
  const out = Buffer.alloc(44 + n * 2);
  out.write('RIFF', 0); out.writeUInt32LE(36 + n * 2, 4); out.write('WAVE', 8);
  out.write('fmt ', 12); out.writeUInt32LE(16, 16);
  out.writeUInt16LE(1, 20); out.writeUInt16LE(1, 22);   // PCM / mono
  out.writeUInt32LE(sr, 24); out.writeUInt32LE(sr * 2, 28);
  out.writeUInt16LE(2, 32); out.writeUInt16LE(16, 34);  // blockAlign / 16-bit
  out.write('data', 36); out.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) {
    let v = samples[i];
    if (v > 1) v = 1; else if (v < -1) v = -1;
    // TPDF dither（±1 LSB）
    const d = rng ? (rng() + rng() - 1) / 32768 : 0;
    let q = Math.round((v + d) * 32767);
    if (q > 32767) q = 32767; else if (q < -32768) q = -32768;
    out.writeInt16LE(q, 44 + i * 2);
  }
  writeFileSync(path, out);
  return out.length;
}

/* ══════════════════════════ 环境底噪（可无缝循环） ══════════════════════════
   ambient()：4 振荡器 pad 55/82.41/110.2/164.8Hz（triangle,sine,sine,sine；detune (i-1.5)*6 音分）
   → lowpass 520 + LFO .07Hz(±160) → pg .11 → amb gain .32*level
   ⚠ 原型 L152-156 明确写过：那层「宽带噪声」= 手机喇叭上的嘶嘶声，已删 —— 这里也不加。
   无缝循环的实现：把 loop 长度取成 LFO 的整数个周期（0.14Hz × 7.142857s = 1 个周期），
   各分音量化到「在 loop 内正好整数个周期」（偏差 < 1.1 音分），再渲染 2 个 loop、丢第一个
   （让 lowpass 的暂态衰减干净）→ 第二个 loop 逐样本周期化，接缝为 0。 */
const AMB_LFO_HZ = 0.14;
const AMB_LOOP_SEC = 1 / AMB_LFO_HZ; // 7.142857142857143 s
const AMB_BASE = [55, 82.41, 110.2, 164.8];
const AMB_GAIN = [0.5, 0.35, 0.18, 0.08];
const AMB_DETUNE = [-9, -3, 3, 9]; // (i-1.5)*6 音分

function renderAmbient(sr) {
  const N = Math.round(AMB_LOOP_SEC * sr);
  const total = N * 2;
  const raw = new Float32Array(total);
  const ph = AMB_BASE.map(() => 0);
  const fq = AMB_BASE.map((f, i) => {
    const fd = f * Math.pow(2, AMB_DETUNE[i] / 1200);
    return Math.round(fd * AMB_LOOP_SEC) / AMB_LOOP_SEC; // 量化到整数周期
  });
  const F = new Biquad('lowpass', 520, 2, sr);
  const out = new Float32Array(N);
  console.log(`  ambient: loop=${AMB_LOOP_SEC.toFixed(6)}s (LFO ${AMB_LFO_HZ}Hz = 1 周期), 渲染 2 个 loop 丢第 1 个`);
  fq.forEach((f, k) => {
    const fd = AMB_BASE[k] * Math.pow(2, AMB_DETUNE[k] / 1200);
    console.log(`    partial ${k}: ${AMB_BASE[k]}Hz detune ${AMB_DETUNE[k] >= 0 ? '+' : ''}${AMB_DETUNE[k]}c → ${fd.toFixed(3)}Hz` +
      ` → 整数周期量化 ${f.toFixed(4)}Hz（周期数 ${Math.round(f * AMB_LOOP_SEC)}，偏差 ${(1200 * Math.log2(f / fd)).toFixed(2)} 音分）`);
  });
  for (let i = 0; i < total; i++) {
    const t = i / sr;
    let s = 0;
    for (let k = 0; k < 4; k++) {
      s += oscAt(k < 2 ? 'triangle' : 'sine', ph[k], fq[k] / sr) * AMB_GAIN[k];
      ph[k] += (TAU * fq[k]) / sr;
      if (ph[k] >= TAU) ph[k] -= TAU * Math.floor(ph[k] / TAU);
    }
    F.setF(520 + 160 * Math.sin(TAU * AMB_LFO_HZ * t));
    s = F.run(s) * 0.11 * 0.32; // pg .11 → amb gain .32*level(=1)
    if (i >= N) out[i - N] = s;
  }
  masterChain(out, sr);
  return out;
}

/* ══════════════════════════ 清单（= audio.js 的逐条转写） ══════════════════════════ */
const EMOTIONS = ['neutral', 'smug', 'cold', 'annoyed', 'pleased', 'tsun', 'joy', 'proud', 'surprised', 'sad', 'focus', 'sleep'];
const PITCH = { neutral: 560, smug: 520, cold: 470, annoyed: 610, pleased: 610, tsun: 660, joy: 700, surprised: 720, sad: 360, focus: 540, sleep: 300, proud: 600 };
const RANK_BASE = [392, 440, 494, 523.3, 587.3, 659.3, 784];
const RANK_I = 2; // 总线只查 rank.wav → 取中档（原型按稀有度 i 变调变重，见 README 差异表）
const IGNITE_F = [523.3, 587.3, 659.3, 784, 880, 1046.5, 1174.7, 1318.5]; // audio.js:89（clamp(x|0,0,7)）

function buildManifest() {
  const M = [];
  const add = (name, sr, make) => M.push({ name, sr, kind: 'layers', make });

  // ── A 高频 12 件 ──
  add('tap', 44100, () => [T({ f: 1320, f2: 1080, dur: 0.05, vol: 0.04 })]);
  // 戳她（audio.js L130：`poke` 620→990Hz triangle 0.1s vol .05）
  add('poke', 44100, () => [T({ f: 620, f2: 990, dur: 0.1, vol: 0.05, type: 'triangle' })]);
  add('choose', 44100, () => [
    T({ f: 740, f2: 1110, dur: 0.12, vol: 0.045, type: 'triangle' }),
    N({ f: 2400, f2: 5200, dur: 0.18, vol: 0.02 }),
  ]);
  add('land', 44100, () => [
    T({ f: 96, f2: 40, dur: 0.42, vol: 0.38, a: 0.004 }),
    N({ type: 'lowpass', f: 700, dur: 0.16, vol: 0.14, a: 0.002 }),
    T({ f: 2400, dur: 0.03, vol: 0.03 }),
  ]);
  for (let x = 0; x < 5; x++) {
    add(`rung_${x}`, 44100, () => [T({ f: 300 * Math.pow(2, x / 5), dur: 0.07, vol: 0.045, type: 'square', lp: 2600 })]);
  }
  // ── docs/41 §3.3 / §3.4 / §3.1：卡牌专属的三组（v16）─────────────────
  // 为什么另立一组而不是复用 rung：rung 是 70ms 方波、5 档跨度 1.74×，
  // 是给派单板的稀有度滚档用的；牌桌的「档位咬合」是**每 104px 一发**的高频
  // 动作，需要更短（与 8ms 震动同量级）+ 带噪声瞬态（不然手机小喇叭上像塑料）。
  //
  // detent_0..4：18ms 高通噪声（"卡进去"）+ 12ms 方波 click（1400→2800Hz 一个八度）
  for (let x = 0; x < 5; x++) {
    const f = 1400 * Math.pow(2, x / 4);
    add(`detent_${x}`, 44100, () => [
      N({ f: 3200, q: 2.5, dur: 0.018, vol: 0.05, a: 0.0005 }),
      T({ f, dur: 0.012, vol: 0.018, type: 'square', lp: 6000 }),
    ]);
  }

  // stamp：落定（压印）。低通冲击给"牌的实体" + 纸面摩擦 + 一声很轻的 C5 确认。
  // 落定原来用 seal（1.26s / −11.6dBFS，全场第二重），但那是个高频动作 ——
  // 来回选 10 次就是 10 次钤印声叠加。seal 保留给"接单/提交"。
  add('stamp', 22050, () => [
    T({ f: 130, f2: 70, dur: 0.22, vol: 0.18, a: 0.003 }),
    N({ type: 'lowpass', f: 900, dur: 0.09, vol: 0.07, a: 0.001 }),
    T({ f: 523.3, dur: 0.28, vol: 0.022, a: 0.003 }),
  ]);

  // deal_0..4：发牌（牌扇入场）。纸牌划出的"唰"——高通噪声扫频 + 短促的落点。
  // 出声预算：一次发牌最多 2 声（首张 deal_0 + 末张 deal_4），见 docs/41 §3.1。
  for (let x = 0; x < 5; x++) {
    add(`deal_${x}`, 44100, () => [
      N({ type: 'highpass', f: 1200 + x * 220, f2: 3800 + x * 400, dur: 0.11, vol: 0.045, a: 0.004 }),
      T({ f: 420 + x * 60, f2: 260, dur: 0.06, vol: 0.02 }),
    ]);
  }
  const rank = (i) => [
    T({ f: 80, f2: 45, dur: 0.35 + i * 0.05, vol: 0.2 + i * 0.03 }),
    ...chord([RANK_BASE[i], RANK_BASE[i] * 1.26, RANK_BASE[i] * 1.5, RANK_BASE[i] * 2],
      { type: 'triangle', dur: 0.8 + i * 0.15, vol: 0.03 + i * 0.006, spread: 0.02 }),
  ];
  const rankFull = (i) => (i >= 5
    ? [...rank(i), N({ f: 6000, dur: 0.8, vol: 0.03, a: 0.01 }), T({ f: RANK_BASE[i] * 4, dur: 1.4, vol: 0.02, at: 0.05 })]
    : rank(i));
  for (let i = 0; i < 7; i++) add(`rank_${i}`, 22050, () => rankFull(i));
  add('rank', 22050, () => rankFull(RANK_I)); // 兜底：总线若有一次不带 variant 的 rank，别落到没声（= 中档 i=2）
  add('seal', 22050, () => [
    T({ f: 70, f2: 44, dur: 0.5, vol: 0.34 }),
    ...chord([293.7, 370, 440, 587.3], { type: 'triangle', dur: 1.2, vol: 0.05, spread: 0.015 }),
    N({ f: 1800, f2: 400, dur: 0.3, vol: 0.06 }),
  ]);
  add('ding', 22050, () => [
    T({ f: 2093, dur: 1.5, vol: 0.14, a: 0.003 }),
    T({ f: 3136, dur: 0.9, vol: 0.05, a: 0.003 }),
    T({ f: 4186, dur: 0.35, vol: 0.02, a: 0.002 }),
  ]);
  add('impact', 22050, () => [
    T({ f: 130, f2: 36, dur: 0.75, vol: 0.5, a: 0.003 }),
    N({ type: 'lowpass', f: 1200, f2: 200, dur: 0.4, vol: 0.2, a: 0.002 }),
    ...chord([1318.5, 1760, 2637], { dur: 1.2, vol: 0.022, at: 0.02, spread: 0.03 }),
  ]);
  for (let n = 0; n < 3; n++) {
    add(`count_${n}`, 44100, (rng) => [T({ f: 1700 + rng() * 300, dur: 0.025, vol: 0.016, type: 'square', lp: 4000 })]);
  }
  add('crit', 44100, () => [
    N({ f: 3000, f2: 9000, dur: 0.18, vol: 0.05, a: 0.15, at: 0 }),
    T({ f: 1567, dur: 0.5, vol: 0.08, type: 'square', lp: 5000, at: 0.16 }),
    T({ f: 2093, dur: 0.7, vol: 0.06, at: 0.16 }),
    T({ f: 110, f2: 50, dur: 0.3, vol: 0.3, at: 0.16 }),
  ]);
  add('levelup', 22050, () => [
    ...[523.3, 659.3, 784, 1046.5, 1318.5].map((f, i) => T({ f, dur: 0.7, vol: 0.055, type: 'triangle', at: i * 0.07 })),
    N({ f: 7000, dur: 0.9, vol: 0.02, at: 0.3 }),
  ]);
  add('fail', 22050, () => [T({ f: 98, f2: 69, dur: 1.7, slide: 1.5, vol: 0.13, a: 0.06 })]);

  // ── 可选两件（Lead 点名，以后要用） ──
  add('boot', 22050, () => [
    T({ f: 38, f2: 112, dur: 1.1, slide: 0.9, vol: 0.3, a: 0.2 }),
    N({ f: 300, f2: 5200, dur: 0.95, vol: 0.06, a: 0.6, q: 0.7 }),
    ...chord([220, 329.6, 440, 554.4, 659.3], { type: 'triangle', dur: 2.6, vol: 0.045, a: 0.02, at: 0.9, spread: 0.035 }),
    T({ f: 1760, dur: 1.8, vol: 0.02, at: 0.95 }),
  ]);
  add('hold', 44100, () => [T({ f: 600, dur: 0.04, vol: 0.02, type: 'square', lp: 3000 })]); // 原型 f=600+x*500

  // ── 批次③ 补件：点环音 ignite（flows.js:90 Sound.play('ignite', i)，逐个点亮主线环）──
  // 原型 audio.js:88-91：f = IGNITE_F[clamp(i,0,7)]；双 tone，无 noise/无随机 → 与 --seed 无关。
  for (let i = 0; i < 8; i++) {
    add(`ignite_${i}`, 22050, () => {
      const f = IGNITE_F[i];
      return [
        T({ f, dur: 1.1, vol: 0.07, a: 0.004 }),
        T({ f: f * 2.76, dur: 0.4, vol: 0.02, a: 0.003 }),
      ];
    });
  }

  // ── B 打字机逐字音节：12 情绪 × 4 变体 ──
  for (const emo of EMOTIONS) {
    for (let n = 0; n < 4; n++) {
      add(`syl_${emo}_${n}`, 22050, (rng) => {
        const base = PITCH[emo] * rand(rng, 0.92, 1.08);
        return [T({ f: base, f2: base * rand(rng, 0.86, 1.12), dur: 0.06, vol: 0.03, type: 'square', bp: base * 2.1, q: 1.4, a: 0.004 })];
      });
    }
  }

  // ── C 环境底噪 ──
  M.push({ name: 'ambient_loop', sr: 22050, kind: 'ambient', make: null });
  return M;
}

/* ══════════════════════════ main ══════════════════════════ */
const manifest = buildManifest();
const selected = ONLY.length ? manifest.filter((e) => ONLY.includes(e.name)) : manifest;
if (ONLY.length && selected.length !== ONLY.length) {
  const miss = ONLY.filter((n) => !manifest.some((e) => e.name === n));
  console.error(`--only 未命中: ${miss.join(', ')}`);
}

if (LIST) {
  for (const e of selected) console.log(`${e.name}\t${e.sr}\t${e.kind}`);
  console.log(`# ${selected.length} files (seed=${SEED})`);
  process.exit(0);
}

mkdirSync(OUT, { recursive: true });
const rows = [];
let total = 0;
for (const e of selected) {
  const sr = e.sr;
  const rng = makeRng(e.name);
  const buf = e.kind === 'ambient' ? renderAmbient(sr) : masterChain(renderLayers(sr, e.make(rng), rng, e.name), sr);
  const bytes = writeWav(join(OUT, `${e.name}.wav`), buf, sr, mulberry32(fnv1a(`dither:${e.name}`)));
  const dur = buf.length / sr;
  total += bytes;
  rows.push({ name: e.name, sr, dur, bytes, peak: peakOf(buf) });
  console.log(`${e.name.padEnd(18)} ${String(sr).padStart(5)}Hz  ${dur.toFixed(3)}s  peak ${peakOf(buf).toFixed(3)}  ${(bytes / 1024).toFixed(1)}KB`);
}

/* 陈旧文件检查（改名/删事件后留下的 .wav） */
const known = new Set(manifest.map((e) => `${e.name}.wav`));
const stale = readdirSync(OUT).filter((f) => f.endsWith('.wav') && !known.has(f));
console.log(`\nseed=${SEED}  wrote ${rows.length} files → ${OUT}`);
console.log(`total ${(total / 1024).toFixed(1)} KB = ${(total / 1024 / 1024).toFixed(3)} MB`);
if (stale.length) console.log(`⚠ 目录里有不在清单内的 .wav（未删，自行确认）: ${stale.join(', ')}`);
