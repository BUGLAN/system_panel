import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'camera.dart';

/// ═══════════════════════════════════════════════════════════
///  进度带（docs/33 阶段 5）—— 「8 条等宽虚线」换成**一条**
///
///  宿主原话：「环这一套语义很不符合我们当前的系统」。
///  视觉上的三个身份里，唯一还需要的读数就是**进度**：
///    · 暗轨（虚线）= 清单上还没做完的部分
///    · 亮弧（实心发光，从右端起逆时针走）= 已完成的比例
///    · 弧头一颗彗星 = 你现在的位置
///    · 走满 = 整圈实心（这个目标兑现了）
///
///  ⚠️ 状态**一律用样式表达，禁止状态文字**（docs/17 的既有纪律）——
///     这里也一个字都不写。
///
///  关键细节照抄原 `ring_painter`（别"优化"）：
///   · 辉光是**三条同半径的描边叠加**（宽度 9 / 4 / core，透明度 ×.07 / ×.16 / ×.9），
///     用加色混合（canvas2d `lighter` → Flutter `BlendMode.plus`）
///   · 前后半弧权重 1 / .55 —— 那个伪 3D 感
///   · 线宽写的是 `w × (1/S)` 且一律被 `max(.4, …)` 夹到 0.4
/// ═══════════════════════════════════════════════════════════
class ProgressBand extends StatelessWidget {
  const ProgressBand({
    super.key,
    required this.done,
    required this.total,
    this.cam = 'full',
    this.camObj,
    this.t = 0,
    this.dim = 1,
    this.lit = 1,
    this.scan = 0,
    this.visible = true,
  });

  /// 已完成单数 / 清单总条数（分母 0 = 未绑定，不画）
  final int done;
  final int total;

  /// 相机预设名
  final String cam;

  /// 弹簧推出来的那一帧相机；给了就用它（否则按 `cam` 查静态预设）
  final Cam? camObj;

  /// 动画时间（秒）—— 彗星/虚线的相位都由它决定
  final double t;

  /// `fx.bright × bandA`（开机 34% / 失败压暗）
  final double dim;

  /// 唤醒点亮 / 失败里掐暗的那一路（0~1）
  final double lit;

  /// 待机扫描（`Stage.scan`）
  final double scan;

  final bool visible;

  /// 腰上那圈的几何（世界单位）：横向半径与所在高度。
  /// 原来是 8 条从脚踝排到肩的椭圆，现在只有**腰间这一条**。
  static const double kRx = .30;
  static const double kRy = StageAnchors.feet + .36;
  static const double kRyy = .066;

  /// 挂签用：这一圈的右端点
  static Offset point(String cam, Size size, {double side = 1}) =>
      Cam.byName(cam).toScreen(side * kRx, kRy, size);

  @override
  Widget build(BuildContext context) {
    if (!visible || total <= 0) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: ProgressBandPainter(
            done: done,
            total: total,
            cam: cam,
            camObj: camObj,
            t: t,
            dim: dim * lit,
            scan: scan,
          ),
        ),
      ),
    );
  }
}

class ProgressBandPainter extends CustomPainter {
  const ProgressBandPainter({
    required this.done,
    required this.total,
    required this.cam,
    this.camObj,
    required this.t,
    required this.dim,
    required this.scan,
  });

  final int done;
  final int total;
  final String cam;
  final Cam? camObj;
  final double t;
  final double dim;
  final double scan;

  static const double _th = math.pi * 2;
  static const int _blue = 0x38E1FF;
  static const int _ice = 0xE9FBFF;
  static const int _pale = 0x9FF0FF;

  double get _frac => total <= 0 ? 0 : (done / total).clamp(0, 1).toDouble();

  @override
  void paint(Canvas canvas, Size size) {
    final Cam c = camObj ?? Cam.byName(cam);
    final double s = c.scale(size.height);
    final double px = 1 / s;
    final double k = s;
    final double mul = dim.clamp(0, 1).toDouble();

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

    final Offset p = c.toScreen(0, ProgressBand.kRy, size);
    final double rx = ProgressBand.kRx * k;
    final double ry = ProgressBand.kRyy * k;

    // ① 暗轨：还没做完的部分（原「未走」环的虚线语言）
    const int segs = 36;
    final double gap = _th / segs;
    for (int j = 0; j < segs; j++) {
      final double a = j * gap + t * .05;
      // 已完成的那一段不再画虚线（亮弧会盖上去）
      final double mid = ((a - t * .05) % _th) / _th;
      if (mid < _frac) continue;
      arc(p.dx, p.dy, rx, ry, a, a + gap * .45, 1.2, _blue, .5 * mul);
    }

    // ② 亮弧：从右端（0 弧度）逆时针走 `frac` 圈
    if (_frac > 0) {
      final double end = _th * _frac;
      final bool full = _frac >= .999;
      final double pulse = .78 + .22 * math.sin(t * 2.6);
      glow(
        p.dx,
        p.dy,
        rx,
        ry,
        0,
        end,
        full ? _ice : _blue,
        (full ? .95 : .62 * pulse) * mul,
        full ? 2.4 : 1.6,
      );
      if (!full) {
        // 弧头 = 彗星（14 段渐隐，照抄原「当前环」的画法）
        final double head = end;
        for (int j = 0; j < 14; j++) {
          final double s2 = head - .95 + j * .068;
          if (s2 < 0) continue;
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
      }
    }

    // ③ 待机扫描：一圈光从脚下扫到头顶再扫回来
    if (scan > .01) {
      final double ph = (math.sin(t * 1.1 - math.pi / 2) + 1) / 2;
      final double wy =
          StageAnchors.feet +
          .06 +
          (StageAnchors.hair + .06 - (StageAnchors.feet + .06)) *
              _easeInOutCubic(ph);
      final Offset sp = c.toScreen(0, wy, size);
      glow(sp.dx, sp.dy, .70 * k, .125 * k, 0, _th, _pale, .95 * scan * mul, 2);
      for (int j = 1; j <= 5; j++) {
        final double dy =
            j * 7 * (math.cos(t * 1.1 - math.pi / 2) > 0 ? -1 : 1);
        glow(
          sp.dx,
          sp.dy + dy,
          .70 * k,
          .125 * k,
          0,
          _th,
          _blue,
          scan * .16 * (1 - j / 6) * mul,
          1,
        );
      }
    }
  }

  static double _easeInOutCubic(double x) =>
      x < .5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;

  static Color _hexa(int rgb, double a) =>
      Color(((a.clamp(0, 1) * 255).round() << 24) | (rgb & 0xFFFFFF));

  @override
  bool shouldRepaint(covariant ProgressBandPainter old) =>
      old.done != done ||
      old.total != total ||
      old.t != t ||
      old.dim != dim ||
      old.cam != cam ||
      old.camObj != camObj ||
      old.scan != scan;
}
