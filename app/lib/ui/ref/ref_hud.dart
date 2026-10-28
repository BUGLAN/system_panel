import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/titles.dart';
import '../../design/ref.dart';
import '../../state/host_state.dart';
import 'ref_kit.dart';

/// ═══════════════════════════════════════════════════════════
///  HUD —— 参考稿 #hud（CSS L89-110，DOM L685-694）
///
///  ⚠️ **本组件顶层是 Positioned**（top/left/right 全 0），
///     必须直接放在 Stack 里（该 Stack 需给出宽度约束）。
///
///  · #hud    L90  absolute / top:0 / left:0 / right:0 / z-index:40 /
///                display:flex / align-items:center / gap:10 /
///                padding:calc(safe + 20px) 18px 0，**没有固定盒高**
///  · #hud.hide L91 translateY(-130%) + opacity:0 + pointer-events:none，
///                transition transform .55s var(--snap) / opacity .4s
/// ═══════════════════════════════════════════════════════════
class RefHud extends StatefulWidget {
  const RefHud({
    super.key,
    required this.state,
    this.visible = true,
    this.coinBump = 0,
    this.coinKey,
    this.streakBump = 0,
    this.onMenu,
    this.onLevelTap,
    this.onCoinTap,
    this.onStreakTap,
    this.onMenuLongPress,
  });

  final HostState state;

  /// false = .hide（收起，把舞台让给主线 / 档案这类 nohud 场景）
  final bool visible;

  /// 每 +1 播一次 bump（晶核 / 连胜）
  final int coinBump;

  /// 晶核 chip 的定位键（coinFly 的落点）
  final Key? coinKey;
  final int streakBump;

  final VoidCallback? onMenu;

  /// 长按菜单键 = 直达 LLM 设置（参考稿没有这一层，是补全组件的入口）
  final VoidCallback? onMenuLongPress;

  final VoidCallback? onLevelTap;
  final VoidCallback? onCoinTap;
  final VoidCallback? onStreakTap;

  @override
  State<RefHud> createState() => _RefHudState();
}

class _RefHudState extends State<RefHud> with SingleTickerProviderStateMixin {
  /// L90 transition:transform .55s var(--snap), opacity .4s
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
    value: widget.visible ? 1 : 0,
  );

  late final CurvedAnimation _slide = CurvedAnimation(
    parent: _c,
    curve: Ref.snap,
  );

  /// opacity .4s —— 占总时长 400/550
  late final CurvedAnimation _fade = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, 400 / 550, curve: Ref.ease),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _c.stop();
      _c.value = widget.visible ? 1 : 0;
    }
  }

  /// 数值一变就 bump 一次（参考稿 bump($('#hudCoin')) / bump($('#hudStreak'))）
  int _coinTick = 0;
  int _streakTick = 0;

  @override
  void didUpdateWidget(RefHud old) {
    super.didUpdateWidget(old);
    if (old.state.coins != widget.state.coins) _coinTick++;
    if (old.state.streak != widget.state.streak) _streakTick++;
    if (old.visible == widget.visible) return;
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _c.value = widget.visible ? 1 : 0;
      return;
    }
    if (widget.visible) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    _fade.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double safeTop = MediaQuery.paddingOf(context).top;
    final HostState s = widget.state;
    final String title = '「${HostTitle.nameOf(s.title)}」';

    final Widget row = Padding(
      // L90 padding:calc(env(safe-area-inset-top) + 20px) 18px 0
      padding: EdgeInsets.only(top: safeTop + 20, left: 18, right: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center, // L90 align-items:center
        children: <Widget>[
          _LevelDial(
            lv: s.lv,
            ratio: s.expRatio,
            onTap: widget.onLevelTap,
            semantic: 'LV${s.lv}，经验 ${s.exp} / ${HostState.need(s.lv)}',
          ),
          const SizedBox(width: 10), // L90 gap:10
          // .who（L98-100）
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: refText(
                    family: Ref.fc,
                    size: 17, // L99 font:900 17px
                    wght: 900,
                    height: 1.25, // L98 line-height:1.25
                    color: Ref.txt,
                  ),
                ),
                Text(
                  title,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis, // L100 text-overflow:ellipsis
                  style: refText(
                    family: Ref.fc,
                    size: 12, // L100 font:500 12px
                    wght: 500,
                    height: 1.25,
                    color: Ref.acid,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // .chip.streak（L104-105）：文字 #ffb35c、火焰实心 #ff8a3d + 4px 辉光
          _Tap(
            onTap: widget.onStreakTap,
            label: '连胜 ${s.streak} 天',
            child: RefChip(
              value: '${s.streak}',
              bump: widget.streakBump + _streakTick,
              valueColor: const Color(0xFFFFB35C),
              icon: const CustomPaint(
                size: Size(17, 17), // L102 .chip svg{width:17px}
                painter: _FlameIcon(
                  fill: Color(0xFFFF8A3D), // L105 fill:#ff8a3d
                  glow: Color(0xFFFF6A00), // L105 drop-shadow(0 0 4px #ff6a00)
                  glowBlur: 4,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // .chip.coin（L103）：17px 青色描边六边 + 数字 16 Chakra
          _Tap(
            key: widget.coinKey,
            onTap: widget.onCoinTap,
            label: '晶核 ${s.coins}',
            // roll(coinN, from, to, 900)：1 − (1−k)³ 滚数
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: s.coins.toDouble()),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (BuildContext _, double v, Widget? icon) => RefChip(
                value: '${v.round()}',
                bump: widget.coinBump + _coinTick,
                icon: icon!,
              ),
              child: const CustomPaint(
                size: Size(17, 17),
                painter: _HexIcon(color: Ref.cyan, stroke: 2.2),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // .iconbtn（L108-110）：42x42 / r14 / 三根横杠 20px stroke 2.2
          GestureDetector(
            onLongPress: widget.onMenuLongPress,
            child: RefIconButton(
              onTap: widget.onMenu,
              semanticLabel: '菜单（长按 = LLM 设置）',
              icon: const CustomPaint(
                size: Size(20, 20), // L110 width:20px
                painter: _BarsIcon(color: Ref.txt),
              ),
            ),
          ),
        ],
      ),
    );

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: _slide,
        builder: (BuildContext context, Widget? child) {
          final double t = _slide.value;
          return IgnorePointer(
            ignoring: t < .999, // L91 pointer-events:none
            child: Opacity(
              opacity: _fade.value,
              child: FractionalTranslation(
                // L91 transform:translateY(-130%)
                translation: Offset(0, -1.3 * (1 - t)),
                child: child,
              ),
            ),
          );
        },
        child: row,
      ),
    );
  }
}

/// 让 .chip 可点（参考稿三枚 chip 都挂了 info 提示）
class _Tap extends StatelessWidget {
  const _Tap({super.key, required this.child, this.onTap, this.label});
  final Widget child;
  final VoidCallback? onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          refPressSound('ui.tap');
          onTap!();
        },
        child: child,
      ),
    );
  }
}

/// .lv（L92-97）：58x58 圆 / 径向底 acid 10%→透明 70%；
/// SVG 环 r=26 stroke 4，轨道白 9%，进度 acid + 5px 辉光，
/// stroke-dashoffset 1.1s var(--ease)；中间 LV(8px 字距 2) + 数字 24px。
class _LevelDial extends StatefulWidget {
  const _LevelDial({
    required this.lv,
    required this.ratio,
    this.onTap,
    this.semantic,
  });

  final int lv;
  final double ratio;
  final VoidCallback? onTap;
  final String? semantic;

  @override
  State<_LevelDial> createState() => _LevelDialState();
}

class _LevelDialState extends State<_LevelDial>
    with SingleTickerProviderStateMixin {
  /// L95 transition:stroke-dashoffset 1.1s var(--ease)
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    value: 1,
  );

  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _c,
    curve: Ref.ease,
  );

  late double _from = widget.ratio;
  late double _to = widget.ratio;

  @override
  void didUpdateWidget(_LevelDial old) {
    super.didUpdateWidget(old);
    if (old.ratio == widget.ratio) return;
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final double current = _from + (_to - _from) * _curve.value;
    _from = current;
    _to = widget.ratio;
    if (reduce) {
      _c.value = 1;
    } else {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: widget.onTap != null,
      label: widget.semantic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          width: 58, // L92 width:58px
          height: 58,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _curve,
                  builder: (BuildContext context, Widget? child) {
                    final double v = _from + (_to - _from) * _curve.value;
                    return CustomPaint(painter: _LevelPainter(ratio: v));
                  },
                ),
              ),
              // .n 数字（L96）：700 24px/1 Chakra + padding-top 10
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Center(
                    child: Text(
                      '${widget.lv}',
                      style: refText(
                        family: Ref.fd,
                        size: 24,
                        wght: 700,
                        height: 1,
                        color: Ref.txt,
                      ),
                    ),
                  ),
                ),
              ),
              // .n::before 的 LV（L97）：700 8px fm / 字距 2 / dim / top 12
              const Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    'LV',
                    style: TextStyle(
                      fontFamily: Ref.fm,
                      fontSize: 8,
                      height: 1,
                      letterSpacing: 2,
                      color: Ref.dim,
                      fontVariations: <FontVariation>[
                        FontVariation('wght', 700),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 环：viewBox 60 里的 r=26 / stroke 4 等比缩到 58 盒。
/// L687 stroke-dasharray="163.4" = 2πr；dashoffset = 163.4 × (1 - ratio)。
class _LevelPainter extends CustomPainter {
  const _LevelPainter({required this.ratio});
  final double ratio;

  @override
  void paint(Canvas canvas, Size s) {
    final Offset c = Offset(s.width / 2, s.height / 2);
    final double r = 26 * (s.width / 60); // L92 r=26（viewBox 60）
    final double sw = 4 * (s.width / 60); // L92 stroke-width 4

    // L92 background:radial-gradient(circle,rgba(214,255,61,.10),transparent 70%)
    final Rect disk = Rect.fromCircle(center: c, radius: s.width / 2);
    canvas.drawCircle(
      c,
      s.width / 2,
      Paint()
        ..shader = const RadialGradient(
          colors: <Color>[Color(0x1AD6FF3D), Color(0x00D6FF3D)],
          stops: <double>[0, .70],
        ).createShader(disk),
    );

    // L94 .trk{stroke:rgba(255,255,255,.09)}
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..color = const Color(0x17FFFFFF),
    );

    // L95 .bar{stroke:var(--acid);stroke-linecap:round;filter:drop-shadow(0 0 5px)}
    final double sweep = 2 * math.pi * ratio.clamp(0.0, 1.0);
    if (sweep > 0) {
      final Rect arc = Rect.fromCircle(center: c, radius: r);
      canvas.drawArc(
        arc,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw
          ..strokeCap = StrokeCap.round
          ..color = Ref.acid
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawArc(
        arc,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw
          ..strokeCap = StrokeCap.round
          ..color = Ref.acid,
      );
    }
  }

  @override
  bool shouldRepaint(_LevelPainter o) => o.ratio != ratio;
}

/// .chip.streak svg（DOM L691）：24 单位火焰路径，实心 + drop-shadow
class _FlameIcon extends CustomPainter {
  const _FlameIcon({required this.fill, required this.glow, this.glowBlur = 4});

  final Color fill;
  final Color glow;
  final double glowBlur;

  static final Path _path = Path()
    ..moveTo(12, 2)
    ..cubicTo(13, 6, 17.5, 8, 17.5, 13.5)
    ..cubicTo(17.5, 16.5, 15, 19, 12, 19)
    ..cubicTo(9, 19, 6.5, 16.5, 6.5, 13.5)
    ..cubicTo(6.5, 11.2, 7.5, 9.5, 8.7, 8.5)
    ..cubicTo(8.7, 10.7, 9.7, 11.8, 10.9, 11.8)
    ..cubicTo(10.9, 8.5, 10, 5.5, 12, 2)
    ..close();

  @override
  void paint(Canvas canvas, Size s) {
    canvas.save();
    canvas.scale(s.width / 24, s.height / 24);
    canvas.drawPath(
      _path,
      Paint()
        ..color = glow
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowBlur),
    );
    canvas.drawPath(_path, Paint()..color = fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FlameIcon o) =>
      o.fill != fill || o.glow != glow || o.glowBlur != glowBlur;
}

/// .chip.coin svg（DOM L692）：六边晶核，fill:none / stroke 2.2
class _HexIcon extends CustomPainter {
  const _HexIcon({required this.color, required this.stroke});
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size s) {
    canvas.save();
    canvas.scale(s.width / 24, s.height / 24);
    final Path p = Path()
      ..moveTo(12, 2.5)
      ..lineTo(20.2, 7.25)
      ..lineTo(20.2, 16.75)
      ..lineTo(12, 21.5)
      ..lineTo(3.8, 16.75)
      ..lineTo(3.8, 7.25)
      ..close();
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HexIcon o) => o.color != color || o.stroke != stroke;
}

/// .iconbtn svg（DOM L693）：M4 6h16 / M8 12h12 / M4 18h16
/// → 三根不等长横杠（16 / 12 / 15 单位），stroke 2.2、linecap round
class _BarsIcon extends CustomPainter {
  const _BarsIcon({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    canvas.save();
    canvas.scale(s.width / 20, s.height / 20); // 设计单位 20
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth =
          2.2 // L110 stroke-width:2.2
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawLine(const Offset(2, 5.4), const Offset(18, 5.4), p); // 16 长
    canvas.drawLine(const Offset(5.4, 10), const Offset(17.4, 10), p); // 12 长
    canvas.drawLine(const Offset(3.2, 14.6), const Offset(18.2, 14.6), p); // 15
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BarsIcon o) => o.color != color;
}
