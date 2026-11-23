/**
 * 演出叠层：结算 / 升级，以及接单前简报与证据来源底板。
 * 升级 ≤ 2s（同一天重复只播简版）。
 */
import { useEffect, useRef, useState } from 'react';
import { levelUpDurationMs } from '../fx/settleTimeline';
import { closeLevelUp } from '../../store/actions/exec';
import { useUi } from '../../store/uiStore';
import { burst, center, confetti, flash, reducedMotion, ring } from '../fx/fx';
import { Briefing } from './Briefing';
import { EvidenceSource } from './EvidenceSource';
import { Verdict } from './Verdict';

function LevelUp({ from, to, brief }: { from: number; to: number; brief: boolean }) {
  const n = useRef<HTMLSpanElement>(null);
  const [canTap, setCanTap] = useState(false);
  useEffect(() => {
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
  const perk = '又往上走了 [一格]。\n“继续。我在看。”';
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
      <Briefing />
      <EvidenceSource />
    </>
  );
}
