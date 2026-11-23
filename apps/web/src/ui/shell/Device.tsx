/**
 * 设备壳（参考稿 #app）：背景层、环境浮尘、HUD、场景、叠层、toast、亮帧、粒子、转场。
 * 手机上全屏；窗口变宽时钳成 430×920 的手机比例居中。
 */
import { useEffect, useRef, useState } from 'react';
import { useGame } from '../../store/gameStore';
import { installBackKey } from '../../store/actions/nav';
import { SCENES, useUi } from '../../store/uiStore';
import { startAmbient } from '../fx/ambient';
import { burst, registerFx, ring } from '../fx/fx';
import { useKeyboardInset } from '../hooks/useKeyboardInset';
import { ConfirmHost } from '../kit/Confirm';
import { Toasts } from '../kit/Toasts';
import { OverlayHost } from './OverlayHost';
import { SceneHost } from './SceneHost';
import { Hud } from './Hud';
import { Wipe } from './Wipe';

export function Device() {
  const app = useRef<HTMLElement>(null);
  const fx = useRef<HTMLCanvasElement>(null);
  const bgfx = useRef<HTMLCanvasElement>(null);
  const flash = useRef<HTMLDivElement>(null);
  const ghostRef = useRef<HTMLDivElement>(null);
  const [host, setHost] = useState<HTMLElement | null>(null);
  const scene = useUi((s) => s.scene);
  const goalShort = useGame((s) => s.game.goal.short);
  const meta = SCENES[scene];
  const ghost = scene === 'main' && goalShort ? goalShort.slice(0, 4) : meta.ghost;

  useEffect(() => {
    if (!app.current || !fx.current || !flash.current || !bgfx.current) return;
    setHost(app.current);
    const off = registerFx({ app: app.current, canvas: fx.current, flash: flash.current });
    const offAmb = startAmbient(bgfx.current, app.current);
    const offBack = installBackKey();
    return () => {
      off();
      offAmb();
      offBack();
    };
  }, []);
  useKeyboardInset(host);

  useEffect(() => {
    ghostRef.current?.animate(
      [
        { opacity: 0, transform: 'translateX(-50%) scale(1.3)' },
        { opacity: 1, transform: 'translateX(-50%) scale(1)' },
      ],
      { duration: 900, easing: 'cubic-bezier(.2,.9,.2,1)' },
    );
  }, [ghost]);

  return (
    <>
      <div className="stage-deco" aria-hidden="true">
        <div className="big t">HOST//SYSTEM · 宿主养成系统 · HOST//SYSTEM · 宿主养成系统 · </div>
        <div className="big b">清单不会自己变短 · LEVEL UP · 清单不会自己变短 · LEVEL UP · </div>
        <div className="side">SYSTEM IS WATCHING · 她在看着你</div>
      </div>
      <main
        id="app"
        ref={app}
        style={{ ['--accent' as string]: meta.acc }}
        onPointerDownCapture={(e) => {
          const a = app.current?.getBoundingClientRect();
          if (!a) return;
          const x = e.clientX - a.left;
          const y = e.clientY - a.top;
          burst(x, y, {
            n: 7,
            min: 1,
            max: 4,
            life: 16,
            sz: 1.3,
            g: 0,
            colors: [meta.acc, '#fff'],
          });
          ring(x, y, meta.acc, 28, 2);
        }}
      >
        <div className="bg">
          <div className="neb" />
          <div className="ghost" ref={ghostRef}>
            {ghost}
          </div>
          <div className="horizon" />
          <div className="floor" />
          <div className="scan" />
          <div className="noise" />
          <div className="vig" />
        </div>
        <canvas id="bgfx" ref={bgfx} />
        <Hud />
        <SceneHost />
        <OverlayHost />
        <ConfirmHost />
        <Toasts />
        <div id="flash" ref={flash} />
        <canvas id="fx" ref={fx} />
        <Wipe />
      </main>
    </>
  );
}
