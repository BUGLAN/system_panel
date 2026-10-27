import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../design/ref.dart';
import 'ref_kit.dart';

/// ═══════════════════════════════════════════════════════════
///  验收幕 —— 两阶段（.vd-scan → .vd-res）叠在同一块半透明幕里
///
///  唯一基准：宿主养成系统_重设计.html
///    · CSS  L421-449（verdict）/ L406（.ovl 幕）
///    · DOM  L802-818
///    · 时序 L1487-1538（scan 21 步 × 80ms → 暴击横幅 380ms → 砸印 440ms
///      → 逐行 +380ms 滚动 / 70ms 间隔 → 经验条 700ms → 「收下」320ms）
///
///  【布局契约】本组件顶层是「整屏矩形」（不是 Positioned），调用方负责塞进
///  Stack：
///
///  ```dart
///  Stack(children: <Widget>[
///    page,
///    if (showVerdict) Positioned.fill(child: RefVerdict(...)),
///  ])
///  ```
///
///  【动效契约】五条控制器全部在 State 里、dispose 释放；阶段 Timer 在
///  dispose 与重排时 cancel；`MediaQuery.maybeDisableAnimationsOf` 为真时
///  **不跑任何循环**，直接落「结果态终值」（进度 100% / 横幅归位 /
///  奖励全出 / 经验条满格 / 按钮可见）。
///
///  音效与震动由调用方编排（JS L1506 的 SFX.scan 每 80ms 一发属于业务层，
///  放进组件里会与调用方重复触发），本文件不碰 Sfx / Haptics。
/// ═══════════════════════════════════════════════════════════

/// 验收幕的两个阶段（参考稿 .vd-scan / .vd-res 的 display 开关，L422-423）
enum RefVerdictPhase { scan, result }

/// 结算奖励行（`.rw .r` L442-444）
///
/// · 左：`500 14px` 中文标签，可带一枚 `11px` mono hot 边框小标（`<em>`）
/// · 右：`700 20px 'Chakra Petch'` acid 数值，进场时从 +0 滚到 +value
class RefRewardRow {
  const RefRewardRow({required this.label, required this.value, this.tag});

  final String label;
  final int value;

  /// 数值后的角标：×2 / ×1.5 / CRIT / TODAY（JS L1521-1522）
  final String? tag;
}

/// `.ovl`（L406）：`rgba(4,3,10,.84)` + `backdrop-filter: blur(12px)`
const Color _kOvlBg = Color(0xD604030A); // .84 × 255 ≈ 214 = 0xD6

/// `.vd-frame`（L424）：220×150 / r14 / 1.5px acid / 0 0 30px rgba(acid,.35)
const double _kFrameW = 220;
const double _kFrameH = 150;
const double _kFrameR = 14;

/// `.vd-scan .core`（L429）：120×120，`margin-bottom:-26px`，`z-index:3`
const double _kCoreSize = 120;
const double _kCoreOverlap = 26;

/// `.vd-prog`（L432）：220×4 / r2 / rgba(255,255,255,.1)
const double _kProgW = 220;
const double _kProgH = 4;

/// `.rank`（L435）：`700 italic 170px/1 'Chakra Petch'`，左右 padding 20
const double _kRankSize = 170;
const double _kRankPad = 20;

/// `.rw` / `.xpw` / `.vd-res .btn` 的最大宽（L441/445/449）
const double _kResMaxW = 330;

/// `.critban`（L438）：高 64 / rotate(-8deg) / 0 0 50px rgba(hot,.7)
const double _kCritBanH = 64;

/// JS L1515 的砸印曲线 `cubic-bezier(.55,0,.75,.2)`（比 --slam 更急停）
const Cubic _kStamp = Cubic(.55, 0, .75, .2);

/// JS L1524 的行进场 `cubic-bezier(.2,1.3,.4,1)`
const Cubic _kRowIn = Cubic(.2, 1.3, .4, 1);

/// JS L1513 的横幅滑入 `cubic-bezier(.2,1,.3,1)`
const Cubic _kBanIn = Cubic(.2, 1, .3, 1);

/// 扫描阶段 JS L1505 的五句副标题，每句占 4 步（共 21 步）
const List<String> _kScanSubs = <String>[
  'ANALYZING EVIDENCE…',
  '比对历史数据…',
  '检测 P 图痕迹…',
  '计算敷衍指数…',
  '生成毒舌评语…',
];

/// 扫描总时长：JS L1506 `for(i=0;i<=20;i++){…await sleep(80)}` = 21×80
const int _kScanMs = 21 * 80;

/// `.critban span` 的跑马灯内容（DOM L812 原文）
const String _kCritText =
    'CRITICAL HIT · 暴击 · CRITICAL HIT · 暴击 · CRITICAL HIT · 暴击 · '
    'CRITICAL HIT · 暴击 · CRITICAL HIT · 暴击 ·';

/// `--rc` 的取值是 JS L1509 里写死的那一份，**不是** Ref.rank 的色谱：
/// `{S:'#fff', A:'#d6ff3d', B:'#3be8ff', C:'#ff3b7a'}`
Color _rankColor(String rank) {
  switch (rank) {
    case 'S':
      return const Color(0xFFFFFFFF);
    case 'A':
      return Ref.acid;
    case 'B':
      return Ref.cyan;
    case 'C':
      return Ref.hot;
    default:
      return Ref.rankOf(rank);
  }
}

/// `.rank.S`（L436）的 6 色 rainbow（首尾同为 hot 才能无缝平铺）
const List<Color> _kRainbow = <Color>[
  Color(0xFFFF3B7A),
  Color(0xFFFFCC4D),
  Color(0xFFD6FF3D),
  Color(0xFF3BE8FF),
  Color(0xFF8F6BFF),
  Color(0xFFFF3B7A),
];

/// `.vd-frame img{filter:saturate(.5) contrast(1.1)}`（L425）的 5×4 色阵。
/// 先 saturate 再 contrast：contrast 的偏移 = 127.5×(1-c)（0~255 区间）。
List<double> _buildPhotoFilter() {
  const double s = .5;
  const double c = 1.1;
  final double inv = 1 - s;
  const List<double> w = <double>[.213, .715, .072];
  final List<double> m = <double>[];
  for (int r = 0; r < 3; r++) {
    for (int k = 0; k < 3; k++) {
      m.add(((r == k ? s : 0) + inv * w[k]) * c);
    }
    m.add(0); // alpha 列
    m.add(127.5 * (1 - c)); // 偏移列
  }
  m.addAll(<double>[0, 0, 0, 1, 0]);
  return m;
}

final List<double> _kPhotoFilter = _buildPhotoFilter();

/// ═══════════════════════════════════════════════════════════════
///  RefVerdict —— 验收幕
/// ═══════════════════════════════════════════════════════════════
class RefVerdict extends StatefulWidget {
  const RefVerdict({
    super.key,
    required this.rank,
    required this.crit,
    required this.line,
    required this.rows,
    required this.xpFrom,
    required this.xpTo,
    required this.xpNeed,
    required this.lv,
    required this.onAccept,
    this.photo,
    this.scanning = true,
    this.phase,
  });

  /// 档位字母（S 档走 rainbow，L436）
  final String rank;
  final bool crit;

  /// `.vline`（L440）：她的话
  final String line;
  final List<RefRewardRow> rows;

  /// 经验条：从左端 [xpFrom] 涨到 [xpTo]，分母 [xpNeed]；左标签 `LV [lv]`
  final int xpFrom;
  final int xpTo;
  final int xpNeed;
  final int lv;

  final VoidCallback onAccept;

  /// 取景框里的照片（须自带 cover 尺寸，如 `Image(… fit: BoxFit.cover)`）
  final Widget? photo;

  /// false = 跳过扫描直接进结果（内部 Timer 不再排）
  final bool scanning;

  /// 外部指定阶段（测试用）：非空时**不跑**内部 Timer / 循环，直接给静态终值
  final RefVerdictPhase? phase;

  @override
  State<RefVerdict> createState() => _RefVerdictState();
}

class _RefVerdictState extends State<RefVerdict> with TickerProviderStateMixin {
  /// 扫描推进：0→1 覆盖 21 步（JS L1506）
  late final AnimationController _scan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _kScanMs),
  );

  /// `.vd-frame::after` 激光：0.9s ease-in-out alternate（L427-428）
  late final AnimationController _laser = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// `.critban span` 跑马灯：4s linear infinite（L439）
  late final AnimationController _marquee = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  /// `.rank.S` rainbow：2s linear infinite（L436-437）
  late final AnimationController _rainbow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  /// 结果阶段总时间线；duration 与各段起点都在 [_planTimeline] 里算
  late final AnimationController _master = AnimationController(vsync: this);

  RefVerdictPhase _phase = RefVerdictPhase.scan;
  Timer? _phaseTimer;
  bool _reduce = false;
  bool _motionSet = false;

  // ── 结果阶段各元素的起止毫秒（JS L1511-1529）───────────────
  static const int _stampAt = 220; // JS L1512 sleep(220) → 横幅 + 砸印
  static const int _rowsAt = 660; // 砸印 440ms 之后（L1513-1515）
  int _xpAt = 0;
  int _btnAt = 0;
  int _totalMs = 1;
  List<int> _rowStart = const <int>[];

  @override
  void initState() {
    super.initState();
    _planTimeline();
  }

  /// JS L1511-1529 的时间线，换成一份毫秒刻度
  void _planTimeline() {
    const int rowGap = 450; // 320ms 进场 + 380ms 滚动 + 70ms 间隔（L1524）
    const int rowRoll = 380;
    const int xpDur = 700; // JS L1528 duration:700
    const int btnDur = 320; // JS L1529 duration:320
    final List<int> starts = <int>[
      for (int i = 0; i < widget.rows.length; i++) _rowsAt + i * rowGap,
    ];
    final int rowsEnd = starts.isEmpty
        ? _rowsAt
        : starts.last + math.max(rowRoll, 320);
    _rowStart = starts;
    _xpAt = rowsEnd + 220; // L1525-1526：xpw 淡入 250ms + sleep(150)
    _btnAt = _xpAt + xpDur; // 经验条跑完才亮「收下」
    _totalMs = _btnAt + btnDur;
    _master.duration = Duration(milliseconds: _totalMs);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final bool first = !_motionSet;
    _motionSet = true;
    if (!first && reduce == _reduce) return;
    _reduce = reduce;
    _kick();
  }

  @override
  void didUpdateWidget(covariant RefVerdict old) {
    super.didUpdateWidget(old);
    if (old.rows.length != widget.rows.length) _planTimeline();
    if (old.phase != widget.phase || old.scanning != widget.scanning) _kick();
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    _scan.dispose();
    _laser.dispose();
    _marquee.dispose();
    _rainbow.dispose();
    _master.dispose();
    super.dispose();
  }

  /// 从零编排当前阶段（也可被外部 phase 变化重新触发）
  void _kick() {
    _phaseTimer?.cancel();
    _laser.stop();
    _marquee.stop();
    _rainbow.stop();
    _master.stop();

    _phase =
        widget.phase ??
        (widget.scanning ? RefVerdictPhase.scan : RefVerdictPhase.result);

    // 减弱动效 / 外部指定阶段 → 只落终值，不跑任何循环
    if (_reduce || widget.phase != null) {
      _scan.value = 1;
      _master.value = 1;
      _rainbow.value = 0;
      if (mounted) setState(() {});
      return;
    }

    if (_phase == RefVerdictPhase.scan) {
      _scan.forward(from: 0);
      _laser.repeat(reverse: true);
      _phaseTimer = Timer(const Duration(milliseconds: _kScanMs), _playResult);
    } else {
      _playResult();
    }
    if (mounted) setState(() {});
  }

  /// 阶段二（JS L1508 起）
  void _playResult() {
    _phaseTimer?.cancel();
    if (!mounted) return;
    setState(() => _phase = RefVerdictPhase.result);
    _laser.stop();
    if (_reduce) {
      _master.value = 1;
      return;
    }
    _master.forward(from: 0);
    _marquee.repeat();
    if (widget.rank.toUpperCase() == 'S') _rainbow.repeat();
  }

  /// 时间线取段：[a]~[b] 毫秒内 0→1（先夹后套曲线，避免曲线外插）
  double _seg(int ms, int a, int b, Curve curve) {
    if (b <= a) return ms >= b ? 1 : 0;
    if (ms <= a) return 0;
    if (ms >= b) return 1;
    return curve.transform(((ms - a) / (b - a)).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        // .ovl 的底（L406）：rgba(4,3,10,.84) + blur 12
        const Positioned.fill(child: ColoredBox(color: _kOvlBg)),
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        Positioned.fill(
          child: Padding(
            // .ovl{padding:30px 26px}（L406）
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 30),
            child: Center(
              child: SingleChildScrollView(
                child: _phase == RefVerdictPhase.scan
                    ? _buildScan()
                    : _buildResult(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  阶段一 .vd-scan（DOM L802-809 / CSS L422-433）
  // ═══════════════════════════════════════════════════════════
  Widget _buildScan() {
    return AnimatedBuilder(
      animation: _scan,
      builder: (BuildContext context, Widget? child) {
        // JS L1506：i 从 0 到 20，width=i*5%，subs[min(4,i/4|0)]，'.'×(i%4)
        final int step = (_scan.value * 20).round();
        final int subIdx = math.max(0, math.min(4, (step / 4).floor()));
        final String dots = '.' * (step % 4);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // core 压住取景框上沿 26px（L429 margin-bottom:-26 / z-index:3）
            Stack(
              alignment: Alignment.topCenter,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(
                    top: _kCoreSize - _kCoreOverlap,
                  ),
                  child: _buildFrame(),
                ),
                const _VerifierCore(size: _kCoreSize),
              ],
            ),
            const SizedBox(height: 24), // .vd-scan h3{margin-top:24}（L430）
            Text(
              '她正在验收$dots',
              textAlign: TextAlign.center,
              style: refText(
                family: Ref.fc,
                size: 22, // L430 font:900 22px
                wght: 900,
                ls: 4, // L430 letter-spacing:4px
                height: 1.2,
                color: Ref.txt,
              ),
            ),
            const SizedBox(height: 6), // L431 margin-top:6
            Text(
              _kScanSubs[subIdx],
              textAlign: TextAlign.center,
              style: refText(
                family: Ref.fm,
                size: 11, // L431 font:500 11px
                wght: 500,
                ls: 3, // L431 letter-spacing:3px
                height: 1.4,
                color: Ref.acid,
              ),
            ),
            const SizedBox(height: 14), // L432 margin-top:14
            _buildScanProg(step),
          ],
        );
      },
    );
  }

  /// `.vd-prog`（L432-433）：220×4 r2 + acid 填充带 10px 辉光
  Widget _buildScanProg(int step) {
    final double w = _kProgW * step / 20;
    return Container(
      width: _kProgW,
      height: _kProgH,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF), // rgba(255,255,255,.1)
        borderRadius: BorderRadius.circular(2),
      ),
      child: w <= 0
          ? null
          : Container(
              width: w,
              height: _kProgH,
              decoration: BoxDecoration(
                color: Ref.acid,
                borderRadius: BorderRadius.circular(2),
                boxShadow: <BoxShadow>[
                  BoxShadow(color: Ref.acid, blurRadius: 10), // L433
                ],
              ),
            ),
    );
  }

  /// `.vd-frame`（L424-428）
  Widget _buildFrame() {
    return Container(
      width: _kFrameW,
      height: _kFrameH,
      decoration: BoxDecoration(
        color: Colors.black, // L424 background:#000
        borderRadius: BorderRadius.circular(_kFrameR),
        border: Border.all(color: Ref.acid, width: 1.5), // L424
        boxShadow: <BoxShadow>[
          BoxShadow(color: Ref.a(Ref.acid, .35), blurRadius: 30), // L424
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_kFrameR - 1.5),
        child: Stack(
          children: <Widget>[
            // img{filter:saturate(.5) contrast(1.1)}（L425）
            Positioned.fill(
              child: ColorFiltered(
                colorFilter: ColorFilter.matrix(_kPhotoFilter),
                child: SizedBox.expand(
                  child: widget.photo ?? const ColoredBox(color: Colors.black),
                ),
              ),
            ),
            // ::before 扫描纹：repeating-linear-gradient(0deg,… 2px 实 2px 空)（L426）
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _ScanlinePainter()),
              ),
            ),
            // ::after 激光（L427-428）：底部 2px acid + 向上 30px 渐隐
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _laser,
                  builder: (BuildContext context, Widget? child) {
                    // @keyframes laser2{from{top:-30px}to{top:calc(100% - 30px)}}
                    final double top =
                        -30 + _laser.value * (_kFrameH - 30 + 30);
                    return Stack(
                      children: <Widget>[
                        Positioned(
                          left: 0,
                          right: 0,
                          top: top,
                          height: 30,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: <Color>[
                                  Colors.transparent,
                                  Ref.a(Ref.acid, .6),
                                ],
                              ),
                              border: const Border(
                                bottom: BorderSide(color: Ref.acid, width: 2),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  阶段二 .vd-res（DOM L810-817 / CSS L434-449）
  // ═══════════════════════════════════════════════════════════
  Widget _buildResult() {
    return AnimatedBuilder(
      animation: _master,
      builder: (BuildContext context, Widget? child) {
        final int ms = (_master.value * _totalMs).round();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // .vtag（L434）：700 11px mono / ls 5 / dim
            Text(
              'VERDICT · 验收结果',
              style: refText(
                family: Ref.fm,
                size: 11,
                wght: 700,
                ls: 5,
                height: 1.4,
                color: Ref.dim,
              ),
            ),
            _buildRankStack(ms),
            // .vline（L440）：500 15/1.6 居中 / maxWidth 320 / minHeight 48
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320, minHeight: 48),
              child: Text(
                widget.line,
                textAlign: TextAlign.center,
                style: RefType.verdictLine,
              ),
            ),
            // .rw（L441-444）
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kResMaxW),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(height: 14),
                  for (int i = 0; i < widget.rows.length; i++)
                    Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : 7), // gap:7
                      child: _buildRow(i, ms),
                    ),
                ],
              ),
            ),
            _buildXp(ms),
            _buildAccept(ms),
          ],
        );
      },
    );
  }

  /// `.rank` + `.critban`（L435-439），DOM L812 的 relative 容器
  Widget _buildRankStack(int ms) {
    final String rank = widget.rank.toUpperCase();
    final Color rc = _rankColor(rank);
    // 先量一遍字宽：Stack 的宽要等于 .rank 的宽（padding 0 20），
    // 否则 .critban 的 left/right:-10% 会按整屏宽算。
    final TextPainter tp = TextPainter(
      text: TextSpan(text: rank, style: _rankStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final double w = tp.width + _kRankPad * 2;
    tp.dispose();

    // 砸印（JS L1515）：scale3.4 rotate-12 blur12 → .9/3°(offset .78) → 1/0
    final double k = _seg(ms, _stampAt, _stampAt + 440, Curves.linear);
    double scale = 1;
    double rot = 0;
    double blur = 0;
    double opa = 1;
    if (k <= 0) {
      scale = 3.4;
      rot = -12;
      blur = 12;
      opa = 0;
    } else if (k < .78) {
      final double t = _kStamp.transform((k / .78).clamp(0.0, 1.0));
      scale = 3.4 + (.9 - 3.4) * t;
      rot = -12 + 15 * t;
      blur = 12 * (1 - t);
      opa = t;
    } else {
      final double t = Curves.easeOut.transform(
        ((k - .78) / .22).clamp(0.0, 1.0),
      );
      scale = .9 + .1 * t;
      rot = 3 * (1 - t);
    }

    return SizedBox(
      width: w,
      height: _kRankSize, // .rank 的 line-height:1（L435）→ 行盒 = 170
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: <Widget>[
          if (widget.crit)
            Positioned(
              left: -w * .1, // left:-10%（L438）
              right: -w * .1, // right:-10%
              top: _kRankSize * .24, // top:24%
              height: _kCritBanH, // height:64
              child: IgnorePointer(child: _buildCritBan(ms, w * 1.2)),
            ),
          AnimatedBuilder(
            animation: _rainbow,
            builder: (BuildContext context, Widget? _) {
              return Transform.rotate(
                angle: rot * math.pi / 180,
                child: Transform.scale(
                  scale: scale,
                  child: Opacity(
                    opacity: opa.clamp(0.0, 1.0),
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(
                        sigmaX: blur / 2,
                        sigmaY: blur / 2,
                      ),
                      child: _RankGlyph(
                        rank: rank,
                        color: rc,
                        phase: _rainbow.value,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// `.critban`（L438-439）：hot 底 / rotate(-8) / 0 0 50px / 跑马灯 4s
  Widget _buildCritBan(int ms, double width) {
    // JS L1513：translateX(-120%) → 0，380ms cubic-bezier(.2,1,.3,1)
    final double k = _seg(ms, _stampAt, _stampAt + 380, _kBanIn);
    final bool shown = ms >= _stampAt;
    return Transform.rotate(
      angle: -8 * math.pi / 180, // rotate(-8deg)（L438）
      child: Opacity(
        opacity: shown ? 1 : 0,
        child: Transform.translate(
          offset: Offset(-1.2 * width * (1 - k), 0),
          child: ClipRect(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Ref.hot, // L438 background:var(--hot)
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Ref.a(Ref.hot, .7),
                    blurRadius: 50, // 0 0 50px rgba(255,59,122,.7)
                  ),
                ],
              ),
              child: AnimatedBuilder(
                animation: _marquee,
                builder: (BuildContext context, Widget? child) {
                  return CustomPaint(
                    painter: _MarqueePainter(
                      phase: _marquee.value,
                      text: _kCritText,
                    ),
                    size: Size(width, _kCritBanH),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// `.rw .r`（L442-444）
  Widget _buildRow(int i, int ms) {
    final RefRewardRow r = widget.rows[i];
    final int at = i < _rowStart.length ? _rowStart[i] : _rowsAt;
    // JS L1524：进场 translateX(-40px) 320ms cubic-bezier(.2,1.3,.4,1)
    final double appear = _seg(ms, at, at + 320, _kRowIn);
    // JS L1524：rollPlus 380ms ease-out，把 +0 滚到 +value
    final double roll = _seg(ms, at, at + 380, Curves.easeOutCubic);
    final int shown = (r.value * roll).round();
    // JS L1487：滚完来一发 scale(1.6)→1，260ms cubic-bezier(.2,1.5,.4,1)
    double pop = 1;
    final int ps = at + 380;
    if (ms > ps && ms < ps + 260) {
      pop = 1.6 - .6 * Ref.pop.transform(((ms - ps) / 260).clamp(0.0, 1.0));
    }

    return Transform.translate(
      offset: Offset(-40 * (1 - appear), 0),
      child: Opacity(
        opacity: appear.clamp(0.0, 1.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0x0DFFFFFF), // rgba(255,255,255,.05)（L442）
            borderRadius: BorderRadius.circular(12), // r12（L442）
            border: Border.all(color: Ref.line), // 1px var(--line)
          ),
          child: Row(
            children: <Widget>[
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        r.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: refText(
                          size: 14, // L442 font:500 14px
                          wght: 500,
                          height: 1.3,
                          color: Ref.txt,
                        ),
                      ),
                    ),
                    // ⚠️ 空串也算「没有角标」：只判 null 会画一个空描边小方块
                    //    （真机截图：EXP / 晶核 / 意志 后面各挂一个粉框）。
                    if (r.tag != null && r.tag!.trim().isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(left: 6), // L444
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ), // 1px 5px（L444）
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4), // L444
                          border: Border.all(color: Ref.hot), // 1px solid hot
                        ),
                        child: Text(
                          r.tag!,
                          style: refText(
                            family: Ref.fm,
                            size: 11, // L444 font:700 11px
                            wght: 700,
                            height: 1.2,
                            color: Ref.hot,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Transform.scale(
                scale: pop,
                child: Text(
                  '+$shown',
                  style: refText(
                    family: Ref.fd,
                    size: 20, // L443 font:700 20px 'Chakra Petch'
                    wght: 700,
                    height: 1,
                    color: Ref.acid,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `.xpw`（L445-448）
  Widget _buildXp(int ms) {
    final int need = widget.xpNeed <= 0 ? 1 : widget.xpNeed;
    final double k = _seg(ms, _xpAt, _xpAt + 700, Curves.easeOutCubic);
    final double from = (widget.xpFrom / need).clamp(0.0, 1.0);
    final double to = (widget.xpTo / need).clamp(0.0, 1.0);
    final double frac = from + (to - from) * k;
    final bool done = k >= 1;
    final bool lvUp = widget.xpTo >= need;
    final double fade = _seg(ms, _xpAt, _xpAt + 250, Curves.linear);
    final String right = done
        ? (lvUp ? 'LEVEL UP!' : '${widget.xpTo} / ${widget.xpNeed}')
        : '${widget.xpFrom} / ${widget.xpNeed}';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _kResMaxW),
      child: Padding(
        padding: const EdgeInsets.only(top: 14), // L445 margin-top:14
        child: Opacity(
          opacity: fade.clamp(0.0, 1.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // .xl（L446）：700 12px mono dim，左右分布
              Padding(
                padding: const EdgeInsets.only(bottom: 6), // margin-bottom:6
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      'LV ${widget.lv}',
                      style: refText(
                        family: Ref.fm,
                        size: 12,
                        wght: 700,
                        height: 1.2,
                        color: Ref.dim,
                      ),
                    ),
                    Text(
                      right,
                      style: refText(
                        family: Ref.fm,
                        size: 12,
                        wght: 700,
                        height: 1.2,
                        color: done && lvUp ? Ref.acid : Ref.dim,
                      ),
                    ),
                  ],
                ),
              ),
              // .xt（L447-448）：10 高 r5 + violet→acid + 12px 辉光
              Container(
                height: 10,
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: const Color(0x14FFFFFF), // rgba(255,255,255,.08)
                  borderRadius: BorderRadius.circular(5),
                ),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints c) {
                    return Container(
                      width: c.maxWidth * frac,
                      height: 10,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: <Color>[Ref.violet, Ref.acid],
                        ),
                        borderRadius: BorderRadius.circular(5),
                        boxShadow: <BoxShadow>[
                          BoxShadow(color: Ref.acid, blurRadius: 12), // L448
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `.vd-res .btn`（L449）：占满 330 / margin-top 20
  Widget _buildAccept(int ms) {
    final double k = _seg(ms, _btnAt, _btnAt + 320, _kRowIn);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _kResMaxW),
      child: Padding(
        padding: const EdgeInsets.only(top: 20),
        child: IgnorePointer(
          ignoring: k < .6,
          child: Opacity(
            opacity: k.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, 20 * (1 - k)),
              child: SizedBox(
                width: double.infinity,
                child: RefButton(label: '收下', onTap: widget.onAccept),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.rank` 的字体（L435）：`700 italic 170px/1 'Chakra Petch'`
final TextStyle _rankStyle = refText(
  family: Ref.fd,
  size: _kRankSize,
  wght: 700,
  height: 1,
  italic: true,
  color: Colors.white,
);

/// ═══════════════════════════════════════════════════════════
///  `.rank` 的渐变字（L435-437）
///
///  · 常态：`linear-gradient(180deg,#fff 10%,var(--rc) 70%)` + drop-shadow 30
///  · S 档：6 色 rainbow，`background-size:200%`，2s linear 位移
///  · 底层再垫一层 30px 模糊的档位色，等价 `filter:drop-shadow(0 0 30px)`
/// ═══════════════════════════════════════════════════════════
class _RankGlyph extends StatelessWidget {
  const _RankGlyph({
    required this.rank,
    required this.color,
    required this.phase,
  });

  final String rank;
  final Color color;
  final double phase;

  @override
  Widget build(BuildContext context) {
    final bool isS = rank == 'S';
    final Widget glow = Text(
      rank,
      style: _rankStyle.copyWith(
        color: null,
        foreground: Paint()
          ..color = Ref.a(color, .85)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15),
      ),
    );

    if (isS) {
      // background-size:200% → 一块瓦片宽 2w；background-position 0→200%
      // 等价于瓦片整体左移 2w。用 12 停（两轮 6 色）覆盖 4w 以免露底。
      final List<Color> cols = <Color>[..._kRainbow, ..._kRainbow];
      return Stack(
        alignment: Alignment.center,
        children: <Widget>[
          glow,
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (Rect r) {
              final double x0 = -phase * 2 * r.width;
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: cols,
                stops: <double>[
                  for (int i = 0; i < cols.length; i++) i / cols.length,
                ],
              ).createShader(Rect.fromLTWH(x0, r.top, 4 * r.width, r.height));
            },
            child: Text(rank, style: _rankStyle),
          ),
        ],
      );
    }

    // 常态：白 10% → 档位色 70% 的竖向渐变（L435）
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        glow,
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (Rect r) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Colors.white, color],
            stops: const <double>[.1, .7],
          ).createShader(r),
          child: Text(rank, style: _rankStyle),
        ),
      ],
    );
  }
}

/// `.vd-frame` 的扫描纹（L426）：2px 实 / 2px 空，accent 8%
class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter();

  @override
  void paint(Canvas canvas, Size s) {
    final Paint p = Paint()..color = Ref.a(Ref.acid, .08);
    for (double y = 0; y < s.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, s.width, 2), p);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter oldDelegate) => false;
}

/// `.critban span`（L439）：`700 italic 34px 'Chakra Petch'` ls 4 白字；
/// `@keyframes marq{to{transform:translateX(-50%)}}` 4s linear（跑半条文案）
class _MarqueePainter extends CustomPainter {
  _MarqueePainter({required this.phase, required this.text});

  final double phase;
  final String text;

  static final TextStyle _style = refText(
    family: Ref.fd,
    size: 34, // L439
    wght: 700,
    ls: 4, // L439 letter-spacing:4px
    height: 1,
    italic: true,
    color: Colors.white,
  );

  @override
  void paint(Canvas canvas, Size s) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: text, style: _style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final double tw = tp.width;
    if (tw <= 0) {
      tp.dispose();
      return;
    }
    final double off = -phase * tw * .5; // translateX(-50%)
    final double dy = (s.height - tp.height) / 2;
    canvas.save();
    canvas.clipRect(Offset.zero & s);
    for (double x = off - tw; x < s.width + tw; x += tw) {
      tp.paint(canvas, Offset(x, dy));
    }
    canvas.restore();
    tp.dispose();
  }

  @override
  bool shouldRepaint(_MarqueePainter old) =>
      old.phase != phase || old.text != text;
}

/// `.vd-scan .core`（L429 + .core 的 SVG 结构 L1093-1105）
///
/// 自绘一版「同心环 + 眼」：r1 34s / r2 14s 反 / r3 7s / r4 22s 反，
/// halo 3.2s 呼吸；`scan` 情绪下 --cc 换成 acid、eye scaleY(.8)（L124）。
class _VerifierCore extends StatefulWidget {
  const _VerifierCore({required this.size});

  final double size;

  @override
  State<_VerifierCore> createState() => _VerifierCoreState();
}

class _VerifierCoreState extends State<_VerifierCore>
    with TickerProviderStateMixin {
  /// 最快的一圈（r3 = 7s）当主相位，其余环按周期比换算
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );

  /// `.core .halo`：3.2s ease-in-out infinite（L126-127）
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  bool _set = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_set && !reduce) return;
    _set = true;
    if (reduce) {
      _spin.stop();
      _breath.stop();
      return;
    }
    if (!_spin.isAnimating) _spin.repeat();
    if (!_breath.isAnimating) _breath.repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _breath,
        builder: (BuildContext context, Widget? child) {
          return CustomPaint(
            painter: _CorePainter(spin: _spin.value, breath: _breath.value),
          );
        },
      ),
    );
  }
}

class _CorePainter extends CustomPainter {
  const _CorePainter({required this.spin, required this.breath});

  /// 0~1 对应 7s（r3）
  final double spin;

  /// 0~1 对应 3.2s（halo 呼吸）
  final double breath;

  static const double _tau = math.pi * 2;

  @override
  void paint(Canvas canvas, Size s) {
    // SVG viewBox 是 200×200（L1093），按 200 单位画再整体缩放
    canvas.save();
    canvas.scale(s.width / 200);
    const Offset c = Offset(100, 100);

    // halo（L1094-1095）：acid 50% → 10% → 0，3.2s 呼吸 scale 1→1.08 / .7
    final double br = 1 + .08 * math.sin(breath * math.pi);
    final double haloA = 1 - .3 * math.sin(breath * math.pi);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(br);
    canvas.drawCircle(
      Offset.zero,
      99,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            Ref.a(Ref.acid, .5 * haloA),
            Ref.a(Ref.acid, .1 * haloA),
            Ref.a(Ref.acid, 0),
          ],
          stops: const <double>[0, .55, 1],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: 99)),
    );
    canvas.restore();

    // r1（L1096）：r93 dash 1 5 opacity .7，34s
    _dashedCircle(
      canvas,
      c,
      93,
      const <double>[1, 5],
      _angle(34),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Ref.a(Ref.acid, .7),
    );
    // r2（L1097）：r81 dash 80 22 10 22，14s 反向
    _dashedCircle(
      canvas,
      c,
      81,
      const <double>[80, 22, 10, 22],
      -_angle(14),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Ref.acid,
    );
    // r3（L1099）：r64 dash 2 8 opacity .85，7s
    _dashedCircle(
      canvas,
      c,
      64,
      const <double>[2, 8],
      _angle(7),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Ref.a(Ref.acid, .85),
    );
    // r4（L1098）：两段 r72 的 3.5px 圆弧，22s 反向
    final double a4 = -_angle(22);
    for (final double start in <double>[-math.pi / 2, math.pi / 2]) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: 72),
        start + a4,
        59.85 * math.pi / 180,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round
          ..color = Ref.acid,
      );
    }

    // eye（L1100-1101）：M36 100 Q100 44 164 100 Q100 156 36 100Z
    final Path eye = Path()
      ..moveTo(36, 100)
      ..quadraticBezierTo(100, 44, 164, 100)
      ..quadraticBezierTo(100, 156, 36, 100)
      ..close();
    canvas.save();
    // .core.scan .eye{transform:scaleY(.8)}（L124）
    canvas.translate(c.dx, c.dy);
    canvas.scale(1, .8);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawPath(eye, Paint()..color = const Color(0xE606050E));
    canvas.drawPath(
      eye,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Ref.acid,
    );
    // iris：r26 环 + r19 22% 填充 + r10 实心 + (92,92) 白点 4（L1101）
    canvas.drawCircle(
      c,
      26,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Ref.acid,
    );
    canvas.drawCircle(c, 19, Paint()..color = Ref.a(Ref.acid, .22));
    canvas.drawCircle(c, 10, Paint()..color = Ref.acid);
    canvas.drawCircle(const Offset(92, 92), 4, Paint()..color = Colors.white);
    canvas.restore();

    canvas.restore();
  }

  /// 把「7s 一圈」的相位换算成周期 [periodSec] 秒的旋转角（弧度）
  double _angle(double periodSec) => spin * _tau * 7 / periodSec;

  void _dashedCircle(
    Canvas canvas,
    Offset c,
    double r,
    List<double> dash,
    double rot,
    Paint p,
  ) {
    final double circ = _tau * r;
    final Rect rect = Rect.fromCircle(center: c, radius: r);
    double pos = 0;
    int i = 0;
    while (pos < circ) {
      final double len = dash[i % dash.length];
      final double a0 = rot + pos / r;
      final double a1 = rot + math.min(pos + len, circ) / r;
      canvas.drawArc(rect, a0, a1 - a0, false, p);
      pos += len;
      i++;
    }
  }

  @override
  bool shouldRepaint(_CorePainter old) =>
      old.spin != spin || old.breath != breath;
}
