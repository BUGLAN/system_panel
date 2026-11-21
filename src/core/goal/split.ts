import type { AttrKey, AttrMap } from '../data/attrs';

/** Dart 的 round()：.5 远离 0（这里只处理非负） */
export function roundHalfUp(x: number): number {
  return Math.floor(x + 0.5);
}

/**
 * 六维点数分配（store.js `splitAttrs`）：按基准权重分 [pts] 点，权重最高的一维至少 1 点，
 * 余数补给第一维。移植自 flutter-final QuestFlow.splitAttrs。
 */
export function splitAttrs(base: AttrMap, pts: number): AttrMap {
  const entries = Object.entries(base) as Array<[AttrKey, number]>;
  if (entries.length === 0) return {};
  const ks = entries.sort((a, b) => b[1] - a[1]).map(([k]) => k);
  const sum = entries.reduce((s, [, v]) => s + v, 0);
  const out: AttrMap = {};
  let left = pts;
  for (let i = 0; i < ks.length; i++) {
    const k = ks[i] as AttrKey;
    const w = base[k] ?? 0;
    const v =
      i === ks.length - 1
        ? left
        : Math.min(left, Math.max(i === 0 ? 1 : 0, roundHalfUp((pts * w) / (sum <= 0 ? 1 : sum))));
    if (v > 0) {
      out[k] = v;
      left -= v;
    }
  }
  const first = ks[0] as AttrKey;
  if (left > 0) out[first] = (out[first] ?? 0) + left;
  return out;
}
