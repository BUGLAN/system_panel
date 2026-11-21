/**
 * 「添加到主屏幕」引导：iOS 不会弹安装提示，得手动加；说清楚不加的话浏览器可能清掉数据。
 * Android Chrome 支持 beforeinstallprompt 时直接给安装按钮。
 */
import { setPrefs } from '../../store/services';
import { setUi, useUi } from '../../store/uiStore';
import { Btn } from '../kit/Btn';
import { Sheet } from '../kit/Sheet';

interface InstallPromptEvent extends Event {
  prompt(): Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
}

let deferred: InstallPromptEvent | null = null;
if (typeof window !== 'undefined') {
  addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault();
    deferred = e as InstallPromptEvent;
  });
}

export function isStandalone(): boolean {
  if (typeof window === 'undefined') return false;
  return (
    matchMedia('(display-mode: standalone)').matches ||
    (navigator as Navigator & { standalone?: boolean }).standalone === true
  );
}

export function isIos(): boolean {
  if (typeof navigator === 'undefined') return false;
  return (
    /iPhone|iPad|iPod/i.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)
  );
}

export function InstallSheet() {
  const open = useUi((s) => s.sheet === 'install');
  const canPrompt = open && deferred !== null;
  const close = () => {
    void setPrefs({ installHintSeen: true });
    setUi({ sheet: null });
  };
  return (
    <Sheet open={open} onClose={close} title="添加到主屏幕">
      {isStandalone() ? (
        <p className="sheet-note">已经在主屏幕上全屏运行了。</p>
      ) : (
        <>
          <p className="sheet-note">
            这个 App 的数据只存在这个浏览器里。
            <b>不添加到主屏幕的话，浏览器在空间紧张或长时间没打开时可能把数据清掉。</b>
            添加之后全屏运行、断网也能打开，记得也定期在设置里「导出存档」。
          </p>
          {isIos() ? (
            <ol className="install-steps">
              <li>用 Safari 打开这个页面</li>
              <li>点底部的「分享」按钮（方框加向上箭头）</li>
              <li>往下找到「添加到主屏幕」，点「添加」</li>
              <li>以后从主屏幕的图标打开</li>
            </ol>
          ) : (
            <ol className="install-steps">
              <li>用 Chrome 打开这个页面</li>
              <li>点右上角菜单「⋮」</li>
              <li>选「安装应用」或「添加到主屏幕」</li>
            </ol>
          )}
          {canPrompt && (
            <Btn
              kind="pri"
              sm
              onClick={async () => {
                const d = deferred;
                if (!d) return;
                await d.prompt();
                deferred = null;
                close();
              }}
            >
              立即安装
            </Btn>
          )}
        </>
      )}
      <Btn kind="ghost" sm onClick={close}>
        知道了
      </Btn>
    </Sheet>
  );
}
