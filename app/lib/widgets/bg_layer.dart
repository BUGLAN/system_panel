import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// ═══════════════════════════════════════════════════════════
///  0 · 天幕 —— 她身后的世界（app.css L46-71 `#bg`）
///  这是所有页面的共享底，不是某一页的装饰。
///  层级：sky 渐变 → 轨道环 ×3 → 背景大字 → 地面网格 → 颗粒
/// ═══════════════════════════════════════════════════════════
class BgLayer extends StatefulWidget {
  const BgLayer({super.key, this.word = 'SYSTEM', this.latin = false});

  /// 她身后写着的那句话（原型里是宿主的目标）
  final String word;

  /// 显式指定走拉丁字形；不传则由 [WordSpec.isLatin] 按内容判定
  /// （flows.js `setWord` 的默认路径是不传 flag 的）
  final bool latin;

  @override
  State<BgLayer> createState() => _BgLayerState();
}

class _BgLayerState extends State<BgLayer> with TickerProviderStateMixin {
  // 三条轨道环各自的周期（app.css L55-57）
  late final AnimationController _ring1 = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 140),
  )..repeat();
  late final AnimationController _ring2 = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 220),
  )..repeat();
  late final AnimationController _ring3 = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 300),
  )..repeat();
  // 地面网格：6s 走一格（46px）
  late final AnimationController _floor = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _ring1.dispose();
    _ring2.dispose();
    _ring3.dispose();
    _floor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints box) {
        final double w = box.maxWidth;
        final double h = box.maxHeight;
        return Stack(
          children: <Widget>[
            // `.sky` 的 background 是五层叠出来的，自下而上：
            //   底色渐变 → ComfyUI 底图（cover）→ 压暗渐变 → 两团辉光
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Color(0xFF061026),
                      Color(0xFF040A18),
                      Color(0xFF020409),
                    ],
                    stops: <double>[0, .48, 1],
                  ),
                ),
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/img/bg-void.jpg'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            // linear-gradient(180deg, rgba(2,6,16,.38), rgba(2,5,12,.12) 44%,
            //                 rgba(1,3,8,.42) 100%)
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Color(0x61020610),
                      Color(0x1F02050C),
                      Color(0x6B010308),
                    ],
                    stops: <double>[0, .44, 1],
                  ),
                ),
              ),
            ),
            const Positioned.fill(child: CustomPaint(painter: _SkyPainter())),
            _orbit(w, h, diameter: 330, alpha: .10, dashed: true, t: _ring1),
            _orbit(
              w,
              h,
              diameter: 620,
              alpha: .07,
              dashed: false,
              t: _ring2,
              reverse: true,
            ),
            _orbit(w, h, diameter: 980, alpha: .07, dashed: true, t: _ring3),
            _word(w, h),
            _floorGrid(w, h),
            const Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: .07,
                  child: CustomPaint(painter: _GrainPainter()),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 轨道环：圆心钉在她的头（--hx/--hy），整环缓慢自转
  Widget _orbit(
    double w,
    double h, {
    required double diameter,
    required double alpha,
    required bool dashed,
    required Animation<double> t,
    bool reverse = false,
  }) {
    final double cx = w * .5;
    final double cy = h * StageAnchors.eyesFracY;
    return Positioned(
      left: cx - diameter / 2,
      top: cy - diameter / 2,
      width: diameter,
      height: diameter,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: t,
          builder: (BuildContext _, Widget? _) => Transform.rotate(
            angle: (reverse ? -1 : 1) * t.value * 2 * math.pi,
            child: CustomPaint(
              painter: _RingPainter(
                color: C.blue.withAlpha((alpha * 255).round()),
                dashed: dashed,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 背景大字：描边 + 竖向渐变填充，居中钉在 chest 锚点，再整体缩到 0.910
  /// 拉丁（SYSTEM 这类）走 Tektur 900/wdth75；中文走数黑体（app.css L60-63）
  Widget _word(double w, double h) {
    final bool latin = WordSpec.isLatin(widget.word, latin: widget.latin);
    final double size = WordSpec.fontSize(widget.word, latin: latin);
    final TextStyle base = latin
        ? fs(
            family: F.num,
            size: size,
            wght: 900,
            wdth: 75,
            ls: size * .06,
            height: 1,
            color: Colors.white,
          )
        : fs(
            family: F.hd,
            size: size,
            wght: 400,
            ls: size * .02,
            height: 1,
            color: Colors.white,
          );
    final double centerY = h * StageAnchors.chestFracY;
    return Positioned(
      left: 0,
      right: 0,
      top: centerY - size / 2,
      height: size,
      child: IgnorePointer(
        child: Transform.scale(
          scale: WordSpec.scale,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // background: linear-gradient(180deg, rgba(56,225,255,.16), transparent 75%)
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (Rect r) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0x2938E1FF), Color(0x0038E1FF)],
                  stops: <double>[0, .75],
                ).createShader(r),
                child: _wordText(base),
              ),
              // -webkit-text-stroke: 1.2px rgba(56,225,255,.2)
              _wordText(
                base.copyWith(
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 1.2
                    ..color = const Color(0x3338E1FF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wordText(TextStyle style) =>
      Text(widget.word, style: style, textAlign: TextAlign.center, maxLines: 1);

  /// 地面网格：透视 + 向上淡出 + 向下滚动
  Widget _floorGrid(double w, double h) {
    return Positioned(
      left: -w * .5,
      right: -w * .5,
      bottom: -h * .02,
      height: h * .42,
      child: IgnorePointer(
        child: Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.identity()
            ..setEntry(3, 2, -1 / 320)
            ..rotateX(66 * math.pi / 180),
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (Rect r) => const LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: <Color>[Colors.white, Color(0x00FFFFFF)],
              stops: <double>[0, .85],
            ).createShader(r),
            child: AnimatedBuilder(
              animation: _floor,
              builder: (BuildContext _, Widget? _) =>
                  CustomPaint(painter: _GridPainter(phase: _floor.value)),
            ),
          ),
        ),
      ),
    );
  }
}

/// 天幕底色：一层竖向底色 + 两团椭圆辉光（app.css L48-52）
class _SkyPainter extends CustomPainter {
  const _SkyPainter();

  @override
  void paint(Canvas canvas, Size s) {
    // radial-gradient(70% 42% at 50% 30%, rgba(31,139,255,.14), transparent 72%)
    _glow(
      canvas,
      s,
      cx: .50,
      cy: .30,
      rx: .70,
      ry: .42,
      color: const Color(0x241F8BFF),
      stop: .72,
    );
    // radial-gradient(90% 50% at 50% 104%, rgba(56,225,255,.08), transparent 62%)
    _glow(
      canvas,
      s,
      cx: .50,
      cy: 1.04,
      rx: .90,
      ry: .50,
      color: const Color(0x1438E1FF),
      stop: .62,
    );
  }

  /// CSS 的椭圆 radial-gradient 在 Flutter 里要手动把圆压成椭圆
  void _glow(
    Canvas canvas,
    Size s, {
    required double cx,
    required double cy,
    required double rx,
    required double ry,
    required Color color,
    required double stop,
  }) {
    final Offset center = Offset(s.width * cx, s.height * cy);
    final double radius = s.width * rx;
    final double ky = (s.height * ry) / radius;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1, ky);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius,
          <Color>[color, color.withAlpha(0)],
          <double>[0, stop],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// 轨道环：1px 实线或虚线
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size s) {
    final Offset center = Offset(s.width / 2, s.height / 2);
    final double r = s.width / 2 - .5;
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    if (!dashed) {
      canvas.drawCircle(center, r, p);
      return;
    }
    final Rect rect = Rect.fromCircle(center: center, radius: r);
    const double dash = 4, gap = 4;
    final double step = (dash + gap) / r;
    for (double a = 0; a < 2 * math.pi; a += step) {
      canvas.drawArc(rect, a, dash / r, false, p);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter o) =>
      o.color != color || o.dashed != dashed;
}

/// 地面网格：46px 格，1px 线，整体向下滚
class _GridPainter extends CustomPainter {
  const _GridPainter({required this.phase});

  final double phase;

  @override
  void paint(Canvas canvas, Size s) {
    final Paint p = Paint()
      ..color = const Color(0x2938E1FF)
      ..strokeWidth = 1;
    const double cell = 46;
    final double off = phase * cell;
    for (double y = off - cell; y < s.height + cell; y += cell) {
      canvas.drawLine(Offset(0, y), Offset(s.width, y), p);
    }
    for (double x = 0; x < s.width + cell; x += cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter o) => o.phase != phase;
}

/// 颗粒：原型的 SVG feTurbulence 换成程序化噪点，用 overlay 混合
class _GrainPainter extends CustomPainter {
  const _GrainPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final Rect rect = Offset.zero & s;
    canvas.saveLayer(rect, Paint()..blendMode = BlendMode.overlay);
    final math.Random rnd = math.Random(20261007);
    final Paint p = Paint();
    final int n = (s.width * s.height / 420).round();
    for (int i = 0; i < n; i++) {
      final int v = rnd.nextInt(256);
      p.color = Color.fromARGB(255, v, v, v);
      canvas.drawRect(
        Rect.fromLTWH(
          rnd.nextDouble() * s.width,
          rnd.nextDouble() * s.height,
          1.4,
          1.4,
        ),
        p,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
