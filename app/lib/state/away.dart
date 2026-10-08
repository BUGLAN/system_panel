import '../data/content.dart';
import '../data/format.dart';

/// ═══════════════════════════════════════════════════════════
///  「她记得你走了多久」（flows.js L186-193）
///
///  原型在 `greet()` 里算 `away = now - S.prevSeen`，再按四档阈值选一句。
///  真源：
///  ```js
///  if (fromBoot || away > 6e4) {
///    let k = 'back10m';
///    if (away > 48 * 36e5) k = 'backLong';
///    else if (away > 20 * 36e5) k = 'back36h';
///    else if (away > 2 * 36e5) k = 'back12h';
///    else if (away > 10 * 6e4) k = 'back2h';
///  }
///  ```
///  注意 `36e5` = 3.6e6ms = **1 小时**（不是"36 小时"），三个阈值分别是
///  48 小时 / 20 小时 / 2 小时 —— 抄错这个常数会让"一整天没来"变成"两天没来"。
/// ═══════════════════════════════════════════════════════════
enum AwayKind {
  /// < 10 分钟
  back10m,

  /// 10 分钟 ~ 2 小时
  back2h,

  /// 2 ~ 20 小时
  back12h,

  /// 20 ~ 48 小时
  back36h,

  /// > 48 小时
  backLong,
}

class AwayGreeting {
  const AwayGreeting._();

  /// 低于这个时长她就不吭声了（`away > 6e4`）
  static const Duration quietBelow = Duration(seconds: 60);

  static const Duration _twoHours = Duration(hours: 2);
  static const Duration _twentyHours = Duration(hours: 20);
  static const Duration _fortyEightHours = Duration(hours: 48);
  static const Duration _tenMinutes = Duration(minutes: 10);

  /// 该说哪一句；`null` = 不用说（离开太短）
  static AwayKind? kindFor(Duration away) {
    if (away <= quietBelow) return null;
    if (away > _fortyEightHours) return AwayKind.backLong;
    if (away > _twentyHours) return AwayKind.back36h;
    if (away > _twoHours) return AwayKind.back12h;
    if (away > _tenMinutes) return AwayKind.back2h;
    return AwayKind.back10m;
  }

  /// 填好变量的那句话
  static String text(AwayKind k, Duration away) {
    switch (k) {
      case AwayKind.back10m:
        return LINES.back10m;
      case AwayKind.back2h:
        return LINES.back2h.replaceAll('{dur}', fmtDur(away));
      case AwayKind.back12h:
        return LINES.back12h.replaceAll('{dur}', fmtDur(away));
      case AwayKind.back36h:
        return LINES.back36h;
      case AwayKind.backLong:
        // 原型 `Math.round(away / 864e5)` —— 四舍五入到天
        final int days = (away.inMilliseconds / Duration.millisecondsPerDay)
            .round();
        return LINES.backLong.replaceAll('{days}', '$days');
    }
  }

  /// 一步到位：不值得说就返回 null
  static String? lineFor(Duration away) {
    final AwayKind? k = kindFor(away);
    return k == null ? null : text(k, away);
  }
}
