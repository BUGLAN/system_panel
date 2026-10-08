/// ═══════════════════════════════════════════════════════════
///  结算演出的时间线（`flows.js` L365-430 `settle()`）
///
///  和派单揭晓一样，原型整段是 `await sleep/tween` 串起来的；
///  这里抽成"给一个时刻 t，算出卡片该显示成什么样"，
///  界面只要一个控制器从头播到尾，时序用单测钉死。
///
///  原型分五段：
///   ① 验收 `w(820)`：证据飞向她、扫描线扫一遍（780ms 动画）
///   ② 落定 `w(380)`：印章砸下 + 亮帧 + 抖 + 爆散
///   ③ 展开：`#rsHead.on` 180 → `#rsCard.on` 160
///   ④ 数字往上跳：800ms →（暴击）等 200 + 520 →（双倍）等 160 + 480
///   ⑤ 经验条 + 筹码：条 520ms → 等 120 → 金币/属性/连击各隔 110ms
/// ═══════════════════════════════════════════════════════════
library;

class SettleTimeline {
  SettleTimeline({
    required this.baseExp,
    required this.finalExp,
    this.crit = false,
    this.dbl = false,
    this.chipCount = 3,
  });

  /// 基础经验（原型 `res.baseExp`）
  final int baseExp;

  /// 最终入账的经验（原型 `res.exp`）
  final int finalExp;

  final bool crit;
  final bool dbl;

  /// 结算页下面有几枚筹码（金币 + 各维度 + 连击）
  final int chipCount;

  // ── 原型的常数，逐条抄 ────────────────────────────────────
  static const double scanDur = 780; // `scan.animate({ duration: 780 })`
  static const double scanHold = 820; // `await w(820)`
  static const double impactHold = 380; // `await w(380)`
  static const double headHold = 180; // `await w(180)`
  static const double cardHold = 160; // `await w(160)`
  static const double countDur = 800; // `count(0, baseExp, 800)`
  static const double critWait = 200; // `await w(200)` 之后打 CRIT
  static const double critDur = 520; // `count(cur, cur*2, 520)`
  static const double dblWait = 160; // `await w(160)` 之后打双倍卡
  static const double dblDur = 480; // `count(cur, res.exp, 480)`
  static const double barDur = 520; // 不跨级：`to(pct, 520)`
  static const double barWait = 120; // `await w(120)` 之后发筹码
  static const double chipGap = 110; // 每枚筹码隔 110ms

  /// ① 开始（扫描线 0 点）
  static const double scanAt = 0;

  /// ② 印章砸下的时刻
  double get impactAt => scanHold;

  /// ③ 抬头 / 卡片展开的时刻
  double get headAt => impactAt + impactHold;
  double get cardAt => headAt + headHold;

  /// ④ 数字开始跳
  double get countAt => cardAt + cardHold;
  double get countEnd => countAt + countDur;

  double get critAt => countEnd + (crit ? critWait : 0);
  double get critEnd => crit ? critAt + critDur : critAt;

  double get dblAt => critEnd + (dbl ? dblWait : 0);
  double get dblEnd => dbl ? dblAt + dblDur : dblAt;

  /// ⑤ 经验条与筹码
  double get barAt => dblEnd;
  double get barEnd => barAt + barDur;
  double get chipAt => barEnd + barWait;

  /// 第 i 枚筹码出现的时刻（0 基）
  double chipAtOf(int i) => chipAt + i * chipGap;

  /// 「保存战报」可点的时刻（原型给 `#rsSave` 加 `.on`）—— 最后一枚筹码之后再稳一下
  double get saveAt =>
      (chipCount <= 0 ? chipAt : chipAtOf(chipCount - 1)) + 220;

  double get total => saveAt + 320;

  // ── 由时刻推算状态 ────────────────────────────────────────

  /// 此刻数字应该显示多少（原型那个 `count()` 是线性 `lerp`）
  int expAt(double t) {
    if (t < countAt) return 0;
    if (t < countEnd) return _lerpInt(0, baseExp, (t - countAt) / countDur);
    final int afterCrit = crit ? baseExp * 2 : baseExp;
    if (!crit) {
      if (t < dblAt) return baseExp;
      if (t < dblEnd) {
        return _lerpInt(baseExp, finalExp, (t - dblAt) / dblDur);
      }
      return finalExp;
    }
    if (t < critEnd) {
      return _lerpInt(baseExp, afterCrit, (t - critAt) / critDur);
    }
    if (!dbl) return afterCrit;
    if (t < dblAt) return afterCrit;
    if (t < dblEnd) return _lerpInt(afterCrit, finalExp, (t - dblAt) / dblDur);
    return finalExp;
  }

  /// 印章：0 = 还没有，1 = CRIT，2 = 双倍卡（原型往 `#rsTags` 追加两个 span）
  int stampAt(double t) {
    if (dbl && t >= dblAt) return 2;
    if (crit && t >= critAt) return 1;
    return 0;
  }

  /// 经验条此刻的填充比例（0~1）
  ///
  /// 静态终态由外部传进来的 `barFrom/barTo` 决定；这里只管"涨"的那一下。
  double barProgressAt(double t) {
    if (t <= barAt) return 0;
    if (t >= barEnd) return 1;
    return (t - barAt) / barDur;
  }

  /// ②③ 的门（原型是 `.on` 类，加了就一直开着）
  bool headOn(double t) => t >= headAt;
  bool cardOn(double t) => t >= cardAt;
  bool saveOn(double t) => t >= saveAt;

  /// 第 i 枚筹码此刻出现了吗
  bool chipOn(int i, double t) => t >= chipAtOf(i);

  /// 稀有度大字砸下来的进度（`@keyframes slam` 700ms）。
  /// `null` = 还没开始砸（此时它应该整块不显示）
  static const double slamDur = 700;

  double? slamAt(double t) {
    if (t < impactAt) return null;
    return ((t - impactAt) / slamDur).clamp(0.0, 1.0);
  }

  /// 扫描线此刻在画面里的纵向位置（原型 `top: 6% → 58%`）与透明度
  ///
  /// `scan.animate([{top:'6%',opacity:0},{opacity:1,offset:.15},{top:'58%',opacity:0}], 780)`
  static const double scanFromPct = .06;
  static const double scanToPct = .58;

  double scanTopPct(double t) {
    final double k = (t / scanDur).clamp(0.0, 1.0);
    return scanFromPct + (scanToPct - scanFromPct) * k;
  }

  double scanOpacity(double t) {
    final double k = (t / scanDur).clamp(0.0, 1.0);
    // 关键帧：0% → 0，15% → 1，100% → 0
    if (k <= .15) return k / .15;
    return 1 - (k - .15) / .85;
  }

  /// 证据飞行的每一道起始延迟（原型 `setTimeout(..., i * 90)`）
  static double streakDelay(int i) => i * 90.0;

  static int _lerpInt(int a, int b, double k) =>
      (a + (b - a) * k.clamp(0.0, 1.0)).round();
}
