import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/fidelity.dart';
import '../../design/ref.dart';
import '../../widgets/slow_ticker.dart';

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
        final Widget content = ColoredBox(color: Ref.bg, child: child);
        final Widget screen = SizedBox(
          width: w,
          height: h,
          // 手机全屏时没有圆角，别为 0 圆角再套一层 ClipRRect：
          // ClipRRect 会在每帧多一个 clip/saveLayer 图层。
          child: framed
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(44),
                  child: content,
                )
              : content,
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
  // JS go()：三道各 360ms 推入（错峰 65）= 490 → 换页 → 停 140 →
  // 三道各 420ms 推走（反向错峰 65）= 550。整段 1180ms。
  static const double _total = 1180;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1180),
  );

  bool _running = false;
  bool _firedCovered = false;

  /// 1 = 前进（从右推入、向左推走）；−1 = 返回（反向）
  double _dir = 1;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> play({bool back = false}) async {
    if (_running) return;
    _running = true;
    _firedCovered = false;
    _dir = back ? -1 : 1;
    await _c.forward(from: 0);
    _running = false;
    widget.onDone?.call();
  }

  ({double enter, double exit}) get _phase {
    final double ms = _c.value * _total;
    return (
      enter: (ms / 490).clamp(0.0, 1.0),
      exit: ((ms - 630) / 550).clamp(0.0, 1.0),
    );
  }

  double get _ms => _c.value * _total;

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
          final double kIn = ((_ms - i * 65) / 360).clamp(0.0, 1.0);
          final double kOut = ((_ms - 630 - (2 - i) * 65) / 420).clamp(
            0.0,
            1.0,
          );
          final double din = Ref.wipe.transform(kIn);
          final double dout = Ref.wipe.transform(kOut);
          // 进：dir·130% → 0；出：0 → −dir·130%
          final double tx = _dir * 130 * (1 - din) - _dir * 130 * dout;
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
              // .wl 随第三道斜带一起滑；换页那一拍放大到 1.08（260ms，不保持）
              content: Transform.scale(
                scale: _ms >= 490 && _ms < 750
                    ? 1 + .08 * ((_ms - 490) / 260)
                    : 1,
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

/// 浮尘氛围层 —— 参考稿 `#bgfx`（JS L974-990，z-index 1：天幕之上、界面之下）。
///
/// docs/49 G：这一层在参考稿里**每一页都在**，App 里组件写了却从没挂上去。
/// 逐条对照参考稿（它按 60fps 每帧推进，这里换算成随时间的闭式解）：
///   · 46 颗尘：r .5~2、上浮 v .12~.5 px/帧、相位 p 每帧 +s（.01~.04）
///     x 每帧 += sin(p)·.25 → 横摆幅度 .25/s（6~25px）
///   · 透明度 .45 ± .25·sin(2p) 一呼一吸；r > 1.5 的用场景强调色，其余白
///   · 流星：每帧 .6% 概率出一道（≈ 每 2.8s 一道），从左外 −120 横穿，
///     9~16 px/帧、长 60~160、透明 → 强调色渐变、高 1.2、整体 .6
///
/// 性能：时钟是 30fps 的 [SlowTicker]（Timer，不逐 vsync 排帧），只触发这一层
/// 的 repaint（`CustomPainter(repaint:)`，不重建 widget）；自带 RepaintBoundary。
/// 减弱动态 / 省电档 / [animate] = false：整层不画、时钟停。
class RefAmbient extends StatefulWidget {
  const RefAmbient({
    super.key,
    this.accent,
    this.count = 46,
    this.animate = true,
  });

  final Color? accent;
  final int count;

  /// false = 停（被不透明整页盖住时用）
  final bool animate;

  @override
  State<RefAmbient> createState() => _RefAmbientState();
}

class _RefAmbientState extends State<RefAmbient> {
  late final SlowTicker _clock = SlowTicker(const Duration(milliseconds: 33));
  final math.Random _rnd = math.Random(20261026);
  final _Streak _streak = _Streak();
  bool _reduce = false;
  bool _on = false;

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
  void initState() {
    super.initState();
    _clock.addListener(_maybeStreak);
    Fidelity.lowPower.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(RefAmbient old) {
    super.didUpdateWidget(old);
    _sync();
  }

  bool get _want => widget.animate && !_reduce && !Fidelity.lowPower.value;

  void _sync() {
    final bool want = _want;
    if (want == _on) return;
    _on = want;
    if (want) {
      _clock.start();
    } else {
      _clock.stop();
    }
    if (mounted) setState(() {});
  }

  /// 参考稿 `if(!streak&&Math.random()<.006)`：每 60fps 帧 .6% → 每 30fps 一拍约 1.2%
  void _maybeStreak() {
    final double t = _clock.value;
    if (_streak.active(t)) return;
    if (_rnd.nextDouble() >= .012) return;
    _streak
      ..t0 = t
      ..y = .1 + _rnd.nextDouble() * .8
      ..v = (9 + _rnd.nextDouble() * 7) * 60
      ..l = 60 + _rnd.nextDouble() * 100;
  }

  @override
  void dispose() {
    _clock.removeListener(_maybeStreak);
    Fidelity.lowPower.removeListener(_sync);
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_on && (_reduce || Fidelity.lowPower.value)) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _MotePainter(
            motes: _motes,
            clock: _clock,
            streak: _streak,
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

/// 当前那一道流星（t0 < 0 = 没有）；横穿完自动失效
class _Streak {
  double t0 = -1;
  double y = 0;
  double v = 0; // px/s
  double l = 0;
  double width = 430;

  double xAt(double t) => -120 + (t - t0) * v;
  bool active(double t) => t0 >= 0 && xAt(t) <= width;
}

class _MotePainter extends CustomPainter {
  _MotePainter({
    required this.motes,
    required this.clock,
    required this.streak,
    required this.accent,
  }) : super(repaint: clock);

  final List<_Mote> motes;
  final SlowTicker clock;
  final _Streak streak;
  final Color accent;

  @override
  void paint(Canvas canvas, Size s) {
    if (s.isEmpty) return;
    final double t = clock.value;
    final double f = t * 60; // 参考稿按帧推进：换算成「第几帧」
    final double w = s.width;
    final double h = s.height;
    final double span = h + 10; // 参考稿 y < −5 → 回到 H + 5
    final Paint p = Paint();
    for (final _Mote m in motes) {
      final double ph = m.phase + m.speed * f;
      // y 每帧 −v，越过顶端从底下重新出来
      final double y = ((m.y * h - m.v * f + 5) % span + span) % span - 5;
      // x 每帧 += sin(p)·.25 的累加 = −(.25/s)·(cos p − cos p0)
      final double x =
          ((m.x * w - (.25 / m.speed) * (math.cos(ph) - math.cos(m.phase))) %
                  w +
              w) %
          w;
      final double a = (.45 + math.sin(ph * 2) * .25).clamp(0.0, 1.0);
      p.color = (m.r > 1.5 ? accent : Colors.white).withValues(alpha: a);
      canvas.drawCircle(Offset(x, y), m.r, p);
    }
    streak.width = w;
    if (streak.active(t)) {
      final double x = streak.xAt(t);
      final Rect r = Rect.fromLTWH(x, streak.y * h, streak.l, 1.2);
      canvas.drawRect(
        r,
        Paint()
          ..shader = LinearGradient(
            colors: <Color>[
              const Color(0x00FFFFFF),
              accent.withValues(alpha: .6),
            ],
          ).createShader(r),
      );
    }
  }

  @override
  bool shouldRepaint(_MotePainter o) =>
      o.accent != accent || !identical(o.motes, motes);
}
