import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../data/rarity.dart';
import '../design/tokens.dart';
import '../state/haptics.dart';
import '../state/host_state.dart';
import '../state/quest.dart';
import '../state/sfx.dart';
import 'hold_button.dart';
import 'press_scale.dart';
import 'plate_timeline.dart';

/// ═══════════════════════════════════════════════════════════
///  派单板（app.css L242-303 `#plate` · ui.js `Plate.build`）
///  一块被她刻上字的玻璃：TO/单号 → 主线第几环 → 大字标题 → 附言
///  → 证明/时限/报酬 → 按住指纹。右上角是等级骰子。
///
///  实测盒模型（390×844，C 级主线第 5 环）：
///    plate/glass/in [16,396,358,384] · head [36,414,318,10]
///    kind [36,442,128,10] · title [36,462,229,64] · why [36,538,307,22]
///    spec [36,573,318,63] · print [36,672,318,108] · fp [104,692,62,70]
///    rank [272,430,86,104] · ring [276,430,78,78] · letter [302,443,25,52]
///    meter [278,517,74,4] · edge [52,778,286,2]
///
///  砸落动画已做；**骰子滚动 / 激光刻字 / 按住指纹**属于行为，等宿主约束，
///  这里渲染的是「已经刻完字、等她点头」的静态样子。
/// ═══════════════════════════════════════════════════════════
/// docs/41 §6.5：揭示可跳过的**防误触窗口**（前 90ms 不响应点击）
const int kRankSkipGuardMs = 90;

class Plate extends StatefulWidget {
  const Plate({
    super.key,
    required this.quest,
    required this.host,
    this.visible = true,
    this.animateLand = true,
    this.onAccept,
    this.onRankFx,
    // docs/41 §6.5：揭示可跳过。整屏点一下 —— 前 90ms 不响应（防误触），
    // 之后任何点击直接把滚档**落终态**（不是「跳过动画」，是「立即结算」）。
    this.skipToken = 0,
    this.onWaver,
  });

  final Quest quest;
  final HostState host;
  final bool visible;

  /// 砸落动画（ui.js `land()`）；比对截图时也会自然落到终态
  final bool animateLand;

  /// 按住指纹 0.9s 才接单
  final VoidCallback? onAccept;

  /// 稀有度滚完那一刻（原型在这里 flash + shake + glitch + burst）
  final ValueChanged<int>? onRankFx;

  /// 每 +1 = 宿主点了一下屏幕（来自 main 的整屏 tap）
  final int skipToken;

  /// 按指纹按到一半松手（`p > .25` 才说，且只说一次）
  final VoidCallback? onWaver;

  @override
  State<Plate> createState() => _PlateState();
}

class _PlateState extends State<Plate> with TickerProviderStateMixin {
  // CSS cubic-bezier(.2,.75,.25,1)
  static const Curve _landCurve = Cubic(.2, .75, .25, 1);

  late final AnimationController _land = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );

  /// 稀有度滚动（`Plate.rankRoll` 的那个 for 循环）
  late final AnimationController _roll = AnimationController(vsync: this);

  /// 激光逐段刻字（`Plate.engrave` 的那个 for 循环）
  late final AnimationController _eng = AnimationController(vsync: this);

  /// 正在滚的时间线（上行 `RankRollTimeline` / 下行 `_ReRankRoll` 共用驱动，
  /// 这里只存「给 t 算档位」的纯函数，界面不关心它往哪边滚）
  int Function(double)? _rollIndexAt;
  double _rollTotal = 0;

  /// 仪式的代际号：换单 / reRank 各 +1，作废还在飞的那一场
  /// （板下「换一个」在开局仪式没播完时就能点，不防会两头一起驱动控制器）
  int _gen = 0;

  /// rankLock / 报酬白闪的重播令牌（`TweenAnimationBuilder` 换 key 才会重播）
  int _lockToken = 0;
  int _rewardToken = 0;
  EngraveTimeline? _engTl;

  /// 此刻显示到第几档
  int _shownIndex = 0;

  /// `rankLock` 那一下（CSS `@keyframes rankLock`）
  bool _lock = false;

  /// 每一段的刻字进度
  List<double> _engK = <double>[1, 1, 1, 1, 1, 1, 1, 1];

  /// 激光头的位置（相对玻璃板）
  Offset? _laser;

  /// 正在被刻的那一段（`.hot`），-1 = 没有
  int _hotIndex = -1;

  /// `#plPrint` 的不透明度：刻完才有（原型 `opacity = .25` → `1`）
  double _printOpacity = 1;

  /// 每一段在玻璃板里的位置（激光要按它走）
  final List<GlobalKey> _engKeys = List<GlobalKey>.generate(
    8,
    (int _) => GlobalKey(),
  );

  /// 八段刻字的文案长度（原型用 `e.textContent.length` 定时长）
  List<int> get _engLengths => <int>[
    'TO · ${widget.host.name} · LV${widget.host.lv}'.length,
    widget.quest.serialText.length,
    widget.quest.kindLabel.length,
    widget.quest.name.length,
    widget.quest.reason.length,
    '证明${widget.quest.proof}'.length,
    '时限${widget.quest.minutesText}'.length,
    // t24：loot 面板只读 quest.lootText（结算经济口径），刻字长度跟着同一句文案走
    '报酬${widget.quest.lootText}'.length,
  ];

  @override
  void initState() {
    super.initState();
    if (widget.visible) _start();
  }

  /// ⚠️ **不能只在 initState 里启动** —— `Plate` 从开机起就挂在树里
  /// （只是 `visible: false`），initState 那会儿仪式就演完一遍了，
  /// 等宿主真点进派单板时看到的是终态（实机踩过：连拍 5 帧一模一样）。
  /// 原型是 `Plate.build()` + `land()` 在**派单那一刻**才跑，所以这里跟着 visible 走。
  @override
  void didUpdateWidget(covariant Plate old) {
    super.didUpdateWidget(old);
    if (!old.visible && widget.visible) {
      _start();
    // docs/41 §6.5：揭示可跳过。
    //
    // 规则：**前 90ms 不响应**（防误触 —— 宿主可能正好在点别处），
    // 之后任何一次点击把滚档**直接落终态**（不是「加速」，是立即结算）。
    // 为什么是「落终态」而不是「跳过动画」：稀有度决定报酬/暴击率，
    // 迟一拍让玩家点空，等于让他多等一次不确定的时长。
    if (widget.skipToken != old.skipToken && _roll.isAnimating) {
      final double elapsedMs = _roll.value * _rollTotal;
      if (elapsedMs >= kRankSkipGuardMs) {
        _roll.stop();
        _roll.value = 1;
      }
    }
    } else if (widget.visible) {
      if (old.quest.serial != widget.quest.serial) {
        _start(); // 换单 = 重新刻一块
      } else if (old.quest.rarity.i != widget.quest.rarity.i) {
        // t26/TODO-12：「换一个」的降档重刻 —— 同一张单（serial 不变）只动了
        // 稀有度。播原型 `Plate.reRank` 的下行滚档 + 报酬重刻，
        // 替代原来的静态跳变（判定从「serial 变了」扩成「serial 或档位变了」）。
        _rerank(from: old.quest.rarity.i);
      }
    }
  }

  void _start() {
    _gen++;
    _roll.removeListener(_onRollTick);
    _eng.removeListener(_onEngTick);
    _shownIndex = 0;
    _lock = false;
    _engK = List<double>.filled(8, 0);
    _printOpacity = .25;
    _roll.value = 0;
    _eng.value = 0;
    _laser = null;
    _hotIndex = -1;
    if (widget.animateLand) {
      _land
        ..value = 0
        ..forward().then((void _) => _ceremony());
      // 委托单落板（`ui.js:238`）：落板动画 560ms 跑到 **440ms** 的那一下
      // —— 原型是 `await sleep(440)` 之后 `Sound.play('land'); FX.shake(3,200); buzz(18)`。
      // `_gen` 保证被换单/重刻作废的那一场不再发声（一次事件只发一次）。
      final int g = _gen;
      Future<void>.delayed(const Duration(milliseconds: 440), () {
        if (!mounted || g != _gen) return;
        Sfx.play('land');
        Haptics.buzz('land');
      });
    } else {
      // 静态比对：直接落在终态，渲染结果与以前逐字节一致
      _land.value = 1;
      _shownIndex = widget.quest.rarity.i;
      _engK = List<double>.filled(8, 1);
      _printOpacity = 1;
    }
  }

  /// 落板 → 揭稀有度 → 逐字刻 → 指纹可用（`flows.js` L279 的调用顺序）
  Future<void> _ceremony() async {
    final int g = _gen;
    if (!mounted) return;
    // ⚠️ 原型的 `land()` 在动画后再等 440 + 150ms 才 resolve
    await Future<void>.delayed(const Duration(milliseconds: 590));
    if (!mounted || g != _gen) return;
    await _rankRoll();
    if (!mounted || g != _gen) return;
    await _engrave();
  }

  Future<void> _rankRoll() async {
    final RankRollTimeline tl = RankRollTimeline(target: widget.quest.rarity.i);
    await _playRoll(
      total: tl.total,
      indexAt: tl.indexAt,
      onFinish: () {
        if (!mounted) return;
        setState(() => _lock = true); // 末级砸下来那一下
        // 原型 `rankRoll` 收尾：flash（稀有度色）· ≥S 抖一下 · 骰子位置爆一圈
        widget.onRankFx?.call(tl.target);
      },
    );
  }

  /// t26/TODO-12 —— 「换一个」的降档重刻（原型 `ui.js Plate.reRank(T, from)`）：
  ///
  /// ```js
  /// async reRank(T, fromR) { // 退缩：字母往下掉一档，报酬重刻
  ///   await this.rankRoll(T.r, RARITY[fromR].i, true);
  ///   const rw = $('#plReward'); rw.classList.remove('done'); … rw.classList.add('done');
  ///   rw.animate([{ filter: 'brightness(2.5)' }, { filter: 'none' }], { duration: 600 });
  /// }
  /// ```
  ///
  /// 下行滚档的每档停留按 MOTION-ANALYSIS P1-3 的规格收敛为 90ms
  /// （三档下行 = 270ms，见 [_ReRankRoll]）；滚完复用同一个 rankLock
  /// （600ms easeOutBack，换 token 重挂重播）+ `onRankFx` 收尾，
  /// 最后报酬行单独重刻一遍（激光照走 + 600ms 白闪收敛）。
  Future<void> _rerank({required int from}) async {
    final int target = widget.quest.rarity.i;
    _gen++; // 作废还在飞的开局仪式
    if (!widget.animateLand || from <= target) {
      // 静态比对（或异常防御）：直接落终态，渲染结果与旧版逐字节一致
      if (!mounted) return;
      setState(() {
        _shownIndex = target;
        _lock = true;
        _lockToken++;
        _engK = List<double>.filled(8, 1);
        _printOpacity = 1;
        _laser = null;
        _hotIndex = -1;
      });
      return;
    }
    final _ReRankRoll tl = _ReRankRoll(from: from, target: target);
    await _playRoll(
      total: tl.total,
      indexAt: tl.indexAt,
      onFinish: () {
        if (!mounted) return;
        setState(() {
          _lock = true;
          _lockToken++; // rankLock 换 key 重挂 → 每次降档都砸那一下
        });
        // 原型 rankRoll 的收尾对 down 分支同样生效（flash/burst，≥S 抖）
        widget.onRankFx?.call(target);
      },
    );
    if (!mounted) return;
    await _reengraveReward();
  }

  /// 报酬行重刻（原型 `reRank` 后半段：`#plReward` 摘掉 `.done` 重新划入，
  /// 收一个 600ms `brightness(2.5)→none` 的白闪）。只重刻第 7 段，激光照走一遍；
  /// 指纹不动（原型也没把它按回去）。
  Future<void> _reengraveReward() async {
    final int g = _gen;
    final double dur =
        ((_engLengths[7] * 17).clamp(110.0, 460.0)).toDouble();
    // 新 loot 文案刚换上，等一帧布局才量得到激光要走的路
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted || g != _gen) return;
    setState(() {
      _engK = List<double>.from(_engK)..[7] = 0;
      _rewardToken++;
    });
    _eng
      ..duration = Duration(milliseconds: dur.round())
      ..addListener(_onRewardTick);
    final Completer<void> done = Completer<void>();
    _eng.forward(from: 0).then((void _) => done.complete());
    await done.future;
    if (!mounted || g != _gen) return;
    _eng.removeListener(_onRewardTick);
    setState(() {
      _laser = null;
      _hotIndex = -1;
      _engK = List<double>.from(_engK)..[7] = 1;
    });
  }

  void _onRewardTick() {
    final double k = _eng.value;
    setState(() {
      _engK = List<double>.from(_engK)..[7] = k;
      _hotIndex = k < 1 ? 7 : -1;
      final Rect? r = _localRect(7);
      _laser = r == null ? null : Offset(r.left + r.width * k, r.center.dy);
    });
  }

  /// 上行/下行滚档共用的驱动：给一条「t → 档位」的纯函数，控制器从头播到尾。
  /// 播完落定终档再触发 [onFinish]（锁 + 特效收尾）；中途 `_gen` 变了就地退出。
  Future<void> _playRoll({
    required double total,
    required int Function(double) indexAt,
    VoidCallback? onFinish,
  }) async {
    final int g = _gen;
    // 起手那一档（`ui.js:251` 的 `set(from); Sound.play('rung', from)`）——
    // 首帧 `_onRollTick` 里 `i == _shownIndex` 不会换档，所以这一发在这里补。
    Sfx.play('rung');
    if (total <= 0) {
      if (mounted) setState(() => _shownIndex = indexAt(0));
      _rankSettled(indexAt(0));
      onFinish?.call();
      return;
    }
    _rollIndexAt = indexAt;
    _rollTotal = total;
    _roll
      ..duration = Duration(milliseconds: total.round())
      ..addListener(_onRollTick);
    final Completer<void> done = Completer<void>();
    _roll.forward(from: 0).then((void _) => done.complete());
    await done.future;
    if (!mounted || g != _gen) return; // 被换单/重刻打断
    _roll.removeListener(_onRollTick);
    final int settled = indexAt(total);
    setState(() => _shownIndex = settled);
    _rankSettled(settled);
    onFinish?.call();
  }

  /// 稀有度落定（`ui.js:263`）：原型就是**带档位**的一发 —— `Sound.play('rank', target)`
  /// （`target = RARITY[r].i`，F~S = 0..6），所以总线上对到 `rank_<i>.wav`。
  /// [target] 与震动的门限同源：它一直是**稀有度档位索引**（上行 = `RankRollTimeline.target`
  /// = `quest.rarity.i`；下行 = `_ReRankRoll` 的目标档），不是我另造的数。
  /// 震动只在 **target ≥ 5** 那两档（原型 `if (target >= 5) { … buzz([20,30,50]) }`）。
  void _rankSettled(int target) {
    Sfx.play('rank', variant: target);
    if (target >= 5) Haptics.buzz('rank');
  }

  void _onRollTick() {
    final int Function(double)? at = _rollIndexAt;
    if (at == null) return;
    final int i = at(_roll.value * _rollTotal);
    if (i != _shownIndex) {
      // 每滚一档一发（`ui.js:251` / `ui.js:254` 两次 `Sound.play('rung', i)`）
      Sfx.play('rung');
      setState(() => _shownIndex = i);
    }
  }

  Future<void> _engrave() async {
    final int g = _gen;
    final EngraveTimeline tl = EngraveTimeline(_engLengths);
    _engTl = tl;
    if (tl.total <= 0) return;
    setState(() {
      _engK = List<double>.filled(8, 0);
      _printOpacity = .25;
    });
    // 位置要等一帧布局完才量得到
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted || g != _gen) return;
    _eng
      ..duration = Duration(milliseconds: tl.total.round())
      ..addListener(_onEngTick);
    final Completer<void> done = Completer<void>();
    _eng.forward().then((void _) => done.complete());
    await done.future;
    _eng.removeListener(_onEngTick);
    if (!mounted || g != _gen) return;
    setState(() {
      _laser = null;
      _printOpacity = 1; // 刻完指纹才能按（原型 `.4s` 过渡）
    });
  }

  void _onEngTick() {
    final EngraveTimeline? tl = _engTl;
    if (tl == null) return;
    final double t = _eng.value * tl.total;
    final int active = tl.activeAt(t);
    setState(() {
      _engK = <double>[for (int i = 0; i < 8; i++) tl.kAt(i, t)];
      _hotIndex = -1;
      for (int i = 0; i < 8; i++) {
        if (tl.hotAt(i, t)) {
          _hotIndex = i; // `.hot` 刻完还热 420ms（原型那段 setTimeout）
          break;
        }
      }
      if (active < 0) {
        _laser = null;
      } else {
        final Rect? r = _localRect(active);
        _laser = r == null
            ? null
            : Offset(r.left + r.width * tl.kAt(active, t), r.center.dy);
      }
    });
  }

  /// 按指纹按到一半松手；`_wavered` 保证一整块板子只说一次（原型 `this._wavered`）
  bool _wavered = false;

  void _onRelease(double p) {
    if (p <= .25 || _wavered) return;
    _wavered = true;
    widget.onWaver?.call();
  }

  /// 第 i 段在玻璃板坐标系里的位置（原型 `rel(e)`）
  Rect? _localRect(int i) {
    final RenderBox? box =
        _engKeys[i].currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? root = context.findRenderObject() as RenderBox?;
    if (box == null || root == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero, ancestor: root) & box.size;
  }

  @override
  void dispose() {
    _land.dispose();
    _roll.dispose();
    _eng.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    // 落点：她的胸口（原型用 Stage.toScreen(0, NY.chest) 算，这里是 boot 镜头实测值）
    const double chestX = 195, chestY = 375.67;
    const double plateCx = 16 + 358 / 2;
    const double plateTop = 844 - 64 - 384;
    const double fromX = chestX - plateCx;
    const double fromY = chestY - plateTop;

    return Positioned(
      left: 16,
      right: 16,
      bottom: 64,
      height: 384,
      child: AnimatedBuilder(
        animation: _land,
        builder: (BuildContext _, Widget? child) {
          final double t = _landCurve.transform(_land.value);
          // 关键帧在 plate_timeline.dart（可单测）：0 → .8 过冲到 1.035，
          // 再在 .8 → 1 之间弹回 1（`.8` 那帧是 rotateX -5deg）
          final ({double scale, double rxDeg}) kf = landKeyframes(t);
          final double inv = 1 - t;
          final Matrix4 m = Matrix4.identity()
            ..setEntry(3, 2, -1 / 900) // perspective: 900px
            ..translateByDouble(fromX * inv, fromY * inv, 0, 1)
            ..rotateX(kf.rxDeg * math.pi / 180)
            ..scaleByDouble(kf.scale, kf.scale, 1, 1);
          return Opacity(
            // 关键帧：0 透明 → .35 就 1
            opacity: (_land.value / .35).clamp(0, 1),
            child: Transform(
              alignment: Alignment.center,
              transform: m,
              child: child,
            ),
          );
        },
        child: _Glass(
          key: const Key('plate'),
          quest: widget.quest,
          host: widget.host,
          onAccept: widget.onAccept,
          onWaver: _onRelease,
          engKeys: _engKeys,
          reveal: PlateReveal(
            shownIndex: _shownIndex,
            lock: _lock,
            lockToken: _lockToken,
            rewardToken: _rewardToken,
            engK: _engK,
            printOpacity: _printOpacity,
            laser: _laser,
            hotIndex: _hotIndex,
          ),
        ),
      ),
    );
  }
}

/// 揭晓进行到哪了 —— `Plate.rankRoll` / `Plate.engrave` 两个循环的当前状态。
///
/// 静态比对（`animateLand: false`）时它落在终态：全亮、指纹可点，
/// 所以**不会改变任何既有截图的观感**。
class PlateReveal {
  const PlateReveal({
    required this.shownIndex,
    this.lock = false,
    this.lockToken = 0,
    this.rewardToken = 0,
    this.engK = const <double>[1, 1, 1, 1, 1, 1, 1, 1],
    this.printOpacity = 1,
    this.laser,
    this.hotIndex = -1,
  });

  /// 此刻显示到第几档稀有度（0 基）
  final int shownIndex;

  /// `rankLock` 那一下
  final bool lock;

  /// rankLock 的重播令牌 —— reRank 每次降档都换新值，
  /// `TweenAnimationBuilder` 换 key 重挂才会再砸一下（原型是摘类再贴回）
  final int lockToken;

  /// 报酬白闪的重播令牌（原型 `reRank` 的 `brightness(2.5)→none` 600ms）
  final int rewardToken;

  /// 八段刻字各自的进度
  final List<double> engK;

  /// `#plPrint` 的不透明度
  final double printOpacity;

  /// 激光头位置（相对玻璃板）
  final Offset? laser;

  /// 正在被刻的那一段（带 `.hot`），-1 = 没有
  final int hotIndex;
}

/// `clip-path: inset(-20% X% -20% 0)` —— 从左往右刻出来
class _EngraveClipper extends CustomClipper<Rect> {
  const _EngraveClipper(this.k);

  final double k;

  @override
  Rect getClip(Size s) =>
      Rect.fromLTRB(0, -s.height * .2, s.width * k, s.height * 1.2);

  @override
  bool shouldReclip(_EngraveClipper old) => old.k != k;
}

/// 玻璃板：斜切玻璃 + 内容 + 稀有度骰子（`Plate.build` 的 DOM 部分）
class _Glass extends StatelessWidget {
  const _Glass({
    super.key,
    required this.quest,
    required this.host,
    this.onAccept,
    this.onWaver,
    this.reveal = const PlateReveal(shownIndex: 0),
    this.engKeys,
  });

  final Quest quest;
  final HostState host;
  final VoidCallback? onAccept;

  /// 按指纹没按满就松手（进度回调，阈值由上层判）
  final ValueChanged<double>? onWaver;

  /// 揭晓状态（默认终态）
  final PlateReveal reveal;

  /// 八段刻字各自的 key —— 激光要按它们的位置走（原型 `rel(e)`）
  final List<GlobalKey>? engKeys;

  /// `[data-eng]` —— 激光逐字刻出来的那一段。
  ///
  /// 原型靠 CSS：`clip-path: inset(-20% 100% -20% 0)`，`.done` 时右边距归零。
  /// **刻完（k ≥ 1）时直接返回 child，不套 ClipRect** —— 这样静态比对
  /// （`animateLand: false`）下渲染树与以前逐字节一致，绝不会影响既有截图。
  Widget _eng(int i, Widget child) {
    final double k = i < reveal.engK.length ? reveal.engK[i] : 1;
    // KeyedSubtree 不产生 RenderObject（零视觉影响），但它的 element 能反查到
    // 子节点的 RenderBox —— 激光就是靠它定位的
    // `.hot`：正在被刻的那一段整段翻白（CSS `color: #fff` + 白光），
    // 用 srcATop 把子树的颜色换成白、保留原透明度 —— 最近似的一步
    final bool hot = reveal.hotIndex == i && k > 0;
    Widget body = child;
    if (hot) {
      body = ColorFiltered(
        colorFilter: const ColorFilter.mode(
          Color(0xFFFFFFFF),
          BlendMode.srcATop,
        ),
        child: body,
      );
    }
    final Widget keyed = KeyedSubtree(key: engKeys?[i], child: body);
    if (k >= 1) return keyed;
    return ClipRect(clipper: _EngraveClipper(k), child: keyed);
  }

  @override
  Widget build(BuildContext context) {
    final Color rk = quest.rarity.color;
    return Stack(
      children: <Widget>[
        // .pl-glass 的底：斜向深蓝玻璃 + 底部稀有度辉光
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment(-.31, -.95),
                        end: Alignment(.31, .95),
                        colors: <Color>[
                          Color(0xEB183662),
                          Color(0xF508142C),
                          Color(0xFB040A18),
                        ],
                        stops: <double>[0, .40, 1],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(painter: _PlateGlowPainter(color: rk)),
                ),
                // .pl-glass::before —— 细扫描线
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: const _ScanlinePainter()),
                  ),
                ),
                // .pl-sheen —— 玻璃反光（inset -40% + translate(-20%,0)）
                Positioned(
                  left: -358 * .4,
                  top: -384 * .4,
                  width: 358 * 1.8,
                  height: 384 * 1.8,
                  child: IgnorePointer(
                    child: Transform.translate(
                      offset: Offset(-358 * 1.8 * .2, 0),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(-.91, -.42),
                            end: Alignment(.91, .42),
                            colors: <Color>[
                              Color(0x00DCFAFF),
                              Color(0x24DCFAFF),
                              Color(0x05DCFAFF),
                              Color(0x00DCFAFF),
                            ],
                            stops: <double>[.38, .48, .54, .60],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 1px 内描边 + 顶边高光（CSS 的两条 inset 阴影）
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0x5238E1FF), width: 1),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 1,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(color: const Color(0x8CC8F5FF)),
            ),
          ),
        ),
        // .pl-edge —— 底缘那道光
        Positioned(
          left: 358 * .1,
          right: 358 * .1,
          bottom: 0,
          height: 2,
          child: DecoratedBox(
            key: const Key('plate.edge'),
            decoration: BoxDecoration(
              color: rk.withAlpha(230),
              boxShadow: <BoxShadow>[
                BoxShadow(color: rk, blurRadius: 14),
                BoxShadow(color: rk, blurRadius: 40),
              ],
            ),
          ),
        ),
        // 内容
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _head(),
                const SizedBox(height: 18),
                // t26 视觉目检补的防线：三行标题（+两行附言）的长单会把
                // 中段撑到 384 盒子外（实测 BOTTOM OVERFLOWED BY 19 PIXELS，
                // 指纹被顶下板）。中段改为「吃掉余量、不够则可滚」——
                // 常规单渲染与旧版逐字节一致（滚动量为 0），长单不再破版。
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _eng(
                          2,
                          Text(
                            quest.kindLabel,
                            style: fs(
                              family: F.mono,
                              size: 10,
                              wght: 600,
                              ls: 2,
                              height: 1,
                              color: C.blue,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 64),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 92),
                            child: _eng(
                              3,
                              Text(
                                quest.name,
                                style: fs(
                                  family: F.hd,
                                  size: 26,
                                  wght: 400,
                                  ls: .52,
                                  height: 1.22,
                                  color: const Color(0xFFF4FDFF),
                                  shadows: <Shadow>[
                                    Shadow(
                                      color: C.blue.withAlpha(89),
                                      blurRadius: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _why(),
                        const SizedBox(height: 14),
                        _spec(),
                      ],
                    ),
                  ),
                ),
                // `#plPrint` 要刻完字才可点（原型 `opacity = .25` → `1`）
                Opacity(opacity: reveal.printOpacity, child: _print(rk)),
              ],
            ),
          ),
        ),
        // .laser —— 刻字时那点白激光（原型按 `rel(e)` 每帧定位）
        if (reveal.laser != null)
          Positioned(
            left: reveal.laser!.dx - 3,
            top: reveal.laser!.dy - 3,
            width: 6,
            height: 6,
            child: IgnorePointer(
              child: DecoratedBox(
                key: const Key('plate.laser'),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFFFFF),
                  boxShadow: <BoxShadow>[
                    const BoxShadow(color: Color(0xFFFFFFFF), blurRadius: 6),
                    BoxShadow(color: C.blue, blurRadius: 16),
                    BoxShadow(color: C.blue, blurRadius: 32),
                  ],
                ),
              ),
            ),
          ),
        // .pl-rank
        Positioned(
          right: 16,
          top: 34,
          width: 86,
          height: 104,
          child: _Rank(
            key: const Key('plate.rank'),
            quest: quest,
            shownIndex: reveal.shownIndex,
            lock: reveal.lock,
            lockToken: reveal.lockToken,
          ),
        ),
      ],
    );
  }

  Widget _head() {
    final TextStyle base = fs(
      family: F.mono,
      size: 9.5,
      wght: 500,
      ls: 1.14,
      height: 1,
      color: C.mist,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        _eng(
          0,
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(text: 'TO · ', style: base),
                TextSpan(
                  text: host.name,
                  style: base.copyWith(
                    color: C.ice,
                    fontVariations: const <FontVariation>[
                      FontVariation('wght', 700),
                    ],
                  ),
                ),
                TextSpan(text: ' · LV${host.lv}', style: base),
              ],
            ),
          ),
        ),
        _eng(1, Text(quest.serialText, style: base)),
      ],
    );
  }

  /// .pl-why —— 带「附言」小牌的那句
  Widget _why() {
    if (quest.reason.isEmpty) return const SizedBox.shrink();
    return _eng(
      4,
      Text.rich(
        TextSpan(
          children: <InlineSpan>[
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: C.blue,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '附言',
                  style: fs(
                    family: F.mono,
                    size: 9.5,
                    wght: 600,
                    ls: 1.14,
                    height: 1.3,
                    color: C.deep,
                  ),
                ),
              ),
            ),
            TextSpan(
              text: quest.reason,
              style: fs(
                family: F.cn,
                size: 13.5,
                wght: 400,
                height: 1.6,
                color: const Color(0xFFB4C8E2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// .pl-spec —— 证明 / 时限 / 报酬
  Widget _spec() {
    final TextStyle dt = fs(
      family: F.mono,
      size: 10,
      wght: 500,
      ls: 1,
      height: 1,
      color: C.dim,
    );
    final TextStyle dd = fs(family: F.cn, size: 13, wght: 400, color: C.ice);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _eng(5, _specRow('证明', Text(quest.proof, style: dd), dt)),
        const SizedBox(height: 7),
        _eng(6, _specRow('时限', Text(quest.minutesText, style: dd), dt)),
        const SizedBox(height: 7),
        _eng(
          7,
          _rewardFlash(
            _specRow(
              '报酬',
              Text(
                // t24：报酬行**只能**读 quest.lootText 这一份真源（含补救 ×0.5）。
                // t15 那版在这里自己拼 `Rewards.expOf/coinOf(rank)`，丢了
                // `kind == 'remedy' ? .5 : 1` —— 同 E 级补救单两块板显示
                // `EXP 1 · ◈ 5` / `EXP 0 · ◈ 3`，都与结算真源 `1/3` 不符。
                // 现在整句文案由 Quest.lootTextOf → Rewards.payout 派生，
                // 显示与结算同源，第三次复发无处可藏（plate_test 钉死）。
                quest.lootText,
                style: fs(
                  family: F.num,
                  size: 13,
                  wght: 700,
                  ls: .39,
                  color: C.blue,
                ),
              ),
              dt,
            ),
          ),
        ),
      ],
    );
  }

  Widget _specRow(String label, Widget value, TextStyle dtStyle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        SizedBox(width: 34, child: Text(label, style: dtStyle)),
        const SizedBox(width: 12),
        value,
      ],
    );
  }

  /// 报酬行的重刻白闪（原型 `reRank` 的
  /// `rw.animate([{filter:'brightness(2.5)'},{filter:'none'}], 600)`，
  /// 近似成一帧 55% 白罩 600ms ease-out 收没）。`rewardToken == 0` 时
  /// （开局仪式 / 静态比对）零包裹，渲染树与旧版逐字节一致。
  Widget _rewardFlash(Widget child) {
    if (reveal.rewardToken == 0) return child;
    return Stack(
      children: <Widget>[
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: TweenAnimationBuilder<double>(
              key: ValueKey<int>(reveal.rewardToken),
              tween: Tween<double>(begin: .55, end: 0),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              builder: (BuildContext _, double k, Widget? grandChild) =>
                  k <= 0 ? const SizedBox.shrink() : ColoredBox(
                    color: Colors.white.withAlpha((k * 255).round()),
                    child: grandChild,
                  ),
            ),
          ),
        ),
      ],
    );
  }

  /// .pl-print —— 按住指纹那一块（ui.js `Plate.hold()`）
  ///
  /// **按满 0.9s** 才算接单；松手以 0.35s 退回。文字三态：
  /// `按住 · 接下` → `确认中` → `已接下`；副标题 `HOLD TO ACCEPT` → `宿主认证 N%`。
  Widget _print(Color rk) {
    return HoldButton(
      duration: const Duration(milliseconds: 900),
      decay: const Duration(milliseconds: 350),
      steps: 8, // 每推进 1/8 打一下（原型在此处放音效 + 5ms 震）
      // 按住每 1/8 步（`ui.js:313`）：原型 `buzz(5)`。音效本批没烘，只上震动。
      onStep: (double _) => Haptics.buzz('hold'),
      onComplete: () {
        // 按满接单（`ui.js:346` `Plate.seal()` 的起手）：
        // `Sound.play('seal'); FX.flash('#bff6ff',.24,280); FX.shake(4,220); buzz([30,40,60])`
        // —— 视觉那半在 main.dart 的 `onAccept` 链路，声音/震动这两发在这里。
        // `HoldButton` 内部 `_fired` 闩住，一整轮按住只会走到这里一次。
        Sfx.play('seal');
        Haptics.buzz('seal');
        onAccept?.call();
      },
      // 没按满就松手 → 上层判 `p > .25` 说那句 `waver`（原型 `Plate.hold()` 的 `up()`）
      onRelease: onWaver,
      builder: (BuildContext context, double p) => Container(
        key: const Key('plate.print'),
        height: 108,
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0x2938E1FF), width: 1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              key: const Key('plate.fp'),
              width: 62,
              height: 70,
              child: _Fingerprint(progress: p),
            ),
            const SizedBox(width: 16),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  p > 0 ? (p >= 1 ? '已接下' : '确认中') : '按住 · 接下',
                  style: fs(
                    family: F.hd,
                    size: 17,
                    wght: 400,
                    ls: 1.36,
                    height: 1,
                    color: C.ice,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  p > 0 ? '宿主认证 ${(p * 100).round()}%' : 'HOLD TO ACCEPT',
                  style: fs(
                    family: F.mono,
                    size: 9.5,
                    wght: 500,
                    ls: 1.33,
                    height: 1,
                    color: C.mist,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// .pl-glass 底部那团稀有度辉光（椭圆 radial，Flutter 的 RadialGradient 是正圆）
class _PlateGlowPainter extends CustomPainter {
  const _PlateGlowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final Offset center = Offset(s.width * .5, s.height * 1.05);
    final double r = s.width * 1.20;
    final double ky = (s.height * .60) / r;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1, ky);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          r,
          <Color>[
            color.withAlpha(66),
            color.withAlpha(0),
          ], // color-mix(rk 26%, transparent)
          <double>[0, .60],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PlateGlowPainter o) => o.color != color;
}

/// repeating-linear-gradient(0deg, rgba(120,220,255,.045) 0 1px, transparent 1px 3px) + opacity .5
class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter();

  @override
  void paint(Canvas canvas, Size s) {
    final Paint p = Paint()..color = const Color(0x0678DCFF);
    for (double y = 0; y < s.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, s.width, 1), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// .pl-rank —— 右上角的等级骰子：一圈进度 + 大字 + 七格刻度
class _Rank extends StatelessWidget {
  const _Rank({
    super.key,
    required this.quest,
    required this.shownIndex,
    this.lock = false,
    this.lockToken = 0,
  });

  final Quest quest;

  /// 揭晓滚到第几档（静态终态 = `quest.rarity.i`）
  final int shownIndex;

  /// `rankLock` 那一下（末档砸下来）
  final bool lock;

  /// 重播令牌（reRank 每次降档 +1）
  final int lockToken;

  @override
  Widget build(BuildContext context) {
    // 滚动过程中显示的是"当前滚到的那一档"，不是最终那一档
    final int i = shownIndex;
    final Color rk = Rarity.of(kRanks[i]).color;
    // `@keyframes rankLock { 0% { scale(1.9); brightness(2.2) } }`
    final Widget ring = SizedBox(
      key: const Key('plate.ring'),
      width: 78,
      height: 78,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned.fill(
            child: CustomPaint(
              painter: _RankRingPainter(color: rk, index: i),
            ),
          ),
          Text(
            kRanks[i],
            style: fs(
              family: F.num,
              size: 52,
              wght: 900,
              wdth: 80,
              height: 1,
              color: rk,
              shadows: <Shadow>[
                Shadow(color: rk.withAlpha(179), blurRadius: 22),
              ],
            ),
          ),
        ],
      ),
    );
    return Column(
      children: <Widget>[
        if (lock)
          TweenAnimationBuilder<double>(
            // 换 token 重挂 → reRank 的每次降档都重播「1.9 砸回 1」
            // （原型 `L.classList.remove('lock'); void L.offsetWidth; L.classList.add('lock')`）
            key: Key('plate.lock.$lockToken'),
            tween: Tween<double>(begin: 1.9, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutBack,
            builder: (BuildContext _, double s, Widget? child) =>
                Transform.scale(scale: s, child: child),
            child: ring,
          )
        else
          ring,
        const SizedBox(height: 9),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(7, (int k) {
            return Padding(
              padding: EdgeInsets.only(right: k == 6 ? 0 : 3),
              child: Container(
                width: 8,
                height: 4,
                decoration: BoxDecoration(
                  color: k <= i ? rk : const Color(0x1F38E1FF),
                  borderRadius: BorderRadius.circular(1),
                  boxShadow: k <= i
                      ? <BoxShadow>[BoxShadow(color: rk, blurRadius: 6)]
                      : null,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// SVG viewBox 80×80 画进 78×78：r=36、周长 226、从正上方起画
class _RankRingPainter extends CustomPainter {
  const _RankRingPainter({required this.color, required this.index});

  final Color color;
  final int index;

  @override
  void paint(Canvas canvas, Size s) {
    final double k = s.width / 80;
    final Offset c = Offset(s.width / 2, s.height / 2);
    final double r = 36 * k;
    final Rect rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * k
        ..color = C.blue.withAlpha(36), // rgba(56,225,255,.14)
    );
    final double frac = (index + 1) / 7;
    final Paint arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * k
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * frac,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * k
        ..strokeCap = StrokeCap.round
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * frac, false, arc);
  }

  @override
  bool shouldRepaint(covariant _RankRingPainter o) =>
      o.color != color || o.index != index;
}

/// .fp —— 七条同心弧组成的指纹（ui.js `FP_PATHS`），外加一圈脉冲
class _Fingerprint extends StatefulWidget {
  const _Fingerprint({required this.progress});

  /// 按住进度（0~1）—— 七条弧按 i/7*.55 错峰点亮，每条在 .45 内走完
  final double progress;

  @override
  State<_Fingerprint> createState() => _FingerprintState();
}

class _FingerprintState extends State<_Fingerprint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (BuildContext _, Widget? _) {
        final double t = _pulse.value;
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // .fp::after —— 2.2s 从 .8 涨到 1.35 并淡出
            Positioned.fill(
              child: Transform.scale(
                scale: .8 + .55 * t,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: C.blue.withAlpha((.18 * 255 * (1 - t)).round()),
                      width: 1,
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _FingerprintPainter(progress: widget.progress),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FingerprintPainter extends CustomPainter {
  const _FingerprintPainter({required this.progress});

  final double progress;

  static const double _cx = 31;
  static const double _cy = 38;
  static const List<double> _radii = <double>[4, 8.5, 13, 17.5, 22, 26.5, 31];

  @override
  void paint(Canvas canvas, Size s) {
    final double k = s.width / 62;
    canvas.save();
    canvas.scale(k);
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < _radii.length; i++) {
      final double r = _radii[i];
      final double a0 = (196 + i * 7) * math.pi / 180;
      final double a1 = (520 - i * 9) * math.pi / 180;
      final Rect rect = Rect.fromCenter(
        center: const Offset(_cx, _cy),
        width: 2 * r,
        height: 2 * r * 1.12,
      );
      final Path path = Path()..arcTo(rect, a0, a1 - a0, true);
      // 底线
      canvas.drawPath(path, stroke..color = C.blue.withAlpha(66));
      // 点亮部分：原型用 `strokeDashoffset`，这里按比例截取路径
      // 错峰：第 i 条从 `i/7*.55` 开始，`.45` 内走完（ui.js L304）
      final double start = i / _radii.length * .55;
      final double kk = ((progress - start) / .45).clamp(0.0, 1.0);
      if (kk <= 0) continue;
      final List<Path> parts = <Path>[];
      for (final PathMetric m in path.computeMetrics()) {
        parts.add(m.extractPath(0, m.length * kk));
      }
      for (final Path part in parts) {
        canvas.drawPath(
          part,
          stroke
            ..color = C.blue
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        canvas.drawPath(
          part,
          stroke
            ..color = C.blue
            ..maskFilter = null,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FingerprintPainter old) =>
      old.progress != progress;
}

/// 下行滚档时间线 —— 原型 `rankRoll` 的 `down` 分支：
///
/// ```js
/// for (let i = from; i >= target; i--) { set(i); if (i > target) await sleep(140); }
/// ```
///
/// 每档停留按 MOTION-ANALYSIS P1-3 的规格收敛为 **90ms**
/// （三档下行 ≈270ms，即验收口径「换单 270ms 下行滚档」；真实业务一次降一档）。
/// 与 [RankRollTimeline] 同约定：给时刻 t，算该显示第几档。
class _ReRankRoll {
  _ReRankRoll({required this.from, required this.target});

  /// 下行每档停留（ms）
  static const double stepMs = 90;

  /// 起始档（旧档）
  final int from;

  /// 目标档（新档，必须 ≤ from）
  final int target;

  /// 整段滚完要多久（末档落地不再等）
  double get total => from > target ? stepMs * (from - target) : 0;

  /// `t` 时刻应该显示第几档（0 基）
  int indexAt(double t) => math.max(target, from - (t / stepMs).floor());
}

/// #plateAlt —— 板子下面那两个「宿主 · …」按钮（app.css L299-303）
///
/// D4（docs/18 §1.3 死按钮清单）：「换一个 / 等会儿」原先没有回调参数、纯展示，
/// 点了没反应。现接 [onPick]，语义按原型 dispatch 循环钉死：
///  - `labels[0]`「换一个」= **retreat**：这一单降一档重刻（F 级还退＝换一张别的 F）；
///    当日累计退缩 3 次强制佩戴「口头巨人」——业务在 `QuestFlow.retreat`
///    （原型 store.js L235-250 / flows.js L282-298），main.dart 装配归 t10；
///  - `labels[1]`「等会儿」= **later**：单子原样留在她手里、回大厅
///    （原型 `Store.later()` store.js L234 / flows.js L315）。
class PlateAlt extends StatelessWidget {
  const PlateAlt({
    super.key,
    required this.labels,
    this.visible = true,
    this.onPick,
  });

  final List<String> labels;
  final bool visible;

  /// 按下第 i 颗（原型 `Plate.alt(opts, onPick)`：
  /// `b.onclick = () => { Sound.play('tap'); onPick(o.v); }`，ui.js L337-341）。
  /// null = 尚未接线：保留按下变色的 `:active` 反馈，但点了不触发业务（不假装成功）。
  final ValueChanged<int>? onPick;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 18,
      // 收起来时同时断掉命中，别替下面的东西挨点
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 400),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              for (int i = 0; i < labels.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 10),
                // `#plateAlt button:active { color: var(--ice); box-shadow: inset 0 0 0 1px var(--blue) }`
                PressBuilder(
                  // D4：原型每颗按钮都有 onclick（ui.js L339），这里原先没接——
                  // 「换一个 / 等会儿」点下去毫无反应的死按钮就是它
                  onTap: onPick == null
                      ? null
                      : () {
                          // 普通点按（`ui.js:339`）：
                          // `b.onclick = () => { Sound.play('tap'); onPick(o.v) }`
                          Sfx.play('tap');
                          onPick!(i);
                        },
                  builder: (BuildContext _, bool down) => Container(
                    key: Key('plate.alt.$i'),
                    height: 36,
                    // Border 占布局、CSS 的 inset 阴影不占 → padding 各减 1px
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xDB040C1C), // rgba(4,12,28,.86)
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: down
                            ? C.blue
                            : const Color(0x4D8FA6C4), // rgba(143,166,196,.3)
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Text(
                          '宿主 · ',
                          style: fs(
                            family: F.mono,
                            size: 9,
                            wght: 500,
                            ls: .9,
                            height: 1,
                            color: C.dim,
                          ),
                        ),
                        Text(
                          labels[i],
                          style: fs(
                            family: F.cn,
                            size: 13,
                            wght: 400,
                            height: 1,
                            color: down ? C.ice : const Color(0xFFC3D2E6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
