/**
 * 大厅（参考稿 #sc-home）：她 + 气泡、主线卡（或待拆卡 / 立目标卡）、执行中药丸、底栏、委托球。
 */
import { useEffect, useRef, useState } from 'react';
import { LINES, fillLine, pickBySeed } from '@host/core/data/lines';
import {
  goalDoneCount,
  goalFirstOpenIndex,
  goalPassedDays,
  goalTotalTasks,
  goalWindowExhausted,
} from '@host/core/model/goal';
import { fmtClock, pad2 } from '@host/core/format';
import { sfx } from '../../audio/sfx';
import { useGame } from '../../store/gameStore';
import { game, now } from '../../store/game';
import { go } from '../../store/actions/nav';
import { retryPendingPlan, resumePlan } from '../../store/actions/plan';
import { resetBind } from '../../store/actions/bind';
import { sayHome, setUi, uiStore, useUi } from '../../store/uiStore';
import { Btn, Tap } from '../kit/Btn';
import { Core, type CoreMood } from '../kit/Core';
import { Typewriter } from '../kit/Typewriter';
import { burst, center, ring, shake } from '../fx/fx';
import { useReveal } from '../hooks/useReveal';

function useNow(ms = 1000): number {
  const [t, setT] = useState(now());
  useEffect(() => {
    const id = setInterval(() => setT(now()), ms);
    return () => clearInterval(id);
  }, [ms]);
  return t;
}

function idleLine(i: number): string {
  const g = game();
  const h = new Date().getHours();
  if (h >= 23 || h < 5) return LINES.idleNight;
  if (h < 10 && i % 3 === 0) return LINES.idleMorning;
  const left = Math.max(0, goalTotalTasks(g.goal) - goalDoneCount(g.goal));
  const pool = [
    fillLine(LINES.holding, { n: g.queue.length }),
    ...LINES.idle.map((l) => fillLine(l, { left })),
  ];
  return pickBySeed(pool, `idle${i}`);
}

function HomeCore() {
  const ref = useRef<HTMLDivElement>(null);
  const [mood, setMood] = useState<CoreMood>('');
  const pokes = useRef(0);
  const reset = useRef<number | undefined>(undefined);
  const lp = useRef<number | undefined>(undefined);
  const long = useRef(false);
  const poke = () => {
    pokes.current++;
    clearTimeout(reset.current);
    reset.current = window.setTimeout(() => {
      pokes.current = 0;
      setMood('');
    }, 3200);
    const n = pokes.current;
    ref.current?.animate(
      [
        { transform: 'scale(1)' },
        { transform: 'scale(.84,.9)' },
        { transform: 'scale(1.08,1.04)' },
        { transform: 'scale(1)' },
      ],
      { duration: 440, easing: 'cubic-bezier(.3,1.6,.5,1)' },
    );
    sfx.play('soft');
    const [x, y] = center(ref.current);
    burst(x, y, {
      n: 10 + n * 3,
      colors: n >= 4 ? ['#ff3b7a', '#fff'] : ['#3be8ff', '#fff'],
      min: 2,
      max: 6 + n,
    });
    setMood(n >= 4 ? 'angry' : '');
    sayHome(LINES.poke[Math.min(n - 1, LINES.poke.length - 1)] ?? '');
    if (n >= 4) shake(n * 0.8, 260);
  };
  return (
    <div ref={ref} className="core-home-wrap">
      <Core
        mood={mood}
        className="core-home"
        onPointerDown={() => {
          long.current = false;
          clearTimeout(lp.current);
          lp.current = window.setTimeout(() => {
            long.current = true;
            setMood('love');
            sfx.play('unlock');
            sayHome('……别、别一直按着。我只是在[充电]。');
            setTimeout(() => setMood(''), 3600);
          }, 900);
        }}
        onPointerUp={() => {
          clearTimeout(lp.current);
          if (!long.current) poke();
        }}
        onPointerLeave={() => clearTimeout(lp.current)}
      />
    </div>
  );
}

function QuestCard() {
  const g = useGame((s) => s.game);
  const busy = useUi((s) => s.planJob !== null);
  const t = useNow(60_000);
  const goal = g.goal;
  if (goal.plan.length === 0) {
    if (g.pendingGoal) {
      return (
        <div className="quest pending rv">
          <div className="q-h">
            <span>MAINLINE · 待拆解</span>
          </div>
          <div className="q-t">{g.pendingGoal}</div>
          <div className="q-f">
            <span>上次没拆成。目标我记着。</span>
          </div>
          <Btn kind="pri" sm disabled={busy} onClick={() => void retryPendingPlan()}>
            重试拆解
          </Btn>
        </div>
      );
    }
    return (
      <div className="quest pending rv">
        <div className="q-h">
          <span>MAINLINE · 未立目标</span>
        </div>
        <div className="q-t">还没有主线。</div>
        <Btn
          kind="pri"
          sm
          onClick={() => {
            resetBind();
            void go('onboard');
          }}
        >
          立目标
        </Btn>
      </div>
    );
  }
  const first = goalFirstOpenIndex(goal);
  if (first < 0 && !g.active) {
    return (
      <div className="quest pending rv">
        <div className="q-h">
          <span>MAINLINE · {goalWindowExhausted(goal) ? '下一段待拆' : '下一条待拆'}</span>
        </div>
        <div className="q-t">{goal.text}</div>
        <div className="q-f">
          <span>这一段已经走完。下一段没拆上。</span>
        </div>
        <Btn kind="pri" sm disabled={busy} onClick={() => void resumePlan()}>
          重试拆解
        </Btn>
      </div>
    );
  }
  const days = goal.days || goalTotalTasks(goal);
  const passed = Math.min(days, goalPassedDays(goal, t));
  const left = Math.max(0, days - passed);
  // 节点只摆焦点所在的那一段（≤14）
  const seg = Math.floor(Math.max(0, first) / 14);
  const segTasks = goal.plan.slice(seg * 14, seg * 14 + 14);
  const next = first >= 0 ? goal.plan[first] : null;
  return (
    <button type="button" className="quest rv" onClick={() => void go('main')}>
      <div className="q-h">
        <span>MAINLINE · 主线</span>
        <span className="left">剩 {left} 天</span>
      </div>
      <div className="q-t">{goal.text}</div>
      <div className="pips">
        {segTasks.map((p) => (
          <i key={p.index} className={p.state === 'done' ? 'd' : p.index === first ? 'c' : ''} />
        ))}
      </div>
      <div className="q-f">
        <span>
          第{' '}
          <b>
            {passed}/{days}
          </b>{' '}
          天
        </span>
        <span>{next ? `下一单 · ${next.rank} · ${next.title}` : '这一单在执行中'}</span>
      </div>
    </button>
  );
}

export function Home() {
  const ref = useRef<HTMLElement>(null);
  const g = useGame((s) => s.game);
  const quip = useUi((s) => s.quip);
  const dot = useUi((s) => s.archiveDot);
  const t = useNow(1000);
  useReveal(ref, 0);
  useEffect(() => {
    if (!uiStore.getState().quip) sayHome(idleLine(0));
    let i = 1;
    const id = setInterval(() => {
      if (document.visibilityState === 'visible') sayHome(idleLine(i++));
    }, 9000);
    return () => clearInterval(id);
  }, []);
  const goal = g.goal;
  const done = goalDoneCount(goal);
  const total = goalTotalTasks(goal);
  const days = goal.days || total;
  const n = g.queue.length;
  const orbRef = useRef<HTMLButtonElement>(null);
  return (
    <section className="scene on" id="sc-home" ref={ref}>
      <div className="home-tag rv">
        <span className="on">
          <i className="dot" />
          SYSTEM ONLINE
        </span>
        {goal.plan.length > 0 && (
          <span>
            DAY {pad2(Math.min(days, goalPassedDays(goal, t)))} / {pad2(days)}
          </span>
        )}
      </div>
      <div className="core-wrap">
        <HomeCore />
        <div className="bubble rv">
          <span className="who2">
            SYSTEM · 她说
            <Tap className="link ask-her" quiet onClick={() => setUi({ chatOpen: true })}>
              先问问她 ›
            </Tap>
          </span>
          <Typewriter text={quip} />
        </div>
      </div>
      <QuestCard />
      <Tap className={`active-pill ${g.active ? 'on' : ''}`} onClick={() => void go('exec')}>
        <i />
        执行中{' '}
        <b>
          {g.active ? (g.active.task.timed ? fmtClock(t - g.active.startAt) : '打卡') : '00:00'}
        </b>{' '}
        点我返回 ›
      </Tap>
      <nav className="dock rv">
        <Tap className="navb" onClick={() => void go('main')}>
          <span className="ring">
            <svg className="arc" viewBox="0 0 70 70">
              <circle
                cx="35"
                cy="35"
                r="32"
                strokeDasharray="201"
                strokeDashoffset={201 * (1 - (total ? done / total : 0))}
              />
            </svg>
            <svg className="ic" viewBox="0 0 24 24">
              <ellipse cx="12" cy="7" rx="8" ry="3" />
              <path d="M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3M4 17c0 1.7 3.6 3 8 3s8-1.3 8-3" />
            </svg>
          </span>
          <em>主线</em>
          {total > 0 && (
            <sup>
              {done}/{total}
            </sup>
          )}
        </Tap>
        <Tap
          className="navb"
          onClick={() => {
            setUi({ archiveDot: false });
            void go('archive');
          }}
        >
          <span className="ring">
            <svg className="ic" viewBox="0 0 24 24">
              <path d="M12 2.5l8.2 4.75v9.5L12 21.5l-8.2-4.75v-9.5z" />
              <path d="M12 8l3.5 2v4L12 16l-3.5-2v-4z" />
            </svg>
            <i className={`newdot ${dot ? 'on' : ''}`} />
          </span>
          <em>档案</em>
        </Tap>
        <Tap className="navb" onClick={() => void go('shop')}>
          <span className="ring">
            <svg className="ic" viewBox="0 0 24 24">
              <rect x="4" y="8" width="16" height="12" rx="2.5" />
              <path d="M9 8V6a3 3 0 0 1 6 0v2M4 13h16" />
            </svg>
          </span>
          <em>补给</em>
        </Tap>
        <Tap
          ref={orbRef}
          className="task-orb"
          onClick={() => {
            const [x, y] = center(orbRef.current);
            burst(x, y, { n: 30, colors: ['#d6ff3d', '#fff'], min: 3, max: 10 });
            ring(x, y, '#d6ff3d', 110, 4);
            if (g.active) return void go('exec');
            if (goal.plan.length === 0 && !g.pendingGoal && n === 0) {
              sayHome('还没有目标，哪来的单。先去主线立一个。');
              return;
            }
            void go('board');
          }}
        >
          <span className="rings" />
          <span className="pulse" />
          <b>{g.active ? '继续' : '委托'}</b>
          <small>TASK</small>
          {n > 0 && <i className="badge">{n}</i>}
        </Tap>
      </nav>
      <div className="orb-cap">
        {g.active ? (
          <>
            她在等你<b>交差</b>
          </>
        ) : (
          <>
            她手里有 <b>{n}</b> 单
          </>
        )}
      </div>
    </section>
  );
}
