import 'dart:math' as math;

import '../data/rarity.dart';
import 'quest.dart';
import 'quest_flow.dart';
import 'goal.dart';

/// ═══════════════════════════════════════════════════════════
///  目标生成 —— 类型识别 · 访谈卡组 · 首目标 3 天 3 环（docs/18 §2.1，T6-1）
///
///  数据真源：prototype/opus-v2-dir/js/content.js L14-241
///    `CATS` / `CAT_ORDER` / `DAILY_COMMON` / `VAGUE`
///  规则真源：prototype/opus-v2-dir/js/store.js `shortOf()` / `makeGoal()`
///
///  绑定流：问目标 → `detectCategory` 识别类型 → `interviewCardsFor` 出
///  3~5 张访谈卡 → 答案三用：
///    ① 定制首目标环参数（`buildFirstGoal`，负担重则第 1 环更轻）
///    ② 选定日常任务池（`dailyPoolFor`，周期任务生成模块读取）
///    ③ 导出小祥长期记忆（`memoriesFromInterview`，T5 memory 用）
///  首次新目标固定 **3 天 3 环（E/D/C）**，每天一环，验证「能坚持」再展开长链。
/// ═══════════════════════════════════════════════════════════

/// 首目标周期（天）—— 宿主钦定：首次新目标 = 3 天。
const int kFirstGoalDays = 3;

/// 首目标三环的档位 —— E/D/C，全部低门槛高胜率（对齐「前 10 任务必胜」精神）。
const List<String> kFirstGoalRanks = <String>['E', 'D', 'C'];

/// 绑定仪式的目标预设（原型 flows.js L126 原样六条）
const List<String> kOnboardPresets = <String>[
  '三个月跑完半马',
  '一个月早睡早起',
  '考研上岸',
  '半年减重 10 斤',
  '学会画画',
  '变优秀',
];

/// 一张访谈卡：一个问题 + 3~4 个选项 chip（「自己写」由组件兜底提供）。
class InterviewCard {
  const InterviewCard({
    required this.id,
    required this.question,
    required this.options,
  });

  /// 卡 id（存档与答案映射的键，如 `sleep.schedule`）
  final String id;

  final String question;

  /// 3~4 个现成选项
  final List<String> options;
}

/// 首目标的环参数（生成 `GoalRing` 的原料）。
class RingSpec {
  const RingSpec({
    required this.short,
    required this.title,
    required this.proof,
    required this.minutes,
    required this.rank,
  });

  final String short;
  final String title;
  final String proof;
  final int minutes;
  final String rank;
}

/// 日常任务模板（原型 `CATS.daily` / `DAILY_COMMON`）——
/// 周期任务生成（T6-2/T8）按目标类型取池的原料。
class DailyTemplate {
  const DailyTemplate({
    required this.title,
    required this.proof,
    required this.minutes,
    required this.attrs,
    required this.rank,
  });

  final String title;
  final String proof;
  final int minutes;
  final Map<String, int> attrs;
  final String rank;
}

/// 目标类型（原型 `CATS` 十类）。
class GoalCategory {
  const GoalCategory({
    required this.id,
    required this.label,
    required this.short,
    required this.pattern,
    required this.tilt,
    required this.cards,
    required this.firstRings,
    required this.daily,
    this.lightRing,
  });

  final String id;
  final String label;

  /// 天幕短字的类别兜底（`shortOfGoal` 用）
  final String short;

  /// 关键词识别（原型 `CATS[k].re`）
  final RegExp pattern;

  /// 六维倾向（v4 换血后的 力/敏/体/智/知/魅）
  final Map<String, int> tilt;

  /// 类别专属访谈卡（3 张；等级更高时 `interviewCardsFor` 会追加通用卡）
  final List<InterviewCard> cards;

  /// 首目标 3 环基准参数（顺序 = E/D/C，天数控到 §2.3 建议时限内）
  final List<RingSpec> firstRings;

  /// 该类日常池
  final List<DailyTemplate> daily;

  /// 访谈显示「负担重」时替换第 1 环的更轻版本（sleep 示例见 docs/18 §2.1）
  final RingSpec? lightRing;
}

// ── 十类全表（content.js L34-220 逐类移植；首环档位按 E/D/C 重排） ──

final GoalCategory _catRun = GoalCategory(
  id: 'run',
  label: '奔跑',
  short: '奔跑',
  pattern: RegExp(r'跑|马拉松|半马|全马|公里|km|配速|5k|10k', caseSensitive: false),
  tilt: const <String, int>{'体': 2, '敏': 1, '力': 1},
  cards: const <InterviewCard>[
    InterviewCard(
      id: 'run.now',
      question: '现在能跑多远？',
      options: <String>['3 公里以内', '3~5 公里', '5 公里以上', '没跑过'],
    ),
    InterviewCard(
      id: 'run.freq',
      question: '一周跑几次？',
      options: <String>['1~2 次', '3~4 次', '5 次以上', '不一定'],
    ),
    InterviewCard(
      id: 'run.slot',
      question: '愿意每周留几个跑步时段？',
      options: <String>['2 个', '3~4 个', '5 个以上'],
    ),
  ],
  firstRings: const <RingSpec>[
    RingSpec(
      short: '穿上跑鞋',
      title: '换上跑鞋，出门快走 15 分钟',
      proof: '运动 App 记录或出门自拍',
      minutes: 15,
      rank: 'E',
    ),
    RingSpec(
      short: '第一公里',
      title: '慢跑 1 公里。可以慢，不许停',
      proof: '跑步 App 截图',
      minutes: 20,
      rank: 'D',
    ),
    RingSpec(
      short: '两公里不停',
      title: '慢跑 2 公里，中途不走路',
      proof: '跑步 App 截图',
      minutes: 25,
      rank: 'C',
    ),
  ],
  daily: const <DailyTemplate>[
    DailyTemplate(
      title: '原地高抬腿 3 组，每组 40 秒',
      proof: '计时截图',
      minutes: 8,
      attrs: <String, int>{'敏': 1, '体': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '慢跑 1.5 公里',
      proof: '跑步 App 截图',
      minutes: 20,
      attrs: <String, int>{'体': 1, '敏': 1},
      rank: 'E',
    ),
    DailyTemplate(
      title: '跑后拉伸 10 分钟，一个动作都别省',
      proof: '拉伸照片',
      minutes: 12,
      attrs: <String, int>{'敏': 2},
      rank: 'F',
    ),
    DailyTemplate(
      title: '间歇跑：快 1 分钟 + 慢 2 分钟，五轮',
      proof: '跑步 App 截图',
      minutes: 20,
      attrs: <String, int>{'体': 1, '敏': 1},
      rank: 'D',
    ),
    DailyTemplate(
      title: '跑前热身 8 分钟，一个动作都别省',
      proof: '拉伸照片',
      minutes: 8,
      attrs: <String, int>{'敏': 1, '体': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '匀速跑 3 公里，配速别忽快忽慢',
      proof: '跑步 App 截图',
      minutes: 25,
      attrs: <String, int>{'体': 2},
      rank: 'D',
    ),
    DailyTemplate(
      title: '深蹲 3 组 × 20，练腿不练腿跑不远',
      proof: '计数截图',
      minutes: 10,
      attrs: <String, int>{'力': 1, '体': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '走满 6000 步，就当放松跑',
      proof: '步数截图',
      minutes: 45,
      attrs: <String, int>{'体': 1, '敏': 1},
      rank: 'E',
    ),
  ],
);

final GoalCategory _catSlim = GoalCategory(
  id: 'slim',
  label: '轻盈',
  short: '轻盈',
  pattern: RegExp(r'减肥|减重|减脂|瘦|斤|体重|体脂|腰围'),
  tilt: const <String, int>{'体': 2, '知': 1, '力': 1},
  cards: const <InterviewCard>[
    InterviewCard(
      id: 'slim.target',
      question: '想先减下多少？',
      options: <String>['2~3 斤', '5 斤左右', '10 斤以上', '没称过，先记录'],
    ),
    InterviewCard(
      id: 'slim.diet',
      question: '最近吃得怎么样？',
      options: <String>['三餐规律', '经常外卖', '宵夜不断'],
    ),
    InterviewCard(
      id: 'slim.move',
      question: '现在动多少？',
      options: <String>['基本不动', '偶尔走走', '每周有运动习惯'],
    ),
  ],
  firstRings: const <RingSpec>[
    RingSpec(
      short: '称重',
      title: '早上空腹称一次体重，记下来',
      proof: '体重秤照片',
      minutes: 5,
      rank: 'E',
    ),
    RingSpec(
      short: '少一杯',
      title: '今天不喝含糖饮料，一杯都不',
      proof: '晚上拍一张今天喝过的东西',
      minutes: 10,
      rank: 'D',
    ),
    RingSpec(
      short: '走路',
      title: '走满 8000 步',
      proof: '步数截图',
      minutes: 30,
      rank: 'C',
    ),
  ],
  daily: const <DailyTemplate>[
    DailyTemplate(
      title: '喝够 6 杯水，别拿饮料凑数',
      proof: '杯子照片',
      minutes: 10,
      attrs: <String, int>{'体': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '饭后散步 20 分钟',
      proof: '步数截图',
      minutes: 25,
      attrs: <String, int>{'体': 1, '敏': 1},
      rank: 'E',
    ),
    DailyTemplate(
      title: '晚饭吃到七分饱，拍一张',
      proof: '饭菜照片',
      minutes: 30,
      attrs: <String, int>{'知': 1, '体': 1},
      rank: 'E',
    ),
    DailyTemplate(
      title: '跳绳 800 下',
      proof: '计数截图',
      minutes: 15,
      attrs: <String, int>{'体': 1, '敏': 1},
      rank: 'D',
    ),
    DailyTemplate(
      title: '晚饭后站 15 分钟，别一吃完就坐下',
      proof: '计时截图',
      minutes: 15,
      attrs: <String, int>{'体': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '把今天吃的东西拍下来，一顿都别漏',
      proof: '饭菜照片',
      minutes: 10,
      attrs: <String, int>{'知': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '走满 8000 步',
      proof: '步数截图',
      minutes: 50,
      attrs: <String, int>{'体': 2},
      rank: 'D',
    ),
    DailyTemplate(
      title: '睡前不吃东西，渴了只喝水',
      proof: '计时截图',
      minutes: 5,
      attrs: <String, int>{'知': 1, '体': 1},
      rank: 'F',
    ),
  ],
);

final GoalCategory _catFit = GoalCategory(
  id: 'fit',
  label: '力量',
  short: '力量',
  pattern: RegExp(r'健身|增肌|肌肉|俯卧撑|引体|腹肌|深蹲|力量|撸铁|练'),
  tilt: const <String, int>{'力': 2, '体': 1},
  cards: const <InterviewCard>[
    InterviewCard(
      id: 'fit.base',
      question: '现在能做几个俯卧撑？',
      options: <String>['一个都费劲', '10 个以内', '20 个以上'],
    ),
    InterviewCard(
      id: 'fit.freq',
      question: '一周想练几次？',
      options: <String>['1~2 次', '3~4 次', '5 次以上'],
    ),
    InterviewCard(
      id: 'fit.place',
      question: '在哪练？',
      options: <String>['家里徒手', '健身房', '都行'],
    ),
  ],
  firstRings: const <RingSpec>[
    RingSpec(
      short: '第一组',
      title: '做 10 个俯卧撑（跪姿也算）',
      proof: '自拍或计数截图',
      minutes: 10,
      rank: 'E',
    ),
    RingSpec(
      short: '三组成型',
      title: '俯卧撑 3 组 × 10，组间休息 60 秒',
      proof: '计数截图',
      minutes: 15,
      rank: 'D',
    ),
    RingSpec(
      short: '核心',
      title: '平板支撑累计 3 分钟',
      proof: '计时截图',
      minutes: 12,
      rank: 'C',
    ),
  ],
  daily: const <DailyTemplate>[
    DailyTemplate(
      title: '20 个深蹲，慢下快起',
      proof: '自拍或计数截图',
      minutes: 6,
      attrs: <String, int>{'力': 1, '体': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '平板支撑 3 组 × 45 秒',
      proof: '计时截图',
      minutes: 8,
      attrs: <String, int>{'力': 1, '体': 1},
      rank: 'E',
    ),
    DailyTemplate(
      title: '拉伸 10 分钟',
      proof: '拉伸照片',
      minutes: 12,
      attrs: <String, int>{'敏': 2},
      rank: 'F',
    ),
    DailyTemplate(
      title: '俯卧撑 4 组 × 12',
      proof: '计数截图',
      minutes: 15,
      attrs: <String, int>{'力': 2},
      rank: 'D',
    ),
    DailyTemplate(
      title: '深蹲 3 组 × 15，膝盖别内扣',
      proof: '计数截图',
      minutes: 10,
      attrs: <String, int>{'力': 1, '体': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '平板支撑 3 组 × 45 秒',
      proof: '计时截图',
      minutes: 8,
      attrs: <String, int>{'力': 1, '体': 1},
      rank: 'E',
    ),
    DailyTemplate(
      title: '练完拉伸 10 分钟，明天才起得来',
      proof: '拉伸照片',
      minutes: 12,
      attrs: <String, int>{'敏': 2},
      rank: 'F',
    ),
    DailyTemplate(
      title: '靠墙静蹲 3 组 × 60 秒',
      proof: '计时截图',
      minutes: 10,
      attrs: <String, int>{'力': 1, '体': 1},
      rank: 'D',
    ),
  ],
);

final GoalCategory _catLang = GoalCategory(
  id: 'lang',
  label: '开口',
  short: '开口',
  pattern: RegExp(r'英语|日语|韩语|法语|德语|单词|口语|听力|六级|四级|雅思|托福|N[1-3]|外语', caseSensitive: false),
  tilt: const <String, int>{'智': 2, '魅': 1},
  cards: const <InterviewCard>[
    InterviewCard(
      id: 'lang.level',
      question: '现在什么水平？',
      options: <String>['零基础', '能读不能说', '口语还行，想进阶'],
    ),
    InterviewCard(
      id: 'lang.exam',
      question: '有没有考试目标？',
      options: <String>['四六级', '雅思托福', '没有，纯兴趣'],
    ),
    InterviewCard(
      id: 'lang.daily',
      question: '每天能背多少词？',
      options: <String>['20 个', '50 个', '量翻倍也要冲'],
    ),
  ],
  firstRings: const <RingSpec>[
    RingSpec(
      short: '第一页',
      title: '背 20 个新词',
      proof: '背词 App 截图',
      minutes: 15,
      rank: 'E',
    ),
    RingSpec(
      short: '跟读',
      title: '跟读一段 3 分钟的音频',
      proof: '录音截图',
      minutes: 15,
      rank: 'D',
    ),
    RingSpec(
      short: '五十词',
      title: '一天背完 50 个新词并复习昨天的',
      proof: '背词 App 截图',
      minutes: 30,
      rank: 'C',
    ),
  ],
  daily: const <DailyTemplate>[
    DailyTemplate(
      title: '背 30 个单词',
      proof: '背词 App 截图',
      minutes: 25,
      attrs: <String, int>{'智': 2},
      rank: 'E',
    ),
    DailyTemplate(
      title: '跟读 5 分钟',
      proof: '录音截图',
      minutes: 10,
      attrs: <String, int>{'魅': 1, '智': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '看一集无中文字幕的短视频',
      proof: '截图',
      minutes: 15,
      attrs: <String, int>{'智': 1, '知': 1},
      rank: 'E',
    ),
    DailyTemplate(
      title: '用外语写今天的三行日记',
      proof: '照片',
      minutes: 15,
      attrs: <String, int>{'智': 1, '魅': 1},
      rank: 'D',
    ),
    DailyTemplate(
      title: '背 15 个新词，晚上再过一遍',
      proof: '背词 App 截图',
      minutes: 20,
      attrs: <String, int>{'智': 2},
      rank: 'E',
    ),
    DailyTemplate(
      title: '听一段 3 分钟音频，听不懂也听完',
      proof: '音频 App 截图',
      minutes: 10,
      attrs: <String, int>{'智': 1, '知': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '大声朗读一段短文，读顺为止',
      proof: '录音截图',
      minutes: 15,
      attrs: <String, int>{'魅': 1, '智': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '把昨天背的 20 个词默写一遍',
      proof: '默写照片',
      minutes: 20,
      attrs: <String, int>{'智': 1, '知': 1},
      rank: 'D',
    ),
  ],
);

final GoalCategory _catExam = GoalCategory(
  id: 'exam',
  label: '上岸',
  short: '上岸',
  pattern: RegExp(r'考研|考公|考编|考证|考试|上岸|复习|期末|高考|学习|刷题|备考'),
  tilt: const <String, int>{'智': 2, '知': 1},
  cards: const <InterviewCard>[
    InterviewCard(
      id: 'exam.stage',
      question: '备考到什么阶段了？',
      options: <String>['刚开始', '过了一半', '快考试了'],
    ),
    InterviewCard(
      id: 'exam.hours',
      question: '现在每天学多久？',
      options: <String>['1 小时以内', '2~3 小时', '4 小时以上'],
    ),
    InterviewCard(
      id: 'exam.weak',
      question: '最弱的是哪块？',
      options: <String>['专业课', '英语', '政治 / 公共课'],
    ),
  ],
  firstRings: const <RingSpec>[
    RingSpec(
      short: '清桌',
      title: '清空书桌，只留下要用的一本书',
      proof: '书桌照片',
      minutes: 10,
      rank: 'E',
    ),
    RingSpec(
      short: '第一个番茄',
      title: '专注学习 25 分钟，手机扣在桌上',
      proof: '计时截图 + 书页照片',
      minutes: 20,
      rank: 'D',
    ),
    RingSpec(
      short: '一章',
      title: '啃完一章，写出 5 条要点',
      proof: '笔记照片',
      minutes: 30,
      rank: 'C',
    ),
  ],
  daily: const <DailyTemplate>[
    DailyTemplate(
      title: '专注 25 分钟，手机扣在桌上',
      proof: '计时截图',
      minutes: 30,
      attrs: <String, int>{'智': 1, '知': 1},
      rank: 'E',
    ),
    DailyTemplate(
      title: '背 30 个知识点 / 单词',
      proof: '进度截图',
      minutes: 25,
      attrs: <String, int>{'智': 2},
      rank: 'E',
    ),
    DailyTemplate(
      title: '把昨天的错题重做一遍',
      proof: '错题照片',
      minutes: 30,
      attrs: <String, int>{'智': 1, '知': 1},
      rank: 'D',
    ),
    DailyTemplate(
      title: '睡前 10 分钟回忆今天学了什么，写三行',
      proof: '笔记照片',
      minutes: 12,
      attrs: <String, int>{'知': 2},
      rank: 'F',
    ),
    DailyTemplate(
      title: '清空书桌，只留下今天要用的那本书',
      proof: '书桌照片',
      minutes: 10,
      attrs: <String, int>{'知': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '做完一套 10 题的小测，错题当场订正',
      proof: '题目照片',
      minutes: 35,
      attrs: <String, int>{'智': 2},
      rank: 'D',
    ),
    DailyTemplate(
      title: '把最近 5 道错题重做一遍',
      proof: '错题本照片',
      minutes: 25,
      attrs: <String, int>{'智': 1, '知': 1},
      rank: 'E',
    ),
    DailyTemplate(
      title: '限时 25 分钟专注，手机扣在桌上',
      proof: '计时截图',
      minutes: 30,
      attrs: <String, int>{'智': 1, '知': 1},
      rank: 'E',
    ),
  ],
);

final GoalCategory _catSleep = GoalCategory(
  id: 'sleep',
  label: '早起',
  short: '早起',
  pattern: RegExp(r'早睡|早起|作息|熬夜|睡眠|睡觉|起床'),
  tilt: const <String, int>{'体': 2, '知': 1},
  cards: const <InterviewCard>[
    // docs/18 §2.1 示例卡组（早睡早起）——三张原样
    InterviewCard(
      id: 'sleep.schedule',
      question: '现在几点起、几点睡？',
      options: <String>['0 点前睡 7 点前起', '0-1 点睡 8 点起', '1-2 点睡 9 点后起', '没有固定'],
    ),
    InterviewCard(
      id: 'sleep.recent',
      question: '最近几天作息如何？',
      options: <String>['基本规律', '偶尔熬夜', '天天熬夜'],
    ),
    InterviewCard(
      id: 'sleep.persist',
      question: '愿意做怎样的坚持？',
      options: <String>['每天早睡 15 分钟', '固定起床闹钟', '午休不超 30 分钟', '睡前不碰手机'],
    ),
  ],
  firstRings: const <RingSpec>[
    RingSpec(
      short: '定闹钟',
      title: '定好明早的闹钟，手机放到够不着的地方',
      proof: '闹钟截图 + 手机位置照片',
      minutes: 5,
      rank: 'E',
    ),
    RingSpec(
      short: '23:30',
      title: '今晚 23:30 前放下手机上床',
      proof: '屏幕使用时间截图',
      minutes: 20,
      rank: 'D',
    ),
    RingSpec(
      short: '不赖床',
      title: '闹钟响后 5 分钟内起床',
      proof: '起床时间截图',
      minutes: 10,
      rank: 'C',
    ),
  ],
  // 「天天熬夜」这类答案 → 第 1 环从更轻的 E 级起步（docs/18 §2.1）
  lightRing: const RingSpec(
    short: '先早一点',
    title: '比昨天早睡 15 分钟',
    proof: '屏幕使用时间截图',
    minutes: 10,
    rank: 'E',
  ),
  daily: const <DailyTemplate>[
    DailyTemplate(
      title: '睡前 30 分钟不碰手机',
      proof: '屏幕使用时间截图',
      minutes: 35,
      attrs: <String, int>{'知': 1, '体': 1},
      rank: 'E',
    ),
    DailyTemplate(
      title: '起床后立刻叠被子',
      proof: '床铺照片',
      minutes: 5,
      attrs: <String, int>{'知': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '午后不喝咖啡和茶',
      proof: '晚上拍一张今天喝过的东西',
      minutes: 10,
      attrs: <String, int>{'体': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '晚上 22:30 关掉所有屏幕',
      proof: '截图',
      minutes: 15,
      attrs: <String, int>{'体': 1, '知': 1},
      rank: 'D',
    ),
    DailyTemplate(
      title: '起床后 10 分钟内拉开窗帘，见一次光',
      proof: '窗外照片',
      minutes: 5,
      attrs: <String, int>{'体': 1, '知': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '手机放到够不着的地方充电，一晚上别碰',
      proof: '手机位置照片',
      minutes: 5,
      attrs: <String, int>{'知': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '午睡不超过 30 分钟',
      proof: '计时截图',
      minutes: 30,
      attrs: <String, int>{'体': 1, '知': 1},
      rank: 'E',
    ),
    DailyTemplate(
      title: '今天不喝咖啡和浓茶，晚上才睡得着',
      proof: '晚上拍一张今天喝过的东西',
      minutes: 5,
      attrs: <String, int>{'知': 1, '体': 1},
      rank: 'F',
    ),
  ],
);

final GoalCategory _catMake = GoalCategory(
  id: 'make',
  label: '作品',
  short: '作品',
  pattern: RegExp(r'画|绘|写作|小说|文章|摄影|拍照|视频|剪辑|作曲|吉他|钢琴|唱歌|创作|设计|手账|插画'),
  tilt: const <String, int>{'智': 1, '魅': 1, '敏': 1},
  cards: const <InterviewCard>[
    InterviewCard(
      id: 'make.level',
      question: '现在是什么水平？',
      options: <String>['纯新手', '会一点', '有作品'],
    ),
    InterviewCard(
      id: 'make.freq',
      question: '一周能创作几次？',
      options: <String>['1~2 次', '3~4 次', '几乎每天'],
    ),
    InterviewCard(
      id: 'make.first',
      question: '想先做出什么？',
      options: <String>['一件完整小作品', '先养成日常习惯', '能给人看'],
    ),
  ],
  firstRings: const <RingSpec>[
    RingSpec(
      short: '打开工具',
      title: '打开工具，随便做 10 分钟',
      proof: '过程截图',
      minutes: 15,
      rank: 'E',
    ),
    RingSpec(
      short: '临摹',
      title: '临摹一个你喜欢的作品 30 分钟',
      proof: '作品照片',
      minutes: 20,
      rank: 'D',
    ),
    RingSpec(
      short: '小练习',
      title: '完成一个 45 分钟的小练习',
      proof: '作品照片',
      minutes: 30,
      rank: 'C',
    ),
  ],
  daily: const <DailyTemplate>[
    DailyTemplate(
      title: '速写 / 速记 15 分钟',
      proof: '照片',
      minutes: 18,
      attrs: <String, int>{'敏': 1, '智': 1},
      rank: 'E',
    ),
    DailyTemplate(
      title: '收集 5 个你喜欢的参考',
      proof: '收藏截图',
      minutes: 15,
      attrs: <String, int>{'知': 2},
      rank: 'F',
    ),
    DailyTemplate(
      title: '练一个最弱的基本功 20 分钟',
      proof: '照片',
      minutes: 25,
      attrs: <String, int>{'敏': 1, '智': 1},
      rank: 'D',
    ),
    DailyTemplate(
      title: '写下三个作品点子',
      proof: '笔记照片',
      minutes: 10,
      attrs: <String, int>{'智': 1, '魅': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '临摹一张你喜欢的图，10 分钟就够',
      proof: '过程截图',
      minutes: 15,
      attrs: <String, int>{'智': 1, '敏': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '写 200 字，写完不回头改',
      proof: '文字截图',
      minutes: 20,
      attrs: <String, int>{'智': 1, '魅': 1},
      rank: 'E',
    ),
    DailyTemplate(
      title: '把一个旧作品翻出来，挑三个毛病',
      proof: '笔记照片',
      minutes: 15,
      attrs: <String, int>{'知': 1, '智': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '做一个 15 分钟内能做完的小练习',
      proof: '成品照片',
      minutes: 20,
      attrs: <String, int>{'智': 1, '敏': 1},
      rank: 'D',
    ),
  ],
);

final GoalCategory _catCode = GoalCategory(
  id: 'code',
  label: '上线',
  short: '上线',
  pattern: RegExp(r'编程|代码|程序|算法|开发|项目|前端|后端|上线|leetcode|刷题|App|独立', caseSensitive: false),
  tilt: const <String, int>{'智': 2, '知': 1},
  cards: const <InterviewCard>[
    InterviewCard(
      id: 'code.level',
      question: '现在什么水平？',
      options: <String>['刚入门', '能写小项目', '想提升架构'],
    ),
    InterviewCard(
      id: 'code.dir',
      question: '想往哪个方向走？',
      options: <String>['算法刷题', '做一个完整项目', '找工作备战'],
    ),
    InterviewCard(
      id: 'code.daily',
      question: '每天能投入多久？',
      options: <String>['30 分钟', '1~2 小时', '3 小时以上'],
    ),
  ],
  firstRings: const <RingSpec>[
    RingSpec(
      short: '环境',
      title: '把开发环境跑起来，输出一行 Hello',
      proof: '终端截图',
      minutes: 15,
      rank: 'E',
    ),
    RingSpec(
      short: '一题',
      title: '做出一道算法题',
      proof: '提交通过截图',
      minutes: 20,
      rank: 'D',
    ),
    RingSpec(
      short: '一个功能',
      title: '写完一个能跑的小功能',
      proof: '运行截图',
      minutes: 30,
      rank: 'C',
    ),
  ],
  daily: const <DailyTemplate>[
    DailyTemplate(
      title: '写 30 分钟代码，不切出去刷别的',
      proof: '编辑器截图',
      minutes: 35,
      attrs: <String, int>{'智': 1, '知': 1},
      rank: 'E',
    ),
    DailyTemplate(
      title: '做一道简单算法题',
      proof: '提交通过截图',
      minutes: 25,
      attrs: <String, int>{'智': 2},
      rank: 'E',
    ),
    DailyTemplate(
      title: '读一篇技术文章并写三行笔记',
      proof: '笔记截图',
      minutes: 20,
      attrs: <String, int>{'智': 1, '知': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '清掉一个 TODO',
      proof: '提交截图',
      minutes: 30,
      attrs: <String, int>{'智': 1, '知': 1},
      rank: 'D',
    ),
    DailyTemplate(
      title: '读 20 分钟官方文档，读不懂也读完一节',
      proof: '文档截图',
      minutes: 25,
      attrs: <String, int>{'智': 2},
      rank: 'E',
    ),
    DailyTemplate(
      title: '把今天踩的坑写进笔记，三行就够',
      proof: '笔记照片',
      minutes: 12,
      attrs: <String, int>{'知': 1, '智': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '重构一个函数，只改一处也行',
      proof: 'diff 截图',
      minutes: 30,
      attrs: <String, int>{'智': 1, '知': 1},
      rank: 'D',
    ),
    DailyTemplate(
      title: '写下下一步要做的三件事，只写三件',
      proof: '清单照片',
      minutes: 10,
      attrs: <String, int>{'知': 1},
      rank: 'F',
    ),
  ],
);

final GoalCategory _catBold = GoalCategory(
  id: 'bold',
  label: '自信',
  short: '自信',
  pattern: RegExp(r'自信|社交|演讲|表达|脱单|搭讪|内向|沟通|社恐|说话|主持'),
  tilt: const <String, int>{'魅': 2, '知': 1},
  cards: const <InterviewCard>[
    InterviewCard(
      id: 'bold.scene',
      question: '最想突破哪个场景？',
      options: <String>['当众讲话', '主动搭话', '线上表达'],
    ),
    InterviewCard(
      id: 'bold.now',
      question: '现在什么状态？',
      options: <String>['能躲就躲', '硬着头皮上', '还行，想更强'],
    ),
    InterviewCard(
      id: 'bold.step',
      question: '愿意从多小的一步开始？',
      options: <String>['打招呼就行', '主动开口一次', '直接挑战演讲'],
    ),
  ],
  firstRings: const <RingSpec>[
    RingSpec(
      short: '对镜子',
      title: '对着镜子大声说一段 1 分钟的自我介绍',
      proof: '录音截图',
      minutes: 8,
      rank: 'E',
    ),
    RingSpec(
      short: '先开口',
      title: '今天主动和一个人打招呼',
      proof: '写一句发生了什么',
      minutes: 10,
      rank: 'D',
    ),
    RingSpec(
      short: '问一个问题',
      title: '主动问店员 / 同事一个问题',
      proof: '写一句发生了什么',
      minutes: 10,
      rank: 'C',
    ),
  ],
  daily: const <DailyTemplate>[
    DailyTemplate(
      title: '给一个很久没联系的人发条消息',
      proof: '对话截图（可打码）',
      minutes: 8,
      attrs: <String, int>{'魅': 2},
      rank: 'E',
    ),
    DailyTemplate(
      title: '对着镜子练习微笑并说"你好"十次',
      proof: '自拍（可不露脸）',
      minutes: 5,
      attrs: <String, int>{'魅': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '在群里说一句话',
      proof: '截图',
      minutes: 5,
      attrs: <String, int>{'魅': 1, '知': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '夸一个人，具体地夸',
      proof: '对话截图',
      minutes: 8,
      attrs: <String, int>{'魅': 1, '知': 1},
      rank: 'E',
    ),
    DailyTemplate(
      title: '抬头挺胸走 10 分钟，别低头看手机',
      proof: '计时截图',
      minutes: 12,
      attrs: <String, int>{'魅': 1, '体': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '对着镜子练 3 分钟的开场白',
      proof: '录音或录像截图',
      minutes: 8,
      attrs: <String, int>{'魅': 2},
      rank: 'F',
    ),
    DailyTemplate(
      title: '在群里发一次言，说点有用的',
      proof: '对话截图（可打码）',
      minutes: 10,
      attrs: <String, int>{'魅': 1, '知': 1},
      rank: 'E',
    ),
    DailyTemplate(
      title: '把一件没做完的小事今天了结掉',
      proof: '完成截图',
      minutes: 20,
      attrs: <String, int>{'知': 1, '魅': 1},
      rank: 'D',
    ),
  ],
);

final GoalCategory _catGen = GoalCategory(
  id: 'gen',
  label: '变强',
  short: '变强',
  pattern: RegExp(r'.*'),
  tilt: const <String, int>{'知': 1, '体': 1, '智': 1},
  cards: const <InterviewCard>[
    InterviewCard(
      id: 'gen.area',
      question: '最想在哪个方面变强？',
      options: <String>['身体', '头脑', '习惯', '收入'],
    ),
    InterviewCard(
      id: 'gen.time',
      question: '现在每天能自由支配多久？',
      options: <String>['30 分钟', '1~2 小时', '3 小时以上'],
    ),
    InterviewCard(
      id: 'gen.first',
      question: '愿意先从哪件小事开始？',
      options: <String>['每天固定 20 分钟', '一周试 3 次', '先做一次看看'],
    ),
  ],
  firstRings: const <RingSpec>[
    RingSpec(
      short: '写下来',
      title: '把目标写在纸上，拍照',
      proof: '纸条照片',
      minutes: 5,
      rank: 'E',
    ),
    RingSpec(
      short: '第一步',
      title: '花 20 分钟做目标的第一件具体的事',
      proof: '过程截图',
      minutes: 20,
      rank: 'D',
    ),
    RingSpec(
      short: '拆解',
      title: '把目标拆成 10 个小步骤写下来',
      proof: '照片',
      minutes: 30,
      rank: 'C',
    ),
  ],
  daily: const <DailyTemplate>[
    DailyTemplate(
      title: '为今天定一个 15 分钟的小目标，做完就算赢',
      proof: '完成截图',
      minutes: 20,
      attrs: <String, int>{'知': 1, '智': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '丢掉一件早该丢的东西',
      proof: '前后对比照片',
      minutes: 10,
      attrs: <String, int>{'知': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '学一个用得上的小技巧，今天就用一次',
      proof: '截图',
      minutes: 15,
      attrs: <String, int>{'智': 1, '敏': 1},
      rank: 'E',
    ),
    DailyTemplate(
      title: '出门走 20 分钟，不带耳机',
      proof: '步数截图',
      minutes: 25,
      attrs: <String, int>{'体': 1, '知': 1},
      rank: 'E',
    ),
    DailyTemplate(
      title: '把拖了三天的那件事先做 10 分钟',
      proof: '完成截图',
      minutes: 15,
      attrs: <String, int>{'知': 1, '智': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '早睡 30 分钟，就今晚',
      proof: '屏幕使用时间截图',
      minutes: 5,
      attrs: <String, int>{'体': 1, '知': 1},
      rank: 'F',
    ),
    DailyTemplate(
      title: '做 20 个深蹲 + 20 个开合跳',
      proof: '计数截图',
      minutes: 8,
      attrs: <String, int>{'力': 1, '体': 1},
      rank: 'E',
    ),
    DailyTemplate(
      title: '写下一件今天做得还行的事，一句就够',
      proof: '文字截图',
      minutes: 8,
      attrs: <String, int>{'魅': 1, '知': 1},
      rank: 'F',
    ),
  ],
);

/// 识别顺序即优先级（content.js L221）——`gen` 兜底必须排最后。
final List<GoalCategory> kGoalCatOrder = <GoalCategory>[
  _catRun,
  _catSlim,
  _catFit,
  _catLang,
  _catExam,
  _catSleep,
  _catMake,
  _catCode,
  _catBold,
  _catGen,
];

final Map<String, GoalCategory> goalCats = <String, GoalCategory>{
  for (final GoalCategory c in kGoalCatOrder) c.id: c,
};

/// 通用日常池（content.js L224-239）—— 任何主线的日常都混进来补短板。
const List<DailyTemplate> kDailyCommon = <DailyTemplate>[
  DailyTemplate(
    title: '整理桌面，只留今天要用的东西',
    proof: '桌面照片',
    minutes: 10,
    attrs: <String, int>{'知': 1},
    rank: 'F',
  ),
  DailyTemplate(title: '出门走 3000 步', proof: '步数截图', minutes: 30, attrs: <String, int>{'体': 1, '敏': 1}, rank: 'E'),
  DailyTemplate(title: '读 20 页书', proof: '页码照片', minutes: 30, attrs: <String, int>{'智': 1, '知': 1}, rank: 'E'),
  DailyTemplate(title: '发呆 10 分钟，不碰手机', proof: '计时截图', minutes: 12, attrs: <String, int>{'知': 2}, rank: 'F'),
  DailyTemplate(
    title: '给一个很久没联系的人发条消息',
    proof: '对话截图（可打码）',
    minutes: 8,
    attrs: <String, int>{'魅': 2},
    rank: 'E',
  ),
  DailyTemplate(title: '20 个深蹲', proof: '自拍或计数截图', minutes: 6, attrs: <String, int>{'力': 1, '体': 1}, rank: 'F'),
  DailyTemplate(
    title: '把一件拖了一周的小事做完',
    proof: '完成截图',
    minutes: 25,
    attrs: <String, int>{'知': 1, '智': 1},
    rank: 'D',
  ),
  DailyTemplate(title: '拉伸 10 分钟', proof: '拉伸照片', minutes: 12, attrs: <String, int>{'敏': 2}, rank: 'F'),
  DailyTemplate(
    title: '平板支撑累计 3 分钟',
    proof: '计时截图',
    minutes: 10,
    attrs: <String, int>{'力': 1, '体': 1},
    rank: 'E',
  ),
  DailyTemplate(title: '写 300 字，写什么都行', proof: '文字截图', minutes: 25, attrs: <String, int>{'智': 1, '魅': 1}, rank: 'E'),
  DailyTemplate(
    title: '收拾房间的一个角落',
    proof: '前后对比照片',
    minutes: 15,
    attrs: <String, int>{'知': 1, '体': 1},
    rank: 'F',
  ),
  DailyTemplate(title: '跳绳 500 下', proof: '计数截图', minutes: 12, attrs: <String, int>{'敏': 1, '体': 1}, rank: 'E'),
  DailyTemplate(
    title: '学一个新技巧，今天用三次',
    proof: '截图',
    minutes: 15,
    attrs: <String, int>{'智': 1, '敏': 1},
    rank: 'F',
  ),
  DailyTemplate(title: '做一顿饭', proof: '饭菜照片', minutes: 40, attrs: <String, int>{'体': 1, '知': 1}, rank: 'D'),
  // ── 批二扩充（TODO-03 模板半批）—— 通用池 14 → 30，把重样期往后推 ──
  DailyTemplate(
    title: '早起后喝一杯水，再做 10 个开合跳',
    proof: '计时截图',
    minutes: 5,
    attrs: <String, int>{'体': 1, '力': 1},
    rank: 'F',
  ),
  DailyTemplate(
    title: '把手机放到够不着的地方，专注 25 分钟',
    proof: '计时截图',
    minutes: 30,
    attrs: <String, int>{'智': 1, '知': 1},
    rank: 'E',
  ),
  DailyTemplate(
    title: '走楼梯不坐电梯，上下各两趟',
    proof: '步数截图',
    minutes: 10,
    attrs: <String, int>{'体': 1, '敏': 1},
    rank: 'F',
  ),
  DailyTemplate(
    title: '写三行今天想说的话，写完就合上',
    proof: '文字截图',
    minutes: 10,
    attrs: <String, int>{'魅': 1, '知': 1},
    rank: 'F',
  ),
  DailyTemplate(
    title: '洗一次碗，顺便把台面擦干净',
    proof: '前后对比照片',
    minutes: 15,
    attrs: <String, int>{'知': 1, '体': 1},
    rank: 'F',
  ),
  DailyTemplate(
    title: '靠墙静蹲 3 组，每组 45 秒',
    proof: '计时截图',
    minutes: 8,
    attrs: <String, int>{'力': 1, '体': 1},
    rank: 'E',
  ),
  DailyTemplate(
    title: '把明天的三件事写下来，只写三件',
    proof: '清单照片',
    minutes: 10,
    attrs: <String, int>{'知': 1, '智': 1},
    rank: 'F',
  ),
  DailyTemplate(
    title: '念一段 3 分钟的文字，念出声',
    proof: '录音截图',
    minutes: 10,
    attrs: <String, int>{'魅': 1, '智': 1},
    rank: 'F',
  ),
  DailyTemplate(
    title: '整理一次手机相册，删掉 30 张废片',
    proof: '相册截图',
    minutes: 15,
    attrs: <String, int>{'知': 1},
    rank: 'F',
  ),
  DailyTemplate(
    title: '靠墙站直 10 分钟，别塌肩',
    proof: '计时截图',
    minutes: 10,
    attrs: <String, int>{'魅': 1, '体': 1},
    rank: 'F',
  ),
  DailyTemplate(
    title: '喝水 6 杯，拿杯子凑数不算',
    proof: '杯子照片',
    minutes: 5,
    attrs: <String, int>{'体': 1},
    rank: 'F',
  ),
  DailyTemplate(
    title: '把昨天没做完的那件事补完',
    proof: '完成截图',
    minutes: 30,
    attrs: <String, int>{'知': 1, '智': 1},
    rank: 'D',
  ),
  DailyTemplate(
    title: '快走 20 分钟，不许边刷手机边走',
    proof: '步数截图',
    minutes: 25,
    attrs: <String, int>{'体': 1, '敏': 1},
    rank: 'E',
  ),
  DailyTemplate(
    title: '手写一页字，慢一点，写整齐',
    proof: '纸面照片',
    minutes: 15,
    attrs: <String, int>{'敏': 1, '知': 1},
    rank: 'F',
  ),
  DailyTemplate(
    title: '今天不喝含糖饮料，一杯都不',
    proof: '晚上拍一张今天喝过的东西',
    minutes: 5,
    attrs: <String, int>{'知': 1, '体': 1},
    rank: 'F',
  ),
  DailyTemplate(
    title: '睡前 10 分钟回顾今天，想清楚一件做对的事',
    proof: '笔记照片',
    minutes: 12,
    attrs: <String, int>{'知': 1, '魅': 1},
    rank: 'F',
  ),
];

// ── 第二目标闭环 · 长链生成（TODO-01 + TODO-06 模板半）──────────
//
// 首次目标 3 天 3 环（[buildFirstGoal]）只是「3 天验证」；验证过了之后
// 叙事不能停在终点 —— 第 3 环 CLEAR 之后由 [buildNextGoal] 按
// 原型 `makeGoal` 的**时长词规则**（store.js L147-150）铸一条 5~8 环的新主线。
// 日常池同时按「模板半批」扩充（[kDailyCommon] ≥30、各类专属池 ≥8），
// 把内容重样期从 ~D9 后移（docs/20 §7.2 批次二）。

/// 长链环数兜底区间（docs/19 P1-3 / TODO-06：5~8 环）
const int kNextGoalMinRings = 5;
const int kNextGoalMaxRings = 8;

/// 长链档位阶梯 —— 原型 `RING_SEQ` 的并集，低开高走、收在 S。
const List<String> kNextGoalRankSeq = <String>[
  'E',
  'D',
  'C',
  'B',
  'A',
  'S',
];

/// 长链末环的时限（原型 `makeGoal` 尾部那句 `m: 120`）
const int kNextGoalFinalMinutes = 120;

/// 时长词 → 环数（原型 `makeGoal` L147-150 逐条移植；默认 6）：
///   一年/半年/三四五六七八九十个月/百天/100 天 → 8
///   两二个月/60 天/八周                        → 7
///   一周/7 天/七天/两周/14 天/十天              → 5
///
/// ⚠️ 「一个月」不在表里（原型默认 6）——所以「三个月」只能由 `[三-十]个月`
/// 命中，绝不能让 `[两二]个月` 把「一个月」也吞掉（负向先行断言挡住）。
int goalRingCountFor(String text) {
  if (RegExp(r'一年|半年|[三四五六七八九十]个月|百天|100\s*天').hasMatch(text)) {
    return 8;
  }
  if (RegExp(r'[两二]个月|60\s*天|八周').hasMatch(text)) return 7;
  if (RegExp(r'一周|7\s*天|七天|两周|14\s*天|十天').hasMatch(text)) return 5;
  return 6;
}

/// 上一目标的完成度提档：全部走完 **且等级到 4** 再多给一环。
/// 只做**上限内的**提档，不给低等级用户硬塞长链（docs/19 P1-3 的「认真用户」）。
int completionRingBoost({
  required int cleared,
  required int total,
  required int level,
}) {
  if (total <= 0 || cleared < total) return 0;
  return level >= 4 ? 1 : 0;
}

/// 新主线的一条环（[RingSpec] 的公共字段全保留，另带环号与收尾标记）
class NextRingSpec {
  const NextRingSpec({required this.spec, required this.index, required this.last});

  final RingSpec spec;
  final int index;
  final bool last;
}

/// 长链环参数表：首目标 3 环原样接上，再按原型阶梯的**升档 + 加时**
/// 逐环加码，末环永远钉成「兑现它」（原型 `makeGoal` 尾环）。
///
/// [n] 为总环数（5~8），[firstRings] 是类别自带的 3 条起步环。
List<NextRingSpec> nextRingSpecs(
  List<RingSpec> firstRings, {
  required int n,
  required String goalText,
}) {
  final int count = n.clamp(kNextGoalMinRings, kNextGoalMaxRings).toInt();
  if (firstRings.isEmpty) return const <NextRingSpec>[];
  final List<RingSpec> base = List<RingSpec>.of(firstRings);
  final int mid = count - 1; // 末环是目标本身
  final List<RingSpec> specs = <RingSpec>[];
  for (int i = 0; i < mid; i++) {
    if (i < base.length) {
      specs.add(base[i]);
      continue;
    }
    // 加码环：底样按序循环，档位走 [kNextGoalRankSeq]，时限每级 ×1.35
    final RingSpec seed = base[i % base.length];
    final String rank = kNextGoalRankSeq[
        (i % kNextGoalRankSeq.length).clamp(0, kNextGoalRankSeq.length - 1)];
    final int cap = switch (rank) {
      'E' => 30,
      'D' => 40,
      'C' => 60,
      'B' => 90,
      'A' => 120,
      _ => 180,
    };
    final int grew = (seed.minutes * 1.35).round();
    specs.add(
      RingSpec(
        short: '加码 ${i - base.length + 1}',
        title: '${seed.title}——加码到 ${grew.clamp(5, cap)} 分钟',
        proof: seed.proof,
        minutes: grew.clamp(5, cap).toInt(),
        rank: rank,
      ),
    );
  }
  specs.add(
    RingSpec(
      short: '兑现',
      title: '$goalText——兑现它',
      proof: '能证明你做到了的截图',
      minutes: kNextGoalFinalMinutes,
      rank: 'S',
    ),
  );
  return <NextRingSpec>[
    for (int i = 0; i < specs.length; i++)
      NextRingSpec(spec: specs[i], index: i, last: i == specs.length - 1),
  ];
}

/// 第二目标：finale 之后自动续主线（TODO-01）——
/// 环数 = 时长词规则（5~8）+ 上一目标完成度提档，档位低开高走收在 S。
///
/// [prev] 上一目标（文本/类型/访谈答案/立目标时刻全部沿用，保证
/// 「换一条路，还是她」的连续性）；[cleared]/[total] 是上一目标走过的环数；
/// [level] 用结算后的等级（提档只看满环完成）。
/// [text]/[cat] 只在「换目标」（宿主另立一句话）时传，不传就沿上一目标。
Goal buildNextGoal({
  required Goal prev,
  required int cleared,
  required int total,
  required int level,
  String? text,
  GoalCategory? cat,
  DateTime? at,
}) {
  final String clean = (text == null || text.trim().isEmpty)
      ? prev.text
      : text.trim();
  final GoalCategory category = cat ??
      (clean == prev.text
          ? (goalCats[prev.cat] ?? detectCategory(clean))
          : detectCategory(clean));
  final int base = goalRingCountFor(clean);
  final int boost = completionRingBoost(
    cleared: cleared,
    total: total,
    level: level,
  );
  final int n = (base + boost)
      .clamp(kNextGoalMinRings, kNextGoalMaxRings)
      .toInt();
  final List<NextRingSpec> specs = nextRingSpecs(
    category.firstRings,
    n: n,
    goalText: clean,
  );
  return Goal(
    text: clean,
    short: shortOfGoal(clean, category),
    at: at ?? DateTime.now(),
    cat: category.id,
    days: n,
    interview: Map<String, String>.of(prev.interview),
    rings: <GoalRing>[
      for (final NextRingSpec s in specs)
        GoalRing(
          short: s.spec.short,
          title: s.spec.title,
          proof: s.spec.proof,
          minutes: s.spec.minutes,
          rank: s.spec.rank,
          state: s.index == 0 ? RingState.cur : RingState.lock,
          finalRing: s.last,
        ),
    ],
  );
}

/// 空泛目标黑名单（content.js L241 `VAGUE`）—— 她会追问到具体为止。
final RegExp _kVague = RegExp(
  r'^(变优秀|变强|变好|变得更好|努力|成功|自律|提升自己|加油|好好学习|做更好的自己|改变|有钱|发财|开心|快乐)$',
);

// ── 识别与拆短字（store.js `shortOf`） ─────────────────────────

/// 关键词 → 类型；一个都不中落 `gen`（`gen` 的 pattern 是 `.*`，所以必须按
/// [kGoalCatOrder] 顺序短路）。
GoalCategory detectCategory(String text) {
  for (final GoalCategory cat in kGoalCatOrder) {
    if (cat.pattern.hasMatch(text)) return cat;
  }
  return goalCats['gen']!;
}

/// 原型 `makeGoal` 开头的空泛判定：剥掉标点后少于 2 字，或整句就是空话。
bool isVagueGoal(String text) {
  final String bare = text.replaceAll(RegExp(r'[。.!！?？\s~～]'), '');
  if (bare.runes.length < 2) return true;
  return _kVague.hasMatch(bare);
}

final List<(RegExp, Object)> _shortRules = <(RegExp, Object)>[
  (RegExp('半马'), '半马'),
  (RegExp('全马|马拉松'), '全马'),
  (RegExp(r'(\d+)\s*(公里|km|K)', caseSensitive: false), (RegExpMatch m) => '${m[1]}K'),
  (RegExp('六级'), '六级'),
  (RegExp('四级'), '四级'),
  (RegExp('雅思'), '雅思'),
  (RegExp('托福'), '托福'),
  (RegExp('考研'), '上岸'),
  (RegExp('考公'), '上岸'),
  (RegExp(r'N[1-5]', caseSensitive: false), (RegExpMatch m) => m[0]!.toUpperCase()),
  (RegExp(r'(\d+)\s*斤'), (RegExpMatch m) => '−${m[1]}斤'),
  (RegExp('早起'), '早起'),
  (RegExp('早睡'), '早睡'),
  (RegExp('腹肌'), '腹肌'),
  (RegExp('引体'), '引体'),
  (RegExp('吉他'), '吉他'),
  (RegExp('钢琴'), '钢琴'),
  (RegExp('小说'), '小说'),
  (RegExp('画'), '画'),
];

/// 天幕大字（`goal.short`，原型 `Store.shortOf`）：先走关键词表，
/// 再落类别兜底短字，最后按 `gen` 的剥前缀规则取前 4 字。
String shortOfGoal(String text, GoalCategory cat) {
  for (final (RegExp, Object) rule in _shortRules) {
    final RegExpMatch? m = rule.$1.firstMatch(text);
    if (m == null) continue;
    final Object v = rule.$2;
    if (v is String) return v;
    return (v as String Function(RegExpMatch))(m);
  }
  if (cat.id != 'gen') return cat.short;
  String s = text.replaceAll(RegExp(r'[，。！？,.!?\s]'), '');
  s = s.replaceAll(RegExp(r'^(我要|我想|想要|我希望|希望|争取|坚持|每天|学会|学习)+'), '');
  s = s.replaceAll(RegExp(r'^(一|两|三|四|五|六|半)?(个)?(月|年|周|天)(内|之内)?'), '');
  s = s.replaceAll(RegExp(r'^(学会|坚持|每天)'), '');
  if (s.isEmpty) return '变强';
  return String.fromCharCodes(s.runes.take(4));
}

// ── 访谈卡组 ──────────────────────────────────────────────────

/// 通用追加卡（等级更高才问——「依据等级设定合适内容」）。
const InterviewCard _kCommonSlot = InterviewCard(
  id: 'common.slot',
  question: '一周愿意投入几个时段？',
  options: <String>['2 个', '3~4 个', '5 个以上'],
);
const InterviewCard _kCommonHistory = InterviewCard(
  id: 'common.history',
  question: '上次立目标是什么结果？',
  options: <String>['没开始就放弃了', '坚持了几天', '完成了'],
);

/// 按等级出 3~5 张卡：新宿主（lv1）= 类别 3 张（docs/18 §2.1 示例即此形态）；
/// lv2~3 追加「投入时段」；lv4+ 再追加「上次结果」（换目标的复盘问法）。
List<InterviewCard> interviewCardsFor(GoalCategory cat, {int level = 1}) {
  final List<InterviewCard> cards = <InterviewCard>[...cat.cards];
  if (level >= 2) cards.add(_kCommonSlot);
  if (level >= 4) cards.add(_kCommonHistory);
  assert(
    cards.length >= 3 && cards.length <= 5,
    '访谈卡组必须落在 3~5 张（docs/18 §2.1）',
  );
  return List<InterviewCard>.unmodifiable(cards);
}

/// 访谈答案是否显示「负担重」——出现熬夜 / 作息不固定这类信号时，
/// 首目标第 1 环换成 [GoalCategory.lightRing]（docs/18 §2.1：
/// 「天天熬夜」则第 1 环从 E 级「比昨天早睡 15 分钟」起）。
bool interviewIndicatesHeavyBurden(
  GoalCategory cat,
  Map<String, String> answers,
) {
  if (cat.lightRing == null) return false;
  final String joined = answers.values.join(' ');
  return joined.contains('熬夜') || joined.contains('没有固定');
}

// ── 首目标生成 ────────────────────────────────────────────────

/// E/D/C 的建议时限上限（docs/18 §2.3「建议时限」列；下限 5 分钟兜底）。
int _clampMin(int minutes, String rank) {
  final int cap = switch (rank) {
    'E' => 15,
    'D' => 20,
    _ => 30,
  };
  return minutes.clamp(5, cap).toInt();
}

/// 首次新目标：**3 天 3 环（E/D/C）**，每天一环，第 3 环即「她头顶那一环」。
/// 访谈答案随 Goal 入档（`interview` 字段），答案显示负担重则第 1 环换轻档。
Goal buildFirstGoal({
  required String text,
  required GoalCategory cat,
  Map<String, String> answers = const <String, String>{},
  DateTime? at,
}) {
  final String clean = text.trim();
  final bool light = interviewIndicatesHeavyBurden(cat, answers);
  final List<RingSpec> specs = cat.firstRings;
  final List<GoalRing> rings = <GoalRing>[];
  for (int i = 0; i < specs.length; i++) {
    // 负担重 → 第 1 环换成更轻的起步环（docs/18 §2.1 的 sleep 示例）
    final RingSpec spec =
        (i == 0 && light && cat.lightRing != null) ? cat.lightRing! : specs[i];
    rings.add(
      GoalRing(
        short: spec.short,
        title: spec.title,
        proof: spec.proof,
        minutes: _clampMin(spec.minutes, spec.rank),
        rank: kFirstGoalRanks[i],
        state: i == 0 ? RingState.cur : RingState.lock,
        finalRing: i == specs.length - 1,
      ),
    );
  }
  return Goal(
    text: clean,
    short: shortOfGoal(clean, cat),
    at: at ?? DateTime.now(),
    rings: rings,
    cat: cat.id,
    days: kFirstGoalDays,
    interview: Map<String, String>.of(answers),
  );
}

// ── 答案三用 · ② 日常池 ───────────────────────────────────────

/// 周期任务生成读取的日常池：目标类型的专属池在前、通用池补位
/// （原型 `genDaily` 的 `pool = [...C.daily, ...DAILY_COMMON]`）。
List<DailyTemplate> dailyPoolFor(String catId) {
  final GoalCategory cat = goalCats[catId] ?? goalCats['gen']!;
  return <DailyTemplate>[...cat.daily, ...kDailyCommon];
}

// ── 答案三用 · ③ 记忆导出（T5 memory 的第一批条目） ────────────

/// 访谈即第一批记忆：目标一句 + 逐卡问答一句。
/// T5 落库时包一层 `{text, source: interview}` 即可。
List<String> memoriesFromInterview({
  required GoalCategory cat,
  required Map<String, String> answers,
  required String goalText,
}) {
  final List<String> out = <String>[
    '宿主立了新目标：「${goalText.trim()}」（${cat.label}向，首期 $kFirstGoalDays 天）。',
  ];
  for (final InterviewCard card in interviewCardsFor(cat)) {
    final String? a = answers[card.id];
    if (a == null || a.isEmpty) continue;
    out.add('${card.question}——$a。');
  }
  return out;
}

// ── 触发判定与绑定语义（装配归 T8，这里只给规则） ─────────────

/// 是否该进绑定/访谈流：**没有主线才要绑**。
/// 老存档（演示档或真实档）环非空 = 已有主线，永不触发；数据兼容由
/// `Goal.fromJson` 的合并式迁移保证（缺 `cat/days/interview` 自动补默认）。
bool shouldOnboard(Goal goal) => goal.isEmpty;

/// 见面礼（原型 `Store.bind()` 的 `S.items.dbl += 1`）——
/// 数值语义在此钉死：绑定完成送 **双倍卡 ×1**（道具表 items.dart 不动，
/// key = 'dbl'）；Banner 演出（`见面礼 · 双倍卡 ×1`，2200ms 自收）归装配。
const int kBindGiftDbl = 1;
const String kBindGiftItemKey = 'dbl';
const String kBindGiftKicker = '见面礼';
const String kBindGiftText = '双倍卡 ×1';

/// 绑定见面礼：返回加了双倍卡的新 items 表（不改动传入表）。
/// 装配侧 `host = host.copyWith(items: applyBindGift(host.items))` 即完成入账。
Map<String, int> applyBindGift(Map<String, int> items) => <String, int>{
  ...items,
  kBindGiftItemKey: (items[kBindGiftItemKey] ?? 0) + kBindGiftDbl,
};

// ═══ 周期任务生成（docs/18 §2.2 · T6-2）══════════════════════════
//
// 「每日 1~2 个」取代原型 `dailyCount=clamp(1+⌈lv/3⌉,2,4)`：
//   候选池 4~6 个（目标类型专属池 + 通用池）→ 按「一单专治最弱维、
//   一单贴主线、其余随缘」（store.js:108 plan 策略）挑 1~2 个。
// 换日（`rollDay`，store.js:179-196 语义）：隔夜日常作废、主线单重钉、
//   清晨首次进入 App 时补发。装配在 main.dart；本模块只出**纯函数**。

/// 每日日常单数：`lv≥5 或连击≥3 → 2`，否则 1（docs/18 §2.2）。
int dailyCountFor({required int level, required int streak}) =>
    (level >= 5 || streak >= 3) ? 2 : 1;

/// 日常单的日上限（docs/01：日上限 6；主线单/补救单不占日常配额）。
const int kDailyCap = 6;

/// 候选池规模：「生成数个、用 1~2 个」—— 每次出 4~6 个候选再挑。
const int kDailyCandidateMin = 4;
const int kDailyCandidateMax = 6;

/// 候选池：目标类型专属池在前、通用池补位，随机去重出 4~6 个（docs/18 §2.2）。
List<DailyTemplate> genDailyCandidates({
  required String catId,
  required math.Random rnd,
  int? n,
}) {
  final List<DailyTemplate> pool = dailyPoolFor(catId);
  final int want =
      (n ?? kDailyCandidateMin + rnd.nextInt(kDailyCandidateMax - kDailyCandidateMin + 1))
          .clamp(0, pool.length);
  final List<DailyTemplate> shuffled = <DailyTemplate>[...pool]..shuffle(rnd);
  return shuffled.take(want).toList();
}

/// 从候选里挑 [n] 个（store.js:108 的 plan 策略）：
/// 第一单专治**最弱维**，第二单**贴主线**（类别六维倾向命中），其余随缘。
List<DailyTemplate> pickDailies({
  required List<DailyTemplate> candidates,
  required Map<String, int> attrs,
  required String goalCatId,
  required int n,
  required math.Random rnd,
}) {
  MapEntry<String, int> weak = attrs.isEmpty
      ? const MapEntry<String, int>('体', 0)
      : attrs.entries.reduce(
          (MapEntry<String, int> a, MapEntry<String, int> b) =>
              b.value < a.value ? b : a,
        );
  final Map<String, int> tilt = goalCats[goalCatId]?.tilt ??
      goalCats['gen']!.tilt;
  final List<DailyTemplate> out = <DailyTemplate>[];
  final Set<String> used = <String>{};
  bool take(bool Function(DailyTemplate) pred) {
    final List<DailyTemplate> cand = candidates
        .where((DailyTemplate d) => !used.contains(d.title) && pred(d))
        .toList();
    if (cand.isEmpty) return false;
    final DailyTemplate d = cand[rnd.nextInt(cand.length)];
    used.add(d.title);
    out.add(d);
    return true;
  }

  final List<bool Function(DailyTemplate)> plan = <bool Function(DailyTemplate)>[
    (DailyTemplate d) => (d.attrs[weak.key] ?? 0) > 0, // 一单专治短板
    (DailyTemplate d) =>
        tilt.keys.any((String k) => (d.attrs[k] ?? 0) > 0), // 一单贴主线
    for (int i = 0; i < kDailyCap; i++) (DailyTemplate _) => true, // 其余随缘
  ];
  for (int i = 0; i < n; i++) {
    if (!(take(plan[i]) || take((DailyTemplate _) => true))) break;
  }
  return out;
}

/// 日常档位（store.js:112-114 沿用 + docs/18 §2.3 的 F 兼容档新政）：
/// lv≥4 有 30% 提一档、lv≥8 再 20%；封顶 lv<8 到 D、lv≥8 到 C；
/// **新生成任务不再出 F**（F 只留给老存档/补救残单，§2.3 表）——
/// 提档后仍为 F 的钉回 E。
String dailyRankFor(String baseRank, {required int level, required math.Random rnd}) {
  String r = baseRank;
  if (level >= 4 && rnd.nextDouble() < .3) {
    r = Rarity.ranks[(Rarity.of(r).i + 1).clamp(0, Rarity.ranks.length - 1)];
  }
  if (level >= 8 && rnd.nextDouble() < .2) {
    r = Rarity.ranks[(Rarity.of(r).i + 1).clamp(0, Rarity.ranks.length - 1)];
  }
  final int cap = level >= 8 ? 3 : 2;
  final int i = math.max(1, math.min(Rarity.of(r).i, cap));
  return Rarity.ranks[i];
}

/// 模板 → 一张日常单。六维 = 模板权重按档位点数重分
/// （`QuestFlow.splitAttrs` 静态复用 —— docs/18 §3.3 的只读纪律；
/// 单号由调用方给，main.dart 经 `_flow.genDaily` 占位取合法单号，绝不撞号）。
Quest dailyQuestFrom(
  DailyTemplate t, {
  required int serial,
  required int level,
  required math.Random rnd,
  String? rank,
}) {
  final String r = rank ?? dailyRankFor(t.rank, level: level, rnd: rnd);
  return Quest(
    serial: serial,
    kind: 'daily',
    ring: -1,
    ringTotal: 0,
    name: t.title,
    reason: '',
    proof: t.proof,
    minutes: t.minutes,
    rank: r,
    attrs: QuestFlow.splitAttrs(t.attrs, Rarity.of(r).pt),
  );
}

/// 换日的**队列手术**（store.js `rollDay` L179-196 移植，纯函数可测）：
///  · 隔夜的日常与主线单**全部作废**（`kind != 'remedy'` 清空；
///    昨天被退缩降过档的主线单，新的一天换一张新档位的 —— 重钉）；
///  · 补救单只留**未过期**的（[remedyDeadline] = 业务层记的截止时刻，
///    null 视为仍有效）；
///  · 主线脚下环重钉一张新单：[mainTask] 由调用方造（带合法单号）；
///    执行中的就是主线单时不重钉（[activeIsMain]，原型 L189）；
///  · 补发当日日常 [fresh]，**日上限 6** 兜底钳制（只数 kind=='daily'）。
///
/// 返回新队列；调用方原位替换业务层的队列并落盘。
List<Quest> rollDayQueue({
  required List<Quest> overnight,
  required List<Quest> fresh,
  Quest? Function()? mainTask,
  bool activeIsMain = false,
  DateTime? remedyDeadline,
  DateTime? now,
}) {
  final DateTime t0 = now ?? DateTime.now();
  final List<Quest> out = <Quest>[
    for (final Quest q in overnight)
      if (q.kind == 'remedy' &&
          (remedyDeadline == null || !remedyDeadline.isBefore(t0)))
        q,
  ];
  if (!activeIsMain) {
    final Quest? m = mainTask?.call();
    if (m != null) out.insert(0, m);
  }
  final int usedDaily = out
      .where((Quest q) => q.kind == 'daily')
      .length;
  final int room = math.max(0, kDailyCap - usedDaily);
  out.addAll(fresh.take(room));
  return out;
}

/// 同一天吗（本地日历日；换日判定与 `_startOfDay` 配套）。
bool isSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 那一天的 0 点（换日游标的存法）。
DateTime startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);
