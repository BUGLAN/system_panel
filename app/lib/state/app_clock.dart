import 'dart:async';

import 'package:flutter/foundation.dart';

/// ═══════════════════════════════════════════════════════════
///  每秒时钟（flows.js L688 `App.second()` + ui.js `Exec.tick()`）
///
///  原型两条定时器：
///   · `setInterval(App.second, 1000)` —— 换日、走神、碎碎念、底栏刷新
///   · `setInterval(Exec.tick, 250)` —— **只在执行中跑**，刷计时器与时限条
///
///  ⚠️ 计时**不是累加**出来的，而是 `现在 - startAt`（原型 `Clock.now() - A.startAt`）
///  —— 这样息屏/切后台再回来，时间照样是对的。
/// ═══════════════════════════════════════════════════════════
class AppClock extends ChangeNotifier {
  AppClock({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  Timer? _sec;
  Timer? _fast;

  /// 当前时刻（每 250ms 或 1s 刷新一次）
  DateTime get now => _now();

  bool get running => _sec != null;

  /// 1 秒一次：`App.second()`
  void startSeconds(VoidCallback onSecond) {
    _sec?.cancel();
    _sec = Timer.periodic(const Duration(seconds: 1), (_) {
      onSecond();
      notifyListeners();
    });
  }

  /// 250ms 一次：`Exec.tick()` —— 只在执行中开
  void startFast() {
    _fast ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      notifyListeners();
    });
  }

  void stopFast() {
    _fast?.cancel();
    _fast = null;
  }

  @override
  void dispose() {
    _sec?.cancel();
    _fast?.cancel();
    super.dispose();
  }
}

/// 执行中这一单的读数（ui.js `Exec.tick()`）
class ExecReadout {
  const ExecReadout({
    required this.elapsed,
    required this.limit,
    required this.progress,
    required this.warn,
    required this.timedOut,
  });

  final Duration elapsed;
  final Duration limit;

  /// 时限条填充比例（原型 `clamp(e / lim * 100, 0, 100)`）
  final double progress;

  /// `e > lim * .85` —— 计时器转白并开始心跳
  final bool warn;

  /// `e >= lim` —— 原型在这里 `App.fail('timeout')`
  final bool timedOut;

  /// 剩余时间（负数表示已超）
  Duration get remaining => limit - elapsed;

  factory ExecReadout.of({
    required DateTime startAt,
    required DateTime now,
    required Duration limit,
  }) {
    final Duration e = now.difference(startAt);
    final double p = limit.inMilliseconds == 0
        ? 1
        : (e.inMilliseconds / limit.inMilliseconds).clamp(0.0, 1.0);
    return ExecReadout(
      elapsed: e.isNegative ? Duration.zero : e,
      limit: limit,
      progress: p,
      warn: e.inMilliseconds > limit.inMilliseconds * .85,
      timedOut: e.inMilliseconds >= limit.inMilliseconds,
    );
  }
}

/// 她主动开口（flows.js L693-706 的那两段）
///
///  · 大厅：距上次操作 > 6s 且距上句 26~42s → 一句碎碎念（夜里/清晨有专属的）
///  · 执行中：距上句 45~75s → 一句「还在？」；剩不到 3 分钟时改成报剩余
class ChatterScheduler {
  ChatterScheduler({double Function(double, double)? rand})
    : _rand = rand ?? ((double a, double b) => a + (b - a) * .5);

  final double Function(double, double) _rand;

  static const Duration idleGap = Duration(seconds: 26);
  static const Duration idleGapMax = Duration(seconds: 42);
  static const Duration execGap = Duration(seconds: 45);
  static const Duration execGapMax = Duration(seconds: 75);
  static const Duration quietAfterAction = Duration(seconds: 6);
  static const Duration dozeAfter = Duration(seconds: 80);

  Duration _nextIdle = Duration.zero;
  Duration _nextExec = Duration.zero;

  /// 下一次该开口的时刻（相对启动时长）
  Duration get idleNextAt => _nextIdle;
  Duration get execNextAt => _nextExec;

  void resetIdle(Duration uptime) {
    _nextIdle =
        uptime +
        Duration(
          milliseconds: _rand(
            idleGap.inMilliseconds.toDouble(),
            idleGapMax.inMilliseconds.toDouble(),
          ).round(),
        );
  }

  void resetExec(Duration uptime) {
    _nextExec =
        uptime +
        Duration(
          milliseconds: _rand(
            execGap.inMilliseconds.toDouble(),
            execGapMax.inMilliseconds.toDouble(),
          ).round(),
        );
  }

  bool idleDue(
    Duration uptime,
    Duration sinceAction, {
    required bool lineQuiet,
  }) => uptime >= _nextIdle && sinceAction >= quietAfterAction && lineQuiet;

  bool execDue(Duration uptime, {required bool lineQuiet}) =>
      uptime >= _nextExec && lineQuiet;
}
