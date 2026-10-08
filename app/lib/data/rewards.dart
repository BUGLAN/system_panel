/// ═══════════════════════════════════════════════════════════
///  E~S 奖励数值表 + 升级曲线（docs/18 §2.3 · T6-2）
///
///  结算经济的**唯一可调常数家**：
///    · 经验 F0 / E1 / D2 / C4 / B6 / A8 / S10（F 是兼容档：仅老存档/
///      补救残单结算用，新生成任务不再出 F）
///    · 金币 F3 / E~C 5 / B7 / A10 / S20
///    · 升级曲线 need(lv) = 12 + lv × 6（lv1=18 … lv5=42 … lv10=72）
///    · 结算乘区（store.js:281-283）：暴击 ×2、双倍卡 ×2（可叠 ×4）、
///      补救单 ×0.5（金币吃暴击不吃双倍）
///
///  ⚠️ QuestFlow.settle 是这些数值的**执行者**（t2 移植时按本表写死，
///  迁移接管走返工卡）；[rewards_test] 用交叉断言钉住两边永不漂移。
///  道具价格不动（items.dart：dbl 60 / crit 45 / shield 90 / swap 30，
///  新金币量级下约 3~10 天攒一件）。
/// ═══════════════════════════════════════════════════════════
class Rewards {
  Rewards._();

  /// 经验表（F 兼容档 = 0）
  static const Map<String, int> kExpByRank = <String, int>{
    'F': 0, 'E': 1, 'D': 2, 'C': 4, 'B': 6, 'A': 8, 'S': 10,
  };

  /// 金币表（F3 / E~C 5 / B7 / A10 / S20）
  static const Map<String, int> kCoinByRank = <String, int>{
    'F': 3, 'E': 5, 'D': 5, 'C': 5, 'B': 7, 'A': 10, 'S': 20,
  };

  static int expOf(String rank) => kExpByRank[rank] ?? 0;
  static int coinOf(String rank) => kCoinByRank[rank] ?? 3;

  /// 升级曲线：`need(lv) = 12 + lv × 6`（单一可调常数，验收后可微调）。
  /// 节奏校验（docs/18 §2.3）：首目标 3 天得 1+2+4=7 EXP + 日常 2~8
  /// → 第 3~5 天升 LV2，正反馈对齐「首目标 3 天」。
  static int needFor(int lv) => 12 + lv * 6;

  /// 结算乘区（store.js:281-283 原样）
  static const int kCritMultiplier = 2;
  static const int kDblMultiplier = 2;
  static const double kRemedyFactor = .5;

  /// 一单的结算出账（纯函数 —— quest_flow.settle 的口径真源）。
  ///
  /// ```js
  /// const k = T.kind === 'remedy' ? .5 : 1;
  /// const baseExp = Math.round(R.exp * k);
  /// const exp = baseExp * (crit ? 2 : 1) * (A.dbl ? 2 : 1);
  /// const coin = Math.round(R.coin * k) * (crit ? 2 : 1);
  /// ```
  static Payout payout({
    required String rank,
    required bool crit,
    required bool dbl,
    bool remedy = false,
  }) {
    final double k = remedy ? kRemedyFactor : 1.0;
    final int baseExp = (expOf(rank) * k).round();
    final int exp =
        baseExp * (crit ? kCritMultiplier : 1) * (dbl ? kDblMultiplier : 1);
    final int coin =
        (coinOf(rank) * k).round() * (crit ? kCritMultiplier : 1);
    return Payout(baseExp: baseExp, exp: exp, coin: coin);
  }
}

/// 一单的出账：[baseExp] 是暴击/双倍**之前**那一跳（结算页第一行），
/// [exp]/[coin] 是最终入账。
class Payout {
  const Payout({required this.baseExp, required this.exp, required this.coin});

  final int baseExp;
  final int exp;
  final int coin;

  @override
  bool operator ==(Object other) =>
      other is Payout &&
      other.baseExp == baseExp &&
      other.exp == exp &&
      other.coin == coin;

  @override
  int get hashCode => Object.hash(baseExp, exp, coin);

  @override
  String toString() => 'Payout(base=$baseExp, exp=$exp, coin=$coin)';
}
