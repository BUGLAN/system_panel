/**
 * 浏览器侧的 PWA 接线：
 *  - Service Worker 注册；新版本就绪时等到「在大厅、没有执行中的单」才切，不在执行中强刷
 *  - 启动时申请持久化存储（navigator.storage.persist），减少浏览器清掉数据的可能
 *  - 音效总线、前后台切换（后台停底噪、挂起音频）、常驻动画在页面不可见时暂停
 *  - 第一次进大厅、没装到主屏幕时弹「添加到主屏幕」引导（iOS 不会自己弹）
 */
import { registerSW } from 'virtual:pwa-register';
import { createAudioBus } from './audio/bus';
import { installSfx, sfx } from './audio/sfx';
import { game } from './store/game';
import { servicesStore } from './store/services';
import { setUi, toast, uiStore } from './store/uiStore';
import { isStandalone } from './ui/overlays/InstallSheet';

export function setupPwa(): void {
  installSfx(createAudioBus(`${import.meta.env.BASE_URL}audio/`));

  // 前后台
  const onVis = () => {
    const vis = document.visibilityState === 'visible';
    sfx.setForeground(vis);
    document.documentElement.classList.toggle('page-hidden', !vis);
  };
  document.addEventListener('visibilitychange', onVis);
  onVis();

  // 底噪只在大厅响
  uiStore.subscribe((s, prev) => {
    if (s.scene !== prev.scene) sfx.ambient(s.scene === 'home');
  });

  // 持久化存储
  try {
    void navigator.storage?.persist?.();
  } catch {
    /* 不支持就算了 */
  }

  // 「添加到主屏幕」引导：第一次进大厅
  uiStore.subscribe((s, prev) => {
    if (
      s.scene === 'home' &&
      prev.scene !== 'home' &&
      !isStandalone() &&
      !servicesStore.getState().prefs.installHintSeen
    ) {
      setTimeout(() => {
        if (uiStore.getState().scene === 'home' && !uiStore.getState().sheet)
          setUi({ sheet: 'install' });
      }, 2500);
    }
  });

  if (import.meta.env.DEV) return;
  let ready = false;
  const update = registerSW({
    onNeedRefresh() {
      ready = true;
      toast('有新版本了：回到大厅时自动更新。');
      tryUpdate();
    },
    onOfflineReady() {
      toast('已经可以离线打开了。', 'ok');
    },
  });
  const tryUpdate = () => {
    const s = uiStore.getState();
    if (ready && s.scene === 'home' && !game().active && !s.show && !s.planJob) void update(true);
  };
  uiStore.subscribe(tryUpdate);
}
