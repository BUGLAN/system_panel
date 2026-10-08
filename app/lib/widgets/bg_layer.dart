import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
  // ⚠️ 性能：转一整圈要 140~300s，60fps 地重建纯浪费——三个环共用一条
  //    Ticker，相位连续累计、**每 100ms 才重建一次**（环1每步弧长
  //    r165×0.26°≈0.74px，亚像素级，肉眼不可辨）。
  late final Ticker _orbitTick = createTicker(_onOrbitTick);
  double _t1 = 0, _t2 = 0, _t3 = 0;
  double _orbitAccum = 0;
  Duration _orbitLast = Duration.zero;
  void _onOrbitTick(Duration now) {
    final double dt = _orbitLast == Duration.zero
        ? 1 / 60
        : (now - _orbitLast).inMicroseconds / 1e6;
    _orbitLast = now;
    _t1 = (_t1 + dt / 140) % 1;
    _t2 = (_t2 + dt / 220) % 1;
    _t3 = (_t3 + dt / 300) % 1;
    _orbitAccum += dt;
    if (_orbitAccum >= .1) {
      _orbitAccum = 0;
      setState(() {});
    }
  }

  // 地面网格：6s 走一格（46px）≈ 7.7px/s。⚠️ 不必每帧重画——相位累计够
  //    **0.25 逻辑像素**（dpr2 下半个设备像素）才重画一次（≈31Hz，位移
  //    远小于一个设备像素，肉眼不可辨），把这块的逐帧失效砍掉一半。
  static const double _floorCell = 46;
  static const double _floorQuantum = .25;
  static const Duration _floorPeriod = Duration(seconds: 6);
  late final Ticker _floorTick = createTicker(_onFloorTick);
  double _floorPhase = 0;
  double _floorPainted = -1;
  Duration _floorLast = Duration.zero;
  void _onFloorTick(Duration now) {
    final double dt = _floorLast == Duration.zero
        ? 1 / 60
        : (now - _floorLast).inMicroseconds / 1e6;
    _floorLast = now;
    final double next = (_floorPhase + dt * 1e6 / _floorPeriod.inMicroseconds) % 1;
    if ((next - _floorPainted).abs() * _floorCell >= _floorQuantum) {
      setState(() {
        _floorPhase = next;
        _floorPainted = next;
      });
    } else {
      _floorPhase = next;
    }
  }

  // 噪点纹理：烘焙一次，之后每帧只 drawImage 一回（原实现是全屏 ~6000 个
  // 1.4px 小矩形 + overlay saveLayer，是常驻 GPU 大户之一）。
  ui.Image? _grain;
  Size _grainSize = Size.zero;

  Future<void> _bakeGrain(Size size) async {
    final int w = size.width.round(), h = size.height.round();
    if (w <= 0 || h <= 0) return;
    if (_grain != null && (size.width - _grainSize.width).abs() < 24 &&
        (size.height - _grainSize.height).abs() < 24) {
      return;
    }
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas c = Canvas(rec);
    final math.Random rnd = math.Random(20261007);
    final Paint p = Paint();
    final int n = (w * h / 420).round();
    for (int i = 0; i < n; i++) {
      final int v = rnd.nextInt(256);
      p.color = Color.fromARGB(255, v, v, v);
      c.drawRect(
        Rect.fromLTWH(rnd.nextDouble() * w, rnd.nextDouble() * h, 1.4, 1.4),
        p,
      );
    }
    final ui.Picture pic = rec.endRecording();
    final ui.Image img = await pic.toImage(w, h);
    pic.dispose();
    if (!mounted) {
      img.dispose();
      return;
    }
    setState(() {
      _grain?.dispose();
      _grain = img;
      _grainSize = size;
    });
  }

  @override
  void initState() {
    super.initState();
    _orbitTick.start();
    _floorTick.start();
  }

  @override
  void dispose() {
    _orbitTick.dispose();
    _floorTick.dispose();
    _grain?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints box) {
        final double w = box.maxWidth;
        final double h = box.maxHeight;
        // 首帧/尺寸变化时烘焙噪声图（内部有去重；异步完成后再 setState）
        _bakeGrain(Size(w, h));
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
            _orbit(w, h, diameter: 330, alpha: .10, dashed: true, t: _t1),
            _orbit(
              w,
              h,
              diameter: 620,
              alpha: .07,
              dashed: false,
              t: _t2,
              reverse: true,
            ),
            _orbit(w, h, diameter: 980, alpha: .07, dashed: true, t: _t3),
            _word(w, h),
            _floorGrid(w, h),
            // 颗粒：噪声图烘焙完成后只做一次贴图 overlay（Opacity .07 照抄原型）
            // 布局时顺带触发烘焙（_bakeGrain 内部有尺寸去重，不会反复烘）
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: .07,
                  child: CustomPaint(painter: _GrainPainter(_grain)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 轨道环：圆心钉在她的头（--hx/--hy），整环缓慢自转
  /// [t] 现在是 0~1 的相位（10Hz Ticker 推进，见 `_onOrbitTick`）
  Widget _orbit(
    double w,
    double h, {
    required double diameter,
    required double alpha,
    required bool dashed,
    required double t,
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
        child: Transform.rotate(
          angle: (reverse ? -1 : 1) * t * 2 * math.pi,
          child: CustomPaint(
            painter: _RingPainter(
              color: C.blue.withAlpha((alpha * 255).round()),
              dashed: dashed,
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
  /// ⚠️ 「向上淡出」原来是 ShaderMask(dstIn) 蒙版——那是一整块额外离屏通道；
  ///    现把同一条渐变直接当线条的**颜色 shader**（水平线在所处行高取同色、
  ///    垂直线沿长度取渐变，与蒙版逐像素一致），省一层 layer。
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
          child: CustomPaint(painter: _GridPainter(phase: _floorPhase)),
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
/// 淡出＝线色自带与原 ShaderMask(dstIn) 同参数的竖向渐变：
/// bottom(α.16) → 85% 处透明（stop 0.85，再往上保持透明）
class _GridPainter extends CustomPainter {
  const _GridPainter({required this.phase});

  final double phase;

  @override
  void paint(Canvas canvas, Size s) {
    final Paint p = Paint()
      ..strokeWidth = 1
      ..shader = ui.Gradient.linear(
        Offset(0, s.height),
        Offset(0, 0),
        <Color>[const Color(0x2938E1FF), const Color(0x0038E1FF)],
        <double>[0, .85],
      );
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

/// 颗粒：原型的 SVG feTurbulence 换成程序化噪点，用 overlay 混合。
/// ⚠️ 性能版：噪点只烘焙成一张 `ui.Image`（见 `_bakeGrain`），paint 时
/// **一次 drawImage + overlay 混合**直接落在画布上——不再 saveLayer，
/// 也不再每帧重放 ~6000 个 1.4px 小矩形。视觉与旧版逐像素一致
/// （同一颗随机种子 20261007、同一密度 w*h/420、同一 1.4px 颗粒）。
class _GrainPainter extends CustomPainter {
  const _GrainPainter(this.noise);

  final ui.Image? noise;

  @override
  void paint(Canvas canvas, Size s) {
    final ui.Image? img = noise;
    if (img == null) return; // 烘焙完成前先不画（7% 透明度，缺一帧无人察觉）
    final Rect dst = Offset.zero & s;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      dst,
      Paint()..blendMode = BlendMode.overlay,
    );
  }

  @override
  bool shouldRepaint(covariant _GrainPainter old) => old.noise != noise;
}
