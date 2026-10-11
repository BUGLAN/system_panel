import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../design/tokens.dart';
import '../state/haptics.dart';
import '../state/host_state.dart';
import '../state/sfx.dart';
import 'sys_icons.dart';

/// ═══════════════════════════════════════════════════════════
///  底栏（app.css L208-240 `#dock`）
///  三颗侧键 + 中央委托环 + 底注。
///  实测盒模型（390×844）：dock [0,696,390,148] · side [18,749,186,69]
///  · dk 三颗 x=18/82/146 各 58×63 · cta [268,712,104,104]
///  · core [276,720,88,88] · cta-n [346,714,24,24] · cap [268,823,104,13]
/// ═══════════════════════════════════════════════════════════
class Dock extends StatelessWidget {
  const Dock({
    super.key,
    required this.state,
    this.visible = true,
    this.onCta,
    this.onSide,
    this.fade,
  });

  /// 唤醒过场用的淡入动画（0→1）。⚠️ 必须**在本组件内部**套 Opacity：
  /// 本 build 顶层是 `Positioned`（ParentDataWidget），外面再包一层带
  /// RenderObject 的包装件会报 `Incorrect use of ParentDataWidget`
  /// （2026-08-11 实测：HUD 与底栏各抛一次）。
  final Animation<double>? fade;

  /// 点了哪颗侧键（0 主线 / 1 档案 / 2 补给）
  final ValueChanged<int>? onSide;

  final HostState state;

  /// 开机中 / 聚焦态 / 面板态时整条底栏下沉隐藏（app.css L211）
  final bool visible;

  /// 点中央那颗委托环
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    final bool running = false; // 有执行中的任务时中央环变成计时器（后续步骤接）
    final bool idle = !running && state.queue == 0;

    Widget body = IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 1.20),
          duration: const Duration(milliseconds: 550),
          curve: kOut,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 400),
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                // #dock::before —— 底部的暗场，让字浮起来
                Positioned(
                  left: 0,
                  right: 0,
                  top: -40,
                  bottom: 0,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            const Color(0x0002050C),
                            const Color(0xD102050C),
                          ],
                          stops: const <double>[0, .62],
                        ),
                      ),
                    ),
                  ),
                ),
                // 内容整体吸底：Stack 默认顶端对齐，不撑满就会浮到上面去
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 26),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            _SideKeys(onSide: onSide),
                            _Cta(
                              state: state,
                              running: running,
                              idle: idle,
                              onTap: onCta,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // .cta-cap
                Positioned(
                  right: 18,
                  bottom: 8,
                  width: 104,
                  child: Text(
                    key: const Key('dock.cap'),
                    _cap(running, idle),
                    textAlign: TextAlign.center,
                    style: fs(
                      family: F.cn,
                      size: 10,
                      wght: 400,
                      ls: .6,
                      color: C.mist,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    if (fade != null) {
      final Animation<double> f = fade!;
      body = AnimatedBuilder(
        animation: f,
        builder: (BuildContext _, Widget? c) => Opacity(
          opacity: Curves.easeOut.transform(f.value.clamp(0.0, 1.0)),
          child: c,
        ),
        child: body,
      );
    }
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 148,
      child: body,
    );
  }

  String _cap(bool running, bool idle) {
    if (running) return '点开 · 继续';
    if (idle) return '换日还有 0 小时';
    return '她手里有 ${state.queue} 单';
  }
}

/// .dk-side —— 主线 / 档案 / 补给
class _SideKeys extends StatelessWidget {
  const _SideKeys({this.onSide});

  /// 点了哪颗侧键（0 主线 / 1 档案 / 2 补给）
  final ValueChanged<int>? onSide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          _Dk(
            key: const Key('dock.key.main'),
            label: '主线',
            svg: kIconMain,
            onTap: onSide == null ? null : () => onSide!(0),
          ),
          const SizedBox(width: 6),
          _Dk(
            key: const Key('dock.key.archive'),
            label: '档案',
            svg: kIconArchive,
            onTap: onSide == null ? null : () => onSide!(1),
          ),
          const SizedBox(width: 6),
          _Dk(
            key: const Key('dock.key.supply'),
            label: '补给',
            svg: kIconSupply,
            onTap: onSide == null ? null : () => onSide!(2),
          ),
        ],
      ),
    );
  }
}

class _Dk extends StatefulWidget {
  const _Dk({super.key, required this.label, required this.svg, this.onTap});

  final String label;
  final String svg;
  final VoidCallback? onTap;

  @override
  State<_Dk> createState() => _DkState();
}

class _DkState extends State<_Dk> {
  /// `.dk:active .ic` —— 按下时**只缩图标圈**（文字标签不缩），并加一层青光
  bool _down = false;

  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 底栏/侧键的点按：原型 `main.js:53` 只 `Sound.play('tap')`（无震动）
      onTap: widget.onTap == null
          ? null
          : () {
              Sfx.play('tap');
              widget.onTap!();
            },
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapUp: widget.onTap == null ? null : (_) => _set(false),
      onTapCancel: widget.onTap == null ? null : () => _set(false),
      behavior: HitTestBehavior.opaque,
      child: _dkBody(context),
    );
  }

  Widget _dkBody(BuildContext context) {
    return SizedBox(
      width: 58,
      child: Column(
        children: <Widget>[
          Transform.scale(
            scale: _down ? .9 : 1,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x99061024), // rgba(6,16,36,.6)
                border: Border.all(color: C.line, width: 1),
                // `.dk:active .ic { box-shadow: inset 0 0 0 1px var(--blue),
                //                   0 0 16px rgba(56,225,255,.4) }`
                boxShadow: _down
                    ? <BoxShadow>[
                        BoxShadow(color: C.blue.withAlpha(102), blurRadius: 16),
                      ]
                    : null,
              ),
              child: Center(
                child: SvgPicture.string(widget.svg, width: 21, height: 21),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.label,
            style: fs(
              family: F.cn,
              size: 11,
              wght: 500,
              ls: 1.1,
              color: C.mist,
            ),
          ),
        ],
      ),
    );
  }
}

/// .cta —— 中央那颗会呼吸的委托环（app.css L218-240）
class _Cta extends StatefulWidget {
  const _Cta({
    required this.state,
    required this.running,
    required this.idle,
    this.onTap,
  });

  final HostState state;
  final bool running;
  final bool idle;
  final VoidCallback? onTap;

  @override
  State<_Cta> createState() => _CtaState();
}

class _CtaState extends State<_Cta> {
  /// `.cta:active .cta-core { transform: scale(.92) }` —— 只缩芯，
  /// 外面那圈 18s 转一圈的轨道**不缩**
  bool _down = false;

  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final HostState state = widget.state;
    final bool running = widget.running;
    final bool idle = widget.idle;
    final VoidCallback? onTap = widget.onTap;
    // .cta 有 margin-bottom: 2（外边距，不是内边距）
    return GestureDetector(
      // 主 CTA：原型 `main.js:47-48` `Sound.play('tap'); buzz(8)` ——
      // **全原型唯一带震动的 tap**（底栏/侧键/HUD 那些只有声音）。
      // 这是 docs/22 R3「15 处波形」里 tap 那一处的真实出处。
      onTap: onTap == null
          ? null
          : () {
              Sfx.play('tap');
              Haptics.buzz('tap');
              onTap();
            },
      onTapDown: onTap == null ? null : (_) => _set(true),
      onTapUp: onTap == null ? null : (_) => _set(false),
      onTapCancel: onTap == null ? null : () => _set(false),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: SizedBox(
          key: const Key('dock.cta'),
          width: 104,
          height: 104,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              // .cta-orbit：inset -8 → 120×120，18s 转一圈
              Positioned(
                left: -8,
                top: -8,
                width: 120,
                height: 120,
                child: const _Orbit(),
              ),
              // .cta-core：inset 8 → 88×88
              Positioned(
                left: 8,
                top: 8,
                right: 8,
                bottom: 8,
                child: Transform.scale(
                  scale: _down ? .92 : 1,
                  child: _Core(running: running, idle: idle),
                ),
              ),
              // .cta-n
              if (!running && !idle)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    key: const Key('dock.cta.n'),
                    constraints: const BoxConstraints(minWidth: 24),
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: C.voidBg,
                          spreadRadius: 3,
                          blurRadius: 0,
                        ),
                        BoxShadow(
                          color: Colors.white.withAlpha(153),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        '${state.queue}',
                        style: fs(
                          family: F.num,
                          size: 13,
                          wght: 800,
                          height: 1,
                          color: C.deep,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 两条虚线圆环：外圈细密，内圈是一段长弧（app.css L220-223）
class _Orbit extends StatefulWidget {
  const _Orbit();

  @override
  State<_Orbit> createState() => _OrbitState();
}

class _OrbitState extends State<_Orbit> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _spin,
      builder: (BuildContext _, Widget? _) => Transform.rotate(
        angle: _spin.value * 2 * math.pi,
        child: const CustomPaint(painter: _OrbitPainter()),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  const _OrbitPainter();

  @override
  void paint(Canvas canvas, Size s) {
    // viewBox 120×120 → 盒子的实际尺寸
    final double k = s.width / 120;
    final Offset c = Offset(s.width / 2, s.height / 2);
    _dashed(canvas, c, 56 * k, 1 * k, 3 * k, 9 * k, C.blue.withAlpha(153), 0);
    // 内圈带 drop-shadow 辉光
    final Paint glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 * k
      ..strokeCap = StrokeCap.butt
      ..color = C.blue.withAlpha(230)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    _dashed(
      canvas,
      c,
      49 * k,
      1.4 * k,
      62 * k,
      246 * k,
      C.blue.withAlpha(230),
      0,
      glow: glow,
    );
  }

  /// 按「弧长」切虚线（CSS 的 stroke-dasharray 就是弧长）
  void _dashed(
    Canvas canvas,
    Offset c,
    double r,
    double sw,
    double dash,
    double gap,
    Color color,
    double phase, {
    Paint? glow,
  }) {
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..color = color;
    final double circ = 2 * math.pi * r;
    final double period = dash + gap;
    final Rect rect = Rect.fromCircle(center: c, radius: r);
    for (double start = phase; start < phase + circ; start += period) {
      final double a0 = (start / r) - math.pi / 2;
      final double a1 = ((start + dash) / r) - math.pi / 2;
      if (glow != null) canvas.drawArc(rect, a0, a1 - a0, false, glow);
      canvas.drawArc(rect, a0, a1 - a0, false, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// .cta-core —— 主态是发光青球，run/idle 态换成玻璃球（app.css L224-240）
class _Core extends StatefulWidget {
  const _Core({required this.running, required this.idle});

  final bool running;
  final bool idle;

  @override
  State<_Core> createState() => _CoreState();
}

class _CoreState extends State<_Core> with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool plain = widget.running || widget.idle;
    return AnimatedBuilder(
      animation: _breath,
      builder: (BuildContext _, Widget? _) {
        final double t = Curves.easeInOut.transform(_breath.value);
        return Container(
          key: const Key('dock.cta.core'),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: plain ? const Color(0xCC040E20) : null,
            gradient: plain
                ? null
                : const RadialGradient(
                    center: Alignment(0, -0.4),
                    radius: .78,
                    colors: <Color>[
                      Color(0xFF9CF1FF),
                      Color(0xFF38E1FF),
                      Color(0xFF1D8FE8),
                    ],
                    stops: <double>[0, .38, 1],
                  ),
            // 外发光（CSS 的 inset 阴影不能用 BoxShadow 表达，放在下面的 ClipOval 里画）
            boxShadow: plain
                ? <BoxShadow>[
                    if (widget.running)
                      BoxShadow(color: C.blue.withAlpha(77), blurRadius: 26)
                    else
                      BoxShadow(color: C.line, spreadRadius: 1, blurRadius: 0),
                  ]
                : <BoxShadow>[
                    BoxShadow(
                      color: C.blue.withAlpha((31 - 11 * t).round()),
                      spreadRadius: 4 + 3 * t,
                    ),
                    BoxShadow(
                      color: C.blue.withAlpha((140 + 40 * t).round()),
                      blurRadius: 34 + 12 * t,
                    ),
                  ],
          ),
          // inset 0 -8px 18px rgba(2,40,90,.45) —— 球体下缘的暗面
          // inset 0 2px 4px rgba(255,255,255,.55) —— 球体顶部的白高光
          child: ClipOval(
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                if (!plain) ...<Widget>[
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            const Color(0x0002285A),
                            const Color(0x0002285A),
                            const Color(0x7302285A),
                          ],
                          stops: const <double>[0, .58, 1],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            const Color(0x8CFFFFFF),
                            const Color(0x00FFFFFF),
                          ],
                          stops: const <double>[0, .085],
                        ),
                      ),
                    ),
                  ),
                ],
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      widget.running
                          ? '00:00'
                          : widget.idle
                          ? '今日已清'
                          : '委托',
                      style: widget.running
                          ? fs(
                              family: F.num,
                              size: 22,
                              wght: 800,
                              ls: .44,
                              height: 1,
                              color: C.ice,
                            )
                          : widget.idle
                          ? fs(
                              family: F.hd,
                              size: 15,
                              wght: 400,
                              ls: 1.2,
                              height: 1,
                              color: C.mist,
                            )
                          : fs(
                              family: F.hd,
                              size: 21,
                              wght: 400,
                              ls: 1.68, // .08em
                              height: 1,
                              color: C.deep,
                            ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.running
                          ? '执行中'
                          : widget.idle
                          ? ''
                          : 'TASK',
                      style: fs(
                        family: F.mono,
                        size: 9,
                        wght: 700,
                        ls: 1.08,
                        height: 1,
                        color: plain ? C.blue : C.deep.withAlpha(179),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
