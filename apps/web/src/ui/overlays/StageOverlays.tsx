/**
 * 演出叠层：结算 / 升级 / 失败，以及接单前简报与证据来源底板。
 * 升级 ≤ 2s（同一天重复只播简版）；失败更短、更暗、更安静。
 */
import { useEffect, useRef, useState } from 'react';
import { levelUpDurationMs } from '../fx/settleTimeline';
import { attrsText, lootText, questCode, timeLabel } from '@host/core/flow/questText';
import { RANK_COLORS } from '../../design/tokens';
import { sfx } from '../../audio/sfx';
import { closeLevelUp, takeRemedyLater, takeRemedyNow } from '../../store/actions/exec';
import { go } from '../../store/actions/nav';
import { useGame } from '../../store/gameStore';
import { setUi, useUi, type Show } from '../../store/uiStore';
import { Btn, Tap } from '../kit/Btn';
import { IconFlame } from '../kit/icons';
import { burst, center, confetti, flash, reducedMotion, ring } from '../fx/fx';
import { Briefing } from './Briefing';
import { EvidenceSource } from './EvidenceSource';
import { Verdict } from './Verdict';
import { ChatPanel } from './Chat';

const PERKS: Record<number, string> = {
  2: '解锁 [护盾] 购买权限。\n到点那一下，它替你挡。',
  4: '日常单开始有机会 [提一档]。\n奖励跟着涨。',
  5: '每天的日常变成 [2 单]。\n她觉得你扛得住了。',
  8: '日常单最高能出到 [C 档]。\n别让她失望。',
};

function LevelUp({ from, to, brief }: { from: number; to: number; brief: boolean }) {
  const n = useRef<HTMLSpanElement>(null);
  const [canTap, setCanTap] = useState(false);
  useEffect(() => {
    sfx.play('levelup');
    flash();
    if (!brief) confetti();
    const t1 = setTimeout(
      () => {
        const [x, y] = center(n.current);
        burst(x, y, {
          type: 'star',
          n: brief ? 14 : 34,
          colors: ['#d6ff3d', '#fff'],
          min: 3,
          max: 11,
          g: 0.05,
          sz: 4,
          life: 50,
        });
        ring(x, y, '#d6ff3d', 150, 4);
      },
      brief ? 200 : 700,
    );
    const t2 = setTimeout(() => setCanTap(true), levelUpDurationMs(brief));
    return () => {
      clearTimeout(t1);
      clearTimeout(t2);
    };
  }, [brief]);
  const perk = PERKS[to] ?? '全属性成长潜力 [+1]。\n“继续。我在看。”';
  return (
    <div className="ovl on" id="lvup" onClick={() => canTap && void closeLevelUp()}>
      {!brief && !reducedMotion() && <div className="rays" />}
      <div className="lu-t">LEVEL UP!</div>
      <div className="lu-n">
        <span className="o">{from}</span>
        <span className="arr">▶</span>
        <span className="nn" ref={n}>
          {to}
        </span>
      </div>
      <div className="lu-p">
        {perk.split('\n').map((l, i) => (
          <span key={i} style={{ display: 'block' }}>
            {l
              .split(/(\[[^\]]+\])/)
              .map((seg, j) => (seg.startsWith('[') ? <b key={j}>{seg.slice(1, -1)}</b> : seg))}
          </span>
        ))}
      </div>
      <div className="lu-tap" style={{ opacity: canTap ? 1 : 0 }}>
        TAP TO CONTINUE
      </div>
    </div>
  );
}

function Fail({ show }: { show: Extract<Show, { kind: 'fail' }> }) {
  const o = show.outcome;
  const streak = useGame((s) => s.game.host.streak);
  const timeout = o.how === 'timeout';
  const r = o.remedy;
  return (
    <div className="ovl on" id="fail">
      <div className="gl-t" data-t={timeout ? '时间到' : '任务失败'}>
        {timeout ? '时间到' : '任务失败'}
      </div>
      <div className="fail-sub">{timeout ? 'TIME OUT' : 'MISSION FAILED'}</div>
      <div className="fail-box">
        <div className="sk">
          <span className="fail-flame">
            <IconFlame />
          </span>
          {streak}
        </div>
        <p>
          连胜 {streak} 天 · 认输不断连胜
          <br />
          {show.line}
        </p>
      </div>
      {r ? (
        <>
          <div className="fail-rem-h">REMEDY · 补救单已备好</div>
          <div
            className="ticket in fail-ticket"
            style={{ ['--gc' as string]: RANK_COLORS[r.rank] }}
          >
            <div className="tk-g">
              <b>{r.rank}</b>
              <small>{questCode(r)}</small>
            </div>
            <div className="tk-b">
              <span className="tk-k">
                {r.planIndex >= 0
                  ? `补救 · 主线 ${String(r.planIndex + 1).padStart(2, '0')}`
                  : '补救'}
              </span>
              <div className="tk-t">{r.name}</div>
              <div className="tk-m">
                {timeLabel(r)} · {r.proof}
              </div>
              <div className="tk-r">
                <span>{lootText(r)}</span>
                {attrsText(r.attrs) && <span>{attrsText(r.attrs)}</span>}
              </div>
            </div>
          </div>
          <Btn kind="pri" onClick={() => void takeRemedyNow()}>
            接下补救单 · 现在做
          </Btn>
          <Tap className="link fail-later" onClick={() => void takeRemedyLater()}>
            先放委托板，回大厅 ›
          </Tap>
        </>
      ) : (
        <Btn
          kind="ghost"
          onClick={async () => {
            setUi({ show: null });
            await go('home', { noHist: true });
          }}
        >
          回到大厅
        </Btn>
      )}
    </div>
  );
}

export function StageOverlays() {
  const show = useUi((s) => s.show);
  return (
    <>
      {show?.kind === 'verdict' && (
        <Verdict
          key={show.result.quest.serial}
          result={show.result}
          evidenceUrl={show.evidenceUrl}
          line={show.line}
          followUpError={show.followUpError}
        />
      )}
      {show?.kind === 'levelup' && <LevelUp from={show.from} to={show.to} brief={show.brief} />}
      {show?.kind === 'fail' && <Fail show={show} />}
      <Briefing />
      <EvidenceSource />
      <ChatPanel />
    </>
  );
}
