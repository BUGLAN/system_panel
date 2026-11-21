/**
 * 「她记得你走了多久」：按离开时长选一句。移植自 flutter-final:app/lib/state/away.dart。
 * 阈值：≤60 秒不吭声；10 分钟 / 2 小时 / 20 小时 / 48 小时分档。
 */
import { fmtDur } from '../format';
import { LINES } from '../data/lines';

export type AwayKind = 'back10m' | 'back2h' | 'back12h' | 'back36h' | 'backLong';

const MIN = 60_000;
const HOUR = 60 * MIN;

export function awayKind(awayMs: number): AwayKind | null {
  if (awayMs <= MIN) return null;
  if (awayMs > 48 * HOUR) return 'backLong';
  if (awayMs > 20 * HOUR) return 'back36h';
  if (awayMs > 2 * HOUR) return 'back12h';
  if (awayMs > 10 * MIN) return 'back2h';
  return 'back10m';
}

export function awayText(k: AwayKind, awayMs: number): string {
  switch (k) {
    case 'back10m':
      return LINES.back10m;
    case 'back2h':
      return LINES.back2h.replace('{dur}', fmtDur(awayMs));
    case 'back12h':
      return LINES.back12h.replace('{dur}', fmtDur(awayMs));
    case 'back36h':
      return LINES.back36h;
    case 'backLong':
      return LINES.backLong.replace('{days}', String(Math.round(awayMs / (24 * HOUR))));
  }
}

/** 一步到位：不值得说就返回 null */
export function awayLine(awayMs: number): string | null {
  const k = awayKind(awayMs);
  return k ? awayText(k, awayMs) : null;
}
