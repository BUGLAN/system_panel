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
    required this.ring,
    required this.ringTotal,
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

  /// 主线第几环（0 基）与总环数
  final int ring;
  final int ringTotal;

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
    if (kind == 'main') return '主线 · 第 ${ring + 1} 环 / $ringTotal';
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
  /// ⚠️ 保持原型板面的**旧表读数**：plate.dart:750/115 直接读 `rarity.exp/coin`，
  /// plate_test 也以这串文案钉原型像素真值 —— 面板口径切换是 widgets 侧的
  /// 返工卡（t8 范围外），这里不动它，零回归。
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
  /// 派单板 loot 面板换读它之后就与结算一致（迁移点：plate.dart:750）。
  String get lootText {
    final double k = kind == 'remedy' ? .5 : 1;
    final String at = attrs.entries
        .map((MapEntry<String, int> e) => '${e.key}+${e.value}')
        .join(' ');
    return 'EXP ${(Rewards.expOf(rank) * k).round()} · '
        '◈ ${(Rewards.coinOf(rank) * k).round()}$at';
  }

  /// 与原型 `Store.veteran()` 的 `Store.head()` 逐字段一致的那一单
  /// （C 级主线第 5 环）。
  /// ⚠️ `serial` 与 `reason` 一开始是我按印象写的（80 / 「38 分」），
  /// 与 veteran 档（41 / 「38 分 46 秒」）对不上 —— 这种小字差异在区域均值里
  /// 几乎看不出来，是换成干净存档后才核对出来的。
  static const Quest demo = Quest(
    serial: 41,
    kind: 'main',
    ring: 4,
    ringTotal: 8,
    name: '跑完 5 公里',
    reason: '上一环你用了 38 分 46 秒。这一环，我加了点码。',
    proof: '跑步 App 截图',
    minutes: 45,
    rank: 'C',
    attrs: <String, int>{'体': 1, '力': 1},
  );
}
