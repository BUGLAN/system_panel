import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/ref.dart';

/// ═══════════════════════════════════════════════════════════
///  参考稿组件基座 —— 逐条对齐「宿主养成系统_重设计.html」
///
///  每个组件都标注了 CSS 行号与原始声明，改数值前先回参考稿对一遍。
///  所有尺寸都是 CSS 像素（= Flutter 逻辑像素），不做二次换算。
/// ═══════════════════════════════════════════════════════════

/// 「.btn::before/::after」的斜切多边形（L72）：
/// polygon(cut 0, 100% 0, 100% calc(100% - cut), calc(100% - cut) 100%, 0 100%, 0 cut)
Path cutCornerPath(Rect r, double cut) {
  final double c = math.min(cut, math.min(r.width, r.height) / 2);
  return Path()
    ..moveTo(r.left + c, r.top)
    ..lineTo(r.right, r.top)
    ..lineTo(r.right, r.bottom - c)
    ..lineTo(r.right - c, r.bottom)
    ..lineTo(r.left, r.bottom)
    ..lineTo(r.left, r.top + c)
    ..close();
}

/// 六边「价格牌」多边形（L399 .ptag：polygon(10px 0,…,0 50%)）
Path hexTagPath(Rect r, double cut) {
  return Path()
    ..moveTo(r.left + cut, r.top)
    ..lineTo(r.right - cut, r.top)
    ..lineTo(r.right, r.center.dy)
    ..lineTo(r.right - cut, r.bottom)
    ..lineTo(r.left + cut, r.bottom)
    ..lineTo(r.left, r.center.dy)
    ..close();
}

/// ═══════════════════════════════════════════════════════════
///  RefButton —— 参考稿 .btn（L71-86）
///
///  · 高 62（.sm 56）、内边距 0 22、字 900 18px / 字距 2（.sm 16）
///  · 双层描边：外层 --bd 铺满 + 内层 --bb inset 1.5px
///  · .pri = acid 底 + 深字 + drop-shadow 0 0 16px 55%
///  · .ghost = --bd rgba(255,255,255,.22) + --bb #110e20
///  · 按下 translateY(3px) scale(.965)，过渡 .14s var(--ease)
///  · 常驻流光：40% 宽斜带 skewX(-20deg)，sheen 3.6s ease-in-out infinite
///    （0%~60% 停在 -60%，60%~100% 扫到 130%）—— 参考稿是循环，不是一次性
/// ═══════════════════════════════════════════════════════════
class RefButton extends StatefulWidget {
  const RefButton({
    super.key,
    required this.label,
    this.onTap,
    this.primary = true,
    this.small = false,
    this.accent,
    this.trailingTriangle = false,
    this.leading,
    this.enabled = true,
    this.animateSheen = true,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool small;

  /// 主色的覆盖（默认 acid；「立新目标」这类用 gold）
  final Color? accent;

  /// 主键右侧的小三角 .tri（8x12）
  final bool trailingTriangle;
  final Widget? leading;
  final bool enabled;

  /// 关闭后不跑流光（列表里多颗按钮时用来省电）
  final bool animateSheen;

  @override
  State<RefButton> createState() => _RefButtonState();
}

class _RefButtonState extends State<RefButton> with TickerProviderStateMixin {
  bool _down = false;
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.animateSheen || !widget.primary) return;
    if (_sheen.isAnimating) return;
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _sheen.value = 1;
    } else {
      _sheen.repeat();
    }
  }

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  bool get _on => widget.enabled && widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    final Color accent = widget.accent ?? Ref.acid;
    final double fs = widget.small ? 16 : 18;
    final bool pri = widget.primary;
    final Color ink = pri ? Ref.onAccent : Ref.txt;

    final Widget title = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (widget.leading != null) ...<Widget>[
          widget.leading!,
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: refText(
              family: Ref.fc,
              size: fs,
              wght: 900,
              ls: 2,
              height: 1,
              color: ink,
            ),
          ),
        ),
        if (widget.trailingTriangle) ...<Widget>[
          const SizedBox(width: 10),
          CustomPaint(
            size: const Size(8, 12),
            painter: _TrianglePainter(color: ink),
          ),
        ],
      ],
    );

    return Semantics(
      button: true,
      enabled: _on,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _on ? (_) => setState(() => _down = true) : null,
        onTapUp: _on ? (_) => setState(() => _down = false) : null,
        onTapCancel: _on ? () => setState(() => _down = false) : null,
        onTap: _on ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Ref.ease,
          height: widget.small ? Ref.btnSmH : Ref.btnH,
          transform: _down
              ? (Matrix4.identity()
                  ..translateByDouble(0, 3, 0, 1)
                  ..scaleByDouble(.965, .965, 1, 1))
              : Matrix4.identity(),
          clipBehavior: Clip.none,
          padding: EdgeInsets.symmetric(horizontal: widget.small ? 18 : 22),
          child: AnimatedBuilder(
            animation: _sheen,
            builder: (BuildContext context, Widget? child) => CustomPaint(
              painter: _BtnPainter(
                accent: accent,
                primary: pri,
                enabled: _on,
                cut: widget.small ? 11 : Ref.btnCut,
                sheen: _sheen.value,
              ),
              child: child,
            ),
            child: Center(child: title),
          ),
        ),
      ),
    );
  }
}

class _BtnPainter extends CustomPainter {
  const _BtnPainter({
    required this.accent,
    required this.primary,
    required this.enabled,
    required this.cut,
    required this.sheen,
  });

  final Color accent;
  final bool primary;
  final bool enabled;
  final double cut;

  /// 0~1：0~0.6 停在左侧（不可见），0.6~1 扫过
  final double sheen;

  @override
  void paint(Canvas canvas, Size s) {
    final Rect r = Offset.zero & s;
    // drop-shadow(0 0 16px mix(--bd 55%))
    if (primary && enabled) {
      canvas.drawPath(
        cutCornerPath(r.deflate(1), cut),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Ref.a(accent, .55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
    }
    // ::before —— 外层描边铺满
    canvas.drawPath(
      cutCornerPath(r, cut),
      Paint()
        ..color = primary
            ? (enabled ? accent : Ref.mix(accent, Ref.bg, .6))
            : (enabled ? const Color(0x38FFFFFF) : const Color(0x1AFFFFFF)),
    );
    // ::after —— 内层 inset 1.5
    canvas.drawPath(
      cutCornerPath(r.deflate(1.5), math.max(0, cut - 1.5)),
      Paint()
        ..color = primary
            ? (enabled ? accent : Ref.mix(accent, Ref.bg, .6))
            : const Color(0xFF110E20),
    );
    // .btn .sh2::before —— 40% 宽斜带；0~60% 不动，60~100% 从左扫到右
    if (primary && enabled) {
      final double k = sheen <= .6 ? 0 : (sheen - .6) / .4;
      if (k > 0) {
        canvas.save();
        canvas.clipPath(cutCornerPath(r.deflate(1.5), cut));
        final double x = -s.width * .6 + s.width * 1.9 * k;
        final Rect band = Rect.fromLTWH(
          x,
          -s.height,
          s.width * .4,
          s.height * 3,
        );
        canvas.drawRect(
          band,
          Paint()
            ..shader = const LinearGradient(
              colors: <Color>[
                Color(0x00FFFFFF),
                Color(0x8CFFFFFF),
                Color(0x00FFFFFF),
              ],
              stops: <double>[0, .5, 1],
            ).createShader(band),
        );
        canvas.restore();
      }
      canvas.drawLine(
        Offset(r.left + cut + 3, r.top + 1),
        Offset(r.right - 4, r.top + 1),
        Paint()
          ..strokeWidth = 1
          ..color = const Color(0x59FFFFFF),
      );
    }
  }

  @override
  bool shouldRepaint(_BtnPainter o) =>
      o.accent != accent ||
      o.primary != primary ||
      o.enabled != enabled ||
      o.cut != cut ||
      o.sheen != sheen;
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter({required this.color});
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
  bool shouldRepaint(_TrianglePainter o) => o.color != color;
}

/// .iconbtn（L108-110）：42x42 / r14 / rgba(255,255,255,.03) + 1px line；
/// hover rgba(255,255,255,.08)；active scale(.9)
class RefIconButton extends StatefulWidget {
  const RefIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 42,
    this.semanticLabel,
  });

  final Widget icon;
  final VoidCallback? onTap;
  final double size;
  final String? semanticLabel;

  @override
  State<RefIconButton> createState() => _RefIconButtonState();
}

class _RefIconButtonState extends State<RefIconButton> {
  bool _down = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _down ? .9 : 1,
            duration: const Duration(milliseconds: 150),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: _hover
                    ? const Color(0x14FFFFFF)
                    : const Color(0x08FFFFFF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Ref.line),
              ),
              child: Center(child: widget.icon),
            ),
          ),
        ),
      ),
    );
  }
}

/// .xbtn（L64-67）：48x48 圆 + 1px color-mix(accent 40%)；
/// hover rotate(90deg) + accent 15% 底；active scale(.88)。
class RefXButton extends StatefulWidget {
  const RefXButton({super.key, this.onTap, this.accent, this.back = false});

  final VoidCallback? onTap;
  final Color? accent;

  /// true = 返回箭头（参考稿 data-back 的 15 5 l-7 7 7 7）
  final bool back;

  @override
  State<RefXButton> createState() => _RefXButtonState();
}

class _RefXButtonState extends State<RefXButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final Color accent = widget.accent ?? Ref.acid;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: widget.back ? '返回' : '关闭',
        child: GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _down ? .88 : 1,
            duration: const Duration(milliseconds: 150),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Ref.ease,
              width: 48,
              height: 48,
              transform: _hover
                  ? (Matrix4.identity()..rotateZ(math.pi / 2))
                  : Matrix4.identity(),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hover ? Ref.a(accent, .15) : const Color(0x08FFFFFF),
                border: Border.all(color: Ref.a(accent, .40)),
              ),
              child: CustomPaint(
                size: const Size(18, 18),
                painter: _GlyphPainter(back: widget.back, color: Ref.txt),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// .xbtn svg：stroke-width 2.4 / stroke-linecap round，18x18
class _GlyphPainter extends CustomPainter {
  const _GlyphPainter({required this.back, required this.color});
  final bool back;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = color;
    if (back) {
      final Path path = Path()
        ..moveTo(s.width * .62, s.height * .2)
        ..lineTo(s.width * .3, s.height * .5)
        ..lineTo(s.width * .62, s.height * .8);
      canvas.drawPath(path, p);
    } else {
      canvas.drawLine(
        Offset(s.width * .25, s.height * .25),
        Offset(s.width * .75, s.height * .75),
        p,
      );
      canvas.drawLine(
        Offset(s.width * .75, s.height * .25),
        Offset(s.width * .25, s.height * .75),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter o) => o.back != back || o.color != color;
}

/// .chip（L101-107）：高 36 / r999 / rgba(255,255,255,.04) / 1px line /
/// 内边距 0 12 0 9 / gap 6 / 数字 700 16px Chakra。
class RefChip extends StatelessWidget {
  const RefChip({
    super.key,
    required this.value,
    this.icon,
    this.valueColor,
    this.glowColor,
    this.bump = 0,
  });

  final String value;
  final Widget? icon;
  final Color? valueColor;
  final Color? glowColor;

  /// 每 +1 播一次 bump（@keyframes bump { 30% { scale(1.25) } } .5s）
  final int bump;

  @override
  Widget build(BuildContext context) {
    final Widget chip = Container(
      height: 36,
      padding: const EdgeInsets.only(left: 9, right: 12),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Ref.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[icon!, const SizedBox(width: 6)],
          Text(
            value,
            style: refText(
              family: Ref.fd,
              size: 16,
              wght: 700,
              height: 1,
              color: valueColor ?? Ref.txt,
              shadows: glowColor == null
                  ? null
                  : <Shadow>[Shadow(color: glowColor!, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
    return _BumpOnChange(bump: bump, child: chip);
  }
}

class _BumpOnChange extends StatefulWidget {
  const _BumpOnChange({required this.bump, required this.child});
  final int bump;
  final Widget child;

  @override
  State<_BumpOnChange> createState() => _BumpOnChangeState();
}

class _BumpOnChangeState extends State<_BumpOnChange>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  @override
  void didUpdateWidget(_BumpOnChange old) {
    super.didUpdateWidget(old);
    if (old.bump != widget.bump) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext _, Widget? child) {
        if (!_c.isAnimating) return child!;
        final double t = _c.value;
        final double k = t < .3
            ? 1 + .25 * (t / .3)
            : 1.25 - .25 * ((t - .3) / .7);
        return Transform.scale(scale: k, child: child);
      },
      child: widget.child,
    );
  }
}

/// .ptag（L399）：六边形价签
/// clip-path: polygon(10px 0, ..., 0 50%); padding 6 16; 700 16px Chakra;
/// 1.5px 当前色边框; 12% 同色底.
class RefHexTag extends StatelessWidget {
  const RefHexTag({
    super.key,
    required this.label,
    required this.color,
    this.cut = 10,
    this.height = 34,
  });

  final String label;
  final Color color;
  final double cut;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _HexTagPainter(color: color, cut: cut),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: cut + 8),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              style: refText(
                family: Ref.fd,
                size: 16,
                wght: 700,
                height: 1,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HexTagPainter extends CustomPainter {
  const _HexTagPainter({required this.color, required this.cut});
  final Color color;
  final double cut;

  @override
  void paint(Canvas canvas, Size s) {
    final Rect r = Offset.zero & s;
    final Path p = hexTagPath(r.deflate(.75), cut);
    canvas.drawPath(p, Paint()..color = Ref.a(color, .12));
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_HexTagPainter o) => o.color != color || o.cut != cut;
}
