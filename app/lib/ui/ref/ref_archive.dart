import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/attrs.dart';
import '../../data/titles.dart';
import '../../design/ref.dart';
import '../../state/host_state.dart';
import '../../state/quest_flow.dart' show HistoryEntry;
import '../../state/sfx.dart';
import '../../widgets/fx_particles.dart';
import 'ref_inputs.dart';
import 'ref_kit.dart';
import 'ref_motion.dart';

/// ═══════════════════════════════════════════════════════════
///  档案 —— 参考稿 #sc-archive（CSS L330-384，DOM L767-787，JS L1562-1608）
///
///  .sh（eyebrow + h1 档案 + .cnt 03/12 + xbtn）
///  → .scroll：.prof 四格 → 雷达（easeOutBack 长出 + 5s 扫描 + 数字滚）
///  → 名牒册（挂绳牌，进场摆荡；点 = 佩戴 / 锁着就晃）
///  → 本周回顾（柱子长出 + 2×2 小卡）→ 六维条（宽度长出）
///  `.sr2` 分段在滚进视口时淡入上移（IntersectionObserver 的等价物）。
///
///  ⚠️ nohud 场景（上边距 30）。
/// ═══════════════════════════════════════════════════════════
class RefArchive extends StatefulWidget {
  const RefArchive({
    super.key,
    required this.host,
    required this.ownedCount,
    required this.totalTitles,
    required this.onBack,
    required this.onEquip,
    this.history,
    this.fx,
    this.onToast,
  });

  final HostState host;
  final int ownedCount;
  final int totalTitles;
  final VoidCallback? onBack;

  /// 佩戴；返回是否成功
  final bool Function(String id)? onEquip;

  /// 结算流水（本周柱状图 / 累计 EXP 用）
  final Future<List<HistoryEntry>>? history;
  final FxController? fx;
  final void Function(String msg, {bool bad})? onToast;

  @override
  State<RefArchive> createState() => _RefArchiveState();
}

class _RefArchiveState extends State<RefArchive>
    with TickerProviderStateMixin, RefTimers<RefArchive> {
  final ScrollController _sc = ScrollController();
  final List<GlobalKey> _secKeys = List<GlobalKey>.generate(
    5,
    (_) => GlobalKey(),
  );
  final Set<int> _in = <int>{};
  List<HistoryEntry> _hist = const <HistoryEntry>[];

  /// 雷达：250ms 后 1.2s easeOutBack 长出
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  /// 雷达扫描扇：5s 一圈
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );

  final Map<String, int> _wiggle = <String, int>{};
  String? _spinId;
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  bool get _reduce => WidgetsBinding
      .instance
      .platformDispatcher
      .accessibilityFeatures
      .disableAnimations;

  @override
  void initState() {
    super.initState();
    widget.history?.then((List<HistoryEntry> h) {
      if (mounted) setState(() => _hist = h);
    });
    if (_reduce) {
      _grow.value = 1;
      _in.addAll(<int>[0, 1, 2, 3, 4]);
    } else {
      later(const Duration(milliseconds: 250), () {
        if (mounted) _grow.forward();
      });
      _sweep.repeat();
    }
    _sc.addListener(_checkIn);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkIn());
  }

  @override
  void dispose() {
    _sc.dispose();
    _grow.dispose();
    _sweep.dispose();
    _spin.dispose();
    super.dispose();
  }

  /// .sr2 进场：分段顶边越过视口 85% 线就点亮（threshold .15）
  void _checkIn() {
    if (!mounted) return;
    final double vh = MediaQuery.sizeOf(context).height;
    bool changed = false;
    for (int i = 0; i < _secKeys.length; i++) {
      if (_in.contains(i)) continue;
      final RenderBox? b =
          _secKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (b == null || !b.hasSize) continue;
      final double top = b.localToGlobal(Offset.zero).dy;
      if (top < vh - b.size.height * .15) {
        _in.add(i);
        changed = true;
      }
    }
    if (changed) setState(() {});
  }

  void _toast(String m, {bool bad = false}) =>
      widget.onToast?.call(m, bad: bad);

  static String _pad(int n) => n.toString().padLeft(2, '0');

  // ── 数据 ────────────────────────────────────────────────
  int get _totalExp {
    int s = 0;
    for (final HistoryEntry e in _hist) {
      s += e.exp;
    }
    return s;
  }

  /// 近 7 天（周一…今天的顺序以「今天」为最后一格）
  List<int> get _week {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final List<int> out = List<int>.filled(7, 0);
    for (final HistoryEntry e in _hist) {
      if (e.result != 'clear') continue;
      final DateTime d = DateTime(e.at.year, e.at.month, e.at.day);
      final int ago = today.difference(d).inDays;
      if (ago >= 0 && ago < 7) out[6 - ago]++;
    }
    return out;
  }

  int get _weekExp {
    final DateTime now = DateTime.now();
    int s = 0;
    for (final HistoryEntry e in _hist) {
      if (now.difference(e.at).inDays < 7) s += e.exp;
    }
    return s;
  }

  // ── 交互 ────────────────────────────────────────────────
  void _tapPlate(HostTitle t, Offset center) {
    final bool owned = widget.host.ownedTitles.contains(t.id);
    if (!owned) {
      unawaited(Sfx.play('error'));
      setState(() => _wiggle[t.id] = (_wiggle[t.id] ?? 0) + 1);
      _toast('未解锁 · ${t.hint}', bad: true);
      return;
    }
    if (widget.host.title == t.id) {
      unawaited(Sfx.play('soft'));
      _toast('已经戴着了。再戴一次也不会更帅。');
      return;
    }
    final bool ok = widget.onEquip?.call(t.id) ?? false;
    if (!ok) {
      unawaited(Sfx.play('error'));
      _toast('现在摘不掉。完成一单再说。', bad: true);
      return;
    }
    unawaited(Sfx.play('unlock'));
    widget.fx?.burst(
      center.dx,
      center.dy,
      n: 20,
      cols: const <Color>[Ref.acid, Ref.violet, Colors.white],
      min: 120,
      max: 480,
      g: 40,
    );
    widget.fx?.ripple(center.dx, center.dy, r1: 90, color: Ref.acid, w: 3);
    setState(() => _spinId = t.id);
    _spin.forward(from: 0).then((_) {
      if (!mounted) return;
      setState(() => _spinId = null);
      _toast('已佩戴「${t.name}」。她瞥了一眼，没说话。');
    });
  }

  void _tapRadar() {
    unawaited(Sfx.play('soft'));
    int sum = 0;
    String top = Attr.all.first.name;
    int best = -1;
    for (final Attr a in Attr.all) {
      final int v = widget.host.attrs[a.k] ?? 0;
      sum += v;
      if (v > best) {
        best = v;
        top = a.name;
      }
    }
    _toast('六维总和 $sum。$top领先，其他……还在加载。');
  }

  // ── build ───────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.only(top: safe.top + Ref.sceneTopNoHud),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Ref.gutter),
            child: RefReveal(index: 0, child: _head()),
          ),
          // .scroll{margin:10px -22px 0;padding:0 22px 40px}：滚动区铺满屏宽
          // （名牒横滑出血到屏边），内容自己留 22 边距；上沿裁切不压抬头。
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: ListView(
                key: const Key('ref.archive.scroll'),
                controller: _sc,
                padding: EdgeInsets.fromLTRB(
                  Ref.gutter,
                  0,
                  Ref.gutter,
                  safe.bottom + 40,
                ),
                children: <Widget>[
                  RefReveal(index: 1, child: _prof()),
                  RefReveal(
                    index: 2,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Center(
                        child: GestureDetector(
                          onTap: _tapRadar,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 340),
                            child: AspectRatio(
                              aspectRatio: 300 / 270,
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  painter: _RadarPainter(
                                    attrs: widget.host.attrs,
                                    grow: _grow,
                                    sweep: _sweep,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _sr(
                    0,
                    RefSectionHeader(
                      title: '名牒册 · 点击佩戴',
                      trailing: '${widget.ownedCount}/${widget.totalTitles} 张',
                      accent: Ref.violet,
                    ),
                  ),
                  _sr(1, _plates()),
                  _sr(2, const RefSectionHeader(title: '数据 · 本周回顾')),
                  _sr(3, _weekCard()),
                  const RefSectionHeader(title: '六维 · 当前数值'),
                  _sr(4, _attrsCard()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// .sr2：opacity 0 / translateY 30 → 原位，.7s ease
  Widget _sr(int i, Widget child) {
    final bool on = _in.contains(i);
    return KeyedSubtree(
      key: _secKeys[i],
      child: AnimatedOpacity(
        opacity: on ? 1 : 0,
        duration: const Duration(milliseconds: 700),
        curve: Ref.ease,
        child: AnimatedSlide(
          offset: on ? Offset.zero : const Offset(0, .12),
          duration: const Duration(milliseconds: 700),
          curve: Ref.ease,
          child: child,
        ),
      ),
    );
  }

  /// .sh + .cnt：一行三件（标题 / 计数 / ✕）
  Widget _head() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const RefEyebrow(text: 'ARCHIVE · 宿主档案', accent: Ref.violet),
              const SizedBox(height: 8),
              Text('档案', style: RefType.h1),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${_pad(widget.ownedCount)} / ${widget.totalTitles}',
            maxLines: 1,
            style: refText(
              family: Ref.fd,
              size: 30,
              wght: 700,
              italic: true,
              height: 1.2,
              color: Ref.violet,
              shadows: const <Shadow>[
                Shadow(color: Ref.violet, blurRadius: 20),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        RefXButton(onTap: widget.onBack, accent: Ref.violet),
      ],
    );
  }

  /// .prof：LV / 累计 EXP / 连胜天 / 完成单
  Widget _prof() {
    final HostState h = widget.host;
    final List<(String, String)> items = <(String, String)>[
      ('LV${h.lv}', '等级'),
      ('${_hist.isEmpty ? h.exp : _totalExp}', '累计 EXP'),
      ('${h.streak}', '连胜天'),
      ('${h.doneCount}', '完成单'),
    ];
    return Row(
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0x09FFFFFF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Ref.line),
              ),
              child: Column(
                children: <Widget>[
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      items[i].$1,
                      style: refText(
                        family: Ref.fd,
                        size: 22,
                        wght: 700,
                        height: 1.1,
                        color: Ref.txt,
                      ),
                    ),
                  ),
                  Text(
                    items[i].$2,
                    style: refText(
                      size: 11,
                      wght: 500,
                      height: 1.5,
                      color: Ref.dim,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// .plates：横滑、scroll-snap、挂绳牌；进场每张摆荡 900ms（错峰 70）
  Widget _plates() {
    final bool on = _in.contains(1);
    return SizedBox(
      height: 4 + 12 + 18 + 188 + 18,
      child: OverflowBox(
        maxWidth: MediaQuery.sizeOf(context).width,
        child: ListView.separated(
          key: const Key('ref.archive.plates'),
          scrollDirection: Axis.horizontal,
          physics: const PageScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(Ref.gutter, 4, Ref.gutter, 18),
          itemCount: HostTitle.all.length,
          separatorBuilder: (BuildContext _, int _) =>
              const SizedBox(width: 14),
          itemBuilder: (BuildContext context, int i) {
            final HostTitle t = HostTitle.all[i];
            final GlobalKey k = GlobalKey();
            return _Plate(
              key: ValueKey<String>('plate.${t.id}'),
              boxKey: k,
              index: i,
              title: t,
              owned: widget.host.ownedTitles.contains(t.id),
              equipped: widget.host.title == t.id,
              swingIn: on,
              wiggle: _wiggle[t.id] ?? 0,
              spin: _spinId == t.id ? _spin : null,
              onTap: () {
                final RenderBox? b =
                    k.currentContext?.findRenderObject() as RenderBox?;
                final RenderBox? root =
                    this.context.findRenderObject() as RenderBox?;
                Offset c = Offset.zero;
                if (b != null && root != null) {
                  c = root.globalToLocal(
                    b.localToGlobal(b.size.center(Offset.zero)),
                  );
                }
                _tapPlate(t, c);
              },
            );
          },
        ),
      ),
    );
  }

  /// .weekc：柱状图（1s ease 长出，错峰 70）+ 2×2
  Widget _weekCard() {
    final bool on = _in.contains(3);
    final List<int> w = _week;
    final int mx = math.max(3, w.fold<int>(0, math.max));
    final DateTime now = DateTime.now();
    const String days = '一二三四五六日';
    final int sum = w.fold<int>(0, (int a, int b) => a + b);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Ref.line),
      ),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 110,
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  for (int i = 0; i < 7; i++) ...<Widget>[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(
                      child: _Bar(
                        value: w[i],
                        frac: on ? math.max(.04, w[i] / mx) : 0,
                        delayMs: i * 70,
                        today: i == 6,
                        label: i == 6
                            ? '今天'
                            : '周${days[(now.weekday - 1 - (6 - i)) % 7]}',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.9,
            children: <Widget>[
              _stat('$sum 单', '本周完成'),
              _stat('+$_weekExp', '本周 EXP'),
              _stat('${widget.host.critCount} 次', '暴击'),
              _stat('${widget.host.bestStreak} 天', '最长连胜'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String v, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            v,
            style: refText(
              family: Ref.fd,
              size: 20,
              wght: 700,
              height: 1.15,
              color: Ref.txt,
            ),
          ),
          Text(
            label,
            style: refText(size: 11, wght: 500, height: 1.3, color: Ref.dim),
          ),
        ],
      ),
    );
  }

  /// .attrs：40 / 1fr / 26 三列；条宽 1.2s ease 长出（错峰 90）
  Widget _attrsCard() {
    final bool on = _in.contains(4);
    final int mx = math.max(
      10,
      widget.host.attrs.values.fold<int>(0, math.max),
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Ref.line),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < Attr.all.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: 9),
            _attrRow(Attr.all[i], i, on, mx),
          ],
        ],
      ),
    );
  }

  Widget _attrRow(Attr a, int i, bool on, int mx) {
    final int v = widget.host.attrs[a.k] ?? 0;
    return Row(
      children: <Widget>[
        SizedBox(
          width: 40,
          child: Text(
            a.name,
            style: refText(size: 12, wght: 500, height: 1.2, color: Ref.dim),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: <Widget>[
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0x12FFFFFF)),
                  ),
                  _DelayedFrac(
                    frac: on ? (v / mx).clamp(0.0, 1.0) : 0,
                    delayMs: i * 90,
                    ms: 1200,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[Ref.violet, Ref.cyan],
                        ),
                        borderRadius: BorderRadius.all(Radius.circular(3)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 26,
          child: Text(
            '$v',
            textAlign: TextAlign.right,
            style: refText(
              family: Ref.fd,
              size: 13,
              wght: 700,
              height: 1.2,
              color: Ref.txt,
            ),
          ),
        ),
      ],
    );
  }
}

/// 宽度在 delay 后按 ease 长到 frac（CSS `transition: width`）
class _DelayedFrac extends StatefulWidget {
  const _DelayedFrac({
    required this.frac,
    required this.delayMs,
    required this.ms,
    required this.child,
  });
  final double frac;
  final int delayMs;
  final int ms;
  final Widget child;

  @override
  State<_DelayedFrac> createState() => _DelayedFracState();
}

class _DelayedFracState extends State<_DelayedFrac>
    with RefTimers<_DelayedFrac> {
  double _f = 0;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(_DelayedFrac old) {
    super.didUpdateWidget(old);
    if (old.frac != widget.frac) _schedule();
  }

  void _schedule() {
    later(Duration(milliseconds: widget.delayMs), () {
      if (mounted) setState(() => _f = widget.frac);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedFractionallySizedBox(
      duration: Duration(milliseconds: widget.ms),
      curve: Ref.ease,
      alignment: Alignment.centerLeft,
      widthFactor: _f,
      heightFactor: 1,
      child: widget.child,
    );
  }
}

/// .bars div：数字 + 柱（6/6/2/2 圆角，violet 渐变；今天 acid + 辉光）+ 周几
class _Bar extends StatelessWidget {
  const _Bar({
    required this.value,
    required this.frac,
    required this.delayMs,
    required this.today,
    required this.label,
  });
  final int value;
  final double frac;
  final int delayMs;
  final bool today;
  final String label;

  @override
  Widget build(BuildContext context) {
    final Color c = today ? Ref.acid : Ref.violet;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 26),
              child: _DelayedHeight(
                frac: frac,
                delayMs: delayMs,
                builder: (double h) => Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Container(
                      height: h,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[c, Ref.a(c, .2)],
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                          bottom: Radius.circular(2),
                        ),
                        boxShadow: today
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: Ref.a(Ref.acid, .35),
                                  blurRadius: 16,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    Positioned(
                      top: -17,
                      left: -6,
                      right: -6,
                      child: Text(
                        '$value',
                        textAlign: TextAlign.center,
                        style: refText(
                          family: Ref.fd,
                          size: 11,
                          wght: 700,
                          height: 1.2,
                          color: Ref.txt,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: refText(size: 11, wght: 500, height: 1.2, color: Ref.dim),
        ),
      ],
    );
  }
}

class _DelayedHeight extends StatefulWidget {
  const _DelayedHeight({
    required this.frac,
    required this.delayMs,
    required this.builder,
  });
  final double frac;
  final int delayMs;
  final Widget Function(double h) builder;

  @override
  State<_DelayedHeight> createState() => _DelayedHeightState();
}

class _DelayedHeightState extends State<_DelayedHeight>
    with RefTimers<_DelayedHeight> {
  double _f = 0;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(_DelayedHeight old) {
    super.didUpdateWidget(old);
    if (old.frac != widget.frac) _schedule();
  }

  void _schedule() {
    later(Duration(milliseconds: widget.delayMs), () {
      if (mounted) setState(() => _f = widget.frac);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext _, BoxConstraints box) =>
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: _f),
            duration: const Duration(milliseconds: 1000),
            curve: Ref.ease,
            builder: (BuildContext _, double v, Widget? _) =>
                widget.builder(box.maxHeight * v),
          ),
    );
  }
}

/// .pw：12 挂孔 + 18 挂绳 + 138×188 牌（transform-origin 50% −30px）
class _Plate extends StatefulWidget {
  const _Plate({
    super.key,
    required this.boxKey,
    required this.index,
    required this.title,
    required this.owned,
    required this.equipped,
    required this.swingIn,
    required this.wiggle,
    required this.spin,
    required this.onTap,
  });

  final GlobalKey boxKey;
  final int index;
  final HostTitle title;
  final bool owned;
  final bool equipped;
  final bool swingIn;
  final int wiggle;
  final Animation<double>? spin;
  final VoidCallback onTap;

  @override
  State<_Plate> createState() => _PlateState();
}

class _PlateState extends State<_Plate>
    with TickerProviderStateMixin, RefTimers<_Plate> {
  /// 进场摆荡：rotate 14 → −6（50%）→ 2（80%）→ 0，opacity 0 → 1（50%）
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// 锁着被点：0 → 7 → −5 → 3 → 0，700ms
  late final AnimationController _wig = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  /// .gl 镭射：4s 线性
  late final AnimationController _holo = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  @override
  void initState() {
    super.initState();
    if (widget.swingIn) _start();
    if (widget.owned) _holo.repeat();
  }

  void _start() {
    later(Duration(milliseconds: widget.index * 70), () {
      if (mounted) _in.forward();
    });
  }

  @override
  void didUpdateWidget(_Plate old) {
    super.didUpdateWidget(old);
    if (widget.swingIn && !old.swingIn) _start();
    if (widget.wiggle != old.wiggle) _wig.forward(from: 0);
    if (widget.owned && !_holo.isAnimating) _holo.repeat();
  }

  @override
  void dispose() {
    _in.dispose();
    _wig.dispose();
    _holo.dispose();
    super.dispose();
  }

  double _swingAngle(double v) {
    // keyframes：0 → 14°，.5 → −6°，.8 → 2°，1 → 0°（ease-out 整段）
    final double t = Curves.easeOut.transform(v);
    double deg;
    if (t < .5) {
      deg = 14 + (-6 - 14) * (t / .5);
    } else if (t < .8) {
      deg = -6 + (2 + 6) * ((t - .5) / .3);
    } else {
      deg = 2 * (1 - (t - .8) / .2);
    }
    return deg * math.pi / 180;
  }

  double _wigAngle(double v) {
    const List<double> k = <double>[0, 7, -5, 3, 0];
    final double p = Curves.easeOut.transform(v) * (k.length - 1);
    final int a = p.floor().clamp(0, k.length - 1);
    final int b = math.min(a + 1, k.length - 1);
    return (k[a] + (k[b] - k[a]) * (p - a)) * math.pi / 180;
  }

  @override
  Widget build(BuildContext context) {
    final bool own = widget.owned;
    final bool eq = widget.equipped;
    final Widget plate = GestureDetector(
      onTap: widget.onTap,
      child: Container(
        key: widget.boxKey,
        width: 138,
        height: 188,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: eq ? Ref.acid : const Color(0x1AFFFFFF),
            width: 1.5,
          ),
          boxShadow: eq
              ? <BoxShadow>[
                  BoxShadow(color: Ref.a(Ref.acid, .35), blurRadius: 26),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14.5),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              CustomPaint(painter: _PlateBg(own)),
              if (own)
                AnimatedBuilder(
                  animation: _holo,
                  builder: (BuildContext _, Widget? _) =>
                      CustomPaint(painter: _PlateHolo(_holo.value)),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Ref.violet),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          (widget.index + 1).toString().padLeft(2, '0'),
                          style: refText(
                            family: Ref.fm,
                            size: 11,
                            wght: 700,
                            height: 1.1,
                            color: Ref.violet,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: own
                          ? const SizedBox.shrink()
                          : Center(
                              child: Text(
                                '?',
                                style: refText(
                                  family: Ref.fd,
                                  size: 46,
                                  wght: 700,
                                  height: 1,
                                  color: Ref.dim2,
                                ),
                              ),
                            ),
                    ),
                    Text(
                      own ? widget.title.name : '？？？',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: refText(
                        size: 19,
                        wght: 900,
                        height: 1.25,
                        color: own ? Ref.txt : Ref.dim2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.title.hint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: refText(
                        size: 11,
                        wght: 400,
                        height: 1.4,
                        color: Ref.dim,
                      ),
                    ),
                    Container(
                      height: 2,
                      margin: const EdgeInsets.only(top: 10),
                      decoration: BoxDecoration(
                        color: own ? null : const Color(0x1FFFFFFF),
                        gradient: own
                            ? const LinearGradient(
                                colors: <Color>[Ref.violet, Ref.cyan],
                              )
                            : null,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        Text(
                          eq ? '已佩戴' : (own ? '点击佩戴' : '未解锁'),
                          style: refText(
                            size: 11,
                            wght: 500,
                            height: 1.2,
                            color: eq ? Ref.acid : Ref.dim,
                          ),
                        ),
                        const Spacer(),
                        if (eq)
                          Text(
                            '●',
                            style: refText(
                              size: 11,
                              wght: 500,
                              height: 1.2,
                              color: Ref.acid,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return SizedBox(
      width: 138,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          _in,
          _wig,
          if (widget.spin != null) widget.spin!,
        ]),
        child: plate,
        builder: (BuildContext _, Widget? child) {
          final double v = _in.value;
          final double op = widget.swingIn ? (v / .5).clamp(0.0, 1.0) : 0;
          double ang = widget.swingIn && v < 1 ? _swingAngle(v) : 0;
          if (_wig.isAnimating) ang += _wigAngle(_wig.value);
          Widget p = child!;
          final Animation<double>? sp = widget.spin;
          if (sp != null) {
            final double t = const Cubic(.3, .9, .3, 1).transform(sp.value);
            p = Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, -1 / 600)
                ..rotateY(t * 2 * math.pi),
              child: p,
            );
          }
          return Opacity(
            opacity: op,
            child: Column(
              children: <Widget>[
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1B1830),
                    border: Border.all(color: Ref.dim2, width: 2),
                  ),
                ),
                Container(
                  width: 2,
                  height: 18,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[Ref.dim2, Color(0x4DFFFFFF)],
                    ),
                  ),
                ),
                // transform-origin: 50% −30px（挂孔处）
                Transform(
                  alignment: Alignment.topCenter,
                  transform: Matrix4.identity()
                    ..translateByDouble(0, -30, 0, 1)
                    ..rotateZ(ang)
                    ..translateByDouble(0, 30, 0, 1),
                  child: p,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// .plate 底：0° 横纹（1px / 14px，白 3% 或紫 5%）+ 160° 渐变
class _PlateBg extends CustomPainter {
  const _PlateBg(this.own);
  final bool own;
  @override
  void paint(Canvas canvas, Size s) {
    final Rect r = Offset.zero & s;
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(-.34, -1),
          end: const Alignment(.34, 1),
          colors: own
              ? const <Color>[Color(0xFF2B2152), Color(0xFF100D20)]
              : const <Color>[Color(0xFF211C39), Color(0xFF0D0B18)],
        ).createShader(r),
    );
    final Paint ln = Paint()
      ..color = own ? const Color(0x0D8F6BFF) : const Color(0x08FFFFFF);
    for (double y = s.height - 1; y > 0; y -= 14) {
      canvas.drawRect(Rect.fromLTWH(0, y, s.width, 1), ln);
    }
  }

  @override
  bool shouldRepaint(_PlateBg o) => o.own != own;
}

/// .plate .gl：115° 白 18% 光带，250% 宽，4s 从 150% 扫到 −100%
class _PlateHolo extends CustomPainter {
  const _PlateHolo(this.t);
  final double t;
  @override
  void paint(Canvas canvas, Size s) {
    final double bw = s.width * 2.5;
    final double pos = 1.5 + (-1 - 1.5) * t;
    final double ox = (s.width - bw) * pos;
    final Rect big = Rect.fromLTWH(ox, 0, bw, s.height);
    canvas.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment(-.9, -.4),
          end: Alignment(.9, .4),
          colors: <Color>[
            Color(0x00FFFFFF),
            Color(0x2EFFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: <double>[.3, .45, .6],
        ).createShader(big),
    );
  }

  @override
  bool shouldRepaint(_PlateHolo o) => o.t != t;
}

/// .radar（L338-342 / JS drawRadar L1565-1579）
class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.attrs, required this.grow, required this.sweep})
    : super(repaint: Listenable.merge(<Listenable>[grow, sweep]));

  final Map<String, int> attrs;
  final Animation<double> grow;
  final Animation<double> sweep;

  static const double _cx = 150, _cy = 135, _r = 92;

  /// easeOutBack（c1 1.70158）
  static double _back(double k) {
    const double c1 = 1.70158, c3 = c1 + 1;
    if (k <= 0) return 0;
    return 1 + c3 * math.pow(k - 1, 3) + c1 * math.pow(k - 1, 2);
  }

  @override
  void paint(Canvas canvas, Size s) {
    if (s.isEmpty) return;
    final double k = math.min(s.width / 300, s.height / 270);
    canvas.save();
    canvas.translate((s.width - 300 * k) / 2, (s.height - 270 * k) / 2);
    canvas.scale(k);

    Offset pt(int i, double r) {
      final double a = (-90 + i * 60) * math.pi / 180;
      return Offset(_cx + r * math.cos(a), _cy + r * math.sin(a));
    }

    Path poly(double r) {
      final Path p = Path();
      for (int i = 0; i < 6; i++) {
        final Offset o = pt(i, r);
        i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
      }
      return p..close();
    }

    for (int l = 1; l <= 5; l++) {
      final double r = _r * l / 5;
      if (l.isOdd) {
        canvas.drawPath(poly(r), Paint()..color = const Color(0x0B8F6BFF));
      }
      canvas.drawPath(
        poly(r),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = l == 5 ? 1.5 : 1
          ..color = Color.fromRGBO(143, 107, 255, l == 5 ? .55 : .18),
      );
    }
    for (int i = 0; i < 6; i++) {
      canvas.drawLine(
        const Offset(_cx, _cy),
        pt(i, _r),
        Paint()
          ..strokeWidth = 1
          ..color = const Color(0x388F6BFF),
      );
    }
    // .sweep：60° 扇，5s 一圈，violet 0 → .45
    canvas.save();
    canvas.translate(_cx, _cy);
    canvas.rotate(sweep.value * 2 * math.pi);
    final Path fan = Path()
      ..moveTo(0, 0)
      ..lineTo(0, -_r)
      ..arcTo(
        Rect.fromCircle(center: Offset.zero, radius: _r),
        -math.pi / 2,
        math.pi / 3,
        false,
      )
      ..close();
    canvas.drawPath(
      fan,
      Paint()
        ..shader = const LinearGradient(
          colors: <Color>[Color(0x008F6BFF), Color(0x738F6BFF)],
        ).createShader(Rect.fromLTWH(0, -_r, _r, _r)),
    );
    canvas.restore();

    // 数值：/max(10, 最大值) 归一
    final List<Attr> ax = Attr.all;
    final int mx = math.max(10, attrs.values.fold<int>(0, math.max));
    final double kk = grow.value.clamp(0.0, 1.0);
    final double e = _back(kk);
    final List<Offset> pts = <Offset>[
      for (int i = 0; i < 6; i++)
        pt(
          i,
          math.max(.05, ((attrs[ax[i].k] ?? 0) / mx).clamp(0.0, 1.0)) * _r * e,
        ),
    ];
    final Path shape = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < 6; i++) {
      shape.lineTo(pts[i].dx, pts[i].dy);
    }
    shape.close();
    canvas.drawPath(
      shape,
      Paint()
        ..shader =
            const RadialGradient(
              colors: <Color>[Color(0x998F6BFF), Color(0x403BE8FF)],
            ).createShader(
              Rect.fromCircle(center: const Offset(_cx, _cy), radius: _r),
            ),
    );
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..color = Ref.cyan
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = Ref.cyan,
    );
    final double kn = math.min(1, kk * 1.4);
    for (int i = 0; i < 6; i++) {
      canvas.drawCircle(
        pts[i],
        4.5,
        Paint()
          ..color = Ref.cyan
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
      canvas.drawCircle(pts[i], 4.5, Paint()..color = Colors.white);
      final Offset lp = pt(i, _r + 28);
      _text(
        canvas,
        ax[i].name,
        Offset(lp.dx, lp.dy - 3),
        refText(size: 13, wght: 500, height: 1, color: Ref.txt),
        baseline: true,
      );
      _text(
        canvas,
        '${((attrs[ax[i].k] ?? 0) * kn).round()}',
        Offset(lp.dx, lp.dy + 15),
        refText(
          family: Ref.fd,
          size: 15,
          wght: 700,
          height: 1,
          color: Ref.violet,
        ),
        baseline: true,
      );
    }
    canvas.restore();
  }

  /// SVG `<text y=…>` 的 y 是基线
  void _text(
    Canvas canvas,
    String t,
    Offset at,
    TextStyle style, {
    bool baseline = false,
  }) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: t, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final double base = baseline
        ? tp.computeDistanceToActualBaseline(TextBaseline.alphabetic)
        : tp.height / 2;
    tp.paint(canvas, at - Offset(tp.width / 2, base));
    tp.dispose();
  }

  @override
  bool shouldRepaint(_RadarPainter o) => o.attrs != attrs;
}
