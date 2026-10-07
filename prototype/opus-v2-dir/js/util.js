/* util.js — 小工具：选择器、时间、缓动、弹簧、模板 */
'use strict';

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const lerp = (a, b, t) => a + (b - a) * t;
const rand = (a, b) => a + Math.random() * (b - a);
const randi = (a, b) => Math.floor(rand(a, b + 1));
const pick = arr => arr[Math.floor(Math.random() * arr.length)];
const ease = {
  outCubic: t => 1 - Math.pow(1 - t, 3),
  inOutCubic: t => (t < .5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2),
  outQuint: t => 1 - Math.pow(1 - t, 5),
  outBack: t => { const c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2); },
  outExpo: t => (t === 1 ? 1 : 1 - Math.pow(2, -10 * t)),
  inQuad: t => t * t,
};

/* 时钟：演示控制台可以"快进一天"，所以全局时间都走这里 */
const Clock = {
  shift: 0,
  now() { return Date.now() + this.shift; },
  date() { return new Date(this.now()); },
};
function dayKey(t = Clock.now()) {
  const d = new Date(t);
  return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
}
function dayDiff(a, b) { // b - a，单位天（按本地日期）
  const pa = a.split('-').map(Number), pb = b.split('-').map(Number);
  return Math.round((new Date(pb[0], pb[1] - 1, pb[2]) - new Date(pa[0], pa[1] - 1, pa[2])) / 864e5);
}
function endOfDay(t = Clock.now()) { const d = new Date(t); d.setHours(23, 59, 59, 999); return d.getTime(); }
const WEEK = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

function fmtDur(ms) {
  const s = Math.max(0, Math.round(ms / 1000));
  if (s < 60) return s + ' 秒';
  const m = Math.floor(s / 60);
  if (m < 60) return m + ' 分' + (s % 60 ? ' ' + (s % 60) + ' 秒' : '');
  const h = Math.floor(m / 60);
  if (h < 48) return h + ' 小时' + (m % 60 ? ' ' + (m % 60) + ' 分' : '');
  return Math.floor(h / 24) + ' 天';
}
function fmtClock(ms) {
  const s = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), ss = s % 60;
  return (h ? h + ':' + String(m).padStart(2, '0') : String(m).padStart(2, '0')) + ':' + String(ss).padStart(2, '0');
}
function fmtMin(min) { return min >= 60 ? (min % 60 ? Math.floor(min / 60) + ' 小时 ' + (min % 60) + ' 分' : min / 60 + ' 小时') : min + ' 分钟'; }
function hhmm(t) { const d = new Date(t); return String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0'); }

function tpl(str, vars = {}) { return String(str).replace(/\{(\w+)\}/g, (_, k) => (vars[k] ?? '')); }
function esc(s) { return String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }

/* LINES 取句：可能是 string[]（随机挑一句）或嵌套对象 */
function line(key, vars) {
  let v = key.split('.').reduce((o, k) => (o ? o[k] : undefined), LINES);
  if (Array.isArray(v)) v = pick(v);
  return tpl(v ?? key, vars);
}
function lines(key, vars) { // 整组按顺序返回（多句连说）
  const v = key.split('.').reduce((o, k) => (o ? o[k] : undefined), LINES) || [key];
  return v.map(s => tpl(s, vars));
}

const sleep = ms => new Promise(r => setTimeout(r, ms));
const nextFrame = () => new Promise(r => requestAnimationFrame(r));

/* rAF 补间：tween(ms, t => …, easeFn) */
function tween(ms, fn, ez = ease.outCubic) {
  return new Promise(res => {
    const t0 = performance.now();
    const step = now => {
      const t = clamp((now - t0) / ms, 0, 1);
      fn(ez(t), t);
      if (t < 1) requestAnimationFrame(step); else res();
    };
    requestAnimationFrame(step);
  });
}

/* 二阶弹簧（临界附近、略欠阻尼），给相机和数值用 */
class Spring {
  constructor(v = 0, k = 120, zeta = .9) { this.x = v; this.v = 0; this.t = v; this.k = k; this.c = 2 * zeta * Math.sqrt(k); }
  set(t, snap) { this.t = t; if (snap) { this.x = t; this.v = 0; } }
  step(dt) {
    const n = Math.max(1, Math.ceil(dt / (1 / 120)));
    const h = dt / n;
    for (let i = 0; i < n; i++) {
      const a = -this.k * (this.x - this.t) - this.c * this.v;
      this.v += a * h; this.x += this.v * h;
    }
    return this.x;
  }
  get done() { return Math.abs(this.x - this.t) < 1e-3 && Math.abs(this.v) < 1e-3; }
}

function el(tag, cls, html) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (html != null) e.innerHTML = html;
  return e;
}

/* [[高亮]] → <em>，其余转义；拆成逐字 span 给打字机用 */
function richChars(str) {
  const out = [];
  const re = /\[\[(.+?)\]\]/g;
  let last = 0, m;
  while ((m = re.exec(str))) {
    for (const ch of str.slice(last, m.index)) out.push({ ch, em: false });
    for (const ch of m[1]) out.push({ ch, em: true });
    last = m.index + m[0].length;
  }
  for (const ch of str.slice(last)) out.push({ ch, em: false });
  return out;
}
function richHTML(str) { return esc(str).replace(/\[\[(.+?)\]\]/g, '<em>$1</em>'); }
function plain(str) { return String(str).replace(/\[\[(.+?)\]\]/g, '$1'); }

const buzz = p => { try { if (navigator.vibrate && App.settings.haptic) navigator.vibrate(p); } catch (e) { } };
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
const uid = () => Math.random().toString(36).slice(2, 9);
