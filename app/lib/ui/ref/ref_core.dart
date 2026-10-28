import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../design/fidelity.dart';
import '../../design/ref.dart';
import '../../widgets/frame_throttle.dart';

/// ═══════════════════════════════════════════════════════════
///  系统核心（她的替身）—— 参考稿 L1093-1105 的 coreSVG()
///
///  参考稿用 SVG 画「四层旋转环 + 一只眼 + 虹膜 + 呼吸 halo」，把「她」
///  之外的最小可辨识形象固定下来。这里用 CustomPainter 逐层复刻：
///    r1 半径 93、1.2px 虚线 1/5、34s 顺转（opacity .7）
///    r2 半径 81、2.5px 虚线 80/22/10/22、14s 逆转
///    r4 两段 72 半径弧、3.5px、22s 逆转（用 cc2）
///    r3 半径 64、1.4px 虚线 2/8、7s 顺转（.85）
///    eye 眼形 + iris（跟随指针）+ 高光点
///    happy / brow / heart 三套表情层（默认透明）
///    halo 呼吸 3.2s（scale 1 到 1.08）
///
///  情绪：happy 转 gold 且闭眼、angry 转 hot 且压扁眼并出眉、
///  scan 转 acid 且眼压到 .8、love 转粉且出心。
/// ═══════════════════════════════════════════════════════════
enum CoreMood { neutral, happy, angry, scan, love }

class RefCore extends StatefulWidget {
  const RefCore({
    super.key,
    required this.size,
    this.mood = CoreMood.neutral,
    this.accent = Ref.cyan,
    this.accent2 = Ref.acid,
    this.followPointer = false,
    this.animate = true,
  });

  final double size;
  final CoreMood mood;

  /// 主环色（情绪会覆盖它）
  final Color accent;

  /// 两道弧的色
  final Color accent2;

  /// 虹膜跟指针转（大厅那颗开）
  final bool followPointer;

  final bool animate;

  @override
  State<RefCore> createState() => _RefCoreState();
}

class _RefCoreState extends State<RefCore> with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 34),
  );
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  /// 34s 自转 + 3.2s 呼吸都慢，30fps 提交足够；60fps 会让这枚核心
  /// 每帧重建 Transform + 重画 4 层虚线环，是常驻 UI 线程大户。
  late final FrameThrottle _paintTick = FrameThrottle(33);

  Offset _iris = Offset.zero;
  bool _reduce = false;

  @override
  void initState() {
    super.initState();
    _spin.addListener(_paintTick.pulse);
    _breath.addListener(_paintTick.pulse);
    Fidelity.lowPower.addListener(_onFidelityChanged);
  }

  void _onFidelityChanged() {
    if (mounted) _syncMotion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncMotion();
  }

  void _syncMotion() {
    if (_reduce || !widget.animate || Fidelity.lowPower.value) {
      _spin.stop();
      _breath.stop();
    } else {
      if (!_spin.isAnimating) _spin.repeat();
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    Fidelity.lowPower.removeListener(_onFidelityChanged);
    _spin.removeListener(_paintTick.pulse);
    _breath.removeListener(_paintTick.pulse);
    _paintTick.dispose();
    _spin.dispose();
    _breath.dispose();
    super.dispose();
  }

  void _aim(Offset local) {
    if (!widget.followPointer) return;
    final Offset c = Offset(widget.size / 2, widget.size / 2);
    final Offset d = local - c;
    final double len = d.distance;
    if (len < 1) return;
    final double m = math.min(15, len / 12);
    setState(() => _iris = Offset(d.dx / len, d.dy / len) * m);
  }

  @override
  Widget build(BuildContext context) {
    final (Color cc, Color cc2) = switch (widget.mood) {
      CoreMood.happy => (Ref.gold, widget.accent2),
      CoreMood.angry => (Ref.hot, widget.accent2),
      CoreMood.scan => (Ref.acid, widget.accent2),
      CoreMood.love => (const Color(0xFFFF7AB6), widget.accent2),
      CoreMood.neutral => (widget.accent, widget.accent2),
    };
    return MouseRegion(
      onHover: (PointerHoverEvent e) => _aim(e.localPosition),
      child: Listener(
        onPointerMove: (PointerMoveEvent e) => _aim(e.localPosition),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _paintTick,
              builder: (BuildContext context, Widget? _) {
                final bool reduce = _reduce;
                final double breath = reduce
                    ? 1
                    : 1 + .04 * Ref.ease.transform(_breath.value);
                return Transform.scale(
                  scale: breath,
                  child: CustomPaint(
                    painter: _CorePainter(
                      mood: widget.mood,
                      cc: cc,
                      cc2: cc2,
                      t: reduce ? 0 : _spin.value,
                      iris: _iris,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CorePainter extends CustomPainter {
  const _CorePainter({
    required this.mood,
    required this.cc,
    required this.cc2,
    required this.t,
    required this.iris,
  });

  final CoreMood mood;
  final Color cc;
  final Color cc2;
  final double t;
  final Offset iris;

  static const double _vb = 200;

  @override
  void paint(Canvas canvas, Size s) {
    if (s.isEmpty) return;
    final double k = s.width / _vb;
    final Offset c = Offset(s.width / 2, s.height / 2);
    double u(double v) => v * k;

    void ring(
      double r,
      double sw,
      List<double> dash,
      double spin,
      Color color, {
      double opacity = 1,
    }) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(spin);
      canvas.translate(-c.dx, -c.dy);
      final Rect rect = Rect.fromCircle(center: c, radius: u(r));
      final Paint p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw * k
        ..color = color.withAlpha((opacity * 255).round());
      if (dash.length == 2 && dash[1] == 0) {
        canvas.drawCircle(c, u(r), p);
      } else {
        double acc = 0;
        final double circ = 2 * math.pi * u(r);
        int i = 0;
        while (acc < circ) {
          final double d = dash[i % dash.length] * k;
          if (i.isEven) {
            canvas.drawArc(rect, acc / u(r), d / u(r), false, p);
          }
          acc += d;
          i++;
        }
      }
      canvas.restore();
    }

    // 1) halo：径向渐变球（.5 峰值）
    final double haloR = u(99);
    canvas.drawCircle(
      c,
      haloR,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[cc.withAlpha(128), cc.withAlpha(26), cc.withAlpha(0)],
          stops: const <double>[0, .55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: haloR)),
    );

    // 2) r1 / r2 / r3
    ring(93, 1.2, <double>[1, 5], t * 2 * math.pi, cc, opacity: .7);
    ring(81, 2.5, <double>[80, 22, 10, 22], -t * (34 / 14) * 2 * math.pi, cc);
    ring(64, 1.4, <double>[2, 8], t * (34 / 7) * 2 * math.pi, cc, opacity: .85);

    // 3) r4：两段 90 度弧
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-t * (34 / 22) * 2 * math.pi);
    canvas.translate(-c.dx, -c.dy);
    final Paint arcP = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = u(3.5)
      ..strokeCap = StrokeCap.round
      ..color = cc2;
    final Rect r72 = Rect.fromCircle(center: c, radius: u(72));
    canvas.drawArc(r72, -math.pi / 2, math.pi * .5, false, arcP);
    canvas.drawArc(r72, math.pi / 2, math.pi * .5, false, arcP);
    canvas.restore();

    // 4) 眼
    final bool closedEye = mood == CoreMood.happy || mood == CoreMood.love;
    final double eyeScaleY = switch (mood) {
      CoreMood.angry => .6,
      CoreMood.scan => .8,
      _ => 1,
    };
    if (closedEye) {
      final Paint p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u(9)
        ..strokeCap = StrokeCap.round
        ..color = closedEye && mood == CoreMood.love ? cc : cc;
      final Path path = Path()
        ..moveTo(c.dx - u(42), c.dy + u(12))
        ..quadraticBezierTo(c.dx, c.dy - u(34), c.dx + u(42), c.dy + u(12));
      canvas.drawPath(path, p);
    } else {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(1, eyeScaleY);
      canvas.translate(-c.dx, -c.dy);
      final Path eye = Path()
        ..moveTo(c.dx - u(64), c.dy)
        ..quadraticBezierTo(c.dx, c.dy - u(56), c.dx + u(64), c.dy)
        ..quadraticBezierTo(c.dx, c.dy + u(56), c.dx - u(64), c.dy)
        ..close();
      canvas.drawPath(eye, Paint()..color = const Color(0xE606050E));
      canvas.drawPath(
        eye,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = u(3)
          ..color = cc,
      );
      final Offset ic = c + iris * k;
      canvas.drawCircle(
        ic,
        u(26),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = u(2)
          ..color = cc,
      );
      canvas.drawCircle(ic, u(19), Paint()..color = cc.withAlpha(56));
      canvas.drawCircle(ic, u(10), Paint()..color = cc);
      canvas.drawCircle(
        ic + Offset(-u(8), -u(8)),
        u(4),
        Paint()..color = Colors.white,
      );
      canvas.restore();
    }

    // 5) angry 眉
    if (mood == CoreMood.angry) {
      final Paint p = Paint()
        ..strokeWidth = u(7)
        ..strokeCap = StrokeCap.round
        ..color = Ref.hot;
      canvas.drawLine(
        Offset(c.dx - u(50), c.dy - u(42)),
        Offset(c.dx - u(10), c.dy - u(24)),
        p,
      );
      canvas.drawLine(
        Offset(c.dx + u(50), c.dy - u(42)),
        Offset(c.dx + u(10), c.dy - u(24)),
        p,
      );
    }

    // 6) love 的心
    if (mood == CoreMood.love) {
      final Path heart = Path()
        ..moveTo(c.dx, c.dy - u(16))
        ..cubicTo(
          c.dx - u(42),
          c.dy - u(42),
          c.dx - u(40),
          c.dy - u(78),
          c.dx - u(16),
          c.dy - u(80),
        )
        ..cubicTo(
          c.dx - u(5),
          c.dy - u(81),
          c.dx,
          c.dy - u(71),
          c.dx,
          c.dy - u(66),
        )
        ..cubicTo(
          c.dx,
          c.dy - u(71),
          c.dx + u(5),
          c.dy - u(81),
          c.dx + u(16),
          c.dy - u(80),
        )
        ..cubicTo(
          c.dx + u(40),
          c.dy - u(78),
          c.dx + u(42),
          c.dy - u(42),
          c.dx,
          c.dy - u(16),
        )
        ..close();
      canvas.drawPath(heart, Paint()..color = cc);
    }
  }

  @override
  bool shouldRepaint(_CorePainter o) =>
      o.mood != mood ||
      o.cc != cc ||
      o.t != t ||
      o.iris != iris ||
      o.cc2 != cc2;
}
