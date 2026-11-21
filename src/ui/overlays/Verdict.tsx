/**
 * 结算演出（参考稿 #verdict）：按 core/flow/settleTimeline 的时间轴走，总时长 ≤1.6s。
 * 扫描 → 评级印章（亮帧 + 音效踩这一帧）→ 奖励行 count-up（800ms ease-out cubic；
 * 暴击：滚到暴击前 → 定格 200ms → CRIT 印章 2.2→1 → 续滚翻倍）→ 经验条（不跨级 520ms /
 * 跨级 360 涨满 → 白闪 → 420 涨到余额）→「收下」。减弱动态效果时直接落到终态。
 */
import { useEffect, useRef, useState } from 'react';
import { attrName } from '../../core/data/attrs';
import { buildSettleTimeline } from '../../core/flow/settleTimeline';
import type { QuestResult } from '../../core/flow/types';
import { questCode } from '../../core/flow/questText';
import { EASE, GRADE_COLORS, MOTION, easeOutCubic } from '../../design/tokens';
import { sfx } from '../../audio/sfx';
import { closeVerdict } from '../../store/actions/exec';
import type { PlanFailure } from '../../core/goal/planFailure';
import { Btn } from '../kit/Btn';
import { Core } from '../kit/Core';
import { Typewriter } from '../kit/Typewriter';
import { burst, center, flash, reducedMotion, ring, shake } from '../fx/fx';
import { haptic } from '../haptics';

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

function roll(el: HTMLElement | null, from: number, to: number, ms: number): Promise<void> {
  return new Promise((res) => {
    if (!el || ms <= 0) {
      if (el) el.textContent = `+${to}`;
      res();
      return;
    }
    const t0 = performance.now();
    const f = (t: number) => {
      const k = Math.min(1, (t - t0) / ms);
      el.textContent = `+${Math.round(from + (to - from) * easeOutCubic(k))}`;
      if (k < 1) requestAnimationFrame(f);
      else res();
    };
    requestAnimationFrame(f);
  });
}

interface Row {
  label: string;
  value: number | string;
  base?: number;
  tag?: string;
}

function rowsOf(r: QuestResult): Row[] {
  const rows: Row[] = [
    { label: 'EXP', value: r.exp, base: r.baseExp, tag: r.dbl ? '×2' : r.crit ? 'CRIT' : '' },
    { label: '晶核', value: r.coin, tag: r.crit ? 'CRIT' : '' },
  ];
  const at = Object.entries(r.attrs)
    .filter(([, v]) => (v ?? 0) > 0)
    .map(([k, v]) => `${attrName(k)} +${v}`)
    .join(' · ');
  if (at) rows.push({ label: '六维', value: at });
  if (r.streakUp) rows.push({ label: '连胜天数', value: r.streak, tag: 'TODAY' });
  return rows;
}

export function Verdict({
  result: r,
  evidenceUrl,
  line,
  followUpError,
}: {
  result: QuestResult;
  evidenceUrl: string | null;
  line: string;
  followUpError: PlanFailure | null;
}) {
  const rm = reducedMotion();
  const [phase, setPhase] = useState<'scan' | 'res'>(rm ? 'res' : 'scan');
  const [ready, setReady] = useState(rm);
  const [sub, setSub] = useState('ANALYZING EVIDENCE…');
  const [say, setSay] = useState(rm ? line : '');
  const [lvlabel, setLvlabel] = useState(`LV ${rm ? r.afterLv : r.beforeLv}`);
  const [xpr, setXpr] = useState(
    rm ? `${r.endExp} / ${r.afterNeed}` : `${r.beforeExp} / ${r.beforeNeed}`,
  );
  const prog = useRef<HTMLElement>(null);
  const rank = useRef<HTMLDivElement>(null);
  const ban = useRef<HTMLDivElement>(null);
  const bar = useRef<HTMLElement>(null);
  const rowEls = useRef<Array<HTMLElement | null>>([]);
  const critStamp = useRef<HTMLElement>(null);
  const rows = rowsOf(r);
  const levelUp = r.ups.length > 0;

  useEffect(() => {
    let alive = true;
    const tl = buildSettleTimeline({ crit: r.crit, rows: rows.length, levelUp });
    const setBar = (p: number) =>
      bar.current?.style.setProperty('--p', String(Math.max(0, Math.min(1, p))));
    if (reducedMotion()) {
      rows.forEach((row, i) => {
        const el = rowEls.current[i];
        if (el && typeof row.value === 'number') el.textContent = `+${row.value}`;
      });
      setBar(r.endExp / r.afterNeed);
      return;
    }
    void (async () => {
      // ① 扫描
      sfx.play('scan');
      const subs = ['ANALYZING EVIDENCE…', '比对历史数据…', '检测 P 图痕迹…', '计算敷衍指数…'];
      prog.current?.animate([{ transform: 'scaleX(0)' }, { transform: 'scaleX(1)' }], {
        duration: tl.scanMs,
        easing: 'cubic-bezier(.2,.9,.2,1)',
        fill: 'forwards',
      });
      for (let i = 0; i < subs.length; i++) {
        setSub(subs[i] as string);
        await sleep(tl.scanMs / subs.length);
      }
      if (!alive) return;
      setPhase('res');
      setBar(r.beforeExp / r.beforeNeed);
      await sleep(16);
      // ② 评级印章：亮帧 + 音效踩这一帧
      if (r.crit) {
        ban.current?.animate(
          [
            { transform: 'rotate(-8deg) translateX(-120%)', opacity: 1 },
            { transform: 'rotate(-8deg) translateX(0)', opacity: 1 },
          ],
          { duration: tl.rankMs, easing: 'cubic-bezier(.2,1,.3,1)', fill: 'forwards' },
        );
      }
      await rank.current?.animate(
        [
          { transform: 'scale(3.4) rotate(-12deg)', opacity: 0 },
          { transform: 'scale(.9) rotate(3deg)', opacity: 1, offset: 0.78 },
          { transform: 'scale(1) rotate(0)', opacity: 1 },
        ],
        { duration: tl.rankMs, easing: 'cubic-bezier(.55,0,.75,.2)', fill: 'backwards' },
      ).finished;
      if (!alive) return;
      flash();
      sfx.play(r.crit ? 'crit' : 'stamp');
      haptic[r.crit ? 'crit' : 'success']();
      shake(r.crit ? 12 : 7, 380);
      {
        const [x, y] = center(rank.current);
        const cols = r.crit ? ['#ff3b7a', '#ffcc4d', '#fff'] : ['#d6ff3d', '#fff', '#3be8ff'];
        burst(x, y, {
          n: r.crit ? 60 : 40,
          colors: cols,
          min: 4,
          max: r.crit ? 15 : 11,
          life: 38,
          sz: 2.5,
        });
        ring(x, y, cols[0] as string, 160, 5);
      }
      setSay(line);
      // ③ 奖励行 + 经验条（并行）
      const rowJobs = rows.map(async (row, i) => {
        await sleep(i * tl.rowStagger);
        const el = rowEls.current[i] ?? null;
        el?.parentElement?.animate(
          [
            { opacity: 0, transform: 'translateX(-40px)' },
            { opacity: 1, transform: 'none' },
          ],
          {
            duration: 300,
            easing: 'cubic-bezier(.2,1.3,.4,1)',
            fill: 'backwards',
          },
        );
        if (typeof row.value !== 'number') return;
        sfx.play('coin');
        if (i === 0 && tl.crit && row.base !== undefined) {
          await roll(el, 0, row.base, tl.crit.baseMs);
          await sleep(tl.crit.freezeMs);
          critStamp.current?.animate(
            [
              { transform: `scale(${MOTION.critStampFrom}) rotate(-12deg)`, opacity: 0 },
              { transform: 'scale(1) rotate(-12deg)', opacity: 1 },
            ],
            { duration: tl.crit.stampMs, easing: 'cubic-bezier(.6,0,.8,.4)', fill: 'forwards' },
          );
          sfx.play('stamp');
          await sleep(tl.crit.stampMs);
          await roll(el, row.base, row.value, tl.crit.restMs);
        } else {
          await roll(el, 0, row.value, tl.countMs);
        }
      });
      const barJob = (async () => {
        await sleep(tl.barAt - tl.rowsAt);
        const b = bar.current;
        if (!b) return;
        const from = r.beforeExp / r.beforeNeed;
        if (tl.bar.kind === 'same') {
          await b.animate(
            [{ transform: `scaleX(${from})` }, { transform: `scaleX(${r.endExp / r.afterNeed})` }],
            {
              duration: tl.bar.ms,
              easing: 'cubic-bezier(.2,.9,.2,1)',
              fill: 'forwards',
            },
          ).finished;
        } else {
          await b.animate([{ transform: `scaleX(${from})` }, { transform: 'scaleX(1)' }], {
            duration: tl.bar.fillMs,
            easing: 'cubic-bezier(.2,.9,.2,1)',
            fill: 'forwards',
          }).finished;
          flash();
          sfx.play('levelup');
          setLvlabel(`LV ${r.afterLv}`);
          setXpr('LEVEL UP!');
          await sleep(tl.bar.flashMs);
          await b.animate(
            [{ transform: 'scaleX(0)' }, { transform: `scaleX(${r.endExp / r.afterNeed})` }],
            {
              duration: tl.bar.refillMs,
              easing: 'cubic-bezier(.2,.9,.2,1)',
              fill: 'forwards',
            },
          ).finished;
        }
        setBar(r.endExp / r.afterNeed);
        setXpr(`${r.endExp} / ${r.afterNeed}`);
      })();
      await Promise.all([...rowJobs, barJob]);
      if (alive) setReady(true);
    })();
    return () => {
      alive = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const g = r.grade;
  return (
    <div className="ovl on" id="verdict">
      {phase === 'scan' ? (
        <div className="vd-scan on">
          <Core mood="scan" className="core-scan" />
          <div className="vd-frame">{evidenceUrl && <img src={evidenceUrl} alt="" />}</div>
          <h3>她正在验收</h3>
          <div className="sub">{sub}</div>
          <div className="vd-prog">
            <i ref={prog} />
          </div>
        </div>
      ) : (
        <div className="vd-res on">
          <div className="vtag">VERDICT · {questCode(r.quest)}</div>
          <div style={{ position: 'relative' }}>
            <div className="critban" ref={ban}>
              <span>
                CRITICAL HIT · 暴击 · CRITICAL HIT · 暴击 · CRITICAL HIT · 暴击 · CRITICAL HIT ·
                暴击 ·
              </span>
            </div>
            <div className={`rank ${g}`} ref={rank} style={{ ['--rc' as string]: GRADE_COLORS[g] }}>
              {g}
            </div>
          </div>
          <Typewriter className="vline" text={say} />
          <div className="rw">
            {rows.map((row, i) => (
              <div className="r" key={row.label}>
                <span>
                  {row.label}
                  {row.tag ? <em>{row.tag}</em> : null}
                </span>
                {typeof row.value === 'number' ? (
                  <b
                    style={{ display: 'inline-block', position: 'relative' }}
                    ref={(el) => void (rowEls.current[i] = el)}
                  >
                    +0
                  </b>
                ) : (
                  <b className="r-attr" ref={(el) => void (rowEls.current[i] = el)}>
                    {row.value}
                  </b>
                )}
                {i === 0 && r.crit && (
                  <i className="crit-stamp" ref={critStamp}>
                    CRIT
                  </i>
                )}
              </div>
            ))}
          </div>
          <div className="xpw">
            <div className="xl">
              <span>{lvlabel}</span>
              <span style={xpr === 'LEVEL UP!' ? { color: 'var(--acid)' } : undefined}>{xpr}</span>
            </div>
            <div className="xt">
              <i ref={bar} />
            </div>
          </div>
          {r.near > 0 && <p className="vd-near">差 {r.near}% 就暴击了。</p>}
          {r.tooFast && (
            <p className="vd-near">{Math.round(r.heldMs / 1000)} 秒就交了？她记下了。</p>
          )}
          {followUpError && (
            <p className="vd-err">
              这一单记上了。下一段没拆出来：{followUpError.detail.slice(0, 40)}
              ——回主线页可以重试拆解。
            </p>
          )}
          <Btn
            kind="pri"
            style={{
              visibility: ready ? 'visible' : 'hidden',
              transition: `opacity .3s cubic-bezier(${EASE.ease.join(',')})`,
            }}
            onClick={() => void closeVerdict()}
          >
            收下
          </Btn>
        </div>
      )}
    </div>
  );
}
