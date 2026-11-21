/**
 * 场景路由：斜切 wipe 转场（参考稿 go/back），返回栈，浏览器返回键 → 先关叠层再返回。
 */
import { sfx } from '../../audio/sfx';
import { game } from '../game';
import { SCENES, setUi, uiStore, type Scene } from '../uiStore';

type WipeRunner = (o: {
  color: string;
  title: string;
  sub: string;
  dir: 1 | -1;
  mid: () => void;
}) => Promise<void>;

let wipe: WipeRunner | null = null;
export function registerWipe(fn: WipeRunner | null): void {
  wipe = fn;
}

/** 切场景。exec 没有执行中的单就回大厅。 */
export async function go(
  name: Scene,
  opt: { back?: boolean; noHist?: boolean } = {},
): Promise<void> {
  const s = uiStore.getState();
  if (s.navBusy || name === s.scene) return;
  let target = name;
  if (target === 'exec' && !game().active) target = 'home';
  const meta = SCENES[target];
  const commit = () => {
    const cur = uiStore.getState();
    let hist = cur.hist;
    if (target === 'home') hist = [];
    else if (
      !opt.back &&
      cur.scene !== 'boot' &&
      !opt.noHist &&
      cur.scene !== 'onboard' &&
      cur.scene !== 'consent'
    ) {
      hist = [...hist, cur.scene].slice(-10);
    }
    setUi({ scene: target, hist, briefing: null });
  };
  setUi({ navBusy: true });
  sfx.play('whoosh');
  try {
    if (wipe && s.scene !== 'boot') {
      await wipe({
        color: meta.acc,
        title: meta.title,
        sub: meta.sub,
        dir: opt.back ? -1 : 1,
        mid: commit,
      });
    } else {
      commit();
    }
  } finally {
    setUi({ navBusy: false });
  }
}

export function back(): void {
  const s = uiStore.getState();
  if (s.navBusy) return;
  const hist = [...s.hist];
  let to: Scene = hist.pop() ?? 'home';
  if (to === 'exec' && !game().active) to = 'home';
  setUi({ hist });
  void go(to, { back: true });
}

/** 返回键（浏览器 / 安卓）：先关最上层的叠层；都关了才返回上一场景 */
export function handleBackKey(): void {
  const s = uiStore.getState();
  if (s.confirm) return s.confirm.resolve(false);
  if (s.show) return; // 演出中不让退
  if (s.planJob) return;
  if (s.briefing) return setUi({ briefing: null });
  if (s.sheet) return setUi({ sheet: null });
  if (s.chatOpen) return setUi({ chatOpen: false });
  if (s.scene === 'exec') return void go('home');
  if (s.scene === 'home' || s.scene === 'boot' || s.scene === 'onboard' || s.scene === 'consent')
    return;
  back();
}

/** 挂浏览器返回键：始终在历史里垫一层，按返回只触发我们自己的处理 */
export function installBackKey(): () => void {
  if (typeof history === 'undefined') return () => {};
  history.pushState({ app: 1 }, '');
  const onPop = () => {
    history.pushState({ app: 1 }, '');
    handleBackKey();
  };
  addEventListener('popstate', onPop);
  return () => removeEventListener('popstate', onPop);
}
