/**
 * 绑定仪式（首次立目标）：输入目标 → 匹配类目 → 3 张访谈卡 → 拆第一段 → 大厅。
 * 拆解失败停在复核态（B1）：错误卡 + 已答的卡 +【重试拆解】【换个说法】「改答案」「先跳过」，答案不清空。
 * 「先跳过」记住目标、先发当天日常（C5）。匹配与拆解都在服务端跑，这里只管界面节奏。
 */
import { createStore } from 'zustand/vanilla';
import { useStore } from 'zustand';
import type { MatchView } from '@host/core/api/types';
import { CRISIS_CARE_LINE, isCrisisText } from '@host/core/agent/guardrail';
import { LINES } from '@host/core/data/lines';
import type { InterviewCard } from '@host/core/data/categoryTypes';
import { BIND_GIFT, isVagueGoal } from '@host/core/goal/categories';
import type { PlanFailure } from '@host/core/goal/planFailure';
import { sfx } from '../../audio/sfx';
import { ApiError, api } from '../api';
import { game, intent } from '../game';
import { sayHome, toast } from '../uiStore';
import { go } from './nav';
import { asFailure, startServerJob, withPlanJob } from './planJob';

export type BindStage = 'ask' | 'interview' | 'review';

export interface BindState {
  stage: BindStage;
  /** 输入框里的目标原文 */
  text: string;
  /** 已经交给她的那句（复核态 / 换个说法回来用） */
  goalText: string;
  /** 匹配出的类目（服务端记着同一句的匹配结果，拆第一段时不再匹配） */
  match: MatchView | null;
  cards: InterviewCard[];
  answers: Record<string, string>;
  idx: number;
  /** 重答模式：原选项描边 */
  editing: boolean;
  error: PlanFailure | null;
  /** 她这一句 */
  line: string;
}

const initial = (): BindState => ({
  stage: 'ask',
  text: '',
  goalText: '',
  match: null,
  cards: [],
  answers: {},
  idx: 0,
  editing: false,
  error: null,
  line: LINES.askGoal,
});

export const bindStore = createStore<BindState>()(initial);
export const useBind = <T>(sel: (s: BindState) => T) => useStore(bindStore, sel);
const set = (p: Partial<BindState>) => bindStore.setState(p);

export function resetBind(prefill = ''): void {
  bindStore.setState({ ...initial(), text: prefill });
}

export function setBindText(text: string): void {
  set({ text });
}

/** ① 交目标：自伤闸门 → 空泛 → 匹配类目（加载卡）→ 访谈 */
export async function submitGoal(): Promise<void> {
  const typed = bindStore.getState().text.trim();
  if (isCrisisText(typed)) {
    set({ error: null, line: CRISIS_CARE_LINE });
    return;
  }
  if (isVagueGoal(typed)) {
    sfx.play('error');
    set({ line: '太空了。说点具体的——[一句话]。' });
    return;
  }
  const prev = bindStore.getState();
  // 换个说法回来、还是同一句：类目卡组没变就直接复核，不重答
  set({ error: null, goalText: typed, line: '……我看看这是哪一类。' });
  const r = await withPlanJob({ kind: 'match', title: '她在看这条目标' }, () =>
    api<{ match: MatchView; cards: InterviewCard[] }>('POST', '/api/plan/match', { text: typed }),
  );
  if (!r) return;
  if (!r.ok) {
    if (r.error instanceof ApiError && r.error.code === 'crisis') {
      set({ error: null, line: CRISIS_CARE_LINE });
      return;
    }
    sfx.play('error');
    set({
      error: asFailure(r.error),
      line: '这一步没走通。答案还没开始答，[重试]或者先跳过。',
    });
    return;
  }
  const { match: m, cards } = r.value;
  const sameDeck = prev.match?.catId === m.catId && cards.every((c) => prev.answers[c.id]);
  sfx.play('deal');
  if (sameDeck) {
    set({
      match: m,
      cards,
      stage: 'review',
      idx: cards.length,
      editing: false,
      line: '答案都在，确认一下。',
    });
    return;
  }
  set({
    match: m,
    cards,
    answers: {},
    idx: 0,
    stage: 'interview',
    editing: false,
    line: '凭第一反应选。想太久的答案都不准。',
  });
}

/** ② 答一张卡；答完最后一张就开始拆 */
export function answer(cardId: string, value: string): void {
  const s = bindStore.getState();
  const v = value.trim();
  if (!v) return;
  const answers = { ...s.answers, [cardId]: v };
  const idx = s.idx + 1;
  sfx.play('soft');
  if (idx >= s.cards.length) {
    set({ answers, idx, editing: false });
    void startBuild();
    return;
  }
  set({ answers, idx });
}

/** 访谈退回上一张 */
export function prevCard(): void {
  const s = bindStore.getState();
  if (s.idx > 0) set({ idx: s.idx - 1 });
}

/** ③ 拆第一段（首目标：只出 E~C）；服务端拆好直接落库（主线 + 当天日常 + 见面礼 + 访谈记忆） */
export async function startBuild(): Promise<void> {
  const s = bindStore.getState();
  if (!s.match) return;
  set({ error: null, line: '……行，让我把这条拆开。' });
  const r = await withPlanJob({ kind: 'bind', title: '拆第一段' }, (onProgress) =>
    startServerJob({ kind: 'bind', text: s.goalText, answers: s.answers }, onProgress),
  );
  if (!r) return;
  if (!r.ok) {
    sfx.play('error');
    const e = asFailure(r.error);
    set({ stage: 'review', error: e, line: '这次没拆明白。答案我都记着——[重试]，或者换个说法。' });
    return;
  }
  await afterFirstGoal();
}

/** 首目标落库之后：进大厅，她报数，见面礼 toast */
export async function afterFirstGoal(): Promise<void> {
  sfx.play('unlock');
  const n = game().goal.plan.length;
  await go('home');
  resetBind();
  sayHome(`排好了。先排 [[${n}]] 张，一天一张；做完我再往下拆。`);
  toast(`${BIND_GIFT.kicker}：${BIND_GIFT.text}`, 'ok');
}

/** 【重试拆解】同一组答案再交 */
export function retryBuild(): void {
  const s = bindStore.getState();
  if (s.match) void startBuild();
  else void submitGoal();
}

/** 【换个说法】回第 0 幕、原文预填；答案留着 */
export function rephrase(): void {
  const s = bindStore.getState();
  set({ stage: 'ask', text: s.goalText || s.text, error: null, line: '换个说法。[一句话]就够。' });
}

/** 「改答案」逐张重答，原选项描边 */
export function editAnswers(): void {
  set({
    stage: 'interview',
    idx: 0,
    editing: true,
    error: null,
    line: '改哪张就点哪个。原来的答案我描了边。',
  });
}

/** 「先跳过」：记住目标、先发当天日常、进大厅（C5） */
export async function skipBind(): Promise<void> {
  const s = bindStore.getState();
  const keep = (s.goalText || s.text).trim();
  const r = await intent('/api/flow/skip-plan', { text: keep });
  if (!r.ok) {
    sfx.play('error');
    toast(r.err.message, 'err');
    return;
  }
  await go('home');
  resetBind();
  sayHome(
    keep ? '目标我记着了。今天先把日常做了，回头[重试拆解]。' : '先从日常开始。目标想好了再来。',
  );
}
