/**
 * 委托板（参考稿 #sc-board）：全部 / 主线 / 补救 / 日常；票券错峰进场。
 *  - 主线只能接清单里第一张没做完的，后面的压暗、右侧竖排「锁定」（E1.3）
 *  - 全部清空才庆祝 CLEAR!；筛选栏空了只说「这一栏今天没有单」（A3）
 *  - 没目标时说「还没有目标，哪来的单」（A2）；记着目标时指向「重试拆解」（C5）
 */
import { useLayoutEffect, useRef } from 'react';
import { attrsText, kindLabel, lootText, questCode, timeLabel } from '@host/core/flow/questText';
import { flowOf } from '../../store/game';
import type { Quest } from '@host/core/model/quest';
import { RANK_COLORS } from '../../design/tokens';
import { sfx } from '../../audio/sfx';
import { useGame } from '../../store/gameStore';
import { back, go } from '../../store/actions/nav';
import { openBriefing } from '../../store/actions/exec';
import { refillDailies } from '../../store/actions/goals';
import { setUi, useUi, type UiState } from '../../store/uiStore';
import { Btn, Tap } from '../kit/Btn';
import { IconBack } from '../kit/icons';
import { useReveal } from '../hooks/useReveal';

type Filter = UiState['boardFilter'];
const TABS: Array<[Filter, string]> = [
  ['all', '全部'],
  ['main', '主线'],
  ['remedy', '补救'],
  ['daily', '日常'],
];

function Ticket({ q, locked, i }: { q: Quest; locked: boolean; i: number }) {
  const label =
    q.kind === 'main'
      ? '主线'
      : q.kind === 'remedy'
        ? q.planIndex >= 0
          ? `补救 · 主线 ${String(q.planIndex + 1).padStart(2, '0')}`
          : '补救'
        : '日常';
  const at = attrsText(q.attrs);
  return (
    <div
      className={`ticket sr in ${locked ? 'locked' : ''}`}
      style={{
        ['--gc' as string]: RANK_COLORS[q.rank],
        animationDelay: `${Math.min(i, 6) * 80}ms`,
      }}
      onClick={() => {
        if (!locked) sfx.play('soft');
        openBriefing(q);
      }}
    >
      <div className="tk-g">
        <b>{q.rank}</b>
        <small>{questCode(q)}</small>
      </div>
      <div className="tk-b">
        <span className={`tk-k ${q.kind === 'main' ? 'main' : ''}`}>{label}</span>
        <div className="tk-t">{q.name}</div>
        <div className="tk-m">
          {kindLabel(q)} · {timeLabel(q)} · {q.proof}
        </div>
        <div className="tk-r">
          <span>{lootText(q)}</span>
          {at && <span>{at}</span>}
        </div>
      </div>
      <div className="tk-go">{locked ? '锁 定' : '接 单'}</div>
    </div>
  );
}

export function Board() {
  const ref = useRef<HTMLElement>(null);
  const tabs = useRef<HTMLDivElement>(null);
  const g = useGame((s) => s.game);
  const filter = useUi((s) => s.boardFilter);
  useReveal(ref);
  useLayoutEffect(() => {
    const host = tabs.current;
    const b = host?.querySelector<HTMLButtonElement>(`button[data-f="${filter}"]`);
    const ind = host?.querySelector<HTMLElement>('.ind');
    if (b && ind) {
      ind.style.width = `${b.offsetWidth}px`;
      ind.style.transform = `translateX(${b.offsetLeft - 4}px)`;
    }
  }, [filter]);
  const f = flowOf(g);
  const all = g.queue;
  const shown = all.filter((q) => filter === 'all' || q.kind === filter);
  const noGoal = g.goal.plan.length === 0;
  return (
    <section className="scene on" id="sc-board" ref={ref}>
      <div className="sh rv">
        <div>
          <div className="eyebrow">BOARD · 委托板</div>
          <h1 className="h1">今天，接哪一单？</h1>
        </div>
        <Tap className="xbtn" aria-label="返回" onClick={back}>
          <IconBack />
        </Tap>
      </div>
      <div className="tabs rv" ref={tabs}>
        <i className="ind" />
        {TABS.map(([k, l]) => (
          <button
            key={k}
            type="button"
            data-f={k}
            className={filter === k ? 'on' : ''}
            onClick={() => {
              if (filter === k) return;
              sfx.play('soft');
              setUi({ boardFilter: k });
            }}
          >
            {l}
          </button>
        ))}
      </div>
      <div className="list">
        {g.active && (
          <div className="board-active" onClick={() => void go('exec')}>
            执行中：{g.active.task.name} · 点我回去 ›
          </div>
        )}
        {shown.map((q, i) => (
          <Ticket key={q.serial} q={q} i={i} locked={f.isMainLocked(q)} />
        ))}
        {shown.length === 0 && all.length > 0 && (
          <div className="empty gray">
            <b>EMPTY</b>这一栏今天没有单。去「全部」看看。
          </div>
        )}
        {all.length === 0 && (
          <>
            <div className="empty">
              {noGoal && !g.pendingGoal ? (
                <>
                  <b>NO GOAL</b>还没有目标，哪来的单。先去主线立一个。
                </>
              ) : (
                <>
                  <b>CLEAR!</b>今日委托清空。
                  <br />
                  她勉强承认：你今天不算太废。
                </>
              )}
            </div>
            <div style={{ textAlign: 'center' }}>
              {noGoal && g.pendingGoal ? (
                <Btn kind="ghost" sm onClick={() => void go('home')}>
                  回大厅重试拆解
                </Btn>
              ) : noGoal ? (
                <Btn kind="ghost" sm onClick={() => void go('main')}>
                  去立目标
                </Btn>
              ) : (
                <Btn kind="ghost" sm onClick={() => void refillDailies()}>
                  再要一批委托
                </Btn>
              )}
            </div>
          </>
        )}
      </div>
    </section>
  );
}
