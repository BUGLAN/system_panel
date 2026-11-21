/**
 * 称号（12 个）。移植自 flutter-final:app/lib/data/titles.dart。
 * 「口头巨人」是耻辱称号：累计退缩 3 次强制佩戴，摘不掉，完成一单才换回。
 */
export interface HostTitle {
  id: string;
  name: string;
  /** 还没拿到时的提示：？？？ · hint */
  hint: string;
  shame?: boolean;
}

export const TITLES: readonly HostTitle[] = [
  { id: 'bind', name: '新绑定的', hint: '绑定系统' },
  { id: 'first', name: '第一滴汗', hint: '完成第一单' },
  { id: 'crit', name: '被暴击眷顾', hint: '触发一次暴击' },
  { id: 'done5', name: '不算太废', hint: '累计完成 5 单' },
  { id: 'redeem', name: '回头是岸', hint: '完成一次补救' },
  { id: 'streak3', name: '三日不断', hint: '连击 3 天' },
  { id: 'rankA', name: 'A 级经手人', hint: '完成一张 A 级' },
  { id: 'done15', name: '惯犯', hint: '累计完成 15 单' },
  { id: 'streak7', name: '七日不断', hint: '连击 7 天' },
  { id: 'rankS', name: 'S 级幸存者', hint: '完成一张 S 级' },
  { id: 'mouth', name: '口头巨人', hint: '退缩 3 次（不想要也得要）', shame: true },
  { id: 'finale', name: '主线终结者', hint: '走完一整条主线' },
];

export function titleName(id: string): string {
  return TITLES.find((t) => t.id === id)?.name ?? id;
}
