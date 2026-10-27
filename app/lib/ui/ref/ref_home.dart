import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/ref.dart';
import '../../state/goal.dart';
import '../../state/host_state.dart';
import 'ref_core.dart';
import 'ref_orb.dart';
import 'ref_text.dart';

/// ═══════════════════════════════════════════════════════════
///  大厅 —— 参考稿 #sc-home（CSS L128-186，DOM L696-717）
///
///  竖向五段（与稿子一致）：
///    home-tag（SYSTEM ONLINE · DAY 03/14）
///    core-wrap（系统核心 + 气泡，占剩余高度、居中，gap 14）
///    quest 主线卡（20 圆角 + 青色渐变 + 斜切 pips）
///    dock（三颗 66 侧键 + 128 委托球）+ orb-cap
///  active-pill 不走文档流：绝对定位在 bottom 172（L158）。
/// ═══════════════════════════════════════════════════════════
class RefHome extends StatefulWidget {
  const RefHome({
    super.key,
    required this.host,
    required this.goal,
    this.quip = '',
    this.activeElapsed,
    this.active = false,
    this.queue = 0,
    this.day = 1,
    this.days = 14,
    this.mood = CoreMood.neutral,
    this.poke = 0,
    this.skipToken = 0,
    this.onQuestTap,
    this.onCoreTap,
    this.onActivePill,
    this.onSide,
    this.onOrb,
  });

  final HostState host;
  final Goal goal;
  final String quip;

  /// 执行中的读数（12:04）；null = 没有执行中
  final String? activeElapsed;
  final bool active;

  final int queue;

  /// 主线已过几天 / 总天数（home-tag 与主线卡右侧都读它）
  final int day;
  final int days;

  /// 戳她之后的脸（参考稿 setMood：happy / angry / love / scan）
  final CoreMood mood;

  /// 变一次 = 她挨了一下（缩放回弹 + 换台词）；0 = 还没戳过
  final int poke;

  /// 点背景跳过打字机
  final int skipToken;

  final VoidCallback? onQuestTap;
  final VoidCallback? onCoreTap;
  final VoidCallback? onActivePill;

  /// 0 主线 / 1 档案 / 2 补给
  final ValueChanged<int>? onSide;
  final VoidCallback? onOrb;

  @override
  State<RefHome> createState() => _RefHomeState();
}

class _RefHomeState extends State<RefHome> with TickerProviderStateMixin {
  /// 她换一句话时的淡入（参考稿打字机之上的「出现」那一拍）
  late final AnimationController _quipIn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );

  /// 戳她：scale(1) → (.84,.9) → (1.08,1.04) → 1，440ms
  /// cubic-bezier(.3,1.6,.5,1)（JS L1251）
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 440),
  );

  static final Animatable<double> _pressTween = TweenSequence<double>(
    <TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 1,
          end: .86,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 30,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: .86,
          end: 1.08,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 1.08,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
    ],
  );

  @override
  void didUpdateWidget(RefHome old) {
    super.didUpdateWidget(old);
    if (old.quip != widget.quip && widget.quip.isNotEmpty) {
      _quipIn.forward(from: 0);
    }
    if (old.poke != widget.poke) {
      _press.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _quipIn.dispose();
    _press.dispose();
    super.dispose();
  }

  void _tapCore() {
    _press.forward(from: 0);
    widget.onCoreTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    final double screenH = MediaQuery.sizeOf(context).height;
    final int done = widget.goal.doneCount;
    final int total = widget.goal.totalTasks == 0
        ? widget.goal.plan.length
        : widget.goal.totalTasks;

    // .scene{padding: safe-top+94 ... ; bottom: safe-bottom+20}（L57-59）
    final double top = safe.top + Ref.sceneTop;
    final double bottom = safe.bottom + Ref.sceneBottom;

    return Stack(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(Ref.gutter, top, Ref.gutter, bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _homeTag(),
              const SizedBox(height: 10),
              Expanded(child: _coreWrap(screenH)),
              if (widget.goal.plan.isNotEmpty)
                _questCard(done, math.max(total, 1)),
              if (widget.goal.plan.isNotEmpty) const SizedBox(height: 16),
              _dock(),
              const SizedBox(height: 4),
              _orbCap(),
            ],
          ),
        ),
        // .active-pill{left:50%;bottom:safe+172;z-index:3}（L158）
        if (widget.active && widget.activeElapsed != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: safe.bottom + 172,
            child: Center(child: _activePill()),
          ),
      ],
    );
  }

  /// .home-tag（L129-132）：11px mono 字距 3 dim；左 SYSTEM ONLINE（acid + 7 点）
  Widget _homeTag() {
    final String day = widget.day.toString().padLeft(2, '0');
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const _BreathDot(color: Ref.acid, size: 7),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'SYSTEM ONLINE',
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  softWrap: false,
                  style: refText(
                    family: Ref.fm,
                    size: 11,
                    wght: 500,
                    ls: 3,
                    height: 1,
                    color: Ref.acid,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'DAY $day / ${widget.days}',
          maxLines: 1,
          style: refText(
            family: Ref.fm,
            size: 11,
            wght: 500,
            ls: 3,
            height: 1,
            color: Ref.dim,
          ),
        ),
      ],
    );
  }

  /// .core-wrap（L133-137）：flex 1，内容居中，gap 14
  ///
  /// 核心 = min(230, 30vh)（L134）；矮屏时先让位给气泡。
  Widget _coreWrap(double screenH) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double core = math
            .min(230.0, math.min(screenH * .30, box.maxHeight - 118))
            .clamp(72.0, 230.0)
            .toDouble();
        return Align(
          alignment: Alignment.center,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AnimatedBuilder(
                  animation: _press,
                  builder: (BuildContext context, Widget? child) {
                    final double sc = _press.isAnimating
                        ? _pressTween.evaluate(_press)
                        : 1;
                    return Transform.scale(scale: sc, child: child);
                  },
                  child: GestureDetector(
                    onTap: _tapCore,
                    behavior: HitTestBehavior.opaque,
                    child: RefCore(
                      size: core,
                      mood: widget.mood,
                      accent: Ref.cyan,
                      followPointer: true,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _bubble(),
              ],
            ),
          ),
        );
      },
    );
  }

  /// .bubble（L136-143）：max-width 310、padding 12/16、圆角 4 16 16 16
  Widget _bubble() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 310),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0x12FFFFFF), Color(0x05FFFFFF)],
          ),
          borderRadius: Ref.bubble,
          border: Border.all(color: Ref.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'SYSTEM · 她说',
              style: refText(
                family: Ref.fm,
                size: 10,
                wght: 700,
                ls: 3,
                height: 1,
                color: Ref.cyan,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedBuilder(
              animation: _quipIn,
              builder: (BuildContext context, Widget? child) {
                final double t = _quipIn.isAnimating
                    ? Ref.ease.transform(_quipIn.value)
                    : 1;
                return Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, 4 * (1 - t)),
                    child: child,
                  ),
                );
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 24),
                child: RefTypewriter(
                  text: widget.quip,
                  skipToken: widget.skipToken,
                  style: refText(
                    family: Ref.fc,
                    size: 15,
                    wght: 500,
                    height: 1.6,
                    color: Ref.txt,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// .quest（L144-157）：r20 / 青色渐变 / 右侧 › / pips / 页脚
  Widget _questCard(int done, int total) {
    final int left = math.max(0, widget.days - widget.day);
    return GestureDetector(
      onTap: widget.onQuestTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0x1F3BE8FF),
              Color(0x0F8F6BFF),
              Color(0x05FFFFFF),
            ],
            stops: <double>[0, .5, 1],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Ref.a(Ref.cyan, .25)),
        ),
        child: Stack(
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          'MAINLINE · 主线',
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          style: refText(
                            family: Ref.fm,
                            size: 10,
                            wght: 500,
                            ls: 3,
                            height: 1,
                            color: Ref.cyan,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0x33FFFFFF)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '剩 $left 天',
                          style: refText(
                            family: Ref.fc,
                            size: 11,
                            wght: 500,
                            ls: 1,
                            height: 1,
                            color: Ref.txt,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.goal.text.isEmpty ? '（还没有目标）' : widget.goal.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: refText(
                    family: Ref.fc,
                    size: 19,
                    wght: 900,
                    height: 1.3,
                    color: Ref.txt,
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: RefPips(total: math.min(total, 12), done: done),
                ),
                const SizedBox(height: 9),
                Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: Row(
                    children: <Widget>[
                      Text(
                        '$done/$total',
                        style: refText(
                          family: Ref.fd,
                          size: 13,
                          wght: 700,
                          height: 1,
                          color: Ref.txt,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '单',
                        style: refText(
                          family: Ref.fc,
                          size: 12,
                          wght: 500,
                          height: 1,
                          color: Ref.dim,
                        ),
                      ),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          _nextHint(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: refText(
                            family: Ref.fc,
                            size: 12,
                            wght: 500,
                            height: 1,
                            color: Ref.dim,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: Text(
                  '›',
                  style: refText(
                    family: Ref.fd,
                    size: 30,
                    wght: 500,
                    height: 1,
                    color: Ref.cyan,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _nextHint() {
    final int i = widget.goal.firstOpenIndex;
    if (i < 0) return '清单走完了';
    final PlanTask? t = widget.goal.taskAt(i);
    if (t == null) return '';
    return '下一单 · ${t.rank} · ${t.title}';
  }

  /// .active-pill（L158-161）：rgba(hot,.14) + 1px hot + 24px 辉光
  Widget _activePill() {
    return GestureDetector(
      onTap: widget.onActivePill,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: Ref.a(Ref.hot, .14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Ref.hot),
          boxShadow: <BoxShadow>[
            BoxShadow(color: Ref.a(Ref.hot, .35), blurRadius: 24),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const _BreathDot(color: Ref.hot, size: 8),
            const SizedBox(width: 10),
            Text(
              '执行中 ',
              style: refText(
                family: Ref.fc,
                size: 13,
                wght: 700,
                height: 1,
                color: const Color(0xFFFFD0DF),
              ),
            ),
            Text(
              widget.activeElapsed ?? '00:00',
              style: refText(
                family: Ref.fd,
                size: 15,
                wght: 700,
                height: 1,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '点我返回 ›',
              style: refText(
                family: Ref.fc,
                size: 13,
                wght: 700,
                height: 1,
                color: const Color(0xFFFFD0DF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// .dock（L162-173）：gap 10，三颗 navb 66 宽 + 128 委托球
  Widget _dock() {
    final int total = widget.goal.totalTasks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.active && widget.activeElapsed != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Center(child: _activePill()),
          ),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            // .dock 的最小宽度 = 3×66 + 2×10 + 10 + 128 = 366；窄屏按比例收，
            // 不做横向溢出（参考稿假设 430 宽，320 宽时也得站得住）。
            const double need = 366;
            // ⚠️ Transform.scale **不改变布局尺寸**（它只改绘制），用它在窄屏上
            //     缩会照样报 overflow。FittedBox 才是「量完再缩」的那一个：
            //     子项按 need 的固有尺寸排版，再整体缩进可用宽度。
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomRight,
              child: SizedBox(
                width: need,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    _navb(
                      index: 0,
                      label: '主线',
                      arc: total == 0
                          ? null
                          : widget.goal.doneCount / math.max(1, total),
                      sup: total == 0
                          ? null
                          : '${widget.goal.doneCount}/$total',
                    ),
                    const SizedBox(width: 10),
                    _navb(index: 1, label: '档案'),
                    const SizedBox(width: 10),
                    _navb(index: 2, label: '补给'),
                    const Spacer(),
                    RefTaskOrb(
                      key: const Key('ref.home.orb'),
                      label: widget.active ? '继续' : '委托',
                      small: 'TASK',
                      badge: widget.queue,
                      onTap: widget.onOrb,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// .navb（L163-173）：宽 66、环 60、标签 13px dim、可带 70 的进度弧
  Widget _navb({
    required int index,
    required String label,
    double? arc,
    String? sup,
  }) {
    return SizedBox(
      width: 66,
      child: GestureDetector(
        onTap: widget.onSide == null ? null : () => widget.onSide!(index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 70,
              height: 70,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  if (arc != null)
                    CustomPaint(
                      size: const Size(70, 70),
                      painter: _NavArcPainter(ratio: arc.clamp(0.0, 1.0)),
                    ),
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        center: Alignment(0, -.4),
                        radius: .9,
                        colors: <Color>[Color(0x14FFFFFF), Color(0x05FFFFFF)],
                      ),
                      border: Border.all(color: const Color(0x24FFFFFF)),
                    ),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CustomPaint(
                          painter: _NavIconPainter(kind: index),
                        ),
                      ),
                    ),
                  ),
                  if (sup != null)
                    Positioned(
                      right: -4,
                      top: -10,
                      child: Text(
                        sup,
                        style: refText(
                          family: Ref.fd,
                          size: 12,
                          wght: 700,
                          height: 1,
                          color: Ref.cyan,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: refText(
                family: Ref.fc,
                size: 13,
                wght: 500,
                height: 1,
                color: Ref.dim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// .orb-cap（L185）：右对齐 12px dim，数字 acid Chakra
  Widget _orbCap() {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: widget.active ? '她在等你' : '她手里有 ',
                style: refText(
                  family: Ref.fc,
                  size: 12,
                  wght: 500,
                  height: 1.3,
                  color: Ref.dim,
                ),
              ),
              TextSpan(
                text: widget.active ? ' 交差' : widget.queue.toString(),
                style: refText(
                  family: Ref.fd,
                  size: 12,
                  wght: 700,
                  height: 1.3,
                  color: Ref.acid,
                ),
              ),
              if (!widget.active)
                TextSpan(
                  text: ' 单',
                  style: refText(
                    family: Ref.fc,
                    size: 12,
                    wght: 500,
                    height: 1.3,
                    color: Ref.dim,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 7px 呼吸点（home-tag / active-pill 共用）
class _BreathDot extends StatefulWidget {
  const _BreathDot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  State<_BreathDot> createState() => _BreathDotState();
}

class _BreathDotState extends State<_BreathDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double s = widget.size;
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, Widget? _) => Opacity(
        opacity: 1 - .75 * Ref.ease.transform(_c.value),
        child: Container(
          width: s,
          height: s,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: <BoxShadow>[
              BoxShadow(color: widget.color, blurRadius: 10),
            ],
          ),
        ),
      ),
    );
  }
}

/// .navb .arc（L168-169）：70×70、2.5px cyan 弧 + 4px 辉光
class _NavArcPainter extends CustomPainter {
  const _NavArcPainter({required this.ratio});
  final double ratio;

  @override
  void paint(Canvas canvas, Size s) {
    final Offset c = s.center(Offset.zero);
    final double r = s.width / 2 - 2;
    final Rect rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Ref.a(Ref.cyan, .18),
    );
    if (ratio <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * ratio,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = Ref.a(Ref.cyan, .5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * ratio,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = Ref.cyan,
    );
  }

  @override
  bool shouldRepaint(_NavArcPainter o) => o.ratio != ratio;
}

/// 三颗侧键的线稿（主线 = 三层环 / 档案 = 六边 / 补给 = 箱子）
class _NavIconPainter extends CustomPainter {
  const _NavIconPainter({required this.kind});
  final int kind;

  @override
  void paint(Canvas canvas, Size s) {
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = Ref.txt;
    final Offset c = s.center(Offset.zero);
    if (kind == 0) {
      for (final (double rx, double ry, double dy)
          in <(double, double, double)>[
            (8, 3, -5),
            (10, 3.4, 0),
            (11.4, 3.8, 5),
          ]) {
        canvas.drawOval(
          Rect.fromCenter(
            center: c + Offset(0, dy),
            width: rx * 1.6,
            height: ry * 1.6,
          ),
          p,
        );
      }
    } else if (kind == 1) {
      final Path hex = Path();
      for (int i = 0; i < 6; i++) {
        final double a = -math.pi / 2 + i * math.pi / 3;
        final Offset o = c + Offset(math.cos(a), math.sin(a)) * 9;
        if (i == 0) {
          hex.moveTo(o.dx, o.dy);
        } else {
          hex.lineTo(o.dx, o.dy);
        }
      }
      hex.close();
      canvas.drawPath(hex, p);
      final Path inner = Path();
      for (int i = 0; i < 6; i++) {
        final double a = -math.pi / 2 + i * math.pi / 3;
        final Offset o = c + Offset(math.cos(a), math.sin(a)) * 4.2;
        if (i == 0) {
          inner.moveTo(o.dx, o.dy);
        } else {
          inner.lineTo(o.dx, o.dy);
        }
      }
      inner.close();
      canvas.drawPath(inner, p);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: c + const Offset(0, 2),
            width: 16,
            height: 11,
          ),
          const Radius.circular(2),
        ),
        p,
      );
      canvas.drawLine(c + const Offset(-8, -2), c + const Offset(8, -2), p);
      canvas.drawArc(
        Rect.fromCenter(center: c + const Offset(0, -5), width: 8, height: 7),
        math.pi,
        math.pi,
        false,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_NavIconPainter o) => o.kind != kind;
}
