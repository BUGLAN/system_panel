import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/attrs.dart';
import '../../data/rewards.dart';
import '../../design/ref.dart';
import '../../state/goal.dart';
import '../../state/sfx.dart';
import '../../widgets/frame_throttle.dart';
import '../../widgets/fx_particles.dart';
import 'ref_carousel.dart';
import 'ref_core.dart';
import 'ref_inputs.dart';
import 'ref_kit.dart';
import 'ref_motion.dart';
import 'ref_tcard.dart';
import 'ref_text.dart';

/// ═══════════════════════════════════════════════════════════
///  主线页 —— 参考稿 #sc-main（DOM L719-731，JS L1261-1364）
///
///  .sh（eyebrow + h1 + xbtn）→ .meta（已过 N/M 天 · 完成 X 单 · 剩 K 天）
///  → .daybar → #mainCar（3D 收藏卡轮播 + .ped 光台）→ #mainRuler（节点轨）
///  → .sysbox（46 核心 + SYSTEM + 情绪 + 打字机）→ .actions（去委托板 / 换目标）
///
///  交互（JS mainTap）：已完成卡 → 翻面看战报；当前卡 → 接单（或回执行页）；
///  锁着的卡 → 抖 + 她骂一句。聚焦换卡 240ms 后她换一句台词（mainFocus）。
///  刚完成一单回来（justDone）：压印砸下 → 1.1s 后转到下一张 → 650ms 后解封。
///
///  ⚠️ nohud 场景：上边距取 30（不是 94）。
/// ═══════════════════════════════════════════════════════════
class RefMain extends StatefulWidget {
  const RefMain({
    super.key,
    required this.goal,
    this.lead,
    this.mood,
    this.line,
    this.lineToken = 0,
    this.activeIndex,
    this.elapsed,
    this.justDone,
    this.fx,
    this.onBack,
    this.onScrub,
    this.onTake,
    this.onDispatch,
    this.onSwapGoal,
  });

  final Goal goal;

  /// 初始焦点（null = 当前单）
  final int? lead;

  /// 外部插话（换目标被驳回等）—— [lineToken] 变化时覆盖 sysbox
  final String? mood;
  final String? line;
  final int lineToken;

  /// 正在执行的主线单序号（null = 没在执行主线）
  final int? activeIndex;
  final String? elapsed;

  /// 刚验收完的那一张（播压印 + 解封下一张）
  final int? justDone;

  final FxController? fx;
  final VoidCallback? onBack;
  final ValueChanged<int>? onScrub;

  /// 点当前卡：接这一单（或回执行页）
  final ValueChanged<int>? onTake;
  final VoidCallback? onDispatch;
  final VoidCallback? onSwapGoal;

  @override
  State<RefMain> createState() => _RefMainState();
}

class _RefMainState extends State<RefMain>
    with TickerProviderStateMixin, RefTimers<RefMain> {
  final RefCarouselController _car = RefCarouselController();
  final GlobalKey _carKey = GlobalKey();
  final Set<int> _flipped = <int>{};
  final math.Random _rnd = math.Random();

  late int _focus = _startIndex;
  String _mood = '尚可';
  String _line = '';
  CoreMood _core = CoreMood.neutral;
  Timer? _focusT;
  Timer? _moodT;

  /// justDone 演出：压印进度（0 = 还没砸）/ 下一张仍封着
  int? _sealNext;
  late final AnimationController _stamp = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );

  int? _shakeIdx;
  int _shakeTok = 0;

  int get _total => widget.goal.plan.length;

  /// 当前单（第一张未完成）—— 卡态 / 节点 / 光台用
  int get _done => widget.goal.firstOpenIndex.clamp(0, _total);

  /// 已完成张数 —— 读数用（清单可能不按顺序完成，不能拿当前序号顶）
  int get _count => widget.goal.doneCount;

  int get _startIndex {
    if (_total == 0) return 0;
    if (widget.justDone != null) return widget.justDone!.clamp(0, _total - 1);
    if (widget.lead != null) return widget.lead!.clamp(0, _total - 1);
    return math.min(_done, _total - 1);
  }

  bool get _bike => RegExp(r'骑|单车|自行车').hasMatch(widget.goal.text);

  @override
  void initState() {
    super.initState();
    if (widget.line != null && widget.line!.isNotEmpty) {
      _line = widget.line!;
      _mood = widget.mood ?? _mood;
    }
    final int? j = widget.justDone;
    if (j != null && j < _total) {
      _stamp.value = 0;
      if (j + 1 < _total) _sealNext = j + 1;
      unawaited(_runJustDone(j));
    }
  }

  @override
  void didUpdateWidget(RefMain old) {
    super.didUpdateWidget(old);
    if (widget.lineToken != old.lineToken &&
        widget.line != null &&
        widget.line!.isNotEmpty) {
      _focusT?.cancel();
      setState(() {
        _line = widget.line!;
        if (widget.mood != null) _mood = widget.mood!;
      });
    }
  }

  @override
  void dispose() {
    _focusT?.cancel();
    _moodT?.cancel();
    _stamp.dispose();
    _car.dispose();
    super.dispose();
  }

  // ── 数据 → 卡面 ───────────────────────────────────────────
  RefTCardData _dataOf(PlanTask t) {
    String k = Attr.all.first.k;
    int best = -1;
    t.attrs.forEach((String key, int v) {
      if (v > best) {
        best = v;
        k = key;
      }
    });
    final String name = Attr.nameOf(k);
    return RefTCardData(
      index: t.index,
      total: _total,
      rank: t.rank,
      cat: name.characters.first,
      catName: name,
      title: t.title,
      minutes: t.minutes,
      proof: t.proof,
      exp: Rewards.expOf(t.rank),
      coin: Rewards.coinOf(t.rank),
      boss: t.finalTask,
      bike: _bike,
    );
  }

  RefTCardRecord _recordOf(PlanTask t) {
    final Duration held = t.held ?? Duration(minutes: t.minutes);
    final double ratio = t.minutes <= 0 ? 1 : held.inSeconds / (t.minutes * 60);
    final String r = ratio >= 1 ? 'A' : (ratio >= .5 ? 'B' : 'C');
    return RefTCardRecord(
      rank: r,
      time: held,
      exp: Rewards.expOf(t.rank),
      coin: Rewards.coinOf(t.rank),
      day: widget.goal.passedDays(t.doneAt ?? DateTime.now()),
    );
  }

  RefTCardState _stateOf(int i) {
    if (_sealNext == i) return RefTCardState.lock;
    final PlanTask t = widget.goal.plan[i];
    if (t.done) return RefTCardState.done;
    if (i == _done) return RefTCardState.cur;
    return RefTCardState.lock;
  }

  // ── 她的台词（JS mainFocus）──────────────────────────────
  void _onFocus(int i) {
    if (!mounted || _total == 0) return;
    setState(() => _focus = i);
    widget.onScrub?.call(i);
    _focusT?.cancel();
    _focusT = Timer(const Duration(milliseconds: 240), () {
      if (!mounted) return;
      final int d = _done;
      final PlanTask t = widget.goal.plan[i];
      String mood;
      String txt;
      if (t.done && _sealNext != i) {
        mood = '满意';
        final List<String> pool = <String>[
          '第 [${i + 1}] 单，已验收。别回头看，往前走。',
          '这单你完成得……[勉强]及格。',
          '[${_pad(i + 1)}] 号存档完毕。我记性很好的。',
        ];
        txt = pool[_rnd.nextInt(pool.length)];
      } else if (i == d) {
        mood = '尚可';
        txt = '[$_count/$_total] 单。清单不会自己变短。';
      } else if (t.finalTask) {
        mood = '期待';
        txt = '终局单。[${t.minutes}] 分钟。我会在终点等你——大概。';
      } else {
        mood = '冷静';
        txt = '第 [${i + 1}] 单还锁着。先把眼前那单干掉。';
      }
      setState(() {
        _mood = mood;
        _line = txt;
        _core = t.done ? CoreMood.happy : CoreMood.neutral;
      });
    });
  }

  void _say(String txt, {CoreMood core = CoreMood.neutral, int ms = 0}) {
    _focusT?.cancel();
    setState(() {
      _line = txt;
      _core = core;
    });
    _moodT?.cancel();
    if (ms > 0) {
      _moodT = Timer(Duration(milliseconds: ms), () {
        if (mounted) setState(() => _core = CoreMood.neutral);
      });
    }
  }

  /// 焦点卡中心（RefMain 自己的坐标 = FX 层坐标：两者都铺满同一个 Stack）
  Offset? _cardCenter() {
    final RenderBox? me = context.findRenderObject() as RenderBox?;
    final RenderBox? car =
        _carKey.currentContext?.findRenderObject() as RenderBox?;
    if (me == null || car == null || !car.hasSize) return null;
    return me.globalToLocal(car.localToGlobal(car.size.center(Offset.zero)));
  }

  // ── 点卡（JS mainTap）──────────────────────────────────────
  void _onTap(int i) {
    final PlanTask t = widget.goal.plan[i];
    final RefTCardState st = _stateOf(i);
    if (st == RefTCardState.done) {
      final bool f = !_flipped.contains(i);
      setState(() => f ? _flipped.add(i) : _flipped.remove(i));
      unawaited(Sfx.play('swipe'));
      final Offset? c = _cardCenter();
      if (c != null) {
        // 参考稿 mainTap 翻面：FX.burst type:'star'（八角星，L1328）
        widget.fx?.burst(
          c.dx,
          c.dy,
          n: 16,
          cols: const <Color>[Ref.cyan, Colors.white, Ref.acid],
          min: 60,
          max: 300,
          g: 40,
          life: .9,
          kind: 'star',
          size: 6,
        );
      }
      if (f) {
        final RefTCardRecord r = _recordOf(t);
        _say(
          '第 [${i + 1}] 单战报：评级 [${r.rank}]，用时 ${_mmss(r.time)}。',
          core: r.rank == 'C' ? CoreMood.angry : CoreMood.happy,
          ms: 1400,
        );
      }
    } else if (st == RefTCardState.cur) {
      _take(i);
    } else {
      setState(() {
        _shakeIdx = i;
        _shakeTok++;
      });
      unawaited(Sfx.play('error'));
      _say('还没解锁。[别急着越级]，宿主。', core: CoreMood.angry, ms: 1500);
    }
  }

  void _take(int i) {
    if (widget.activeIndex != i) {
      final Offset? c = _cardCenter();
      if (c != null) {
        widget.fx?.burst(
          c.dx,
          c.dy,
          n: 30,
          cols: const <Color>[Ref.acid, Colors.white],
          min: 180,
          max: 660,
          life: .8,
        );
        widget.fx?.ripple(c.dx, c.dy, r1: 120, color: Ref.acid, w: 4, ms: 500);
      }
    }
    widget.onTake?.call(i);
  }

  // ── 刚完成一单（JS ENTER.main justDone）──────────────────
  Future<void> _runJustDone(int j) async {
    await pause(const Duration(milliseconds: 760));
    if (!mounted) return;
    await _stamp.animateTo(1, curve: Ref.slam);
    if (!mounted) return;
    unawaited(Sfx.play('stamp'));
    final Offset? c = _cardCenter();
    if (c != null) {
      widget.fx?.burst(
        c.dx + 60,
        c.dy - 50,
        n: 34,
        cols: const <Color>[Ref.hot, Colors.white],
        min: 180,
        max: 660,
        life: .8,
      );
      widget.fx?.ripple(c.dx + 60, c.dy - 50, r1: 120, color: Ref.hot, w: 4);
    }
    _say('盖章。[$_count/$_total]，清单短了一点点。');
    if (_count >= _total || j + 1 >= _total) return;
    await pause(const Duration(milliseconds: 1100));
    if (!mounted) return;
    _car.go(j + 1);
    await pause(const Duration(milliseconds: 650));
    if (!mounted) return;
    setState(() => _sealNext = null);
    unawaited(Sfx.play('unlock'));
    await pause(const Duration(milliseconds: 380));
    if (!mounted) return;
    final Offset? c2 = _cardCenter();
    if (c2 != null) {
      widget.fx?.burst(
        c2.dx,
        c2.dy,
        n: 30,
        cols: const <Color>[Ref.acid, Colors.white, Ref.cyan],
        min: 120,
        max: 540,
        g: 60,
      );
      widget.fx?.ripple(c2.dx, c2.dy, r1: 160, color: Ref.acid, w: 3);
    }
    _say('新卡解封：[${widget.goal.plan[j + 1].title}]。别愣着。');
  }

  // ── build ───────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Ref.gutter,
        safe.top + Ref.sceneTopNoHud,
        Ref.gutter,
        safe.bottom + Ref.sceneBottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          RefReveal(index: 0, child: _head()),
          RefReveal(index: 1, child: _meta()),
          RefReveal(index: 2, child: _dayBar()),
          Expanded(child: _carBox()),
          RefReveal(index: 3, child: _ruler()),
          RefReveal(index: 4, child: _sysbox()),
          RefReveal(index: 5, child: _actions()),
        ],
      ),
    );
  }

  Widget _head() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const RefEyebrow(text: 'MAINLINE · 主线', accent: Ref.cyan),
              const SizedBox(height: 8),
              Text(
                widget.goal.text.isEmpty ? '（还没有目标）' : widget.goal.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: RefType.h1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        RefXButton(onTap: widget.onBack, accent: Ref.cyan),
      ],
    );
  }

  Widget _meta() {
    final Goal g = widget.goal;
    final int days = g.days <= 0 ? 14 : g.days;
    final int passed = g.passedDays(DateTime.now()).clamp(1, days);
    final int left = (days - passed).clamp(0, days);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 4,
        children: <Widget>[
          Text('已过', style: RefType.meta),
          Text('$passed/$days', style: RefType.metaNum),
          Text('天 · 完成', style: RefType.meta),
          Text('$_count', style: RefType.metaNum),
          Text('单', style: RefType.meta),
          Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0x40FFFFFF)),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              left <= 0 ? '今天截止' : '剩 $left 天',
              style: refText(size: 13, wght: 400, height: 1.4, color: Ref.txt),
            ),
          ),
        ],
      ),
    );
  }

  /// .daybar：每天一格（3 间距 / 5 高），过去 cyan、今天 acid 闪
  Widget _dayBar() {
    final Goal g = widget.goal;
    final int days = g.days <= 0 ? 14 : g.days;
    final int today = g.passedDays(DateTime.now()).clamp(1, days);
    // 长目标（>30 天）一格一天会细成发丝：按周聚合，保持稿子的「格」感
    final int per = days > 30 ? 7 : 1;
    final int n = (days / per).ceil();
    final int cur = ((today - 1) / per).floor();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < n; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: i == cur
                  ? const RefBlink(
                      child: SizedBox(
                        height: 5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Ref.acid,
                            borderRadius: BorderRadius.all(Radius.circular(1)),
                          ),
                        ),
                      ),
                    )
                  : Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: i < cur ? Ref.cyan : const Color(0x14FFFFFF),
                        borderRadius: BorderRadius.circular(1),
                        boxShadow: i < cur
                            ? const <BoxShadow>[
                                BoxShadow(color: Ref.cyan, blurRadius: 6),
                              ]
                            : null,
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Color get _pedColor {
    if (_total == 0) return Ref.cyan;
    final int i = _focus.clamp(0, _total - 1);
    final PlanTask t = widget.goal.plan[i];
    if (t.done && _sealNext != i) return Ref.cyan;
    if (t.finalTask) return Ref.gold;
    if (i == _done) return Ref.acid;
    return Ref.violet;
  }

  /// .car（flex 1 / min 250 / 左右 −22 出血）
  Widget _carBox() {
    if (_total == 0) {
      return Center(
        child: Text(
          '还没有清单。先去立一个目标。',
          style: refText(size: 14, wght: 500, height: 1.8, color: Ref.dim),
        ),
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) => OverflowBox(
        minWidth: box.maxWidth + Ref.gutter * 2,
        maxWidth: box.maxWidth + Ref.gutter * 2,
        minHeight: math.max(250, box.maxHeight),
        maxHeight: math.max(250, box.maxHeight),
        child: RefCarousel(
          key: _carKey,
          controller: _car,
          count: _total,
          start: _startIndex,
          ar: .66,
          wf: .7,
          maxW: 300,
          pad: 34,
          shadeMode: true,
          compactH: 430,
          onFocus: _onFocus,
          onTap: _onTap,
          // 压暗由轮播叠在卡外（拖动时卡面不重栅格化，docs/49 E2）；
          // 颜色 / 圆角与 RefTCard 内部的 .tc-face 压暗一致
          shadeColor: const Color(0xFF05040A),
          shadeRadius: const BorderRadius.all(Radius.circular(20)),
          underlay: RefPedestal(color: _pedColor),
          itemBuilder: (BuildContext _, int i, RefCarouselSlot slot) {
            final PlanTask t = widget.goal.plan[i];
            final RefTCardState st = _stateOf(i);
            final Widget card = RefTCard(
              key: slot.focus ? const Key('ref.main.card') : null,
              data: _dataOf(t),
              state: st,
              active: widget.activeIndex == i,
              flipped: _flipped.contains(i) && st == RefTCardState.done,
              focus: slot.focus,
              compact: slot.compact,
              shade: slot.shade,
              record: st == RefTCardState.done ? _recordOf(t) : null,
              stamp: widget.justDone == i ? _stamp : null,
            );
            if (_shakeIdx != i) return card;
            return RefShakeX(token: _shakeTok, child: card);
          },
        ),
      ),
    );
  }

  /// #mainRuler（L638-648）：22 圆节点 + 底轨 + 进度光轨
  Widget _ruler() {
    if (_total <= 0) return const SizedBox.shrink();
    // 光轨铺到当前单那一格（参考稿 --pf = done/9）
    final double pf = _total <= 1 ? 1 : (_done / (_total - 1)).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 2),
      child: SizedBox(
        height: 30,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final double w = box.maxWidth;
            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: <Widget>[
                const Positioned(
                  left: 11,
                  right: 11,
                  top: 14,
                  height: 2,
                  child: ColoredBox(color: Color(0x1AFFFFFF)),
                ),
                Positioned(
                  left: 11,
                  top: 14,
                  height: 2,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: pf),
                    duration: const Duration(milliseconds: 1000),
                    curve: Ref.ease,
                    builder: (BuildContext _, double v, Widget? _) => Container(
                      width: (w - 22) * v,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[Ref.cyan, Ref.acid],
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(color: Ref.cyan, blurRadius: 8),
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[for (int i = 0; i < _total; i++) _node(i)],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _node(int i) {
    final PlanTask t = widget.goal.plan[i];
    final bool d = t.done;
    final bool c = i == _done && !d;
    final bool b = t.finalTask;
    final bool on = i == _focus;
    final Color fg = d
        ? const Color(0xFF06222A)
        : (c ? Ref.acid : (b ? Ref.gold : Ref.dim));
    final Color border = d
        ? Ref.cyan
        : (c ? Ref.acid : (b ? Ref.gold : const Color(0x2EFFFFFF)));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _car.go(i);
        unawaited(Sfx.play('soft'));
      },
      child: AnimatedScale(
        scale: on ? 1.32 : 1,
        duration: const Duration(milliseconds: 350),
        curve: Ref.ease,
        child: SizedBox(
          width: 22,
          height: 22,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: <Widget>[
              if (c)
                const Positioned(
                  left: -5,
                  top: -5,
                  right: -5,
                  bottom: -5,
                  child: _PulseRing(),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: d ? Ref.cyan : Ref.ink,
                  border: Border.all(color: border, width: 1.5),
                  boxShadow: <BoxShadow>[
                    if (d && !on)
                      const BoxShadow(color: Color(0x8C3BE8FF), blurRadius: 8),
                    if (on)
                      BoxShadow(
                        color: d
                            ? const Color(0x403BE8FF)
                            : const Color(0x1FFFFFFF),
                        spreadRadius: 3,
                      ),
                    if (on) BoxShadow(color: d ? Ref.cyan : fg, blurRadius: 16),
                  ],
                ),
                child: Text(
                  b ? '★' : '${i + 1}',
                  style: refText(
                    family: Ref.fd,
                    size: 10,
                    wght: 700,
                    height: 1,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// .sysbox（L229-234）
  Widget _sysbox() {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 0, 12),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Ref.cyan, width: 3)),
        gradient: LinearGradient(
          colors: <Color>[Color(0x143BE8FF), Color(0x003BE8FF)],
          stops: <double>[0, .7],
        ),
      ),
      child: Row(
        children: <Widget>[
          RefCore(size: 46, mood: _core),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      'SYSTEM',
                      style: refText(
                        family: Ref.fm,
                        size: 13,
                        wght: 700,
                        ls: 4,
                        height: 1,
                        color: Ref.cyan,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '·····',
                      style: refText(
                        family: Ref.fm,
                        size: 13,
                        wght: 700,
                        ls: 2,
                        height: 1,
                        color: Ref.dim2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _mood,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: refText(
                          size: 12,
                          wght: 500,
                          ls: 1,
                          height: 1,
                          color: Ref.dim,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 26),
                  child: RefTypewriter(
                    key: ValueKey<String>(_line),
                    text: _line,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: refText(
                      size: 17,
                      wght: 500,
                      height: 1.5,
                      color: Ref.txt,
                    ),
                    highlightStyle: refText(
                      family: Ref.fd,
                      size: 17 * 1.15,
                      wght: 700,
                      height: 1.3,
                      color: Ref.cyan,
                      shadows: const <Shadow>[
                        Shadow(color: Ref.cyan, blurRadius: 12),
                      ],
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

  /// .actions：去委托板（pri，flex 1）+ 换目标（ghost）
  Widget _actions() {
    return Row(
      children: <Widget>[
        Expanded(
          child: RefButton(
            key: const Key('ref.main.toBoard'),
            label: '去委托板',
            trailingTriangle: true,
            onTap: widget.onDispatch,
          ),
        ),
        const SizedBox(width: 12),
        RefButton(
          key: const Key('ref.main.swapGoal'),
          label: '换目标',
          primary: false,
          animateSheen: false,
          onTap: widget.onSwapGoal,
        ),
      ],
    );
  }
}

String _pad(int n) => n.toString().padLeft(2, '0');
String _mmss(Duration d) =>
    '${_pad(d.inMinutes)}:${_pad(d.inSeconds.remainder(60))}';

/// 当前节点外圈的呼吸环（tcpulse 1.4s：scale 1 → 1.35，透明 1 → .5）
class _PulseRing extends StatefulWidget {
  const _PulseRing();
  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  /// 1.4s 呼吸环，30fps 足够；60fps 会让主线页多一层逐帧 Opacity+Transform。
  late final FrameThrottle _paintTick = FrameThrottle(33);

  @override
  void initState() {
    super.initState();
    _c.addListener(_paintTick.pulse);
  }

  @override
  void dispose() {
    _c.removeListener(_paintTick.pulse);
    _paintTick.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _paintTick,
      builder: (BuildContext _, Widget? _) {
        final double e = Curves.easeInOut.transform(
          math.sin(_c.value * math.pi),
        );
        return Opacity(
          opacity: 1 - .5 * e,
          child: Transform.scale(
            scale: 1 + .35 * e,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Ref.acid, width: 1.5),
              ),
            ),
          ),
        );
      },
    );
  }
}
