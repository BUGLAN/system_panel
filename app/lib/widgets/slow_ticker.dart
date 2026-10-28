import 'dart:async';

import 'package:flutter/foundation.dart';

/// 低频环境动画时钟：用 Timer 而不是 Ticker。
///
/// Flutter 的 Ticker 即使回调里不 setState，也会每个 vsync 唤醒一次并让
/// 引擎走一遍帧调度；对 10~30fps 就够的慢动画，这是常驻的 CPU/GPU 成本。
/// [SlowTicker] 只在 [period] 到点时 notifyListeners，画面不变时完全不排帧。
class SlowTicker extends ChangeNotifier {
  SlowTicker(this.period);

  final Duration period;
  Timer? _timer;
  double _value = 0;

  /// 累计秒数（从 start/reset 起算）
  double get value => _value;

  bool get isActive => _timer != null;

  void start({bool reset = false}) {
    if (reset) _value = 0;
    if (_timer != null) return;
    _timer = Timer.periodic(period, (_) {
      _value += period.inMicroseconds / 1e6;
      notifyListeners();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void reset() {
    _value = 0;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
