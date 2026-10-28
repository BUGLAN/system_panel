import 'dart:math' as math;

import '../data/rarity.dart';
import 'goal.dart';
import 'plan_failure.dart';
import 'quest.dart';
import 'quest_flow.dart';

/// ═══════════════════════════════════════════════════════════
///  目标生成 —— 类别表 · 访谈卡组 · 计划规则（docs/34）
///
///  ⚠️ 2026-10-23 宿主定调（**这条最重要，别改回去**）：
///    目标拆解**只有 LLM 一条路**。旧版这里有「类别模板兜底」
///    （`GoalCategory.firstTasks` + 加码段），它正是「两周内骑自行车 10 次」
///    被铸成「把目标写在纸上，拍照」×4 的根因，而且把失败藏了起来。
///    现在模板全部删除：
///      · 类别识别 / 拆解内容 → `agent/plan_agent.dart`（Agent 调 `set_plan`）
///      · 本文件只留**规则**：条数、档位阶梯、时限上限、六维分配、校验
///      · 任何不合规 → 抛 [PlanRuleError]，不修正、不降级
///
///  数据真源：prototype/opus-v2-dir/js/content.js L14-241
///    `CATS`（类别名/六维倾向/访谈卡/日常池）/ `DAILY_COMMON` / `VAGUE`
///
///  绑定流：问目标 → Agent 拆解 + `interviewCardsFor` 出 3~5 张访谈卡 →
///  答案三用：① 喂给拆解（`PlanBrief.interview`）② 选日常池 ③ 导出记忆。
///  首次新目标固定 **3 天 3 张（E/D/C）**，验证「能坚持」再展开长计划。
/// ═══════════════════════════════════════════════════════════

/// 首目标周期（天）—— 宿主钦定：首次新目标 = 3 天。
const int kFirstGoalDays = 3;

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

/// 一张任务的**原料**（= `set_plan` 工具的 item schema 对应的 Dart 形状）。
///
/// 这是 Agent 交上来的东西，也是 [validatePlan] 校验的对象；字段顺序与
/// 类型必须与 `mainline_tool.setPlanSchema` 一一对应，别单方面改。
class TaskSpec {
  const TaskSpec({
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
    required this.tilt,
    required this.cards,
    required this.daily,
  });

  final String id;
  final String label;

  /// 六维倾向（v4 换血后的 力/敏/体/智/知/魅）
  final Map<String, int> tilt;

  /// 类别专属访谈卡（3 张；等级更高时 `interviewCardsFor` 会追加通用卡）
  final List<InterviewCard> cards;

  /// 该类日常池（每日委托的**产品内容**，与目标拆解无关）
  final List<DailyTemplate> daily;
}

// ── 十类全表（content.js L34-220 逐类移植；首环档位按 E/D/C 重排） ──

final GoalCategory _catRun = GoalCategory(
  id: 'run',
  label: '奔跑',
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
  DailyTemplate(
    title: '出门走 3000 步',
    proof: '步数截图',
    minutes: 30,
    attrs: <String, int>{'体': 1, '敏': 1},
    rank: 'E',
  ),
  DailyTemplate(
    title: '读 20 页书',
    proof: '页码照片',
    minutes: 30,
    attrs: <String, int>{'智': 1, '知': 1},
    rank: 'E',
  ),
  DailyTemplate(
    title: '发呆 10 分钟，不碰手机',
    proof: '计时截图',
    minutes: 12,
    attrs: <String, int>{'知': 2},
    rank: 'F',
  ),
  DailyTemplate(
    title: '给一个很久没联系的人发条消息',
    proof: '对话截图（可打码）',
    minutes: 8,
    attrs: <String, int>{'魅': 2},
    rank: 'E',
  ),
  DailyTemplate(
    title: '20 个深蹲',
    proof: '自拍或计数截图',
    minutes: 6,
    attrs: <String, int>{'力': 1, '体': 1},
    rank: 'F',
  ),
  DailyTemplate(
    title: '把一件拖了一周的小事做完',
    proof: '完成截图',
    minutes: 25,
    attrs: <String, int>{'知': 1, '智': 1},
    rank: 'D',
  ),
  DailyTemplate(
    title: '拉伸 10 分钟',
    proof: '拉伸照片',
    minutes: 12,
    attrs: <String, int>{'敏': 2},
    rank: 'F',
  ),
  DailyTemplate(
    title: '平板支撑累计 3 分钟',
    proof: '计时截图',
    minutes: 10,
    attrs: <String, int>{'力': 1, '体': 1},
    rank: 'E',
  ),
  DailyTemplate(
    title: '写 300 字，写什么都行',
    proof: '文字截图',
    minutes: 25,
    attrs: <String, int>{'智': 1, '魅': 1},
    rank: 'E',
  ),
  DailyTemplate(
    title: '收拾房间的一个角落',
    proof: '前后对比照片',
    minutes: 15,
    attrs: <String, int>{'知': 1, '体': 1},
    rank: 'F',
  ),
  DailyTemplate(
    title: '跳绳 500 下',
    proof: '计数截图',
    minutes: 12,
    attrs: <String, int>{'敏': 1, '体': 1},
    rank: 'E',
  ),
  DailyTemplate(
    title: '学一个新技巧，今天用三次',
    proof: '截图',
    minutes: 15,
    attrs: <String, int>{'智': 1, '敏': 1},
    rank: 'F',
  ),
  DailyTemplate(
    title: '做一顿饭',
    proof: '饭菜照片',
    minutes: 40,
    attrs: <String, int>{'体': 1, '知': 1},
    rank: 'D',
  ),
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

// ═══════════════════════════════════════════════════════════
//  计划铸造（2026-10-23 宿主定调：**只有 LLM 一条路**）
//
//  旧实现有两条路：LLM 交任务池 / 类别模板兜底（firstTasks + 加码段）。
//  模板路是「两周内骑自行车 10 次」被铸成「把目标写在纸上，拍照」×4 的根因，
//  而且它把失败藏了起来。现在：
//    · 内容**只能**来自 Agent 调 set_plan 交上来的任务池
//    · 本文件只负责**规则**：条数、档位阶梯、时限上限、六维分配
//    · 任何一条不合规 → 抛 [PlanRuleError]，不做修正、不做降级
// ═══════════════════════════════════════════════════════════

/// 计划条数区间（docs/34：条数 = 期限天数）。
/// 下限 2 = 至少「一张推进单 + 一张兑现单」；上限只是防呆（一年也就 366）。
const int kPlanMinTasks = 2;
const int kPlanMaxTasks = 400;

/// 各档位的建议时限上限（分钟）。**阶梯是规则**，所以模型交上来的时限
/// 一律按它校验 —— 超了就是不合格，抛出去让开发者看见。
int rankCapMinutes(String rank) => switch (rank) {
  'F' => 20,
  'E' => 30,
  'D' => 40,
  'C' => 60,
  'B' => 90,
  'A' => 120,
  _ => 180,
};

/// 兑现单的时限下限（原型 makeGoal 尾部那句 m: 120）
const int kPlanFinalMinutes = 120;

/// 首目标允许的档位（docs/05「前 10 任务必胜」：E/D/C）
const List<String> kFirstGoalRanks = <String>['E', 'D', 'C'];

/// 期限 → 清单条数。
///
/// **2026-10-23 修正（真机事故）**：旧口径是「条数 = 期限天数」，于是
/// 「两周内骑自行车 10 次」被铸成 **14 张「第 N 次骑行」**，末张还写成
/// 「第14次骑满120分钟并交全部10次轨迹」—— 与目标自带的次数配额直接打架。
/// 现在：
///   · 目标写了次数（[quota] > 0）→ 条数 = 次数（10 次就是 10 张）
///   · 没写次数 → 条数 = 期限天数（一天一张）
/// 两者都夹在 [kPlanMinTasks, kPlanMaxTasks] 内。
int planTaskCountFor(int days, {int quota = 0}) {
  final int n = quota > 0 ? quota : days;
  return n.clamp(kPlanMinTasks, kPlanMaxTasks).toInt();
}

// ═══════════════════════════════════════════════════════════
//  分段并行拆解（docs/49 F3，2026-10-28 真机：换目标 2 分钟拆不完还报错）
// ═══════════════════════════════════════════════════════════
//
//  根因：条数 = 期限天数。「三个月跑完半马」是 90 张、「半年减重」是 180 张，
//  一次 set_plan 要模型吐出几千~上万 token 的 JSON —— 单轮 90s 超时、
//  或被 max_tokens 截断成残缺数组，然后报错重试，越重试越慢。
//
//  解法：长清单按 [kPlanSegmentSize] 切段、**并行**拆（每段一次独立的 set_plan），
//  按顺序拼回后照旧过 [validatePlan]。档位阶梯由切段时**预先分配**：
//  每段一个档位区间 [lo, hi]，相邻两段首尾相接（前段 hi = 后段 lo），
//  段内不倒退 ⇒ 全链不倒退；末段收尾必须是 S 级兑现单。
//  仍然全部走 LLM，没有模板、没有兜底 —— 只是把一份大活拆成几份小活同时干。

/// 一段最多几张（12 张 ≈ 1k 出参 token，推理模型一轮 15~30s）
const int kPlanSegmentSize = 12;

/// 同时最多拆几段（再多端点容易限流）
const int kPlanSegmentConcurrency = 6;

/// 段间档位阶梯（末段上限另给 S）
const List<String> _kSegmentLadder = <String>['E', 'D', 'C', 'B', 'A'];

/// 长清单里的一段。
class PlanSegment {
  const PlanSegment({
    required this.index,
    required this.count,
    required this.from,
    required this.size,
    required this.total,
    required this.lo,
    required this.hi,
  });

  /// 第几段（0 基）/ 一共几段
  final int index;
  final int count;

  /// 本段第一张在整份清单里的序号（1 基）与张数
  final int from;
  final int size;

  /// 整份清单张数
  final int total;

  /// 本段档位区间（含两端）
  final String lo;
  final String hi;

  int get to => from + size - 1;

  /// 末段：收尾那一张就是整条主线的兑现单
  bool get last => index == count - 1;

  /// 阶段提示（让各段的强度曲线接得上）
  String get phase {
    if (last) return '冲刺与兑现：强度拉满，最后一张是兑现单';
    final double k = index / count;
    if (k < .25) return '起步期：低强度、先把习惯立住';
    if (k < .6) return '加量期：在前一段的基础上逐步加码';
    return '强化期：逼近目标强度';
  }
}

/// 清单 → 段。首目标或不超过一段的清单：只有一段（区间 F~S，交给 [validatePlan] 全量校验）。
List<PlanSegment> planSegmentsFor(int total, {bool firstGoal = false}) {
  if (firstGoal || total <= kPlanSegmentSize) {
    return <PlanSegment>[
      PlanSegment(
        index: 0,
        count: 1,
        from: 1,
        size: total,
        total: total,
        lo: 'F',
        hi: 'S',
      ),
    ];
  }
  final int k = (total / kPlanSegmentSize).ceil();
  final int base = total ~/ k;
  final int extra = total % k; // 前 extra 段各多一张
  String bound(int i) =>
      _kSegmentLadder[math.min(
        _kSegmentLadder.length - 1,
        (i * _kSegmentLadder.length) ~/ k,
      )];
  final List<PlanSegment> out = <PlanSegment>[];
  int from = 1;
  for (int i = 0; i < k; i++) {
    final int size = base + (i < extra ? 1 : 0);
    out.add(
      PlanSegment(
        index: i,
        count: k,
        from: from,
        size: size,
        total: total,
        lo: bound(i),
        hi: i == k - 1 ? 'S' : bound(i + 1),
      ),
    );
    from += size;
  }
  return out;
}

/// 一段的规则校验（与 [validatePlan] 同口径，只看本段）：
/// 张数、字段非空、档位落在本段区间、时限不越档位上限、段内不倒退；
/// 末段最后一张必须是 S 级兑现单。不合规就抛 [PlanRuleError]。
void validatePlanSegment(PlanSegment seg, List<TaskSpec> tasks) {
  if (tasks.length != seg.size) {
    throw PlanRuleError(
      '第 ${seg.index + 1} 段要正好 ${seg.size} 张（第 ${seg.from}~${seg.to} 张），'
      '模型给了 ${tasks.length} 张',
    );
  }
  final int lo = Rarity.ranks.indexOf(seg.lo);
  final int hi = Rarity.ranks.indexOf(seg.hi);
  for (int i = 0; i < tasks.length; i++) {
    final TaskSpec t = tasks[i];
    final int n = seg.from + i;
    if (t.short.trim().isEmpty) throw PlanRuleError('第 $n 张的 short 是空的');
    if (t.title.trim().isEmpty) throw PlanRuleError('第 $n 张的 title 是空的');
    if (t.proof.trim().isEmpty) throw PlanRuleError('第 $n 张的 proof 是空的');
    final int r = Rarity.ranks.indexOf(t.rank);
    if (r < lo || r > hi) {
      throw PlanRuleError('第 $n 张档位 ${t.rank} 不在本段区间 ${seg.lo}~${seg.hi} 里');
    }
    final int cap = rankCapMinutes(t.rank);
    if (t.minutes < 5 || t.minutes > cap) {
      throw PlanRuleError(
        '第 $n 张「${t.short}」的时限 ${t.minutes} 分钟越界（${t.rank} 档允许 5~$cap）',
      );
    }
    if (i > 0 && r < Rarity.ranks.indexOf(tasks[i - 1].rank)) {
      throw PlanRuleError(
        '第 $n 张档位倒退了：${tasks[i - 1].rank} → ${t.rank}（段内必须低开高走）',
      );
    }
  }
  if (seg.last && tasks.last.rank != 'S') {
    throw PlanRuleError('第 ${seg.to} 张是兑现单，必须 S 级，模型给了 ${tasks.last.rank}');
  }
}

/// 计划规则校验 —— **fail fast**：任何一条不合规都抛 [PlanRuleError]。
///
/// 校验项（docs/34 §3）：
///   · 条数 == 期限天数，且期限落在 [kPlanMinTasks, kPlanMaxTasks]
///   · 首目标（[firstGoal]）期限固定 [kFirstGoalDays]、档位只能是 E/D/C
///   · 每张：short / title / proof 非空、minutes 是正整数且不超档位上限、
///     rank 在 F~S
///   · 档位全链**不倒退**（低开高走）
///   · 非首目标的末张必须是 **S 级兑现单**且时限 ≥ [kPlanFinalMinutes]
///
/// 注意：这里**只判不合规就抛**，绝不「顺手改一改」——修正会把问题藏起来。
void validatePlan({
  required int days,
  required List<TaskSpec> tasks,
  int quota = 0,
  bool firstGoal = false,
}) {
  if (days < kPlanMinTasks || days > kPlanMaxTasks) {
    throw PlanRuleError('期限 $days 天不在 $kPlanMinTasks~$kPlanMaxTasks 之间');
  }
  if (firstGoal && days != kFirstGoalDays) {
    throw PlanRuleError('首目标期限必须是 $kFirstGoalDays 天，模型给了 $days 天');
  }
  final int want = planTaskCountFor(days, quota: quota);
  if (tasks.length != want) {
    final String why = quota > 0 ? '次数 $quota 次' : '期限 $days 天';
    throw PlanRuleError('清单条数必须是 $want 张（= $why），模型给了 ${tasks.length} 张');
  }
  for (int i = 0; i < tasks.length; i++) {
    final TaskSpec t = tasks[i];
    final int n = i + 1;
    if (t.short.trim().isEmpty) throw PlanRuleError('第 $n 张的 short 是空的');
    if (t.title.trim().isEmpty) throw PlanRuleError('第 $n 张的 title 是空的');
    if (t.proof.trim().isEmpty) throw PlanRuleError('第 $n 张的 proof 是空的');
    if (!Rarity.ranks.contains(t.rank)) {
      throw PlanRuleError(
        '第 $n 张的 rank「${t.rank}」不在 ${Rarity.ranks.join('/')} 里',
      );
    }
    final int cap = rankCapMinutes(t.rank);
    if (t.minutes < 5 || t.minutes > cap) {
      throw PlanRuleError(
        '第 $n 张「${t.short}」的时限 ${t.minutes} 分钟越界（${t.rank} 档允许 5~$cap）',
      );
    }
    if (firstGoal && !kFirstGoalRanks.contains(t.rank)) {
      throw PlanRuleError(
        '首目标第 $n 张档位是 ${t.rank}，首目标只允许 ${kFirstGoalRanks.join('/')}',
      );
    }
    if (i > 0) {
      final int prev = Rarity.ranks.indexOf(tasks[i - 1].rank);
      final int cur = Rarity.ranks.indexOf(t.rank);
      if (cur < prev) {
        throw PlanRuleError(
          '第 $n 张档位倒退了：${tasks[i - 1].rank} → ${t.rank}（全链必须低开高走）',
        );
      }
    }
  }
  if (!firstGoal) {
    final TaskSpec last = tasks.last;
    if (last.rank != 'S') {
      throw PlanRuleError('末张是兑现单，必须 S 级，模型给了 ${last.rank}');
    }
    // ⚠️ 2026-10-23 真机修正：原来这里硬要求「兑现单 ≥ 120 分钟」，
    //    结果「两周内骑自行车 10 次」的交全部轨迹那一步（模型给 10 分钟）
    //    被判定不合规，整个目标建不出来。
    //    兑现单**是不是一次长任务**取决于目标本身：骑车 10 次的兑现动作
    //    就是「交 10 次轨迹」这种轻验证。所以这里只校验**档位上限**，
    //    下限交给 S 档自身的 5 分钟底线（与其它张一致）。
    if (last.minutes > rankCapMinutes('S')) {
      throw PlanRuleError(
        '兑现单时限超过 S 档上限 ${rankCapMinutes('S')} 分钟，模型给了 ${last.minutes}',
      );
    }
  }
}

/// 已校验的任务池 → [PlanTask]（加六维分配、下标、兑现标记）。
///
/// 六维按类别倾向 [GoalCategory.tilt] 与档位点数走 [QuestFlow.splitAttrs]，
/// 生成时定死，结算只读（docs/34 §2.2）。
List<PlanTask> buildPlanTasks({
  required GoalCategory cat,
  required List<TaskSpec> tasks,
  bool firstGoal = false,
}) => <PlanTask>[
  for (int i = 0; i < tasks.length; i++)
    PlanTask(
      index: i,
      short: tasks[i].short,
      title: tasks[i].title,
      proof: tasks[i].proof,
      minutes: tasks[i].minutes,
      rank: tasks[i].rank,
      attrs: QuestFlow.splitAttrs(cat.tilt, Rarity.of(tasks[i].rank).pt),
      // 首目标不摆兑现门（docs/05）；其余末张 = 兑现单
      finalTask: !firstGoal && i == tasks.length - 1,
    ),
];

/// 用**已校验**的任务池铸一个目标。这是计划落库的唯一入口。
///
/// 不做任何兜底：调用方必须先拿到 PlanAgent 交上来的任务池，校验失败
/// （[validatePlan]）会当场抛 —— 这里不会替它编一份清单。
Goal buildGoalFromPlan({
  required String text,
  required String short,
  required GoalCategory cat,
  required int days,

  /// 目标自带的次数配额（0 = 没有；有就按它定条数，见 [planTaskCountFor]）
  int quota = 0,
  required List<TaskSpec> tasks,
  Map<String, String> answers = const <String, String>{},
  DateTime? at,
  String uid = '',
  bool firstGoal = false,
}) {
  final String clean = text.trim();
  if (clean.isEmpty) throw const PlanRuleError('目标文本是空的');
  validatePlan(days: days, tasks: tasks, quota: quota, firstGoal: firstGoal);
  return Goal(
    text: clean,
    short: short.trim().isEmpty ? clean : short.trim(),
    at: at ?? DateTime.now(),
    plan: buildPlanTasks(cat: cat, tasks: tasks, firstGoal: firstGoal),
    cat: cat.id,
    days: days,
    interview: Map<String, String>.of(answers),
    uid: uid,
  );
}

/// 空泛目标黑名单（content.js L241 VAGUE）—— 输入侧的前置校验，
/// 不是生成兜底：不合格的目标连 Agent 都不发。
final RegExp _kVague = RegExp(
  r'^(变优秀|变强|变好|变得更好|努力|成功|自律|提升自己|加油|好好学习|做更好的自己|改变|有钱|发财|开心|快乐)$',
);

/// 空泛判定：剥掉标点后少于 2 字，或整句就是空话。
bool isVagueGoal(String text) {
  final String bare = text.replaceAll(RegExp(r'[。.!！?？\s~～]'), '');
  if (bare.runes.length < 2) return true;
  return _kVague.hasMatch(bare);
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

/// 按等级出 3~5 张卡：新宿主（lv1）= 类别 3 张；lv2~3 追加「投入时段」；
/// lv4+ 再追加「上次结果」（换目标的复盘问法）。
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

// ── 答案三用 · ② 日常池 ───────────────────────────────────────

/// 周期任务生成读取的日常池：目标类型的专属池在前、通用池补位。
List<DailyTemplate> dailyPoolFor(String catId) {
  final GoalCategory cat = goalCats[catId] ?? goalCats['gen']!;
  return <DailyTemplate>[...cat.daily, ...kDailyCommon];
}

// ── 答案三用 · ③ 记忆导出（T5 memory 的第一批条目） ────────────

/// 访谈即第一批记忆：目标一句 + 逐卡问答一句。
List<String> memoriesFromInterview({
  required GoalCategory cat,
  required Map<String, String> answers,
  required String goalText,
  int days = kFirstGoalDays,
}) {
  final List<String> out = <String>[
    '宿主立了新目标：「${goalText.trim()}」（${cat.label}向，期限 $days 天）。',
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
bool shouldOnboard(Goal goal) => goal.isEmpty;

/// 见面礼（原型 Store.bind() 的 S.items.dbl += 1）
const int kBindGiftDbl = 1;
const String kBindGiftItemKey = 'dbl';
const String kBindGiftKicker = '见面礼';
const String kBindGiftText = '双倍卡 ×1';

/// 绑定见面礼：返回加了双倍卡的新 items 表（不改动传入表）。
Map<String, int> applyBindGift(Map<String, int> items) => <String, int>{
  ...items,
  kBindGiftItemKey: (items[kBindGiftItemKey] ?? 0) + kBindGiftDbl,
};

// ═══ 周期任务生成（docs/18 §2.2 · T6-2）══════════════════════════
//
// ⚠️ 这一段与「目标拆解」无关：日常池是**产品内容**（每日委托），不是
//    拆解失败时的兜底。拆解失败一律抛，不会退到这里。

/// 每日日常单数：lv≥5 或连击≥3 → 2，否则 1（docs/18 §2.2）。
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
      (n ??
              kDailyCandidateMin +
                  rnd.nextInt(kDailyCandidateMax - kDailyCandidateMin + 1))
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
  final MapEntry<String, int> weak = attrs.isEmpty
      ? const MapEntry<String, int>('体', 0)
      : attrs.entries.reduce(
          (MapEntry<String, int> a, MapEntry<String, int> b) =>
              b.value < a.value ? b : a,
        );
  final Map<String, int> tilt =
      goalCats[goalCatId]?.tilt ?? goalCats['gen']!.tilt;
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

  final List<bool Function(DailyTemplate)> plan =
      <bool Function(DailyTemplate)>[
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
/// **新生成任务不再出 F**（F 只留给老存档/补救残单）。
String dailyRankFor(
  String baseRank, {
  required int level,
  required math.Random rnd,
}) {
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

/// 模板 → 一张日常单。六维 = 模板权重按档位点数重分。
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
    name: t.title,
    reason: '',
    proof: t.proof,
    minutes: t.minutes,
    rank: r,
    attrs: QuestFlow.splitAttrs(t.attrs, Rarity.of(r).pt),
  );
}

/// 换日的**队列手术**（store.js rollDay L179-196 移植，纯函数可测）。
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
  final int usedDaily = out.where((Quest q) => q.kind == 'daily').length;
  final int room = math.max(0, kDailyCap - usedDaily);
  out.addAll(fresh.take(room));
  return out;
}

/// 同一天吗（本地日历日；换日判定与 startOfDay 配套）。
bool isSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 那一天的 0 点（换日游标的存法）。
DateTime startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);
