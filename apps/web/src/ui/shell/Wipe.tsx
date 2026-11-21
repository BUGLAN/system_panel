/** 斜切转场（参考稿 #wipe）：三条斜带扫入 360ms → 切场景 → 扫出 420ms */
import { useEffect, useRef, useState } from 'react';
import { registerWipe } from '../../store/actions/nav';
import { sfx } from '../../audio/sfx';
import { reducedMotion } from '../fx/fx';

const E = 'cubic-bezier(.75,0,.25,1)';
const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

export function Wipe() {
  const host = useRef<HTMLDivElement>(null);
  const [label, setLabel] = useState({ title: '', sub: '', color: '#d6ff3d' });

  useEffect(() => {
    registerWipe(async ({ color, title, sub, dir, mid }) => {
      const el = host.current;
      if (!el) return mid();
      if (reducedMotion()) {
        mid();
        return;
      }
      setLabel({ title, sub: `${sub} · LOADING`, color });
      el.style.display = 'block';
      const bars = [...el.querySelectorAll<HTMLElement>('.wb')];
      await Promise.all(
        bars.map(
          (b, i) =>
            b.animate(
              [
                { transform: `translateX(${dir * 130}%) skewX(-18deg)` },
                { transform: 'translateX(0) skewX(-18deg)' },
              ],
              {
                duration: 360,
                delay: i * 65,
                easing: E,
                fill: 'forwards',
              },
            ).finished,
        ),
      );
      mid();
      el.querySelector('.wl')?.animate(
        [{ transform: 'skewX(18deg) scale(1)' }, { transform: 'skewX(18deg) scale(1.08)' }],
        {
          duration: 260,
        },
      );
      await sleep(140);
      sfx.play('swipe');
      await Promise.all(
        bars.map(
          (b, i) =>
            b.animate(
              [
                { transform: 'translateX(0) skewX(-18deg)' },
                { transform: `translateX(${-dir * 130}%) skewX(-18deg)` },
              ],
              {
                duration: 420,
                delay: (bars.length - 1 - i) * 65,
                easing: E,
                fill: 'forwards',
              },
            ).finished,
        ),
      );
      el.style.display = 'none';
    });
    return () => registerWipe(null);
  }, []);

  return (
    <div id="wipe" ref={host} style={{ ['--wc' as string]: label.color }}>
      <div className="wb wb1" />
      <div className="wb wb2" />
      <div className="wb wb3">
        <div className="wl">
          <b>{label.title}</b>
          <small>{label.sub}</small>
          <i />
        </div>
      </div>
    </div>
  );
}
