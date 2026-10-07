import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// ═══════════════════════════════════════════════════════════
///  屏幕空间特效（js/fx.js）—— 火花 / 爆散 / 上升尘 / 涟漪 / 光痕
///
///  全部走**加色混合**（canvas2d `lighter` → Flutter `BlendMode.plus`）。
///  原型是"有粒子就跑 rAF、跑完清空画布"，这里等价于 Ticker 按需启停。
///
///  各处调用的原参数（写进注释，避免以后凭感觉改）：
///   · 激光刻字 `spark(x,y,6,'#bff6ff')`
///   · 结算爆散 `burst(cx,cy,{n:60,cols:['#38e1ff','#e9fbff','#7fdcff']})`
///   · 证据入槽 `burst(r.cx,r.cy,{n:16,max:160,life:.5})`
///   · 钤印涟漪 `ripple(r.cx,r.cy,{r1:300,flat:.38,col:'#bff6ff',w:3,ms:700})`
/// ═══════════════════════════════════════════════════════════
class FxParticle {
  FxParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.max,
    required this.size,
    required this.color,
    required this.kind,
    required this.gravity,
    required this.drag,
    this.rot = 0,
    this.vr = 0,
  });

  double x, y, vx, vy;
  double life = 0;
  final double max;
  final double size;
  final Color color;

  /// 'line'（火花）| 'shard'（碎片）| 'dot'（尘）
  final String kind;
  final double gravity;
  final double drag;
  double rot;
  final double vr;
}

class FxRipple {
  FxRipple({
    required this.x,
    required this.y,
    required this.max,
    required this.r0,
    required this.r1,
    required this.color,
    required this.flat,
    required this.w,
  });

  final double x, y, max, r0, r1, flat, w;
  final Color color;
  double t = 0;
}

class FxStreak {
  FxStreak({
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
    required this.max,
    required this.color,
    required this.w,
  });

  final double x0, y0, x1, y1, max, w;
  final Color color;
  double t = 0;
}

/// 命令式入口 —— 与原型 `FX.spark()` / `FX.burst()` 一一对应
class FxController extends ChangeNotifier {
  FxController({math.Random? rnd}) : _rnd = rnd ?? math.Random();

  final math.Random _rnd;
  final List<FxParticle> parts = <FxParticle>[];
  final List<FxRipple> rips = <FxRipple>[];
  final List<FxStreak> streaks = <FxStreak>[];

  static const List<Color> _burstCols = <Color>[
    Color(0xFF38E1FF),
    Color(0xFFE9FBFF),
    Color(0xFF7FDCFF),
  ];

  bool get busy => parts.isNotEmpty || rips.isNotEmpty || streaks.isNotEmpty;

  double _r(double a, double b) => a + _rnd.nextDouble() * (b - a);

  /// 激光刻字的火花：短、亮、往下掉
  void spark(
    double x,
    double y, {
    int n = 6,
    Color color = const Color(0xFFBFF6FF),
  }) {
    for (int i = 0; i < n; i++) {
      final double a = _r(-math.pi, 0) + _r(-.4, .4);
      final double v = _r(80, 320);
      parts.add(
        FxParticle(
          x: x,
          y: y,
          vx: math.cos(a) * v,
          vy: math.sin(a) * v,
          max: _r(.18, .45),
          size: _r(.8, 1.8),
          color: color,
          kind: 'line',
          gravity: 900,
          drag: .9,
        ),
      );
    }
    notifyListeners();
  }

  /// 结算爆散
  void burst(
    double x,
    double y, {
    int n = 60,
    List<Color>? cols,
    double min = 120,
    double max = 620,
    double flat = 1,
    double life = 1.3,
    double size = 3.2,
    double shards = .35,
    double g = 160,
    double drag = .965,
  }) {
    final List<Color> c = cols ?? _burstCols;
    for (int i = 0; i < n; i++) {
      final double a = _r(0, math.pi * 2);
      final double v = _r(min, max);
      parts.add(
        FxParticle(
          x: x,
          y: y,
          vx: math.cos(a) * v,
          vy: math.sin(a) * v * flat,
          max: _r(.5, life),
          size: _r(1, size),
          color: c[_rnd.nextInt(c.length)],
          kind: _rnd.nextDouble() < shards ? 'shard' : 'dot',
          gravity: g,
          drag: drag,
          rot: _r(0, 6),
          vr: _r(-12, 12),
        ),
      );
    }
    notifyListeners();
  }

  /// 往上飘的数据尘
  void rise(
    double x,
    double y, {
    int n = 20,
    Color color = const Color(0xFF38E1FF),
  }) {
    for (int i = 0; i < n; i++) {
      parts.add(
        FxParticle(
          x: x + _r(-60, 60),
          y: y + _r(-10, 30),
          vx: _r(-14, 14),
          vy: _r(-140, -40),
          max: _r(.8, 1.6),
          size: _r(1, 2.4),
          color: color,
          kind: 'dot',
          gravity: -20,
          drag: .99,
        ),
      );
    }
    notifyListeners();
  }

  void ripple(
    double x,
    double y, {
    int ms = 900,
    double r0 = 10,
    double r1 = 260,
    Color color = const Color(0xFF38E1FF),
    double flat = 1,
    double w = 2,
  }) {
    rips.add(
      FxRipple(
        x: x,
        y: y,
        max: ms / 1000,
        r0: r0,
        r1: r1,
        color: color,
        flat: flat,
        w: w,
      ),
    );
    notifyListeners();
  }

  void streak(
    double x0,
    double y0,
    double x1,
    double y1, {
    int ms = 420,
    Color color = const Color(0xFFE9FBFF),
    double w = 3,
  }) {
    streaks.add(
      FxStreak(
        x0: x0,
        y0: y0,
        x1: x1,
        y1: y1,
        max: ms / 1000,
        color: color,
        w: w,
      ),
    );
    notifyListeners();
  }

  void clear() {
    parts.clear();
    rips.clear();
    streaks.clear();
  }

  /// 推进一帧（fx.js `_loop` L63-101）
  void step(double dtRaw) {
    final double dt = math.min(.05, dtRaw);
    for (final FxParticle p in parts) {
      p.life += dt;
      final double k = math.pow(p.drag, dt * 60).toDouble();
      p.vx *= k;
      p.vy = p.vy * k + p.gravity * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      if (p.kind == 'shard') p.rot += p.vr * dt;
    }
    parts.removeWhere((FxParticle p) => p.life >= p.max);
    for (final FxRipple r in rips) {
      r.t += dt;
    }
    rips.removeWhere((FxRipple r) => r.t / r.max >= 1);
    for (final FxStreak s in streaks) {
      s.t += dt;
    }
    streaks.removeWhere((FxStreak s) => s.t / s.max >= 1);
  }
}

/// `#fx` 画布
class FxField extends StatefulWidget {
  const FxField({super.key, required this.controller});

  final FxController controller;

  @override
  State<FxField> createState() => _FxFieldState();
}

class _FxFieldState extends State<FxField> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_wake);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_wake);
    _ticker.dispose();
    super.dispose();
  }

  /// 有粒子就跑、跑完就停（原型 `_kick` / L100-101）
  void _wake() {
    if (!_ticker.isActive && widget.controller.busy) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration now) {
    final double dt = _last == Duration.zero
        ? 1 / 60
        : (now - _last).inMicroseconds / 1e6;
    _last = now;
    widget.controller.step(dt);
    if (!widget.controller.busy) {
      _ticker.stop();
      setState(() {}); // 最后一帧要清干净
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(painter: _FxPainter(widget.controller)),
      ),
    );
  }
}

class _FxPainter extends CustomPainter {
  const _FxPainter(this.c);

  final FxController c;

  static double _outCubic(double x) => 1 - math.pow(1 - x, 3).toDouble();
  static double _inOutCubic(double x) =>
      x < .5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;

  @override
  void paint(Canvas canvas, Size size) {
    if (!c.busy) return;
    canvas.saveLayer(Offset.zero & size, Paint()..blendMode = BlendMode.plus);
    final Paint stroke = Paint()..style = PaintingStyle.stroke;
    final Paint fill = Paint();

    for (final FxParticle p in c.parts) {
      final double a = 1 - p.life / p.max;
      final Color col = p.color.withAlpha((a.clamp(0, 1) * 255).round());
      if (p.kind == 'line') {
        stroke
          ..color = col
          ..strokeWidth = p.size;
        canvas.drawLine(
          Offset(p.x, p.y),
          Offset(p.x - p.vx * .03, p.y - p.vy * .03),
          stroke,
        );
      } else if (p.kind == 'shard') {
        final double s = p.size * 2.2;
        canvas.save();
        canvas.translate(p.x, p.y);
        canvas.rotate(p.rot);
        fill.color = col;
        canvas.drawRect(Rect.fromLTWH(-s, -s * .3, s * 2, s * .6), fill);
        canvas.restore();
      } else {
        fill.color = col;
        canvas.drawCircle(Offset(p.x, p.y), p.size * (0.6 + a * .6), fill);
      }
    }

    for (final FxRipple r in c.rips) {
      final double p = r.t / r.max;
      final double rad = r.r0 + (r.r1 - r.r0) * _outCubic(p);
      stroke
        ..color = r.color.withAlpha(
          (math.pow(1 - p, 1.5).toDouble().clamp(0, 1) * 255).round(),
        )
        ..strokeWidth = r.w * (1 - p * .6);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(r.x, r.y),
          width: rad * 2,
          height: rad * 2 * r.flat,
        ),
        stroke,
      );
    }

    for (final FxStreak s in c.streaks) {
      final double p = s.t / s.max;
      final double h = _inOutCubic(math.min(1, p * 1.25));
      final double tl = _inOutCubic(math.max(0, p * 1.25 - .25));
      final Offset head = Offset(
        s.x0 + (s.x1 - s.x0) * h,
        s.y0 + (s.y1 - s.y0) * h,
      );
      final Offset tail = Offset(
        s.x0 + (s.x1 - s.x0) * tl,
        s.y0 + (s.y1 - s.y0) * tl,
      );
      stroke
        ..strokeWidth = s.w
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          colors: <Color>[const Color(0x0038E1FF), s.color],
        ).createShader(Rect.fromPoints(tail, head));
      canvas.drawLine(tail, head, stroke);
      stroke.shader = null;
      fill.color = Colors.white;
      canvas.drawCircle(head, s.w * 1.4, fill);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FxPainter old) => true;
}
