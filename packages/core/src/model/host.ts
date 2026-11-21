/**
 * 宿主档案。移植自 flutter-final:app/lib/state/host_state.dart（去掉旧档迁移字段）。
 */
import { zeroAttrs, type AttrKey } from '../data/attrs';
import { attrMap, int, intMap, isObj, str, strList, type Json } from '../save/json';

export interface HostState {
  name: string;
  lv: number;
  /** 当前等级内的经验余额 */
  exp: number;
  /** 晶核 */
  coins: number;
  /** 连胜天数 */
  streak: number;
  bestStreak: number;
  /** 佩戴中的称号 id */
  title: string;
  ownedTitles: string[];
  /** 六维 */
  attrs: Record<AttrKey, number>;
  doneCount: number;
  critCount: number;
  failCount: number;
  /** 道具持有数（id → 数量） */
  items: Record<string, number>;
  /** 累计 EXP：只增不减（升级扣的是余额，累计不扣） */
  totalExp: number;
}

export function emptyHost(): HostState {
  return {
    name: '宿主',
    lv: 1,
    exp: 0,
    coins: 0,
    streak: 0,
    bestStreak: 0,
    title: 'bind',
    ownedTitles: ['bind'],
    attrs: zeroAttrs(),
    doneCount: 0,
    critCount: 0,
    failCount: 0,
    items: { dbl: 0, crit: 0, shield: 0, patch: 0 },
    totalExp: 0,
  };
}

export function hostToJson(h: HostState): Json {
  return {
    name: h.name,
    lv: h.lv,
    exp: h.exp,
    coins: h.coins,
    streak: h.streak,
    bestStreak: h.bestStreak,
    title: h.title,
    ownedTitles: [...h.ownedTitles],
    attrs: { ...h.attrs },
    doneCount: h.doneCount,
    critCount: h.critCount,
    failCount: h.failCount,
    items: { ...h.items },
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
    coins: Math.max(0, int(v, 'coins', def.coins)),
    streak: Math.max(0, int(v, 'streak', def.streak)),
    bestStreak: Math.max(0, int(v, 'bestStreak', def.bestStreak)),
    title: str(v, 'title', def.title),
    ownedTitles: strList(v, 'ownedTitles', def.ownedTitles),
    attrs: { ...zeroAttrs(), ...attrMap(v, 'attrs', {}) },
    doneCount: Math.max(0, int(v, 'doneCount', 0)),
    critCount: Math.max(0, int(v, 'critCount', 0)),
    failCount: Math.max(0, int(v, 'failCount', 0)),
    items: { ...def.items, ...intMap(v, 'items', {}) },
    totalExp: Math.max(0, int(v, 'totalExp', 0)),
  };
}
