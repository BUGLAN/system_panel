/** 顶栏（参考稿 #hud）：等级环 / 名字与完成数 / 连胜 / 菜单 */
import { dayKey } from '@host/core/time/day';
import { now, tz } from '../../store/game';
import { needFor } from '@host/core/data/rewards';
import { useGame } from '../../store/gameStore';
import { SCENES, setUi, toast, useUi } from '../../store/uiStore';
import { Tap } from '../kit/Btn';
import { IconFlame, IconMenu } from '../kit/icons';

export function Hud() {
  const scene = useUi((s) => s.scene);
  const host = useGame((s) => s.game.host);
  const lastDone = useGame((s) => s.game.meta.lastDoneDay);
  const show = SCENES[scene].hud;
  const need = needFor(host.lv);
  const ratio = Math.min(1, host.exp / need);
  // 「今天」按账号时区、服务器时间算（与连胜判定同口径）
  const todayKey = dayKey(now(), tz());
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
        <span>已完成 {host.doneCount} 单</span>
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
      <Tap className="iconbtn" aria-label="系统设置" onClick={() => setUi({ sheet: 'system' })}>
        <IconMenu />
      </Tap>
    </header>
  );
}
