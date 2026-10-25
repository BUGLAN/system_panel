import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/fidelity.dart';
import '../design/tokens.dart';
import '../state/haptics.dart';
import '../state/sfx.dart';
import 'rail_base.dart' show railReduceMotion;

/// 游戏按键（docs/48 §4「CTA 是一颗有厚度的实体键」）。
///
/// 原来的主 CTA 是一块**平的青色色块**：没有厚度、没有受光面、按下只缩 4%。
/// 宿主截图里它是全屏最亮、却最「便宜」的东西。这颗按键的结构：
///
/// ```
///   ┌╱──────────────────────────╲┐  ← 受光棱（1px 白）
///   │  面：竖向渐变 + 斜切两角     │  ← 按下时整面下沉 [kKeyTravel]
///   │            去执行      ›››  │
///   └╲──────────────────────────╱┘
///    ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀  ← 底座（深一档的同形，露出 3px = 厚度）
/// ```
///
/// - **按下**：面下沉到底座（0ms，跟手）+ 轻震；**不出声**（docs/48 §5：
///   声音只给「已发生」的事，按下还没发生）。
/// - **抬起**：[Ease.pop] 带一点过冲弹回 —— 「键帽」的弹性。
/// - **扫光**：挂载时、文案变化时各扫一次（一次性，不循环：常驻循环既费电，
///   也会让 `pumpAndSettle` 永远等不到安定）。
/// - 省电档：不画外辉（MaskFilter）与扫光；减弱动态：不下沉，只压暗。
///
/// 几何不变：高度 = [height]（主线页 56），宽度由调用方约束 / 内容决定，
/// 所以 M-21 的「ghost 位置逐像素不动」照旧成立。
class GameButton extends StatefulWidget {
  const GameButton({
    super.key,
    required this.label,
    this.onTap,
    this.primary = true,
    this.height = 56,
    this.padding = const EdgeInsets.symmetric(horizontal: 19),
    this.cue = 'ui.tap',
    this.accent = C.blue,
    this.chevrons = true,
  });

  final String label;
  final VoidCallback? onTap;

  /// 主键（实色发光）/ 次键（暗玻璃 + 描边）
  final bool primary;
  final double height;
  final EdgeInsets padding;

  /// 点按落定后的音效（[SoundRule.cues] 的键）；null = 调用方自己出声
  final String? cue;
  final Color accent;

  /// 主键右侧的「›››」方向符
  final bool chevrons;

  @override
  State<GameButton> createState() => _GameButtonState();
}

/// 键程：面下沉的像素（= 底座露出的厚度）
const double kKeyTravel = 3;

class _GameButtonState extends State<GameButton> with TickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    lowerBound: -.3, // Ease.pop 的过冲会把值带到 0 以下（面弹得比原位略高）
    upperBound: 1,
    value: 0,
  );
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _sheenArmed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_sheenArmed) {
      _sheenArmed = true;
      _maybeSheen();
    }
  }

  @override
  void didUpdateWidget(GameButton old) {
    super.didUpdateWidget(old);
    if (old.label != widget.label) _maybeSheen();
  }

  void _maybeSheen() {
    if (!widget.primary || widget.onTap == null) return;
    if (railReduceMotion(context) || !Fidelity.rich(context)) return;
    _sheen.forward(from: 0);
  }

  @override
  void dispose() {
    _press.dispose();
    _sheen.dispose();
    super.dispose();
  }

  void _down() {
    _press.value = 1; // 0ms：手指要立刻有回应
    Haptics.buzz('tap');
  }

  void _up() {
    _press.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: _PopBack(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null;
    final bool reduce = railReduceMotion(context);
    final bool rich = Fidelity.rich(context);
    final Color ink = widget.primary
        ? (enabled ? C.deep : Pal.text3)
        : (enabled ? C.ice : Pal.text4);
    final Widget label = AnimatedSwitcher(
      // 状态切换 160ms（M-20）
      duration: const Duration(milliseconds: 160),
      child: Text(
        widget.label,
        key: ValueKey<String>(widget.label),
        maxLines: 1,
        style: fs(
          family: F.cn,
          size: 15,
          wght: 700,
          ls: widget.primary ? 2.2 : 1.2,
          height: 1,
          color: ink,
        ),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _down() : null,
      onTapUp: enabled ? (_) => _up() : null,
      onTapCancel: enabled ? _up : null,
      onTap: enabled
          ? () {
              if (widget.cue != null) Sfx.cue(widget.cue!);
              widget.onTap!();
            }
          : null,
      child: SizedBox(
        height: widget.height,
        child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[_press, _sheen]),
          builder: (BuildContext context, Widget? child) {
            final double p = _press.value;
            final double travel = reduce ? 0 : p.clamp(0.0, 1.0) * kKeyTravel;
            return CustomPaint(
              painter: _KeyPainter(
                primary: widget.primary,
                enabled: enabled,
                accent: widget.accent,
                press: reduce ? 0 : p,
                sheen:
                    (_sheen.isAnimating ||
                        (_sheen.value > 0 && _sheen.value < 1))
                    ? _sheen.value
                    : -1,
                glow: rich,
                chevrons: widget.primary && widget.chevrons && enabled,
                dim: reduce && p > .5,
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  top: travel,
                  bottom: kKeyTravel - travel,
                ),
                child: child,
              ),
            );
          },
          child: Padding(
            padding: widget.padding,
            child: Center(child: label),
          ),
        ),
      ),
    );
  }
}

/// 抬起的回弹：从 1 回到 0，带一次轻过冲（等价于 Ease.pop 反向）
class _PopBack extends Curve {
  @override
  double transformInternal(double t) => Ease.pop.transform(t);
}

class _KeyPainter extends CustomPainter {
  const _KeyPainter({
    required this.primary,
    required this.enabled,
    required this.accent,
    required this.press,
    required this.sheen,
    required this.glow,
    required this.chevrons,
    required this.dim,
  });

  final bool primary;
  final bool enabled;
  final Color accent;
  final double press;

  /// 0~1 扫光进度；-1 = 不画
  final double sheen;
  final bool glow;
  final bool chevrons;
  final bool dim;

  static const double cut = 12;

  static Path _shape(Rect r) => Path()
    ..moveTo(r.left + cut, r.top)
    ..lineTo(r.right, r.top)
    ..lineTo(r.right, r.bottom - cut)
    ..lineTo(r.right - cut, r.bottom)
    ..lineTo(r.left, r.bottom)
    ..lineTo(r.left, r.top + cut)
    ..close();

  static Color _a(Color c, double a) =>
      c.withAlpha((a.clamp(0.0, 1.0) * 255).round());

  @override
  void paint(Canvas canvas, Size s) {
    final double travel = press * kKeyTravel;
    final Rect base = Rect.fromLTWH(
      0,
      kKeyTravel,
      s.width,
      s.height - kKeyTravel,
    );
    final Rect face = Rect.fromLTWH(0, travel, s.width, s.height - kKeyTravel);
    final Path facePath = _shape(face);

    // ── 外辉（富效果档）：按下更亮 ──
    if (glow && enabled && primary) {
      canvas.drawPath(
        _shape(base.inflate(1)),
        Paint()
          ..color = _a(accent, .30 + .22 * press)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
    }

    // ── 底座（厚度）──
    canvas.drawPath(
      _shape(base),
      Paint()
        ..color = primary
            ? (enabled
                  ? Color.lerp(accent, Pal.ink0, .62)!
                  : const Color(0xFF0A1424))
            : const Color(0xFF02060F),
    );

    // ── 面 ──
    if (primary && enabled) {
      canvas.drawPath(
        facePath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color.lerp(accent, Colors.white, .42)!,
              accent,
              Color.lerp(accent, const Color(0xFF0B4F8F), .45)!,
            ],
            stops: const <double>[0, .45, 1],
          ).createShader(face),
      );
    } else if (primary) {
      canvas.drawPath(facePath, Paint()..color = Pal.ink2);
    } else {
      canvas.drawPath(
        facePath,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xF0102240), Color(0xF0060F22)],
          ).createShader(face),
      );
    }

    canvas.save();
    canvas.clipPath(facePath);

    // 斜纹刻槽（主键右端）：HUD 的「警示条」语汇，告诉你这是一颗「执行」键
    if (primary && enabled) {
      final Paint groove = Paint()
        ..color = _a(Colors.white, .16)
        ..strokeWidth = 3;
      for (int i = 0; i < 3; i++) {
        final double x = face.right - 24 - i * 8;
        canvas.drawLine(
          Offset(x, face.bottom),
          Offset(x + 14, face.top),
          groove,
        );
      }
    }

    // 扫光：一条斜向白带从左扫到右（一次性）
    if (sheen >= 0 && primary && enabled) {
      final double x =
          -s.width * .3 + s.width * 1.6 * Curves.easeInOut.transform(sheen);
      final double w = s.width * .22;
      canvas.save();
      canvas.translate(x, face.center.dy);
      canvas.rotate(.5);
      final Rect band = Rect.fromCenter(
        center: Offset.zero,
        width: w,
        height: s.height * 3,
      );
      canvas.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            colors: <Color>[
              _a(Colors.white, 0),
              _a(Colors.white, .45 * math.sin(sheen * math.pi)),
              _a(Colors.white, 0),
            ],
          ).createShader(band),
      );
      canvas.restore();
    }

    // 底部内暗：面的下半收暗（受光从上来）
    final Rect lower = Rect.fromLTWH(
      face.left,
      face.center.dy,
      face.width,
      face.height / 2,
    );
    canvas.drawRect(
      lower,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            _a(Colors.black, 0),
            _a(Colors.black, primary ? .12 : .25),
          ],
        ).createShader(lower),
    );
    if (dim) canvas.drawPath(facePath, Paint()..color = _a(Colors.black, .14));
    canvas.restore();

    // 受光棱：顶边 1px（避开左上斜切）
    canvas.drawLine(
      Offset(face.left + cut + 2, face.top + .75),
      Offset(face.right - 4, face.top + .75),
      Paint()
        ..strokeWidth = 1.2
        ..color = primary
            ? _a(Colors.white, enabled ? .75 : .12)
            : _a(accent, enabled ? .55 : .15),
    );

    // 次键描边：左上亮 → 右下暗的渐变边
    if (!primary) {
      canvas.drawPath(
        _shape(face.deflate(.5)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              _a(accent, enabled ? .65 : .18),
              _a(accent, enabled ? .14 : .06),
            ],
          ).createShader(face),
      );
    }

    // ››› 方向符
    if (chevrons) {
      final Paint cv = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final double cy = face.center.dy;
      for (int i = 0; i < 3; i++) {
        final double x = face.right - 66 + i * 7.0;
        cv.color = _a(C.deep, .28 + .2 * i);
        canvas.drawPath(
          Path()
            ..moveTo(x, cy - 5)
            ..lineTo(x + 4.5, cy)
            ..lineTo(x, cy + 5),
          cv,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_KeyPainter o) =>
      o.primary != primary ||
      o.enabled != enabled ||
      o.accent != accent ||
      o.press != press ||
      o.sheen != sheen ||
      o.glow != glow ||
      o.chevrons != chevrons ||
      o.dim != dim;
}
