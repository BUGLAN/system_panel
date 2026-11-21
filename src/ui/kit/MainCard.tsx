/**
 * 主线收藏卡（参考稿 MAINLINE · COLLECTIBLE CARDS v2）：正面 = 题面；
 * 已完成翻面 = 战报（评级 / 用时 / 完成于）；未解封翻面 = 封印 + 情报。
 * 插图按题面泛化：计时单画表盘、带距离画路线、兑现单画终局光芒（不画具体运动器材）。
 */
import { attrName } from '../../core/data/attrs';
import type { PlanTask } from '../../core/model/goal';
import { payout } from '../../core/data/rewards';
import { fmtDur, pad2 } from '../../core/format';
import { GRADE_COLORS, RANK_PIPS } from '../../design/tokens';
import { IconLock } from './icons';

export type CardState = 'done' | 'cur' | 'lock';

const REC_Q: Record<string, [string, string]> = {
  S: ['……我无话可说。这次算你狠。', '暴击收场。别得意，我只是记下了。'],
  A: ['达标。我记下了，别指望我夸你。', '节奏稳定。勉强像个宿主了。'],
  B: ['及格线上蹭过去的。我看见了。', '下次别让我等这么久。'],
  C: ['到此一游式完成。我很宽容。', '这也算？……算吧。'],
};

function Art({ t }: { t: PlanTask }) {
  const km = /(\d+(?:\.\d+)?)\s*(公里|km|KM)/.exec(t.title)?.[1];
  const kind = t.finalTask ? 'boss' : km ? 'route' : 'clock';
  let bg: React.ReactNode;
  let lab: string;
  let big: React.ReactNode;
  if (kind === 'clock') {
    const f = Math.min(1, t.minutes / 60);
    const C = 2 * Math.PI * 58;
    bg = (
      <>
        <circle cx="120" cy="80" r="58" fill="none" stroke="currentColor" strokeWidth="1" opacity=".18" />
        <circle
          cx="120"
          cy="80"
          r="58"
          fill="none"
          stroke="currentColor"
          strokeWidth="3"
          strokeLinecap="round"
          strokeDasharray={`${C * f} ${C}`}
          transform="rotate(-90 120 80)"
          opacity=".75"
        />
        {Array.from({ length: 12 }, (_, k) => {
          const a = (k / 12) * Math.PI * 2;
          return (
            <path
              key={k}
              d={`M${120 + Math.sin(a) * 48} ${80 - Math.cos(a) * 48}L${120 + Math.sin(a) * 53} ${80 - Math.cos(a) * 53}`}
              stroke="currentColor"
              strokeWidth="1.4"
              opacity=".5"
            />
          );
        })}
        <g className="pulse">
          <circle cx="120" cy="80" r="6" fill="currentColor" />
        </g>
      </>
    );
    lab = t.timed ? 'TIME TRIAL' : 'CHECK-IN';
    big = t.timed ? (
      <>
        {t.minutes}
        <small>MIN</small>
      </>
    ) : (
      <small>打卡</small>
    );
  } else if (kind === 'route') {
    bg = (
      <>
        <path className="dash" d="M22 44C60 10 84 70 120 40S182 18 218 36" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" />
        <circle cx="22" cy="44" r="4" fill="currentColor" />
        <g className="pulse">
          <circle cx="218" cy="36" r="6" fill="none" stroke="#fff" strokeWidth="1.5" />
        </g>
        <circle cx="218" cy="36" r="3" fill="#fff" />
        <path className="dash" d="M14 132H226" stroke="currentColor" strokeWidth="1.5" opacity=".6" />
      </>
    );
    lab = 'ROUTE';
    big = (
      <>
        {km}
        <small>KM</small>
      </>
    );
  } else {
    bg = (
      <>
        {Array.from({ length: 14 }, (_, k) => {
          const a = (k / 14) * Math.PI * 2;
          return (
            <path
              key={k}
              d={`M${120 + Math.cos(a) * 40} ${70 + Math.sin(a) * 40}L${120 + Math.cos(a) * 120} ${70 + Math.sin(a) * 120}`}
              stroke="currentColor"
              strokeWidth="1"
              opacity=".22"
            />
          );
        })}
        <g className="pulse">
          <path d="M98 82l8-18 14 12 14-12 8 18z" fill="currentColor" />
        </g>
      </>
    );
    lab = 'FINAL · 兑现';
    big = (
      <>
        {t.minutes}
        <small>MIN</small>
      </>
    );
  }
  return (
    <div className="tc-art">
      <div className="wm">{t.rank}</div>
      <span className="kind">{lab}</span>
      {big && <span className="big">{big}</span>}
      <svg viewBox="0 0 240 150" preserveAspectRatio="xMidYMid meet">
        {bg}
      </svg>
    </div>
  );
}

const Frame = () => (
  <div className="tc-frame">
    <i />
    <i />
    <i />
    <i />
  </div>
);

export function MainCard({
  t,
  total,
  state,
  executing,
  catChar,
}: {
  t: PlanTask;
  total: number;
  state: CardState;
  executing: boolean;
  catChar: string;
}) {
  const pips = RANK_PIPS[t.rank];
  const attr = Object.entries(t.attrs)[0];
  const p = payout({ rank: t.rank, crit: false, dbl: false });
  const g = t.grade ?? 'B';
  const foot =
    state === 'cur' ? (
      <>
        <span className="tri" />
        {executing ? '执行中 · 点击返回' : '当前目标 · 点击接取'}
      </>
    ) : state === 'done' ? (
      <>
        评级 <b>{g}</b> · 点击翻看战报 ⟲
      </>
    ) : (
      <>
        <IconLock />
        完成上一单解锁
      </>
    );
  return (
    <div className="deal">
      <div className="tc">
        <div className="tc-face tc-front">
          {t.finalTask && <div className="bossl">FINAL</div>}
          <div className="tc-head">
            <span>MAIN</span>
            <b>{pad2(t.index + 1)}</b>
            <span className="of">/{total}</span>
            <span className="tc-rar">
              {Array.from({ length: 5 }, (_, k) => (
                <s key={k} className={k < pips ? '' : 'o'} />
              ))}
            </span>
            <span className="tc-cat">
              <span>{catChar}</span>
            </span>
          </div>
          <Art t={t} />
          <div className="tc-mid">
            <div className="tc-medal">
              <span>
                <b>{t.rank}</b>
              </span>
            </div>
            <div className="tc-meta">
              <span>
                <i>⏱</i>
                {t.timed ? `${t.minutes} 分钟` : '打卡'}
              </span>
              <span>
                <i>EV</i>
                {t.proof}
              </span>
            </div>
          </div>
          <div className="tc-t">{t.title}</div>
          <div className="tc-stats">
            <div>
              <small>经验 EXP</small>
              <span className="x">+{p.exp}</span>
            </div>
            <div>
              <small>晶核</small>
              <span className="c">{p.coin}</span>
            </div>
            <div>
              <small>{attr ? attrName(attr[0]) : '六维'}</small>
              <span className="a">+{attr?.[1] ?? 0}</span>
            </div>
          </div>
          <div className="tc-foot">{foot}</div>
          {state === 'done' && (
            <div className="stamp">
              已完成<small>CLEAR</small>
            </div>
          )}
          <div className="tc-holo" />
          <div className="tc-glare" />
          <Frame />
        </div>
        {state === 'done' ? (
          <div className="tc-face tc-back tcrec" style={{ ['--rc' as string]: GRADE_COLORS[g] }}>
            <div className="rec-h">
              <span>RECORD · 战报</span>
              <span>MAIN {pad2(t.index + 1)}</span>
            </div>
            <div className="rec-r">
              {g}
              <small>验收评级 · GRADE</small>
            </div>
            <div className="rec-l">
              <div>
                用时
                <b>{t.heldMs !== null ? fmtDur(t.heldMs) : '—'}</b>
              </div>
              <div>
                目标<b>{t.timed ? `${t.minutes} 分钟` : '打卡'}</b>
              </div>
              <div>
                完成于
                <b>{t.doneAt ? new Date(t.doneAt).toLocaleDateString('zh-CN', { month: 'numeric', day: 'numeric' }) : '—'}</b>
              </div>
            </div>
            <div className="rec-q">
              <em>SYSTEM 批注</em>
              {(REC_Q[g] ?? REC_Q['B'])?.[t.index % 2]}
            </div>
            <div className="rec-f">点击翻回正面</div>
            <div className="tc-glare" />
            <Frame />
          </div>
        ) : (
          <div className="tc-face tc-back cb">
            <div className="cb-emb">
              <svg viewBox="0 0 100 100">
                <g className="r1">
                  <circle cx="50" cy="50" r="46" fill="none" stroke="currentColor" strokeWidth="1.5" strokeDasharray="18 7" />
                </g>
                <g className="r2">
                  <circle cx="50" cy="50" r="37" fill="none" stroke="currentColor" strokeWidth="1" strokeDasharray="3 5" opacity=".7" />
                </g>
                <path d="M18 50Q50 22 82 50Q50 78 18 50Z" fill="none" stroke="#fff" strokeWidth="2" />
                <circle cx="50" cy="50" r="10" fill="currentColor" />
                <circle cx="54" cy="46" r="3" fill="#fff" />
              </svg>
            </div>
            <div className="cb-t">
              HOST <em>//</em> SYSTEM
            </div>
            <div className="cb-s">
              MAIN {pad2(t.index + 1)} · {t.finalTask ? 'FINAL ' : ''}SEALED
            </div>
            <div className="cb-intel">
              <small>
                情报 · {t.rank} 级 · {attr ? attrName(attr[0]) : ''}
              </small>
              <p>
                {t.title}
                <i>
                  {t.timed ? `${t.minutes} 分钟` : '打卡'} · {t.proof}
                </i>
              </p>
            </div>
            <div className="cb-l">
              <IconLock />
              完成上一单解封
            </div>
            <div className="tc-holo" />
            <div className="tc-glare" />
            <Frame />
          </div>
        )}
      </div>
    </div>
  );
}
