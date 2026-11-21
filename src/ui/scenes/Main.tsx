/**
 * 主线（参考稿 #sc-main）：已过 x/总 天、分段标识（第 k 段 · 01–14 + 段进度格，B7）、
 * 当前这一段的收藏卡轮播 + 底座 + 节点轨、她的点评、去委托板 / 换目标。
 * 没主线：【立目标】；记着目标：【重试拆解】；清单走完没续上：【重试拆解】（D3.2）。
 */
import { useEffect, useRef, useState } from 'react';
import { attrName } from '../../core/data/attrs';
import { PLAN_WINDOW_SIZE } from '../../core/goal/plan';
import {
  goalDoneCount,
  goalFirstOpenIndex,
  goalPassedDays,
  goalTotalTasks,
  goalWindowExhausted,
} from '../../core/model/goal';
import { pad2 } from '../../core/format';
import { sfx } from '../../audio/sfx';
import { useGame } from '../../store/gameStore';
import { game, now } from '../../store/game';
import { back, go } from '../../store/actions/nav';
import { openBriefing } from '../../store/actions/exec';
import { openGoalSwap } from '../../store/actions/goals';
import { resumePlan, retryPendingPlan } from '../../store/actions/plan';
import { resetBind } from '../../store/actions/bind';
import { sayMain, setUi, uiStore, useUi } from '../../store/uiStore';
import { Btn, Tap } from '../kit/Btn';
import { Carousel, type CarouselApi } from '../kit/Carousel';
import { Core, type CoreMood } from '../kit/Core';
import { IconBack } from '../kit/icons';
import { MainCard, type CardState } from '../kit/MainCard';
import { Typewriter } from '../kit/Typewriter';
import { burst, center, flash, ring, shake, shakeEl } from '../fx/fx';
import { useReveal } from '../hooks/useReveal';
import { RANK_COLORS } from '../../design/tokens';

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

function Empty() {
  const pending = useGame((s) => s.game.pendingGoal);
  const busy = useUi((s) => s.planJob !== null);
  return (
    <div className="main-empty rv">
      <p>{pending ? `「${pending}」上次没拆成。\n目标我记着，点下面重试。` : '还没有清单。先去立一个目标。'}</p>
      {pending ? (
        <Btn kind="pri" disabled={busy} onClick={() => void retryPendingPlan()}>
          重试拆解
        </Btn>
      ) : (
        <Btn
          kind="pri"
          onClick={() => {
            resetBind();
            void go('onboard');
          }}
        >
          立目标
        </Btn>
      )}
    </div>
  );
}

export function Main() {
  const ref = useRef<HTMLElement>(null);
  const car = useRef<CarouselApi>(null);
  const g = useGame((s) => s.game);
  const line = useUi((s) => s.mainLine);
  const busy = useUi((s) => s.planJob !== null);
  const [mood, setMood] = useState<CoreMood>('');
  const [moodText, setMoodText] = useState('尚可');
  const [focus, setFocus] = useState(0);
  const [flipped, setFlipped] = useState<Set<number>>(new Set());
  const goal = g.goal;
  const first = goalFirstOpenIndex(goal);
  const total = goalTotalTasks(goal);
  const done = goalDoneCount(goal);
  const seg = Math.floor(Math.max(0, first >= 0 ? first : goal.plan.length - 1) / PLAN_WINDOW_SIZE);
  const segs = Math.max(1, Math.ceil(total / PLAN_WINDOW_SIZE));
  const tasks = goal.plan.slice(seg * PLAN_WINDOW_SIZE, seg * PLAN_WINDOW_SIZE + PLAN_WINDOW_SIZE);
  const startLocal = (() => {
    const jd = uiStore.getState().mainJustDone;
    const at = jd !== null ? jd : first >= 0 ? first : goal.plan.length - 1;
    return Math.max(0, Math.min(tasks.length - 1, at - seg * PLAN_WINDOW_SIZE));
  })();
  useReveal(ref);

  const stateOf = (local: number): CardState => {
    const t = tasks[local];
    if (!t) return 'lock';
    if (t.state === 'done') return 'done';
    return t.index === first ? 'cur' : 'lock';
  };

  const onFocus = (local: number) => {
    setFocus(local);
    const t = tasks[local];
    if (!t) return;
    const st = stateOf(local);
    const n = t.index + 1;
    if (st === 'done') {
      setMood('happy');
      setMoodText('满意');
      sayMain(`第 [${n}] 单，已验收。别回头看，往前走。`);
    } else if (st === 'cur') {
      setMood('');
      setMoodText('尚可');
      sayMain(`第 [${Math.min(goal.days || total, goalPassedDays(goal, now()))}] 天，完成 [${done}] 单。清单不会自己变短。`);
    } else if (t.finalTask) {
      setMood('');
      setMoodText('期待');
      sayMain(t.timed ? `终局单。[${t.minutes}] 分钟。我会在终点等你——大概。` : '终局单。[打卡]，随时交。我会在终点等你——大概。');
    } else {
      setMood('');
      setMoodText('冷静');
      sayMain(`第 [${n}] 单还锁着。先把眼前那单干掉。`);
    }
  };

  const onTap = (local: number, el: HTMLDivElement) => {
    const t = tasks[local];
    if (!t) return;
    const st = stateOf(local);
    if (st === 'done') {
      const next = new Set(flipped);
      const f = !next.has(local);
      if (f) next.add(local);
      else next.delete(local);
      setFlipped(next);
      sfx.play('swipe');
      const [x, y] = center(el);
      burst(x, y, { type: 'star', n: 16, colors: ['#3be8ff', '#fff'], g: 0.04, sz: 3 });
      if (f) sayMain(`第 [${t.index + 1}] 单战报：评级 [${t.grade ?? '—'}]。`);
      return;
    }
    if (st === 'cur') {
      const a = game().active;
      if (a && a.task.planIndex === t.index && a.task.goalId) {
        void go('exec');
        return;
      }
      const q = game().queue.find(
        (x) => (x.kind === 'main' || (x.kind === 'remedy' && x.planIndex >= 0)) && x.planIndex === t.index,
      );
      if (q) openBriefing(q);
      return;
    }
    shakeEl(el);
    sfx.play('error');
    setMood('angry');
    setTimeout(() => setMood(''), 1500);
    sayMain('还没解锁。[别急着越级]，宿主。');
  };

  // 刚交掉一环：盖章 → 移到下一张 → 解封
  useEffect(() => {
    const jd = uiStore.getState().mainJustDone;
    if (jd === null) return;
    setUi({ mainJustDone: null });
    let alive = true;
    void (async () => {
      await sleep(760);
      const local = jd - seg * PLAN_WINDOW_SIZE;
      const stamp = car.current?.cardEl(local)?.querySelector<HTMLElement>('.stamp');
      if (!alive) return;
      if (stamp) {
        await stamp.animate(
          [
            { transform: 'rotate(-14deg) scale(3.4)', opacity: 0 },
            { transform: 'rotate(-14deg) scale(1)', opacity: 1 },
          ],
          { duration: 320, easing: 'cubic-bezier(.6,0,.8,.4)', fill: 'backwards' },
        ).finished;
        sfx.play('stamp');
        shake(9, 380);
        const [x, y] = center(stamp);
        burst(x, y, { n: 34, colors: ['#ff3b7a', '#fff'], min: 3, max: 11 });
        ring(x, y, '#ff3b7a', 120, 4);
      }
      sayMain(`盖章。完成 [${goalDoneCount(game().goal)}] 单，清单短了一点点。`);
      await sleep(1100);
      if (!alive) return;
      const nextLocal = local + 1;
      if (nextLocal < tasks.length) {
        car.current?.go(nextLocal);
        await sleep(650);
        sfx.play('unlock');
        const el = car.current?.cardEl(nextLocal);
        if (el) {
          const [x, y] = center(el);
          burst(x, y, { type: 'star', n: 30, colors: ['#d6ff3d', '#fff', '#3be8ff'], min: 2, max: 9, sz: 3 });
          ring(x, y, '#d6ff3d', 160, 3);
          flash();
        }
        const nt = tasks[nextLocal];
        if (nt) sayMain(`新卡解封：[${nt.title}]。别愣着。`);
      }
    })();
    return () => {
      alive = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (goal.plan.length === 0) {
    return (
      <section className="scene nohud on" id="sc-main" ref={ref}>
        <div className="sh rv">
          <div>
            <div className="eyebrow">MAINLINE · 主线</div>
            <h1 className="h1">（还没有目标）</h1>
          </div>
          <Tap className="xbtn" aria-label="返回" onClick={back}>
            <IconBack />
          </Tap>
        </div>
        <Empty />
      </section>
    );
  }

  const days = goal.days || total;
  const passed = Math.min(days, goalPassedDays(goal, now()));
  const left = Math.max(0, days - passed);
  const resume = first < 0 && !g.active;
  const focusTask = tasks[focus];
  const pedColor =
    focusTask?.state === 'done'
      ? '#3be8ff'
      : focusTask?.finalTask
        ? '#ffcc4d'
        : focusTask && focusTask.index === first
          ? '#d6ff3d'
          : '#8f6bff';
  return (
    <section className="scene nohud on" id="sc-main" ref={ref}>
      <div className="sh rv">
        <div style={{ minWidth: 0 }}>
          <div className="eyebrow">MAINLINE · 主线</div>
          <h1 className="h1">{goal.text}</h1>
        </div>
        <Tap className="xbtn" aria-label="返回" onClick={back}>
          <IconBack />
        </Tap>
      </div>
      <div className="meta rv">
        已过{' '}
        <b>
          {passed}/{days}
        </b>{' '}
        天 · 完成 <b>{done}</b> 单 <span className="pill">{left > 0 ? `剩 ${left} 天` : '今天截止'}</span>
      </div>
      <div className="segbar rv">
        <span>
          第 {seg + 1} 段 · {pad2(seg * PLAN_WINDOW_SIZE + 1)}–{pad2(seg * PLAN_WINDOW_SIZE + tasks.length)}
        </span>
        {segs <= 16 ? (
          <span className="segpips">
            {Array.from({ length: segs }, (_, i) => (
              <i key={i} className={i < seg ? 'd' : i === seg ? 'c' : ''} />
            ))}
          </span>
        ) : (
          <span>
            {seg + 1} / {segs} 段
          </span>
        )}
      </div>
      <div className="car" id="mainCar">
        <Carousel
          api={car}
          count={tasks.length}
          start={startLocal}
          ar={0.66}
          wf={0.7}
          max={300}
          pad={34}
          shade
          compactH={430}
          onFocus={onFocus}
          onTap={onTap}
          cardClass={(i) => {
            const st = stateOf(i);
            const t = tasks[i];
            return `${st} ${t?.finalTask ? 'boss' : ''} ${st === 'lock' ? 'fd' : ''} ${flipped.has(i) ? 'flipped' : ''} ${st === 'cur' ? 'cur' : ''}`;
          }}
          cardStyle={(i) => {
            const t = tasks[i];
            return t ? { ['--gc' as string]: t.finalTask ? '#ffcc4d' : RANK_COLORS[t.rank] } : {};
          }}
          render={(i) => {
            const t = tasks[i];
            if (!t) return null;
            const a = g.active;
            const at = Object.keys(t.attrs)[0];
            return (
              <MainCard
                t={t}
                total={total}
                state={stateOf(i)}
                executing={!!a && a.task.planIndex === t.index}
                catChar={at ? attrName(at).slice(0, 1) : '主'}
              />
            );
          }}
        >
          <div className="ped" style={{ ['--pc' as string]: pedColor }}>
            <b />
            <i />
            <i />
          </div>
        </Carousel>
      </div>
      <div className="rv" id="mainRuler" style={{ ['--pf' as string]: Math.min(1, tasks.filter((t) => t.state === 'done').length / Math.max(1, tasks.length - 1)) }}>
        {tasks.map((t, i) => (
          <i
            key={t.index}
            className={`${t.state === 'done' ? 'd' : ''} ${t.index === first ? 'c' : ''} ${t.finalTask ? 'b' : ''} ${i === focus ? 'on' : ''}`}
            onClick={() => {
              car.current?.go(i);
              sfx.play('soft');
            }}
          >
            {t.finalTask ? '★' : t.index + 1}
          </i>
        ))}
      </div>
      <div className="sysbox rv">
        <Core className="core-main" mood={mood} />
        <div style={{ minWidth: 0 }}>
          <div className="sb-h">
            SYSTEM <i>·····</i>
            <span>{moodText}</span>
          </div>
          <Typewriter text={line} />
        </div>
      </div>
      <div className="actions rv">
        {resume ? (
          <Btn kind="pri" disabled={busy} onClick={() => void resumePlan()}>
            {goalWindowExhausted(goal) ? '重试拆解 · 下一段' : '重试拆解 · 下一条'}
          </Btn>
        ) : (
          <Btn kind="pri" onClick={() => void go('board')}>
            去委托板 <span className="tri" />
          </Btn>
        )}
        <Btn kind="ghost" onClick={openGoalSwap}>
          换目标
        </Btn>
      </div>
    </section>
  );
}
