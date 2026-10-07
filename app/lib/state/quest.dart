import '../data/rarity.dart';

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
  });

  /// 单号（原型按 4 位补零显示）
  final int serial;

  /// 'main' | 'daily' | 'remedy'
  final String kind;

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

  /// ui.js L196 的 kind 文案
  String get kindLabel {
    switch (kind) {
      case 'main':
        return '主线 · 第 ${ring + 1} 环 / $ringTotal';
      case 'remedy':
        return '补救 · 24 小时内有效';
      default:
        return '日常委托';
    }
  }

  /// util.js `fmtMin`
  String get minutesText {
    final int m = minutes;
    if (m < 60) return '$m 分钟';
    if (m % 60 == 0) return '${m ~/ 60} 小时';
    return '${m ~/ 60} 小时 ${m % 60} 分';
  }

  /// ui.js `rewardHTML` 的纯文本版：`EXP 50 · ◈ 24 体+1 力+1`
  String get rewardText {
    final double k = kind == 'remedy' ? .5 : 1;
    final String at = attrs.entries.map((MapEntry<String, int> e) => '${e.key}+${e.value}').join(' ');
    return 'EXP ${(rarity.exp * k).round()} · ◈ ${(rarity.coin * k).round()}$at';
  }

  /// 与原型演示态一致的那一单（实测：C 级主线第 5 环）
  static const Quest demo = Quest(
    serial: 80,
    kind: 'main',
    ring: 4,
    ringTotal: 8,
    name: '跑完 5 公里',
    reason: '上一环你用了 38 分。这一环，我加了点码。',
    proof: '跑步 App 截图',
    minutes: 45,
    rank: 'C',
    attrs: <String, int>{'体': 1, '力': 1},
  );
}
