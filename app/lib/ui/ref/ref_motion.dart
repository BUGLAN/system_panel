import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../design/fidelity.dart';
import '../../design/ref.dart';

/// ═══════════════════════════════════════════════════════════
///  参考稿的通用动效原语
///
///  · [RefReveal] —— `.rv` 进场（JS `reveal()` L1167）：
///      opacity 0→1、translateY 30→0、blur 8→0，680ms，
///      delay = base + i·80，cubic(.2,.9,.2,1)。每个场景换进来时
///      元素按顺序一层层「显影」。
///  · [RefBlink] —— `@keyframes blinkdot`：1s/1.4s 一呼一吸，50% 处 .25。
/// ═══════════════════════════════════════════════════════════
class RefReveal extends StatefulWidget {
  const RefReveal({
    super.key,
    required this.index,
    required this.child,
    this.base = 140,
  });

  final int index;
  final int base;
  final Widget child;

  @override
  State<RefReveal> createState() => _RefRevealState();
}

class _RefRevealState extends State<RefReveal>
    with SingleTickerProviderStateMixin, RefTimers<RefReveal> {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 680),
  );

  @override
  void initState() {
    super.initState();
    final bool reduce = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    if (reduce) {
      _c.value = 1;
      return;
    }
    later(Duration(milliseconds: widget.base + widget.index * 80), () {
      _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (BuildContext _, Widget? child) {
        final double v = _c.value;
        if (v >= 1) return child!;
        final double e = Ref.ease.transform(v);
        final double blur = 8 * (1 - e);
        Widget w = Transform.translate(
          offset: Offset(0, 30 * (1 - e)),
          child: child,
        );
        // 省电档跳过模糊（docs/49 E7）：每次换页 5~7 层同时做整块 blur，
        // 位移 + 透明已经足够把「显影」讲清楚
        if (blur > .3 && !Fidelity.lowPower.value) {
          w = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: blur / 2,
              sigmaY: blur / 2,
            ),
            child: w,
          );
        }
        return Opacity(opacity: e.clamp(0.0, 1.0), child: w);
      },
    );
  }
}

class RefBlink extends StatefulWidget {
  const RefBlink({
    super.key,
    required this.child,
    this.period = const Duration(milliseconds: 1000),
    this.low = .25,
    this.steps = false,
  });

  final Widget child;
  final Duration period;
  final double low;

  /// `steps(1)`：硬切（光标那种），否则线性呼吸
  final bool steps;

  @override
  State<RefBlink> createState() => _RefBlinkState();
}

class _RefBlinkState extends State<RefBlink>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void initState() {
    super.initState();
    final bool reduce = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    if (!reduce) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c.drive(
        TweenSequence<double>(<TweenSequenceItem<double>>[
          TweenSequenceItem<double>(
            tween: widget.steps
                ? ConstantTween<double>(1)
                : Tween<double>(begin: 1, end: widget.low),
            weight: 50,
          ),
          TweenSequenceItem<double>(
            tween: widget.steps
                ? ConstantTween<double>(widget.low)
                : Tween<double>(begin: widget.low, end: 1),
            weight: 50,
          ),
        ]),
      ),
      child: widget.child,
    );
  }
}

/// 一次性抖动（JS `shakeEl`：±9 / ±6，380ms）—— token 每变一次抖一回
class RefShakeX extends StatefulWidget {
  const RefShakeX({super.key, required this.token, required this.child});
  final int token;
  final Widget child;

  @override
  State<RefShakeX> createState() => _RefShakeXState();
}

class _RefShakeXState extends State<RefShakeX>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void didUpdateWidget(RefShakeX old) {
    super.didUpdateWidget(old);
    if (widget.token != old.token) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (BuildContext _, Widget? c) {
        if (!_c.isAnimating) return c!;
        const List<double> k = <double>[0, -9, 9, -6, 6, 0];
        final double p = _c.value * (k.length - 1);
        final int a = p.floor().clamp(0, k.length - 1);
        final int b = math.min(a + 1, k.length - 1);
        final double x = k[a] + (k[b] - k[a]) * (p - a);
        return Transform.translate(offset: Offset(x, 0), child: c);
      },
    );
  }
}

/// 参考稿 `coinFly(from, toEl, n, color)`（JS L1143-1150）：n 枚六边晶核
/// 沿二次贝塞尔从 [from] 飞到 [to]（中点随机偏 ±90 / 上抬 30~120），
/// 每枚 620 + i·40ms、错峰 40ms，途中放大 1.3 并转一圈；落地回调 [onLand]。
/// [token] 每变一次飞一轮。
class RefCoinFly extends StatefulWidget {
  const RefCoinFly({
    super.key,
    required this.token,
    required this.from,
    required this.to,
    this.n = 10,
    this.color = Ref.cyan,
    this.onLand,
  });

  final int token;
  final Offset from;
  final Offset to;
  final int n;
  final Color color;
  final VoidCallback? onLand;

  @override
  State<RefCoinFly> createState() => _RefCoinFlyState();
}

class _RefCoinFlyState extends State<RefCoinFly>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  final math.Random _rnd = math.Random();
  List<Offset> _mids = const <Offset>[];
  bool _landed = false;

  int get _totalMs => 620 + (widget.n - 1) * 80;

  @override
  void didUpdateWidget(RefCoinFly old) {
    super.didUpdateWidget(old);
    if (widget.token != old.token) _play();
  }

  void _play() {
    final Offset a = widget.from;
    final Offset b = widget.to;
    _mids = <Offset>[
      for (int i = 0; i < widget.n; i++)
        Offset(
          (a.dx + b.dx) / 2 + (_rnd.nextDouble() * 180 - 90),
          math.min(a.dy, b.dy) - (30 + _rnd.nextDouble() * 90),
        ),
    ];
    _landed = false;
    _c.duration = Duration(milliseconds: _totalMs);
    _c.forward(from: 0).then((_) {
      if (!_landed) {
        _landed = true;
        widget.onLand?.call();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (BuildContext _, Widget? _) {
          if (!_c.isAnimating || _mids.isEmpty) return const SizedBox.shrink();
          return CustomPaint(
            size: Size.infinite,
            painter: _CoinPainter(
              ms: _c.value * _totalMs,
              n: widget.n,
              from: widget.from,
              to: widget.to,
              mids: _mids,
              color: widget.color,
            ),
          );
        },
      ),
    );
  }
}

class _CoinPainter extends CustomPainter {
  _CoinPainter({
    required this.ms,
    required this.n,
    required this.from,
    required this.to,
    required this.mids,
    required this.color,
  });
  final double ms;
  final int n;
  final Offset from;
  final Offset to;
  final List<Offset> mids;
  final Color color;

  static const Cubic _ease = Cubic(.3, .1, .3, 1);

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < n; i++) {
      final double dur = 620.0 + i * 40;
      final double k = ((ms - i * 40) / dur).clamp(0.0, 1.0);
      if (k <= 0 || k >= 1) continue;
      final double e = _ease.transform(k);
      // 0~.45 段到中点、.45~1 段到终点（keyframes offset .45）
      final Offset p = e < .45
          ? Offset.lerp(from, mids[i], e / .45)!
          : Offset.lerp(mids[i], to, (e - .45) / .55)!;
      final double sc = e < .45
          ? .3 + (1.3 - .3) * (e / .45)
          : 1.3 + (.5 - 1.3) * ((e - .45) / .55);
      final double op = e < .45 ? e / .45 : 1 - .1 * ((e - .45) / .55);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(e * 2 * math.pi);
      canvas.scale(sc);
      final Path hex = Path()
        ..moveTo(0, -7)
        ..lineTo(7, -3.5)
        ..lineTo(7, 3.5)
        ..lineTo(0, 7)
        ..lineTo(-7, 3.5)
        ..lineTo(-7, -3.5)
        ..close();
      canvas.drawPath(hex, Paint()..color = color.withValues(alpha: op));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CoinPainter o) => o.ms != ms;
}

/// 场景里的延时一律走这里：State 销毁时一并取消（`Future.delayed` 取消不了，
/// 页面切走后回调还会跑、测试里还会报 pending timer）。
mixin RefTimers<T extends StatefulWidget> on State<T> {
  final Set<Timer> _refTimers = <Timer>{};

  /// [d] 之后执行 [f]（State 已销毁则不执行）
  void later(Duration d, VoidCallback f) {
    late final Timer t;
    t = Timer(d, () {
      _refTimers.remove(t);
      if (mounted) f();
    });
    _refTimers.add(t);
  }

  /// 可被销毁打断的等待（打断后 Future 永不完成，后续代码不会再跑）
  Future<void> pause(Duration d) {
    final Completer<void> c = Completer<void>();
    later(d, c.complete);
    return c.future;
  }

  @override
  void dispose() {
    for (final Timer t in _refTimers) {
      t.cancel();
    }
    _refTimers.clear();
    super.dispose();
  }
}
