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
    this.near = 0,
    // ── T2 补全：真实结算（store.js settle() 返回值）的其余字段 ──
    this.ups = const <int>[],
    this.titles = const <String>[],
    this.planClear = -1,
    this.finale = false,
    this.redeemed = false,
    this.empty = false,
    this.tooFast = false,
    this.held = Duration.zero,
    this.afterLv,
    this.afterNeed,
    this.endExp,
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

  /// 暴击判定**差了多少**（百分点）。原型 `store.js` L280：
  ///
  /// ```js
  /// const near = !crit && roll - chance < .08
  ///   ? Math.max(1, Math.round((roll - chance) * 100)) : 0;
  /// ```
  ///
  /// 只有"差不到 8% 就中"才有值，其余是 0 —— 而 `#rsNear` 那一行
  /// **只在有值（或 0 份证据）时才显示**，否则整行 opacity 0。
  final int near;

  Rarity get rarity => quest.rarity;

  // ── T2 补全的字段（demo 档全部走默认值，老界面零感知）──────────

  /// 升到的每一级（空 = 这一单没升级；原型 `res.ups`）
  final List<int> ups;

  /// 本次解锁的称号 id（原型 `res.titles`）
  final List<String> titles;

  /// 点亮的主线环（-1 = 非主线单或主线未推进；原型 `res.planClear`）
  final int planClear;

  /// 主线收官（最后一环也清了）
  final bool finale;

  /// 补救单抵消了那次失败（原型 `res.redeemed`）
  final bool redeemed;

  /// 队列空了 —— 结算页该弹【收工。】而不是【再来一单。】
  final bool empty;

  /// 执行不足 60 秒就交（她会拆穿）
  final bool tooFast;

  /// 这单执行了多久
  final Duration held;

  /// 结算后的等级 / 升级所需（升级过才与 before 不同；null = 未升级）
  final int? afterLv;
  final int? afterNeed;

  /// 结算后的经验余额（升级过时 ≠ beforeExp + exp；原型 `res.after.exp`）
  final int? endExp;

  /// 结算后停在几级（界面 LV 读数）
  int get lvAfter => afterLv ?? beforeLv;

  /// 结算后"升到下一级"所需（经验条分母；升级后会换档）
  int get finalNeed => afterNeed ?? beforeNeed;

  /// 结算后的经验读数：没升级 = beforeExp + exp；升级过 = 溢出后的余额
  /// （原型 `res.after.exp`）
  int get expAfterSettle => ups.isEmpty ? afterExp : (endExp ?? exp);

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
