/**
 * 换目标（弹窗式面板，✕ 关闭）：当前主线卡（将撤下 · 等级 / 晶核 / 六维保留）+ 新目标输入；
 * 没有目标时切成「首次立目标」模式（B2）：不显示「将撤下」，主键「下一步 · 访谈」带原文进绑定仪式。
 */
import { useState } from 'react';
import { ONBOARD_PRESETS } from '@host/core/goal/categories';
import { goalDoneCount, goalPassedDays, goalTotalTasks } from '@host/core/model/goal';
import { planFailLine, planFailTitle } from '../../agent/goalBuilder';
import { useGame } from '../../store/gameStore';
import { now } from '../../store/game';
import { submitGoalSwap, swapStore, useSwap } from '../../store/actions/goals';
import { setUi, useUi } from '../../store/uiStore';
import { Btn, Tap } from '../kit/Btn';
import { LimitedInput, charCount } from '../kit/LimitedInput';
import { Panel } from '../kit/Sheet';
import { Typewriter } from '../kit/Typewriter';
import { GOAL_MAX } from '../scenes/Onboard';

function SwapForm() {
  const g = useGame((s) => s.game.goal);
  const text = useSwap((s) => s.text);
  const line = useSwap((s) => s.line);
  const err = useSwap((s) => s.error);
  const busy = useUi((s) => s.planJob !== null);
  const [composing, setComposing] = useState(false);
  const first = g.plan.length === 0;
  const can = !composing && !busy && text.trim().length > 0;
  const setText = (v: string) => swapStore.setState({ text: v });
  return (
    <>
      <div className="bubble swap-bubble">
        <span className="who2">SYSTEM · 她说</span>
        <Typewriter text={line} />
      </div>
      {first ? (
        <div className="swap-cur first">第一次立目标 · 没有旧清单要撤 · 下一步答 3 张访谈卡</div>
      ) : (
        <div className="swap-cur">
          <div className="sc-h">
            CURRENT · 当前主线 <span>将撤下</span>
          </div>
          <b>{g.text}</b>
          <small>
            完成 {goalDoneCount(g)}/{goalTotalTasks(g)} 单 · 已过{' '}
            {Math.min(g.days, goalPassedDays(g, now()))} 天 · 等级 / 晶核 / 六维保留
          </small>
        </div>
      )}
      {err && (
        <div className="err-card">
          <div className="ec-h">PLAN · 拆解失败</div>
          <b>{planFailTitle(err.code)}</b>
          <p>{planFailLine(err.code)} 旧主线没动。</p>
          <small>{err.detail}</small>
        </div>
      )}
      <div className="ob-field">
        <label className="ob-lab">新目标</label>
        <LimitedInput
          value={text}
          onChange={setText}
          onComposing={setComposing}
          onSubmit={() => can && void submitGoalSwap()}
          max={GOAL_MAX}
          placeholder="比如：半年减重 10 斤"
        />
        <div className="ob-count">{composing ? '输入中…' : `${charCount(text)}/${GOAL_MAX}`}</div>
      </div>
      <div className="chips">
        {ONBOARD_PRESETS.map((p) => (
          <Tap key={p} className="chip-opt" quiet onClick={() => setText(p)}>
            {p}
          </Tap>
        ))}
      </div>
      <Tap
        className="link swap-ask"
        onClick={() => {
          setUi({ sheet: null, chatOpen: true });
        }}
      >
        先问问她 ›
      </Tap>
      <div className="panel-act kb-dock">
        <Btn kind="pri" disabled={!can} onClick={() => void submitGoalSwap()}>
          {busy ? '拆解中…' : first ? '下一步 · 访谈' : '确认换线'}
        </Btn>
      </div>
    </>
  );
}

export function GoalSwap() {
  const open = useUi((s) => s.sheet === 'goalSwap');
  const first = useGame((s) => s.game.goal.plan.length === 0);
  return (
    <Panel
      open={open}
      onClose={() => setUi({ sheet: null })}
      eyebrow={first ? 'FIRST GOAL · 立目标' : 'REWRITE · 换目标'}
      title={first ? '先立第一条主线' : '换一条主线'}
      accent="var(--acid)"
    >
      <SwapForm />
    </Panel>
  );
}
