import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// 认输暗幕 Veil 与失败抽色矩阵 kFailColorMatrix。
// 从旧 fail_layer.dart 拆出来的仅存两件（v3 失败页是 RefFail，旧 FailLayer 已删）。

/// `#veil` —— 认输时压下来的那层（radial-gradient 80% 60% at 50% 40%），opacity .6
class Veil extends StatelessWidget {
  const Veil({super.key, this.opacity = 0, this.instant = false});

  final double opacity;

  /// 按住认输时用 —— 原型在那段时间把 `transition` 设成 `none`，
  /// veil 跟着手指**一比一**变暗；松手才恢复 900ms 过渡（`ui.js` L456 / L460）
  final bool instant;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: opacity,
          duration: instant ? Duration.zero : const Duration(milliseconds: 900),
          child: const CustomPaint(painter: _VeilPainter()),
        ),
      ),
    );
  }
}

class _VeilPainter extends CustomPainter {
  const _VeilPainter();

  static const Color _inner = Color(0x4002040A); // rgba(2,4,10,.25)
  static const Color _outer = Color(0xEB010206); // rgba(1,2,6,.92)

  @override
  void paint(Canvas canvas, Size s) {
    final Offset c = Offset(s.width * .5, s.height * .4);
    final double rx = s.width * .8;
    final double ry = s.height * .6;
    final double ky = ry / rx;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(1, ky);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawCircle(
      c,
      rx,
      Paint()..shader = ui.Gradient.radial(c, rx, <Color>[_inner, _outer]),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// `#app.fail #bg { filter: saturate(.2) brightness(.55) }`
/// 写成一张 4×5 颜色矩阵（先降饱和到 .2，再整体 ×.55）
const List<double> kFailColorMatrix = <double>[
  0.20372, 0.31460, 0.03168, 0, 0, //
  0.09372, 0.42460, 0.03168, 0, 0, //
  0.09372, 0.31460, 0.14168, 0, 0, //
  0, 0, 0, 1, 0, //
];
