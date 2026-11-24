/**
 * 3D 卡轮播（参考稿 Carousel）：拖拽 / 甩动 / 滚轮 / 方向键，焦点卡跟手微倾。
 * 卡片内容由 render(i) 给（React 节点），物理与布局在 effect 里直接改 transform。
 */
import { useEffect, useImperativeHandle, useRef, type ReactNode, type Ref } from 'react';

export interface CarouselApi {
  go(i: number): void;
  cardEl(i: number): HTMLDivElement | null;
}

export interface CarouselProps {
  count: number;
  start: number;
  render: (i: number) => ReactNode;
  cardClass?: (i: number) => string;
  cardStyle?: (i: number) => React.CSSProperties;
  onFocus?: (i: number) => void;
  onTap?: (i: number, el: HTMLDivElement) => void;
  /** 宽高比 / 宽度占比 / 最大宽 / 上下留白 / 矮屏紧凑阈值 */
  ar?: number;
  wf?: number;
  max?: number;
  pad?: number;
  shade?: boolean;
  compactH?: number;
  api?: Ref<CarouselApi>;
  children?: ReactNode;
}

const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));

/**
 * 只在值变了才写行内样式。--sh / --op 是继承型自定义属性，写一次整张卡的子树都要重算样式；
 * 拖动时每帧给 14 张卡都写一遍很贵，远处的卡值不变就跳过。
 */
const written = new WeakMap<HTMLElement, Map<string, string>>();
function put(el: HTMLElement, k: string, v: string): void {
  let m = written.get(el);
  if (!m) written.set(el, (m = new Map()));
  if (m.get(k) === v) return;
  m.set(k, v);
  el.style.setProperty(k, v);
}

export function Carousel(p: CarouselProps) {
  const host = useRef<HTMLDivElement>(null);
  const cards = useRef<Array<HTMLDivElement | null>>([]);
  const st = useRef({
    pos: p.start,
    target: p.start,
    idx: -1,
    cw: 0,
    ch: 0,
    tilt: { x: 0, y: 0 },
    raf: 0,
    ready: false,
  });
  const props = useRef(p);
  useEffect(() => {
    props.current = p;
  });

  useImperativeHandle(p.api, () => ({
    go(i: number) {
      st.current.target = clamp(i, 0, props.current.count - 1);
      kick();
    },
    cardEl: (i: number) => cards.current[i] ?? null,
  }));

  function layout(): void {
    const s = st.current;
    cards.current.forEach((c, i) => {
      if (!c) return;
      const d = i - s.pos;
      const a = Math.abs(d);
      const sg = Math.sign(d);
      const x = sg * (Math.min(a, 1) * s.cw * 0.74 + Math.max(0, a - 1) * s.cw * 0.2);
      const ry = -clamp(d, -1.5, 1.5) * 26;
      const rz = d * 3;
      const z = -Math.min(a, 4) * 150;
      const y = Math.min(a, 3) * 16;
      const sc = 1 - Math.min(a, 3) * 0.07;
      const tl = a < 0.5 ? ` rotateX(${s.tilt.y}deg) rotateY(${s.tilt.x}deg)` : '';
      // 完全透明（a ≥ 3.2）的卡直接 visibility:hidden：不绘制、不占合成层的显存（14 张卡 × 正反两面都是 3D 层）
      const gone = a >= 3.2;
      put(c, 'visibility', gone ? 'hidden' : 'visible');
      if (!gone) {
        put(
          c,
          'transform',
          `translate3d(${x}px,${y}px,${z}px) rotateY(${ry}deg) rotateZ(${rz}deg) scale(${sc})${tl}`,
        );
        put(c, 'z-index', String(100 - Math.round(a * 10)));
      }
      if (props.current.shade) {
        put(c, '--sh', (Math.min(a, 1.4) * 0.5).toFixed(3));
        put(c, '--op', a > 2.6 ? Math.max(0, 3.2 - a).toFixed(3) : '1');
      } else {
        put(c, 'opacity', String(a > 2.6 ? Math.max(0, 3.2 - a) : 1));
      }
      c.classList.toggle('focus', a < 0.5);
    });
  }

  const drag = useRef<{
    x: number;
    p: number;
    lx: number;
    lt: number;
    v: number;
    card: HTMLDivElement | null;
    moved: number;
  } | null>(null);

  function tick(): void {
    const s = st.current;
    s.raf = 0;
    if (!host.current) return;
    if (!drag.current) {
      const d = s.target - s.pos;
      s.pos += d * 0.15;
      if (Math.abs(d) < 0.0008) s.pos = s.target;
    }
    layout();
    const idx = clamp(Math.round(s.pos), 0, props.current.count - 1);
    if (idx !== s.idx) {
      s.idx = idx;
      props.current.onFocus?.(idx);
    }
    if (drag.current || s.pos !== s.target) s.raf = requestAnimationFrame(tick);
  }
  function kick(): void {
    if (!st.current.raf) st.current.raf = requestAnimationFrame(tick);
  }

  useEffect(() => {
    const inner = host.current;
    if (!inner) return;
    const measure = () => {
      const o = props.current;
      const W = inner.clientWidth;
      const H = inner.clientHeight;
      const ar = o.ar ?? 0.7;
      const pd = o.pad ?? 24;
      let cw = Math.min(W * (o.wf ?? 0.62), o.max ?? 270);
      let ch = cw / ar;
      if (ch > H - pd) {
        ch = H - pd;
        cw = ch * ar;
      }
      st.current.cw = cw;
      st.current.ch = ch;
      cards.current.forEach((c) => {
        if (!c) return;
        c.classList.toggle('compact', !!o.compactH && ch < o.compactH);
        c.style.width = `${cw}px`;
        c.style.height = `${ch}px`;
        c.style.left = `${(W - cw) / 2}px`;
        c.style.top = `${(H - ch) / 2}px`;
      });
      layout();
    };
    const ro = new ResizeObserver(measure);
    ro.observe(inner);
    measure();
    tick();
    st.current.ready = true;
    let wl = 0;
    const onWheel = (e: WheelEvent) => {
      e.preventDefault();
      const t = performance.now();
      const d = Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY;
      if (t - wl < 280 || Math.abs(d) < 4) return;
      wl = t;
      st.current.target = clamp(
        Math.round(st.current.target) + (d > 0 ? 1 : -1),
        0,
        props.current.count - 1,
      );
      kick();
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return;
      st.current.target = clamp(
        Math.round(st.current.target) + (e.key === 'ArrowRight' ? 1 : -1),
        0,
        props.current.count - 1,
      );
      kick();
    };
    inner.addEventListener('wheel', onWheel, { passive: false });
    addEventListener('keydown', onKey);
    const s = st.current;
    return () => {
      ro.disconnect();
      inner.removeEventListener('wheel', onWheel);
      removeEventListener('keydown', onKey);
      cancelAnimationFrame(s.raf);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [p.count]);

  return (
    <div
      className="car-in"
      ref={host}
      onPointerDown={(e) => {
        drag.current = {
          x: e.clientX,
          p: st.current.pos,
          lx: e.clientX,
          lt: performance.now(),
          v: 0,
          card: (e.target as HTMLElement).closest<HTMLDivElement>('.gcard'),
          moved: 0,
        };
        st.current.tilt = { x: 0, y: 0 };
        try {
          e.currentTarget.setPointerCapture(e.pointerId);
        } catch {
          /* 不支持就算了 */
        }
        kick();
      }}
      onPointerMove={(e) => {
        const d = drag.current;
        const s = st.current;
        if (d) {
          const dx = e.clientX - d.x;
          const t = performance.now();
          d.moved = Math.max(d.moved, Math.abs(dx));
          d.v = d.v * 0.5 + ((e.clientX - d.lx) / Math.max(1, t - d.lt)) * 0.5;
          d.lx = e.clientX;
          d.lt = t;
          s.pos = clamp(d.p - dx / (s.cw * 0.74), -0.35, props.current.count - 0.65);
          kick();
          return;
        }
        if (e.pointerType !== 'mouse') return;
        const c = cards.current[s.idx];
        if (!c) return;
        const r = c.getBoundingClientRect();
        if (
          e.clientX < r.left ||
          e.clientX > r.right ||
          e.clientY < r.top ||
          e.clientY > r.bottom
        ) {
          if (s.tilt.x || s.tilt.y) {
            s.tilt = { x: 0, y: 0 };
            layout();
          }
          return;
        }
        const rx = (e.clientX - r.left) / r.width;
        const ry = (e.clientY - r.top) / r.height;
        s.tilt = { x: (rx - 0.5) * 18, y: -(ry - 0.5) * 14 };
        c.style.setProperty('--mx', `${rx * 100}%`);
        c.style.setProperty('--my', `${ry * 100}%`);
        layout();
      }}
      onPointerUp={() => {
        const d = drag.current;
        const s = st.current;
        if (!d) return;
        drag.current = null;
        if (d.moved < 6) {
          if (d.card) {
            const i = Number(d.card.dataset['i']);
            if (i === s.idx) props.current.onTap?.(i, d.card);
            else {
              s.target = i;
            }
          }
        } else {
          s.target = clamp(
            Math.round(s.pos - (d.v * 200) / (s.cw * 0.74)),
            0,
            props.current.count - 1,
          );
        }
        kick();
      }}
      onPointerCancel={() => {
        drag.current = null;
        kick();
      }}
      onPointerLeave={() => {
        const s = st.current;
        if (!drag.current && (s.tilt.x || s.tilt.y)) {
          s.tilt = { x: 0, y: 0 };
          layout();
        }
      }}
    >
      {Array.from({ length: p.count }, (_, i) => (
        <div
          key={i}
          data-i={i}
          ref={(el) => void (cards.current[i] = el)}
          className={`gcard ${p.cardClass?.(i) ?? ''}`}
          style={p.cardStyle?.(i)}
        >
          {p.render(i)}
        </div>
      ))}
      {p.children}
    </div>
  );
}
