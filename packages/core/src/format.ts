/** 时间 / 数字格式。移植自 flutter-final:app/lib/data/format.dart */

/** 1 小时以内 MM:SS，超过 H:MM:SS */
export function fmtClock(ms: number): string {
  const s = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const ss = s % 60;
  return `${h > 0 ? `${h}:` : ''}${String(m).padStart(2, '0')}:${String(ss).padStart(2, '0')}`;
}

/** 25 分钟 / 1 小时 / 1 小时 30 分 */
export function fmtMin(min: number): string {
  if (min < 60) return `${min} 分钟`;
  if (min % 60 !== 0) return `${Math.floor(min / 60)} 小时 ${min % 60} 分`;
  return `${min / 60} 小时`;
}

/** 一段时长：秒 → 分 → 小时 → 天 */
export function fmtDur(ms: number): string {
  const s = Math.max(0, Math.floor(ms / 1000));
  if (s < 60) return `${s} 秒`;
  const m = Math.floor(s / 60);
  if (m < 60) return s % 60 !== 0 ? `${m} 分 ${s % 60} 秒` : `${m} 分`;
  const h = Math.floor(m / 60);
  if (h < 48) return m % 60 !== 0 ? `${h} 小时 ${m % 60} 分` : `${h} 小时`;
  return `${Math.floor(h / 24)} 天`;
}

/** 两位补零 */
export function pad2(n: number): string {
  return String(n).padStart(2, '0');
}
