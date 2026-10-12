import '../data/rarity.dart';
import '../data/rewards.dart';

/// 一单委托 —— 对应原型里 `Plate.build(T)` 吃到的那份数据。
///
/// 派单/排期/奖励结算的**规则**尚未由宿主约束，这里只是数据模型 +
/// 一份与原型演示态逐字段一致的样例（用于同状态比对）。
class Quest {
  const Quest({
    required this.serial,
    required this.kind,
    this.planIndex = -1,
    this.planTotal = 0,
    this.goalId = '',
    required this.name,
    required this.reason,
    required this.proof,
    required this.minutes,
    required this.rank,
    required this.attrs,
    this.hinted = false,
  });

  /// 单号（原型按 4 位补零显示）
  final int serial;

  /// 'main' | 'daily' | 'remedy'
  final String kind;

  /// 她替你留的（原型 `T.hinted`）—— 只影响 `kindLabel` 的第四档文案
  final bool hinted;

  /// 计划里第几张单（0 基；日常/补救 = -1）与计划总条数
  final int planIndex;
  final int planTotal;

  /// 这张单属于哪个目标（`Goal.id`；日常/补救 = 空串）。
  /// 主线单只对**同一个**目标的清单起作用 —— 换过目标的老单不许再动新清单。
  final String goalId;

  final String name;

  /// 她的附言（可以为空）
  final String reason;

  /// 验证方式
  final String proof;

  /// 时限（分钟）
  final int minutes;

  final String rank;

  /// 六维加成，如 {'体': 1, '力': 1}
  final Map<String, int> attrs;

  Rarity get rarity => Rarity.of(rank);

  String get serialText => '№ ${serial.toString().padLeft(4, '0')}';

  /// ui.js L196 的 kind 文案 —— **四档**，不是三档
  String get kindLabel {
    if (kind == 'main') return '主线 · 第 ${planIndex + 1} 单 / $planTotal';
    if (kind == 'remedy') return '补救 · 24 小时内有效';
    if (hinted) return '日常 · 她替你留的';
    return '日常委托';
  }

  /// util.js `fmtMin`
  String get minutesText {
    final int m = minutes;
    if (m < 60) return '$m 分钟';
    if (m % 60 == 0) return '${m ~/ 60} 小时';
    return '${m ~/ 60} 小时 ${m % 60} 分';
  }

  /// ui.js `rewardHTML` 的纯文本版：`EXP 50 · ◈ 24 体+1 力+1`
  ///
  /// ⚠️ **原型旧表遗留读数**（rarity.exp/coin）——t15 起**没有生产读者**：
  /// plate.dart 的 loot 面板已切 [lootText]（结算经济口径），本 getter 仅由
  /// rewards_test 的交叉断言钉着存档（旧表字符串不再用于任何界面）。
  String get rewardText {
    final double k = kind == 'remedy' ? .5 : 1;
    final String at = attrs.entries
        .map((MapEntry<String, int> e) => '${e.key}+${e.value}')
        .join(' ');
    return 'EXP ${(rarity.exp * k).round()} · ◈ ${(rarity.coin * k).round()}$at';
  }

  /// 结算经济口径（docs/18 §2.3 Rewards 表）的报酬文案 —— C 级 = `EXP 4 · ◈ 5`。
  ///
  /// 这是「这一单**真会**结算出多少」的真源读数（quest_flow.settle 同表）；
  /// 派单板 loot 面板**只能**读它（t24 起 plate.dart 不再自己拼数字）。
  ///
  /// [crit]/[dbl] 默认 false —— 队列里等接单的单子还没有道具标记，派单板
  /// 显示的就是「裸单出账」；结算那一刻才有暴击/双倍（`quest_flow.settle`
  /// 的 `crit`/`a.dbl`）。真源乘区一律经 [lootTextOf] → `Rewards.payout`。
  String get lootText =>
      lootTextOf(rank: rank, remedy: kind == 'remedy', attrs: attrs);

  /// 这一单在 [crit]/[dbl]/补救 条件下的报酬文案（与结算同一个
  /// [Rewards.payout] 派生）—— 纯函数，方便「显示 = 结算」全档位遍历断言。
  static String lootTextOf({
    required String rank,
    bool remedy = false,
    bool crit = false,
    bool dbl = false,
    Map<String, int> attrs = const <String, int>{},
  }) {
    final Payout p = Rewards.payout(
      rank: rank,
      crit: crit,
      dbl: dbl,
      remedy: remedy,
    );
    final String at = attrs.entries
        .map((MapEntry<String, int> e) => '${e.key}+${e.value}')
        .join(' ');
    return 'EXP ${p.exp} · ◈ ${p.coin}$at';
  }

  /// 与原型 `Store.veteran()` 的 `Store.head()` 逐字段一致的那一单
  /// （C 级主线第 5 张）。
  /// ⚠️ `serial` 与 `reason` 一开始是我按印象写的（80 / 「38 分」），
  /// 与 veteran 档（41 / 「38 分 46 秒」）对不上 —— 这种小字差异在区域均值里
  /// 几乎看不出来，是换成干净存档后才核对出来的。
  static const Quest demo = Quest(
    serial: 41,
    kind: 'main',
    planIndex: 4,
    planTotal: 8,
    goalId: 'demo',
    name: '跑完 5 公里',
    reason: '上一张你用了 38 分 46 秒。这一张，我加了点码。',
    proof: '跑步 App 截图',
    minutes: 45,
    rank: 'C',
    attrs: <String, int>{'体': 1, '力': 1},
  );
}
