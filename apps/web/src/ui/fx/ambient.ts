/**
 * 背景浮尘 + 偶尔一道流光（参考稿 ambient motes）。常驻循环：页面不可见或减弱动态效果时停。
 *
 * PWA 改（iPhone 发烫）：
 *  - 强调色不再每帧 getComputedStyle（会强制整页样式计算），改为 #app 的 style 变了才读一次
 *  - 只画 30 帧 / 秒（浮尘很慢，看不出差别；画布整屏重画 + 上传减半）
 *  - 位移按真实经过的时间推进（以 60 帧为一个单位），掉帧或高刷屏上速度都不变
 */
import { reducedMotion } from './fx';

const FRAME_MS = 1000 / 30;
const UNIT_MS = 1000 / 60;

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

  let acc = '#d6ff3d';
  const readAccent = () => {
    acc = getComputedStyle(host).getPropertyValue('--accent').trim() || '#d6ff3d';
  };
  readAccent();
  const mo = new MutationObserver(readAccent);
  mo.observe(host, { attributes: true, attributeFilter: ['style', 'class'] });

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
  let timer = 0;
  let last = 0;
  let stopped = false;

  // 画完一帧，隔一段再申请下一帧：rAF 每秒只触发 ~30 次，不在没画的帧上也唤醒主线程
  const next = () => {
    timer = window.setTimeout(() => {
      timer = 0;
      if (!stopped) raf = requestAnimationFrame(frame);
    }, FRAME_MS - 6);
  };

  const frame = (t: number) => {
    raf = 0;
    if (stopped) return;
    next();
    // k = 这一帧相当于几个 60 帧单位（切回前台的第一帧最多补 4 个，免得一下跳很远）
    const k = last ? Math.min(4, (t - last) / UNIT_MS) : 1;
    last = t;
    cx.clearRect(0, 0, W, H);
    for (const m of M) {
      m.y -= m.v * k;
      m.p += m.s * k;
      m.x += Math.sin(m.p) * 0.25 * k;
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
    if (!streak && Math.random() < 0.006 * k)
      streak = { y: rand(H * 0.1, H * 0.9), x: -120, v: rand(9, 16), l: rand(60, 160) };
    if (streak) {
      const g = cx.createLinearGradient(streak.x, 0, streak.x + streak.l, 0);
      g.addColorStop(0, 'rgba(255,255,255,0)');
      g.addColorStop(1, acc);
      cx.globalAlpha = 0.6;
      cx.fillStyle = g;
      cx.fillRect(streak.x, streak.y, streak.l, 1.2);
      streak.x += streak.v * k;
      if (streak.x > W) streak = null;
    }
    cx.globalAlpha = 1;
  };

  const sync = () => {
    const run = document.visibilityState === 'visible' && !reducedMotion();
    if (run && !raf && !timer) {
      last = 0;
      raf = requestAnimationFrame(frame);
    }
    if (!run) {
      if (raf) cancelAnimationFrame(raf);
      if (timer) clearTimeout(timer);
      raf = timer = 0;
      cx.clearRect(0, 0, W, H);
    }
  };
  document.addEventListener('visibilitychange', sync);
  sync();
  return () => {
    stopped = true;
    if (raf) cancelAnimationFrame(raf);
    if (timer) clearTimeout(timer);
    ro.disconnect();
    mo.disconnect();
    document.removeEventListener('visibilitychange', sync);
  };
}
