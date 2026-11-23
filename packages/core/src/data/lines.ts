/**
 * 台词库（她说的话 + 固定读数文案）。移植自 flutter-final:app/lib/data/content.dart。
 * `[[…]]` 是高亮；`{key}` 是填空位。
 */
export const LINES = {
  /** 开机日志；{host} 由存档决定 */
  bootLog: [
    '挂载人格模块 …… 毒舌 ✓',
    '挂载人格模块 …… 靠谱 ✓',
    '校准良心 …… 未找到，跳过',
    '链接宿主档案 …… {host}',
    '唤醒序列就绪',
  ],

  /** 大厅待机碎碎念；{left} 是清单上还没做完的单数 */
  idle: [
    '盯着我看能变强吗？不能。',
    '还差 [[{left}]] 单。清单不会自己变短。',
    '我手里的单不会过期——你的耐心会。',
    '系统在待机。宿主也在待机。这不对吧。',
    '手指别在我身上画圈。我看得见。',
    '你知道吗，我每天都在等这个按钮被按下。',
  ],
  idleNight: '这个点还醒着？那就做点有用的，或者去睡。',
  idleMorning: '早。今天给我争气点。',

  /** 回来时她记得你走了多久 */
  back10m: '又回来了？……刚走就想我了？不用回答。',
  back2h: '离开了 [[{dur}]]。去干正事了吧。',
  back12h: '[[{dur}]] 没见。我数着呢。——系统的本职工作而已。',
  back36h: '一整天。你知道这一天我在干嘛吗？等。系统没有别的事可干。',
  backLong: '[[{days}]] 天。我差点以为你把我卸载了。……没卸就好。',

  /** 戳她 —— 越戳越恼 */
  poke: [
    '……手拿开。',
    '戳系统不会掉经验。',
    '再戳，我就派一单俯卧撑。',
    '宿主，你是不是很闲？',
    '……（她决定无视你）',
  ],

  holding: '我手里有 [[{n}]] 单。都是给你的。',
  askGoal: '说吧。你想变成什么样？[[一句话]]。',
} as const;

/** 主线全景那一句 */
export function mainlineLine(done: number, total: number): string {
  return `[[${done}/${total}]] 单。清单不会自己变短。`;
}

/** 没给停顿时的默认挂留时长：按字数算，夹在 900~2400ms（剥掉 [[ ]] 后的 UTF-16 长度） */
export function defaultHold(text: string): number {
  const s = text.replaceAll('[[', '').replaceAll(']]', '');
  return Math.min(2400, Math.max(900, 420 + s.length * 42));
}

/** 把 {key} 换成值；没给的键保留原样（由调用方保证都给全） */
export function fillLine(template: string, vars: Record<string, string | number>): string {
  return template.replace(/\{(\w+)\}/g, (m, k: string) => (k in vars ? String(vars[k]) : m));
}

/** 确定性选句：种子哈希（同现场稳定，可测） */
export function pickBySeed<T>(pool: readonly T[], seed: string): T {
  let h = 0;
  for (let i = 0; i < seed.length; i++) h = (h * 31 + seed.charCodeAt(i)) & 0x7fffffff;
  return pool[h % pool.length] as T;
}

/** 剥掉 [[ ]] 高亮标记 */
export function plainLine(text: string): string {
  return text.replaceAll('[[', '').replaceAll(']]', '');
}
