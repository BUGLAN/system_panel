/// 目标匹配 / 拆解 / 续拆的**健康与安全护栏**（G2.2）。
///
/// 为什么要单独一份：原来匹配与拆解的提示词里没有任何健康约束，
/// 「一个月减 30 斤」会被照常拆成 30 张越来越狠的任务（模型为了凑数字，
/// 自然会往断食、脱水、带伤硬练上排）。条款集中在这里，三条路径共用：
///   · 匹配 `GoalMatchAgent`（userText 末尾带 [kMatchGuard]）
///   · 拆解 / 续拆 `PlanBrief.userText`（首段与续拆都走它，带 [kPlanGuard]）
///   · `set_plan` 的 tasks schema 描述（工具定义里再钉一遍禁区）
///
/// 自伤 / 自杀类目标**不在这里**：那类连 LLM 都不发，走本地闸门
/// `data/crisis_words.dart`。
library;

/// 她拒拆时句首的标记。提示词要求「违法 / 伤害他人」的目标不调工具、
/// 只回一句「〔不拆〕+ 为什么」—— Agent 看到它就按 `badGoal` 抛，
/// 界面上读得出是「她不接」，而不是笼统的「模型没交工具（noPlan）」。
const String kRefuseMark = '〔不拆〕';

/// 匹配环节的护栏：期限怎么读、什么目标不接。
const String kMatchGuard =
    '【护栏】\n'
    '- 减重类：期限照他写的读，不许为了凑他那个数字去缩短；没写期限就按'
    '每周最多减约 1 公斤（2 斤）推算需要多久。\n'
    '- 目标本身违法、或要伤害他人（报复、跟踪、偷拿、诈骗、霸凌……）：'
    '不接，不要调用 set_goal_category，只回一句「$kRefuseMark」开头的话说清为什么。';

/// 拆解 / 续拆的护栏：减重节奏、任务禁区、不拆的目标。
const String kPlanGuard =
    '【健康与安全护栏】（任何一张违反，整份重排）\n'
    '- 减重类按安全节奏排：每周最多减约 1 公斤（2 斤）。期限内到不了他说的数字，'
    '就按安全节奏排——兑现单只验安全节奏能到的量（如「称重：比起点轻 4 斤」），'
    '别照抄他原来那个数字；你那句解释里直说「先按安全的速度走」。\n'
    '- 任务里不许出现：断食 / 不吃某一顿、催吐、泻药、脱水 / 少喝水、'
    '极端热量缺口（每天只吃几百大卡这类）、带伤或身体不舒服还硬练。'
    '饮食只排规律三餐、少油少糖、记录饮食这类温和动作；运动强度一点点往上加。\n'
    '- 目标本身违法、或要伤害他人：不拆，不要调用 set_plan，'
    '只回一句「$kRefuseMark」开头的话说清为什么。';

/// `set_plan` tasks 描述里追加的一句（工具定义也是提示词，再钉一遍禁区）。
const String kPlanSchemaGuard =
    '**健康底线**：不许断食、催吐、脱水、极端节食、带伤硬练；'
    '减重每周最多约 1 公斤（2 斤）。';

/// 她这句是不是「拒拆」—— 是就返回去掉标记后的理由，不是返回 null。
///
/// 只认句首（剥掉情绪标签与空白之后）：标记出现在正文中间多半是她在引用规则，
/// 不算拒拆。
String? refusalOf(String text) {
  final String t = text
      .trim()
      .replaceFirst(RegExp(r'^\[[A-Za-z]+\][ \t]*'), '')
      .trimLeft();
  if (!t.startsWith(kRefuseMark)) return null;
  final String why = t.substring(kRefuseMark.length).trim();
  return why.isEmpty ? '这个目标不接' : why;
}
