/* fx.js — 屏幕空间特效：火花、爆散、光痕、涟漪、白闪、震屏 */
'use strict';

const FX = {
  cv: null, g: null, W: 0, H: 0, dpr: 1, parts: [], rips: [], streaks: [], running: false,

  init(cv) {
    this.cv = cv; this.g = cv.getContext('2d');
    this.resize(); new ResizeObserver(() => this.resize()).observe(cv.parentElement);
  },
  resize() {
    const r = this.cv.parentElement.getBoundingClientRect();
    this.dpr = Math.min(devicePixelRatio || 1, 2); this.W = r.width; this.H = r.height;
    this.cv.width = r.width * this.dpr; this.cv.height = r.height * this.dpr;
  },
  _kick() { if (!this.running) { this.running = true; this._last = performance.now(); requestAnimationFrame(t => this._loop(t)); } },

  /* 激光刻字的火花：短、亮、往下掉 */
  spark(x, y, n = 6, col = '#bff6ff') {
    for (let i = 0; i < n; i++) {
      const a = rand(-Math.PI, 0) + rand(-.4, .4), v = rand(80, 320);
      this.parts.push({ x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v, life: 0, max: rand(.18, .45), size: rand(.8, 1.8), col, kind: 'line', g: 900, drag: .9 });
    }
    this._kick();
  },
  /* 结算爆散 */
  burst(x, y, o = {}) {
    const n = o.n || 60, cols = o.cols || ['#38e1ff', '#e9fbff', '#7fdcff'];
    for (let i = 0; i < n; i++) {
      const a = rand(0, Math.PI * 2), v = rand(o.min || 120, o.max || 620);
      this.parts.push({
        x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v * (o.flat || 1), life: 0, max: rand(.5, o.life || 1.3),
        size: rand(1, o.size || 3.2), col: pick(cols), kind: Math.random() < (o.shards ?? .35) ? 'shard' : 'dot',
        g: o.g ?? 160, drag: o.drag ?? .965, rot: rand(0, 6), vr: rand(-12, 12),
      });
    }
    this._kick();
  },
  /* 往上飘的数据尘（失败时几乎没有，成功时一小把） */
  rise(x, y, n = 20, col = '#38e1ff') {
    for (let i = 0; i < n; i++) this.parts.push({ x: x + rand(-60, 60), y: y + rand(-10, 30), vx: rand(-14, 14), vy: rand(-140, -40), life: 0, max: rand(.8, 1.6), size: rand(1, 2.4), col, kind: 'dot', g: -20, drag: .99 });
    this._kick();
  },
  ripple(x, y, o = {}) { this.rips.push({ x, y, t: 0, max: (o.ms || 900) / 1000, r0: o.r0 || 10, r1: o.r1 || 260, col: o.col || '#38e1ff', flat: o.flat || 1, w: o.w || 2 }); this._kick(); },
  streak(x0, y0, x1, y1, o = {}) { this.streaks.push({ x0, y0, x1, y1, t: 0, max: (o.ms || 420) / 1000, col: o.col || '#e9fbff', w: o.w || 3 }); this._kick(); },

  flash(col = '#fff', a = .16, ms = 180) {
    if (reduceMotion) a *= .5;
    const f = $('#flash'); f.style.transition = 'none'; f.style.background = col; f.style.opacity = a;
    requestAnimationFrame(() => { f.style.transition = `opacity ${ms}ms ease-out`; f.style.opacity = 0; });
  },
  shake(px = 4, ms = 240) {
    if (reduceMotion) return;
    const s = $('#shake'), t0 = performance.now();
    const step = now => {
      const p = (now - t0) / ms; if (p >= 1) { s.style.transform = ''; return; }
      const k = (1 - p) * px; s.style.transform = `translate(${rand(-k, k).toFixed(1)}px,${rand(-k, k).toFixed(1)}px)`;
      requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  },

  _loop(now) {
    const dt = Math.min(.05, (now - this._last) / 1000); this._last = now;
    const g = this.g, d = this.dpr;
    g.setTransform(d, 0, 0, d, 0, 0); g.clearRect(0, 0, this.W, this.H);
    g.globalCompositeOperation = 'lighter';
    this.parts = this.parts.filter(p => {
      p.life += dt; if (p.life >= p.max) return false;
      p.vx *= Math.pow(p.drag, dt * 60); p.vy = p.vy * Math.pow(p.drag, dt * 60) + p.g * dt;
      p.x += p.vx * dt; p.y += p.vy * dt;
      const a = 1 - p.life / p.max;
      g.globalAlpha = a; g.fillStyle = g.strokeStyle = p.col;
      if (p.kind === 'line') {
        g.lineWidth = p.size; g.beginPath(); g.moveTo(p.x, p.y); g.lineTo(p.x - p.vx * .03, p.y - p.vy * .03); g.stroke();
      } else if (p.kind === 'shard') {
        p.rot += p.vr * dt; const s = p.size * 2.2;
        g.save(); g.translate(p.x, p.y); g.rotate(p.rot); g.fillRect(-s, -s * .3, s * 2, s * .6); g.restore();
      } else { g.beginPath(); g.arc(p.x, p.y, p.size * (0.6 + a * .6), 0, 6.283); g.fill(); }
      return true;
    });
    this.rips = this.rips.filter(r => {
      r.t += dt; const p = r.t / r.max; if (p >= 1) return false;
      const e = ease.outCubic(p), rad = lerp(r.r0, r.r1, e);
      g.globalAlpha = Math.pow(1 - p, 1.5); g.strokeStyle = r.col; g.lineWidth = r.w * (1 - p * .6);
      g.beginPath(); g.ellipse(r.x, r.y, rad, rad * r.flat, 0, 0, 6.283); g.stroke();
      return true;
    });
    this.streaks = this.streaks.filter(s => {
      s.t += dt; const p = s.t / s.max; if (p >= 1) return false;
      const h = ease.inOutCubic(Math.min(1, p * 1.25)), tl = ease.inOutCubic(Math.max(0, p * 1.25 - .25));
      const hx = lerp(s.x0, s.x1, h), hy = lerp(s.y0, s.y1, h), tx = lerp(s.x0, s.x1, tl), ty = lerp(s.y0, s.y1, tl);
      const gr = g.createLinearGradient(tx, ty, hx, hy); gr.addColorStop(0, 'rgba(56,225,255,0)'); gr.addColorStop(1, s.col);
      g.globalAlpha = 1; g.strokeStyle = gr; g.lineWidth = s.w; g.lineCap = 'round';
      g.beginPath(); g.moveTo(tx, ty); g.lineTo(hx, hy); g.stroke();
      g.fillStyle = '#fff'; g.beginPath(); g.arc(hx, hy, s.w * 1.4, 0, 6.283); g.fill();
      return true;
    });
    g.globalAlpha = 1; g.globalCompositeOperation = 'source-over';
    if (this.parts.length || this.rips.length || this.streaks.length) requestAnimationFrame(t => this._loop(t));
    else { this.running = false; g.clearRect(0, 0, this.W, this.H); }
  },
};
