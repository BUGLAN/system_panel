/** 场景进场：.rv 元素错峰淡入上移（参考稿 reveal；只动 transform / opacity） */
import { useLayoutEffect, type RefObject } from 'react';
import { reducedMotion } from '../fx/fx';

export function useReveal(
  ref: RefObject<HTMLElement | null>,
  base = 140,
  deps: unknown[] = [],
): void {
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el || reducedMotion()) return;
    el.querySelectorAll<HTMLElement>('.rv').forEach((n, i) => {
      n.animate(
        [
          { opacity: 0, transform: 'translateY(30px)' },
          { opacity: 1, transform: 'none' },
        ],
        {
          duration: 680,
          delay: base + i * 80,
          easing: 'cubic-bezier(.2,.9,.2,1)',
          fill: 'backwards',
        },
      );
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
}
