import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../stage/camera.dart';
import '../state/goal.dart';

/// ═══════════════════════════════════════════════════════════
///  环挂签（app.css L137-152 `#ringLabels`）
///  主线全景时，每一环的右端伸出一条短横线，挂上 `R1 穿上跑鞋`。
///  位置由 `Stage.ringPoint(i, 1)` 给出 —— 那是**纯数学**，
///  不需要 Live2D（见 stage/camera.dart 的推导）。
///
///  实测：R1 [272,610,100,14]（= 环位 x+4、垂直居中）… ★ [307,35,81,16]
/// ═══════════════════════════════════════════════════════════
class RingLabels extends StatelessWidget {
  const RingLabels({
    super.key,
    required this.goal,
    this.cam = 'full',
    this.visible = true,
    this.onPick,
  });

  final Goal goal;

  /// 当前相机预设名（主线全景是 `full`）
  final String cam;

  final bool visible;

  /// 点某一环的挂签（原型里 `.rl` 是 `pointer-events:auto` + onclick → `MainV.detail(i)`）
  final ValueChanged<int>? onPick;

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 400),
          child: Stack(
            children: <Widget>[
              for (int i = 0; i < goal.rings.length; i++) _place(i, size),
            ],
          ),
        ),
      ),
    );
  }

  Widget _place(int i, Size size) {
    final GoalRing ring = goal.rings[i];
    final RingGeom geom = RingGeom.of(
      i,
      goal.rings.length,
      finalRing: ring.finalRing,
    );
    final Offset p = geom.point(cam, size);
    // `b.style.left = p.x + 4; b.style.top = p.y` + `transform: translateY(-50%)`
    return Positioned(
      left: p.dx + 4,
      top: p.dy,
      child: FractionalTranslation(
        translation: const Offset(0, -.5),
        child: GestureDetector(
          onTap: onPick == null ? null : () => onPick!(i),
          behavior: HitTestBehavior.opaque,
          child: _Rl(key: Key('ring.label.$i'), index: i, ring: ring),
        ),
      ),
    );
  }
}

/// `#ringLabels .rl` —— 短横线 + `R1` + 短名
class _Rl extends StatelessWidget {
  const _Rl({super.key, required this.index, required this.ring});

  final int index;
  final GoalRing ring;

  @override
  Widget build(BuildContext context) {
    final bool done = ring.state == RingState.done;
    final bool cur = ring.state == RingState.cur;
    final bool lock = ring.state == RingState.lock;

    final Color nameColor = cur
        ? Colors.white
        : done
        ? C.ice
        : C.mist;
    final Color numColor = cur
        ? Colors.white
        : done
        ? C.blue
        : C.mist;

    return Opacity(
      // .rl.lock { opacity: .55 }
      opacity: lock ? .55 : 1,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // i —— 22×1 的短横线；走过实心、脚下发光、未走虚线
          SizedBox(
            width: 22,
            height: 1,
            child: lock
                ? CustomPaint(painter: const _DashPainter())
                : DecoratedBox(
                    decoration: BoxDecoration(
                      color: cur ? C.blue : const Color(0x8038E1FF),
                      boxShadow: cur
                          ? <BoxShadow>[BoxShadow(color: C.blue, blurRadius: 6)]
                          : null,
                    ),
                  ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 20,
            child: Text(
              ring.finalRing ? '★' : 'R${index + 1}',
              maxLines: 1,
              style: fs(
                family: F.num,
                size: 11,
                wght: 700,
                height: 1,
                color: numColor,
              ),
            ),
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 104),
            child: Text(
              ring.short,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ring.finalRing
                  ? fs(
                      family: F.hd,
                      size: 13,
                      wght: 400,
                      ls: .52,
                      color: nameColor,
                    )
                  : fs(
                      family: F.cn,
                      size: 11.5,
                      wght: cur ? 600 : 400,
                      color: nameColor,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.rl.lock i` 的 `repeating-linear-gradient(90deg, rgba(56,225,255,.4) 0 3px, transparent 3px 6px)`
class _DashPainter extends CustomPainter {
  const _DashPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final Paint p = Paint()..color = const Color(0x6638E1FF);
    for (double x = 0; x < s.width; x += 6) {
      canvas.drawRect(Rect.fromLTWH(x, 0, math.min(3, s.width - x), 1), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
