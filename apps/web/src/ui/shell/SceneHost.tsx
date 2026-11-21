/** 只挂当前场景（离开即卸载，常驻动画随之停掉） */
import { useUi } from '../../store/uiStore';
import { Archive } from '../scenes/Archive';
import { Board } from '../scenes/Board';
import { Boot } from '../scenes/Boot';
import { Consent } from '../scenes/Consent';
import { Exec } from '../scenes/Exec';
import { Home } from '../scenes/Home';
import { Main } from '../scenes/Main';
import { Onboard } from '../scenes/Onboard';
import { Shop } from '../scenes/Shop';

export function SceneHost() {
  const scene = useUi((s) => s.scene);
  switch (scene) {
    case 'boot':
      return <Boot />;
    case 'consent':
      return <Consent />;
    case 'onboard':
      return <Onboard />;
    case 'home':
      return <Home />;
    case 'main':
      return <Main />;
    case 'board':
      return <Board />;
    case 'exec':
      return <Exec />;
    case 'archive':
      return <Archive />;
    case 'shop':
      return <Shop />;
  }
}
