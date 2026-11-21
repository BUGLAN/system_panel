/**
 * 她的头像（系统核心）：多层旋转环 + 会跟手的眼睛 + 眨眼；情绪：happy / angry / scan / love。
 * 移植自参考稿 coreSVG / trackEyes / 眨眼定时器。
 */
import { useEffect, useId, useRef, type PointerEventHandler } from 'react';

export type CoreMood = '' | 'happy' | 'angry' | 'scan' | 'love';

const cores = new Set<HTMLElement>();
let px = 0;
let py = 0;
let wired = false;

function track(): void {
  for (const c of cores) {
    const r = c.getBoundingClientRect();
    if (!r.width) continue;
    const dx = px - (r.left + r.width / 2);
    const dy = py - (r.top + r.height / 2);
    const d = Math.hypot(dx, dy) || 1;
    const m = Math.min(15, d / 12);
    const ir = c.querySelector<SVGGElement>('.iris');
    if (ir)
      ir.style.transform = `translate(${(dx / d) * m}px,${((dy / d) * m * 0.7).toFixed(2)}px)`;
  }
}

function wire(): void {
  if (wired || typeof window === 'undefined') return;
  wired = true;
  px = innerWidth / 2;
  py = innerHeight / 2;
  addEventListener('pointermove', (e) => {
    px = e.clientX;
    py = e.clientY;
    track();
  });
  setInterval(() => {
    if (document.visibilityState !== 'visible') return;
    for (const c of cores) {
      if (Math.random() < 0.45 || c.classList.contains('happy') || c.classList.contains('love'))
        continue;
      c.querySelector('.eye')?.animate(
        [{ transform: 'scaleY(1)' }, { transform: 'scaleY(.06)' }, { transform: 'scaleY(1)' }],
        {
          duration: 170,
        },
      );
    }
  }, 2600);
}

export function Core({
  mood = '',
  className = '',
  onPointerDown,
  onPointerUp,
  onPointerLeave,
}: {
  mood?: CoreMood;
  className?: string;
  onPointerDown?: PointerEventHandler<HTMLDivElement>;
  onPointerUp?: PointerEventHandler<HTMLDivElement>;
  onPointerLeave?: PointerEventHandler<HTMLDivElement>;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const gid = `cg${useId().replace(/:/g, '')}`;
  useEffect(() => {
    wire();
    const el = ref.current;
    if (!el) return;
    cores.add(el);
    return () => {
      cores.delete(el);
    };
  }, []);
  return (
    <div
      ref={ref}
      className={`core ${mood} ${className}`}
      onPointerDown={onPointerDown}
      onPointerUp={onPointerUp}
      onPointerLeave={onPointerLeave}
      onContextMenu={(e) => e.preventDefault()}
    >
      <svg viewBox="0 0 200 200" aria-hidden="true">
        <defs>
          <radialGradient id={gid}>
            <stop offset="0" style={{ stopColor: 'var(--cc)', stopOpacity: 0.5 }} />
            <stop offset=".55" style={{ stopColor: 'var(--cc)', stopOpacity: 0.1 }} />
            <stop offset="1" style={{ stopColor: 'var(--cc)', stopOpacity: 0 }} />
          </radialGradient>
        </defs>
        <circle className="halo" cx="100" cy="100" r="99" fill={`url(#${gid})`} />
        <g className="r r1">
          <circle
            className="st"
            cx="100"
            cy="100"
            r="93"
            fill="none"
            strokeWidth="1.2"
            strokeDasharray="1 5"
            opacity=".7"
          />
        </g>
        <g className="r r2">
          <circle
            className="st"
            cx="100"
            cy="100"
            r="81"
            fill="none"
            strokeWidth="2.5"
            strokeDasharray="80 22 10 22"
          />
        </g>
        <g className="r r4">
          <path
            className="st2"
            d="M100 28 a72 72 0 0 1 62 36"
            fill="none"
            strokeWidth="3.5"
            strokeLinecap="round"
          />
          <path
            className="st2"
            d="M100 172 a72 72 0 0 1 -62 -36"
            fill="none"
            strokeWidth="3.5"
            strokeLinecap="round"
          />
        </g>
        <g className="r r3">
          <circle
            className="st"
            cx="100"
            cy="100"
            r="64"
            fill="none"
            strokeWidth="1.4"
            strokeDasharray="2 8"
            opacity=".85"
          />
        </g>
        <g className="eye">
          <path
            className="st"
            d="M36 100 Q100 44 164 100 Q100 156 36 100Z"
            fill="rgba(6,5,14,.9)"
            strokeWidth="3"
          />
          <g className="iris">
            <circle className="st" cx="100" cy="100" r="26" fill="none" strokeWidth="2" />
            <circle className="fl" cx="100" cy="100" r="19" opacity=".22" />
            <circle className="fl" cx="100" cy="100" r="10" />
            <circle cx="92" cy="92" r="4" fill="#fff" />
          </g>
        </g>
        <path
          className="happy st"
          d="M58 112 Q100 66 142 112"
          fill="none"
          strokeWidth="9"
          strokeLinecap="round"
        />
        <path
          className="brow"
          d="M50 58 L90 76 M150 58 L110 76"
          stroke="#ff3b7a"
          strokeWidth="7"
          strokeLinecap="round"
        />
        <path
          className="heart fl"
          d="M100 134 C58 108 60 72 84 70 C95 69 100 79 100 84 C100 79 105 69 116 70 C140 72 142 108 100 134Z"
        />
      </svg>
    </div>
  );
}
