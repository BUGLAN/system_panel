import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../stage/camera.dart';
import '../stage/progress_band.dart';
import '../state/goal.dart';
import 'rail_base.dart';

/// ═══════════════════════════════════════════════════════════
///  主线挂签（原 ringtag —— 「R5/8」那套已随环一起废除）
///  大厅里挂在**进度带右端**的 112×48 小挂签：主线 / 0/8 / 目标短字 / 进度条。
///  点它展开主线页（docs/33 的卡片式新视图）。
///
///  ⚠️ 真机走查（docs/39 §2.1 / H-08，图 05/06）暴露三个问题，这里整支重写：
///   ① 恒 .18 不透明度 → 只剩一片几乎看不见的淡字（新：常态 .78 / 说话 .55 /
///      失败 .35 三档）；
///   ② 右边缘超出 430 屏宽约 46pt 被裁（新：左缘夹在 [16, W-16-112]，永不越界）；
///   ③ 只吃静态 cam 字符串、1.4s 推镜时不跟手（新：吃逐帧 camObj）。
///
///  落点 = ProgressBand.point(cam) + (0, -18) —— 与进度带右端点同一套相机数学。
/// ═══════════════════════════════════════════════════════════

/// 挂签的三档不透明度（docs/39 H-08）
enum PlanTagTone {
  /// 常态：.78
  normal(.78),

  /// 她正在说话：.55（让字幕是那一拍的唯一主角）
  speaking(.55),

  /// 失败页：.35（压暗，但目标还在那里）
  failed(.35);

  const PlanTagTone(this.opacity);

  final double opacity;
}

class PlanTag extends StatefulWidget {
  const PlanTag({
    super.key,
    required this.goal,
    this.cam = 'lobby',
    this.camObj,
    this.visible = true,
    this.tone = PlanTagTone.normal,
    this.onTap,
  });

  final Goal goal;

  /// 静态相机预设名（给了 [camObj] 就以逐帧相机为准）
  final String cam;

  /// 弹簧推出来的那一帧相机。**逐帧跟手**靠它：只吃字符串时，
  /// 大厅 ↔ 主线的 1.4s 推镜期间挂签是钉死的（真机图 06 的错位就是它）。
  final Cam? camObj;

  final bool visible;

  /// 三档不透明度（见 [PlanTagTone]）
  final PlanTagTone tone;

  final VoidCallback? onTap;

  @override
  State<PlanTag> createState() => _PlanTagState();
}

class _PlanTagState extends State<PlanTag> with TickerProviderStateMixin {
  /// 进度变化时的 600ms 1.06 脉冲（docs/39 H-08）
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: Motion.harvestMs),
  );

  /// 系统心跳（docs/39 H-18 / §5.1）：2400ms，只驱动锚点那颗光点的呼吸。
  /// 与 CTA 呼吸同一个周期 —— 同屏只留「她 + 心跳」两个可感知循环。
  /// reduced-motion 下不跑（光点保持静态亮）。
  late final AnimationController _heart = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: Motion.heartMs),
  );

  int _lastDone = -1;

  @override
  void didUpdateWidget(covariant PlanTag old) {
    super.didUpdateWidget(old);
    final int done = widget.goal.doneCount;
    if (_lastDone >= 0 && done != _lastDone) {
      _pulse.forward(from: 0);
    }
    _lastDone = done;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // H-18：心跳只在可见且没开减弱动态时跑（不可见时白烧 ticker）
    final bool on = widget.visible && !railReduceMotion(context);
    if (on && !_heart.isAnimating) {
      _heart.repeat();
    } else if (!on && _heart.isAnimating) {
      _heart.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _heart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Goal goal = widget.goal;
    if (goal.plan.isEmpty) return const SizedBox.shrink();
    final Size size = MediaQuery.sizeOf(context);
    final int total = goal.totalTasks;
    final int done = goal.doneCount;

    // 锚点：进度带右端点 + (0, -18)；左缘夹在 [16, W-16-112]（不再越界被裁）
    final Cam? cam = widget.camObj;
    final Offset p = cam == null
        ? ProgressBand.point(widget.cam, size)
        : cam.toScreen(ProgressBand.kRx, ProgressBand.kRy, size);
    // 左缘夹在 [16, W-16-112]：锚点在屏外/贴边时挂签也不出画（真机图 06 的裁字）。
    // ⚠️ clamp 的上下界反了会抛（num.clamp 要求 lower ≤ upper）—— 窄屏兜个底。
    final double maxLeft = size.width - 16 - kPlanTagW;
    final double left = maxLeft <= 16 ? 16 : p.dx.clamp(16.0, maxLeft);
    final double top = p.dy - 18;

    Widget tag = _TagBody(
      key: const Key('planTag'),
      done: done,
      total: total,
      short: goal.short,
      heart: _heart,
    );
    final bool reduce = railReduceMotion(context);
    // 进度脉冲只缩**这一小块**（112×48），不下探到环场，也不做 saveLayer
    if (!reduce) {
      tag = AnimatedBuilder(
        animation: _pulse,
        builder: (BuildContext _, Widget? child) {
          if (!_pulse.isAnimating) return child!;
          // docs/39 H-08「进度变化 600ms 1.06 脉冲」：1.06 → 1 走 easeOutCubic
          final double k =
              1 + .06 * (1 - Curves.easeOutCubic.transform(_pulse.value));
          return Transform.scale(scale: k, child: child);
        },
        child: tag,
      );
    }

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: AnimatedOpacity(
          key: const Key('planTag.fade'),
          opacity: widget.visible ? widget.tone.opacity : 0,
          // reduced-motion：三档照落，但不做淡入淡出（§5.5「直接落终态」）
          duration: reduce
              ? Duration.zero
              : const Duration(milliseconds: Motion.scrimMs),
          curve: kOut,
          child: GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: tag,
          ),
        ),
      ),
    );
  }
}

/// 挂签的宽 / 高（docs/39 H-08）
const double kPlanTagW = 112;
const double kPlanTagH = 48;

class _TagBody extends StatefulWidget {
  const _TagBody({
    super.key,
    required this.done,
    required this.total,
    required this.short,
    this.heart,
  });

  final int done;
  final int total;
  final String short;

  /// 系统心跳（docs/39 H-18）—— 锚点光点跟着呼吸；null = 静态
  final Animation<double>? heart;

  @override
  State<_TagBody> createState() => _TagBodyState();
}

class _TagBodyState extends State<_TagBody> {
  /// 数字滚动的起点（docs/39 H-11「挂签数字 count 300ms」）。
  /// 只在 [done] 变化时从旧值滚到新值；首挂直接显示，没有「从 0 数上来」。
  late int _from = widget.done;

  @override
  void didUpdateWidget(covariant _TagBody old) {
    super.didUpdateWidget(old);
    if (old.done != widget.done) _from = old.done;
  }

  @override
  Widget build(BuildContext context) {
    final int done = widget.done;
    final int total = widget.total;
    final String short = widget.short;
    final double ratio = total <= 0 ? 0 : (done / total).clamp(0.0, 1.0);
    return SizedBox(
      width: kPlanTagW,
      height: kPlanTagH,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          // 玻璃底 + 左侧青色挂边（挂签的「吊挂」那一笔）
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xB3040E20), // rgba(4,14,32,.7)
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0x2938E1FF), width: 1),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 8,
            bottom: 8,
            width: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[C.blue.withAlpha(64), C.blue],
                ),
              ),
            ),
          ),
          // 锚点光点：钉在进度带右端点那一行（tag 顶 + 18 = 锚点 y）
          // docs/39 H-18：它吃 2.4s 系统心跳（与 CTA 呼吸同相位），
          // 幅度很小 —— 要的是「像呼吸不像闪」。
          Positioned(
            left: -3.5,
            top: 18 - 3.5,
            child: AnimatedBuilder(
              animation: widget.heart ?? kAlwaysDismissedAnimation,
              builder: (BuildContext _, Widget? child) {
                final double h = widget.heart == null
                    ? 0
                    : (math.sin(
                                widget.heart!.value * 2 * math.pi - math.pi / 2,
                              ) +
                              1) /
                          2;
                return Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: C.blue,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: C.blue.withAlpha((120 + 80 * h).round()),
                        blurRadius: 6 + 5 * h,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // 两行：① 主线 9.5 + 0/8（Tektur 16）  ② 目标短字（11.5，单行省略）
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 5, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      '主线',
                      style: fs(
                        family: F.mono,
                        size: 9.5,
                        wght: 500,
                        ls: 1.9,
                        height: 1,
                        color: C.mist,
                      ),
                    ),
                    const Spacer(),
                    // docs/39 H-11：数字 300ms count-up（进度收割那 600ms 里先动起来）。
                    // reduced-motion 直接落终值（§5.5：只保留「数值变了」这件事）。
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: _from.toDouble(),
                        end: done.toDouble(),
                      ),
                      duration: railReduceMotion(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      builder: (BuildContext _, double v, Widget? _) {
                        final int shown = v.round();
                        return Text.rich(
                          TextSpan(
                            children: <InlineSpan>[
                              TextSpan(
                                text: '$shown',
                                style: fs(
                                  family: F.num,
                                  size: 16,
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
                                  size: 16,
                                  wght: 600,
                                  height: 1,
                                  color: C.mist,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  short,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: fs(
                    family: F.cn,
                    size: 11.5,
                    wght: 400,
                    height: 1,
                    color: C.ice,
                  ),
                ),
              ],
            ),
          ),
          // 底部 2px 进度条：done/total，青 α.6
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 2,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: C.line2),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: ratio,
                  alignment: Alignment.centerLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: C.blue.withAlpha(153), // α .6
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
