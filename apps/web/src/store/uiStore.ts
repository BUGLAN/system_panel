/**
 * 界面状态（不进存档）：当前场景、返回栈、叠层、toast、她的台词。
 * 主流程状态机：场景 = boot / auth / consent / onboard / home / main / exec / archive；
 * 叠层（底板、弹窗、结算、升级、加载卡）叠在场景上，返回键先关叠层。
 */
import { createStore } from 'zustand/vanilla';
import { useStore } from 'zustand';
import type { QuestResult } from '@host/core/flow/types';
import type { Quest } from '@host/core/model/quest';
import type { PlanProgress } from '@host/core/api/types';
import type { PlanFailure } from '@host/core/goal/planFailure';

export type Scene = 'boot' | 'auth' | 'consent' | 'onboard' | 'home' | 'main' | 'exec' | 'archive';

export interface SceneMeta {
  hud: boolean;
  ghost: string;
  acc: string;
  title: string;
  sub: string;
}

export const SCENES: Record<Scene, SceneMeta> = {
  boot: { hud: false, ghost: '系统', acc: '#d6ff3d', title: '唤醒', sub: 'BOOT' },
  auth: { hud: false, ghost: '登录', acc: '#3be8ff', title: '登录', sub: 'SIGN IN' },
  consent: { hud: false, ghost: '告知', acc: '#3be8ff', title: '告知', sub: 'NOTICE' },
  onboard: { hud: false, ghost: '绑定', acc: '#d6ff3d', title: '绑定仪式', sub: 'BINDING' },
  home: { hud: true, ghost: '系统', acc: '#d6ff3d', title: '大厅', sub: 'LOBBY' },
  main: { hud: false, ghost: '主线', acc: '#3be8ff', title: '主线', sub: 'MAINLINE' },
  exec: { hud: true, ghost: '执行', acc: '#ff3b7a', title: '任务开始', sub: 'MISSION START' },
  archive: { hud: false, ghost: '档案', acc: '#8f6bff', title: '档案', sub: 'ARCHIVE' },
};

export type ToastKind = '' | 'ok' | 'err';

export interface Toast {
  id: number;
  text: string;
  kind: ToastKind;
}

export interface ConfirmReq {
  title: string;
  body: string;
  yes: string;
  no: string;
  danger?: boolean;
  resolve(v: boolean): void;
}

/** 底板类叠层（同一时间只开一个） */
export type SheetKind =
  'system' | 'llm' | 'notice' | 'install' | 'evidence' | 'goalSwap' | 'account';

/** 全屏演出叠层 */
export type Show =
  | {
      kind: 'verdict';
      result: QuestResult;
      evidenceUrl: string | null;
      line: string;
      followUpError: PlanFailure | null;
    }
  | { kind: 'levelup'; from: number; to: number; brief: boolean };

/** 等 LLM 时的整屏加载卡 */
export interface PlanJobUi {
  kind: 'match' | 'bind' | 'retry' | 'window' | 'finale' | 'swap';
  title: string;
  progress: PlanProgress;
}

export interface UiState {
  scene: Scene;
  hist: Scene[];
  navBusy: boolean;
  sheet: SheetKind | null;
  confirm: ConfirmReq | null;
  briefing: Quest | null;
  show: Show | null;
  planJob: PlanJobUi | null;
  toasts: Toast[];
  /** 大厅气泡 / 主线 sysbox / 执行 watch 的台词 */
  quip: string;
  mainLine: string;
  watchLine: string;
  watchAt: number;
  /** 刚交掉的那一环（主线页盖章 + 解封下一张的演出） */
  mainJustDone: number | null;
}

export const uiStore = createStore<UiState>()(() => ({
  scene: 'boot',
  hist: [],
  navBusy: false,
  sheet: null,
  confirm: null,
  briefing: null,
  show: null,
  planJob: null,
  toasts: [],
  quip: '',
  mainLine: '',
  watchLine: '',
  watchAt: 0,
  mainJustDone: null,
}));

export function useUi<T>(sel: (s: UiState) => T): T {
  return useStore(uiStore, sel);
}

export const setUi = (p: Partial<UiState>) => uiStore.setState(p);

let toastSeq = 0;
export function toast(text: string, kind: ToastKind = ''): void {
  const t: Toast = { id: ++toastSeq, text, kind };
  uiStore.setState((s) => ({ toasts: [...s.toasts, t].slice(-3) }));
  setTimeout(
    () => uiStore.setState((s) => ({ toasts: s.toasts.filter((x) => x.id !== t.id) })),
    2900,
  );
}

export function confirmBox(
  o: Omit<ConfirmReq, 'resolve' | 'yes' | 'no'> & { yes?: string; no?: string },
): Promise<boolean> {
  return new Promise((resolve) => {
    setUi({
      confirm: {
        yes: '确定',
        no: '再想想',
        ...o,
        resolve: (v) => {
          setUi({ confirm: null });
          resolve(v);
        },
      },
    });
  });
}

export function sayHome(text: string): void {
  setUi({ quip: text });
}
export function sayMain(text: string): void {
  setUi({ mainLine: text });
}
export function sayWatch(text: string): void {
  setUi({ watchLine: text, watchAt: Date.now() });
}
