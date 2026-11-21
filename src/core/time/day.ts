/**
 * 本地日历日工具。连胜、换日、补签都按「日历日」判断，用 'YYYY-MM-DD' 字符串存，
 * 避开夏令时与时区换算带来的 23/25 小时问题。
 */
export type DayKey = string;

const RE = /^(\d{4})-(\d{2})-(\d{2})$/;

/** epoch ms → 本地日历日 */
export function dayKey(ms: number): DayKey {
  const d = new Date(ms);
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

export function isDayKey(v: unknown): v is DayKey {
  return typeof v === 'string' && RE.test(v);
}

/** 日历日序号（距 1970-01-01 的天数，按 UTC 算，与本地时区无关） */
function ordinal(k: DayKey): number {
  const m = RE.exec(k);
  if (!m) return NaN;
  return Math.round(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])) / 86_400_000);
}

/** b − a 相差几天（同一天 = 0；b 是 a 的第二天 = 1） */
export function daysBetween(a: DayKey, b: DayKey): number {
  return ordinal(b) - ordinal(a);
}

/** 某日 ± n 天 */
export function addDays(k: DayKey, n: number): DayKey {
  const o = ordinal(k) + n;
  const d = new Date(o * 86_400_000);
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}
