/** 按住认输（参考稿 #giveUp）：按满 1.6s 才算；中途松手进度回落，她嘀咕一句 */
import { useEffect, useRef } from 'react';
import { LINES, pickBySeed } from '@host/core/data/lines';
import { sfx } from '../../audio/sfx';
import { sayWatch } from '../../store/uiStore';
import { haptic } from '../haptics';
import { appEl } from '../fx/fx';

const HOLD_MS = 1600;

/** 按住的控制器：挂在按钮元素上，事件监听在 effect 里装卸 */
function attachHold(
  btn: HTMLButtonElement,
  done: () => void,
  isDisabled: () => boolean,
): () => void {
  let on = false;
  let t0 = 0;
  let p = 0;
  let raf = 0;
  const setP = (v: number) => {
    p = v;
    btn.style.setProperty('--p', String(v));
  };
  const step = () => {
    if (!on) return;
    setP(Math.min(1, (performance.now() - t0) / HOLD_MS));
    sfx.holdSet(p);
    const app = appEl();
    if (app && p > 0.25 && Math.random() < p) {
      app.animate(
        [
          {
            transform: `translate(${(Math.random() - 0.5) * 6 * p}px,${(Math.random() - 0.5) * 6 * p}px)`,
          },
          { transform: 'none' },
        ],
        { duration: 70 },
      );
    }
    if (p >= 1) {
      on = false;
      sfx.holdStop();
      btn.classList.remove('ing');
      setP(0);
      haptic.fail();
      done();
      return;
    }
    raf = requestAnimationFrame(step);
  };
  const down = () => {
    if (isDisabled()) return;
    on = true;
    t0 = performance.now();
    btn.classList.add('ing');
    sfx.holdStart();
    haptic.tap();
    sayWatch('……你在按什么？[松手]。');
    raf = requestAnimationFrame(step);
  };
  const release = () => {
    if (!on) return;
    on = false;
    cancelAnimationFrame(raf);
    sfx.holdStop();
    btn.classList.remove('ing');
    if (p > 0.3) sayWatch(pickBySeed(LINES.waver, String(Date.now())));
    const p0 = p;
    const t1 = performance.now();
    const back = () => {
      if (on) return;
      const k = Math.min(1, (performance.now() - t1) / 300);
      setP(p0 * (1 - k));
      if (k < 1) requestAnimationFrame(back);
    };
    back();
  };
  const ctx = (e: Event) => e.preventDefault();
  btn.addEventListener('pointerdown', down);
  for (const ev of ['pointerup', 'pointerleave', 'pointercancel'])
    btn.addEventListener(ev, release);
  btn.addEventListener('contextmenu', ctx);
  return () => {
    on = false;
    cancelAnimationFrame(raf);
    btn.removeEventListener('pointerdown', down);
    for (const ev of ['pointerup', 'pointerleave', 'pointercancel'])
      btn.removeEventListener(ev, release);
    btn.removeEventListener('contextmenu', ctx);
  };
}

export function HoldButton({
  label,
  onDone,
  disabled,
}: {
  label: string;
  onDone: () => void;
  disabled?: boolean;
}) {
  const ref = useRef<HTMLButtonElement>(null);
  const doneRef = useRef(onDone);
  const disRef = useRef(!!disabled);
  useEffect(() => {
    doneRef.current = onDone;
    disRef.current = !!disabled;
  });
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    return attachHold(
      el,
      () => doneRef.current(),
      () => disRef.current,
    );
  }, []);
  return (
    <button ref={ref} type="button" className="btn hold" disabled={disabled}>
      <span className="fill" />
      {label}
    </button>
  );
}
