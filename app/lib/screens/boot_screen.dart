import 'dart:async';

import 'package:flutter/material.dart';

import '../data/content.dart';
import '../design/tokens.dart';

/// 日志行的入场时长 —— app.css L534 `.bt-log div { animation: fadeUp .3s var(--out) }`。
/// 快进时「先铺完日志、再演唤醒」的那一拍也用它：铺完的行先把入场走完，唤醒才接管画面。
/// （不等的后果就是快进一闪而过 ≈ 还是把日志跳掉了，正是 docs/22 §R5 要修的那个问题。）
const Duration _kLineIn = Duration(milliseconds: 300);

/// 进度条走一格的时长 —— app.css L537 `.bt-bar i { transition: width .5s var(--out) }`。
/// ⚠️ 这个常量**一物两用**：既喂进度条的 TweenAnimationBuilder，又是「进度条打到 100%」
/// 到「唤醒序列就绪」之间的间隔。依据是原型 flows.js L53-63：先 `bar.style.width='100%'`，
/// `await sleep(500)` 之后才 `add(LINES.bootLog[4])` —— 两个 500ms 在原版里本来就是同一个数
/// （CSS 过渡时长 = 那一拍 sleep），所以「条走满」与「最后一行落下」是同一拍。
/// 移植后靠这一个共享常量保住对齐，不靠手感调参；真机上只差 1 帧（ticker 首次 tick 在下一帧）。
const Duration _kBarTravel = Duration(milliseconds: 500);

/// 开机脚本的一步：落一行日志 / 推一次进度条，`hold` 之后走下一步
class _Step {
  const _Step({this.line, this.bar, this.hold = Duration.zero});

  final String? line;
  final double? bar;
  final Duration hold;
}

/// ═══════════════════════════════════════════════════════════
///  开机自检（app.css L524-540 `#boot` · flows.js `boot()`）
///  不是 logo 页，是一台正在启动的系统：日志在滚、进度在走、
///  底下写「触碰屏幕 · 唤醒系统」——点一下才开始。
///  门禁（docs/22 §R5 裁决 D-m）：点任意处 = 触发唤醒这一拍；
///  日志没滚完就先快进再唤醒，演出开始后不可二次跳过。
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
  String _clock = '--:--:--';

  /// 开机脚本 + 游标（`_cursor` = 下一步的序号）
  List<_Step> _script = const <_Step>[];
  int _cursor = 0;
  Timer? _stepTimer;

  /// 日志滚完（最后一拍已落）→ 门禁走「点一下 = 直接唤醒」那条路
  bool _ready = false;

  /// 门禁放行闩：**一次点击定生死**。快进的 300ms 节拍里再点也不会插队，
  /// 因为闩在第一次点击时就落下了；两条唤醒路径都锁在它后面。
  bool _gate = false;

  /// 唤醒演出已经开始（画面淡出 + 不再收点击）—— 现有语义，保留：不可二次跳过
  bool _gone = false;

  Timer? _ffTimer;
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
    _stepTimer?.cancel();
    _ffTimer?.cancel();
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

  /// 开机脚本（原型 flows.js L41-64 的节奏）。
  /// 原型真值的三个间隔一律不动：160 / 160 / `_kBarTravel`；
  /// 收紧的只是移植时自己造的两处占位：字形 300 → 240（Flutter 字体随包，不用 await 字体表）、
  /// 模型就绪 700 → 560（原型这一段由 Stage.init 的模型加载进度驱动，模型还没移植）。
  /// 总时长 2020 → 1780ms。
  List<_Step> _buildScript() => <_Step>[
    const _Step(
      line: 'SYS//BOOT · 链路建立',
      bar: .08,
      hold: Duration(milliseconds: 240),
    ),
    const _Step(
      line: '字形载入 ✓',
      bar: .18,
      hold: Duration(milliseconds: 560),
    ),
    // 原型这一段由 Stage.init 的模型加载进度驱动（bar 18% → 88%）；
    // 模型还没移植，先用一个「就绪」占位，bar 直接跳到 88%
    const _Step(line: '就绪', bar: .88, hold: Duration(milliseconds: 160)),
    _Step(line: LINES.bootLog[0], hold: const Duration(milliseconds: 160)),
    _Step(line: LINES.bootLog[2], hold: const Duration(milliseconds: 160)),
    _Step(
      line: LINES.bootLog[3].replaceAll(
        '{host}',
        widget.host ?? LINES.hostUnknown,
      ),
      bar: 1,
      hold: _kBarTravel, // 与进度条走格同源 → 最后一行落下时条正好走满
    ),
    _Step(line: LINES.bootLog[4]), // 「唤醒序列就绪」
  ];

  void _run() {
    _script = _buildScript();
    _step();
  }

  /// 走一步。第一次调用 = 脚本第一步立即执行（`initState` 里同步落第一行），
  /// 之后每一步由上一步的 `hold` 定时器推进。
  void _step() {
    if (!mounted || _cursor >= _script.length) return;
    final _Step s = _script[_cursor++];
    setState(() => _apply(s));
    if (_cursor >= _script.length) {
      _ready = true;
      _goFade.forward(); // 唤醒提示淡入，随后一直呼吸
      return;
    }
    _stepTimer = Timer(s.hold, _step);
  }

  /// 落一步的内容（不 setState，由调用方决定是「一步一帧」还是「快进一帧全铺」）
  void _apply(_Step s) {
    final String? line = s.line;
    if (line != null) {
      _log.add(line);
      while (_log.length > _maxLines) {
        _log.removeAt(0);
      }
    }
    final double? bar = s.bar;
    if (bar != null) _bar = bar;
  }

  /// 门禁（docs/22 §R5 裁决 D-m）：**点任意处 = 触发唤醒这一拍**
  /// · 日志没滚完 → 先把剩下的铺完（快进），等行入场走完（`_kLineIn`）再演唤醒；
  /// · 日志已滚完 → 直接唤醒（不多等一拍）；
  /// · 演出开始后不可二次跳过 —— `_gate` 一落，后面所有点击都进不来。
  void _tap() {
    if (_gate) return;
    _gate = true;
    if (_ready) {
      _wake();
      return;
    }
    _fastForward();
    _ffTimer = Timer(_kLineIn, _wake);
  }

  /// 快进：把脚本里**剩下的每一步在同一帧铺完**（日志一次补齐到最终 5 行、进度条一次打满），
  /// 已经落好的行不动。所以快进后日志区就是终态，不是中途状态。
  void _fastForward() {
    _stepTimer?.cancel();
    _stepTimer = null;
    setState(() {
      while (_cursor < _script.length) {
        _apply(_script[_cursor++]);
      }
    });
    if (!_ready) {
      _ready = true;
      _goFade.forward();
    }
  }

  /// `onWake` 的**唯一**调用点：门禁闩 `_gate` 保证引到它的路径只有一条，
  /// `_gone` 再兜一层 —— 整个生命周期最多一次。
  void _wake() {
    if (!mounted || _gone) return;
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
          // 原型是 `pointerdown`（flows.js L65）——按下即算，不等抬手
          onTapDown: (TapDownDetails _) => _tap(),
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

  /// .bt-bar —— 走格时长 = `_kBarTravel`，与「最后一行」的间隔同源（见文件头注释）
  Widget _barBlock() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        // 轨道整体宽度：对齐证据用它当分母（fill / 轨道 = 走格比例）
        key: const Key('boot.bar'),
        height: 2,
        decoration: BoxDecoration(
          color: const Color(0x1A38E1FF), // rgba(56,225,255,.1)
          borderRadius: BorderRadius.circular(1),
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: _bar),
          duration: _kBarTravel,
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

    // animation: fadeUp .3s var(--out) both（`_kLineIn` 与快进节拍同源）
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: _kLineIn,
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
