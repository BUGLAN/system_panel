#!/usr/bin/env node
/* tools/audio/inspect_wav.mjs — 实测产出：读 WAV 头 + 算 peak/RMS/DC + 循环接缝
 *
 * 用法：
 *   node tools/audio/inspect_wav.mjs                       # 默认扫 app/assets/audio
 *   node tools/audio/inspect_wav.mjs app/assets/audio       # 指定目录
 *   node tools/audio/inspect_wav.mjs app/assets/audio --md  # 直接输出 markdown 表（贴 README）
 *
 * 只读，不写任何文件。峰值/有效值都是**从写好的 16-bit PCM 里读回来算的**，
 * 不是合成过程中的中间量。
 */
'use strict';
import { readdirSync, readFileSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '..', '..');
const argv = process.argv.slice(2);
const MD = argv.includes('--md');
const SPEC_IDX = argv.indexOf('--spec');
const dirArg = argv.find((a, i) => !a.startsWith('--') && i !== (SPEC_IDX >= 0 ? SPEC_IDX + 1 : -1));
const DIR = resolve(dirArg || join(REPO, 'app', 'assets', 'audio'));

/* ── 主频校验：Hann 窗 + radix-2 FFT，取前 5 个峰 ──
   目的：证明烘出来的**确实是原型写的那个音高**（不是"看着像"）。
   用法：node tools/audio/inspect_wav.mjs --spec rung_0,ding,tap */
function fft(re, im) {
  const n = re.length;
  for (let i = 1, j = 0; i < n; i++) {
    let bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) { [re[i], re[j]] = [re[j], re[i]]; [im[i], im[j]] = [im[j], im[i]]; }
  }
  for (let len = 2; len <= n; len <<= 1) {
    const ang = -2 * Math.PI / len;
    for (let i = 0; i < n; i += len) {
      for (let k = 0; k < len / 2; k++) {
        const wr = Math.cos(ang * k), wi = Math.sin(ang * k);
        const ur = re[i + k], ui = im[i + k];
        const vr = re[i + k + len / 2] * wr - im[i + k + len / 2] * wi;
        const vi = re[i + k + len / 2] * wi + im[i + k + len / 2] * wr;
        re[i + k] = ur + vr; im[i + k] = ui + vi;
        re[i + k + len / 2] = ur - vr; im[i + k + len / 2] = ui - vi;
      }
    }
  }
}
function spectrum(file) {
  const b = readFileSync(file);
  const sr = b.readUInt32LE(24);
  let dataOff = 44;
  // 找 data chunk（fmt 16 字节 → data 常在 36）
  if (b.toString('ascii', 36, 40) !== 'data') {
    let off = 12;
    while (off + 8 <= b.length) {
      const id = b.toString('ascii', off, off + 4), size = b.readUInt32LE(off + 4);
      if (id === 'data') { dataOff = off + 8; break; }
      off += 8 + size + (size % 2);
    }
  }
  const frames = Math.floor((b.length - dataOff) / 2);
  let n = 1; while (n * 2 <= Math.min(frames, 8192)) n *= 2;
  const re = new Float64Array(n), im = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    const w = 0.5 - 0.5 * Math.cos((2 * Math.PI * i) / (n - 1));
    re[i] = (b.readInt16LE(dataOff + i * 2) / 32768) * w;
  }
  fft(re, im);
  const mag = new Float64Array(n / 2);
  let mx = 1e-12;
  for (let i = 0; i < n / 2; i++) { mag[i] = Math.hypot(re[i], im[i]); if (mag[i] > mx) mx = mag[i]; }
  const peaks = [];
  for (let i = 2; i < n / 2 - 2; i++) {
    if (mag[i] > mag[i - 1] && mag[i] >= mag[i + 1] && mag[i] > mx * 0.02) {
      // 抛物线插值细化峰位
      const a = mag[i - 1], c = mag[i], d = mag[i + 1];
      const off = (0.5 * (a - d)) / (a - 2 * c + d || 1);
      peaks.push({ hz: ((i + off) * sr) / n, db: 20 * Math.log10(c / mx) });
    }
  }
  peaks.sort((p, q) => q.db - p.db);
  return { file: basename(file), sr, n, res: sr / n, peaks: peaks.slice(0, 5) };
}

const specIdx = SPEC_IDX;
if (specIdx >= 0) {
  const names = String(argv[specIdx + 1] || '').split(',').map((s) => s.trim()).filter(Boolean);
  for (const nm of names) {
    const f = nm.endsWith('.wav') ? join(DIR, nm) : join(DIR, `${nm}.wav`);
    const s = spectrum(f);
    console.log(`${s.file}  (FFT n=${s.n}, 分辨率 ${s.res.toFixed(1)}Hz, 起点 0s)`);
    console.log('   主峰: ' + s.peaks.map((p) => `${p.hz.toFixed(1)}Hz(${p.db.toFixed(1)}dB)`).join('  '));
  }
  process.exit(0);
}

function parseWav(file) {
  const b = readFileSync(file);
  if (b.length < 44 || b.toString('ascii', 0, 4) !== 'RIFF' || b.toString('ascii', 8, 12) !== 'WAVE') {
    throw new Error(`不是 RIFF/WAVE: ${file}`);
  }
  let off = 12, fmt = null, dataOff = -1, dataLen = 0;
  while (off + 8 <= b.length) {
    const id = b.toString('ascii', off, off + 4);
    const size = b.readUInt32LE(off + 4);
    if (id === 'fmt ') {
      fmt = {
        audioFormat: b.readUInt16LE(off + 8), channels: b.readUInt16LE(off + 10),
        sampleRate: b.readUInt32LE(off + 12), byteRate: b.readUInt32LE(off + 16),
        blockAlign: b.readUInt16LE(off + 20), bits: b.readUInt16LE(off + 22),
      };
    } else if (id === 'data') { dataOff = off + 8; dataLen = size; }
    off += 8 + size + (size % 2);
  }
  if (!fmt || dataOff < 0) throw new Error(`缺 fmt/data: ${file}`);

  const n = Math.floor(dataLen / 2);
  let peak = 0, sum2 = 0, sum = 0, clipped = 0;
  let prev = 0, maxStep = 0;
  const first = b.readInt16LE(dataOff) / 32768;
  for (let i = 0; i < n; i++) {
    const v = b.readInt16LE(dataOff + i * 2) / 32768;
    const a = Math.abs(v);
    if (a > peak) peak = a;
    if (a >= 1) clipped++;
    sum += v; sum2 += v * v;
    if (i > 0) { const d = Math.abs(v - prev); if (d > maxStep) maxStep = d; }
    prev = v;
  }
  const wrap = Math.abs(first - prev); // 首尾样本差 = 循环接缝跳变
  return {
    file: basename(file), ...fmt, frames: n, durationSec: n / fmt.sampleRate,
    bytes: b.length, peak, peakDb: 20 * Math.log10(peak || 1e-9),
    rmsDb: 20 * Math.log10(Math.sqrt(sum2 / n) || 1e-9),
    dc: sum / n, clipped, maxStep, wrap,
    headerOk: b.readUInt32LE(4) === b.length - 8 && dataLen === n * 2,
  };
}

const files = readdirSync(DIR).filter((f) => f.toLowerCase().endsWith('.wav')).sort();
if (!files.length) { console.error(`没有 .wav: ${DIR}`); process.exit(1); }

const rows = files.map((f) => parseWav(join(DIR, f)));
const total = rows.reduce((s, r) => s + r.bytes, 0);

const pad = (s, n) => String(s).padEnd(n);
const padL = (s, n) => String(s).padStart(n);
const f2 = (v) => v.toFixed(2);

if (MD) {
  console.log('| # | 文件 | 采样率 | 时长 s | 峰值(线性) | 峰值 dBFS | RMS dBFS | DC | 削顶 | 字节 |');
  console.log('|---|---|---|---|---|---|---|---|---|---|');
  rows.forEach((r, i) => {
    console.log(`| ${i + 1} | \`${r.file}\` | ${r.sampleRate} | ${r.durationSec.toFixed(3)} | ${r.peak.toFixed(4)} | ${f2(r.peakDb)} | ${f2(r.rmsDb)} | ${r.dc.toExponential(1)} | ${r.clipped} | ${r.bytes} |`);
  });
  console.log(`\n合计 ${rows.length} 个文件 / ${total} 字节 = ${(total / 1024).toFixed(1)} KB = ${(total / 1024 / 1024).toFixed(3)} MB`);
} else {
  console.log(`DIR ${DIR}`);
  console.log(pad('#', 4) + pad('file', 20) + padL('sr', 7) + padL('sec', 9) + padL('peak', 9) + padL('dBFS', 8) + padL('rms', 8) + padL('clip', 6) + padL('bytes', 9) + padL('wrap', 9));
  rows.forEach((r, i) => {
    console.log(
      pad(i + 1, 4) + pad(r.file, 20) + padL(r.sampleRate, 7) + padL(r.durationSec.toFixed(3), 9) +
      padL(r.peak.toFixed(4), 9) + padL(f2(r.peakDb), 8) + padL(f2(r.rmsDb), 8) +
      padL(r.clipped, 6) + padL(r.bytes, 9) + padL(r.wrap.toExponential(2), 9));
  });
  console.log(`\n${rows.length} files, total ${total} bytes = ${(total / 1024).toFixed(1)} KB = ${(total / 1024 / 1024).toFixed(3)} MB`);
}

/* 一致性断言（bad 会打印出来，供 CI/人工复核） */
const bad = [];
for (const r of rows) {
  if (r.audioFormat !== 1) bad.push(`${r.file}: audioFormat=${r.audioFormat} (应 1=PCM)`);
  if (r.channels !== 1) bad.push(`${r.file}: channels=${r.channels} (应 1)`);
  if (r.bits !== 16) bad.push(`${r.file}: bits=${r.bits} (应 16)`);
  if (!r.headerOk) bad.push(`${r.file}: RIFF/data 长度字段不自洽`);
  if (r.clipped > 0) bad.push(`${r.file}: 削顶 ${r.clipped} 样本`);
  if (Math.abs(r.dc) > 1e-3) bad.push(`${r.file}: DC 偏高 ${r.dc}`);
}
const amb = rows.find((r) => r.file === 'ambient_loop.wav');
if (amb) {
  const ok = amb.wrap <= amb.maxStep;
  console.log(`\n[loop] ambient_loop 接缝跳变 |x[0]-x[n-1]| = ${amb.wrap.toExponential(3)}，` +
    `文件内最大相邻差 = ${amb.maxStep.toExponential(3)} → ${ok ? '无缝（接缝 < 内部最大跳变）' : '⚠ 有接缝'}`);
}
console.log(bad.length ? `\n⚠ ${bad.length} 项待查:\n  ${bad.join('\n  ')}` : '\n✅ 全部通过：PCM/单声道/16-bit/头自洽/无削顶/DC≈0');
process.exit(bad.length ? 1 : 0);
