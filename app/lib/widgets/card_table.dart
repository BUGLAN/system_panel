import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../design/fidelity.dart';

import '../design/tokens.dart';
import '../state/haptics.dart';
import '../state/sfx.dart';
import 'card_skins.dart';
import 'rail_base.dart';

export 'card_skins.dart';

/// ═══════════════════════════════════════════════════════════
///  牌桌 · 抉择场景（docs/32）——「她发牌，你落子」
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

/// 点**侧牌**时是否顺手落定。默认 false（只送位）—— docs/32 §7.3-1。
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
    this.tapLeadAlways = false,
    this.lead,
    this.onLeadReport,
    this.run = -1,
    this.strideScale = 1.0,
  });

  final List<TableCard> cards;
  final CardSkin skin;
  final CardTableSize size;

  /// 点**领位**（= 落定）时回调；点了不可用的牌不会触发
  final ValueChanged<int>? onPick;

  final int? initialLead;

  /// 领位**无论 enabled 与否**都回调 [onPick]（docs/39 M-10）。
  ///
  /// 默认 false = 老行为（`enabled: false` 的牌点了只响一声、不打开）——
  /// 补给 / 称号 / 证据 / 换目标四个场景都走默认值，**行为一行不变**。
  ///
  /// 主线页置 true：「点领位 = 打开牌屉」要全五态成立，
  /// 接任务只发生在牌屉里的按钮上，所以 `enabled` 在这里只表达
  /// 「这单现在能不能接」，不再兼任「能不能看」。
  final bool tapLeadAlways;

  /// **受控领位**（docs/39 M-13/M-14）：非 null 时由外部指定当前领位，
  /// 变化就跟着 `moveTo`（刻度轨拖动 → 牌扇领位跟着动，但**不开牌屉**）。
  ///
  /// null = 不接管（默认）：领位仍由牌桌自己的拖拽/点选决定，
  /// 其余四个场景（补给/称号/证据/换目标）一行行为都不变。
  final int? lead;

  /// 领位变化上报（无论来自手势还是受控注入）—— 刻度轨据此画「脚下」。
  final ValueChanged<int>? onLeadReport;

  /// 执行中状态线的光包相位（docs/39 M-09）；`< 0` = 不画。
  ///
  /// 默认 -1：其余四个场景（补给/称号/证据/换目标）不跑这个动画。
  final double run;

  /// 步距缩放（2026-10-23）：主线牌扇要挂**全部 N 张**，
  /// 张数一多就得压窄相邻间距，否则 180 张会叠成一条线、拖不动也看不清。
  ///
  /// 默认 1.0 = 原样 —— 补给/称号/证据/换目标四个场景一行行为都不变。
  final double strideScale;

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
    // docs/39 M-13：受控领位 —— 外部（刻度轨拖动/点击）改了 `lead` 就跟着走。
    // 这里**不响 rung**：拖动/点击那一下已经由刻度轨自己 `_detent` 过了。
    final int? want = widget.lead;
    if (want != null && want != _rail.lead) {
      if (_rail.moveTo(want, length: _n)) {
        widget.onLeadReport?.call(_rail.lead);
        if (!railReduceMotion(context)) _sweep.forward(from: 0);
      }
    }
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
    // docs/41 §3.1「发牌」：一次发牌**只出 2 声**（首张 + 末张）。
    // 为什么不是逐张：相隔 <20ms 的两声会被听成一个；n=8 时 stagger 只有 11.4ms。
    //
    // ⚠️ 末张那一声走 [_enter] 的进度判断，**不用 `Future.delayed`**：
    //    后者会给 widget 测试留 pending timer（仓库踩过）。
    if (reduce) return;
    Sfx.play('deal', variant: 0);
    Haptics.buzz('deal');
    if (_n > 1 && _spanMs > 120) _lastDealSounded = false;
  }

  /// 末张发牌那一声是否已经响过（每个入场周期只响一次）
  bool _lastDealSounded = true;

  /// 入场进度推进时检查：走到 88% 就把末张那一声补上
  void _tickDealSound() {
    if (_lastDealSounded || !_enter.isAnimating) return;
    if (_enter.value < .88) return;
    _lastDealSounded = true;
    Sfx.play('deal', variant: 4);
  }
  double _enterP(int i, double ms) {
    final double start = _stagger * i;
    if (ms <= start) return 0;
    return kEnterCurve.transform(((ms - start) / kEnterMs).clamp(0.0, 1.0));
  }

  /// 换领位：响一声 + 轻震（= 选择器的「档位咬合」），并给新领位扫一次光
  void _onLeadChanged() {
    // docs/41 §1「牌桌的档位咬合有两处结构性浪费」Bug ②：
    // 原来这里 `Sfx.play('rung')` **不带 variant** → `_pick` 随机取 5 档之一，
    // 于是每次落定的音高是不受控的（可能低音，破坏「往右走高」的阶梯感）。
    // 改成与 [_onDragProgress] 同一口径：音高跟着领位下标走。
    Sfx.play('detent', variant: _rail.lead % 5);
    Haptics.buzz('choose');
    _lastDetent = null;
    if (!railReduceMotion(context)) _sweep.forward(from: 0);
    widget.onLeadReport?.call(_rail.lead);
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
    // docs/41 §3.3：咬合换专用 detent（28ms，与 8ms 震动同量级）。
    // rung 是 70ms 方波 —— 手指 8ms 就结束了、耳朵还在响，是「音画不同步」的来源。
    Sfx.play('detent', variant: i % 5);
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
    // docs/39 M-10：`tapLeadAlways` 的桌子（主线）把「点开看」与「接单」
    // 彻底分开 —— 五态都能打开详情，所以这里不看 `enabled`、也不压印；
    // 接单只发生在详情里的按钮上（那里的音效才是 seal）。
    if (widget.tapLeadAlways) {
      // 看详情 = tap + choose（§5.4：原来这里错用 seal，那是接单的音）
      Sfx.play('tap');
      Haptics.buzz('choose');
      widget.onPick?.call(i);
      return;
    }
    if (!c.enabled) {
      // 不可用：点了她解释一句，**不落定**
      //
      // 2026-10-23：原来这里与「点开详情」共用 tap + choose —— 两声一模一样，
      // 用户分不清「我点到了但买不起」和「我点开了」。改成最低档 detent
      // （机械卡住的那一下，28ms）配 edge（拖到边界的震动），
      // 与「点开」的 tap 在音色上彻底分开。
      Sfx.play('detent', variant: 0);
      Haptics.buzz('edge');
      return;
    }
    _locked = true;
    // 因果同帧（apple-design §13）：压印、亮闪、声音、震动都在这一下
    //
    // docs/41 §3.4：落定**不再用 `seal`** —— 那是全场第二重的音（1.26s），
    // 却是「我把这一张选定了」这种高频动作；来回选 10 次就是 10 次钤印声叠加。
    // 改用 `stamp`（0.29s / −16.3dBFS），`seal` 保留给接任务/提交。
    Sfx.play('stamp');
    Haptics.buzz('stamp');
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

  /// 实际步距 = 皮肤步距 × [CardTable.strideScale]（张数多时压窄）。
  double get _stride => _g.stride * widget.strideScale;

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
          stride: _stride,
          // 两端继续拖 = 渐进阻力，不是硬停（apple-design §9）
          rubberExtent: c.maxWidth,
          onLeadChanged: _onLeadChanged,
          // 拖动中每过一格：一声 + 轻震（档位咬合）
          onDragProgress: _onDragProgress,
          builder: (BuildContext _, double dx) => AnimatedBuilder(
            // ⚠️ 入场走到 88% 时补末张那声发牌（[_tickDealSound]），
            //    走 AnimatedBuilder 的每帧回调，不另起 timer。
            animation: Listenable.merge(<Listenable>[
              _enter,
              _stamp,
              _sweep,
              _DealTicker(_enter, _tickDealSound),
            ]),
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
    final double p = _rail.lead - drag / _stride;
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

    // docs/48 §3：领位脚下的「悬浮光池」—— 稀有度色的一团椭圆辉光 +
    // 一条台面反光线。它告诉你「这张牌被举起来了」，并把牌和她脚下的
    // 地台光连成同一套光源语言。单个渐变，不做 blur。
    final int leadI = _rail.lead.clamp(0, _n - 1);
    final Color pool = widget.cards[leadI].accent ?? C.blue;
    final double poolOp = (_enter.value).clamp(0.0, 1.0) * (1 - frac.abs() * .6);
    final Widget body = Transform.rotate(
      angle: tilt,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            left: cx - dims.w * .85,
            width: dims.w * 1.7,
            top: _g.topPad + _g.dy0 + dims.h - 22,
            height: 56,
            child: IgnorePointer(
              child: CustomPaint(
                key: const Key('table.pool'),
                painter: _PoolPainter(color: pool, opacity: poolOp),
              ),
            ),
          ),
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

    // ── 入场：**发牌**（docs/41 §3.1）──────────────────────────────
    // 原来只有「透明 + 微缩 + 从上方落下」三条同时线性插值 —— 那是「淡入」，
    // 不是「发牌」。真实的发牌有**方向**：牌从右下方被甩出来，落定时才转正。
    //
    // 补的两条（都随 ep 收口，末帧严格等于原样）：
    //   ① **微旋转 + 位移方向**：从 +3.5° 转到 0、从右下方小幅摆入
    //   ② 落定前**先到位、后转正**（旋转用 ep 的平方根 → 先转、后落）
    // ⚠️ 不加过冲：入场不是手势驱动的（`card_table.dart:20-21` 已写对）。
    final double ep = reduce ? _enter.value : _enterP(i, ms);
    final double px = cx - dims.w / 2 + dx0;
    // 位移：向上 10（原位）＋ 入场时从右下方 6px 摆入
    // ⚠️ 必须**对称**：`sign == 0`（领位）时若给 +6，领位牌首帧就偏右 6px，
    //  「领位居中」这条测试与视觉都会被破坏。所以领位不给横向偏移，
    //  只做纵向 + 旋转；侧位才顺着自己的方向甩出。
    final double enterDx = (reduce || sign == 0) ? 0 : (1 - ep) * 6 * sign;
    final double py = _g.topPad + dy0 + (reduce ? 0 : (1 - ep) * -10);
    final double pScale = scale * (reduce ? 1 : (0.94 + 0.06 * ep));
    // 旋转：入场时额外 +3.5° 甩出，收口比位移更早（√ep → 先转正再落定）
    final double enterRot = reduce
        ? 0
        : (1 - math.sqrt(ep.clamp(0.0, 1.0))) * 3.5 * math.pi / 180;
    // 减弱动态：按下不缩放，改成压暗一点点（保留「这一下被接收了」的反馈）
    final double pOp = (op * ep).clamp(0.0, 1.0);

    // ── 按下反馈：按下即缩（与 press_scale.dart 的 `:active` 同款、无补间）──
    // ⚠️ 这一条**不再由本 State 驱动**（见 _PressFeedback）：
    //    按下/抬起各来一次 setState，每次都把整桌 8 张牌重建一遍，
    //    而 8 张牌里只有 1 张的视觉真的变了 —— 白重建的 7 张就是「点一下卡一下」。

    // ── 落定压印（docs/41 §3.4）──────────────────────────────────
    // 两段：前 30% **压下去**（1 → 1.02），后 70% **弹回来**（1.02 → 1）。
    //
    // ⚠️ 原来这里是 `pScale * (stamping ? 1.02 : 1)` —— 1.02 是**瞬间乘上去**
    //    然后瞬间消失，中间没有过程。读起来是「闪了一下」，不是「压印」。
    //    为什么只到 1.02 而不是 1.08：1.02 是**压进去**（press-in），
    //    过冲属于「被甩出来的东西」（入场/弹簧），不属于落定。
    final bool stamping = i == _stampIndex && _stamp.value > 0;
    final double st = stamping ? _stamp.value : 0;
    final double stampScale = st <= 0
        ? 1.0
        : (st < .3
              ? 1 + .02 * (st / .3) // 压入
              : 1.02 - .02 * ((st - .3) / .7)); // 回落
    final double flash = st <= 0
        ? 0
        : (st < .7 ? (1 - st / .7) * kStampFlash : 0);

    // ── 焦点扫光：只有领位、只有换位那一下 ──
    final double sweep = (reduce || !isLead) ? 0 : _sweep.value;

    // ── 名牒的倾角由**手势进度**驱动（方向提示，§8）──
    final double lean = reduce ? 0 : -frac;

    return Positioned(
      // 入场位移：叠加到 left（只在入场期间非 0，末帧严格为 0）
      left: px + enterDx,
      top: py,
      width: dims.w,
      height: dims.h,
      child: _PressFeedback(
        // 每张牌一个稳定 key（`table.card.<id>`）：牌桌是所有"选一个"场景的
        // 公共落点（补给 / 称号 / 道具 / 取景），没有它就只能靠坐标猜是哪张。
        key: Key('table.card.${c.id}'),
        onTap: () => _tapCard(i),
        // RepaintBoundary 不裁切（它是**重绘隔离**，不是裁剪层）——
        // 牌面那圈 boxShadow 照旧溢出到牌外，观感不变；见 _PressFeedback 的说明
        tiltEnabled: !reduce,
        glareColor: c.accent ?? C.blue,
        child: Transform(
          alignment: Alignment.center,
          // docs/48 §3：**真 3D 牌扇**。原来侧牌只有平面旋转（rotateZ），读起来
          // 是「贴纸转了个角」；现在侧牌再绕 Y 轴朝内转（像握在手里的一把牌，
          // 牌面朝向持牌人），领位在拖拽时顺着手势轻微偏航 —— 有了透视，
          // 远近关系不再只靠缩放压暗表达。
          // 入场时额外 +3.5° 甩出（√ep 收口：先转正、后落定）
          transform: Matrix4.identity()
            ..setEntry(3, 2, reduce ? 0 : 0.0011)
            ..rotateZ(rot + enterRot)
            ..rotateY(reduce ? 0 : (-a.clamp(-2.0, 2.0) * .16 + lean * .10)),
          child: Transform.scale(
            // 落定压印：两段（压入 → 回落），见上方 stampScale 的说明
            scale: pScale * stampScale,
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
                // docs/39 M-07：离领位 ≥1.5 格 = 「±2 位」，只留档位 + 状态线
                far: ad >= 1.5,
                // docs/39 M-06：换领位时外辉 200ms 淡入。`sweep` 就是那 520ms 的
                // 一次性进度，它的前 200/520 ≈ .38 正好当外辉的淡入段用 ——
                // 不额外开一个 controller（牌桌已经有三个）。
                leadT: isLead ? (reduce ? 1.0 : (sweep / .38).clamp(0.0, 1.0)) : 1,
                // docs/39 M-09：只有 duty 的执行中会画光包（其余皮肤不看这个字段）
                run: widget.run,
                foilLevel: Fidelity.rich(context) ? 1 : 0,
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
  const _PressFeedback({
    super.key,
    required this.onTap,
    required this.child,
    this.tiltEnabled = true,
    this.glareColor = C.blue,
  });

  final VoidCallback onTap;

  final Widget child;

  /// 手指跟随倾斜（docs/48 §3）。减弱动态效果时关。
  final bool tiltEnabled;

  /// 镜面眩光的色温（稀有度色与白混合）
  final Color glareColor;

  @override
  State<_PressFeedback> createState() => _PressFeedbackState();
}

/// 跟手倾斜的最大角度（弧度，≈7°）
const double kTiltMax = .12;

class _PressFeedbackState extends State<_PressFeedback>
    with SingleTickerProviderStateMixin {
  bool _down = false;

  /// 手指在牌上的归一化位置（-1~1）；倾斜 / 眩光都读它
  Offset _target = Offset.zero;
  Offset _tilt = Offset.zero;

  /// 抬手后的回正：弹簧（SpringSpec.tilt），每帧只重绘这一张牌
  late final AnimationController _settle = AnimationController.unbounded(
    vsync: this,
  )..addListener(_onSettle);
  Offset _settleFrom = Offset.zero;

  void _onSettle() {
    final double k = (1 - _settle.value).clamp(-0.2, 1.0);
    setState(() => _tilt = _settleFrom * k);
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _aim(Offset local) {
    if (!widget.tiltEnabled) return;
    final Size? sz = context.size;
    if (sz == null || sz.isEmpty) return;
    _target = Offset(
      ((local.dx / sz.width) * 2 - 1).clamp(-1.0, 1.0),
      ((local.dy / sz.height) * 2 - 1).clamp(-1.0, 1.0),
    );
    _settle.stop();
    setState(() => _tilt = _target);
  }

  void _release() {
    if (_tilt == Offset.zero) {
      if (_down) setState(() => _down = false);
      return;
    }
    _down = false;
    _settleFrom = _tilt;
    _settle.value = 0;
    _settle.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(
          mass: 1,
          stiffness: SpringSpec.tilt.k,
          ratio: SpringSpec.tilt.zeta,
        ),
        0,
        1,
        0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool reduce = railReduceMotion(context);
    final double mag = _tilt.distance.clamp(0.0, 1.4);
    Widget face = Opacity(
      opacity: (reduce && _down) ? kPressDim : 1,
      child: widget.child,
    );
    // 镜面眩光：只在按住/回正期间画（平时零成本）
    if (!reduce && mag > .02) {
      face = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          face,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _GlarePainter(
                  at: _tilt,
                  strength: (mag / 1.0).clamp(0.0, 1.0),
                  tint: widget.glareColor,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return RepaintBoundary(
      child: Listener(
        // Listener 不进手势竞技场：拖牌（滑轨）与跟手倾斜可以同时发生
        onPointerDown: (PointerDownEvent e) => _aim(e.localPosition),
        onPointerMove: (PointerMoveEvent e) {
          if (_down) {
            _aim(e.localPosition);
          } else if (_tilt != Offset.zero && !_settle.isAnimating) {
            // 手指在拖滑轨（不是按住这张牌）→ 倾斜立刻回正，不让牌歪着被拖走
            _release();
          }
        },
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (TapDownDetails _) => setState(() => _down = true),
          onTapUp: (TapUpDetails _) => _release(),
          onTapCancel: _release,
          onTap: widget.onTap,
          // 2026-10-23：按下与抬起分开计时 —— 按下 0ms（瞬时，手指要有回应）、
          // 抬起 120ms 回弹（Motion.touchMs / Motion.releaseMs）。
          child: AnimatedScale(
            scale: reduce ? 1 : (_down ? kPressScale : 1),
            duration: _down
                ? const Duration(milliseconds: Motion.touchMs)
                : const Duration(milliseconds: Motion.releaseMs),
            curve: _down ? Curves.linear : Ease.pop,
            child: (reduce || _tilt == Offset.zero)
                ? face
                : Transform(
                    alignment: Alignment.center,
                    // 按下的那一角往下压（像用指尖按住一张有厚度的卡）
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0014)
                      ..rotateX(_tilt.dy * kTiltMax)
                      ..rotateY(-_tilt.dx * kTiltMax),
                    child: face,
                  ),
          ),
        ),
      ),
    );
  }
}

/// 牌面镜面眩光：一团跟着指尖走的柔光（screen 混合，不发灰）
class _GlarePainter extends CustomPainter {
  const _GlarePainter({
    required this.at,
    required this.strength,
    required this.tint,
  });

  final Offset at;
  final double strength;
  final Color tint;

  @override
  void paint(Canvas canvas, Size s) {
    final RRect rr = RRect.fromRectAndRadius(
      Offset.zero & s,
      const Radius.circular(12),
    );
    canvas.save();
    canvas.clipRRect(rr);
    final Offset c = Offset(
      s.width * (.5 + at.dx * .5),
      s.height * (.5 + at.dy * .5),
    );
    final double r = s.width * .9;
    final Color warm = Color.lerp(Colors.white, tint, .35)!;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = RadialGradient(
          colors: <Color>[
            warm.withAlpha((70 * strength).round()),
            warm.withAlpha((18 * strength).round()),
            warm.withAlpha(0),
          ],
          stops: const <double>[0, .35, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlarePainter old) =>
      old.at != at || old.strength != strength || old.tint != tint;
}

/// 领位脚下的悬浮光池
class _PoolPainter extends CustomPainter {
  const _PoolPainter({required this.color, required this.opacity});

  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size s) {
    if (opacity <= .01) return;
    final Offset c = Offset(s.width / 2, s.height * .42);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(1, .28);
    final double r = s.width / 2;
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            color.withAlpha((90 * opacity).round()),
            color.withAlpha((26 * opacity).round()),
            color.withAlpha(0),
          ],
          stops: const <double>[0, .45, 1],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)),
    );
    canvas.restore();
    // 台面反光线
    final Rect line = Rect.fromCenter(center: c, width: s.width * .62, height: 1.2);
    canvas.drawRect(
      line,
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            color.withAlpha(0),
            Color.lerp(color, Colors.white, .5)!.withAlpha((150 * opacity).round()),
            color.withAlpha(0),
          ],
        ).createShader(line),
    );
  }

  @override
  bool shouldRepaint(_PoolPainter old) =>
      old.color != color || old.opacity != opacity;
}

class _DealTicker extends ChangeNotifier {
  _DealTicker(this._target, this._onTick) {
    _target.addListener(_forward);
  }

  final Animation<double> _target;
  final VoidCallback _onTick;

  void _forward() {
    _onTick();
    notifyListeners();
  }

  @override
  void dispose() {
    _target.removeListener(_forward);
    super.dispose();
  }
}
