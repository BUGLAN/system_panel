import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/haptics.dart';
import '../state/sfx.dart';
import 'card_skins.dart';
import 'rail_base.dart';

export 'card_skins.dart';

/// ═══════════════════════════════════════════════════════════
///  牌桌 · 抉择场景（docs/27）——「她发牌，你落子」
///
///  本文件只管**机械**：入场 / 领位 / 拖拽吸附 / 落定压印，
///  以及每种皮肤自己的几何。**长什么样**全在 `card_skins.dart`。
///
///  ── 动效口径（Apple《Designing Fluid Interfaces》+ animate-expo）──
///   1. **入场不锁输入**：牌 280ms 内 materialize 完，第一帧就能点。
///      没有「揭示完才可点」——那等于把用户按在原地等一段动画（§1 响应）。
///   2. **入场不加过冲**：它不是手势驱动的，就不该弹（animate-expo §5）。
///      过冲只留给「甩出来的」东西 —— 那在 [RailShell] 的弹簧里。
///   3. **按下即有反馈**：按下 120ms 缩到 .97，抬起才落定（§7）。
///   4. **动效跟着输入走**：焦点扫光只在**换领位**时播一次；名牒的倾角由
///      **拖拽位移**驱动 —— 没有任何「自己在那动」的循环动画。
///   5. **减弱动态**：保留 160ms 交叉淡入（§14：更少更轻，不是全无）。
/// ═══════════════════════════════════════════════════════════

/// 入场：整段 ≤ 280ms（animate-expo §5「移动端 UI 动画都在 300ms 以内」）
const int kEnterMs = 200;
const int kEnterBudgetMs = 280;

/// 强烈 ease-out —— `Easing.bezier(0.23, 1, 0.32, 1)`（animate-expo 的 UI 默认）
const Cubic kEnterCurve = Cubic(.23, 1, .32, 1);

/// 按下反馈：100~150ms（animate-expo §7）。
/// 牌面用的是**即按即缩**（与 `press_scale.dart` 的 `:active` 同款、无补间），
/// 出口铭牌用 [kPressMs] 做 100ms 补间。
const int kPressMs = 100;
const double kPressScale = .97;

/// 焦点扫光：换领位时**播一次**（不是循环）
const int kSweepMs = 520;

/// 落定压印
const int kStampMs = 200;
const double kStampFlash = .16;

/// 点**侧牌**时是否顺手落定。默认 false（只送位）—— docs/27 §7.3-1。
const bool kCardSideTapCommits = false;

/// 牌桌（皮肤由 [skin] 决定，几何由 `geomOf(skin)` 给出）
class CardTable extends StatefulWidget {
  const CardTable({
    super.key,
    required this.cards,
    this.skin = CardSkin.shelf,
    this.size = CardTableSize.l,
    this.onPick,
    this.initialLead,
  });

  final List<TableCard> cards;
  final CardSkin skin;
  final CardTableSize size;

  /// 点**领位**（= 落定）时回调；点了不可用的牌不会触发
  final ValueChanged<int>? onPick;

  final int? initialLead;

  @override
  State<CardTable> createState() => _CardTableState();
}

class _CardTableState extends State<CardTable> with TickerProviderStateMixin {
  final RailController _rail = RailController();

  /// 入场（materialize）：0 → 1
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: kEnterBudgetMs),
  );

  /// 落定压印
  late final AnimationController _stamp = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: kStampMs),
  );

  /// 焦点扫光（换领位时 from 0 重播一次）
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: kSweepMs),
  );

  /// 正在压印的那一张（-1 = 没有）
  int _stampIndex = -1;

  /// 落定锁（只挡落定那一下，200ms 后自动解锁；**不锁整桌手势**）
  bool _locked = false;

  bool _started = false;

  SkinGeom get _g => geomOf(widget.skin);

  int get _n => widget.cards.length;

  @override
  void initState() {
    super.initState();
    _rail.moveTo(widget.initialLead ?? (_n - 1) ~/ 2, length: _n);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _playEnter();
  }

  @override
  void didUpdateWidget(covariant CardTable old) {
    super.didUpdateWidget(old);
    _rail.clampTo(_n);
    if (_ids(old.cards) != _ids(widget.cards)) _playEnter();
  }

  @override
  void dispose() {
    _enter.dispose();
    _stamp.dispose();
    _sweep.dispose();
    _rail.dispose();
    super.dispose();
  }

  static String _ids(List<TableCard> l) =>
      l.map((TableCard c) => c.id).join('\u0000');

  /// 逐张错峰（牌多时收紧，保证整段不超过 [kEnterBudgetMs]）
  double get _stagger =>
      _n <= 1 ? 0 : math.min(26.0, (kEnterBudgetMs - kEnterMs) / (_n - 1));

  /// 整段入场多长（含错峰）
  double get _spanMs => kEnterMs + _stagger * (_n - 1);

  void _playEnter() {
    final bool reduce = railReduceMotion(context);
    // 减弱动态：**只做 160ms 交叉淡入** —— 不位移、不缩放、不扫光。
    // （apple-design §14：更少更轻，不是全无；纯透明度变化保留下来解释状态）
    _enter.duration = Duration(milliseconds: reduce ? 160 : _spanMs.round());
    _enter.forward(from: 0);
    if (!reduce) _sweep.forward(from: 0);
  }

  double _enterP(int i, double ms) {
    final double start = _stagger * i;
    if (ms <= start) return 0;
    return kEnterCurve.transform(((ms - start) / kEnterMs).clamp(0.0, 1.0));
  }

  /// 换领位：响一声 + 轻震（= 选择器的「档位咬合」），并给新领位扫一次光
  void _onLeadChanged() {
    Sfx.play('rung');
    Haptics.buzz('choose');
    _lastDetent = null;
    if (!railReduceMotion(context)) _sweep.forward(from: 0);
  }

  /// 上一次咬合到第几格（null = 还没咬过）
  double? _lastDetent;

  /// **拖动中**每越过一格：响一声 + 轻震（同一帧）。
  ///
  /// 这是选择器的手感来源（animate-expo §8：档位咬合 = selection 反馈），
  /// 也是宿主点名要的「左滑右滑的手势效果 + 音效」。
  /// 音高跟着格子走（`rung` 有 5 档变调），越往右越高。
  void _onDragProgress(double pos) {
    final double detent = pos.roundToDouble();
    final double? last = _lastDetent;
    _lastDetent = detent;
    if (last == null || detent == last) return;
    if (railReduceMotion(context)) return;
    final int i = detent.round().clamp(0, _n - 1);
    Sfx.play('rung', variant: i % 5);
    Haptics.buzz('choose');
  }

  /// 点一张牌：侧牌只送位；领位落定
  void _tapCard(int i) {
    if (_locked) return;
    if (i != _rail.lead) {
      if (_rail.moveTo(i, length: _n)) _onLeadChanged();
      if (!kCardSideTapCommits) return;
    }
    _commit(i);
  }

  void _commit(int i) {
    final TableCard c = widget.cards[i];
    if (!c.enabled) {
      // 不可用：点了她解释一句，**不落定**
      Sfx.play('tap');
      Haptics.buzz('choose');
      return;
    }
    _locked = true;
    // 因果同帧（apple-design §13）：压印、亮闪、声音、震动都在这一下
    Sfx.play('seal');
    Haptics.buzz('seal');
    widget.onPick?.call(i);
    if (railReduceMotion(context)) {
      _locked = false;
      return;
    }
    _stampIndex = i;
    _stamp.forward(from: 0).whenComplete(() {
      _locked = false;
      if (mounted) setState(() => _stampIndex = -1);
    });
  }

  /// 分段线性插值：0 → v0，1 → v1，2 → v2，>2 按最后一档继续外推
  static double _extrap(double a, double v0, double v1, double v2) {
    if (a <= 0) return v0;
    if (a <= 1) return v0 + (v1 - v0) * a;
    if (a <= 2) return v1 + (v2 - v1) * (a - 1);
    return v2 + (v2 - v1) * (a - 2);
  }

  double _sideDx(double ad) => _extrap(ad, 0, _g.dx1, _g.dx2);

  double _sideScale(double ad) => _extrap(ad, 1, _g.scale1, _g.scale2);

  double _sideDy(double ad) => _extrap(ad, _g.dy0, _g.dy1, _g.dy2);

  double _sideOp(double ad) => _extrap(ad, 1, _g.op1, _g.op2);

  double _tableH(double h) => h + _g.topPad + _g.dy2 + 30;

  @override
  Widget build(BuildContext context) {
    final bool reduce = railReduceMotion(context);
    final Dims dims = dimsOf(widget.skin, widget.size);
    if (_n == 0) return const SizedBox.shrink();

    return SizedBox(
      height: _tableH(dims.h),
      child: LayoutBuilder(
        builder: (BuildContext ctx, BoxConstraints c) => RailShell(
          controller: _rail,
          length: _n,
          stride: _g.stride,
          // 两端继续拖 = 渐进阻力，不是硬停（apple-design §9）
          rubberExtent: c.maxWidth,
          onLeadChanged: _onLeadChanged,
          // 拖动中每过一格：一声 + 轻震（档位咬合）
          onDragProgress: _onDragProgress,
          builder: (BuildContext _, double dx) => AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[_enter, _stamp, _sweep]),
            builder: (BuildContext _, Widget? _) =>
                _stack(c.maxWidth / 2, dims, dx, reduce),
          ),
        ),
      ),
    );
  }

  Widget _stack(double cx, Dims dims, double drag, bool reduce) {
    // ── 连续位置 p ──────────────────────────────────────────────
    //
    // p = 「现在镜头对在第几格」，**可以是小数**。所有几何（缩放 / 升降 /
    // 外倾 / 明暗 / 横移）都是 p 的**连续函数** —— 所以拖到一半时，下一张
    // 已经在**平滑地长成领位**，而不是等松手才瞬间跳过去。
    //
    // （以前这里用的是「整数领位 + 刚性平移」，松手那一瞬整叠会跳一格，
    //   看上去就是「切换没有动画、很卡手」。）
    final double p = _rail.lead - drag / _g.stride;
    // 离最近一格的偏移（−.5 ~ .5）：整桌侧倾 / 高光 / 名牒摆动都由它驱动。
    // 用它而不是 drag：松手时 drag 会被补偿跳一下（见 RailShell），frac 不会。
    final double frac = (p - _rail.lead).clamp(-1.0, 1.0);
    final double ms = _enter.value * _spanMs;
    final double tilt = reduce ? 0 : -frac * .035;

    // 领位最后画（压在最上面），离得越远越先画
    final List<int> order = List<int>.generate(_n, (int i) => i)
      ..sort((int a, int b) {
        final double da = (a - p).abs();
        final double db = (b - p).abs();
        if (da != db) return db.compareTo(da);
        return a.compareTo(b);
      });

    final Widget body = Transform.rotate(
      angle: tilt,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          for (final int i in order) _card(i, p, frac, cx, dims, ms, reduce),
        ],
      ),
    );
    return body;
  }

  Widget _card(
    int i,
    double p,
    double frac,
    double cx,
    Dims dims,
    double ms,
    bool reduce,
  ) {
    final TableCard c = widget.cards[i];
    // a = 这一张离「镜头」几个格（连续、有符号）
    final double a = i - p;
    final double ad = a.abs();
    final double sign = a == 0 ? 0 : (a > 0 ? 1 : -1);
    final bool isLead = ad < .5;

    final double scale = _sideScale(ad);
    final double dx0 = _sideDx(ad) * sign;
    final double dy0 = _sideDy(ad);
    final double rot = reduce
        ? 0
        : a.clamp(-2.0, 2.0) * _g.rot1 * math.pi / 180;
    final double op = _sideOp(ad);

    // ── 入场：materialize（透明 + 微缩 + 从上方落下），无过冲 ──
    // 减弱动态时只剩「透明度」那一条
    final double ep = reduce ? _enter.value : _enterP(i, ms);
    final double px = cx - dims.w / 2 + dx0;
    final double py = _g.topPad + dy0 + (reduce ? 0 : (1 - ep) * -10);
    final double pScale = scale * (reduce ? 1 : (0.94 + 0.06 * ep));
    // 减弱动态：按下不缩放，改成压暗一点点（保留「这一下被接收了」的反馈）
    final double pOp = (op * ep).clamp(0.0, 1.0);

    // ── 按下反馈：按下即缩（与 press_scale.dart 的 `:active` 同款、无补间）──
    // ⚠️ 这一条**不再由本 State 驱动**（见 _PressFeedback）：
    //    按下/抬起各来一次 setState，每次都把整桌 8 张牌重建一遍，
    //    而 8 张牌里只有 1 张的视觉真的变了 —— 白重建的 7 张就是「点一下卡一下」。

    // ── 落定压印 ──
    final bool stamping = i == _stampIndex && _stamp.value > 0;
    final double st = stamping ? _stamp.value : 0;
    final double flash = st <= 0
        ? 0
        : (st < .7 ? (1 - st / .7) * kStampFlash : 0);

    // ── 焦点扫光：只有领位、只有换位那一下 ──
    final double sweep = (reduce || !isLead) ? 0 : _sweep.value;

    // ── 名牒的倾角由**手势进度**驱动（方向提示，§8）──
    final double lean = reduce ? 0 : -frac;

    return Positioned(
      left: px,
      top: py,
      width: dims.w,
      height: dims.h,
      child: _PressFeedback(
        onTap: () => _tapCard(i),
        // RepaintBoundary 不裁切（它是**重绘隔离**，不是裁剪层）——
        // 牌面那圈 boxShadow 照旧溢出到牌外，观感不变；见 _PressFeedback 的说明
        child: Transform.rotate(
          angle: rot,
          child: Transform.scale(
            scale: pScale * (stamping ? 1.02 : 1),
            child: Opacity(
              opacity: pOp,
              child: CardFace(
                skin: widget.skin,
                card: c,
                size: widget.size,
                lead: isLead,
                flash: flash,
                stamp: st,
                sweep: sweep,
                lean: lean,
                // 液态玻璃的对角高光跟着手势走
                dragPhase: reduce ? 0 : (-frac * 2).clamp(-1.0, 1.0),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 减弱动态下的按下反馈：不缩放，压暗一点点（保留「这一下被接收了」）
const double kPressDim = .86;

/// 单张牌的「按下反馈 + 重绘隔离」。
///
/// ── 为什么要有这一层（点选卡顿的两处结构性根因）──────────────
///  1. **按下状态只该重建这一张牌**。旧版把 `_pressed` 放在 _CardTableState 里，
///     onTapDown/onTapUp 各 setState 一次 → 每次点选都把**整桌 8 张牌**
///     连同它们的 CardFace 与自定义 painter 全部重建一遍，
///     而其中 7 张的视觉一个字都没变 —— 那 7 张就是白花的钱。
///     现在按下态是这一张牌的私有 state，`setState` 的作用域只到它自己。
///  2. **重绘隔离**。牌面是 ClipPath + GlassPainter + 两层大半径 boxShadow，
///     旧版没有任何 RepaintBoundary，于是整屏任何一次重绘
///     （环场、粒子、Live2D 平台视图都在动）都会把这 8 张牌重新光栅化一遍。
///     加边界后这一层被缓存，只有它自己的内容变了才重绘。
///
/// ⚠️ 缩放仍走 `Transform`（不改布局、不重排），与旧版一致；
///    RepaintBoundary **不裁切**（它只建独立图层），牌面那圈阴影照旧溢出。
class _PressFeedback extends StatefulWidget {
  const _PressFeedback({required this.onTap, required this.child});

  final VoidCallback onTap;

  final Widget child;

  @override
  State<_PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<_PressFeedback> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final bool reduce = railReduceMotion(context);
    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (TapDownDetails _) => setState(() => _down = true),
        onTapUp: (TapUpDetails _) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: Transform.scale(
          scale: reduce ? 1 : (_down ? kPressScale : 1),
          child: Opacity(
            opacity: (reduce && _down) ? kPressDim : 1,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
