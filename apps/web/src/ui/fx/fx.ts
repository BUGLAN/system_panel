/**
 * 一次性视觉反馈：粒子（迸散 / 圆环 / 彩带）、亮帧、震屏。移植自参考稿的 FX / flash / shake。
 *  - 亮帧按 docs/00：全屏白色、16% 透明度、脉冲 180ms；失败亮度是成功的 1/3
 *  - 尊重 prefers-reduced-motion：不震屏、粒子减量
 *  - 只动 transform / opacity（canvas 绘制不走布局）
 */
import { MOTION } from '../../design/tokens';

interface Particle {
  type: 'spark' | 'conf' | 'star' | 'heart' | 'dot' | 'ring';
  x: number;
  y: number;
  vx: number;
  vy: number;
  g: number;
  life: number;
  max: number;
  c: string;
  sz: number;
  rot: number;
  vr: number;
  drag: number;
  R: number;
  w: number;
}

export interface BurstOpts {
  n?: number;
  colors?: string[];
  type?: Particle['type'];
  angle?: number;
  spread?: number;
  min?: number;
  max?: number;
  g?: number;
  life?: number;
  sz?: number;
  drag?: number;
}

let app: HTMLElement | null = null;
let canvas: HTMLCanvasElement | null = null;
let ctx: CanvasRenderingContext2D | null = null;
let flashEl: HTMLElement | null = null;
let W = 0;
let H = 0;
const P: Particle[] = [];
let running = false;

const rand = (a: number, b: number) => a + Math.random() * (b - a);
const pick = <T>(a: readonly T[]): T => a[Math.floor(Math.random() * a.length)] as T;

export function reducedMotion(): boolean {
  return (
    typeof matchMedia !== 'undefined' && matchMedia('(prefers-reduced-motion: reduce)').matches
  );
}

function size(): void {
  if (!app || !canvas || !ctx) return;
  const r = app.getBoundingClientRect();
  const d = Math.min(2, devicePixelRatio || 1);
  W = r.width;
  H = r.height;
  canvas.width = W * d;
  canvas.height = H * d;
  ctx.setTransform(d, 0, 0, d, 0, 0);
}

export function registerFx(o: {
  app: HTMLElement;
  canvas: HTMLCanvasElement;
  flash: HTMLElement;
}): () => void {
  app = o.app;
  canvas = o.canvas;
  ctx = canvas.getContext('2d');
  flashEl = o.flash;
  size();
  const ro = new ResizeObserver(size);
  ro.observe(app);
  return () => {
    ro.disconnect();
    app = canvas = flashEl = null;
    ctx = null;
  };
}

export function appEl(): HTMLElement | null {
  return app;
}

/** 元素中心点（相对 #app） */
export function center(el: Element | null): [number, number] {
  if (!el || !app) return [W / 2, H / 2];
  const a = app.getBoundingClientRect();
  const r = el.getBoundingClientRect();
  return [r.left - a.left + r.width / 2, r.top - a.top + r.height / 2];
}

function add(p: Particle): void {
  P.push(p);
  if (!running) {
    running = true;
    requestAnimationFrame(loop);
  }
}

function star(c: CanvasRenderingContext2D, x: number, y: number, r: number): void {
  c.beginPath();
  for (let i = 0; i < 8; i++) {
    const a = (i * Math.PI) / 4;
    const rr = i % 2 ? r * 0.38 : r;
    c.lineTo(x + Math.cos(a) * rr, y + Math.sin(a) * rr);
  }
  c.closePath();
  c.fill();
}

function heart(c: CanvasRenderingContext2D, x: number, y: number, r: number): void {
  c.beginPath();
  c.moveTo(x, y + r * 0.9);
  c.bezierCurveTo(x - r * 1.6, y - r * 0.2, x - r * 0.6, y - r * 1.3, x, y - r * 0.4);
  c.bezierCurveTo(x + r * 0.6, y - r * 1.3, x + r * 1.6, y - r * 0.2, x, y + r * 0.9);
  c.fill();
}

function loop(): void {
  const c = ctx;
  if (!c) {
    running = false;
    P.length = 0;
    return;
  }
  c.clearRect(0, 0, W, H);
  for (let i = P.length - 1; i >= 0; i--) {
    const p = P[i] as Particle;
    p.life++;
    const k = p.life / p.max;
    if (k >= 1) {
      P.splice(i, 1);
      continue;
    }
    if (p.type === 'ring') {
      c.globalCompositeOperation = 'lighter';
      c.strokeStyle = p.c;
      c.globalAlpha = 1 - k;
      c.lineWidth = p.w * (1 - k) + 0.5;
      c.beginPath();
      c.arc(p.x, p.y, p.R * (1 - Math.pow(1 - k, 3)), 0, 7);
      c.stroke();
      continue;
    }
    p.vx *= p.drag;
    p.vy *= p.drag;
    p.vy += p.g;
    p.x += p.vx;
    p.y += p.vy;
    p.rot += p.vr;
    c.globalAlpha = 1 - k * k;
    c.fillStyle = c.strokeStyle = p.c;
    if (p.type === 'conf') {
      c.globalCompositeOperation = 'source-over';
      c.save();
      c.translate(p.x, p.y);
      c.rotate(p.rot);
      c.scale(1, Math.cos(p.life * 0.2));
      c.fillRect(-p.sz, -p.sz * 0.45, p.sz * 2, p.sz * 0.9);
      c.restore();
    } else if (p.type === 'spark') {
      c.globalCompositeOperation = 'lighter';
      c.lineWidth = p.sz * 0.6;
      c.lineCap = 'round';
      c.beginPath();
      c.moveTo(p.x, p.y);
      c.lineTo(p.x - p.vx * 2.6, p.y - p.vy * 2.6);
      c.stroke();
    } else if (p.type === 'star') {
      c.globalCompositeOperation = 'lighter';
      star(c, p.x, p.y, p.sz * (1.4 - k * 0.6));
    } else if (p.type === 'heart') {
      c.globalCompositeOperation = 'source-over';
      heart(c, p.x, p.y, p.sz);
    } else {
      c.globalCompositeOperation = 'lighter';
      c.beginPath();
      c.arc(p.x, p.y, p.sz * (1 - k * 0.5), 0, 7);
      c.fill();
    }
  }
  c.globalAlpha = 1;
  c.globalCompositeOperation = 'source-over';
  if (P.length) requestAnimationFrame(loop);
  else {
    running = false;
    c.clearRect(0, 0, W, H);
  }
}

export function burst(x: number, y: number, o: BurstOpts = {}): void {
  if (!ctx) return;
  const n = Math.round((o.n ?? 16) * (reducedMotion() ? 0.35 : 1));
  const cols = o.colors ?? ['#d6ff3d', '#ffffff'];
  for (let i = 0; i < n; i++) {
    const a =
      o.angle !== undefined
        ? o.angle + rand(-(o.spread ?? 0.5), o.spread ?? 0.5)
        : rand(0, Math.PI * 2);
    const s = rand(o.min ?? 2, o.max ?? 7);
    const life = o.life ?? 30;
    const sz = o.sz ?? 2;
    add({
      type: o.type ?? 'spark',
      x,
      y,
      vx: Math.cos(a) * s,
      vy: Math.sin(a) * s,
      g: o.g ?? 0.1,
      life: 0,
      max: rand(life, life * 1.7),
      c: pick(cols),
      sz: rand(sz, sz * 2),
      rot: rand(0, 6.28),
      vr: rand(-0.3, 0.3),
      drag: o.drag ?? 0.95,
      R: 0,
      w: 0,
    });
  }
}

export function ring(x: number, y: number, c = '#d6ff3d', R = 70, w = 3): void {
  if (!ctx) return;
  add({
    type: 'ring',
    x,
    y,
    life: 0,
    max: 30,
    c,
    R,
    w,
    vx: 0,
    vy: 0,
    g: 0,
    sz: 0,
    rot: 0,
    vr: 0,
    drag: 1,
  });
}

export function confetti(): void {
  const cols = ['#d6ff3d', '#ff3b7a', '#3be8ff', '#ffcc4d', '#8f6bff', '#fff'];
  const base = {
    type: 'conf' as const,
    n: 60,
    spread: 0.5,
    min: 8,
    max: 17,
    g: 0.22,
    drag: 0.985,
    life: 80,
    sz: 5,
    colors: cols,
  };
  burst(0, H * 0.75, { ...base, angle: -Math.PI / 3 });
  burst(W, H * 0.75, { ...base, angle: (-Math.PI * 2) / 3 });
}

/** 亮帧：白色 16%、脉冲 180ms */
export function flash(): void {
  if (!flashEl) return;
  const o = MOTION.flash.opacity;
  flashEl.animate([{ opacity: o }, { opacity: 0 }], {
    duration: MOTION.flash.ms,
    easing: 'cubic-bezier(.2,.9,.2,1)',
  });
}

/** 震屏（减弱动态效果时不震） */
export function shake(p = 8, d = 420): void {
  if (!app || reducedMotion()) return;
  const k: Keyframe[] = [];
  for (let i = 0; i < 9; i++) {
    const f = 1 - i / 9;
    k.push({
      transform: `translate(${rand(-p, p) * f}px,${rand(-p, p) * f}px) rotate(${rand(-p, p) * f * 0.08}deg)`,
    });
  }
  k.push({ transform: 'none' });
  app.animate(k, { duration: d });
}

/** 元素左右抖一下（输入不合法） */
export function shakeEl(el: Element | null): void {
  if (!el || reducedMotion()) return;
  el.animate(
    [
      { transform: 'translateX(0)' },
      { transform: 'translateX(-9px)' },
      { transform: 'translateX(9px)' },
      { transform: 'translateX(-6px)' },
      { transform: 'translateX(6px)' },
      { transform: 'translateX(0)' },
    ],
    { duration: 380, composite: 'add' },
  );
}

/** 数字弹一下 */
export function bump(el: Element | null): void {
  if (!el) return;
  el.animate(
    [
      { transform: 'scale(1)' },
      { transform: 'scale(1.25)', offset: 0.3 },
      { transform: 'scale(1)' },
    ],
    {
      duration: 500,
      easing: 'cubic-bezier(.2,.9,.2,1)',
    },
  );
}
