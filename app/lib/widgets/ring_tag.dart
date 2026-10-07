import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../stage/camera.dart';
import '../state/goal.dart';

/// ═══════════════════════════════════════════════════════════
///  当前环的挂签（app.css L128-138 `.ringtag`）
///  大厅里挂在她**脚下那一环**右端的标签：主线 / R5/8 / 五公里。
///  点它展开主线全景（`main.js` L61 → `App.mainline()`）。
///
///  落点由 `Flow.place()` 给出：`translate(round(p.x+4), round(p.y-14))`，
///  `p = Stage.ringPoint(curRing, 1)` —— 用的是**大厅相机**，不是全景那套。
///  实测（390×844）：tag [305,387,69,44] · lead [305,409,24,1]
///    rt-k [335,387,21,9] · b [335,399,30,15] · em [335,417,35,14]
///
///  ⚠️ `#ui:has(#line.on) .ringtag.on { opacity: .18 }` ——
///  字幕一出来它就暗到 18%。（大厅里字幕是一直在的，所以平时就是暗的。）
/// ═══════════════════════════════════════════════════════════
class RingTag extends StatelessWidget {
  const RingTag({
    super.key,
    required this.goal,
    this.cam = 'lobby',
    this.visible = true,
    this.dimmed = false,
    this.onTap,
  });

  final Goal goal;

  /// 挂签跟着相机走 —— 大厅用 `lobby`，全景用 `full`
  final String cam;

  final bool visible;

  /// 字幕在的时候暗到 18%
  final bool dimmed;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final int ci = goal.currentIndex;
    if (ci < 0) return const SizedBox.shrink();

    final GoalRing ring = goal.rings[ci];
    final Size size = MediaQuery.sizeOf(context);
    final Offset p = RingGeom.of(
      ci,
      goal.rings.length,
      finalRing: ring.finalRing,
    ).point(cam, size);

    return Positioned(
      // 原型是 Math.round，不是截断
      left: (p.dx + 4).roundToDouble(),
      top: (p.dy - 14).roundToDouble(),
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? (dimmed ? .18 : 1) : 0,
          duration: const Duration(milliseconds: 500),
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              // `#ringTag` 指的是**外层整块**（含 padding-left 30），宽 69
              key: const Key('ringTag'),
              // `.lead` 是绝对定位的、不占内容宽度；内容从 padding-left 30 起
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned(
                    left: 0,
                    top: 22, // 整块 44 高，50%
                    child: _lead(),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 30, right: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '主线',
                          style: fs(
                            family: F.mono,
                            size: 8.5,
                            wght: 500,
                            ls: 1.87, // .22em
                            height: 1,
                            color: C.mist,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text.rich(
                          TextSpan(
                            children: <InlineSpan>[
                              TextSpan(
                                text: 'R${ci + 1}',
                                style: fs(
                                  family: F.num,
                                  size: 15,
                                  wght: 800,
                                  height: 1,
                                  color: C.blue,
                                  shadows: <Shadow>[
                                    Shadow(
                                      color: C.blue.withAlpha(140),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                              ),
                              TextSpan(
                                text: '/${goal.rings.length}',
                                style: fs(
                                  family: F.num,
                                  size: 10,
                                  wght: 600,
                                  height: 1,
                                  color: C.mist,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 3),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 74),
                          child: Text(
                            ring.finalRing ? goal.short : ring.short,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: fs(
                              family: F.cn,
                              size: 11.5,
                              wght: 400,
                              color: C.ice,
                            ),
                          ),
                        ),
                      ],
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

  /// `.lead` —— 24 长的一条渐隐引线，左端顶着一颗会发光的点
  Widget _lead() {
    return SizedBox(
      width: 24,
      height: 1,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[C.blue.withAlpha(230), C.blue.withAlpha(64)],
                ),
              ),
            ),
          ),
          Positioned(
            left: -3,
            top: -3,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: C.blue,
                boxShadow: <BoxShadow>[BoxShadow(color: C.blue, blurRadius: 8)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
