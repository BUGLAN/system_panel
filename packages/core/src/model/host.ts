/**
 * 宿主档案。移植自 flutter-final:app/lib/state/host_state.dart（晶核、道具、称号、六维已拿掉）。
 */
import { int, isObj, str, type Json } from '../save/json';

export interface HostState {
  name: string;
  lv: number;
  /** 当前等级内的经验余额 */
  exp: number;
  /** 连胜天数 */
  streak: number;
  bestStreak: number;
  doneCount: number;
  /** 累计 EXP：只增不减（升级扣的是余额，累计不扣） */
  totalExp: number;
}

export function emptyHost(): HostState {
  return {
    name: '宿主',
    lv: 1,
    exp: 0,
    streak: 0,
    bestStreak: 0,
    doneCount: 0,
    totalExp: 0,
  };
}

export function hostToJson(h: HostState): Json {
  return {
    name: h.name,
    lv: h.lv,
    exp: h.exp,
    streak: h.streak,
    bestStreak: h.bestStreak,
    doneCount: h.doneCount,
    totalExp: h.totalExp,
  };
}

export function hostFromJson(v: unknown): HostState {
  const def = emptyHost();
  if (!isObj(v)) return def;
  const lv = int(v, 'lv', def.lv);
  return {
    name: str(v, 'name', def.name),
    lv: lv < 1 ? 1 : lv,
    exp: Math.max(0, int(v, 'exp', def.exp)),
    streak: Math.max(0, int(v, 'streak', def.streak)),
    bestStreak: Math.max(0, int(v, 'bestStreak', def.bestStreak)),
    doneCount: Math.max(0, int(v, 'doneCount', 0)),
    totalExp: Math.max(0, int(v, 'totalExp', 0)),
  };
}
