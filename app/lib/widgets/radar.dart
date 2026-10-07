import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/attrs.dart';
import '../design/tokens.dart';

/// ═══════════════════════════════════════════════════════════
///  六维雷达（app.css L458-465 `.radar` · ui.js `Sheet.radar`）
///  viewBox 0 0 300 245，四条网格环 + 六条轴 + 一个多边形。
///  **刻度是平方根**：低值往外扩，免得极端偏科变成一根针；
///  最弱那一维的轴名变灰。
///
///  实测：svg 盒 [45,488,300,245]（在 350 宽的内容区里居中）
/// ═══════════════════════════════════════════════════════════
class Radar extends StatelessWidget {
  const Radar({super.key, required this.attrs, this.weakKey});

  final Map<String, int> attrs;

  /// 最弱那一维的单字键（轴名变灰）
  final String? weakKey;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('sheet.radar'),
      width: 300,
      height: 245,
      child: CustomPaint(
        painter: _RadarPainter(attrs: attrs, weakKey: weakKey),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter({required this.attrs, this.weakKey});

  final Map<String, int> attrs;
  final String? weakKey;

  // ui.js L555：const R = 92, cx = 150, cy = 120
  static const double _cx = 150, _cy = 120, _r = 92;

  static const Color _grid = Color(0x2438E1FF); // rgba(56,225,255,.14)
  static const Color _shapeFill = Color(0x2938E1FF); // rgba(56,225,255,.16)

  @override
  void paint(Canvas canvas, Size s) {
    final List<String> ks = Attr.all.map((Attr a) => a.k).toList();
    final int maxV = math.max(
      10,
      ks.map((String k) => attrs[k] ?? 0).reduce(math.max),
    );

    Offset pt(int i, double r) {
      final double a = -math.pi / 2 + i * math.pi / 3;
      return Offset(_cx + r * math.cos(a), _cy + r * math.sin(a));
    }

    Path poly(double r) {
      final Path p = Path();
      for (int i = 0; i < ks.length; i++) {
        final Offset o = pt(i, r);
        i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
      }
      return p..close();
    }

    // 四条网格环 + 六条轴
    final Paint grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _grid;
    for (final double f in <double>[.25, .5, .75, 1]) {
      canvas.drawPath(poly(_r * f), grid);
    }
    for (int i = 0; i < ks.length; i++) {
      canvas.drawLine(Offset(_cx, _cy), pt(i, _r), grid);
    }

    // 平方根刻度
    final List<Offset> vals = <Offset>[
      for (int i = 0; i < ks.length; i++)
        pt(i, _r * math.sqrt((attrs[ks[i]] ?? 0) / maxV)),
    ];
    final Path shape = Path()..moveTo(vals[0].dx, vals[0].dy);
    for (int i = 1; i < vals.length; i++) {
      shape.lineTo(vals[i].dx, vals[i].dy);
    }
    shape.close();
    // filter: drop-shadow(0 0 6px rgba(56,225,255,.7))
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = C.blue.withAlpha(90)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(shape, Paint()..color = _shapeFill);
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = C.blue,
    );

    // 顶点小圆点（r 2.2，白的）+ 轴名 + 数值
    for (int i = 0; i < ks.length; i++) {
      canvas.drawCircle(vals[i], 2.2, Paint()..color = Colors.white);
      final Offset lp = pt(i, _r + 22);
      _text(
        canvas,
        Attr.nameOf(ks[i]),
        Offset(lp.dx, lp.dy - 7),
        fs(
          family: F.cn,
          size: 12,
          wght: 400,
          height: 1,
          color: ks[i] == weakKey ? const Color(0xFF8A97AD) : C.ice,
        ),
      );
      _text(
        canvas,
        '${attrs[ks[i]] ?? 0}',
        Offset(lp.dx, lp.dy + 9),
        fs(family: F.num, size: 12, wght: 800, height: 1, color: C.blue),
      );
    }
  }

  /// `dominant-baseline: middle` + `text-anchor: middle` —— 文字正中落在给定点上
  void _text(Canvas canvas, String t, Offset center, TextStyle style) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: t, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _RadarPainter o) =>
      o.attrs != attrs || o.weakKey != weakKey;
}
