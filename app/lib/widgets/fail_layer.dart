import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// ═══════════════════════════════════════════════════════════
///  失败 / 补救（app.css L403-412 `#failv` + L71/88 的降调）
///  认输不是羞辱：画面压暗抽色、只有一句更短更轻的话，
///  然后**补救单已经摆在板上**——「做到了，这一笔划掉」。
///
///  实测盒模型（390×844）：
///    failv [0,0,390,844] · rec [0,84,390,10]
///    remedy [24,602,342,64]（kick 16 + 正文两行 20.8）
///    line [20,397,350,98] · choices [20,701,350,109]
/// ═══════════════════════════════════════════════════════════
class FailLayer extends StatefulWidget {
  const FailLayer({
    super.key,
    required this.recordedAt,
    this.timeout = false,
    this.remedy,
    this.visible = true,
    this.animate = true,
  });

  /// 认输/超时的时间（原型的 `hhmm(Clock.now())`）
  final String recordedAt;

  /// 是超时还是主动认输
  final bool timeout;

  /// 补救单；为空就只有上面那行记录
  final Remedy? remedy;

  final bool visible;

  /// 演出开关；比对截图时用 `false` 直接落终态
  final bool animate;

  @override
  State<FailLayer> createState() => _FailLayerState();
}

class _FailLayerState extends State<FailLayer>
    with SingleTickerProviderStateMixin {
  /// `#failv { opacity: 0; transition: opacity .6s }` → `.on { opacity: 1 }`
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
    value: 1,
  );

  /// `.fv-remedy { opacity:0; translateY(6px); transition: all .6s var(--out) }` —— 它是在
  /// 她那几句话之后才 `.on` 的；那几句话的时长属于业务，这里先给一个固定的 1.4s
  bool _remedyOn = true;

  @override
  void initState() {
    super.initState();
    if (widget.visible) _run();
  }

  /// 与派单板/结算卡同一个坑：这一层也一直挂在树里，演出要跟着"变可见"走
  @override
  void didUpdateWidget(covariant FailLayer old) {
    super.didUpdateWidget(old);
    if (!old.visible && widget.visible) _run();
  }

  void _run() {
    if (!widget.animate) {
      _fade.value = 1;
      _remedyOn = true;
      return;
    }
    _fade.forward(from: 0);
    _remedyOn = false;
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _remedyOn = true);
    });
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String recordedAt = widget.recordedAt;
    final bool timeout = widget.timeout;
    final Remedy? remedy = widget.remedy;
    if (!widget.visible) return const SizedBox.shrink();
    return Positioned.fill(
      child: Opacity(
        opacity: _fade.value,
        child: Stack(
          children: <Widget>[
            // .fv-rec
            Positioned(
              left: 0,
              right: 0,
              top: 84,
              child: Text.rich(
                key: const Key('fail.rec'),
                textAlign: TextAlign.center,
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: '${timeout ? '超时' : '认输'} · 已记录 ',
                      style: fs(
                        family: F.mono,
                        size: 10,
                        wght: 500,
                        ls: 2.4,
                        color: const Color(0xFF5D6B82),
                      ),
                    ),
                    TextSpan(
                      text: recordedAt,
                      style: fs(
                        family: F.mono,
                        size: 10,
                        wght: 600,
                        ls: 2.4,
                        color: const Color(0xFF8794AA),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // .fv-remedy
            if (remedy != null)
              Positioned(
                left: 24,
                right: 24,
                bottom: 178,
                child: AnimatedSlide(
                  offset: _remedyOn ? Offset.zero : const Offset(0, .06),
                  duration: const Duration(milliseconds: 600),
                  curve: const Cubic(.16, 1, .3, 1), // --out
                  child: AnimatedOpacity(
                    opacity: _remedyOn ? 1 : 0,
                    duration: const Duration(milliseconds: 600),
                    child: Column(
                      key: const Key('fail.remedy'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '补救 · REMEDY',
                          style: fs(
                            family: F.mono,
                            size: 10,
                            wght: 400,
                            ls: 1.6,
                            height: 1.6, // 继承 .fv-remedy 的 line-height
                            color: C.blue.withAlpha(204), // opacity .8
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text.rich(
                          TextSpan(
                            children: <InlineSpan>[
                              TextSpan(
                                text: remedy.name,
                                style: fs(
                                  family: F.cn,
                                  size: 13,
                                  wght: 600,
                                  height: 1.6,
                                  color: C.blue,
                                ),
                              ),
                              TextSpan(
                                text:
                                    '（做一半）· ${remedy.minutesText}\n截止 ${remedy.deadline} · '
                                    '${remedy.rank} 级 · 做到了，这一笔划掉',
                                style: fs(
                                  family: F.cn,
                                  size: 13,
                                  wght: 400,
                                  height: 1.6,
                                  color: const Color(0xFF9FB3CC),
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
          ],
        ),
      ),
    );
  }
}

/// 补救单 —— 原型的 `info.remedy`
class Remedy {
  const Remedy({
    required this.name,
    required this.minutes,
    required this.deadline,
    required this.rank,
  });

  /// 做一半的那个动作
  final String name;

  /// 补救时限（分钟）
  final int minutes;

  /// 「明天 20:02」这样的字面
  final String deadline;

  final String rank;

  /// util.js `fmtMin`
  String get minutesText {
    if (minutes < 60) return '$minutes 分钟';
    if (minutes % 60 != 0) return '${minutes ~/ 60} 小时 ${minutes % 60} 分';
    return '${minutes ~/ 60} 小时';
  }

  /// 与原型演示态一致的那张补救单
  static const Remedy demo = Remedy(
    name: '跑完 8 公里，跑后拉伸 10 分钟',
    minutes: 35,
    deadline: '明天 20:02',
    rank: 'D',
  );
}

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
