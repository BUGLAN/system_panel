/**
 * 首启告知页（简化版，docs/00 第六节）：目标、聊天、照片会发给你自己配置的模型服务商；
 * 同意后才发请求。不同意就留在本页（没有这些她没法工作）。
 */
import { useRef, useState } from 'react';
import { giveConsent } from '../../store/services';
import { game } from '../../store/game';
import { go } from '../../store/actions/nav';
import { Btn } from '../kit/Btn';
import { Typewriter } from '../kit/Typewriter';
import { useReveal } from '../hooks/useReveal';

export const NOTICE_ROWS: Array<[string, string]> = [
  ['目标原文与访谈答案', '发给你配置的模型服务商，拆成任务清单'],
  ['聊天内容', '发给你配置的模型服务商，生成她的回复'],
  ['证据照片', '压缩后发给你配置的视觉模型，核对和任务对不对得上'],
  ['API Key', '只存在这台设备的浏览器里，直接发给服务商，不经过任何中转'],
  ['存档', '等级、主线、记录、照片都只存在这台设备的浏览器里'],
];

export function NoticeList() {
  return (
    <div className="notice-list">
      {NOTICE_ROWS.map(([k, v]) => (
        <div key={k} className="nl-row">
          <b>{k}</b>
          <span>{v}</span>
        </div>
      ))}
    </div>
  );
}

export function Consent() {
  const ref = useRef<HTMLElement>(null);
  const [line, setLine] = useState(
    '拆任务、陪你说话、验证据，都要把内容交给[你自己配置的模型服务商]过一遍。',
  );
  useReveal(ref);
  const agree = async () => {
    await giveConsent();
    const g = game();
    await go(g.goal.plan.length === 0 && !g.pendingGoal ? 'onboard' : g.active ? 'exec' : 'home');
  };
  return (
    <section className="scene nohud on consent" ref={ref}>
      <div className="eyebrow rv">NOTICE · 告知</div>
      <h1 className="h1 rv">
        开工之前，
        <br />
        先把话说清楚。
      </h1>
      <div className="bubble rv consent-bubble">
        <span className="who2">SYSTEM · 她说</span>
        <Typewriter text={line} />
      </div>
      <div className="rv">
        <NoticeList />
      </div>
      <div className="ex-sp" />
      <div className="consent-act rv">
        <Btn kind="pri" onClick={() => void agree()}>
          同意并继续
        </Btn>
        <Btn
          kind="ghost"
          sm
          onClick={() =>
            setLine(
              '明白，不勉强。但没有这些我没法工作：拆不了目标、回不了话、也验不了证据。想好了随时点[同意并继续]。',
            )
          }
        >
          不同意
        </Btn>
      </div>
    </section>
  );
}
