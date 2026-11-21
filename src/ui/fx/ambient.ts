/**
 * 背景浮尘 + 偶尔一道流光（参考稿 ambient motes）。常驻循环：页面不可见或减弱动态效果时停。
 */
import { reducedMotion } from './fx';

export function startAmbient(canvas: HTMLCanvasElement, host: HTMLElement): () => void {
  const cx = canvas.getContext('2d');
  if (!cx) return () => {};
  const rand = (a: number, b: number) => a + Math.random() * (b - a);
  let W = 0;
  let H = 0;
  const size = () => {
    const r = host.getBoundingClientRect();
    const d = Math.min(2, devicePixelRatio || 1);
    W = r.width;
    H = r.height;
    canvas.width = W * d;
    canvas.height = H * d;
    cx.setTransform(d, 0, 0, d, 0, 0);
  };
  size();
  const ro = new ResizeObserver(size);
  ro.observe(host);
  const M = Array.from({ length: 46 }, () => ({
    x: rand(0, W),
    y: rand(0, H),
    r: rand(0.5, 2),
    v: rand(0.12, 0.5),
    p: rand(0, 6.28),
    s: rand(0.01, 0.04),
  }));
  let streak: { y: number; x: number; v: number; l: number } | null = null;
  let raf = 0;
  let stopped = false;

  const frame = () => {
    raf = 0;
    if (stopped) return;
    cx.clearRect(0, 0, W, H);
    const acc = getComputedStyle(host).getPropertyValue('--accent').trim() || '#d6ff3d';
    for (const m of M) {
      m.y -= m.v;
      m.p += m.s;
      m.x += Math.sin(m.p) * 0.25;
      if (m.y < -5) {
        m.y = H + 5;
        m.x = rand(0, W);
      }
      cx.globalAlpha = 0.25 + Math.sin(m.p * 2) * 0.25 + 0.2;
      cx.fillStyle = m.r > 1.5 ? acc : '#ffffff';
      cx.beginPath();
      cx.arc(m.x, m.y, m.r, 0, 7);
      cx.fill();
    }
    if (!streak && Math.random() < 0.006)
      streak = { y: rand(H * 0.1, H * 0.9), x: -120, v: rand(9, 16), l: rand(60, 160) };
    if (streak) {
      const g = cx.createLinearGradient(streak.x, 0, streak.x + streak.l, 0);
      g.addColorStop(0, 'rgba(255,255,255,0)');
      g.addColorStop(1, acc);
      cx.globalAlpha = 0.6;
      cx.fillStyle = g;
      cx.fillRect(streak.x, streak.y, streak.l, 1.2);
      streak.x += streak.v;
      if (streak.x > W) streak = null;
    }
    cx.globalAlpha = 1;
    raf = requestAnimationFrame(frame);
  };

  const sync = () => {
    const run = document.visibilityState === 'visible' && !reducedMotion();
    if (run && !raf) raf = requestAnimationFrame(frame);
    if (!run && raf) {
      cancelAnimationFrame(raf);
      raf = 0;
    }
    if (!run) cx.clearRect(0, 0, W, H);
  };
  document.addEventListener('visibilitychange', sync);
  sync();
  return () => {
    stopped = true;
    if (raf) cancelAnimationFrame(raf);
    ro.disconnect();
    document.removeEventListener('visibilitychange', sync);
  };
}
