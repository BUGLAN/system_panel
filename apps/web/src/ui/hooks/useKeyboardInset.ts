/**
 * 软键盘高度：visualViewport 比布局视口矮多少，就是键盘挡住了多少。
 * 写进 #app 的 --kb 变量，CTA 用 translateY(-var(--kb)) 吸在键盘上沿（B3）。
 */
import { useEffect } from 'react';

export function useKeyboardInset(host: HTMLElement | null): void {
  useEffect(() => {
    const vv = typeof window === 'undefined' ? null : window.visualViewport;
    if (!host || !vv) return;
    const update = () => {
      const inset = Math.max(0, window.innerHeight - vv.height - vv.offsetTop);
      host.style.setProperty('--kb', `${Math.round(inset)}px`);
      host.classList.toggle('kb-open', inset > 80);
    };
    update();
    vv.addEventListener('resize', update);
    vv.addEventListener('scroll', update);
    return () => {
      vv.removeEventListener('resize', update);
      vv.removeEventListener('scroll', update);
    };
  }, [host]);
}
