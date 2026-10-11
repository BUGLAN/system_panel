import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/attrs.dart';
import '../design/tokens.dart';

/// ═══════════════════════════════════════════════════════════
///  六维雷达（app.css L458-465 `.radar` · ui.js `Sheet.radar`）
///  viewBox 0 0 300 245：三条内圈网格 + 一条满值环 + 六条轴 + 一个多边形。
///
///  **刻度是「线性 50 满值」**（本版改口径，替掉旧的「平方根 + 动态最大值」）：
///  旧口径拿当前最大维值当分母，宿主的六维一起涨时图形纹丝不动，也没有「满值」可言。
///  新口径只认一条满分线 —— 50 分，并且 50 分正好落在基准半径 R=92 上：
///    · v ∈ [0,50]：r = 92 × (v/50)^0.56
///      指数 0.56 ≈ √0.3 是拿手感换来的：纯线性时 v=17 只画到 31，六维稍一偏科就缩成一根针；
///      抬到 0.56 后 v=17 → r≈50，形状还看得见，而 v=50 仍精确等于 92（没满分就不顶格）。
///    · v > 50（溢出带）：r = 92 + 30 × ((v−50)/50)^0.7
///      100 分的理论落点是 r=122。但**正上方**只有 120 的余量（cy=120），
///      所以实际绘制由几何护栏 kRadarRClamp=117 削住（v≳95 那一段），溢出顶点
///      因此永远留在 300×245 画布内、不被裁切。
///  **溢出的那一维要一眼看出来**：轴加亮成实心青（α.55 / 1.6px，从中心一路画到溢出顶点）、
///  顶点白点换冰蓝并放大到 3.0、数值文本也从青换成冰蓝 —— 三条同时生效。
///  最弱那一维的轴名照旧变灰。
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

/// 满值（50 分）所在的半径 —— 满值环就画在这条线上
const double kRadarR = 92;

/// 溢出带上限（100 分）的半径
const double kRadarRMax = 122;

/// 满值刻度：50 分是唯一满分线
const int kRadarFull = 50;

/// 0~50 段的幂指数：≈ √0.3，把低值抬出来又不让 50 分提前顶格
const double _kLowPow = 0.56;

/// 溢出段的幂指数
const double _kSpillPow = 0.7;

/// 溢出带的高度（92 → 122）
const double _kSpillSpan = 30;

/// 单维数值 → 该维顶点离圆心的半径。
/// 绘制与测试共用这一个真源，免得测试另抄一套公式、两边各说各话。
///
/// 画布允许的最大半径：圆心在 (150,120)，**正上方只剩 120 的余量**，
/// 再留 3px 给顶点白点/冰点的半径与那圈外发光，所以上限 117。
///
/// ⚠️ 这不是刻度，是**几何护栏**：v=100 的理论落点是 122（下方 120+122=242<245、
/// 左右 28~272 都放得下，只有正上方会顶出画布）。宿主定的是「按比例画大、允许溢出」，
/// 所以护栏只削掉最后那一段（v≳95），不改变「50 落在满值环上」这条主刻度。
const double kRadarRClamp = 117;

double radarRadiusFor(int v) {
  if (v <= 0) return 0; // 0 与负值都退回圆心（负数的 pow 会算出 NaN）
  if (v <= kRadarFull) {
    return kRadarR * math.pow(v / kRadarFull, _kLowPow).toDouble();
  }
  final double r =
      kRadarR +
      _kSpillSpan *
          math.pow((v - kRadarFull) / kRadarFull, _kSpillPow).toDouble();
  return math.min(r, kRadarRClamp);
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter({required this.attrs, this.weakKey});

  final Map<String, int> attrs;
  final String? weakKey;

  // ui.js L555：const R = 92, cx = 150, cy = 120
  static const double _cx = 150, _cy = 120;

  static const Color _grid = Color(0x2438E1FF); // rgba(56,225,255,.14) 内圈网格
  static const Color _ringStroke = Color(0x5738E1FF); // .34 满值环
  static const Color _ringFill = Color(0x0B38E1FF); // .045 满值基准面
  static const Color _shapeFill = Color(0x2938E1FF); // rgba(56,225,255,.16)
  static const Color _spillAxis = Color(0x8C38E1FF); // .55 溢出维的轴

  @override
  void paint(Canvas canvas, Size s) {
    final List<String> ks = Attr.all.map((Attr a) => a.k).toList();
    final List<double> rs = <double>[
      for (int i = 0; i < ks.length; i++) radarRadiusFor(attrs[ks[i]] ?? 0),
    ];

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

    final Paint grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _grid;

    // 满值基准面：先铺淡填充，再叠三条更暗的内圈网格，最后把 50 分那条环描出来
    // —— 顺序不能反，环要在最上面才是画面里最实的一条线
    canvas.drawPath(poly(kRadarR), Paint()..color = _ringFill);
    for (final double f in <double>[.25, .5, .75]) {
      canvas.drawPath(poly(kRadarR * f), grid);
    }
    canvas.drawPath(
      poly(kRadarR),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = _ringStroke,
    );

    // 六条轴：溢出的那一维换成实心青，并且一路画到溢出顶点（让人看见它冲出去了）
    final Paint spillAxis = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = _spillAxis;
    for (int i = 0; i < ks.length; i++) {
      final bool spill = (attrs[ks[i]] ?? 0) > kRadarFull;
      canvas.drawLine(
        Offset(_cx, _cy),
        pt(i, spill ? rs[i] : kRadarR),
        spill ? spillAxis : grid,
      );
    }

    // 数值多边形（刻度见 radarRadiusFor）
    final List<Offset> vals = <Offset>[
      for (int i = 0; i < ks.length; i++) pt(i, rs[i]),
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

    // 顶点小圆点（溢出维换冰蓝并放大）+ 轴名 + 数值
    for (int i = 0; i < ks.length; i++) {
      final bool spill = (attrs[ks[i]] ?? 0) > kRadarFull;
      canvas.drawCircle(
        vals[i],
        spill ? 3.0 : 2.2,
        Paint()..color = spill ? C.ice : Colors.white,
      );
      // 读数钉死在满值环外一圈：溢出顶点可能跑到 r=122，跟着它跑会撞轴名、还会出界
      final Offset lp = pt(i, kRadarR + 22);
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
        fs(
          family: F.num,
          size: 12,
          wght: 800,
          height: 1,
          color: spill ? C.ice : C.blue,
        ),
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
