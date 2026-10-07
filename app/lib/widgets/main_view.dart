import 'package:flutter/material.dart';

import '../data/format.dart';
import '../design/tokens.dart';
import '../state/goal.dart';

/// ═══════════════════════════════════════════════════════════
///  主线全景（app.css L419-435 `#mainv` + ui.js `MainV`）
///  抬头写目标与进度、右上角一个 ×、底部一张环详情卡 + 「换目标」。
///  环本身套在她身上（WebGL），这里只做**面板**部分；
///  挂在环上的那些标签见 `ring_labels.dart`。
///
///  实测盒模型（390×844）：
///    mv-top [20,22,350,79] · kick [20,27,107,13] · h3 [20,49,186,28] · p [20,83,186,18]
///    × [332,22,38,38] · detail [20,631,350,121] · low [20,764,350,54] · 换目标 [20,764,88,54]
/// ═══════════════════════════════════════════════════════════
class MainView extends StatelessWidget {
  const MainView({
    super.key,
    required this.goal,
    this.selected,
    this.canDispatch = false,
    this.visible = true,
    this.onClose,
    this.onDispatch,
    this.onNewGoal,
  });

  final Goal goal;

  /// 当前展开的环序（null = 没展开，只有抬头）
  final int? selected;

  /// 是否给「让她派这一环」（原型 `canGo`：没有执行中的任务 + 有主线单）
  final bool canDispatch;

  final bool visible;
  final VoidCallback? onClose;
  final VoidCallback? onDispatch;
  final VoidCallback? onNewGoal;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 400),
          child: Stack(
            children: <Widget>[
              _top(),
              if (selected != null) _detail(goal.rings[selected!]),
              _low(),
            ],
          ),
        ),
      ),
    );
  }

  /// .mv-top
  Widget _top() {
    return Positioned(
      left: 20,
      right: 20,
      top: 22,
      child: Row(
        key: const Key('main.top'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // `.kick` 是 inline，被父级 16px strut 撑出的行框里下沉 5px
                SizedBox(
                  height: 19.2,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      'MAINLINE · 主线',
                      key: const Key('main.kicker'),
                      style: fs(
                        family: F.mono,
                        size: 10,
                        wght: 400,
                        ls: 1.6,
                        color: C.blue,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Text(
                    goal.text,
                    key: const Key('main.title'),
                    style: fs(
                      family: F.hd,
                      size: 22,
                      wght: 400,
                      ls: .44,
                      height: 1.25,
                      color: C.ice,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text.rich(
                  key: const Key('main.progress'),
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: '${goal.doneCount}',
                        style: fs(
                          family: F.num,
                          size: 14,
                          wght: 800,
                          color: C.ice,
                        ),
                      ),
                      TextSpan(
                        text:
                            ' / ${goal.rings.length} 环 · 起于 ${goal.startedText}',
                      ),
                    ],
                    style: fs(
                      family: F.mono,
                      size: 11,
                      wght: 600,
                      ls: 1.1,
                      color: C.mist,
                    ),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onClose,
            behavior: HitTestBehavior.opaque,
            child: Container(
              key: const Key('main.close'),
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x99040E20), // rgba(4,14,32,.6)
                border: Border.all(color: C.line, width: 1),
              ),
              child: Text(
                '×',
                style: fs(
                  family: F.cn,
                  size: 22,
                  wght: 400,
                  height: 1,
                  color: C.ice,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// .mv-detail
  Widget _detail(GoalRing ring) {
    return Positioned(
      left: 20,
      right: 20,
      bottom: 92,
      child: Container(
        key: const Key('main.detail'),
        padding: const EdgeInsets.fromLTRB(
          15,
          13,
          15,
          13,
        ), // CSS 14/16，Border 占 1
        decoration: BoxDecoration(
          color: const Color(0xE6040C1C), // rgba(4,12,28,.9)
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: C.line, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              ring.finalRing
                  ? '终点 · 我头顶那一环'
                  : 'RING ${(selected ?? 0) + 1} · ${ring.rank} 级',
              style: fs(
                family: F.mono,
                size: 10,
                wght: 400,
                ls: 1.6,
                color: C.blue,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              ring.title,
              style: fs(
                family: F.hd,
                size: 17,
                wght: 400,
                height: 1.3,
                color: C.ice,
              ),
            ),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: ring.statusText().split(' · 用时').first,
                    style: ring.state == RingState.cur
                        ? fs(
                            family: F.cn,
                            size: 12.5,
                            wght: 600,
                            height: 1.6,
                            color: C.ice,
                          )
                        : null,
                  ),
                  if (ring.held != null)
                    TextSpan(text: ' · 用时 ${fmtDur(ring.held!)}'),
                  TextSpan(
                    text: '\n证明：${ring.proof} · 时限 ${fmtMin(ring.minutes)}',
                  ),
                ],
                style: fs(
                  family: F.cn,
                  size: 12.5,
                  wght: 400,
                  height: 1.6,
                  color: C.mist,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// .mv-low
  Widget _low() {
    return Positioned(
      left: 20,
      right: 20,
      bottom: 26,
      child: Row(
        key: const Key('main.low'),
        children: <Widget>[
          if (canDispatch) ...<Widget>[
            Expanded(child: _mainButton()),
            const SizedBox(width: 10),
          ],
          _ghostButton(),
        ],
      ),
    );
  }

  Widget _mainButton() {
    return GestureDetector(
      onTap: onDispatch,
      behavior: HitTestBehavior.opaque,
      child: Container(
        key: const Key('main.dispatch'),
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: C.blue,
          borderRadius: BorderRadius.circular(27),
          boxShadow: <BoxShadow>[
            BoxShadow(color: C.blue.withAlpha(102), blurRadius: 28),
          ],
        ),
        child: Stack(
          children: <Widget>[
            // inset 0 1px 0 rgba(255,255,255,.6)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.white.withAlpha(153)),
              ),
            ),
            Text(
              '让她派这一环',
              style: fs(
                family: F.cn,
                size: 15,
                wght: 600,
                ls: .9,
                height: 1,
                color: C.deep,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ghostButton() {
    return GestureDetector(
      onTap: onNewGoal,
      behavior: HitTestBehavior.opaque,
      child: Container(
        key: const Key('main.newGoal'),
        height: 54,
        // Border 占布局、CSS 的 inset 阴影不占 → padding 各减 1px
        padding: const EdgeInsets.symmetric(horizontal: 19),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xB3040E20), // rgba(4,14,32,.7)
          borderRadius: BorderRadius.circular(27),
          border: Border.all(color: C.line, width: 1),
        ),
        child: Text(
          '换目标',
          style: fs(
            family: F.cn,
            size: 15,
            wght: 600,
            ls: .9,
            height: 1,
            color: C.ice,
          ),
        ),
      ),
    );
  }
}
