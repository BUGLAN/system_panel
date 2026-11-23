/**
 * 执行面板（参考稿 #sc-exec）：不计时，做完随时交；
 * 快照记录（≤3 张，后台校验，拒收留痕）、【提交任务】、收起。
 */
import { useEffect, useRef, useState } from 'react';
import { fmtDur } from '@host/core/format';
import { questCode, timeLabel } from '@host/core/flow/questText';
import { RANK_COLORS } from '../../design/tokens';
import { useGame } from '../../store/gameStore';
import { now } from '../../store/game';
import { evidenceUrl, removeEvidence, useEvidence } from '../../store/actions/evidence';
import { minimize, submitQuest, useExec } from '../../store/actions/exec';
import { setUi, useUi } from '../../store/uiStore';
import { Btn, Tap } from '../kit/Btn';
import { Core } from '../kit/Core';
import { Typewriter } from '../kit/Typewriter';
import { useReveal } from '../hooks/useReveal';

function Slot({ id, status, onRemove }: { id: string; status: string; onRemove: () => void }) {
  const [url, setUrl] = useState<string | null>(null);
  const checking = useEvidence((s) => s.checking.includes(id));
  useEffect(() => {
    let alive = true;
    void evidenceUrl(id).then((u) => alive && setUrl(u));
    return () => {
      alive = false;
    };
  }, [id]);
  const badge = status === 'verified' ? '✓' : status === 'unsure' ? '存疑' : '未校验';
  return (
    <button
      type="button"
      className={`evi-slot has ${checking ? 'checking' : ''}`}
      onClick={onRemove}
      aria-label="撤掉这张证据"
    >
      {url && <img src={url} alt="证据" />}
      <i className={`evi-badge ${status}`}>{checking ? '校验中' : badge}</i>
    </button>
  );
}

export function Exec() {
  const ref = useRef<HTMLElement>(null);
  const a = useGame((s) => s.game.active);
  const watch = useUi((s) => s.watchLine);
  const watchAt = useUi((s) => s.watchAt);
  const waiting = useEvidence((s) => s.waiting);
  const picking = useEvidence((s) => s.picking);
  const rejectNote = useEvidence((s) => s.rejectNote);
  const settling = useExec((s) => s.settling);
  const [t, setT] = useState(now());
  useReveal(ref);
  useEffect(() => {
    const id = setInterval(() => setT(now()), 1000);
    return () => clearInterval(id);
  }, []);
  if (!a) return <section className="scene on" />;
  const shownWatch = watch && t - watchAt < 3800 ? watch : '正在看着你';
  const q = a.task;
  const busy = waiting || settling;
  return (
    <section
      className="scene on"
      id="sc-exec"
      ref={ref}
      style={{ ['--gc' as string]: RANK_COLORS[q.rank] }}
    >
      <div className="ex-h rv">
        <span className="gbadge">{q.rank}</span>
        <span className="rec">
          <i />
          执行中
        </span>
        <span>·</span>
        <span className="ex-code">{questCode(q)}</span>
      </div>
      <h1 className="h1 ex-t rv">{q.name}</h1>
      <div className="checkin-box rv">
        <b>{timeLabel(q)} · 不计时</b>
        <span>
          接单 {fmtDur(Math.max(0, t - a.startAt))} 了。做完随时交 ——
          先留快照记录，再点【提交任务】。
        </span>
      </div>
      <div className="watch rv">
        <Core className="core-watch" mood={busy ? 'scan' : ''} />
        <b>SYSTEM</b>
        <Typewriter as="em" text={shownWatch} />
      </div>
      <div className="evi rv">
        <div className="evi-h">
          快照记录 · <b>{q.proof}</b>
        </div>
        <div className="evi-row">
          {a.evidence.map((e) => (
            <Slot key={e.id} id={e.id} status={e.status} onRemove={() => removeEvidence(e.id)} />
          ))}
          {a.evidence.length < 3 && (
            <Tap
              className="evi-slot"
              aria-label="上传证据"
              disabled={picking || busy}
              onClick={() => setUi({ sheet: 'evidence' })}
            >
              {picking ? '…' : '+'}
            </Tap>
          )}
        </div>
        <p className="evi-tip">
          {a.evidence.length
            ? '点缩略图可以撤掉。最多 3 张。'
            : '拍一张或从相册选。没有证据，她不认账。'}
        </p>
        {rejectNote && <p className="evi-reject">上一张被拒：{rejectNote}</p>}
      </div>
      <div className="ex-sp" />
      <div className="ex-act rv" style={{ position: 'relative', zIndex: 7 }}>
        <div className="row">
          <Btn kind="pri" grow disabled={busy} onClick={() => void submitQuest()}>
            {waiting ? '她在验证据…' : settling ? '结算中…' : '提交任务'}
          </Btn>
        </div>
        <div className="row2">
          <Tap className="link" disabled={busy} onClick={minimize}>
            收起 ▾
          </Tap>
        </div>
      </div>
    </section>
  );
}
