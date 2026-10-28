import 'package:flutter/foundation.dart';

/// 把 60fps 的动画通知压到指定帧率，用于「变化很慢、但每帧都在重建」的环境动画。
///
/// 用法：AnimationController/Ticker 继续按 vsync 推进，但 [pulse] 只在
/// 距上次通知超过 [minIntervalMs] 时才 notifyListeners()。这样 CustomPaint /
/// AnimatedBuilder 的重绘与 rebuild 次数直接按目标帧率下降，动画相位仍连续。
///
/// 注意：只改「提交频率」，不改动画时长与曲线；慢速环境动画（16s 星云、
/// 34s 核心环、18s 委托球）在 15~30fps 下肉眼几乎无差别。
class FrameThrottle extends ChangeNotifier {
  FrameThrottle(this.minIntervalMs);

  final int minIntervalMs;
  final Stopwatch _clock = Stopwatch()..start();
  int _lastMs = -1 << 30;

  void pulse() {
    final int now = _clock.elapsedMilliseconds;
    if (now - _lastMs < minIntervalMs) return;
    _lastMs = now;
    notifyListeners();
  }

  @override
  void dispose() {
    _clock.stop();
    super.dispose();
  }
}
