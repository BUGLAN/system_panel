/** 顶栏（参考稿 #hud）：等级环 / 称号 / 连胜 / 晶核 / 聊天 / 菜单 */
import { needFor } from '@host/core/data/rewards';
import { titleName } from '@host/core/data/titles';
import { useGame } from '../../store/gameStore';
import { SCENES, setUi, toast, useUi } from '../../store/uiStore';
import { Tap } from '../kit/Btn';
import { IconChat, IconCoin, IconFlame, IconMenu } from '../kit/icons';

export function Hud() {
  const scene = useUi((s) => s.scene);
  const host = useGame((s) => s.game.host);
  const lastDone = useGame((s) => s.game.meta.lastDoneDay);
  const show = SCENES[scene].hud;
  const need = needFor(host.lv);
  const ratio = Math.min(1, host.exp / need);
  const today = new Date();
  const todayKey = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
  return (
    <header id="hud" className={show ? '' : 'hide'}>
      <Tap
        className="lv"
        aria-label="等级"
        quiet
        onClick={() =>
          toast(`EXP ${host.exp} / ${need} · 距离 LV${host.lv + 1} 还差 ${need - host.exp}`)
        }
      >
        <svg viewBox="0 0 60 60">
          <circle className="trk" cx="30" cy="30" r="26" fill="none" strokeWidth="4" />
          <circle
            className="bar"
            cx="30"
            cy="30"
            r="26"
            fill="none"
            strokeWidth="4"
            strokeDasharray="163.4"
            strokeDashoffset={163.4 * (1 - ratio)}
          />
        </svg>
        <span className="n">{host.lv}</span>
      </Tap>
      <div className="who">
        <b>{host.name}</b>
        <span className={host.title === 'mouth' ? 'shame' : ''}>「{titleName(host.title)}」</span>
      </div>
      <Tap
        className="chip streak"
        id="hudStreak"
        quiet
        onClick={() =>
          toast(
            `连胜 ${host.streak} 天。${lastDone === todayKey ? '今天已打卡。' : '今天还没完成任何一单。'}`,
          )
        }
      >
        <IconFlame />
        <span>{host.streak}</span>
      </Tap>
      <Tap
        className="chip coin"
        id="hudCoin"
        quiet
        onClick={() =>
          toast(
            `晶核 ${host.coins}。${host.coins < 45 ? '穷，但是干净。' : '有点小钱了，别乱花。'}`,
          )
        }
      >
        <IconCoin />
        <span>{host.coins}</span>
      </Tap>
      <Tap className="iconbtn" aria-label="和她说话" onClick={() => setUi({ chatOpen: true })}>
        <IconChat />
      </Tap>
      <Tap className="iconbtn" aria-label="系统设置" onClick={() => setUi({ sheet: 'system' })}>
        <IconMenu />
      </Tap>
    </header>
  );
}
