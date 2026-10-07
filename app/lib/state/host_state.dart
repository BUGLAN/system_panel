/// 宿主档案 —— 对应原型 `Store.S` 里被界面读到的那部分。
///
/// 行为逻辑（存盘、发单、结算、连击规则）尚未由宿主约束，所以这里**只是数据**，
/// 先放一份与原型「老宿主 · 第 23 天」逐字段一致的演示档，
/// 好让界面能与原型做同状态比对。
class HostState {
  const HostState({
    required this.name,
    required this.lv,
    required this.exp,
    required this.coins,
    required this.streak,
    required this.title,
    required this.queue,
    required this.ringIndex,
    required this.ringTotal,
    required this.attrs,
    required this.doneCount,
    required this.critCount,
    required this.failCount,
    required this.bestStreak,
    required this.ownedTitles,
    required this.items,
  });

  final String name;
  final int lv;
  final int exp;
  final int coins;
  final int streak;

  /// 已挂上的称号 id（原型的 `Store.title`）
  final String title;

  /// 她手里还有几单
  final int queue;

  /// 主线：脚下第几环（0 基）与总环数
  final int ringIndex;
  final int ringTotal;

  /// 六维，键是单字（力/敏/体/智/知/魅）
  final Map<String, int> attrs;

  /// stats.done / stats.crit / stats.fail
  final int doneCount;
  final int critCount;
  final int failCount;

  final int bestStreak;

  /// 已解锁的称号 id
  final List<String> ownedTitles;

  /// 道具持有数（key → 数量）
  final Map<String, int> items;

  /// 升到下一级要的经验（store.js L5：`need = lv => 60 + lv * 40`）
  static int need(int lv) => 60 + lv * 40;

  /// 经验环的进度（HUD 里 `clamp(exp / need(lv), 0, 1)`）
  double get expRatio => (exp / need(lv)).clamp(0.0, 1.0);

  /// 最弱的一维（`Store.weakest()`）—— 档案雷达里那一轴会变灰
  MapEntry<String, int> get weakest => attrs.entries.reduce(
    (MapEntry<String, int> a, MapEntry<String, int> b) =>
        b.value < a.value ? b : a,
  );

  /// 原型 `Store.veteran()` 建出来的那一档（实测：exp 214 / need 340 / 金币 340）
  static const HostState demo = HostState(
    name: '林深',
    lv: 7,
    exp: 214,
    coins: 340,
    streak: 6,
    title: 'done15',
    queue: 5,
    ringIndex: 4,
    ringTotal: 8,
    attrs: <String, int>{'力': 9, '敏': 12, '体': 17, '智': 6, '知': 8, '魅': 4},
    doneCount: 31,
    critCount: 6,
    failCount: 4,
    bestStreak: 6,
    ownedTitles: <String>[
      'bind',
      'first',
      'crit',
      'done5',
      'redeem',
      'streak3',
      'done15',
    ],
    items: <String, int>{'dbl': 2, 'crit': 1, 'shield': 0, 'swap': 0},
  );

  static const HostState empty = HostState(
    name: '宿主',
    lv: 1,
    exp: 0,
    coins: 0,
    streak: 0,
    title: 'bind',
    queue: 0,
    ringIndex: -1,
    ringTotal: 0,
    attrs: <String, int>{'力': 0, '敏': 0, '体': 0, '智': 0, '知': 0, '魅': 0},
    doneCount: 0,
    critCount: 0,
    failCount: 0,
    bestStreak: 0,
    ownedTitles: <String>['bind'],
    items: <String, int>{'dbl': 0, 'crit': 0, 'shield': 0, 'swap': 0},
  );
}
