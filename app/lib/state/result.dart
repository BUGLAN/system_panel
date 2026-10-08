import '../data/rarity.dart';
import 'quest.dart';

/// 一单的结算结果 —— 对应原型 `flows.js settle()` 里那份 `res`。
///
/// 这里只放界面需要读的字段；暴击/双倍/连击的**判定规则**尚未由宿主约束，
/// 所以 demo 是与原型演示态一致的一份数据。
class QuestResult {
  const QuestResult({
    required this.quest,
    required this.beforeLv,
    required this.beforeExp,
    required this.beforeNeed,
    required this.exp,
    required this.coin,
    required this.attrs,
    required this.streak,
    required this.streakUp,
    required this.crit,
    required this.dbl,
    required this.photos,
    required this.chance,
  });

  final Quest quest;

  /// 结算前的等级/经验/升级所需（`.rs-lv` 那行与经验条的起点）
  final int beforeLv;
  final int beforeExp;
  final int beforeNeed;

  /// 这一单最终拿到多少经验（含暴击/双倍）
  final int exp;

  final int coin;

  /// 六维加成
  final Map<String, int> attrs;

  final int streak;
  final bool streakUp;

  final bool crit;
  final bool dbl;

  /// 交了几份证据、当时的暴击率
  final int photos;
  final double chance;

  Rarity get rarity => quest.rarity;

  /// 结算后停在多少经验（`.rs-lv` 右侧那行）
  int get afterExp => beforeExp + exp;

  /// 暴击/双倍**之前**那一跳的落点（原型 `res.baseExp`）。
  ///
  /// ⚠️ 真值由 `Store.settle()` 给，那属于业务规则（还没定）；
  /// 这里按"暴击 = 翻倍"倒推，未暴击时就是最终值 —— 演示档正好是后者。
  int get baseExp => crit ? exp ~/ 2 : exp;

  /// 暴击率百分比（整数）
  int get chancePct => (chance * 100).round();

  /// 与原型演示态一致的那一单结算（C 级主线第 5 环）
  static const QuestResult demo = QuestResult(
    quest: Quest.demo,
    beforeLv: 7,
    beforeExp: 214,
    beforeNeed: 340,
    exp: 50,
    coin: 24,
    attrs: <String, int>{'体': 1, '力': 1},
    streak: 7,
    streakUp: true,
    crit: false,
    dbl: false,
    photos: 0,
    chance: .12,
  );
}
