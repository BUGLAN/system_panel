/** 开机屏（参考稿 #boot）：日志逐行 360ms、进度条，点击唤醒 */
import { useEffect, useRef, useState } from 'react';
import { sfx } from '../../audio/sfx';
import { bootData, bootLines, enterAfterBoot } from '../../store/actions/boot';
import { Core } from '../kit/Core';
import { burst, center, flash, reducedMotion, ring } from '../fx/fx';

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

export function Boot() {
  const [lines, setLines] = useState<string[]>([]);
  const [p, setP] = useState(0);
  const [go, setGo] = useState(false);
  const [happy, setHappy] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  const coreRef = useRef<HTMLDivElement>(null);
  const started = useRef(false);

  useEffect(() => {
    let alive = true;
    void (async () => {
      await bootData();
      const all = bootLines();
      for (let i = 0; i < all.length && alive && !started.current; i++) {
        setLines((l) => [...l, all[i] as string].slice(-5));
        setP((i + 1) / all.length);
        await sleep(360);
      }
      if (alive) setGo(true);
    })();
    return () => {
      alive = false;
    };
  }, []);

  const start = async () => {
    if (started.current) return;
    started.current = true;
    await bootData();
    sfx.unlock();
    sfx.play('boot');
    setHappy(true);
    flash();
    const [x, y] = center(coreRef.current);
    burst(x, y, { n: 56, colors: ['#d6ff3d', '#3be8ff', '#fff'], min: 3, max: 14, life: 40 });
    ring(x, y, '#d6ff3d', 240, 5);
    ring(x, y, '#3be8ff', 160, 3);
    const el = root.current;
    if (el && !reducedMotion()) {
      await el.animate(
        [
          { opacity: 1, transform: 'scale(1)' },
          { opacity: 0, transform: 'scale(1.15)' },
        ],
        { duration: 620, delay: 240, easing: 'ease-in', fill: 'forwards' },
      ).finished;
    }
    enterAfterBoot();
  };

  return (
    <div id="boot" ref={root} onClick={() => void start()} role="button" aria-label="点击唤醒系统">
      <div ref={coreRef}>
        <Core mood={happy ? 'happy' : ''} />
      </div>
      <div className="boot-logo">
        <span>HOST</span>
        <i>//</i>
        <span>SYSTEM</span>
      </div>
      <div className="boot-sub">宿 主 养 成 系 统</div>
      <div className="boot-log">
        {lines.map((l, i) => (
          <div key={`${i}-${l}`} className="bl">
            &gt;{' '}
            {l.includes('✓') ? (
              <>
                {l.replace(' ✓', '')} <span className="ok">✓</span>
              </>
            ) : (
              l
            )}
          </div>
        ))}
      </div>
      <div className="boot-bar">
        <i style={{ ['--p' as string]: p }} />
      </div>
      <button className={`boot-go ${go ? 'on' : ''}`} type="button">
        点击唤醒系统<small>TAP TO START</small>
      </button>
    </div>
  );
}
