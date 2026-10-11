import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/items.dart';
import '../design/tokens.dart';
import '../state/haptics.dart';
import '../state/sfx.dart';
import 'card_skins.dart';
import 'rail_base.dart';

/// ═══════════════════════════════════════════════════════════
///  甲 · 物件台（`docs/28` §4）—— 「选择道具」的新形态
///
///  道具是**实体物件**，所以走**厚卡 + 摊牌**：三件东西摊在台面上，
///  中间那件被推到你面前**抬起来**（悬停抬起），旁边两件**向外旋开让位**。
///
///  与乙 · 铭牌轨（`choice_rail.dart`，横版斜切薄牌 / 不缩放 / 阶梯缩进）
///  刻意不同：这里是**竖版厚卡**，靠**放大 + 抬起 + 旋转**领位。
///
///  ── 纪律（docs/28 §3.4）────────────────────────────────
///  1. **只动 `Transform` / `Opacity`** —— 卡的布局尺寸恒为 86×112，
///     领位的 104×136 由 `Transform.scale` 表达，绝不改布局（禁止 AnimatedContainer）。
///  2. 位移曲线 `kOut`（[kItemRailMs]）；过冲用 `railOvershoot`。
///  3. 手势 / 吸附 / 断命中全在 `RailShell` 里，这里只画外观与路由点击。
///  4. 减弱动态效果 → 直接落终态。
///
///  ── 几何（为什么是这些数）──────────────────────────────
///  抽屉内可用宽 = 390 − 14×2（`.drawer` 左右）− 14×2（内边距）− 2（1px 描边两侧）
///  = **332px**。三张 86 的卡 + 8 的间距 = 274；物件台视口取 **266**
///  （274 − 8 = 266，恰好留下 8px 横向滚动余量），
///  「去补给」键 60 + 6 的间隙 → 266 + 6 + 60 = 332 正好装满。
///  ⚠️ **横向滚动只是兜底**：三张卡与第 4 格「去补给」在不滚动时全部可见可点。
/// ═══════════════════════════════════════════════════════════

/// 普通位卡尺寸（布局尺寸恒为此值，领位由缩放表达）
const double kItemCardW = 208; // = 补给货架 L 档卡宽（CardTableSize.l）
const double kItemCardH = 292; // = 补给货架 L 档卡高

/// 领位卡的视觉尺寸（= 86 × [kItemLeadScale]）
const double kItemLeadW = 252;
const double kItemLeadH = 353;

/// 领位缩放 = 104 / 86
const double kItemLeadScale = kItemLeadW / kItemCardW; // ≈ 1.2093

/// 侧卡缩放。**取值受可读性铁律约束**（docs/28 §3.4-6：退让项的缩放不得让正文
/// 等效小于 13px）：名称字号 [kItemNameSize] 15 × .88 = **13.2px** ≥ 13。
/// 所以这里不是 .82 —— .82 会把 13px 的正文压到 10.7px，违反铁律。
const double kItemSideScale = .88;

/// 名称字号（F.cn）。配 [kItemSideScale] 保证等效 ≥ 13px。
const double kItemNameSize = 15;

/// 卡间距
/// 卡间距。外壳拆掉后可用宽从 332 放开到 362，所以从 8 松到 10。
///
/// ⚠️ 仍要保证 `kItemCardW * kItemLeadScale` ≤ [kItemStride]，
/// 否则领位卡放大后会压住邻卡（「免死金牌」被整张盖住那次就是这么来的）。
const double kItemGap = 10;

/// 一格 = 卡宽 + 间距（拖拽位移换算「翻几格」用，也用于滚动定位）
const double kItemStride = kItemCardW + kItemGap; // 94

/// 物件台视口宽。三张卡的内容宽是 274，视口取 266 → 留 8px 横向滚动余量，
/// 同时给右侧「去补给」键腾出 60 + 6 的位置（合计 332 = 抽屉内可用宽）。
const double kItemRailViewport = 362; // 抽屉可用全宽（390 − 14×2 外边距）

/// 物件台**视口高度**。必须容下领位卡的完整视觉高度 ——
/// 领位卡视觉高 [kItemLeadH]（136），居中缩放让它上下各溢出 12，
/// 再叠一次上抬 |[kItemLeadLift]|（12）→ 需要 136 + 12 = 148，留 6 余量给外发光。
///
/// ⚠️ 这里以前写的是 [kItemCardH]（112），于是 ClipRect 把领位卡的**上边框和圆环顶部**
/// 整整裁掉 24px —— 看起来像「卡片没有上边框」。视口高度必须按**领位卡的视觉尺寸**算，
/// 不能按布局尺寸算。
const double kItemRailViewportH = kItemLeadH + 12 + 6; // 154

/// 「去补给」那枚独立斜切小键的宽
const double kItemShopW = 60;

/// 物件台与「去补给」之间的间隙
const double kItemRailGap = 6;

/// 位移 / 形变时长（docs/28 §3.4-2：350~420ms）
const Duration kItemRailMs = Duration(milliseconds: 380);

/// 领位抬起高度（向上为负）
const double kItemLeadLift = -12;

/// 侧卡向外浮动的额外横向偏移
const double kItemFloatX = 14;

/// 侧卡旋转角（弧度，±4°）
const double kItemFloatTilt = 4 * math.pi / 180;

/// 侧卡下沉
const double kItemSinkY = 6;

/// 侧卡压暗
const double kItemDim = .55;

/// 无货 / 已生效的灰（沿用 `.it[disabled] { opacity: .35 }`）
///
/// ⚠️ 它现在**只**用于 [ItemCardState.opacity] 这个对外读数（冻结测试按它判态），
///    **不再**乘到渲染上 —— 宿主三次反馈「整张牌半透明」就是乘出来的。
///    无货改由「更暗的底 + 更灰的字 + 灰状态条」表达（材质，不是透明度）。
const double kItemDisabledOpacity = .35;

/// 中央圆环相对内容盒的右移量。
///
/// 卡面用了货架外壳的**左上 22px 斜切**：内容盒左起 16、圆环 44 居中后左缘落在 21，
/// 正好压在那条斜边上（切角上圆环会被削掉一牙）。右移 3px 让左缘到 24 —— 干净。
const double kItemGlyphNudge = 3;

/// 状态条三态
const Color kItemBarUsed = C.blue;
const Color kItemBarReady = Color(0x6638E1FF); // 暗青（可用）
const Color kItemBarOut = C.dim; // 无货

/// 物件台的裁切：**只限制左右，纵向完全放开**。
///
/// 用 `ClipRect` 会把领位卡的上边框一起裁掉（它比布局矩形高 24px）；
/// 完全不裁又会让侧卡盖到右边的「去补给」键上。所以只裁 x。
class _RailClip extends CustomClipper<Path> {
  const _RailClip();

  @override
  Path getClip(Size s) => Path()..addRect(
    Rect.fromLTRB(0, -s.height, s.width, s.height * 2),
  );

  @override
  bool shouldReclip(_RailClip oldClipper) => false;
}

/// ═══════════════════════════════════════════════════════════
///  物件台
/// ═══════════════════════════════════════════════════════════
class ItemRail extends StatefulWidget {
  const ItemRail({
    super.key,
    required this.open,
    required this.counts,
    required this.used,
    this.ids = Item.execIds,
    this.onUse,
  });

  /// 抽屉是否展开（false = 断命中 + 落收起态）
  final bool open;

  /// 持有数（`Store.S.items`）
  final Map<String, int> counts;

  /// 本单已经挂上生效的（原型 `A[k]`）
  final Set<String> used;

  /// 台面上摆哪几件（默认执行期那三样，顺序照原型写死）
  final List<String> ids;

  /// 用某件道具（真正的数值变化属于业务规则，这里只上报）
  final ValueChanged<String>? onUse;

  @override
  State<ItemRail> createState() => _ItemRailState();
}

class _ItemRailState extends State<ItemRail>
    with SingleTickerProviderStateMixin {
  /// 领位状态机（跨 rebuild 存活）
  final RailController _rail = RailController();

  /// 使用那一拍的脉冲：0 → 1（抬起 + 亮帧）→ 0
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    _pulse.addListener(_onPulseTick);
  }

  void _onPulseTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pulse.removeListener(_onPulseTick);
    _pulse.dispose();
    _rail.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ItemRail old) {
    super.didUpdateWidget(old);
    _rail.clampTo(widget.ids.length);
  }

  /// 换领位 → 响 `rung` + 轻震（docs/28 §3.3）
  ///
  /// 不再需要「滚到领位」那一步：三张卡 + 浮动量本来就在视口内
  /// （最左 25-43 = -18 起、最右 241+43 = 284 止，视口 266 —— 只溢出边缘一点，
  /// 而溢出是设计的一部分），所以滚动是多余的，已整段删除。
  void _onLeadChanged() {
    Sfx.play('rung');
    Haptics.buzz('choose');
  }

  /// 一张卡在**内容坐标**里的中心（`d.localPosition` 用的就是这套坐标）
  double _cardCx(int i) {
    final int d = i - _rail.lead;
    final double x = d == 0 ? 0 : d * kItemStride + d.sign * kItemFloatX;
    return kItemRailViewport / 2 + x;
  }

  /// 点一下台面 —— **按「点到哪一张卡」路由**，不按离中心的距离。
  ///
  ///  · 点到**领位卡** → 使用（`onUse` + 那一拍）
  ///  · 点到**侧卡** → 先送它到领位（`moveTo`，不响 `seal`），再使用它
  ///    —— 与冻结测试一致：`tap(exec.drawer.crit)` 必须真的用掉 crit。
  ///
  /// 用矩形判定而不是「离中心 ±N」：卡的真实中心受**向外浮动**影响
  /// （侧卡中心离领位一格 + 14px），用固定半径会在边缘上错判。
  ///
  /// `localPosition` 的原点就是内容盒原点（手势挂在 RailShell 的 builder 里，
  /// 与内容盒同源），所以直接拿来跟 [_cardCx] 比 —— 实测过，不要再加减滚动位。
  void _onTapUp(TapUpDetails d) {
    final int n = widget.ids.length;
    if (n <= 0) return;
    final double cx = d.localPosition.dx;
    for (int i = 0; i < n; i++) {
      if ((cx - _cardCx(i)).abs() <= kItemCardW / 2) {
        if (i != _rail.lead && _rail.moveTo(i, length: n)) _onLeadChanged();
        _use(widget.ids[i]);
        return;
      }
    }
    // 落在卡与卡之间的缝里：按方向翻一格
    final int dir = cx < kItemRailViewport / 2 ? -1 : 1;
    if (_rail.step(dir, length: n)) _onLeadChanged();
  }

  /// 使用某件道具（`ui.js:444`：只有「真的用上了」那一拍才响）
  ///
  /// 两个前置条件对齐原型：**本单没生效过**（`!A[k]`）且**手上有货**（`n > 0`）。
  /// 「已生效」的格子点了依旧走原回调（行为一字不动），只是不再补响那一声。
  void _use(String id) {
    final bool on = widget.used.contains(id);
    final int n = widget.counts[id] ?? 0;
    if (n <= 0 && !on) return; // 灰掉的：不回调、不响、不震
    if (!on && n > 0) {
      Sfx.play('seal');
      Haptics.buzz('seal');
    }
    _pulse.forward(from: 0); // 抬起弹一下 + 青色亮帧
    widget.onUse?.call(id);
  }

  /// 使用那一拍的位移曲线：0 → -6px 过冲 → 0
  double get _pulseLift {
    final double t = _pulse.value;
    if (t <= 0) return 0;
    final double k = t < .5 ? t * 2 : (1 - t) * 2;
    return -6 * railOvershoot(k);
  }

  /// 亮帧：中段最亮（原型「全屏白 16%」那一拍的卡面版）
  double get _flash {
    final double t = _pulse.value;
    if (t <= 0) return 0;
    final double k = t < .5 ? t * 2 : (1 - t) * 2;
    return (k * .16).clamp(0.0, .16);
  }

  @override
  Widget build(BuildContext context) {
    final int n = widget.ids.length;
    final bool reduce = railReduceMotion(context);
    // ⚠️ 裁切**只裁左右，不裁上下** —— 这是这一处唯一正确的裁法：
    //
    //  · 上下**必须放开**：领位卡是「放大 + 上抬」的，视觉高 [kItemLeadH]（136）
    //    再抬 12，需要 148 的纵向空间。以前视口高写 [kItemCardH]（112）又套了
    //    两层 `ClipRect`，结果领位卡的**上边框和圆环顶部被裁掉 24px**
    //    —— 看上去就像「卡片没有上边框」。
    //  · 左右**必须裁住**：侧卡会向外浮动溢出视口；不裁的话它们会盖到右边的
    //    「去补给」键上（真踩过：暴击芯片/免死金牌 糊在去补给上面）。
    //
    // 所以不能用 `ClipRect`（两向都裁），要用只限制 x 的自定义 clipper。
    return SizedBox(
      width: kItemRailViewport,
      height: kItemRailViewportH,
      child: ClipPath(
        clipper: const _RailClip(),
        // 领位卡比布局矩形高，用 Center 把「布局矩形」放在视口正中，
        // 让放大后的上下溢出量对称，不至于只往一边顶出去。
        child: Center(
          child: SizedBox(
            height: kItemCardH,
            child: RailShell(
              controller: _rail,
              length: n,
              stride: kItemStride,
              open: widget.open,
              onLeadChanged: _onLeadChanged,
              // 唯一的手势入口。必须**在 RailShell 之内**：
              // RailShell 的 `IgnorePointer(ignoring: !open)` 要能连它一起断掉
              // （放在外面就会出现「收起了还能点到」）。
              builder: (BuildContext _, double dx) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _onTapUp,
                child: _strip(n, dx, reduce),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 台面本体：普通位排在 `i * stride`，领位槽居中，
  /// 跟随拖拽时整条轨按 `dx` 平移（松手由 RailShell 用 `kOut` 弹回 0）。
  Widget _strip(int n, double dx, bool reduce) {
    if (n <= 0) return const SizedBox.shrink();
    final int lead = _rail.lead;
    final List<Widget> cards = <Widget>[];
    // 领位最后画（压在邻卡之上，视觉上「被推到你面前」）
    for (int i = 0; i < n; i++) {
      if (i == lead) continue;
      cards.add(_slot(i, lead, dx, reduce));
    }
    cards.add(_slot(lead, lead, dx, reduce));
    return Stack(clipBehavior: Clip.none, children: cards);
  }

  /// 一张卡的槽位：槽宽恒为 [kItemCardW]，卡按领位距离缩放 + 向外浮动 + 旋开
  Widget _slot(int i, int lead, double dx, bool reduce) {
    final int d = i - lead;
    final double x = d == 0 ? 0 : d * kItemStride + d.sign * kItemFloatX;
    return Positioned(
      left: kItemRailViewport / 2 - kItemCardW / 2 + x + dx,
      top: 0,
      width: kItemCardW,
      height: kItemCardH,
      child: Align(
        alignment: Alignment.topCenter,
        child: _card(i, d, reduce),
      ),
    );
  }

  Widget _card(int i, int d, bool reduce) {
    final String id = widget.ids[i];
    final Item? it = Item.byId(id);
    if (it == null) return const SizedBox.shrink();
    final int n = widget.counts[id] ?? 0;
    final bool on = widget.used.contains(id);
    return ItemCard(
      key: Key('exec.drawer.$id'),
      item: it,
      index: i,
      lead: d == 0,
      distance: d,
      count: n,
      used: on,
      disabled: n <= 0 && !on,
      reduceMotion: reduce,
      pulse: d == 0 ? _pulseLift : 0,
      flash: d == 0 ? _flash : 0,
    );
  }
}

/// ═══════════════════════════════════════════════════════════
///  一张竖版物件厚卡
///
///  · 右上角 mono 角标（`EX · 01`）
///  · 中央 44px 圆环 glyph（圆环 + 径向辉光 + 外发光）
///  · 名称（cn 15，配侧卡 .88 缩放 → 等效 13.2px）+ 持有数（mono 10）
///  · 底部 2px 状态条（已生效 = 实心发光 / 可用 = 暗青 / 无货 = 灰）
///
///  领位：[kItemLeadScale] 放大 + 抬起 [kItemLeadLift] + 旋转归零 + 青色外发光
///  侧位：向外浮动 [kItemFloatX] + 旋转 ±4° + 下沉 [kItemSinkY] + 压暗 [kItemDim]
/// ═══════════════════════════════════════════════════════════
class ItemCard extends StatefulWidget {
  const ItemCard({
    super.key,
    required this.item,
    required this.index,
    required this.lead,
    required this.distance,
    required this.count,
    required this.used,
    required this.disabled,
    this.reduceMotion = false,
    this.pulse = 0,
    this.flash = 0,
  });

  final Item item;
  final int index;
  final bool lead;

  /// 离领位几格（0 = 领位本身）
  final int distance;

  final int count;
  final bool used;
  final bool disabled;
  final bool reduceMotion;

  /// 使用那一拍的额外抬起（负值向上）
  final double pulse;

  /// 使用那一拍的亮帧不透明度
  final double flash;

  @override
  State<ItemCard> createState() => ItemCardState();
}

/// 卡的状态对外可见：测试要读它**本帧实际生效的** [opacity]，
/// 而不是去渲染树里猜哪一个 `Opacity` 才是这一张的。
class ItemCardState extends State<ItemCard> with SingleTickerProviderStateMixin {
  /// 0 = 完全让位，1 = 完全领位；换领位时在两者之间补间
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: kItemRailMs,
    value: widget.lead ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    if (widget.reduceMotion) _t.value = widget.lead ? 1 : 0;
  }

  @override
  void didUpdateWidget(covariant ItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion) {
      _t.value = widget.lead ? 1 : 0;
      return;
    }
    if (oldWidget.lead != widget.lead) {
      _t.animateTo(widget.lead ? 1 : 0, curve: kOut);
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  /// 本帧的让位程度（0 = 领位，1 = 完全让位）
  double get _side => 1 - _t.value;

  /// 本帧实际生效的不透明度（让位压暗 / 无货灰）。
  double get opacity => widget.disabled
      ? math.min(kItemDisabledOpacity, 1 - kItemDim * _side)
      : 1 - kItemDim * _side;

  @override
  Widget build(BuildContext context) {
    final double t = _t.value;
    final double side = 1 - t;
    final double scale = kItemLeadScale * t + kItemSideScale * side;
    final double rot = kItemFloatTilt * side * widget.distance.sign;
    final double dx = kItemFloatX * side * widget.distance.sign;
    final double dy = kItemLeadLift * t + kItemSinkY * side + widget.pulse;
    return Transform.translate(
      offset: Offset(dx, dy),
      child: Transform.rotate(
        angle: rot,
        child: Transform.scale(
          scale: scale,
          // 命中区留在布局矩形（86×112）上：领位放大后视觉溢出的那一圈
          // 不抢邻居的点击（本仓库踩过「隐形按钮吃掉下层点击」）。
          // 路由本身在 `_onTapUp` 里按矩形判，这里只是不让溢出区参与命中。
          transformHitTests: false,
          // ⚠️ 无货（disabled）**不套 Opacity** —— 宿主三次反馈「整张牌半透明」，
          //    根因就是这里：无货乘 .35 会连后面的她一起透出来。
          //    无货改用材质表达（更暗的底 + 更灰的字 + 灰状态条，见 [_face]）。
          //    侧位退让的压暗（kItemDim）保留：那是「退到后面」的空间关系，不是禁用。
          child: widget.disabled
              ? _face(t)
              : Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: _face(t),
                ),
        ),
      ),
    );
  }

  /// 卡面 = **外面补给货架卡的外壳 + 里面原来的道具卡内容**（宿主原话）。
  ///
  /// 外壳的每一项都取自 `card_skins.dart` 的**公开 API**（[ShelfClipper] /
  /// [ShelfColors] / [GlassLayer] / [GlassPainter]），不是照抄一份数值 ——
  /// 两边漂移的话宿主一眼就能看出「同一个样式长得不一样」。
  /// 对照表（货架 → 道具卡）：
  ///
  ///  · 形状        圆角 14 + 左上斜切 22px → 同（[ShelfClipper]）
  ///  · 背板        `ShelfColors.backplate`（0xFF050A14 不透明）→ 同
  ///  · 底          领位 [ShelfColors.leadTop]/[leadBottom] → 同；
  ///               侧位 [sideTop]/[sideBottom] → 同；无货 [offTop]/[offBottom] → 同
  ///  · 玻璃层      `GlassLayer(lead, phase)` → 同（对角高光跟手 = 使用那一拍）
  ///  · 描边 1px    领位 C.blue α110 / 侧位 C.line2 → 同
  ///  · 落影        领位 0xB3050812 (0,18) 36 −4 / 侧位 0x80000000 (0,8) 16 → 同
  ///  · 内边距      16 / 16 / 16 / 14 → 左/上/下同（16/16/14）；右 8（见 [_face] 里的实测依据）
  ///
  /// ⚠️ 形状是**真的裁**（ClipPath），不是画一个圆角矩形假装：
  ///    斜切吃掉左上角 22px，所以内容（圆环）要避开它（见 [kItemGlyphNudge]）。
  Widget _face(double t) {
    final bool on = widget.used;
    final bool out = widget.disabled;
    // ⚠️ **直接复用补给货架那张脸**（宿主 2026-10-11：「为啥不复用主界面补给的样式？
    //    又用了一种样式，请直接复用主界面补给的样式！」）。
    //
    //    上一版是「照着货架的数值自己搭一遍」——形状/材质/描边都对得上，
    //    但**排布是另一套**（角标在右上、圆环 44、名称居中），所以看上去仍然是
    //    另一种卡。这一版不再自搭：走同一个 [CardFace] + 同一个 [CardSkin.shelf]，
    //    只是把外挂件关掉（chrome: false —— 道具是拿来用的，不挂吊钩与价签）
    //    并把尺寸换成抽屉的 86×112。
    //
    //    要改货架卡的样子，改 card_skins.dart 一处，两边同时变 —— 这就是复用的意义。
    return CardFace(
      skin: CardSkin.shelf,
      size: CardTableSize.s,
      dims: const Dims(kItemCardW, kItemCardH),
      chrome: false, // 不要吊钩、不要价签行
      lead: widget.lead,
      dragPhase: widget.flash * 12, // 使用那一拍：玻璃高光跟着扫一下
      card: TableCard(
        id: widget.item.id,
        index: widget.index,
        kicker: 'EX · ${(widget.index + 1).toString().padLeft(2, '0')}',
        title: widget.item.name,
        glyph: widget.item.glyph,
        // 底部那行读数：已生效 / 持有 ×N（无货时也照实写 ×0）
        badge: on ? '已生效' : '持有 ×${widget.count}',
        enabled: !out,
      ),
    );
  }


}


/// ═══════════════════════════════════════════════════════════
///  「去补给」—— 独立斜切小键（不进卡组：它不是一个物件）
///
///  宽 60、与卡同高；内容走 `Matrix4.skewX` 斜切（斜切语言与派单板同源），
///  但**命中区留在矩形上**（斜切只做视觉，不改点击形状）。
/// ═══════════════════════════════════════════════════════════
class ShopKey extends StatelessWidget {
  const ShopKey({super.key, required this.coins, this.onTap});

  final int coins;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('exec.drawer.shop'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: kItemShopW,
        height: kItemCardH,
        decoration: BoxDecoration(
          color: const Color(0x0D38E1FF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: C.line2, width: 1),
        ),
        child: Transform(
          transform: Matrix4.skewX(-.14),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text('◈', style: fs(family: F.num, size: 20, wght: 800, height: 1, color: C.blue)),
              const SizedBox(height: 6),
              Text('去补给', style: fs(family: F.cn, size: 13, wght: 400, height: 1, color: C.ice)),
              const SizedBox(height: 3),
              Text('金币 $coins', style: fs(family: F.mono, size: 10, wght: 500, height: 1, color: C.mist)),
            ],
          ),
        ),
      ),
    );
  }
}
