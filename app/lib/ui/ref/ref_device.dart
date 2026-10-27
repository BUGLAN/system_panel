import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/ref.dart';

/// ═══════════════════════════════════════════════════════════
///  设备壳 —— 参考稿 #app（L38-39）
///
///  手机上是全屏；窗口变宽时不会无脑拉满，而是钳成 430×920 的
///  「手机比例」，居中加一圈外框（44 圆角 + 11px 深边 + 双层辉光）。
///  这一条同时满足「适配常见窗口尺寸」与「参考稿的桌面呈现」。
/// ═══════════════════════════════════════════════════════════
class RefDeviceFrame extends StatelessWidget {
  const RefDeviceFrame({super.key, required this.child, this.accent});

  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double w = math.min(c.maxWidth, Ref.deviceMaxW);
        final double h = math.min(c.maxHeight, Ref.deviceMaxH);
        final bool framed = c.maxWidth >= 600 || c.maxHeight >= 960;
        final Widget screen = SizedBox(
          width: w,
          height: h,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(framed ? 44 : 0),
            child: ColoredBox(color: Ref.bg, child: child),
          ),
        );
        if (!framed) return screen;
        // L39：外框 1px 白 9% + 11px 深色 + 12px 白 7% + 两个大范围辉光
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(56),
                color: const Color(0xFF0C0A16),
                border: Border.all(color: const Color(0x17FFFFFF)),
                boxShadow: <BoxShadow>[
                  const BoxShadow(color: Color(0xD9000000), blurRadius: 60),
                  BoxShadow(
                    color: Ref.a(accent ?? Ref.violet, .18),
                    blurRadius: 120,
                  ),
                ],
              ),
              child: Padding(padding: const EdgeInsets.all(11), child: screen),
            ),
          ),
        );
      },
    );
  }
}

/// ═══════════════════════════════════════════════════════════
///  斜切 wipe 转场 —— 参考稿 L493-499 + L1172-1183
///
///  三道斜带（accent / white / 深底+标题）从 translateX(±130%) skewX(-18deg)
///  推入：进 360ms、三道各错峰 65ms；第三道中央落 54px/900/字距 8 的大字。
///  出 420ms 反向推走。整段 900ms。
///
///  用法：放在 Stack 最顶层，调用 play() 跑完整段。
/// ═══════════════════════════════════════════════════════════
class RefWipe extends StatefulWidget {
  const RefWipe({
    super.key,
    this.accent,
    this.title = '',
    this.sub = '',
    this.onCovered,
    this.onDone,
  });

  final Color? accent;
  final String title;
  final String sub;

  /// 屏幕被完全盖住的那一拍（在这里换页）
  final VoidCallback? onCovered;

  /// 整段结束
  final VoidCallback? onDone;

  @override
  State<RefWipe> createState() => RefWipeState();
}

class RefWipeState extends State<RefWipe> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  bool _running = false;
  bool _firedCovered = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 0~40% 推入（360ms），40~46% 停，46%~93% 推走（420ms）
  Future<void> play() async {
    if (_running) return;
    _running = true;
    _firedCovered = false;
    await _c.forward(from: 0);
    _running = false;
    widget.onDone?.call();
  }

  ({double enter, double exit}) get _phase {
    final double v = _c.value;
    return (
      enter: (v / .40).clamp(0.0, 1.0),
      exit: ((v - .46) / .47).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = widget.accent ?? Ref.acid;
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, Widget? _) {
        final ({double enter, double exit}) p = _phase;
        if (!_firedCovered && p.enter >= 1) {
          _firedCovered = true;
          // ⚠️ **不能在这里直接调**：onCovered 干的是换页（setState），
          //    而这一帧正处在 build 里 —— 会炸 "setState() called during build"，
          //    整个 Stack 那帧被丢掉，观感是「点了转场但页面没动」。
          //    推到这一帧结束后再换页。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onCovered?.call();
          });
        }
        if (_c.value == 0) return const SizedBox.shrink();

        Widget bar(int i, Color? color, {Widget? content}) {
          final double lagIn = i * .055;
          final double kIn = ((p.enter - lagIn) / (1 - lagIn)).clamp(0.0, 1.0);
          final double lagOut = (2 - i) * .055;
          final double kOut = ((p.exit - lagOut) / (1 - lagOut)).clamp(
            0.0,
            1.0,
          );
          final double din = Ref.wipe.transform(kIn);
          final double dout = Ref.wipe.transform(kOut);
          // 进：-130% → 0；出：0 → +130%
          final double tx = -130 + din * 130 + dout * 130;
          return Positioned.fill(
            child: IgnorePointer(
              child: FractionalTranslation(
                translation: Offset(tx / 100, 0),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.skewX(-18 * math.pi / 180),
                  child: ColoredBox(
                    color: color ?? const Color(0xFF0B0A14),
                    child: content,
                  ),
                ),
              ),
            ),
          );
        }

        return Stack(
          children: <Widget>[
            bar(0, accent),
            bar(1, Colors.white),
            bar(
              2,
              null,
              content: Opacity(
                opacity: (Ref.wipe.transform(p.enter) * (1 - p.exit)).clamp(
                  0.0,
                  1.0,
                ),
                child: Center(
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.skewX(18 * math.pi / 180),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          widget.title,
                          textAlign: TextAlign.center,
                          style: refText(
                            family: Ref.fc,
                            size: 54,
                            wght: 900,
                            ls: 8,
                            height: 1,
                            color: accent,
                            shadows: <Shadow>[
                              Shadow(color: accent, blurRadius: 30),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.sub,
                          textAlign: TextAlign.center,
                          style: refText(
                            family: Ref.fm,
                            size: 12,
                            wght: 700,
                            ls: 8,
                            height: 1,
                            color: Ref.dim,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: 180,
                          height: 3,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: <Color>[
                                const Color(0x00FFFFFF),
                                accent,
                                const Color(0x00FFFFFF),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 浮尘氛围层（参考稿 L974-990 的 #bgfx）：46 颗尘缓缓上浮 + 正弦横摆。
///
/// 减弱动态时整层不挂（返回 0 尺寸），不产生常驻 ticker。
class RefAmbient extends StatefulWidget {
  const RefAmbient({super.key, this.accent, this.count = 46});

  final Color? accent;
  final int count;

  @override
  State<RefAmbient> createState() => _RefAmbientState();
}

class _RefAmbientState extends State<RefAmbient>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  final math.Random _rnd = math.Random(20261026);

  late final List<_Mote> _motes = List<_Mote>.generate(
    widget.count,
    (int i) => _Mote(
      x: _rnd.nextDouble(),
      y: _rnd.nextDouble(),
      r: .5 + _rnd.nextDouble() * 1.5,
      v: .12 + _rnd.nextDouble() * .38,
      phase: _rnd.nextDouble() * math.pi * 2,
      speed: .01 + _rnd.nextDouble() * .03,
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      if (_c.isAnimating) _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, Widget? _) => CustomPaint(
          painter: _MotePainter(
            motes: _motes,
            t: _c.value * 24,
            accent: widget.accent ?? Ref.acid,
          ),
        ),
      ),
    );
  }
}

class _Mote {
  _Mote({
    required this.x,
    required this.y,
    required this.r,
    required this.v,
    required this.phase,
    required this.speed,
  });

  final double x;
  final double y;
  final double r;
  final double v;
  final double phase;
  final double speed;
}

class _MotePainter extends CustomPainter {
  const _MotePainter({
    required this.motes,
    required this.t,
    required this.accent,
  });

  final List<_Mote> motes;
  final double t;
  final Color accent;

  @override
  void paint(Canvas canvas, Size s) {
    if (s.isEmpty) return;
    final Paint p = Paint();
    for (final _Mote m in motes) {
      final double y = ((m.y - t * m.v / 24) % 1 + 1) % 1;
      final double x =
          ((m.x + math.sin(t * m.speed + m.phase) * .006) % 1 + 1) % 1;
      p.color = (m.r > 1.5 ? accent : Colors.white).withAlpha(
        (.5 * 255).round(),
      );
      canvas.drawCircle(Offset(x * s.width, y * s.height), m.r, p);
    }
  }

  @override
  bool shouldRepaint(_MotePainter o) => o.t != t || o.accent != accent;
}
