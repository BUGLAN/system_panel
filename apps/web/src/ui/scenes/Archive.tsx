/**
 * 档案（参考稿 #sc-archive）：资料（等级 / 累计 EXP / 连胜 / 完成单）、六维雷达、
 * 名牒册（点击佩戴；「口头巨人」摘不掉）、7 天战报、六维条。
 */
import { useEffect, useRef, useState } from 'react';
import { ATTRS } from '@host/core/data/attrs';
import { TITLES } from '@host/core/data/titles';
import { summarizeWeek } from '@host/core/flow/history';
import { pad2 } from '@host/core/format';
import { sfx } from '../../audio/sfx';
import { useGame } from '../../store/gameStore';
import { historyAll, now, tz } from '../../store/game';
import { back } from '../../store/actions/nav';
import { wearTitle } from '../../store/actions/goals';
import { toast } from '../../store/uiStore';
import type { HistoryEntry } from '@host/core/flow/types';
import { Tap } from '../kit/Btn';
import { IconBack } from '../kit/icons';
import { useReveal } from '../hooks/useReveal';
import { reducedMotion } from '../fx/fx';

function Radar({ vals, max }: { vals: number[]; max: number }) {
  const cx = 150;
  const cy = 135;
  const R = 92;
  const pt = (i: number, r: number): [number, number] => {
    const a = ((-90 + i * 60) * Math.PI) / 180;
    return [cx + Math.cos(a) * r, cy + Math.sin(a) * r];
  };
  const [k, setK] = useState(reducedMotion() ? 1 : 0);
  useEffect(() => {
    if (reducedMotion()) return;
    const t0 = performance.now() + 250;
    const c1 = 1.70158;
    const c3 = c1 + 1;
    let raf = 0;
    const step = (t: number) => {
      const x = Math.min(1, Math.max(0, (t - t0) / 1200));
      const e = x === 0 ? 0 : 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2);
      setK(e);
      if (x < 1) raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  }, []);
  const pts = vals.map((v, i) => pt(i, Math.max(0.05, Math.min(1, v / max)) * R * k));
  return (
    <svg viewBox="0 0 300 270">
      <defs>
        <radialGradient id="rg">
          <stop offset="0" stopColor="#8f6bff" stopOpacity=".6" />
          <stop offset="1" stopColor="#3be8ff" stopOpacity=".25" />
        </radialGradient>
        <linearGradient id="swg" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#8f6bff" stopOpacity="0" />
          <stop offset="1" stopColor="#8f6bff" stopOpacity=".45" />
        </linearGradient>
      </defs>
      {[1, 2, 3, 4, 5].map((l) => (
        <polygon
          key={l}
          points={[0, 1, 2, 3, 4, 5].map((i) => pt(i, (R * l) / 5).join(',')).join(' ')}
          fill={l % 2 ? 'rgba(143,107,255,.045)' : 'none'}
          stroke={`rgba(143,107,255,${l === 5 ? 0.55 : 0.18})`}
          strokeWidth={l === 5 ? 1.5 : 1}
        />
      ))}
      {[0, 1, 2, 3, 4, 5].map((i) => {
        const [x, y] = pt(i, R);
        return <line key={i} x1={cx} y1={cy} x2={x} y2={y} stroke="rgba(143,107,255,.22)" />;
      })}
      <g className="sweep">
        <path
          d={`M${cx} ${cy} L${cx} ${cy - R} A${R} ${R} 0 0 1 ${pt(1, R).join(' ')} Z`}
          fill="url(#swg)"
        />
      </g>
      <polygon
        points={pts.map((p) => p.join(',')).join(' ')}
        fill="url(#rg)"
        stroke="#3be8ff"
        strokeWidth="2"
        strokeLinejoin="round"
        style={{ filter: 'drop-shadow(0 0 8px #3be8ff)' }}
      />
      {ATTRS.map((a, i) => {
        const [x, y] = pt(i, R + 28);
        const [dx, dy] = pts[i] ?? [cx, cy];
        return (
          <g key={a.k}>
            <circle
              r="4.5"
              cx={dx}
              cy={dy}
              fill="#fff"
              style={{ filter: 'drop-shadow(0 0 5px #3be8ff)' }}
            />
            <text className="lbl" x={x} y={y - 3} textAnchor="middle">
              {a.name}
            </text>
            <text className="val" x={x} y={y + 15} textAnchor="middle">
              {Math.round((vals[i] ?? 0) * Math.min(1, k * 1.4))}
            </text>
          </g>
        );
      })}
    </svg>
  );
}

export function Archive() {
  const ref = useRef<HTMLElement>(null);
  const host = useGame((s) => s.game.host);
  const [hist, setHist] = useState<HistoryEntry[]>([]);
  const [grow, setGrow] = useState(false);
  useReveal(ref);
  useEffect(() => {
    void historyAll().then(setHist);
    const t = setTimeout(() => setGrow(true), 400);
    return () => clearTimeout(t);
  }, []);
  const vals = ATTRS.map((a) => host.attrs[a.k] ?? 0);
  const max = Math.max(10, ...vals);
  const wk = summarizeWeek(hist, now(), tz());
  const maxBar = Math.max(3, ...wk.dayDone);
  const days = '日一二三四五六';
  const owned = host.ownedTitles.length;
  return (
    <section className="scene nohud on" id="sc-archive" ref={ref}>
      <div className="sh rv">
        <div>
          <div className="eyebrow">ARCHIVE · 宿主档案</div>
          <h1 className="h1">档案</h1>
        </div>
        <div className="cnt">
          {pad2(owned)} / {TITLES.length}
        </div>
        <Tap className="xbtn" aria-label="返回" onClick={back}>
          <IconBack />
        </Tap>
      </div>
      <div className="scroll">
        <div className="prof rv">
          {(
            [
              [`LV${host.lv}`, '等级'],
              [host.totalExp, '累计 EXP'],
              [host.streak, '连胜天'],
              [host.doneCount, '完成单'],
            ] as const
          ).map(([b, s]) => (
            <div key={s}>
              <b>{b}</b>
              <span>{s}</span>
            </div>
          ))}
        </div>
        <div
          className="radar rv"
          onClick={() => {
            sfx.play('soft');
            toast(`六维总和 ${vals.reduce((a, b) => a + b, 0)}。`);
          }}
        >
          <Radar vals={vals} max={max} />
        </div>
        <div className="sec-h">
          名牒册 · 点击佩戴
          <b>
            {owned}/{TITLES.length} 张
          </b>
        </div>
        <div className="plates">
          {TITLES.map((t, i) => {
            const own = host.ownedTitles.includes(t.id);
            const eq = host.title === t.id;
            return (
              <div className="pw" key={t.id}>
                <i className="pin" />
                <i className="str" />
                <div
                  className={`plate ${own ? 'own' : 'lock'} ${eq ? 'eq' : ''} ${t.shame ? 'shame' : ''}`}
                  onClick={(e) => {
                    if (!own) {
                      sfx.play('error');
                      e.currentTarget.animate(
                        [
                          { transform: 'rotate(0)' },
                          { transform: 'rotate(7deg)' },
                          { transform: 'rotate(-5deg)' },
                          { transform: 'rotate(0)' },
                        ],
                        { duration: 700, easing: 'ease-out' },
                      );
                      toast(`未解锁 · ${t.hint}`, 'err');
                      return;
                    }
                    void wearTitle(t.id);
                  }}
                >
                  <span className="gl" />
                  <span className="no">{pad2(i + 1)}</span>
                  {!own && <span className="q">?</span>}
                  <div className="nm">{own ? t.name : '？？？'}</div>
                  <div className="ht">{t.hint}</div>
                  <div className="ln" />
                  <div className="st">
                    <span>
                      {eq ? '已佩戴' : own ? (t.shame ? '摘不掉' : '点击佩戴') : '未解锁'}
                    </span>
                    <span>{eq ? '●' : ''}</span>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
        <div className="sec-h">数据 · 最近 7 天</div>
        <div className="weekc">
          <div className="bars">
            {wk.dayDone.map((v, i) => {
              const d = new Date(now() - (6 - i) * 86_400_000);
              return (
                <div key={i} className={i === 6 ? 'today' : ''}>
                  <b className="v">{v}</b>
                  <i style={{ ['--h' as string]: grow ? Math.max(0.04, v / maxBar) : 0 }} />
                  <span>{i === 6 ? '今天' : `周${days[d.getDay()]}`}</span>
                </div>
              );
            })}
          </div>
          <div className="wstats">
            {(
              [
                [`${wk.doneCount} 单`, '7 天完成'],
                [`+${wk.totalExp}`, '7 天 EXP'],
                [`${host.critCount} 次`, '累计暴击'],
                [`${host.bestStreak} 天`, '最长连胜'],
              ] as const
            ).map(([b, s]) => (
              <div key={s}>
                <b>{b}</b>
                <span>{s}</span>
              </div>
            ))}
          </div>
        </div>
        <div className="sec-h">六维 · 当前数值</div>
        <div className="weekc">
          <div className="attrs" style={{ marginTop: 0 }}>
            {ATTRS.map((a, i) => (
              <div className="a" key={a.k}>
                <span>{a.name}</span>
                <div className="tr">
                  <i style={{ ['--w' as string]: grow ? Math.min(1, (vals[i] ?? 0) / max) : 0 }} />
                </div>
                <b>{vals[i]}</b>
              </div>
            ))}
          </div>
        </div>
        {wk.recent.length > 0 && (
          <>
            <div className="sec-h">流水 · 最近 8 条</div>
            <div className="weekc recent">
              {wk.recent.map((e) => (
                <div key={`${e.at}-${e.name}`} className={`rc ${e.result}`}>
                  <span>{e.result === 'clear' ? '✓' : e.result === 'timeout' ? '⏱' : '×'}</span>
                  <b>{e.name}</b>
                  <em>
                    {e.result === 'clear' ? `+${e.exp}` : e.result === 'timeout' ? '超时' : '认输'}
                  </em>
                </div>
              ))}
            </div>
          </>
        )}
      </div>
    </section>
  );
}
