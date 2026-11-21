/** 音效试听页（开发用）：逐条点听，核对事件 → 声音的映射 */
import { createAudioBus } from '../audio/bus';
import type { SfxName } from '../audio/sfx';
import { SFX_TIER } from '../audio/voices';

export const SFX_DOC: Record<SfxName, string> = {
  press: '按下任何按钮（基础按钮组件自己出声）· 按钮下压',
  soft: '轻点：切筛选、点选项、戳她 · 选中高亮',
  swipe: '卡片轮播换焦点、转场扫出 · 卡片位移',
  whoosh: '场景斜切转场 · wipe 斜带',
  tick: '刻度 / 计数 · 数字跳动',
  scan: '结算扫描证据 · 扫描进度条',
  type: '打字机逐字（每两字一声）· 文字逐字出现',
  deal: '访谈发牌、卡组到手 · 卡片入场',
  success: '证据入槽、补签成功、保存设置 · 绿色 toast / 粒子',
  error: '被拒：没证据、买不起、主线锁住、拆解失败 · 红色 toast / 抖动',
  coin: '装载道具、奖励行入账 · 数字滚动',
  buy: '购买成功 · 卡片闪光',
  unlock: '名牒解锁、新目标落库、下一张卡解封 · 名牒卡 / 星星',
  boot: '唤醒系统 · 开机屏爆闪',
  stamp: '结算评级印章砸下 / 主线盖章（亮帧踩这一帧）· 印章 + 白闪 + 震屏',
  crit: '暴击 · CRIT 横幅 + 印章 + 红色粒子',
  levelup: '升级（经验条跨级的白闪 + 升级叠层）· LEVEL UP 叠层',
  fail: '认输 / 超时判负（更短更暗更安静）· 失败页 + 暗色亮帧',
  shield: '护盾到点挡下一次 · toast + 白闪',
};

const bus = createAudioBus('/audio/');
const list = document.getElementById('list');
for (const [name, doc] of Object.entries(SFX_DOC) as Array<[SfxName, string]>) {
  const tr = document.createElement('tr');
  const tier = SFX_TIER[name];
  tr.innerHTML = `<td><b>${name}</b></td><td><span class="tier ${tier}">${tier}</span></td><td>${doc}</td><td><button>播放</button></td>`;
  tr.querySelector('button')?.addEventListener('click', () => {
    bus.unlock();
    setTimeout(() => bus.play(name), 30);
  });
  list?.appendChild(tr);
}
const hold = document.getElementById('hold');
let raf = 0;
hold?.addEventListener('pointerdown', () => {
  bus.unlock();
  bus.holdStart();
  const t0 = performance.now();
  const step = () => {
    bus.holdSet(Math.min(1, (performance.now() - t0) / 1600));
    raf = requestAnimationFrame(step);
  };
  step();
});
for (const ev of ['pointerup', 'pointerleave']) {
  hold?.addEventListener(ev, () => {
    cancelAnimationFrame(raf);
    bus.holdStop();
  });
}
let amb = false;
document.getElementById('amb')?.addEventListener('click', () => {
  bus.unlock();
  amb = !amb;
  bus.ambient(amb);
});
document
  .getElementById('vol')
  ?.addEventListener('input', (e) => bus.setVolume(Number((e.target as HTMLInputElement).value)));
