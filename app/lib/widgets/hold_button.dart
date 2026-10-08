import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// ═══════════════════════════════════════════════════════════
///  按住类按钮（原型里三处：接单指纹 / 认输 / 重置存档）
///
///  三处用的是同一套推进逻辑，只是参数不同（`ui.js` L297 / L449 / L624）：
///   · 指纹接单：按满 **0.9s**，松手以 **0.35s** 退回
///   · 认输：    按满 **1.2s**，松手以 **0.30s** 退回
///   · 重置存档：按满 **2.0s**，松手以 **1.00s** 退回
///  每帧 `p = clamp(p + (按住 ? dt/满 : -dt/退), 0, 1)`，`p >= 1` 触发完成。
///
///  ⚠️ 别用 `AnimationController` 的 `forward/reverse` —— 那样松手是"反向播放"，
///  速度跟按下的进度挂钩；原型是**固定速率退回**，两者手感不一样。
/// ═══════════════════════════════════════════════════════════
class HoldButton extends StatefulWidget {
  const HoldButton({
    super.key,
    required this.duration,
    required this.builder,
    required this.onComplete,
    this.decay = const Duration(milliseconds: 350),
    this.onProgress,
    this.steps = 0,
    this.onStep,
    this.onRelease,
    this.enabled = true,
  });

  /// 按住多久算完成
  final Duration duration;

  /// 松手后多久退回 0
  final Duration decay;

  /// `p` ∈ [0,1] → 长什么样
  final Widget Function(BuildContext context, double p) builder;

  /// `p` 到 1 时触发
  final VoidCallback onComplete;

  /// 每一帧回报进度（认输用它驱动 veil 的暗度）
  final ValueChanged<double>? onProgress;

  /// 每推进 `1/steps` 报一次（指纹是 8，用来打点）
  final int steps;
  final ValueChanged<double>? onStep;

  /// 没按满就松手时回调，参数是松手那一刻的进度。
  /// 原型 `Plate.hold()` 用它决定要不要说那句 `waver`（`p > .25` 才说，且只说一次）。
  final ValueChanged<double>? onRelease;

  final bool enabled;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;
  double _p = 0;
  bool _holding = false;
  bool _fired = false;

  double get _full => widget.duration.inMicroseconds / 1e6;
  double get _back => widget.decay.inMicroseconds / 1e6;

  void _start() {
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration now) {
    final double dt = _last == Duration.zero
        ? 1 / 60
        : (now - _last).inMicroseconds / 1e6;
    _last = now;
    final double prev = _p;
    _p = (_p + (_holding ? dt / _full : -dt / _back)).clamp(0.0, 1.0);
    setState(() {});
    widget.onProgress?.call(_p);
    if (widget.steps > 0) {
      final int st = (_p * widget.steps).floor();
      final int was = (prev * widget.steps).floor();
      if (_holding && st != was) widget.onStep?.call(_p);
    }
    if (_p >= 1) {
      _holding = false;
      _ticker.stop();
      if (!_fired) {
        _fired = true;
        widget.onComplete();
      }
      return;
    }
    if (!_holding && _p <= 0) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// 松手（原型 `up()`）：`if (!holding) return`，没按满就回报一次进度
  void _release() {
    if (!_holding) return;
    _holding = false;
    if (_p < 1) widget.onRelease?.call(_p);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // 整块都可按（原型这几个按钮都有 `touch-action: none`）；
      // 默认的 deferToChild 会在子节点不可命中时漏掉按下
      behavior: HitTestBehavior.opaque,
      onPointerDown: widget.enabled
          ? (PointerDownEvent _) {
              _holding = true;
              _start();
            }
          : null,
      onPointerUp: widget.enabled ? (PointerUpEvent _) => _release() : null,
      onPointerCancel: widget.enabled
          ? (PointerCancelEvent _) => _release()
          : null,
      child: widget.builder(context, _p),
    );
  }
}
