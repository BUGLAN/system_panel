/**
 * 首启告知页（v2，docs/05 Q5）：数据存在这台服务器上；目标 / 照片经服务器发给模型服务商；
 * 服务器管理员在技术上能接触到数据。同意记录跟账号走，同意后才发请求；不同意就留在本页。
 */
import { useRef, useState } from 'react';
import { giveConsent } from '../../store/services';
import { game } from '../../store/game';
import { go } from '../../store/actions/nav';
import { toast } from '../../store/uiStore';
import { Btn } from '../kit/Btn';
import { Typewriter } from '../kit/Typewriter';
import { useReveal } from '../hooks/useReveal';

export const NOTICE_ROWS: Array<[string, string]> = [
  ['存档', '等级、主线、记录、照片存在这台服务器上，换设备登录还在'],
  ['目标原文与访谈答案', '经服务器发给模型服务商（服务器配的，或你自己填的），拆成任务清单'],
  ['证据照片', '压缩后存在服务器，并发给视觉模型核对；只有你自己的账号能看到'],
  ['谁能看到', '服务器管理员在技术上能接触到数据库和照片；App 里没有任何查看别人数据的功能'],
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
    '你的档存在[这台服务器]上。拆任务、陪你说话、验证据，都要经服务器交给模型服务商过一遍。',
  );
  useReveal(ref);
  const agree = async () => {
    try {
      await giveConsent();
    } catch (e) {
      toast(e instanceof Error ? e.message : '没记上，再点一次。', 'err');
      return;
    }
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
