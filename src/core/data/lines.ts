/**
 * 台词库（她说的话 + 固定读数文案）。移植自 flutter-final:app/lib/data/content.dart 与
 * agent/copy.dart 的内置模板池。`[[…]]` 是高亮；`{key}` 是填空位。
 * 按 docs/50 A12，金额符号 ◈ 一律写成文字「晶核」。
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

  /** 执行中她隔一阵子冒一句 */
  exec: [
    '还在？好。',
    '计时没停。你也别停。',
    '别看我，看任务。',
    '快照拍了吗？证据越多，暴击率越高。',
    '我不催。……算了，我催。',
  ],
  /** 剩不到 3 分钟时改成报剩余 */
  execNear: '还剩 [[{t}]]。',
  doze: '……（待机）',

  /** 回来时她记得你走了多久 */
  back10m: '又回来了？……刚走就想我了？不用回答。',
  back2h: '离开了 [[{dur}]]。去干正事了吧。',
  back12h: '[[{dur}]] 没见。我数着呢。——系统的本职工作而已。',
  back36h: '一整天。你知道这一天我在干嘛吗？等。系统没有别的事可干。',
  backLong: '[[{days}]] 天。我差点以为你把我卸载了。……没卸就好。',

  /** 按住认输按到一半松手 */
  waver: ['……犹豫了？', '手抖什么。', '按住。别松。'],

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
  remedyLine: '补救的路，我给你留着：[[{dl}]]前，做一半。做到了，这次不算。',

  /** 用掉一个执行类道具 */
  itemDbl: '双倍卡，挂上了。最好别浪费。',
  itemCrit: '暴击芯片，插好了。运气这东西，买得到一点。',
  itemShield: '护盾，挂上了。到点那一下我替你挡。……你是不是对自己没信心？',
  /** 护盾碎掉、顺延（docs/01 Q3） */
  shieldBreak: '时间到了。护盾碎了，再给你 [[{m}]]。这次没有第二块。',
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

/** 四语气的内置兜底池（LLM 没配 / 失败时用） */
export const COPY = {
  dispatch: [
    LINES.holding,
    '[[{rank}]] 级。[[{name}]]，{minutes}——证据按「{proof}」交。',
    '接住。[[{name}]]。理由我写在单子上了，看完再动。',
    '新单钉上了，[[{rank}]] 级，{minutes}。别让我等。',
  ],
  settleLow: [
    '[[{exp}]] 点经验。有总比没有强。',
    '做完了就算数。晶核 [[{coin}]]，收好。',
    '这就是今天的全部了吗。……算你交了差。',
  ],
  settleMid: [
    '[[{exp}]] EXP 入账。这个速度，勉强能看。',
    '完成确认。晶核 [[{coin}]]——离下一件道具不远了。',
    '不错。但[[{streak}]]连击才是你该守住的数字。',
  ],
  settleHigh: [
    '[[{exp}]] EXP。今天这单，配得上你吹过的牛。',
    '利落。晶核 [[{coin}]] 照付。别飘，明天还有。',
    '完成确认。证据 [[{photos}]] 份，一单比一单像样。',
  ],
  settleTop: [
    'S 级都让你啃下来了。……有点东西。[[{exp}]] EXP、晶核 [[{coin}]]，拿好。',
    '这一单我记进档案了。[[{streak}]] 连击，就是你现在的名字。',
  ],
  roast: [
    '连败 [[{fail}]] 次了。你的字典里是不是没有「吸取教训」这四个字？',
    '连击 [[{streak}]]——最好的时候是 [[{best}]]。自己挑个数字脸红。',
    '空着手来要暴击？我的暴击不给借口。',
    LINES.remedyLine,
    '手里还压着 [[{queue}]] 单。它们不会自己消失。',
  ],
  probe: [
    LINES.askGoal,
    '哪个环节卡住了？[[说具体点]]。',
    '先回答我：这次要[[短平快]]，还是[[上强度]]？',
    '「想换」不算理由。这单哪里不对，[[一样一样说]]。',
  ],
} as const;

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
