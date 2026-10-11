import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../stage/spring.dart';

/// ═══════════════════════════════════════════════════════════
///  rail_base —— 「轨」的薄底座（docs/28 §7.1）
///
///  甲 · 物件台（`item_rail.dart`）与 乙 · 铭牌轨（`choice_rail.dart`）
///  **共用这一层逻辑**，但**不共用外观**：这里只管「领位是谁 / 手势怎么吸附 /
///  错峰怎么排 / 减弱动态效果怎么落终态 / 命中怎么断」，
///  一张卡长什么样、怎么位移、怎么旋转，全在各自的 rail 文件里。
///
///  这样 docs/28 §6 要求的「两套设计不相同」落在**视觉与动效层**，
///  而吸附/命中/无障碍这类容易写错的机械活不会写两遍。
///
///  ⚠️ 两条纪律（docs/28 §3.4）：
///  1. 只动 `Transform` / `Opacity` —— 不触发布局重排，
///     禁止用 `AnimatedContainer` 改尺寸做过渡。
///  2. 展开/收起时用 `IgnorePointer(ignoring: !open)` 断命中 ——
///     本仓库真踩过「一颗看不见的按钮替派单板的指纹挨点」。
/// ═══════════════════════════════════════════════════════════

/// 甩动判定阈值（像素/秒）：**仅作参考** —— 松手落点现在由动量投影决定
/// （见 [railProject]），不再靠「超阈值就翻一格」。
const double kRailFlingVelocity = 420;

/// 松手回弹的时长（吸附那一拍）。
///
/// ⚠️ 已不是 [RailShell] 用的路径：吸附现在走**真源弹簧 + 手指速度交接**
/// （Apple《Designing Fluid Interfaces》§5）。保留这个常量只给
/// 「确实要一段定时补间」的地方用。
const Duration kRailSnapMs = Duration(milliseconds: 380);

/// 动量投影的衰减率（Apple §6 的示例代码）：
/// `project(v) = (v/1000) · d/(1−d)`。
///
/// d 越接近 1 抛得越远：**0.998** = 正常滚动手感（一次轻甩能抛半屏），
/// **0.99** = 更「脆」。牌桌取 **0.995** —— 一次轻甩约抛两格、
/// 重甩过三四格，卡片不该像长列表那样抛出去。
const double kRailDecelerationRate = .995;

/// 橡皮筋常数（Apple §9：越界不是硬停，是渐进阻力）
const double kRubberConstant = .55;

/// 动量投影：松手后**它要去哪**，而不是**它现在在哪**。
///
/// 这一条是「轻甩一下 = 小输入大输出」的全部来源（Apple §6）。
double railProject(double velocity, {double rate = kRailDecelerationRate}) =>
    (velocity / 1000) * rate / (1 - rate);

/// 橡皮筋：越过边界 [overshoot] 像素、参照长度 [dimension] 时实际跟手多少。
///
/// 越界越深、跟得越少 —— 读起来是「有回应，但到头了」，不是「卡死了」。
double rubberBand(
  double overshoot,
  double dimension, {
  double constant = kRubberConstant,
}) =>
    (overshoot * dimension * constant) /
    (dimension + constant * overshoot.abs());

/// 错峰入场的时间表（docs/28 §3.4-3）：0 / 60 / 120ms
Duration railStagger(int i) => Duration(milliseconds: 60 * i.clamp(0, 5));

/// 系统「减弱动态效果」是否打开。
///
/// 为真时**直接落终态、不挂任何动画**（docs/28 §3.4-4）。
/// 在 `build` 里读即可：`MediaQuery` 变化会重建。
bool railReduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// 一条「轨」的领位状态机。
///
/// 领位（lead）= 当前被推到你面前的那一个：甲套里它被放大抬起，乙套里它左对齐亮边。
/// **任一时刻恰好一个领位**（docs/28 §3.1）。
class RailController extends ChangeNotifier {
  // 对外叫 lead、对内是私有字段，所以用不了 initializing formal
  // ignore: prefer_initializing_formals
  RailController({int lead = 0}) : _lead = lead;

  int _lead;

  /// 当前领位下标（永远落在 `[0, length)` 内）
  int get lead => _lead;

  /// 换领位。返回**是否真的动了** —— 调用方据此决定要不要响一声
  /// （docs/28 §3.3：换领位才响 `rung`/`tap`，点原地不响）。
  ///
  /// [length] 传 0 或 1 时永远不动（单卡居中，左右留白，不硬撑）。
  bool moveTo(int i, {required int length}) {
    if (length <= 1) return false;
    final int n = i.clamp(0, length - 1);
    if (n == _lead) return false;
    _lead = n;
    notifyListeners();
    return true;
  }

  /// 按方向翻一格（[dir] 取 -1 / +1）；到边界返回 false，**不绕圈**
  /// —— 游戏里那种「滑到头就停住」比无限轮播更符合「摊开」的观感。
  bool step(int dir, {required int length}) =>
      moveTo(_lead + (dir >= 0 ? 1 : -1), length: length);

  /// 把 [length] 变小（卡组换了）之后，领位是否还站得住；站不住就夹回来
  void clampTo(int length) {
    final int n = length <= 0 ? 0 : _lead.clamp(0, length - 1);
    if (n == _lead) return;
    _lead = n;
    notifyListeners();
  }

  /// 从拖拽位移 + **松手速度**反算「该落在哪一格」。
  ///
  /// [dx] = 本次手势累计横向位移（像素，右为正）；
  /// [stride] = 一格多少像素；[velocity] = 松手瞬间速度（像素/秒）。
  ///
  /// 规则（Apple《Designing Fluid Interfaces》§6 动量投影）：
  /// 先把速度投影成一个**落点**（[railProject]），再吸附到离落点最近的一格。
  /// 所以「轻甩一下」会连过好几格，而不是永远只翻一格 ——
  /// 慢拖（速度≈0）时投影≈0，退化成「吸附到最近一格」，与老行为一致。
  int settleIndex({
    required double dx,
    required double velocity,
    required double stride,
    required int length,
    required int startLead,
  }) {
    if (length <= 1 || stride <= 0) {
      return startLead.clamp(0, math.max(0, length - 1));
    }
    // 手指向左拖（dx < 0）＝ 看右边那一个 ＝ 领位 +1，所以取负号
    final double moved = -dx / stride;
    final double projected = moved - railProject(velocity) / stride;
    final int target = startLead + projected.round();
    return target.clamp(0, length - 1);
  }
}

/// 一条轨的外壳：手势 + 吸附 + 命中开关。
///
/// 外观全部由 [builder] 决定 —— 两套 rail 各自画自己的卡。
/// 外壳**不加 `ClipRect`**：卡片故意「向外浮动」溢出一点是设计的一部分，
/// 而且裁掉会把侧卡的命中区一起裁没（测试里要能直接 tap 到侧卡）。
///
/// ── 手感三条（Apple《Designing Fluid Interfaces》）──────────
///  1. **1:1 跟手**（§2）：手指怎么动，整叠怎么动，位移只走 `Transform`。
///  2. **速度交接**（§5）：松手时把手指速度喂给弹簧，从**当前值**出发回弹，
///     拖动与动画之间没有缝。
///  3. **可中断**（§3）：抓住正在回弹的整叠 = 从**当前这一帧**接手，
///     不跳回起点、不清零位移。
class RailShell extends StatefulWidget {
  const RailShell({
    super.key,
    required this.controller,
    required this.length,
    required this.stride,
    required this.builder,
    this.open = true,
    this.enabled = true,
    this.onLeadChanged,
    this.onDragProgress,
    this.rubberExtent = 320,
  });

  /// 领位状态机（由调用方持有，跨 rebuild 存活）
  final RailController controller;

  /// 卡组长度（0 或 1 = 不接手势，单卡居中）
  final int length;

  /// 一格多少像素 —— 拖拽位移换算成「翻几格」用
  final double stride;

  /// 画整条轨：拿到「当前位移」自己决定每张卡怎么摆
  final Widget Function(BuildContext context, double dx) builder;

  /// 是否展开（false 时断命中 + 由 [builder] 自己落收起态）
  final bool open;

  /// 是否允许手势
  final bool enabled;

  /// 领位变了（调用方据此响 `rung` / `tap` + 轻震）
  final VoidCallback? onLeadChanged;

  /// 拖动过程中报「现在压在第几格（可为小数）」—— 调用方据此做**档位咬合**反馈
  /// （每越过一格响一声 + 轻震，就是选择器的手感）。
  final ValueChanged<double>? onDragProgress;

  /// 橡皮筋的参照长度（像素，一般给视口宽）
  final double rubberExtent;

  @override
  State<RailShell> createState() => _RailShellState();
}

class _RailShellState extends State<RailShell>
    with SingleTickerProviderStateMixin {
  /// 本次手势的累计位移（像素）。
  ///
  /// ⚠️ 用 `ValueNotifier` 而不是 `setState`：跟手与回弹都是**每帧**变化，
  /// `setState` 会把外壳（手势 / 断命中）一起重建。这里只让「画卡的那棵子树」
  /// 跟着重建 —— 对应 animate-expo 的「别在手势/滚动里 setState」。
  final ValueNotifier<double> _dx = ValueNotifier<double>(0);

  /// 回弹用的真源弹簧（k=120, ζ=.9，见 [RailSpringTicker]）
  RailSpringTicker? _spring;
  late final Ticker _ticker = createTicker(_onTick);
  double _lastUs = 0;

  int get _len => widget.length;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
  }

  @override
  void didUpdateWidget(covariant RailShell old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
    widget.controller.clampTo(_len);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _ticker.dispose();
    _dx.dispose();
    super.dispose();
  }

  void _onController() {
    if (mounted) setState(() {});
  }

  bool get _canDrag => widget.open && widget.enabled && _len > 1;

  /// 越界时的渐进阻力（§9）：在两端继续往外拖，跟手量按 [rubberBand] 收敛
  double get _shownDx {
    final double raw = _dx.value;
    if (_len <= 1) return raw;
    final int lead = widget.controller.lead;
    final bool past = (lead == 0 && raw > 0) || (lead == _len - 1 && raw < 0);
    if (!past) return raw;
    return raw.sign * rubberBand(raw.abs(), widget.rubberExtent);
  }

  void _stopSpring() {
    _spring = null;
    if (_ticker.isActive) _ticker.stop();
  }

  void _onTick(Duration elapsed) {
    final double us = elapsed.inMicroseconds.toDouble();
    // 首帧 dt 从 0 起算；夹上限，免得掉帧时弹簧一步跨过头
    final double dt = ((us - _lastUs) / 1e6).clamp(0.0, 1 / 30);
    _lastUs = us;
    final RailSpringTicker? s = _spring;
    if (s == null) return;
    s.step(dt);
    if (s.done) {
      _stopSpring();
      _dx.value = 0;
      return;
    }
    _dx.value = s.value;
  }

  void _onDragStart(DragStartDetails _) {
    // 可中断（§3）：抓住正在回弹的整叠就从**当前这一帧**接手，
    // 不把位移清零 —— 清零会让整叠「跳」一下。
    _stopSpring();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_canDrag) return;
    _dx.value += d.delta.dx;
    // 手指向左拖（dx < 0）＝ 往右边那一格走
    widget.onDragProgress?.call(
      widget.controller.lead - _dx.value / widget.stride,
    );
  }

  void _onDragEnd(DragEndDetails d) {
    if (_canDrag) {
      final int before = widget.controller.lead;
      final int target = widget.controller.settleIndex(
        dx: _dx.value,
        velocity: d.velocity.pixelsPerSecond.dx,
        stride: widget.stride,
        length: _len,
        startLead: before,
      );
      if (widget.controller.moveTo(target, length: _len)) {
        // ⚠️ 领位换人时**补偿位移**，让「视觉位置」`p = lead − dx/stride` 保持连续。
        //
        // 不补偿的话，整叠会在松手那一瞬**跳一格**（缩放/倾角/明暗全部瞬变），
        // 然后才被弹簧推回来 —— 看上去就是「切换没有动画、很卡手」。
        // 补偿之后：位置不动，**剩下的距离由弹簧一路走完**，那才是动画。
        _dx.value += (target - before) * widget.stride;
        widget.onLeadChanged?.call();
      }
    }
    if (!mounted) return;
    if (railReduceMotion(context)) {
      _dx.value = 0;
      return;
    }
    // 速度交接（§5）：从当前值出发、带着手指速度回 0
    _spring = RailSpringTicker(
      from: _dx.value,
      to: 0,
      velocity: d.velocity.pixelsPerSecond.dx,
    );
    _lastUs = 0;
    _ticker.start();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.open,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onHorizontalDragStart: _canDrag ? _onDragStart : null,
        onHorizontalDragUpdate: _canDrag ? _onDragUpdate : null,
        onHorizontalDragEnd: _canDrag ? _onDragEnd : null,
        child: ValueListenableBuilder<double>(
          valueListenable: _dx,
          builder: (BuildContext _, double _, Widget? _) =>
              widget.builder(context, _shownDx),
        ),
      ),
    );
  }
}

/// 把真源弹簧跑完一次，返回一个能逐帧问「现在到哪了」的推子。
///
/// 与 [Spring] 同源（半隐式欧拉 + 子步 ≤1/120s），**不要**换成 Flutter 的
/// `SpringSimulation`（同样的 k/zeta 过冲与收敛都不一样，见 `stage/spring.dart`）。
///
/// [velocity] 是**初始速度**（像素/秒）—— 这是「速度交接」的接口：
/// 手指松开那一刻的速度直接喂进来，弹簧就接着它跑，中间没有缝。
class RailSpringTicker {
  RailSpringTicker({
    double from = 0,
    double to = 1,
    double velocity = 0,
    double k = 120,
    double zeta = .9,
  }) : _s = Spring(v: from, k: k, zeta: zeta) {
    _s.v = velocity;
    _s.set(to);
  }

  final Spring _s;

  /// 推进一步（[dt] 秒），返回当前位置
  double step(double dt) => _s.step(dt);

  bool get done => _s.done;

  double get value => _s.x;

  /// 换目标（可中断：从**当前值 + 当前速度**继续，不跳）
  void retarget(double to) => _s.set(to);
}

/// 单向「过冲」曲线：0 → 1，末尾轻轻过一下（≈1.08），用于入场与确认那一拍。
///
/// 这是 docs/28 §3.4-2 说的 `easeOutBack`。过冲量**收窄到 1.08**
/// （原型 `--spring` 的手感），不是 Flutter `Curves.easeOutBack` 的 1.10。
double railOvershoot(double t) {
  const double c1 = 1.08;
  const double c3 = c1 + 1;
  final double u = t - 1;
  return 1 + c3 * u * u * u + c1 * u * u;
}

/// 错峰入场的进度：给定「入场已过毫秒数」与「第几张」，返回 0~1 的过冲进度。
///
/// [i] 那张的入场在 `railStagger(i)` 之后开始，走 [durMs] 毫秒。
/// 窗口还没到就返回 0（还没开始动），过完返回 1。
double railEnter(double elapsedMs, int i, {double durMs = 420}) {
  final double start = railStagger(i).inMilliseconds.toDouble();
  if (elapsedMs <= start) return 0;
  final double t = ((elapsedMs - start) / durMs).clamp(0.0, 1.0);
  return railOvershoot(t);
}

/// 入场窗口的计时器：与动画系统解耦，测试里可以直接喂时间。
class RailEnterClock {
  RailEnterClock({this.spanMs = 900});

  /// 整段入场窗口多长（最后一张的错峰 + 它的时长，留一点余量）
  final double spanMs;

  double _elapsed = 0;
  bool _done = false;

  bool get done => _done;
  double get elapsedMs => _elapsed;

  /// 推进 [dtMs] 毫秒；返回是否还在窗口内
  bool advance(double dtMs) {
    if (_done) return false;
    _elapsed += dtMs;
    if (_elapsed >= spanMs) {
      _elapsed = spanMs;
      _done = true;
      return false;
    }
    return true;
  }

  void snapDone() {
    _elapsed = spanMs;
    _done = true;
  }
}
