import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../design/ref.dart';
import 'ref_kit.dart';

/// ═══════════════════════════════════════════════════════════
///  三块全屏幕 —— 升级 / 失败 / 确认弹窗
///
///  唯一基准：宿主养成系统_重设计.html
///    · RefLevelUp  CSS L450-460 / DOM L820-826 / JS L1539-1549
///    · RefFail     CSS L461-474 / DOM L828-833 / JS L1550-1560
///    · RefModal    CSS L475-480 / DOM L835      / JS L1140-1142
///
///  【布局契约】三者顶层都是「整屏矩形」（内部没有 Positioned），调用方塞进
///  Stack 并按 [visible] 开关：
///
///      Stack(children: <Widget>[
///        page,
///        Positioned.fill(child: RefLevelUp(visible: lvUp, ...)),
///        Positioned.fill(child: RefFail(visible: failed, ...)),
///        Positioned.fill(child: RefModal(visible: ask, ...)),
///      ])
///
///  【动效契约】控制器全在 State 且 dispose 释放；[visible] 转 false 时停掉
///  所有循环；MediaQuery.maybeDisableAnimationsOf 为真时落终态、不跑任何循环
///  （光轮停转、故障字只留固定偏色、呼吸不跳）。
/// ═══════════════════════════════════════════════════════════

/// #lvup（L451）的放射半径。CSS 是 circle at 50% 45%（默认 farthest-corner，
/// 400pt 屏约 512px）；Flutter 的 RadialGradient.radius 以「短边」为单位 →
/// 512/390 ≈ 1.3
const double _kNovaRadius = 1.3;

/// #lvup .rays（L452）：1400×1400 / 30s 一圈
/// @keyframes spin{to{transform:rotate(360deg)}}（L117）
const int _kRaysMs = 30000;

/// @keyframes blinkdot{50%{opacity:.25}}（L132），.lu-tap 1.4s（L460）
const int _kBreathMs = 1400;

/// .modal（L476）：宽 340 / padding 24 22 20 / r22
const double _kModalW = 340;

/// .modal .mb .btn（L480）：高 52 / 字号 15
const double _kModalBtnH = 52;

/// ═══════════════════════════════════════════════════════════════
///  RefLevelUp —— 升级幕
///
///  · .lu-t   700 italic 52px acid + 0 0 30px + 4px 4px 0 hot（L453）
///  · .lu-n   96px 三槽：旧 60px dim2 / 三角 40px acid / 新 96px 白 + 40px 辉光
///  · .lu-p   padding 14/18 / r16 / rgba(0,0,0,.4) / 1px acid .35 / 14×1.7
///  · .lu-tap 12px mono 字距 4 dim，1.4s 呼吸
///  进场时序照 JS L1544-1547：标题 520ms / 新数字 720ms(延迟 320) /
///  说明 500ms(延迟 700)；点击 1000ms 后才接受（JS L1548）。
/// ═══════════════════════════════════════════════════════════════
class RefLevelUp extends StatefulWidget {
  const RefLevelUp({
    super.key,
    required this.from,
    required this.to,
    required this.perk,
    required this.onTap,
    this.visible = true,
  });

  final int from;
  final int to;

  /// .lu-p 的说明文案（JS L1541-1542 的 perks）
  final String perk;

  /// .lu-tap TAP TO CONTINUE —— 整屏可点（JS L1548 的 ov.onclick）
  final VoidCallback onTap;

  final bool visible;

  @override
  State<RefLevelUp> createState() => _RefLevelUpState();
}

class _RefLevelUpState extends State<RefLevelUp> with TickerProviderStateMixin {
  /// L452：animation:spin 30s linear infinite
  late final AnimationController _rays = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _kRaysMs),
  );

  /// L460：.lu-tap 用 blinkdot 1.4s
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _kBreathMs),
  );

  /// JS L1544-1547 的进场编排，总长 1200ms
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(covariant RefLevelUp old) {
    super.didUpdateWidget(old);
    if (old.visible != widget.visible) _sync();
  }

  void _sync() {
    if (!widget.visible) {
      _rays.stop();
      _breath.stop();
      _enter.stop();
      return;
    }
    if (_reduce) {
      _enter.value = 1;
      _rays.stop();
      _breath.stop();
      return;
    }
    _enter.forward(from: 0);
    if (!_rays.isAnimating) _rays.repeat();
    if (!_breath.isAnimating) _breath.repeat();
  }

  @override
  void dispose() {
    _rays.dispose();
    _breath.dispose();
    _enter.dispose();
    super.dispose();
  }

  /// 0~1 的线性取段
  /// 时间段进度 [0,1]。
  ///
  /// ⚠️ 两端都要 clamp：过冲曲线（Ref.pop / Ref.flip 这类）在 t=1 上可能
  ///    算出 1.0000000000000002，直接喂 Curve.transform 会触发 Flutter 的
  ///    `t >= 0.0 && t <= 1.0` 断言（离屏出图实测崩在升级过场）。
  double _seg(double ms, int a, int b) {
    if (ms <= a) return 0;
    if (ms >= b) return 1;
    return ((ms - a) / (b - a)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _enter,
      builder: (BuildContext context, Widget? child) {
        final double ms = _enter.value * 1200;
        // JS L1544：标题 scale(3)→1，520ms cubic-bezier(.2,1.5,.4,1)
        final double tTitle = Ref.pop.transform(_seg(ms, 0, 520));
        final double titleScale = 3 + (1 - 3) * tTitle;
        final double titleOpa = _seg(ms, 0, 260);
        // JS L1545：新数字 scale(0) rotate(-120) → 1.35(offset .7) → 1，
        // 720ms 时长 / 延迟 320
        final double nk = _seg(ms, 320, 1040);
        final double nScale;
        final double nRot;
        if (nk < .7) {
          final double t = Curves.easeOut.transform((nk / .7).clamp(0.0, 1.0));
          nScale = 1.35 * t;
          nRot = -120 * (1 - t);
        } else {
          final double t = Curves.easeOut.transform(
            ((nk - .7) / .3).clamp(0.0, 1.0),
          );
          nScale = 1.35 + (1 - 1.35) * t;
          nRot = 0;
        }
        // JS L1546：说明 translateY(20)→0，500ms 延迟 700
        final double pk = Curves.easeOut.transform(_seg(ms, 700, 1200));
        final double pOpa = _seg(ms, 700, 900);
        final bool tapReady = _reduce || ms >= 1000; // JS L1548 的 sleep(1000)

        return _OverlayScreen(
          onTap: tapReady ? widget.onTap : null,
          // #lvup（L451）：radial acid .25 → rgba(4,3,10,.92) 60%
          background: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -.1), // circle at 50% 45%
                radius: _kNovaRadius,
                colors: <Color>[Color(0x40D6FF3D), Color(0xEB04030A)],
                stops: <double>[0, .6],
              ),
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // .rays（L452）：6deg 实 / 12deg 空，30s 一圈，径向收到 55%
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _RaysPainter(turns: _reduce ? 0 : _rays.value),
                  ),
                ),
              ),
              // ⚠️ 过场里 96px 的等级数字 + 60px 的旧等级 + 两个 20 间距，
              //    在 320~430 宽的屏上会横向溢出（离屏出图实测：溢出 803px，
              //    因为 Row 是 MainAxisSize.min 且整列不受屏宽约束）。
              //    这里把整列收进屏宽并按比例缩放，视觉与参考稿一致。
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // .lu-t（L453）
                      Transform.scale(
                        scale: titleScale,
                        child: Opacity(
                          opacity: titleOpa.clamp(0.0, 1.0),
                          child: Text('LEVEL UP!', style: RefType.levelUp),
                        ),
                      ),
                      // .lu-n（L454-457）：margin 22 0 / gap 20 / 700 96px
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 22),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              '$widget.from',
                              style: refText(
                                family: Ref.fd,
                                size: 60, // .lu-n .o{font-size:60px}（L455）
                                wght: 700,
                                height: 1,
                                color: Ref.dim2,
                              ),
                            ),
                            const SizedBox(width: 20), // gap:20（L454）
                            // .lu-n .arr{font-size:40px;color:acid}（L456）
                            // —— 不写三角字形，按 40px 字号的三角比例画 Path
                            const SizedBox(
                              width: 26,
                              height: 32,
                              child: CustomPaint(
                                painter: _ArrowPainter(color: Ref.acid),
                              ),
                            ),
                            const SizedBox(width: 20),
                            Transform.rotate(
                              angle: nRot * math.pi / 180,
                              child: Transform.scale(
                                scale: nScale,
                                child: Text(
                                  '$widget.to',
                                  style: refText(
                                    family: Ref.fd,
                                    size: 96, // .lu-n{font:700 96px/1}（L454）
                                    wght: 700,
                                    height: 1,
                                    color: Colors.white,
                                    // .nn{text-shadow:0 0 40px acid}（L457）
                                    shadows: const <Shadow>[
                                      Shadow(color: Ref.acid, blurRadius: 40),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // .lu-p（L458）
                      Transform.translate(
                        offset: Offset(0, 20 * (1 - pk)),
                        child: Opacity(
                          opacity: pOpa.clamp(0.0, 1.0),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0x66000000,
                                ), // rgba(0,0,0,.4)
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Ref.a(Ref.acid, .35)),
                              ),
                              child: Text(
                                widget.perk,
                                textAlign: TextAlign.center,
                                style: refText(
                                  size: 14, // L458 font:500 14px/1.7
                                  wght: 500,
                                  height: 1.7,
                                  color: Ref.txt,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // .lu-tap（L460）：margin-top 26 / 12px mono / ls 4 / dim
                      Padding(
                        padding: const EdgeInsets.only(top: 26),
                        child: AnimatedBuilder(
                          animation: _breath,
                          builder: (BuildContext context, Widget? child) {
                            // blinkdot：50% 处 opacity .25，其余 1
                            final double o = _reduce
                                ? .7
                                : 1 -
                                      .75 *
                                          (0.5 -
                                              0.5 *
                                                  math.cos(
                                                    _breath.value * math.pi * 2,
                                                  ));
                            return Opacity(
                              opacity: o.clamp(.25, 1.0),
                              child: child,
                            );
                          },
                          child: Text(
                            'TAP TO CONTINUE',
                            style: refText(
                              family: Ref.fm,
                              size: 12,
                              wght: 500,
                              ls: 4,
                              height: 1.4,
                              color: Ref.dim,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// .lu-n .arr 的三角（L456 的箭头按 40px 字号渲染约 26×32 的实心三角）
class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final Path p = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, s.height / 2)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.color != color;
}

/// #lvup .rays（L452）：
/// repeating-conic-gradient(acid .13 0 6deg, transparent 6deg 18deg)
/// + mask:radial-gradient(circle,#000 10%,transparent 55%)，30s linear。
///
/// 「径向遮罩」等价于「把楔形 alpha 乘上一条径向渐变」，所以直接把
/// RadialGradient 当楔形的画笔，省掉一层 saveLayer。
class _RaysPainter extends CustomPainter {
  const _RaysPainter({required this.turns});

  final double turns;

  @override
  void paint(Canvas canvas, Size s) {
    final Offset c = Offset(s.width / 2, s.height * .45); // top:45%（L452）
    // mask 的 radial 默认 farthest-corner：1400×1400 的盒 → 半径取对角
    final double far =
        math.sqrt(s.width * s.width + s.height * s.height) / 2 + 8;
    final Rect rect = Rect.fromCircle(center: c, radius: far);
    const double seg = 6; // 0~6deg 实
    const double gap = 12; // 6~18deg 空
    final double top = (turns * 360) % 360;

    final Paint p = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          Ref.a(Ref.acid, .13),
          Ref.a(Ref.acid, .13), // #000 10% 之前不衰减
          Ref.a(Ref.acid, 0), // 55% 处归零
        ],
        stops: const <double>[0, .1, .55],
      ).createShader(rect);

    for (double a = 0; a < 360; a += seg + gap) {
      final Path wedge = Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(rect, (a + top) * math.pi / 180, seg * math.pi / 180, false)
        ..close();
      canvas.drawPath(wedge, p);
    }
  }

  @override
  bool shouldRepaint(_RaysPainter old) => old.turns != turns;
}

/// ═══════════════════════════════════════════════════════════════
///  RefFail —— 失败幕
///
///  · .gl-t 900 46px/1.1 字距 6 白字，两层复制体（hot / cyan）各偏 ±3px、
///    分别取上下半，steps(2) 抖动 1.2s / 0.9s（L463-468）
///  · .fail-sub 700 12px mono 字距 6 hot（L469）
///  · .fail-box 由调用方给（本组件只保证 320 宽与 28 的间距，样式见 L470）
///  · 底部 ghost 按钮占满 320（L474）
/// ═══════════════════════════════════════════════════════════════
class RefFail extends StatefulWidget {
  const RefFail({
    super.key,
    required this.title,
    required this.sub,
    required this.box,
    required this.onBack,
    this.visible = true,
  });

  /// .gl-t 的正文（CSS 用 data-t 复制同一段文字做错位）
  final String title;

  /// .fail-sub：如 MISSION FAILED
  final String sub;

  /// .fail-box 的内容 —— 调用方自带 r16 / rgba(255,255,255,.04) /
  /// 1px rgba(255,59,122,.3) 的盒子（L470）
  final Widget box;

  /// 「回到大厅」（JS L1558 的 failOk）
  final VoidCallback onBack;

  final bool visible;

  @override
  State<RefFail> createState() => _RefFailState();
}

class _RefFailState extends State<RefFail> with TickerProviderStateMixin {
  /// .gl-t::before{animation:gl1 1.2s steps(2) infinite}（L465）
  late final AnimationController _g1 = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  /// .gl-t::after{animation:gl2 .9s steps(2) infinite}（L466）
  late final AnimationController _g2 = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// JS L1556-1557：标题 500ms / 盒子 500ms 延迟 300
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(covariant RefFail old) {
    super.didUpdateWidget(old);
    if (old.visible != widget.visible) _sync();
  }

  void _sync() {
    if (!widget.visible) {
      _g1.stop();
      _g2.stop();
      _enter.stop();
      return;
    }
    if (_reduce) {
      _enter.value = 1;
      _g1.stop();
      _g2.stop();
      return;
    }
    _enter.forward(from: 0);
    if (!_g1.isAnimating) _g1.repeat();
    if (!_g2.isAnimating) _g2.repeat();
  }

  @override
  void dispose() {
    _g1.dispose();
    _g2.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _enter,
      builder: (BuildContext context, Widget? child) {
        final double ms = _enter.value * 800;
        // JS L1556：标题 scale(1.6) blur(10) → 1，500ms cubic-bezier(.2,1.4,.4,1)
        final double tk = Ref.pop.transform((ms / 500).clamp(0.0, 1.0));
        final double tScale = 1.6 + (1 - 1.6) * tk;
        final double tOpa = (ms / 300).clamp(0.0, 1.0);
        final double tBlur = 10 * (1 - tk);
        // JS L1557：盒子 translateY(30)→0，500ms 延迟 300
        final double bk = Curves.easeOut.transform(
          ((ms - 300) / 500).clamp(0.0, 1.0),
        );

        return _OverlayScreen(
          onTap: null,
          // #fail（L462）：radial hot .22 → rgba(4,3,10,.94) 65%
          background: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -.2), // circle at 50% 40%
                radius: 1.05,
                colors: <Color>[Ref.a(Ref.hot, .22), Ref.a(Ref.bg, .94)],
                stops: const <double>[0, .65],
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Opacity(
                opacity: tOpa,
                child: Transform.scale(
                  scale: tScale,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: tBlur / 2,
                      sigmaY: tBlur / 2,
                    ),
                    child: AnimatedBuilder(
                      animation: Listenable.merge(<Listenable>[_g1, _g2]),
                      builder: (BuildContext context, Widget? _) {
                        return _GlitchTitle(
                          text: widget.title,
                          on1: !_reduce && _g1.value >= .5,
                          on2: !_reduce && _g2.value >= .5,
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8), // .fail-sub{margin-top:8}（L469）
              Text(
                widget.sub,
                textAlign: TextAlign.center,
                style: refText(
                  family: Ref.fm,
                  size: 12, // L469 font:700 12px
                  wght: 700,
                  ls: 6, // letter-spacing:6px
                  height: 1.4,
                  color: Ref.hot,
                ),
              ),
              const SizedBox(height: 28), // .fail-box{margin-top:28}（L470）
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Opacity(
                  opacity: bk.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, 30 * (1 - bk)),
                    child: SizedBox(width: double.infinity, child: widget.box),
                  ),
                ),
              ),
              const SizedBox(height: 22), // #fail .btn{margin-top:22}（L474）
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: SizedBox(
                  width: double.infinity,
                  child: RefButton(
                    label: '回到大厅',
                    primary: false, // DOM L832 是 .btn.ghost
                    onTap: widget.onBack,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// .gl-t + 两层错位复制体（L463-468）
class _GlitchTitle extends StatelessWidget {
  const _GlitchTitle({
    required this.text,
    required this.on1,
    required this.on2,
  });

  final String text;

  /// @keyframes gl1 的 50% 帧是否生效（steps(2) 只有两档）
  final bool on1;

  /// @keyframes gl2 的 50% 帧是否生效
  final bool on2;

  static final TextStyle _base = refText(
    size: 46, // L463 font:900 46px/1.1
    wght: 900,
    ls: 6, // letter-spacing:6px
    height: 1.1,
    color: Colors.white,
  );

  @override
  Widget build(BuildContext context) {
    // 0%  ：::before translate(-3px,0) inset(0 0 55% 0)
    //       ::after  translate(3px,0)  inset(55% 0 0 0)
    // 50% ：::before translate(4px,-2px) inset(10% 0 60% 0)
    //       ::after  translate(-4px,2px) inset(60% 0 5% 0)
    final double dx1 = on1 ? 4 : -3;
    final double dy1 = on1 ? -2 : 0;
    final double dx2 = on2 ? -4 : 3;
    final double dy2 = on2 ? 2 : 0;
    final double t1 = on1 ? 10 : 0;
    final double b1 = on1 ? 60 : 55;
    final double t2 = on2 ? 60 : 55;
    final double b2 = on2 ? 5 : 0;

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Text(text, style: _base, textAlign: TextAlign.center),
        Positioned.fill(
          child: Transform.translate(
            offset: Offset(dx1, dy1),
            child: _InsetClip(
              topPct: t1,
              bottomPct: b1,
              child: Text(
                text,
                style: _base.copyWith(color: Ref.hot),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Transform.translate(
            offset: Offset(dx2, dy2),
            child: _InsetClip(
              topPct: t2,
              bottomPct: b2,
              child: Text(
                text,
                style: _base.copyWith(color: Ref.cyan),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// clip-path:inset(t r b l) 的等价物（只用到上下百分比）
class _InsetClip extends StatelessWidget {
  const _InsetClip({
    required this.topPct,
    required this.bottomPct,
    required this.child,
  });

  final double topPct;
  final double bottomPct;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      clipper: _InsetClipper(topPct: topPct, bottomPct: bottomPct),
      child: child,
    );
  }
}

class _InsetClipper extends CustomClipper<Rect> {
  const _InsetClipper({required this.topPct, required this.bottomPct});

  final double topPct;
  final double bottomPct;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    0,
    size.height * topPct / 100,
    size.width,
    size.height - size.height * bottomPct / 100,
  );

  @override
  bool shouldReclip(_InsetClipper old) =>
      old.topPct != topPct || old.bottomPct != bottomPct;
}

/// ═══════════════════════════════════════════════════════════════
///  RefModal —— 确认弹窗
///
///  · 幕：rgba(4,3,10,.84) + blur 12（L406），260ms 淡入（JS L1123）
///  · 卡：340 / padding 24 22 20 / r22 /
///        linear-gradient(160deg,#1f1a36,#0e0c19) /
///        1px rgba(255,255,255,.12) / 0 30px 80px rgba(0,0,0,.7)（L476）
///  · h3 900 21px（L477）/ p 400 14px/1.7 dim（L478）
///  · 两颗按钮各 flex 1 / 高 52 / 字号 15（L480）
///  · 进场：opacity 260ms + scale(.8) translateY(30) → none，
///    420ms cubic-bezier(.2,1.4,.4,1)（JS L1141）
///
///  ⚠️ 已知偏差：L480 要「高 52 / 字号 15」，而 RefButton 只有 62(默认) /
///  56(small) 两档且 ref_kit.dart 不许改 —— 这里固定 52 高，按 .btn 的同一套
///  斜切双层描边（L71-80）自绘一枚，字重/字距/主次配色与 RefButton 一致。
/// ═══════════════════════════════════════════════════════════════
class RefModal extends StatefulWidget {
  const RefModal({
    super.key,
    required this.title,
    required this.body,
    required this.yes,
    required this.no,
    required this.onPick,
    this.visible = true,
  });

  final String title;
  final String body;
  final String yes;
  final String no;

  /// true = 主键（右侧）／false = 次键（左侧）
  final ValueChanged<bool> onPick;

  final bool visible;

  @override
  State<RefModal> createState() => _RefModalState();
}

class _RefModalState extends State<RefModal>
    with SingleTickerProviderStateMixin {
  /// JS L1141：scale(.8) translateY(30px) + opacity 0 → none，
  /// 420ms cubic-bezier(.2,1.4,.4,1)
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.visible) _play();
  }

  @override
  void didUpdateWidget(covariant RefModal old) {
    super.didUpdateWidget(old);
    if (old.visible != widget.visible && widget.visible) _play();
  }

  void _play() {
    if (_reduce) {
      _in.value = 1;
    } else {
      _in.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _in,
      builder: (BuildContext context, Widget? child) {
        final double t = _in.value;
        final double k = Ref.pop.transform(t);
        // 幕 260ms（JS L1123）/ 卡 420ms：幕的不透明度先跑满
        final double scrim = (t * 420 / 260).clamp(0.0, 1.0);
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: Opacity(
                opacity: scrim,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: const ColoredBox(
                      color: Color(0xD604030A), // rgba(4,3,10,.84)
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {}, // 幕吃掉手势，不穿透
                child: Padding(
                  // .ovl{padding:30px 26px}（L406）
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 30,
                  ),
                  child: Center(
                    child: Opacity(
                      opacity: scrim,
                      child: Transform.translate(
                        offset: Offset(0, 30 * (1 - k)), // translateY(30)
                        child: Transform.scale(
                          scale: .8 + .2 * k, // scale(.8) → 1
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: _buildCard(),
    );
  }

  Widget _buildCard() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _kModalW),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20), // 24 22 20（L476）
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22), // r22（L476）
          // linear-gradient(160deg,#1f1a36,#0e0c19)（L476）
          gradient: const LinearGradient(
            begin: Alignment(-.94, -.34), // 160deg
            end: Alignment(.94, .34),
            colors: <Color>[Color(0xFF1F1A36), Color(0xFF0E0C19)],
          ),
          border: Border.all(color: const Color(0x1FFFFFFF)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0xB3000000), // rgba(0,0,0,.7)
              offset: Offset(0, 30),
              blurRadius: 80,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: refText(
                size: 21, // .modal h3{font:900 21px}（L477）
                wght: 900,
                height: 1.3,
                color: Ref.txt,
              ),
            ),
            const SizedBox(height: 10), // margin-top:10（L478）
            Text(
              widget.body,
              textAlign: TextAlign.center,
              style: refText(
                size: 14, // .modal p{font:400 14px/1.7;color:dim}（L478）
                wght: 400,
                height: 1.7,
                color: Ref.dim,
              ),
            ),
            const SizedBox(height: 22), // margin-top:22（L479）
            // .mb{display:flex;gap:10}，两颗各 flex:1、高 52（L480）
            SizedBox(
              height: _kModalBtnH,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _ModalButton(
                      label: widget.no,
                      primary: false,
                      onTap: () => widget.onPick(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ModalButton(
                      label: widget.yes,
                      primary: true,
                      onTap: () => widget.onPick(true),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 弹窗按钮（L480）：高 52 / 字号 15 / 斜切 11，
/// 复用 ref_kit 的 cutCornerPath 与 .btn 的双层描边（L72-80）
class _ModalButton extends StatefulWidget {
  const _ModalButton({
    required this.label,
    required this.primary,
    required this.onTap,
  });

  final String label;
  final bool primary;
  final VoidCallback onTap;

  @override
  State<_ModalButton> createState() => _ModalButtonState();
}

class _ModalButtonState extends State<_ModalButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          // .btn:active{transform:translateY(3px) scale(.965)}（L82）
          scale: _down ? .965 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Ref.ease,
          child: CustomPaint(
            painter: _ModalBtnPainter(primary: widget.primary),
            child: Center(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: refText(
                  size: 15, // L480 font-size:15px
                  wght: 900,
                  ls: 2, // .btn{letter-spacing:2px}（L71）
                  height: 1,
                  color: widget.primary ? Ref.onAccent : Ref.txt,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModalBtnPainter extends CustomPainter {
  const _ModalBtnPainter({required this.primary});

  final bool primary;

  @override
  void paint(Canvas canvas, Size s) {
    final Rect r = Offset.zero & s;
    const double cut = 11; // 52 高按 62→13 的比例取 11
    if (primary) {
      // .btn.pri{filter:drop-shadow(0 0 16px 55%)}（L78）
      canvas.drawPath(
        cutCornerPath(r.deflate(1), cut),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Ref.a(Ref.acid, .55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
    }
    // ::before 外层铺满（L73）
    canvas.drawPath(
      cutCornerPath(r, cut),
      Paint()..color = primary ? Ref.acid : const Color(0x38FFFFFF),
    );
    // ::after 内层 inset 1.5（L74），ghost 的内底是 #110e20（L80）
    canvas.drawPath(
      cutCornerPath(r.deflate(1.5), cut - 1.5),
      Paint()..color = primary ? Ref.acid : const Color(0xFF110E20),
    );
  }

  @override
  bool shouldRepaint(_ModalBtnPainter old) => old.primary != primary;
}

/// ═══════════════════════════════════════════════════════════════
///  .ovl 的公共壳（L406）：铺满 / 居中 / padding 30 26 / 可选 onTap
/// ═══════════════════════════════════════════════════════════════
class _OverlayScreen extends StatelessWidget {
  const _OverlayScreen({
    required this.background,
    required this.child,
    required this.onTap,
  });

  final Widget background;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(child: background),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(
              // .ovl{padding:30px 26px}（L406）
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 30),
              child: Center(child: SingleChildScrollView(child: child)),
            ),
          ),
        ),
      ],
    );
  }
}
