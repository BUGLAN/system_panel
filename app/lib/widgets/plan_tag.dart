import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../stage/progress_band.dart';
import '../state/goal.dart';

/// ═══════════════════════════════════════════════════════════
///  进度挂签（原 `ringtag` —— 「R5/8」那套已随环一起废除）
///  大厅里挂在**进度带**右端的小标签：主线 / 4/8 单 / 目标短字。
///  点它展开主线页（`docs/33` 的卡片式新视图）。
///
///  落点 = `ProgressBand.point('lobby') + (4, -14)`（用的是大厅相机）。
///  ⚠️ 字幕一出来它就暗到 18%（`#ui:has(#line.on)` 的既有纪律）。
/// ═══════════════════════════════════════════════════════════
class PlanTag extends StatelessWidget {
  const PlanTag({
    super.key,
    required this.goal,
    this.cam = 'lobby',
    this.visible = true,
    this.dimmed = false,
    this.onTap,
  });

  final Goal goal;

  /// 挂签跟着相机走 —— 大厅用 `lobby`，主线页用 `full`
  final String cam;

  final bool visible;

  /// 字幕在的时候暗到 18%
  final bool dimmed;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (goal.plan.isEmpty) return const SizedBox.shrink();
    final Size size = MediaQuery.sizeOf(context);
    final Offset p = ProgressBand.point(cam, size);
    final int total = goal.totalTasks;
    final int done = goal.doneCount;

    return Positioned(
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
              key: const Key('planTag'),
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned(left: 0, top: 22, child: _lead()),
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
                            ls: 1.87,
                            height: 1,
                            color: C.mist,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text.rich(
                          TextSpan(
                            children: <InlineSpan>[
                              TextSpan(
                                text: '$done',
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
                                text: '/$total',
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
                            goal.short,
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
