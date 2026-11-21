/** 应用根：样式 + 设备壳。读档与开机序列在开机屏里跑。 */
import './ui/styles/ref-shell.css';
import './ui/styles/ref-cards.css';
import './ui/styles/ref-exec.css';
import './ui/styles/ref-archive.css';
import './ui/styles/ref-overlays.css';
import './ui/styles/ref-maincards.css';
import './ui/styles/extra.css';
import { Device } from './ui/shell/Device';

export function App() {
  return <Device />;
}
