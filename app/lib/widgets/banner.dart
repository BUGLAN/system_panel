import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// ═══════════════════════════════════════════════════════════
///  横幅（app.css L502-508 `#banner`）
///  称号 / 道具 / 连击到手时从顶上滑下来的一条。
///  实测：`left:50%; top:86px`，`translate(-50%,-20px)` → 落定时 `translate(-50%,0)`。
/// ═══════════════════════════════════════════════════════════
class SysBanner extends StatelessWidget {
  const SysBanner({
    super.key,
    required this.kicker,
    required this.text,
    this.glyph = '✦',
    this.visible = true,
  });

  /// 上面那行小字（`见面礼`）
  final String kicker;

  /// 主文案（`双倍卡 ×1`）
  final String text;

  /// 左边圆字标里的字
  final String glyph;

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: 86,
      child: IgnorePointer(
        ignoring: !visible,
        // ⚠️ `Positioned(top:)` 不给高度时是松约束，`Center` 会**撑满**剩余高度，
        // 把横幅顶到别处 —— heightFactor: 1 让它只占内容那么高（踩过）
        child: Center(
          heightFactor: 1,
          child: AnimatedSlide(
            offset: visible
                ? Offset.zero
                : const Offset(0, -.45), // translateY(-20px)
            duration: const Duration(milliseconds: 500),
            curve: kOut,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                key: const Key('banner'),
                padding: const EdgeInsets.fromLTRB(
                  9,
                  8,
                  15,
                  8,
                ), // CSS 9/16/9/10，Border 占 1
                decoration: BoxDecoration(
                  color: const Color(0xEB040E20), // rgba(4,14,32,.92)
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: C.blue, width: 1),
                  boxShadow: <BoxShadow>[
                    BoxShadow(color: C.blue.withAlpha(77), blurRadius: 30),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _glyph(),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          kicker,
                          style: fs(
                            family: F.mono,
                            size: 9,
                            wght: 600,
                            ls: 1.8,
                            height: 1,
                            color: C.blue,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          text,
                          style: fs(
                            family: F.hd,
                            size: 15,
                            wght: 400,
                            ls: .6,
                            height: 1,
                            color: C.ice,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// `#banner .glyph` —— 30 的圆，字号 12
  Widget _glyph() {
    return SizedBox(
      width: 30,
      height: 30,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _RingGlowPainter(color: C.blue.withAlpha(64)),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: C.blue, width: 1.5),
              gradient: RadialGradient(
                colors: <Color>[C.blue.withAlpha(46), C.blue.withAlpha(0)],
                stops: const <double>[0, .7],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              glyph,
              style: fs(family: F.num, size: 12, wght: 800, color: C.blue),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.glyph` 的外发光 `0 0 12px` —— 不能用 BoxShadow（会透进透明的内部）
class _RingGlowPainter extends CustomPainter {
  const _RingGlowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final double r = s.width / 2;
    canvas.drawCircle(
      Offset(r, r),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  @override
  bool shouldRepaint(covariant _RingGlowPainter o) => o.color != color;
}
