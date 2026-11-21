/**
 * 执行面板（参考稿 #sc-exec）：计时单倒计时 + 进度条 / 打卡单「做完随时交」；
 * 快照记录（≤3 张，后台校验，拒收留痕）、道具托盘、【提交任务】、认输（按住）、收起。
 */
import { useEffect, useRef, useState } from 'react';
import { EXEC_ITEM_IDS, itemById } from '@host/core/data/items';
import { critChance } from '@host/core/data/rewards';
import { fmtClock } from '@host/core/format';
import { questCode } from '@host/core/flow/questText';
import { deadlineOf } from '@host/core/flow/settle';
import { RANK_COLORS } from '../../design/tokens';
import { useGame } from '../../store/gameStore';
import { now } from '../../store/game';
import { evidenceUrl, removeEvidence, useEvidence } from '../../store/actions/evidence';
import { equipItem, giveUp, minimize, submitQuest, useExec } from '../../store/actions/exec';
import { sayWatch, setUi, useUi } from '../../store/uiStore';
import { Btn, Tap } from '../kit/Btn';
import { Core } from '../kit/Core';
import { HoldButton } from '../kit/HoldButton';
import { ItemIcon } from '../kit/icons';
import { Typewriter } from '../kit/Typewriter';
import { useReveal } from '../hooks/useReveal';

const MILESTONES: Array<[number, string]> = [
  [0.25, '四分之一。我还以为你会在第 [3] 分钟放弃。'],
  [0.5, '过半了。腿酸是正常的，[意志]也会酸。'],
  [0.75, '最后四分之一。别在这时候想晚饭。'],
  [1, '[达标]！现在提交，她挑不出毛病。'],
];

function Digits({ text }: { text: string }) {
  return (
    <div className="digits">
      {[...text].map((c, i) => (
        <span key={`${i}-${c}`} className={c === ':' ? 'colon' : 'dg'}>
          {c}
        </span>
      ))}
    </div>
  );
}

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

function Tray({ open, onClose }: { open: boolean; onClose: () => void }) {
  const a = useGame((s) => s.game.active);
  const items = useGame((s) => s.game.host.items);
  return (
    <div className={`tray ${open ? 'open' : ''}`}>
      <div className="tback" onClick={onClose} />
      <div className="tlabel">LOADOUT · 选择装载道具</div>
      <div>
        {EXEC_ITEM_IDS.map((id, i) => {
          const it = itemById(id);
          if (!it) return null;
          const eq = !!a?.[id];
          const broken = id === 'shield' && (a?.extraMs ?? 0) > 0;
          const off = id === 'shield' && a && !a.task.timed;
          return (
            <div
              key={id}
              className={`icard ${eq ? 'eq' : ''} ${off || broken ? 'off' : ''}`}
              style={{
                ['--gc' as string]: it.color,
                ['--tx' as string]: `${(i - 1) * 118}px`,
                ['--rot' as string]: `${(i - 1) * 9}deg`,
                ['--ty' as string]: `${Math.abs(i - 1) * 16}px`,
              }}
              onClick={() => !eq && equipItem(id)}
            >
              <div className="ih">
                {it.code}
                <span>×{items[id] ?? 0}</span>
              </div>
              <div className="ii">
                <ItemIcon id={id} />
              </div>
              <b>{it.name}</b>
              <p>{it.desc.split('。')[0]}。</p>
              <div className="eqt">
                {eq
                  ? '✓ 已装载'
                  : broken
                    ? '已碎'
                    : off
                      ? '打卡单用不上'
                      : (items[id] ?? 0) > 0
                        ? '点击装载'
                        : '持有 ×0'}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

export function Exec() {
  const ref = useRef<HTMLElement>(null);
  const a = useGame((s) => s.game.active);
  const streak = useGame((s) => s.game.host.streak);
  const watch = useUi((s) => s.watchLine);
  const watchAt = useUi((s) => s.watchAt);
  const waiting = useEvidence((s) => s.waiting);
  const picking = useEvidence((s) => s.picking);
  const rejectNote = useEvidence((s) => s.rejectNote);
  const settling = useExec((s) => s.settling);
  const [t, setT] = useState(now());
  const [tray, setTray] = useState(false);
  const hit = useRef(new Set<number>());
  useReveal(ref);
  useEffect(() => {
    const id = setInterval(() => setT(now()), 250);
    return () => clearInterval(id);
  }, []);
  const quarter = a?.task.timed
    ? Math.floor(((t - a.startAt) / Math.max(1, a.task.minutes * 60_000)) * 4)
    : -1;
  useEffect(() => {
    if (quarter < 1) return;
    const m = MILESTONES[Math.min(3, quarter - 1)];
    if (m && !hit.current.has(m[0])) {
      hit.current.add(m[0]);
      sayWatch(m[1]);
    }
  }, [quarter]);
  if (!a) return <section className="scene on" />;
  const shownWatch = watch && t - watchAt < 3800 ? watch : '正在看着你';
  const q = a.task;
  const elapsed = Math.max(0, t - a.startAt);
  const limitMs = q.minutes * 60_000 + a.extraMs;
  const p = q.timed ? elapsed / Math.max(1, q.minutes * 60_000) : 0;
  const left = Math.max(0, deadlineOf(a) - t);
  const counts = {
    verified: a.evidence.filter((e) => e.status === 'verified').length,
    unverified: a.evidence.filter((e) => e.status === 'unverified').length,
    unsure: a.evidence.filter((e) => e.status === 'unsure').length,
  };
  const chance = critChance({ ...counts, streak, critItem: a.crit });
  const equipped = (a.dbl ? 1 : 0) + (a.crit ? 1 : 0) + (a.shield ? 1 : 0);
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
      {q.timed ? (
        <>
          <div className={`timer rv ${p >= 1 ? 'hit' : ''}`}>
            <Digits text={fmtClock(elapsed)} />
            {a.extraMs > 0 && <small>护盾顺延</small>}
          </div>
          <div className="rv">
            <div className="tbar" style={{ ['--p' as string]: Math.min(1, elapsed / limitMs) }}>
              <div className="ticks">
                <i />
                <i />
                <i />
                <i />
                <i />
              </div>
              <div className="fill" />
              <div className="knob" />
            </div>
            <div className="tmeta">
              <span>{Math.floor(Math.min(p, 9.99) * 100)}%</span>
              <span>
                目标 {fmtClock(q.minutes * 60_000)} · 剩 {fmtClock(left)}
              </span>
            </div>
          </div>
        </>
      ) : (
        <div className="checkin-box rv">
          <b>打卡 · 不计时</b>
          <span>做完随时交 —— 先留快照记录，再点【提交任务】。</span>
        </div>
      )}
      <div className="watch rv">
        <Core className="core-watch" mood={busy ? 'scan' : ''} />
        <b>SYSTEM</b>
        <Typewriter as="em" text={shownWatch} />
      </div>
      <div className="evi rv">
        <div className="evi-h">
          快照记录 · <b>{q.proof}</b>
          <span className="evi-crit">暴击率 {Math.round(chance * 100)}%</span>
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
            ? '点缩略图可以撤掉。证据越多，暴击率越高。'
            : '拍一张或从相册选。没有证据，她不认账。'}
        </p>
        {rejectNote && <p className="evi-reject">上一张被拒：{rejectNote}</p>}
      </div>
      <div className="ex-sp" />
      <Tray open={tray} onClose={() => setTray(false)} />
      <div className="ex-act rv" style={{ position: 'relative', zIndex: 7 }}>
        <div className="row">
          <Btn kind="ghost" sm disabled={busy} onClick={() => setTray((v) => !v)}>
            道具 <i className={`eqn ${equipped ? 'on' : ''}`}>{equipped}</i>
          </Btn>
          <Btn
            kind="pri"
            grow
            disabled={busy}
            onClick={() => {
              setTray(false);
              void submitQuest();
            }}
          >
            {waiting ? '她在验证据…' : settling ? '结算中…' : '提交任务'}
          </Btn>
        </div>
        <div className="row2">
          <HoldButton label="认输（按住）" disabled={busy} onDone={() => void giveUp()} />
          <Tap className="link" disabled={busy} onClick={minimize}>
            收起 ▾
          </Tap>
        </div>
      </div>
    </section>
  );
}
