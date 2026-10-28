import 'package:flutter/material.dart';

/// ═══════════════════════════════════════════════════════════
///  极简 SVG path 解析 —— 让参考稿里的图标 `d="…"` 原样上屏
///  （JS `IC` 表 L1033-1039、HUD/侧键图标）。
///
///  支持 M L H V C S Q T A Z（大小写），够参考稿全部图标用。
/// ═══════════════════════════════════════════════════════════
Path parseSvgPath(String d) {
  final Path p = Path();
  final RegExp tok = RegExp(
    r'[MmLlHhVvCcSsQqTtAaZz]|-?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?',
  );
  final List<String> t = tok
      .allMatches(d)
      .map((Match m) => m.group(0)!)
      .toList();
  int i = 0;
  String cmd = 'M';
  double x = 0, y = 0, sx = 0, sy = 0;
  double? lcx, lcy; // 上一个三次控制点（S 反射用）
  double? lqx, lqy;
  bool isCmd(String s) => RegExp(r'^[A-Za-z]$').hasMatch(s);
  double n() => double.parse(t[i++]);
  while (i < t.length) {
    if (isCmd(t[i])) {
      cmd = t[i++];
    }
    final bool rel = cmd == cmd.toLowerCase();
    final double ox = rel ? x : 0;
    final double oy = rel ? y : 0;
    switch (cmd.toUpperCase()) {
      case 'M':
        x = ox + n();
        y = oy + n();
        p.moveTo(x, y);
        sx = x;
        sy = y;
        cmd = rel ? 'l' : 'L'; // 后续成对坐标按 lineTo
        lcx = lqx = null;
      case 'L':
        x = ox + n();
        y = oy + n();
        p.lineTo(x, y);
        lcx = lqx = null;
      case 'H':
        x = (rel ? x : 0) + n();
        p.lineTo(x, y);
        lcx = lqx = null;
      case 'V':
        y = (rel ? y : 0) + n();
        p.lineTo(x, y);
        lcx = lqx = null;
      case 'C':
        final double x1 = ox + n(), y1 = oy + n();
        final double x2 = ox + n(), y2 = oy + n();
        x = ox + n();
        y = oy + n();
        p.cubicTo(x1, y1, x2, y2, x, y);
        lcx = x2;
        lcy = y2;
        lqx = null;
      case 'S':
        final double x1 = lcx == null ? x : 2 * x - lcx;
        final double y1 = lcy == null ? y : 2 * y - lcy;
        final double x2 = ox + n(), y2 = oy + n();
        x = ox + n();
        y = oy + n();
        p.cubicTo(x1, y1, x2, y2, x, y);
        lcx = x2;
        lcy = y2;
        lqx = null;
      case 'Q':
        final double x1 = ox + n(), y1 = oy + n();
        x = ox + n();
        y = oy + n();
        p.quadraticBezierTo(x1, y1, x, y);
        lqx = x1;
        lqy = y1;
        lcx = null;
      case 'T':
        final double x1 = lqx == null ? x : 2 * x - lqx;
        final double y1 = lqy == null ? y : 2 * y - lqy;
        x = ox + n();
        y = oy + n();
        p.quadraticBezierTo(x1, y1, x, y);
        lqx = x1;
        lqy = y1;
        lcx = null;
      case 'A':
        final double rx = n(), ry = n(), rot = n();
        final bool large = n() != 0;
        final bool sweep = n() != 0;
        x = ox + n();
        y = oy + n();
        p.arcToPoint(
          Offset(x, y),
          radius: Radius.elliptical(rx, ry),
          rotation: rot, // Flutter 这里收的就是角度
          largeArc: large,
          clockwise: sweep,
        );
        lcx = lqx = null;
      case 'Z':
        p.close();
        x = sx;
        y = sy;
        lcx = lqx = null;
      default:
        i++;
    }
  }
  return p;
}

/// 参考稿 `IC` 图标表（viewBox 0 0 24 24，fill）
class RefIcons {
  const RefIcons._();
  static const String spark =
      'M12 1.5l2.6 7.9 7.9 2.6-7.9 2.6L12 22.5l-2.6-7.9L1.5 12l7.9-2.6z';
  static const String x2a =
      'M3.5 6.5l2-2 4 4 4-4 2 2-4 4 4 4-2 2-4-4-4 4-2-2 4-4z';
  static const String x2b =
      'M15.5 13.5c0-2 1.3-3 3-3s3 1 3 2.6c0 1.6-1.3 2.4-3.4 4.4h3.6v2h-6.4v-1.7c3-2.8 3.9-3.5 3.9-4.6 0-.6-.4-.9-1-.9s-1 .4-1 1.2z';
  static const String shield =
      'M12 1.5l8.5 3.2v6.6c0 5.4-3.6 9.6-8.5 11.2-4.9-1.6-8.5-5.8-8.5-11.2V4.7z';
  static const String patch =
      'M5 4h2V2h2v2h6V2h2v2h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zm0 6v10h14V10zm5.5 8.2l-3.2-3.2 1.4-1.4 1.8 1.8 4.8-4.8 1.4 1.4z';

  static List<String> of(String id) => switch (id) {
    'crit' => <String>[spark],
    'dbl' => <String>[x2a, x2b],
    'shield' => <String>[shield],
    'patch' => <String>[patch],
    _ => <String>[spark],
  };
}

/// 24×24 viewBox 的填充图标（可加辉光）
class RefSvgIcon extends StatelessWidget {
  const RefSvgIcon({
    super.key,
    required this.paths,
    required this.color,
    this.size = 24,
    this.glow = 0,
  });
  final List<String> paths;
  final Color color;
  final double size;
  final double glow;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _SvgIconPainter(paths, color, glow),
  );
}

class _SvgIconPainter extends CustomPainter {
  _SvgIconPainter(this.paths, this.color, this.glow);
  final List<String> paths;
  final Color color;
  final double glow;
  static final Map<String, Path> _cache = <String, Path>{};

  @override
  void paint(Canvas canvas, Size s) {
    canvas.scale(s.width / 24);
    for (final String d in paths) {
      final Path p = _cache.putIfAbsent(d, () => parseSvgPath(d))
        ..fillType = PathFillType.evenOdd;
      if (glow > 0) {
        canvas.drawPath(
          p,
          Paint()
            ..color = color
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, glow / 2),
        );
      }
      canvas.drawPath(p, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_SvgIconPainter o) =>
      o.color != color || o.paths != paths || o.glow != glow;
}
