/**
 * 软键盘高度：visualViewport 比布局视口矮多少，就是键盘挡住了多少。
 * 写进 #app 的 --kb 变量，.kb-dock 据此吸在键盘上沿（B3）。
 *
 * 顺带把 iOS 主屏幕 App 的整页滚动拉回 0（整页本来就不滚，内容在 fixed 的 #root 里）：
 *  - iOS 26 起「添加到主屏幕」打开时，输入框一获得焦点，WebKit 会把整页滚到 scrollY = -62（滚进状态栏那条），
 *    之后画面和点击差一个状态栏高度——点下面的输入框落到上面那个上、光标画在框外。负的滚动一律当场拉回。
 *  - 键盘收起后还残留滚动也拉回，免得整页停在半截、点击错位。
 *  （2026-11-24 在 iOS 模拟器上量的）
 * offsetTop 只算向下平移的部分：上面那种 -62 的状态没弹键盘，照算会凭空多出 62px「键盘」，把底部按钮顶上去。
 */
import { useEffect } from 'react';

const isTextField = (el: Element | null): boolean =>
  el instanceof HTMLTextAreaElement ||
  (el instanceof HTMLInputElement && el.type !== 'button' && el.type !== 'checkbox') ||
  (el instanceof HTMLElement && el.isContentEditable);

export function useKeyboardInset(host: HTMLElement | null): void {
  useEffect(() => {
    const vv = typeof window === 'undefined' ? null : window.visualViewport;
    if (!host || !vv) return;
    const update = () => {
      if (window.scrollY < 0) window.scrollTo(0, 0);
      const inset = Math.max(0, window.innerHeight - vv.height - Math.max(0, vv.offsetTop));
      host.style.setProperty('--kb', `${Math.round(inset)}px`);
      host.classList.toggle('kb-open', inset > 80);
    };
    // 焦点从一个输入框换到另一个时也会先失焦，等一拍看焦点落哪儿再决定
    let blurTimer = 0;
    const onFocusOut = () => {
      clearTimeout(blurTimer);
      blurTimer = window.setTimeout(() => {
        if (!isTextField(document.activeElement) && window.scrollY !== 0) window.scrollTo(0, 0);
      }, 120);
    };
    update();
    vv.addEventListener('resize', update);
    vv.addEventListener('scroll', update);
    window.addEventListener('scroll', update, { passive: true });
    document.addEventListener('focusout', onFocusOut);
    return () => {
      clearTimeout(blurTimer);
      vv.removeEventListener('resize', update);
      vv.removeEventListener('scroll', update);
      window.removeEventListener('scroll', update);
      document.removeEventListener('focusout', onFocusOut);
    };
  }, [host]);
}
