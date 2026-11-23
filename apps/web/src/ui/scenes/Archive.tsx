/**
 * 档案（参考稿 #sc-archive）：资料（等级 / 累计 EXP / 连胜 / 完成单）、7 天战报、最近流水。
 */
import { useEffect, useRef, useState } from 'react';
import { summarizeWeek } from '@host/core/flow/history';
import { useGame } from '../../store/gameStore';
import { historyAll, now, tz } from '../../store/game';
import { back } from '../../store/actions/nav';
import type { HistoryEntry } from '@host/core/flow/types';
import { Tap } from '../kit/Btn';
import { IconBack } from '../kit/icons';
import { useReveal } from '../hooks/useReveal';

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
  const wk = summarizeWeek(hist, now(), tz());
  const maxBar = Math.max(3, ...wk.dayDone);
  const days = '日一二三四五六';
  return (
    <section className="scene nohud on" id="sc-archive" ref={ref}>
      <div className="sh rv">
        <div>
          <div className="eyebrow">ARCHIVE · 宿主档案</div>
          <h1 className="h1">档案</h1>
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
