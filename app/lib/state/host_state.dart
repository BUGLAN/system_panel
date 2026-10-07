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
  });

  final String name;
  final int lv;
  final int exp;
  final int coins;
  final int streak;

  /// 已挂上的称号（原型的 Store.title）
  final String title;

  /// 她手里还有几单
  final int queue;

  /// 主线：脚下第几环（0 基）与总环数
  final int ringIndex;
  final int ringTotal;

  /// 升到下一级要的经验（store.js L5：`need = lv => 60 + lv * 40`）
  static int need(int lv) => 60 + lv * 40;

  /// 经验环的进度（HUD 里 `clamp(exp / need(lv), 0, 1)`）
  double get expRatio => (exp / need(lv)).clamp(0.0, 1.0);

  /// 原型 `Store.veteran()` 建出来的那一档（实测：exp 214 / need 340 / 金币 340）
  static const HostState demo = HostState(
    name: '林深',
    lv: 7,
    exp: 214,
    coins: 340,
    streak: 6,
    title: '惯犯',
    queue: 5,
    ringIndex: 4,
    ringTotal: 8,
  );

  static const HostState empty = HostState(
    name: '宿主',
    lv: 1,
    exp: 0,
    coins: 0,
    streak: 0,
    title: '新绑定的',
    queue: 0,
    ringIndex: -1,
    ringTotal: 0,
  );
}
