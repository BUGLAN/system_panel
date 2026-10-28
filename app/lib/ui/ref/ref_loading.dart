import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/ref.dart';
import 'ref_core.dart';
import 'ref_motion.dart';

/// ═══════════════════════════════════════════════════════════
///  加载态（docs/49 D）—— 参考稿没有这一块，按它的语言补：
///
///  · [RefSpinner]     —— 小号转圈（证据槽「校验中」/ 按钮内）
///  · [RefScanBar]     —— 不定进度扫描条（.tbar 的轨道 + 一段 accent 光带来回扫）
///  · [RefPlanLoading] —— 「SYSTEM 正在拆解」加载卡：核心 + 扫描条 + 分步进度
///                        + 计时 + 她的等待台词。绑定仪式 / 换目标 / 收官结算共用。
///
///  为什么要有它：拆解走 LLM（匹配 + 拆解 + 校验），常见 10~60 秒。原来这段时间
///  屏幕上什么都不动，按钮还能连点 —— 宿主的原话是「像卡住了一样」。
///
///  减弱动态效果：扫描条停在中段、转圈停住，文字与计时照常（信息不降级）。
/// ═══════════════════════════════════════════════════════════

bool _reduceOf(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// 小号转圈：一段 270° 的弧，900ms 一圈
class RefSpinner extends StatefulWidget {
  const RefSpinner({
    super.key,
    this.size = 18,
    this.color = Ref.acid,
    this.stroke = 2,
  });

  final double size;
  final Color color;
  final double stroke;

  @override
  State<RefSpinner> createState() => _RefSpinnerState();
}

class _RefSpinnerState extends State<RefSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _c,
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _ArcPainter(color: widget.color, stroke: widget.stroke),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter({required this.color, required this.stroke});

  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size s) {
    final Rect r = Offset.zero & s;
    final Rect arc = r.deflate(stroke / 2);
    canvas.drawCircle(
      r.center,
      arc.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Ref.a(color, .16),
    );
    canvas.drawArc(
      arc,
      -math.pi / 2,
      math.pi * 1.5,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: <Color>[Ref.a(color, 0), color],
          stops: const <double>[0, .75],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(arc),
    );
  }

  @override
  bool shouldRepaint(_ArcPainter o) => o.color != color || o.stroke != stroke;
}

/// 不定进度扫描条：轨道 rgba(255,255,255,.07)，一段 34% 宽的 accent 光带
/// 1.4s 往返一趟（ease-in-out），带 10px 辉光。只改 Transform，不重画轨道。
class RefScanBar extends StatefulWidget {
  const RefScanBar({super.key, this.color = Ref.acid, this.height = 4});

  final Color color;
  final double height;

  @override
  State<RefScanBar> createState() => _RefScanBarState();
}

class _RefScanBarState extends State<RefScanBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceOf(context)) {
      _c.value = .5;
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
    final double h = widget.height;
    return ClipRRect(
      borderRadius: BorderRadius.circular(h / 2),
      child: SizedBox(
        height: h,
        child: LayoutBuilder(
          builder: (BuildContext _, BoxConstraints box) {
            final double w = box.maxWidth;
            final double seg = w * .34;
            final Widget glow = Container(
              width: seg,
              height: h,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(h / 2),
                gradient: LinearGradient(
                  colors: <Color>[
                    Ref.a(widget.color, 0),
                    widget.color,
                    Ref.a(widget.color, 0),
                  ],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(color: Ref.a(widget.color, .6), blurRadius: 10),
                ],
              ),
            );
            return Stack(
              children: <Widget>[
                const Positioned.fill(
                  child: ColoredBox(color: Color(0x12FFFFFF)),
                ),
                AnimatedBuilder(
                  animation: _c,
                  child: glow,
                  builder: (BuildContext _, Widget? child) {
                    final double t = Curves.easeInOut.transform(_c.value);
                    return Transform.translate(
                      offset: Offset(-seg + (w + seg) * t, 0),
                      child: child,
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 「SYSTEM 正在拆解」加载卡。
///
/// [stage] = 当前进行到第几步（0 起；`>= steps.length` = 全部完成）。
/// 计时从 [startedAt] 起算（不传就从挂载起算），每秒一跳。
/// 她的等待台词每 [quipEvery] 换一句（[quips] 为空就不显示）。
class RefPlanLoading extends StatefulWidget {
  const RefPlanLoading({
    super.key,
    required this.steps,
    this.stage = 0,
    this.eyebrow = 'PROCESSING · 拆解中',
    this.title = 'SYSTEM 正在拆解',
    this.goal,
    this.startedAt,
    this.accent = Ref.acid,
    this.quips = kPlanQuips,
    this.quipEvery = const Duration(milliseconds: 4200),
  });

  final List<String> steps;
  final int stage;
  final String eyebrow;
  final String title;

  /// 正在处理的那句目标（引号括起来显示；null 不显示）
  final String? goal;
  final DateTime? startedAt;
  final Color accent;
  final List<String> quips;
  final Duration quipEvery;

  /// 默认的等待台词（毒舌但靠谱：她在干活，不是在发呆）
  static const List<String> kPlanQuips = <String>[
    '别催。拆东西要时间。',
    '我在逐字读你那句话。',
    '规则校验比你想的严。',
    '在排先后顺序……谁先谁后很重要。',
    '再等等，快好了——大概。',
  ];

  @override
  State<RefPlanLoading> createState() => _RefPlanLoadingState();
}

class _RefPlanLoadingState extends State<RefPlanLoading> {
  late final DateTime _t0 = widget.startedAt ?? DateTime.now();
  Timer? _tick;
  int _sec = 0;
  int _quip = 0;

  @override
  void initState() {
    super.initState();
    _sec = DateTime.now().difference(_t0).inSeconds;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final int s = DateTime.now().difference(_t0).inSeconds;
      final int every = math.max(1, widget.quipEvery.inSeconds);
      setState(() {
        _sec = s;
        if (widget.quips.isNotEmpty && s > 0 && s % every == 0) {
          _quip = (_quip + 1) % widget.quips.length;
        }
      });
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String get _clock {
    final int m = _sec ~/ 60;
    final int s = _sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final Color acc = widget.accent;
    final bool reduce = _reduceOf(context);
    return Semantics(
      liveRegion: true,
      label:
          '${widget.title}，第 ${math.min(widget.stage + 1, widget.steps.length)} 步',
      child: Container(
        key: const Key('ref.planLoading'),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment(-.94, -.34),
            end: Alignment(.94, .34),
            colors: <Color>[Color(0xFF1F1A36), Color(0xFF0E0C19)],
          ),
          border: Border.all(color: Ref.a(acc, .28)),
          boxShadow: <BoxShadow>[
            BoxShadow(color: Ref.a(acc, .14), blurRadius: 28, spreadRadius: -6),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                RefCore(
                  size: 46,
                  mood: CoreMood.neutral,
                  accent: acc,
                  animate: !reduce,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          RefBlink(
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: acc,
                                boxShadow: <BoxShadow>[
                                  BoxShadow(color: acc, blurRadius: 8),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.eyebrow,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: refText(
                                family: Ref.fm,
                                size: 10,
                                wght: 700,
                                ls: 3,
                                height: 1.2,
                                color: acc,
                              ),
                            ),
                          ),
                          Text(
                            _clock,
                            key: const Key('ref.planLoading.clock'),
                            style: refText(
                              family: Ref.fm,
                              size: 12,
                              wght: 600,
                              height: 1.2,
                              color: Ref.dim,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.title,
                        style: refText(
                          size: 18,
                          wght: 900,
                          height: 1.25,
                          color: Ref.txt,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (widget.goal != null &&
                widget.goal!.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                '「${widget.goal!.trim()}」',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: refText(
                  size: 14,
                  wght: 500,
                  height: 1.5,
                  color: Ref.txt,
                ),
              ),
            ],
            const SizedBox(height: 14),
            RefScanBar(color: acc),
            const SizedBox(height: 14),
            for (int i = 0; i < widget.steps.length; i++)
              _step(i, widget.steps[i], acc),
            if (widget.quips.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Ref.ease,
                transitionBuilder: (Widget c, Animation<double> a) =>
                    FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, .3),
                          end: Offset.zero,
                        ).animate(a),
                        child: c,
                      ),
                    ),
                child: Text(
                  widget.quips[_quip % widget.quips.length],
                  key: ValueKey<int>(_quip),
                  style: refText(
                    size: 13,
                    wght: 500,
                    height: 1.5,
                    color: Ref.dim,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 一行步骤：已完成 ✓（薄荷）/ 进行中 转圈（accent）/ 未开始 空心点（dim2）
  Widget _step(int i, String label, Color acc) {
    final bool done = i < widget.stage;
    final bool cur = i == widget.stage;
    final Color c = done ? Ref.mint : (cur ? Ref.txt : Ref.dim2);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 18,
            height: 18,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: done
                    ? const Icon(
                        Icons.check_rounded,
                        key: ValueKey<String>('done'),
                        size: 16,
                        color: Ref.mint,
                      )
                    : cur
                    ? RefSpinner(
                        key: const ValueKey<String>('cur'),
                        size: 14,
                        color: acc,
                      )
                    : Container(
                        key: const ValueKey<String>('todo'),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Ref.dim2, width: 1.5),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 260),
              style: refText(
                size: 14,
                wght: cur ? 700 : 500,
                height: 1.3,
                color: c,
              ),
              child: Text(label),
            ),
          ),
          Text(
            '0${i + 1}',
            style: refText(
              family: Ref.fm,
              size: 10,
              wght: 600,
              ls: 1,
              height: 1,
              color: done ? Ref.a(Ref.mint, .7) : Ref.dim2,
            ),
          ),
        ],
      ),
    );
  }
}
