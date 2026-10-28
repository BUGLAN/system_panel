import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../design/ref.dart';

/// ═══════════════════════════════════════════════════════════
///  天幕 —— 参考稿 .bg（CSS L41-53，DOM L681）
///
///  逐层对照（DOM 顺序即绘制顺序）：
///   · .bg      L41  absolute / inset:0 / z-index:0 / overflow:hidden
///   · .neb     L42  三层椭圆径向雾（accent 22% @50%/32%、
///                  violet 20% @18%/72%、hot 10% @86%/55%），
///                  inset:-25%，16s ease-in-out alternate
///                  → translate(5%,-4%) scale(1.1) rotate(5deg)
///   · .ghost   L49  居中（left:50% translateX(-50%)，top:24%）的
///                  900 200px/1 描边大字，2px 白 5%，字距 -6
///   · .horizon L48  bottom:45% 的 1px 渐变线，opacity .35，辉光 20px
///   · .floor   L44-47 bottom:-6% / 高 52% / 左右 -60% /
///                  perspective(380px) rotateX(64deg) / 46px 网格 /
///                  2.4s 向上滚一格 / 向上淡出遮罩
///   · .scan    L50  3px 周期、1px 白 2.2% 扫描线
///   · .noise   L52  inset:-50% / opacity .06 / 0.9s steps(4) 抖动
///   · .vig     L51  radial 120% 85% at 50% 40% / 45% 后压黑 78%
///
///  ⚠️ 这是一个**普通 Widget（自己铺满父级）**，不是 Positioned。
///  调用方放进 Stack 时用 Positioned.fill(child: RefBackground(...))，
///  或作为 Stack(fit: StackFit.expand) 的第一个孩子。
///  桌面装饰 .stage-deco（L28-36）不做 —— 手机端没有它。
/// ═══════════════════════════════════════════════════════════
class RefBackground extends StatefulWidget {
  const RefBackground({
    super.key,
    required this.accent,
    this.ghost = '系统',
    this.animate = true,
  });

  /// 当前场景的主强调色（参考稿 #app{--accent}，由路由切换写入）
  final Color accent;

  /// .ghost 那枚大字（大厅是「系统」）
  final String ghost;

  /// 关掉后完全静止（三组循环都不跑）
  final bool animate;

  @override
  State<RefBackground> createState() => _RefBackgroundState();
}

class _RefBackgroundState extends State<RefBackground>
    with TickerProviderStateMixin {
  /// L42 animation:neb 16s ease-in-out infinite alternate
  late final AnimationController _neb = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  );

  /// L47 animation:floor 2.4s linear infinite
  late final AnimationController _floor = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  /// L52 animation:grain .9s steps(4) infinite
  late final AnimationController _grain = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  late final CurvedAnimation _nebCurve = CurvedAnimation(
    parent: _neb,
    curve: Curves.easeInOut,
  );

  /// 预烘焙噪点（L52 的 160x160 feTurbulence）：只画一次，之后每帧只是位移
  ui.Image? _noise;
  bool _motion = false;

  @override
  void initState() {
    super.initState();
    _noise = _bakeNoise();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(RefBackground old) {
    super.didUpdateWidget(old);
    _syncMotion();
  }

  /// 循环的唯一开关：关掉 / 系统要求减少动效 → 一律落终态，不跑循环
  void _syncMotion() {
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final bool on = widget.animate && !reduce;
    if (on == _motion) {
      if (!on &&
          (_neb.isAnimating || _floor.isAnimating || _grain.isAnimating)) {
        _stopAll();
      }
      return;
    }
    _motion = on;
    if (on) {
      _neb.repeat(reverse: true);
      _floor.repeat();
      _grain.repeat();
    } else {
      _stopAll();
    }
  }

  void _stopAll() {
    _neb.value = 0;
    _floor.value = 0;
    _grain.value = 0;
  }

  @override
  void dispose() {
    _nebCurve.dispose();
    _neb.dispose();
    _floor.dispose();
    _grain.dispose();
    _noise?.dispose();
    super.dispose();
  }

  /// L52：160x160 的白点噪点，opacity 由绘制时统一压到 .06
  ui.Image _bakeNoise() {
    const int kTile = 160;
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas c = Canvas(rec);
    final math.Random rnd = math.Random(0x5EED);
    for (int i = 0; i < 2600; i++) {
      final double x = rnd.nextDouble() * kTile;
      final double y = rnd.nextDouble() * kTile;
      final int a = 40 + rnd.nextInt(200);
      c.drawRect(
        Rect.fromLTWH(x, y, 1 + rnd.nextDouble(), 1 + rnd.nextDouble()),
        Paint()..color = Color.fromARGB(a, 255, 255, 255),
      );
    }
    final ui.Picture pic = rec.endRecording();
    final ui.Image img = pic.toImageSync(kTile, kTile);
    pic.dispose();
    return img;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      // L41 overflow:hidden
      child: ColoredBox(
        color: Ref.bg, // #app{background:var(--bg)} L38
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final double w = box.maxWidth;
            final double h = box.maxHeight;
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // ── .neb（L42）────────────────────────────────────
                AnimatedBuilder(
                  animation: _nebCurve,
                  builder: (BuildContext context, Widget? child) {
                    final double t = _nebCurve.value;
                    // @keyframes neb{to{translate3d(5%,-4%,0) scale(1.1) rotate(5deg)}}
                    // 百分比是 .neb 自身尺寸（= 容器 1.5 倍，因为 inset:-25%）
                    final double dx = w * 1.5 * .05 * t;
                    final double dy = -h * 1.5 * .04 * t;
                    final double s = 1 + .1 * t;
                    final double a = 5 * math.pi / 180 * t;
                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..translateByDouble(dx, dy, 0, 1)
                        ..rotateZ(a)
                        ..scaleByDouble(s, s, 1, 1),
                      child: CustomPaint(
                        painter: _NebPainter(accent: widget.accent),
                      ),
                    );
                  },
                ),
                // ── .ghost（L49）──────────────────────────────────
                IgnorePointer(
                  child: CustomPaint(
                    painter: _GhostPainter(text: widget.ghost),
                  ),
                ),
                // ── .horizon（L48）────────────────────────────────
                IgnorePointer(
                  child: CustomPaint(
                    painter: _HorizonPainter(accent: widget.accent),
                  ),
                ),
                // ── .floor（L44-47）───────────────────────────────
                Positioned(
                  left: -w * .6,
                  width: w * 2.2,
                  bottom: -h * .06,
                  height: h * .52,
                  child: IgnorePointer(
                    child: Transform(
                      // transform-origin:50% 100%（rotateX 绕底边翻）
                      alignment: Alignment.bottomCenter,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, -1 / 380) // perspective(380px)
                        ..rotateX(64 * math.pi / 180),
                      child: AnimatedBuilder(
                        animation: _floor,
                        builder: (BuildContext context, Widget? child) {
                          // mask-image:linear-gradient(to top,#000 5%,transparent 80%)
                          // —— 直接做进描线的着色器里（线是纯色，乘渐变 = 遮罩）。
                          // ⚠️ 别用 ShaderMask：它在 3D 透视下的 saveLayer 会被
                          //    Impeller 画成一整块不透明的亮板（底部那道硬边暗带）。
                          return CustomPaint(
                            painter: _FloorPainter(
                              accent: widget.accent,
                              // @keyframes floor{to{background-position:0 46px}}
                              scroll: _floor.value * 46,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                // ── .scan（L50）──────────────────────────────────
                IgnorePointer(
                  child: CustomPaint(painter: const _ScanPainter()),
                ),
                // ── .noise（L52）─────────────────────────────────
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _grain,
                    builder: (BuildContext context, Widget? child) {
                      final Offset o = _grainStep(_grain.value);
                      return CustomPaint(
                        painter: _NoisePainter(
                          image: _noise,
                          // inset:-50% ⇒ 元素是容器 2 倍，百分比按它算
                          dx: o.dx * 2 * w,
                          dy: o.dy * 2 * h,
                        ),
                      );
                    },
                  ),
                ),
                // ── .vig（L51）───────────────────────────────────
                IgnorePointer(
                  child: CustomPaint(painter: const _VignettePainter()),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// @keyframes grain{25%{translate(-3%,2%)}50%{translate(2%,-3%)}75%{translate(-2%,-1%)}}
  /// steps(4) = 4 段跳变，不插值
  Offset _grainStep(double t) {
    const List<Offset> k = <Offset>[
      Offset.zero,
      Offset(-.03, .02),
      Offset(.02, -.03),
      Offset(-.02, -.01),
    ];
    return k[(t * 4).floor().clamp(0, 3)];
  }
}

/// 椭圆径向渐变（CSS radial-gradient(38% 28% at ...) 的等价物）。
/// 画布先按 ry/rx 压扁，再画正圆 —— shader 跟着 CTM 一起变形。
void _ellipse(
  Canvas canvas,
  Offset center,
  double rx,
  double ry,
  List<Color> colors,
  List<double> stops,
) {
  if (rx <= 0 || ry <= 0) return;
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.scale(1, ry / rx);
  // ⚠️ CSS 的 radial-gradient 在椭圆外继续铺最后一档颜色（clamp 到整盒）。
  //    只画椭圆外接框的话，暗角 .78 的黑在框外就丢了 —— 屏幕下方 18%
  //    会多出一道没压暗的亮带（真机截图那道硬边）。这里铺满一个足够大的方。
  final double big = rx * 4 + center.distance * 4 + 4000;
  canvas.drawRect(
    Rect.fromCircle(center: Offset.zero, radius: big),
    Paint()
      ..shader = ui.Gradient.radial(
        Offset.zero,
        rx,
        colors,
        stops,
        TileMode.clamp,
      ),
  );
  canvas.restore();
}

/// .neb（L42）
class _NebPainter extends CustomPainter {
  const _NebPainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size s) {
    // .neb{inset:-25%} ⇒ 渐变盒是 1.5 倍
    final Rect box = Rect.fromLTWH(
      -s.width * .25,
      -s.height * .25,
      s.width * 1.5,
      s.height * 1.5,
    );
    Offset at(double fx, double fy) =>
        Offset(box.left + box.width * fx, box.top + box.height * fy);

    _ellipse(
      canvas,
      at(.50, .32),
      box.width * .38,
      box.height * .28,
      <Color>[Ref.a(accent, .22), Ref.a(accent, 0)],
      <double>[0, .70],
    );
    _ellipse(
      canvas,
      at(.18, .72),
      box.width * .35,
      box.height * .25,
      <Color>[Ref.a(Ref.violet, .20), Ref.a(Ref.violet, 0)],
      <double>[0, .70],
    );
    _ellipse(
      canvas,
      at(.86, .55),
      box.width * .30,
      box.height * .25,
      <Color>[Ref.a(Ref.hot, .10), Ref.a(Ref.hot, 0)],
      <double>[0, .70],
    );
  }

  @override
  bool shouldRepaint(_NebPainter o) => o.accent != accent;
}

/// .ghost（L49）：top:24% / 居中 / 900 200px / 描边 2px 白 5% / 字距 -6
class _GhostPainter extends CustomPainter {
  const _GhostPainter({required this.text});
  final String text;

  @override
  void paint(Canvas canvas, Size s) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: refText(
          family: Ref.fc,
          size: 200, // L49 font:900 200px/1
          wght: 900,
          ls: -6, // letter-spacing:-6px
          height: 1,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth =
                2 // -webkit-text-stroke:2px
            ..color = const Color(0x0DFFFFFF), // rgba(255,255,255,.05)
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    tp.paint(canvas, Offset((s.width - tp.width) / 2, s.height * .24));
  }

  @override
  bool shouldRepaint(_GhostPainter o) => o.text != text;
}

/// .horizon（L48）：bottom 45% / 1px 渐变线 / opacity .35 / 辉光 20
class _HorizonPainter extends CustomPainter {
  const _HorizonPainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size s) {
    final double y = s.height * .55; // bottom:45%
    final Rect line = Rect.fromLTWH(0, y, s.width, 1);
    final Color edge = Ref.a(accent, 0);
    final Color mid = Ref.a(accent, .35); // opacity:.35
    canvas.drawRect(
      line,
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[edge, mid, edge],
          stops: const <double>[0, .5, 1],
        ).createShader(line),
    );
    // box-shadow:0 0 20px var(--accent)
    canvas.drawRect(
      line,
      Paint()
        ..color = mid
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
  }

  @override
  bool shouldRepaint(_HorizonPainter o) => o.accent != accent;
}

/// .floor（L44-47）：46px 网格、accent 26%、向上滚一格
class _FloorPainter extends CustomPainter {
  const _FloorPainter({required this.accent, required this.scroll});
  final Color accent;

  /// 0 → 46（@keyframes floor 的 background-position y）
  final double scroll;

  @override
  void paint(Canvas canvas, Size s) {
    const double cell = 46; // background-size:46px 46px
    final Rect r = Offset.zero & s;
    final Paint p = Paint()
      // color-mix(--accent 26%, transparent) × 自下而上的遮罩
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: <Color>[
          Ref.a(accent, .26),
          Ref.a(accent, .26),
          Ref.a(accent, 0),
        ],
        stops: const <double>[0, .05, .8],
      ).createShader(r)
      ..strokeWidth = 1;
    for (double x = 0; x <= s.width; x += cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), p);
    }
    final double off = scroll % cell;
    for (double y = off; y <= s.height; y += cell) {
      canvas.drawLine(Offset(0, y), Offset(s.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_FloorPainter o) =>
      o.accent != accent || o.scroll != scroll;
}

/// .scan（L50）：repeating-linear-gradient 3px 周期、1px 白 2.2%
class _ScanPainter extends CustomPainter {
  const _ScanPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final Paint p = Paint()..color = const Color(0x06FFFFFF); // .022
    for (double y = 0; y < s.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, s.width, 1), p);
    }
  }

  @override
  bool shouldRepaint(_ScanPainter o) => false;
}

/// .noise（L52）：预烘焙贴图 + 整像素位移（绝不每帧造矩形）
class _NoisePainter extends CustomPainter {
  const _NoisePainter({
    required this.image,
    required this.dx,
    required this.dy,
  });
  final ui.Image? image;
  final double dx;
  final double dy;

  @override
  void paint(Canvas canvas, Size s) {
    final ui.Image? img = image;
    if (img == null) return;
    final Rect area = Offset.zero & s;
    canvas.saveLayer(
      area,
      Paint()..color = const Color(0x0FFFFFFF), // opacity:.06
    );
    final Paint p = Paint()
      ..filterQuality = FilterQuality.none
      ..shader = ui.ImageShader(
        img,
        TileMode.repeated,
        TileMode.repeated,
        Matrix4.translationValues(dx, dy, 0).storage,
      );
    canvas.drawRect(area, p);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NoisePainter o) =>
      o.image != image || o.dx != dx || o.dy != dy;
}

/// .vig（L51）：radial 120% 85% at 50% 40%，45% 后压黑 78%
class _VignettePainter extends CustomPainter {
  const _VignettePainter();

  @override
  void paint(Canvas canvas, Size s) {
    _ellipse(
      canvas,
      Offset(s.width * .5, s.height * .4),
      s.width * .6, // 120% / 2
      s.height * .425, // 85% / 2
      <Color>[const Color(0x00000000), const Color(0xC7000000)], // .78
      <double>[.45, 1],
    );
  }

  @override
  bool shouldRepaint(_VignettePainter o) => false;
}
