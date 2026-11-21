/**
 * 绑定仪式：输入目标（50 字、组字不计、组字时 CTA 置灰）→ 3 张访谈卡 → 拆第一段；
 * 失败停在复核态（错误卡 + 已答的卡 + 四个按钮）。键盘弹起时 CTA 吸在键盘上沿（B3）。
 */
import { useRef, useState } from 'react';
import { ONBOARD_PRESETS } from '@host/core/goal/categories';
import { planFailLine, planFailTitle } from '@host/core/goal/planFailCopy';
import {
  answer,
  editAnswers,
  prevCard,
  rephrase,
  retryBuild,
  setBindText,
  skipBind,
  submitGoal,
  useBind,
} from '../../store/actions/bind';
import { setUi, useUi } from '../../store/uiStore';
import { Btn, Tap } from '../kit/Btn';
import { Core } from '../kit/Core';
import { LimitedInput, charCount } from '../kit/LimitedInput';
import { Typewriter } from '../kit/Typewriter';
import { useReveal } from '../hooks/useReveal';

export const GOAL_MAX = 50;

function Bubble({ text }: { text: string }) {
  return (
    <div className="bubble ob-bubble">
      <span className="who2">SYSTEM · 她说</span>
      <Typewriter text={text} />
    </div>
  );
}

function ErrorCard() {
  const e = useBind((s) => s.error);
  if (!e) return null;
  const needsKey = e.code === 'noKey' || e.code === 'cors';
  return (
    <div className="err-card">
      <div className="ec-h">PLAN · 拆解失败</div>
      <b>{planFailTitle(e.code)}</b>
      <p>{planFailLine(e.code)}</p>
      <small>{e.detail}</small>
      {needsKey && (
        <Tap className="link" onClick={() => setUi({ sheet: 'llm' })}>
          去填模型设置 ›
        </Tap>
      )}
    </div>
  );
}

function AskStage() {
  const text = useBind((s) => s.text);
  const error = useBind((s) => s.error);
  const busy = useUi((s) => s.planJob !== null);
  const [composing, setComposing] = useState(false);
  const n = charCount(text);
  const can = !composing && !busy && text.trim().length > 0;
  return (
    <>
      <div className="eyebrow rv">BINDING · 绑定仪式</div>
      <h1 className="h1 rv">宿主，说出你的目标。</h1>
      <ErrorCard />
      <div className="ob-field rv">
        <label className="ob-lab">目标</label>
        <LimitedInput
          value={text}
          onChange={setBindText}
          onComposing={setComposing}
          onSubmit={() => can && void submitGoal()}
          max={GOAL_MAX}
          placeholder="比如：三个月跑完半马"
          enterKeyHint="done"
        />
        <div className="ob-count">{composing ? '输入中…' : `${n}/${GOAL_MAX}`}</div>
      </div>
      <div className="chips rv">
        {ONBOARD_PRESETS.map((p) => (
          <Tap key={p} className="chip-opt" quiet onClick={() => setBindText(p)}>
            {p}
          </Tap>
        ))}
      </div>
      <div className="ex-sp" />
      <div className="kb-dock rv">
        {error && (
          <Tap className="link ob-skip" onClick={() => void skipBind()}>
            先跳过，今天先做日常 ›
          </Tap>
        )}
        <Btn kind="pri" disabled={!can} onClick={() => void submitGoal()}>
          确立目标
        </Btn>
      </div>
    </>
  );
}

function InterviewStage() {
  const cards = useBind((s) => s.cards);
  const idx = useBind((s) => s.idx);
  const answers = useBind((s) => s.answers);
  const editing = useBind((s) => s.editing);
  const [own, setOwn] = useState<string | null>(null);
  const [composing, setComposing] = useState(false);
  const card = cards[Math.min(idx, cards.length - 1)];
  if (!card) return null;
  const prev = answers[card.id];
  return (
    <>
      <div className="eyebrow rv">INTERVIEW · 访谈</div>
      <h1 className="h1 rv">
        答完这几张，
        <br />
        我给你排第一段。
      </h1>
      <div className="iv-card rv" key={card.id}>
        <div className="iv-h">
          <span>
            {String(idx + 1).padStart(2, '0')} / {String(cards.length).padStart(2, '0')}
          </span>
          {idx > 0 && (
            <Tap className="link" quiet onClick={prevCard}>
              ‹ 上一张
            </Tap>
          )}
        </div>
        <b className="iv-q">{card.question}</b>
        <div className="iv-opts">
          {card.options.map((o) => (
            <Tap
              key={o}
              className={`iv-opt ${editing && prev === o ? 'was' : ''}`}
              onClick={() => {
                setOwn(null);
                answer(card.id, o);
              }}
            >
              {o}
            </Tap>
          ))}
          {own === null ? (
            <Tap
              className={`iv-opt own ${editing && prev && !card.options.includes(prev) ? 'was' : ''}`}
              quiet
              onClick={() => setOwn('')}
            >
              自己写 ›
            </Tap>
          ) : (
            <div className="iv-own">
              <LimitedInput
                value={own}
                onChange={setOwn}
                onComposing={setComposing}
                onSubmit={() => !composing && own.trim() && answer(card.id, own)}
                max={GOAL_MAX}
                placeholder="用一句话回答"
                autoFocus
              />
              <Btn
                kind="pri"
                sm
                disabled={composing || !own.trim()}
                onClick={() => answer(card.id, own)}
              >
                回答
              </Btn>
            </div>
          )}
        </div>
      </div>
    </>
  );
}

function ReviewStage() {
  const cards = useBind((s) => s.cards);
  const answers = useBind((s) => s.answers);
  const goalText = useBind((s) => s.goalText);
  const error = useBind((s) => s.error);
  const busy = useUi((s) => s.planJob !== null);
  return (
    <>
      <div className="eyebrow rv">{error ? 'PLAN · 拆解失败' : 'REVIEW · 复核'}</div>
      <h1 className="h1 rv">{error ? '拆到一半，线断了。' : '答案都在，确认一下。'}</h1>
      <ErrorCard />
      <div className="kept rv">
        <div className="kept-h">KEPT · 已答，不用重答</div>
        <div className="kept-row">
          <span>目标</span>
          <b>{goalText}</b>
        </div>
        {cards.map((c) => (
          <div className="kept-row" key={c.id}>
            <span>{c.question}</span>
            <b>{answers[c.id] ?? '—'}</b>
          </div>
        ))}
      </div>
      <div className="ex-sp" />
      <div className="review-act rv">
        <Btn kind="pri" disabled={busy} onClick={retryBuild}>
          {error ? '重试拆解' : '开始拆解'}
        </Btn>
        <div className="row">
          <Btn kind="ghost" sm grow disabled={busy} onClick={rephrase}>
            换个说法
          </Btn>
          <Btn kind="ghost" sm grow disabled={busy} onClick={editAnswers}>
            改答案 ›
          </Btn>
        </div>
        <Tap className="link ob-skip" onClick={() => void skipBind()}>
          暂时跳过 ›
        </Tap>
      </div>
    </>
  );
}

export function Onboard() {
  const ref = useRef<HTMLElement>(null);
  const stage = useBind((s) => s.stage);
  const line = useBind((s) => s.line);
  useReveal(ref, 140, [stage]);
  return (
    <section className={`scene nohud on onboard st-${stage}`} ref={ref}>
      <div className="ob-top">
        <Core className="ob-core" />
        <Bubble text={line} />
      </div>
      {stage === 'ask' && <AskStage />}
      {stage === 'interview' && <InterviewStage />}
      {stage === 'review' && <ReviewStage />}
    </section>
  );
}
