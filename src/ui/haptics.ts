/** 震动：只在支持 navigator.vibrate 的设备上调用（iOS 不支持，静默跳过） */
export function vibrate(pattern: number | number[]): void {
  try {
    if (typeof navigator !== 'undefined' && typeof navigator.vibrate === 'function')
      navigator.vibrate(pattern);
  } catch {
    /* 有的浏览器在没有用户手势时会抛 */
  }
}

export const haptic = {
  tap: () => vibrate(8),
  success: () => vibrate([12, 40, 18]),
  crit: () => vibrate([20, 30, 40]),
  fail: () => vibrate(60),
};
