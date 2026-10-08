import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/goal.dart';
import 'camera.dart';

/// ═══════════════════════════════════════════════════════════
///  环场（stage.js L568-663 `_drawRings`）
///  她脚下到头顶那 8 个椭圆环 —— **画在独立的 2D canvas 上**
///  （`stage.js` L127 `cv.id = 'ringCv'`），跟 Live2D 模型无关，
///  所以这一层不需要模型就能落地。
///
///  关键细节（照抄原型，别"优化"）：
///   · 辉光是**三条同半径的描边叠加**（宽度 9 / 4 / core，透明度 ×.07 / ×.16 / ×.9），
///     用加色混合（canvas2d `lighter` → Flutter `BlendMode.plus`）
///   · 线宽写的是 `w × (1/S)`，而 1/S ≈ .0034 —— **一律被 `max(.4, …)` 夹到 0.4**
///   · 椭圆按角度切成前后两半：`[0,π]` 与 `[2π,3π]` 是"正面"（权重 1），
///     `[π,2π]` 是"背面"（权重 .55）—— 这是那个伪 3D 感
///   · done 环上那 12 个刻度、cur 环上那颗菱形，长度写的是 `4 × (1/S)` ≈ .014px，
///     **在原型里本来就看不见**；照抄等于不画，别自作主张放大
/// ═══════════════════════════════════════════════════════════
class RingField extends StatelessWidget {
  const RingField({
    super.key,
    required this.goal,
    this.cam = 'full',
    this.camObj,
    this.t = 0,
    this.dim = 1,
    this.ringMul,
    this.scan = 0,
    this.visible = true,
  });

  final Goal goal;

  /// 相机预设名
  final String cam;

  /// 弹簧推出来的那一帧相机；给了就用它（否则按 `cam` 查静态预设）
  final Cam? camObj;

  /// 动画时间（秒）—— 刻度/彗星/虚线的相位都由它决定
  final double t;

  /// `fx.bright × ringA`
  final double dim;

  /// 逐环系数（`Stage.ringMul[i]`，默认 1）—— 失败时把当前那一环掐暗
  final List<double>? ringMul;

  /// 待机扫描（`Stage.scan`）
  final double scan;

  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: RingFieldPainter(
            goal: goal,
            cam: cam,
            camObj: camObj,
            t: t,
            dim: dim,
            scan: scan,
          ),
        ),
      ),
    );
  }
}

class RingFieldPainter extends CustomPainter {
  const RingFieldPainter({
    required this.goal,
    required this.cam,
    this.camObj,
    required this.t,
    required this.dim,
    this.ringMul,
    required this.scan,
  });

  final Goal goal;
  final String cam;
  final Cam? camObj;
  final double t;
  final double dim;
  final List<double>? ringMul;
  final double scan;

  static const double _th = math.pi * 2;
  static const int _blue = 0x38E1FF;
  static const int _ice = 0xE9FBFF;
  static const int _pale = 0x9FF0FF;

  @override
  void paint(Canvas canvas, Size size) {
    final Cam c = camObj ?? Cam.byName(cam);
    final double s = c.scale(size.height);
    final double px = 1 / s; // ⚠️ 原型就是这么写的，后面会被 max(.4, …) 夹掉
    final double k = s; // 世界单位 → 屏幕

    /// `arc()`（stage.js L575）
    void arc(
      double cx,
      double cy,
      double rx,
      double ry,
      double a0,
      double a1,
      double w,
      int col,
      double al, {
      bool plus = false,
    }) {
      if (al <= .003 || a1 <= a0) return;
      final Paint p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(.4, w * px)
        ..color = _hexa(col, math.min(1, al));
      if (plus) p.blendMode = BlendMode.plus;
      final int n = math.max(4, ((a1 - a0) / .07).ceil());
      final Path path = Path();
      for (int i = 0; i <= n; i++) {
        final double a = a0 + (a1 - a0) * i / n;
        final double x = cx + rx * math.cos(a);
        final double y = cy + ry * math.sin(a);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, p);
    }

    /// `glow()`（stage.js L588）—— 前后半弧分别加权
    void glow(
      double cx,
      double cy,
      double rx,
      double ry,
      double a0,
      double a1,
      int col,
      double al, [
      double core = 1.6,
    ]) {
      if (al <= .004 || rx <= 0 || ry <= 0) return;
      final double st = ((a0 % _th) + _th) % _th;
      final double e = st + (a1 - a0);
      // 第三个数是 front 权重：1 → 1，其余 → .55（stage.js L592）
      final List<List<double>> parts = <List<double>>[
        <double>[st, e, 0],
        <double>[0, math.pi, 1],
        <double>[math.pi, _th, 0],
        <double>[_th, _th + math.pi, 1],
        <double>[_th + math.pi, _th * 2, 0],
      ];
      for (final List<double> seg in parts) {
        final double lo = math.max(seg[0], st);
        final double hi = math.min(seg[1], e);
        if (hi <= lo) continue;
        final double w = seg[2] == 1 ? 1 : .55;
        arc(cx, cy, rx, ry, lo, hi, 9, col, al * .07 * w, plus: true);
        arc(cx, cy, rx, ry, lo, hi, 4, col, al * .16 * w, plus: true);
        arc(cx, cy, rx, ry, lo, hi, core, col, al * .9 * w, plus: true);
      }
    }

    for (int i = 0; i < goal.rings.length; i++) {
      final GoalRing ring = goal.rings[i];
      final RingGeom g = RingGeom.of(
        i,
        goal.rings.length,
        finalRing: ring.finalRing,
      );
      final Offset p = c.toScreen(0, g.ry, size);
      final double rx = g.rx * k;
      final double ry = g.ryy * k;
      final double mul =
          dim * ((ringMul != null && i < ringMul!.length) ? ringMul![i] : 1);

      switch (ring.state) {
        case RingState.done:
          glow(
            p.dx,
            p.dy,
            rx,
            ry,
            0,
            _th,
            ring.finalRing ? _ice : _blue,
            .95 * mul,
            ring.finalRing ? 2.4 : 1.6,
          );
          // 12 个刻度：原型里长度是 4×(1/S) ≈ .014px，实际看不见；照抄
          for (int j = 0; j < 12; j++) {
            final double a = j * math.pi / 6 + t * .12;
            final double x = p.dx + rx * math.cos(a);
            final double y = p.dy + ry * math.sin(a);
            canvas.drawLine(
              Offset(x, y - 4 * px),
              Offset(x, y + 4 * px),
              Paint()
                ..strokeWidth = math.max(.4, 1.2 * px)
                ..color = _hexa(0xBFF6FF, .7 * mul),
            );
          }
        case RingState.cur:
          final double pulse = .55 + .45 * math.sin(t * 2.6);
          glow(
            p.dx,
            p.dy,
            rx,
            ry,
            0,
            _th,
            _blue,
            (.38 + .3 * pulse) * mul,
            1.3,
          );
          final double a = t * 1.15; // 彗星
          for (int j = 0; j < 14; j++) {
            final double s2 = a - .95 + j * .068;
            glow(
              p.dx,
              p.dy,
              rx,
              ry,
              s2,
              s2 + .07,
              _ice,
              (j / 14) * .95 * mul,
              2.2,
            );
          }
          // 菱形：`dd = 5 × (1/S)` ≈ .017px，同样看不见；照抄
          final double na = t * .55;
          final double x = p.dx + rx * math.cos(na);
          final double y = p.dy + ry * math.sin(na);
          final double dd = 5 * px;
          final Path dm = Path()
            ..moveTo(x, y - dd * 1.4)
            ..lineTo(x + dd, y)
            ..lineTo(x, y + dd * 1.4)
            ..lineTo(x - dd, y)
            ..close();
          canvas.drawPath(dm, Paint()..color = _hexa(_ice, mul));
        case RingState.lock:
          final int segs = ring.finalRing ? 24 : 36;
          final double gap = _th / segs;
          if (ring.finalRing) {
            glow(p.dx, p.dy, rx, ry, 0, _th, _blue, .32 * mul, 1);
          }
          for (int j = 0; j < segs; j++) {
            final double s2 = j * gap + t * .05;
            arc(p.dx, p.dy, rx, ry, s2, s2 + gap * .45, 1.2, _blue, .5 * mul);
          }
      }
    }

    // 待机扫描：一圈光从脚下扫到头顶再扫回来（stage.js L641）
    if (scan > .01) {
      final double ph = (math.sin(t * 1.1 - math.pi / 2) + 1) / 2;
      final double wy =
          StageAnchors.feet +
          .06 +
          (StageAnchors.hair + .06 - (StageAnchors.feet + .06)) *
              _easeInOutCubic(ph);
      final Offset p = c.toScreen(0, wy, size);
      glow(p.dx, p.dy, .70 * k, .125 * k, 0, _th, _pale, .95 * scan, 2);
      for (int j = 1; j <= 5; j++) {
        final double dy =
            j * 7 * (math.cos(t * 1.1 - math.pi / 2) > 0 ? -1 : 1);
        glow(
          p.dx,
          p.dy + dy,
          .70 * k,
          .125 * k,
          0,
          _th,
          _blue,
          scan * .16 * (1 - j / 6),
          1,
        );
      }
    }
  }

  static double _easeInOutCubic(double x) =>
      x < .5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;

  /// `hexa()` —— `0xRRGGBB` + 透明度
  static Color _hexa(int rgb, double a) =>
      Color(((a.clamp(0, 1) * 255).round() << 24) | (rgb & 0xFFFFFF));

  @override
  bool shouldRepaint(covariant RingFieldPainter old) =>
      old.t != t ||
      old.dim != dim ||
      old.cam != cam ||
      old.camObj != camObj ||
      old.scan != scan;
}
