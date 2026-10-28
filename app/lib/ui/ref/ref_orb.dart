import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/fidelity.dart';
import '../../design/ref.dart';
import '../../widgets/frame_throttle.dart';

/// .task-orb（L174-186）—— 大厅右下那颗会呼吸的酸绿委托球。
///
///  128×128；::before inset 12 = 104 的实球（radial #fbffd8 → acid 35%
///  → #7fae00 + 0 0 40px rgba(214,255,61,.55)）；
///  .rings 是 2px dashed 45% 18s 顺转；.pulse 是 2s 的扩散环。
class RefTaskOrb extends StatefulWidget {
  const RefTaskOrb({
    super.key,
    required this.label,
    this.badge,
    this.small = '',
    this.onTap,
    this.size = 128,
  });

  final String label;

  /// 右上白徽标的数字（0 或 null 不显示）
  final int? badge;
  final String small;
  final VoidCallback? onTap;
  final double size;

  @override
  State<RefTaskOrb> createState() => _RefTaskOrbState();
}

class _RefTaskOrbState extends State<RefTaskOrb> with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  /// 18s 环 + 2s 扩散环，30fps 提交看不出差异；60fps 会让委托球
  /// 每帧重建两层 AnimatedBuilder（含大半径 boxShadow）。
  late final FrameThrottle _paintTick = FrameThrottle(33);

  bool _down = false;
  bool _reduce = false;

  @override
  void initState() {
    super.initState();
    _spin.addListener(_paintTick.pulse);
    _pulse.addListener(_paintTick.pulse);
    Fidelity.lowPower.addListener(_onFidelityChanged);
  }

  void _onFidelityChanged() {
    if (mounted) _syncMotion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncMotion();
  }

  void _syncMotion() {
    if (_reduce || Fidelity.lowPower.value) {
      _spin.stop();
      _pulse.stop();
      return;
    }
    if (!_spin.isAnimating) _spin.repeat();
    if (!_pulse.isAnimating) _pulse.repeat();
  }

  @override
  void dispose() {
    Fidelity.lowPower.removeListener(_onFidelityChanged);
    _spin.removeListener(_paintTick.pulse);
    _pulse.removeListener(_paintTick.pulse);
    _paintTick.dispose();
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double s = widget.size;
    final bool hasBadge = (widget.badge ?? 0) > 0;
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? .9 : 1,
          duration: const Duration(milliseconds: 180),
          child: SizedBox(
            width: s,
            height: s,
            child: RepaintBoundary(
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  AnimatedBuilder(
                    animation: _paintTick,
                    builder: (BuildContext _, Widget? _) => Transform.rotate(
                      angle: _spin.value * 2 * math.pi,
                      child: CustomPaint(
                        size: Size.square(s),
                        painter: const _OrbRingsPainter(),
                      ),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _paintTick,
                    builder: (BuildContext _, Widget? _) {
                      final double k = _pulse.value;
                      return Opacity(
                        opacity: (1 - k).clamp(0.0, 1.0) * .8,
                        child: Transform.scale(
                          scale: 1 + .5 * k,
                          child: Container(
                            width: s - 24,
                            height: s - 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Ref.acid, width: 2),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  RepaintBoundary(
                    child: Container(
                      width: s - 24,
                      height: s - 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          center: Alignment(-.3, -.44),
                          radius: .78,
                          colors: <Color>[
                            Color(0xFFFBFFD8),
                            Ref.acid,
                            Color(0xFF7FAE00),
                          ],
                          stops: <double>[0, .35, 1],
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Ref.a(Ref.acid, _down ? .8 : .55),
                            blurRadius: _down ? 70 : 40,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              widget.label,
                              style: refText(
                                family: Ref.fc,
                                size: 30,
                                wght: 900,
                                ls: 2,
                                height: 1,
                                color: Ref.onAccent,
                              ),
                            ),
                            if (widget.small.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 4),
                              Text(
                                widget.small,
                                style: refText(
                                  family: Ref.fm,
                                  size: 10,
                                  wght: 700,
                                  ls: 4,
                                  height: 1,
                                  color: Ref.onAccent.withAlpha(191),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (hasBadge)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Ref.bg,
                              spreadRadius: 4,
                              blurRadius: 0,
                            ),
                            BoxShadow(
                              color: Colors.white.withAlpha(128),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            '${widget.badge}',
                            style: refText(
                              family: Ref.fd,
                              size: 17,
                              wght: 700,
                              height: 1,
                              color: Ref.onAccent,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbRingsPainter extends CustomPainter {
  const _OrbRingsPainter();

  @override
  void paint(Canvas canvas, Size s) {
    if (s.isEmpty) return;
    final Offset c = s.center(Offset.zero);
    final double r = s.width / 2 - 1;
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Ref.a(Ref.acid, .45);
    const double dash = 8;
    const double gap = 8;
    final double step = (dash + gap) / r;
    for (double a = 0; a < 2 * math.pi; a += step) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        a,
        dash / r,
        false,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// .gbadge（L267）：34 圆 / 2px 档位色边 / 12px 外辉 / 700 italic 18px
class RefRankBadge extends StatelessWidget {
  const RefRankBadge({
    super.key,
    required this.rank,
    this.size = 34,
    this.color,
  });

  final String rank;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color c = color ?? Ref.rankOf(rank);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c, width: 2),
        boxShadow: <BoxShadow>[BoxShadow(color: c, blurRadius: 12)],
      ),
      child: Text(
        rank,
        style: refText(
          family: Ref.fd,
          size: size * .52,
          wght: 700,
          italic: true,
          height: 1,
          color: c,
        ),
      ),
    );
  }
}

/// .gc-top .cat（L198）：30×30、1.5px 边、rotate(45deg)、r6，内部字反旋
class RefCatMark extends StatelessWidget {
  const RefCatMark({
    super.key,
    required this.glyph,
    this.color,
    this.size = 30,
  });

  final String glyph;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color c = color ?? Ref.cyan;
    return Transform.rotate(
      angle: math.pi / 4,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: c, width: 1.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Transform.rotate(
          angle: -math.pi / 4,
          child: Text(
            glyph,
            style: refText(
              family: Ref.fc,
              size: size * .5,
              wght: 900,
              height: 1,
              color: c,
            ),
          ),
        ),
      ),
    );
  }
}

/// .pips i（L151-154）：斜切 8 高的小格（已完成 cyan+辉光 / 当前 acid 闪）
class RefPips extends StatelessWidget {
  const RefPips({
    super.key,
    required this.total,
    required this.done,
    this.accent,
    this.height = 8,
    this.gap = 4,
  });

  final int total;
  final int done;
  final Color? accent;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (total <= 0) return const SizedBox.shrink();
    final Color cy = accent ?? Ref.cyan;
    return Row(
      children: <Widget>[
        for (int i = 0; i < total; i++) ...<Widget>[
          if (i > 0) SizedBox(width: gap),
          Expanded(
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.skewX(-20 * math.pi / 180),
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  color: i < done
                      ? cy
                      : (i == done ? Ref.acid : const Color(0x14FFFFFF)),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: i < done
                      ? <BoxShadow>[BoxShadow(color: cy, blurRadius: 8)]
                      : (i == done
                            ? <BoxShadow>[
                                BoxShadow(color: Ref.acid, blurRadius: 8),
                              ]
                            : null),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// .tri（L86）：8×12 的实心三角
class RefTri extends StatelessWidget {
  const RefTri({super.key, this.color, this.size = 12});

  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * .66,
      height: size,
      child: CustomPaint(painter: _TriPainter(color: color ?? Ref.onAccent)),
    );
  }
}

class _TriPainter extends CustomPainter {
  const _TriPainter({required this.color});
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
  bool shouldRepaint(_TriPainter o) => o.color != color;
}

/// .link（L68-69）：500 13px dim，hover 转 accent
class RefLink extends StatelessWidget {
  const RefLink({super.key, required this.label, this.onTap, this.accent});

  final String label;
  final VoidCallback? onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return _HoverLink(label: label, onTap: onTap, accent: accent ?? Ref.acid);
  }
}

class _HoverLink extends StatefulWidget {
  const _HoverLink({
    required this.label,
    required this.onTap,
    required this.accent,
  });

  final String label;
  final VoidCallback? onTap;
  final Color accent;

  @override
  State<_HoverLink> createState() => _HoverLinkState();
}

class _HoverLinkState extends State<_HoverLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: refText(
            family: Ref.fc,
            size: 13,
            wght: 500,
            height: 1.4,
            color: _hover ? widget.accent : Ref.dim,
          ),
          child: Text(widget.label),
        ),
      ),
    );
  }
}
