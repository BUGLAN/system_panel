import 'dart:async';

import 'package:flutter/material.dart';

import '../data/content.dart';
import '../design/tokens.dart';

/// ═══════════════════════════════════════════════════════════
///  开机自检（app.css L524-540 `#boot` · flows.js `boot()`）
///  不是 logo 页，是一台正在启动的系统：日志在滚、进度在走、
///  底下写「触碰屏幕 · 唤醒系统」——点一下才开始。
/// ═══════════════════════════════════════════════════════════
class BootScreen extends StatefulWidget {
  const BootScreen({super.key, this.host, this.onWake});

  /// 存档里的宿主（`名字 · LV7`）；没有存档就是「未找到 · 新宿主」
  final String? host;

  /// 唤醒回调。原型里接的是整段醒来演出，目前只留给下一步接。
  final VoidCallback? onWake;

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> with TickerProviderStateMixin {
  static const int _maxLines = 5; // app.css L35：日志只留最近 5 行

  final List<String> _log = <String>[];
  double _bar = 0;
  int _tipIx = 0;
  bool _gone = false;
  String _clock = '--:--:--';

  Timer? _clockTimer;
  Timer? _tipTimer;
  late final AnimationController _breathe;
  late final AnimationController _goFade;

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _goFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _clock = _fmt(DateTime.now());
    _clockTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => setState(() => _clock = _fmt(DateTime.now())),
    );
    _tipTimer = Timer.periodic(const Duration(milliseconds: 3200), (_) {
      setState(() => _tipIx++);
    });
    _run();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _tipTimer?.cancel();
    _breathe.dispose();
    _goFade.dispose();
    super.dispose();
  }

  static String _fmt(DateTime d) => <String>[
    d.hour.toString().padLeft(2, '0'),
    d.minute.toString().padLeft(2, '0'),
    d.second.toString().padLeft(2, '0'),
  ].join(':');

  void _add(String line) {
    if (!mounted) return;
    setState(() {
      _log.add(line);
      while (_log.length > _maxLines) {
        _log.removeAt(0);
      }
    });
  }

  void _setBar(double v) {
    if (!mounted) return;
    setState(() => _bar = v);
  }

  /// 开机序列（flows.js L41-67 的节奏）
  Future<void> _run() async {
    _add('SYS//BOOT · 链路建立');
    _setBar(.08);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _add('字形载入 ✓');
    _setBar(.18);
    // 原型这一段由 Stage.init 的模型加载进度驱动；
    // 模型还没移植，先用一个「就绪」占位，bar 直接跳到 88%
    await Future<void>.delayed(const Duration(milliseconds: 700));
    _add('就绪');
    _setBar(.88);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _add(LINES.bootLog[0]);
    await Future<void>.delayed(const Duration(milliseconds: 160));
    _add(LINES.bootLog[2]);
    await Future<void>.delayed(const Duration(milliseconds: 160));
    _add(
      LINES.bootLog[3].replaceAll('{host}', widget.host ?? LINES.hostUnknown),
    );
    _setBar(1);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _add(LINES.bootLog[4]);
    if (!mounted) return;
    _goFade.forward(); // 唤醒提示淡入，随后一直呼吸
  }

  void _wake() {
    if (_gone) return;
    setState(() => _gone = true);
    widget.onWake?.call();
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle topStyle = fs(
      family: F.mono,
      size: 10,
      wght: 500,
      ls: 1.8,
      height: 1,
      color: C.bootTop,
    );
    final TextStyle subStyle = fs(
      family: F.hd,
      size: 13,
      wght: 400,
      ls: 9.1,
      height: 1,
      color: C.blue.withAlpha(153), // rgba(56,225,255,.6)
    );

    return AnimatedOpacity(
      opacity: _gone ? 0 : 1,
      duration: const Duration(milliseconds: 600),
      child: IgnorePointer(
        ignoring: _gone,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (TapDownDetails _) => _wake(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 38),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // .bt-top
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(LINES.bootTopLeft, style: topStyle),
                    Text(_clock, style: topStyle),
                  ],
                ),
                // .bt-mid
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(LINES.bootSub, style: subStyle),
                    ),
                  ),
                ),
                // .bt-low
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 150),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _logBlock(),
                      _barBlock(),
                      _tipBlock(),
                      _goBlock(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// .bt-log
  Widget _logBlock() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 92),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[for (final String line in _log) _LogLine(line)],
      ),
    );
  }

  /// .bt-bar
  Widget _barBlock() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        height: 2,
        decoration: BoxDecoration(
          color: const Color(0x1A38E1FF), // rgba(56,225,255,.1)
          borderRadius: BorderRadius.circular(1),
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: _bar),
          duration: const Duration(milliseconds: 500),
          curve: kOut,
          builder: (BuildContext _, double v, Widget? _) => Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: v.clamp(0, 1),
              // heightFactor 不给的话，无子元素的 DecoratedBox 会被量成 0 高（条就没了）
              heightFactor: 1,
              child: DecoratedBox(
                key: const Key('boot.bar.fill'),
                decoration: BoxDecoration(
                  color: C.blue,
                  borderRadius: BorderRadius.circular(1),
                  boxShadow: <BoxShadow>[
                    BoxShadow(color: C.blue, blurRadius: 10),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// .bt-tip
  Widget _tipBlock() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 16.8), // 1.4em
        child: Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: 'TIPS · ',
                style: fs(
                  family: F.mono,
                  size: 9,
                  wght: 600,
                  ls: 1.44,
                  color: C.blue,
                ),
              ),
              TextSpan(
                text: LINES.tips[_tipIx % LINES.tips.length],
                style: fs(family: F.cn, size: 12, wght: 400, color: C.bootLog),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// .bt-go —— ready 后淡入，然后一直呼吸
  Widget _goBlock() {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[_goFade, _breathe]),
        builder: (BuildContext _, Widget? _) {
          final double fade = Curves.easeInOut.transform(_goFade.value);
          final double breath = 1 - .65 * _breathe.value; // 1 → .35
          return Opacity(
            opacity: (fade * breath).clamp(0, 1),
            child: Padding(
              padding: const EdgeInsets.only(left: 4.8), // .3em
              child: Text(
                LINES.bootGo,
                textAlign: TextAlign.center,
                style: fs(
                  family: F.hd,
                  size: 16,
                  wght: 400,
                  ls: 4.8,
                  height: 1,
                  color: C.ice,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 一行日志：`› 文案`，其中 ✓ 是青色加粗（app.css L533）
class _LogLine extends StatelessWidget {
  const _LogLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final TextStyle base = fs(
      family: F.mono,
      size: 10.5,
      wght: 500,
      ls: .315,
      height: 1.75,
      color: C.bootLog,
    );
    final TextStyle hit = base.copyWith(
      color: C.blue,
      fontVariations: const <FontVariation>[FontVariation('wght', 600)],
    );

    final List<InlineSpan> spans = <InlineSpan>[
      TextSpan(text: '› ', style: base),
    ];
    final List<String> parts = text.split('✓');
    for (int i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) spans.add(TextSpan(text: parts[i], style: base));
      if (i < parts.length - 1) spans.add(TextSpan(text: '✓', style: hit));
    }

    // animation: fadeUp .3s var(--out) both
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: kOut,
      builder: (BuildContext _, double v, Widget? child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - v)),
          child: child,
        ),
      ),
      child: Text.rich(TextSpan(style: base, children: spans)),
    );
  }
}
