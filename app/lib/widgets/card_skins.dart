import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// ═══════════════════════════════════════════════════════════
///  牌面皮肤（docs/32 §4 / §5）—— 三种**完全不同**的牌面语言
///
///  宿主原话：「这些地方的卡片样式绝对不能每一处都一样」。
///  所以三种场景不是换色，而是换**形状 + 材质 + 排布 + 动效**：
///
///   · [CardSkin.shelf] 补给 · **货架**：竖版厚卡，**左上**斜切，
///     卡顶外挂一枚**吊钩**，卡底外挂**六边价签**。排布 = 扇。
///   · [CardSkin.tag] 称号 · **名牒**：竖版窄牌，顶部**真挖一个挂孔**
///     （透出后面的舞台）+ 一段挂绳，卡面是**纸纹**。
///     排布 = 挂在一条横杆上（中间垂得最低、两侧往上收）。
///   · [CardSkin.frame] 证据 · **取景窗**：横版宽幅，**四角取景括号**
///     + 内部网格 + 一条扫描线。排布 = 两张斜叠。
///
///  ── 材质：液态玻璃（对齐 skill-liquid-glass / AndroidLiquidGlass）──
///  那个库的效果链是 **vibrancy → blur → lens + highlight + shadow/innerShadow**。
///  ⚠️ 这里**只用其中不采样背景的那几条**：宿主明确要求牌**不能模糊、不能遮挡**
///  后面的 Live2D（后面还要拿它做角色口型），所以 `blur` / `lens` 一律不做，
///  只做「玻璃自己身上的光」：
///    · **表面色**（vibrancy）：一层极淡的白，把深底提起来
///    · **对角高光**（Highlight）：一条斜向光带，**位置跟着手势走**（液态感）
///    · **边缘折射**：内缩一圈的渐变描边，左上亮、右下收 —— 玻璃的厚度
///    · **内阴影**（InnerShadow）：底边内侧一圈暗 —— 厚玻璃
///    · 底色**提高不透明度**（宿主反馈「透明度过高」）：领位 α≈.94、侧位 α≈.97
///
///  ── 字体口径（apple-design §15）────────────────────────────
///  字距跟字号走（大标题负、小字标正）、行高跟字号反向、
///  层级 = 字重 + 字号 + 行高**一套**给的；压在玻璃上的正文用更亮的色 +
///  更重的字重（vibrancy），不用平灰。
/// ═══════════════════════════════════════════════════════════

/// 牌的三档尺寸
enum CardTableSize { l, m, s }

/// 牌面语言
enum CardSkin {
  /// 补给 · 货架（竖版厚卡 + 吊钩 + 六边价签）
  shelf,

  /// 称号 · 名牒（竖版窄牌 + 挂孔 + 纸纹）
  tag,

  /// 证据 · 取景窗（横版宽幅 + 四角括号 + 扫描线）
  frame,

  /// 主线 · 委托（docs/33：一条 2px 状态线 + 左侧印位 + 题面/规则行，
  /// 大牌审视态多出报酬条 / 代价条 / 她的批注）—— 第 4 套皮肤
  duty,
}

/// 主线委托的状态线（docs/33 §3.3）—— 只有 [CardSkin.duty] 读它。
///
///  · [sealed]    待发布：系统还没派（暗青虚线）
///  · [open]      可接：亮青实线 + 外辉
///  · [active]    执行中：亮青呼吸
///  · [done]      已完成：实心 + 压印
///  · [abandoned] 已放弃：灰、整张压暗
enum DutyState { sealed, open, active, done, abandoned }

class Dims {
  const Dims(this.w, this.h);

  final double w;
  final double h;
}

Dims dimsOf(CardSkin skin, CardTableSize size) {
  // 取景窗是**横版宽幅**（不是竖卡）：尺寸与档位无关
  if (skin == CardSkin.frame) return const Dims(246, 140);
  // 委托：**竖牌**（2026-10-12 宿主：横条牌 268×58 退役 —— 它本质是列表项不是牌）。
  // L = 牌屉里那张大牌（竖版九区）；M = 主线牌扇的竖牌；S = XS 微牌（换目标预设）
  if (skin == CardSkin.duty) {
    return switch (size) {
      CardTableSize.l => const Dims(208, 292),
      // docs/39 M-05：132×196 → 148×220（牌扇领位牌）。
      // CardTable 高度 = 220 + topPad 26 + dy2 38 + 30 = 314。
      CardTableSize.m => const Dims(148, 220),
      CardTableSize.s => const Dims(100, 72),
    };
  }
  return switch (size) {
    CardTableSize.l => const Dims(208, 292),
    CardTableSize.m => const Dims(132, 196),
    CardTableSize.s => const Dims(86, 112),
  };
}

/// 每种皮肤自己的牌桌几何。
///
/// `dy` 为负 = 往上（「挂」的语言：名牒两侧往上收）；为正 = 往下。
class SkinGeom {
  const SkinGeom({
    required this.stride,
    required this.dx1,
    required this.dx2,
    required this.dy0,
    required this.dy1,
    required this.dy2,
    required this.rot1,
    required this.scale1,
    required this.scale2,
    required this.op1,
    required this.op2,
    required this.topPad,
  });

  /// 一格拖拽多少像素
  final double stride;

  /// 侧位横移（±1 / ±2）
  final double dx1;
  final double dx2;

  /// 领位 / ±1 / ±2 的纵向位移
  final double dy0;
  final double dy1;
  final double dy2;

  /// 侧位外倾角（度）
  final double rot1;

  /// 缩放与压暗
  final double scale1;
  final double scale2;
  final double op1;
  final double op2;

  /// 桌面上下留白
  final double topPad;
}

SkinGeom geomOf(CardSkin s) => switch (s) {
  // 货架：摊得更开、旋得更狠、领位抬得更高 —— 「摊开一货架」
  //
  // ⚠️ op（不透明度）**不参与让位**：宿主三次反馈「透明度太高」。
  //    牌底一律**全不透明**（0xFF…），退到后面靠的是**更暗的底 + 更小的缩放
  //    + 更紧的落影**（材质重量）。"玻璃感"由表面色 / 对角高光 / 边缘折射 /
  //    内阴影给 —— 不靠真透明，所以后面的 Live2D 也永远透不出来。
  CardSkin.shelf => const SkinGeom(
    // 2026-10-12：96 → 112。原来 stride 96 < 牌宽 208，相邻牌压掉 112px（54%），
    // 侧牌文字被硬裁（宿主截图「本单暴击率 +25…」）。拉宽后侧牌露出可读宽度，
    // 配合 `lead` 摘要（侧位不画规则行与价签）才真正解决裁字。
    stride: 112,
    dx1: 98,
    dx2: 152,
    dy0: -18,
    dy1: 26,
    dy2: 54,
    rot1: 7,
    scale1: .84,
    scale2: .64,
    op1: 1.0,
    op2: .99,
    topPad: 30,
  ),
  // 名牒：挂在横杆上（领位最低、两侧往上），不旋转、不缩太多
  CardSkin.tag => const SkinGeom(
    stride: 104,
    dx1: 104,
    dx2: 178,
    dy0: 8,
    dy1: -8,
    dy2: -20,
    rot1: 0,
    scale1: .86,
    scale2: .70,
    op1: 1.0,
    op2: .99,
    topPad: 34,
  ),
  // 委托：**竖牌扇**（2026-10-12 重设计）——像手里捏着一把牌：领位抬起，
  // 两侧向外倾、往下沉、缩小。横条牌的「竖直堆叠」（stride 66 / dx1 6）已退役。
  //
  // docs/39 M-05 / M-06（2026-10-17 真机走查后）：牌 132×196 → 148×220，
  // stride 96 → 104，侧位缩放 .86 → .84，领位纵向提升 −6 → −12。
  // 露出宽度账（M 档牌宽 148、侧位缩放 .84 = 124.3）：
  //   dx1 104 → 侧位内侧缘 104 − 124.3/2 = 41.85、外侧缘 −82.45；领位左缘 −74
  //   ⇒ 被压住 33px、露出约 91px —— 够放一行 14.3px/17pt 的名称（铁律 2）。
  CardSkin.duty => const SkinGeom(
    stride: 104,
    dx1: 104,
    dx2: 164,
    dy0: -12,
    dy1: 18,
    dy2: 38,
    rot1: 5,
    scale1: .84,
    scale2: .70,
    op1: 1.0,
    op2: .99,
    topPad: 26,
  ),
  // 取景窗：两张斜叠（横移很小、纵向错开），几乎不缩放
  CardSkin.frame => const SkinGeom(
    stride: 86,
    dx1: 38,
    dx2: 66,
    dy0: -12,
    dy1: 30,
    dy2: 52,
    rot1: 0,
    scale1: .94,
    scale2: .88,
    op1: 1.0,
    op2: .97,
    topPad: 26,
  ),
};

/// 牌桌上的一张牌（纯数据）
class TableCard {
  const TableCard({
    required this.id,
    this.kicker,
    this.title = '',
    this.glyph,
    this.rule,
    this.note,
    this.badge,
    this.loot = const <String>[],
    this.price,
    this.accent,
    this.enabled = true,
    this.rarity = 0,
    this.sealWord,
    this.index,
    this.locked = false,
    this.shame = false,
    this.rank = '',
    this.dutyState = DutyState.open,
    this.dutyMeta,
    this.cost,
    this.elapsed,
    this.evidenceCount = 0,
  });

  final String id;
  final String? kicker;
  final String title;
  final String? glyph;
  final String? rule;
  final String? note;
  final String? badge;
  final List<String> loot;

  /// 金币价签（货架用）
  final int? price;

  /// 稀有度色（只用在左侧条与印位）
  final Color? accent;

  final bool enabled;
  final int rarity;
  final String? sealWord;

  /// 牌角的小序号（名牒的方印 / 货架的编号）
  final int? index;

  /// 未得（名牒：虚线框 + 剪影）
  final bool locked;

  /// 耻辱章（红框红印）
  final bool shame;

  // ── 以下是 [CardSkin.duty]（主线 · 委托）专属的区 ──────────────

  /// 档位字母（F~S）—— duty 的印位读它（其余皮肤走 [rarity] 索引）
  final String rank;

  /// 状态线（docs/33 §3.3）
  final DutyState dutyState;

  /// ⑤ 规则行：`20 min · 训练照片 · 力`
  final String? dutyMeta;

  /// ⑦ 代价条：有代价才出现（`认输 2/3 · 连击归零`）
  final String? cost;

  /// 执行中的计时读数（`12:04`）—— 状态线右侧
  final String? elapsed;

  /// ⑩ 证据带已经拍到几张（docs/39 M-16）。0 = 还没拍。
  ///
  /// 只给 [CardSkin.duty] 的牌屉读；本轮只读**份数**（缩略图要接存档里的
  /// 相对路径 + 会话里的 absPath，那是 P1 的活）。
  final int evidenceCount;
}

/// 高对比 / 反色 → 用实底材质（apple-design §14）。
///
/// ⚠️ Flutter 的 `AccessibilityFeatures` **没有** `reduceTransparency`
/// （系统「减弱透明度」在 Flutter 侧读不到），所以这里只能读
/// `highContrast` 与 `invertColors` 这两个能读到的信号。
bool solidMaterial(BuildContext context) {
  final MediaQueryData mq = MediaQuery.of(context);
  return mq.highContrast || mq.invertColors;
}

/// 压在深色玻璃上的正文颜色：领位那张更亮（vibrancy，§12）
Color vibrancyText({required bool lead}) =>
    lead ? const Color(0xFFB6CCE6) : const Color(0xFF9DB4D0);

/// ═══════════════════════════════════════════════════════════
///  货架外壳（**公开 API**）—— 给「货架之外、但要用同一套卡面语言」的地方复用
///
///  宿主原话：「使用这个道具卡，他的样式……就是主界面的那个里面补给的样式」。
///  所以这里把货架卡**外壳**（形状 / 材质 / 描边 / 落影）里可复用的部分提出来。
///  调用方拿到的是与货架卡**同源**的常量与画法 —— 不是「照着抄一份」：
///  抄一份两边就会各自漂移，而这种「同一处样式长得不一样」正是宿主最恨的。
///
///  ⚠️ 这里只**新增**：货架 / 名牒 / 取景窗三种皮肤自己的数值与画法一律不动，
///     原有私有实现已改为直接引用下面这些常量，渲染结果逐像素不变。
/// ═══════════════════════════════════════════════════════════

/// 货架外壳的形状：圆角 14 + **左上斜切 22px**。
///
/// 斜切是货架的身份证：`moveTo(0,22) → lineTo(22,0) → 右上 → 右下 → 左下`。
/// 不裁切、只需要一条路径时（描边、命中、遮罩）用 [shelfPath]。
const double kShelfCut = 22;

/// 货架外壳的圆角（与斜切一起构成形状；描边的圆角矩形用）
const double kShelfRadius = 14;

/// 货架外壳的形状路径。
///
/// [inset] = 整条路径向内收多少 —— 描边要收半个线宽，
/// 否则线有一半落在裁切之外、看上去只有 0.5px。
Path shelfPath(Size s, {double inset = 0}) {
  final double w = math.max(0, s.width - inset * 2);
  final double h = math.max(0, s.height - inset * 2);
  // 斜切长度不能被卡宽/卡高吃光：窄卡上必须退化，否则路径会自交
  final double b = math.min(kShelfCut, math.min(w, h));
  return Path()
    ..moveTo(inset, inset + b)
    ..lineTo(inset + b, inset)
    ..lineTo(inset + w, inset)
    ..lineTo(inset + w, inset + h)
    ..lineTo(inset, inset + h)
    ..close();
}

/// 货架外壳的裁切：圆角 14 + 左上斜切 22px。
///
/// 它**只裁形状，不裁阴影**：落影画在裁切之外的外层装饰上（见 [GlassLayer] 的用法）。
class ShelfClipper extends CustomClipper<Path> {
  const ShelfClipper();

  @override
  Path getClip(Size s) => shelfPath(s);

  @override
  bool shouldReclip(ShelfClipper oldClipper) => false;
}

/// 货架外壳的**材质常量**。
///
/// 全部是**不透明**的：宿主三次反馈「透明度太高 / 整张牌半透明」——
/// 退后、不可用都不许用 `Opacity` 表达，只能靠更暗的底 + 更灰的字（材质重量）。
class ShelfColors {
  const ShelfColors._();

  /// 不透明背板（保险）：无论渐变怎么算，牌都**不可能**透出后面的她
  static const Color backplate = Color(0xFF050A14);

  /// 领位底（离你更近 → 更亮）
  static const Color leadTop = Color(0xFF16294A);
  static const Color leadBottom = Color(0xFF080F1E);

  /// 侧位底（退后 → 更暗）
  static const Color sideTop = Color(0xFF0E1B30);
  static const Color sideBottom = Color(0xFF050A14);

  /// 不可用底（**最暗**；与「更灰的字」配对，不叠透明度）
  static const Color offTop = Color(0xFF0A101A);
  static const Color offBottom = Color(0xFF04070C);
}

/// 货架外壳的**玻璃层**：表面色（vibrancy）+ 对角高光（跟手）+ 边缘折射 + 内阴影。
///
/// 与货架卡用的是**同一个** [GlassPainter]，所以「玻璃的厚度」不会两边长得不一样。
/// [radius] 传卡自己的圆角（货架 = [kShelfRadius]）。
///
/// ⚠️ 这层**不采样背景**（不做 blur / lens）：宿主明确要求牌不能模糊、
///    不能遮挡后面的 Live2D（后面还要拿它做角色口型）。
class GlassLayer extends StatelessWidget {
  const GlassLayer({
    super.key,
    required this.lead,
    this.phase = 0,
    this.radius = kShelfRadius,
    this.solid = false,
  });

  /// 领位：表面色更亮、高光更亮
  final bool lead;

  /// -1~1：对角高光跟着手势走（这就是「液态」的来源）
  final double phase;

  final double radius;

  /// 高对比 / 反色 → 整层不画，改走实底材质（apple-design §14）
  final bool solid;

  @override
  Widget build(BuildContext context) {
    if (solid) return const SizedBox.shrink();
    return Stack(
      children: <Widget>[
        // 表面色（vibrancy）：一层极淡的白，把深底「提」起来
        Positioned.fill(
          child: ColoredBox(color: Colors.white.withAlpha(lead ? 13 : 7)),
        ),
        // 对角高光 + 边缘折射 + 内阴影
        Positioned.fill(
          child: CustomPaint(
            painter: GlassPainter(lead: lead, phase: phase, radius: radius),
          ),
        ),
      ],
    );
  }
}

/// ═══════════════════════════════════════════════════════════
///  牌面（正面）
/// ═══════════════════════════════════════════════════════════
class CardFace extends StatelessWidget {
  const CardFace({
    super.key,
    required this.skin,
    required this.card,
    required this.size,
    required this.lead,
    this.flash = 0,
    this.stamp = 0,
    this.sweep = 0,
    this.lean = 0,
    this.dragPhase = 0,
    this.chrome = true,
    this.showKicker = true,
    this.dims,
    this.far = false,
    this.leadT = 1,
    this.run = -1,
  });

  final CardSkin skin;
  final TableCard card;
  final CardTableSize size;
  final bool lead;

  /// 要不要画这身皮肤的**外挂件**（货架的吊钩、价签行）。
  ///
  /// 补给页要（那是货架，价格是它的一部分）；**执行期道具抽屉不要** ——
  /// 道具是拿来用的、不是拿来买的，挂个价签只会让人以为点它要花钱。
  final bool chrome;

  /// 要不要画左上角那行 mono 角标（`ITEM · DBL` / `EX · 01`）。
  ///
  /// 抽屉里关掉：宿主 2026-10-11 原话「卡片表面还有意义不明的字」——
  /// 执行期的道具卡上写 `EX · 01` 确实没有意义。
  final bool showKicker;

  /// 覆盖尺寸：抽屉里的卡比货架小（86×112），但必须长着**同一张脸**，
  /// 所以尺寸从这里进来，皮肤内部的一切都按这个盒子自适应。
  final Dims? dims;

  /// 落定亮闪 0~1
  final double flash;

  /// 压印进度 0~1
  final double stamp;

  /// 焦点扫光 0~1（**换领位时播一次**，不是循环）
  final double sweep;

  /// 拖拽倾角 -1~1（手势方向的提示）
  final double lean;

  /// 拖拽进度 -1~1 —— 液态玻璃的**对角高光跟着它走**
  final double dragPhase;

  /// 离领位 ≥2 格（docs/39 M-07「±2 位只留档位 + 状态线，不画文字」）。
  ///
  /// 只有 [CardSkin.duty] 读它（其余三套皮肤的侧位本来就靠缩放压暗表达层级，
  /// 没有「±2 位」这个概念）—— 默认 false，别处行为一行不变。
  final bool far;

  /// 领位外辉的淡入进度 0~1（docs/39 M-06「换领位时外辉 200ms 淡入」）。
  ///
  /// 同样只有 duty 读它；默认 1 = 立刻就位（其余皮肤不画这层辉光）。
  final double leadT;

  /// 执行中状态线的**光包相位** 0~1（docs/39 M-09「12px 光包 1.6s 走」）。
  ///
  /// `< 0` = 不画（默认 -1）—— 因此**不给它灌值的地方完全没有光包、行为不变**；
  /// 只有主线页的牌扇会用一个 15fps 的 ticker 往里灌。
  final double run;

  @override
  Widget build(BuildContext context) {
    final Dims d = dims ?? dimsOf(skin, size);
    return SizedBox(
      width: d.w,
      height: d.h,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(child: _body(context, d)),
          if (skin == CardSkin.shelf && chrome)
            Positioned(
              top: -13,
              left: 0,
              right: 0,
              height: 14,
              child: CustomPaint(painter: _HookPainter(lead: lead)),
            ),
          if (skin == CardSkin.tag)
            Positioned(
              top: -15,
              left: 0,
              right: 0,
              height: 16,
              child: CustomPaint(painter: _RopePainter(lead: lead)),
            ),
          // ⚠️ 价签**长在卡里**（见 `_shelf` 的底部一行）——
          //    宿主原话「下方有锁 60 这些，直接设计到卡片里面不要外挂」。
          if (flash > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: C.ice.withAlpha((flash * 255).round()),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          if (stamp > 0)
            Positioned.fill(child: IgnorePointer(child: _stampMark())),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, Dims d) => switch (skin) {
    CardSkin.shelf => _shelf(context, d),
    CardSkin.tag => _tag(context, d),
    CardSkin.frame => _frame(context, d),
    // 委托牌三态：XS 微牌（换目标预设）/ 宽盒 = 牌屉（主线详情）/ 竖牌（牌扇与审视）
    CardSkin.duty =>
      d.h <= 80
          ? _dutyChip(context, d)
          : (d.w > d.h * 1.2 ? _dutyDrawer(context, d) : _dutyFull(context, d)),
  };

  /// 液态玻璃的一层：表面色 + 对角高光（跟手）+ 边缘折射 + 内阴影。
  ///
  /// 实底模式（高对比 / 反色）下整层不画。
  Widget _glass({
    required bool lead,
    required bool solid,
    required double radius,
  }) {
    if (solid) return const SizedBox.shrink();
    return Stack(
      children: <Widget>[
        // 表面色（vibrancy）：一层极淡的白，把深底「提」起来
        Positioned.fill(
          child: ColoredBox(color: Colors.white.withAlpha(lead ? 13 : 7)),
        ),
        // 对角高光 + 边缘折射 + 内阴影
        Positioned.fill(
          child: CustomPaint(
            painter: GlassPainter(lead: lead, phase: dragPhase, radius: radius),
          ),
        ),
      ],
    );
  }

  // ── 补给 · 货架 ────────────────────────────────────────────
  Widget _shelf(BuildContext context, Dims d) {
    final Color accent = card.accent ?? C.blue;
    final bool solid = solidMaterial(context);
    // ⚠️ 「买不起」**不再**用 `Opacity` 表达。
    //    宿主截图里四张牌全是半透明 —— 根因就是这条：12 金币买不起任何一件，
    //    四张牌全部 `enabled: false` → 整张牌乘 .5 → 连她一起透出来。
    //    不可用现在由**更暗的底 + 更灰的字 + 红描边价签**表达（材质，不是透明度）。
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        // 描边只做「轮廓」；层级交给材质与落影，不靠到处发光的青线
        border: Border.all(
          color: !card.enabled
              ? C.rS.withAlpha(120)
              : (lead ? C.blue.withAlpha(120) : C.line2),
          width: 1,
        ),
        boxShadow: <BoxShadow>[
          // 落影分档：领位更大更沉（它离你更近），侧位只是贴着台面
          if (lead)
            const BoxShadow(
              color: Color(0xB3050812),
              offset: Offset(0, 18),
              blurRadius: 36,
              spreadRadius: -4,
            )
          else
            const BoxShadow(
              color: Color(0x80000000),
              offset: Offset(0, 8),
              blurRadius: 16,
            ),
          // 顶部受光收口（1px，不增加绘制层）
          const BoxShadow(
            color: Color(0x14FFFFFF),
            offset: Offset(0, 1),
            blurRadius: 0,
            spreadRadius: 0,
          ),
        ],
      ),
      child: ClipPath(
        clipper: const _ShelfClipper(),
        child: Stack(
          children: <Widget>[
            // 不透明背板（保险）：无论渐变怎么算，牌都**不可能**透出后面的她
            const Positioned.fill(
              child: ColoredBox(color: ShelfColors.backplate),
            ),
            // 底：领位更亮（离你更近），侧位更暗（退后）。都接近实底。
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: solid
                      ? const LinearGradient(
                          colors: <Color>[Color(0xFF0D1B33), Color(0xFF0D1B33)],
                        )
                      : LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          // 三组底色的真源在 [ShelfColors]（公开 API）：
                          // 领位更亮 / 侧位更暗 / 不可用最暗 —— 都不用透明度表达
                          colors: !card.enabled
                              ? const <Color>[
                                  ShelfColors.offTop,
                                  ShelfColors.offBottom,
                                ]
                              : (lead
                                    ? const <Color>[
                                        ShelfColors.leadTop,
                                        ShelfColors.leadBottom,
                                      ]
                                    : const <Color>[
                                        ShelfColors.sideTop,
                                        ShelfColors.sideBottom,
                                      ]),
                        ),
                ),
              ),
            ),
            _glass(lead: lead, solid: solid, radius: 14),
            if (card.accent != null)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 3,
                child: ColoredBox(color: card.accent!),
              ),
            if (sweep > 0) _sweepBand(sweep),
            Padding(
              padding: EdgeInsets.fromLTRB(
                (card.accent != null ? 3 : 0) + 16,
                16,
                16,
                14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (showKicker)
                    _kickerRow(showBadge: card.price == null || !chrome),
                  const SizedBox(height: 20),
                  if (card.glyph != null)
                    Center(child: _ring(card.glyph!, accent, 48)),
                  const SizedBox(height: 18),
                  Text(
                    card.title,
                    maxLines: lead ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: fs(
                      family: F.hd,
                      size: lead ? 19 : 16,
                      wght: 700,
                      ls: -.3, // 大字号负字距（§15）
                      height: 1.12, // 大字号紧行高（§15）
                      color: card.enabled ? C.ice : C.mist,
                    ),
                  ),
                  // ⑤ 规则行：**只在领位**（侧位不画 —— 它被压住的那半边不许有字）
                  if (lead && card.rule != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      card.rule!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: fs(
                        family: F.cn,
                        size: 11.5,
                        wght: 500, // 压在玻璃上：字重顶一点（vibrancy）
                        height: 1.45,
                        color: card.enabled ? vibrancyText(lead: lead) : C.dim,
                      ),
                    ),
                  ],
                  const Spacer(),
                  // ⑥ 报酬条（侧位只留数字）
                  if (card.loot.isNotEmpty) ...<Widget>[
                    if (lead)
                      Row(
                        children: <Widget>[
                          for (final String v in card.loot) ...<Widget>[
                            _chip(v),
                            const SizedBox(width: 6),
                          ],
                        ],
                      )
                    else
                      _lootRow(compact: true),
                    const SizedBox(height: 10),
                  ],
                  // 侧位只留一个**价格角标**（不画持有数、不画六边价签）——
                  // 价格还能横向比较，但被压住的那半边不再有字（铁律 2）
                  if (!lead && chrome && card.price != null) ...<Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          '◈',
                          style: fs(
                            family: F.num,
                            size: 10,
                            wght: 700,
                            height: 1,
                            color: card.enabled ? C.rB : C.dim,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${card.price}',
                          style: fs(
                            family: F.num,
                            size: 12,
                            wght: 700,
                            height: 1,
                            color: card.enabled ? C.ice : C.dim,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  // 价签在卡里：左下「持有 ×N」、右下六边价签（买不起 = 红描边 + 锁）
                  //
                  // ⚠️ 2026-10-12：**只在领位显示**。原来四张牌都挂价签与持有数，
                  //    侧牌被压掉 54% 后这两行挤成一团（宿主截图⑤）。
                  // 2026-10-23：价签改用 AnimatedSwitcher 平滑让位 ——
                  //    换领位时淡入，不再在侧位那一帧突然出现/消失。
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeOutCubic,
                    // ⚠️ 不用默认的 Stack layoutBuilder：牌面只有 148 宽，
                    //    过渡期叠两层会让行高抖动。这里**只留当前孩子** ——
                    //    进场淡入、退场立即（退出本来就该比进场快，且侧位
                    //    那一刻牌本身在缩，动效已经盖住）。
                    layoutBuilder: (Widget? current, List<Widget> previous) =>
                        current ?? const SizedBox.shrink(),
                    child: (lead && chrome && card.price != null)
                        ? Row(
                            key: const ValueKey<String>('price.on'),
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  card.badge ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: fs(
                                    family: F.mono,
                                    size: 9,
                                    wght: 600,
                                    height: 1,
                                    color: C.mist,
                                  ),
                                ),
                              ),
                              _hexPrice(card.price!, card.enabled),
                            ],
                          )
                        : const SizedBox.shrink(
                            key: ValueKey<String>('price.off'),
                          ),
                  ),
                  const SizedBox(height: 10),
                  _statusLine(accent),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 称号 · 名牒 ────────────────────────────────────────────
  Widget _tag(BuildContext context, Dims d) {
    final bool locked = card.locked;
    final bool solid = solidMaterial(context);
    final Color line = card.shame
        ? C.rS.withAlpha(190)
        : (lead ? C.blue.withAlpha(140) : C.line2);
    // 倾角由**拖拽位移**驱动（不是自己在那摆）
    // 未得也**不调透明度**（同上：乘出来的透明会把她透出来）
    return Transform.rotate(
      angle: lean * 3.5 * math.pi / 180,
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: <BoxShadow>[
            if (lead)
              const BoxShadow(
                color: Color(0xA603060E),
                offset: Offset(0, 14),
                blurRadius: 30,
                spreadRadius: -4,
              )
            else
              const BoxShadow(
                color: Color(0x73000000),
                offset: Offset(0, 6),
                blurRadius: 14,
              ),
          ],
        ),
        child: ClipPath(
          clipper: const _TagClipper(),
          child: Stack(
            children: <Widget>[
              // 不透明背板（保险）
              const Positioned.fill(
                child: ColoredBox(color: Color(0xFF050A14)),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: solid
                        ? const LinearGradient(
                            colors: <Color>[
                              Color(0xFF0D1B33),
                              Color(0xFF0D1B33),
                            ],
                          )
                        : LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: locked
                                ? const <Color>[
                                    Color(0xFF0A101A),
                                    Color(0xFF04070C),
                                  ]
                                : (lead
                                      ? const <Color>[
                                          Color(0xFF16294A),
                                          Color(0xFF080F1E),
                                        ]
                                      : const <Color>[
                                          Color(0xFF0E1B30),
                                          Color(0xFF050A14),
                                        ]),
                          ),
                  ),
                ),
              ),
              _glass(lead: lead, solid: solid, radius: 10),
              Positioned.fill(
                child: CustomPaint(
                  painter: _PaperPainter(
                    color: C.line2,
                    dashed: locked,
                    border: line,
                  ),
                ),
              ),
              if (card.badge == '已佩戴')
                Positioned.fill(child: CustomPaint(painter: _EtchPainter())),
              if (sweep > 0) _sweepBand(sweep),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 30, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        if (card.index != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: line),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              card.index!.toString().padLeft(2, '0'),
                              style: fs(
                                family: F.mono,
                                size: 8,
                                wght: 600,
                                height: 1,
                                color: card.shame ? C.rS : C.blue,
                              ),
                            ),
                          ),
                        const Spacer(),
                        if (card.shame)
                          Text(
                            '耻',
                            style: fs(
                              family: F.hd,
                              size: 13,
                              wght: 700,
                              height: 1,
                              color: C.rS,
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    if (card.glyph != null)
                      Center(
                        child: Text(
                          card.glyph!,
                          style: fs(
                            family: F.hd,
                            size: 30,
                            wght: 700,
                            height: 1,
                            color: C.dim,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      card.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: fs(
                        family: F.hd,
                        size: locked ? 15 : 17,
                        wght: 700,
                        ls: -.2,
                        height: 1.15,
                        color: locked ? C.mist : C.ice,
                      ),
                    ),
                    if (card.rule != null) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        card.rule!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: fs(
                          family: F.cn,
                          size: 10.5,
                          wght: 500,
                          height: 1.35,
                          color: locked ? C.dim : vibrancyText(lead: lead),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Container(
                            height: 2,
                            decoration: BoxDecoration(
                              color: card.badge == '已佩戴'
                                  ? C.blue
                                  : (locked ? C.dim : C.blue.withAlpha(110)),
                              boxShadow: card.badge == '已佩戴'
                                  ? <BoxShadow>[
                                      BoxShadow(
                                        color: C.blue.withAlpha(150),
                                        blurRadius: 8,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                        if (card.badge != null) ...<Widget>[
                          const SizedBox(width: 8),
                          Text(
                            card.badge!,
                            style: fs(
                              family: F.mono,
                              size: 8,
                              wght: 600,
                              height: 1,
                              color: C.blue,
                            ),
                          ),
                        ],
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
  }

  // ── 证据 · 取景窗 ──────────────────────────────────────────
  Widget _frame(BuildContext context, Dims d) {
    final bool solid = solidMaterial(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: lead ? C.blue.withAlpha(120) : C.line2,
          width: 1,
        ),
        boxShadow: <BoxShadow>[
          if (lead)
            const BoxShadow(
              color: Color(0xA603060E),
              offset: Offset(0, 14),
              blurRadius: 30,
              spreadRadius: -4,
            )
          else
            const BoxShadow(
              color: Color(0x73000000),
              offset: Offset(0, 6),
              blurRadius: 14,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: <Widget>[
            // 不透明背板（保险）
            const Positioned.fill(child: ColoredBox(color: Color(0xFF050A14))),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: solid
                      ? const LinearGradient(
                          colors: <Color>[Color(0xFF081426), Color(0xFF081426)],
                        )
                      : LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: lead
                              ? const <Color>[
                                  Color(0xFF0A1730),
                                  Color(0xFF03070F),
                                ]
                              : const <Color>[
                                  Color(0xFF081426),
                                  Color(0xFF02060E),
                                ],
                        ),
                ),
              ),
            ),
            _glass(lead: lead, solid: solid, radius: 8),
            Positioned.fill(
              child: CustomPaint(
                painter: _ViewfinderPainter(
                  lead: lead,
                  sweep: sweep,
                  accent: card.accent ?? C.blue,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 20, 20, 20),
              child: Row(
                children: <Widget>[
                  if (card.glyph != null)
                    _ring(card.glyph!, card.accent ?? C.blue, 46),
                  if (card.glyph != null) const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          card.kicker ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: fs(
                            family: F.mono,
                            size: 8.5,
                            wght: 600,
                            ls: 2, // 小字标正字距（§15）
                            height: 1,
                            color: C.blue,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          card.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: fs(
                            family: F.hd,
                            size: 18,
                            wght: 700,
                            ls: -.3,
                            height: 1.05,
                            color: C.ice,
                          ),
                        ),
                        if (card.rule != null) ...<Widget>[
                          const SizedBox(height: 7),
                          Text(
                            card.rule!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: fs(
                              family: F.cn,
                              size: 11,
                              wght: 500,
                              height: 1.3,
                              color: vibrancyText(lead: lead),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 共用零件 ──────────────────────────────────────────────

  /// 焦点扫光：一道**从上沿往下走**的亮带，走完就没（一次性）
  Widget _sweepBand(double t) {
    final double k = Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
    final double fade = (1 - t).clamp(0.0, 1.0);
    return Positioned(
      left: 0,
      right: 0,
      top: -24 + 64 * k,
      height: 22,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                C.ice.withAlpha(0),
                C.ice.withAlpha((52 * fade).round()),
                C.ice.withAlpha(0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kickerRow({bool showBadge = true}) {
    return Row(
      children: <Widget>[
        Container(width: 2, height: 9.5, color: C.blue),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            card.kicker ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: fs(
              family: F.mono,
              size: 9.5,
              wght: 600,
              ls: 2.2, // 小字标正字距（§15）
              height: 1,
              color: C.blue,
            ),
          ),
        ),
        if (showBadge && card.badge != null)
          Text(
            card.badge!,
            maxLines: 1,
            style: fs(
              family: F.mono,
              size: 9,
              wght: 600,
              height: 1,
              color: C.mist,
            ),
          ),
      ],
    );
  }

  Widget _statusLine(Color accent) {
    return Container(
      height: 2,
      decoration: BoxDecoration(
        color: card.enabled ? (lead ? accent : C.blue.withAlpha(90)) : C.dim,
        borderRadius: BorderRadius.circular(1),
        boxShadow: lead && card.enabled
            ? <BoxShadow>[
                BoxShadow(color: accent.withAlpha(130), blurRadius: 8),
              ]
            : null,
      ),
    );
  }

  /// 战利品格：实底（不叠半透明，§12）
  Widget _chip(String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1A33),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: C.line2),
      ),
      child: Text(
        v,
        style: fs(
          family: F.num,
          size: 11,
          wght: 700,
          ls: -.2,
          height: 1,
          color: C.blue,
        ),
      ),
    );
  }

  Widget _ring(String s, Color accent, double size) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accent, width: 1.5),
        gradient: RadialGradient(
          colors: <Color>[accent.withAlpha(46), accent.withAlpha(0)],
          stops: const <double>[0, .7],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(color: accent.withAlpha(52), blurRadius: 12),
        ],
      ),
      child: Text(
        s,
        style: fs(
          family: F.num,
          size: size * .34,
          wght: 800,
          ls: -.3,
          height: 1,
          color: accent,
        ),
      ),
    );
  }

  /// 六边价签（货架专属）：买不起 = 灰 + 红描边 + 一枚「锁」字
  Widget _hexPrice(int price, bool afford) {
    final Color fg = afford ? C.blue : C.dim;
    return SizedBox(
      width: 76,
      height: 30,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned.fill(
            child: CustomPaint(
              painter: _HexPainter(
                fill: const Color(0xFF061024), // 实底，不叠半透明
                line: afford ? C.blue.withAlpha(150) : C.rS.withAlpha(160),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                afford ? '◈' : '锁',
                style: fs(
                  family: afford ? F.num : F.cn,
                  size: 10,
                  wght: 700,
                  height: 1,
                  color: fg,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$price',
                style: fs(
                  family: F.num,
                  size: 13,
                  wght: 800,
                  ls: -.2,
                  height: 1,
                  color: fg,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 压印（scale 2.2→1、rotate −14°→−6°，与结算印章同一动词）
  Widget _stampMark() {
    final double k = _overshoot(stamp.clamp(0.0, 1.0));
    final double op = stamp < .18
        ? stamp / .18
        : (1 - ((stamp - .62) / .38).clamp(0.0, 1.0));
    return Center(
      child: Opacity(
        opacity: op.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: (-14 + 8 * stamp) * math.pi / 180,
          child: Transform.scale(
            scale: 2.2 - 1.2 * k,
            child: Text(
              card.sealWord ?? '接',
              style: fs(
                family: F.hd,
                size: skin == CardSkin.frame ? 64 : 92,
                wght: 700,
                height: 1,
                color: C.blue.withAlpha(215),
                shadows: <Shadow>[
                  Shadow(color: C.ice.withAlpha(170), blurRadius: 22),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

double _overshoot(double t) {
  const double c1 = 1.08;
  const double c3 = c1 + 1;
  final double u = t - 1;
  return 1 + c3 * u * u * u + c1 * u * u;
}

/// ═══════════════════════════════════════════════════════════
///  牌背 —— 留给「余波」（落定后未选的牌翻回背面收回袖中）
///  与将来可能的暗牌。本轮入场不做翻面，所以它暂时没有调用点。
/// ═══════════════════════════════════════════════════════════
class CardBackFace extends StatelessWidget {
  const CardBackFace({
    super.key,
    required this.skin,
    required this.size,
    required this.card,
    this.preGlow = 0,
  });

  final CardSkin skin;
  final CardTableSize size;
  final TableCard card;
  final double preGlow;

  @override
  Widget build(BuildContext context) {
    final Color edge = card.accent ?? C.blue;
    final BorderRadius radius = BorderRadius.circular(
      skin == CardSkin.frame ? 8 : (skin == CardSkin.shelf ? 14 : 10),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: skin == CardSkin.frame
              ? const <Color>[Color(0xFF061020), Color(0xFF02060F)]
              : const <Color>[C.abyss, C.navy],
        ),
        border: Border.all(
          color: preGlow > 0
              ? edge.withAlpha((255 * (.25 + .75 * preGlow)).round())
              : C.line2,
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: CustomPaint(painter: _BackPainter(skin: skin)),
      ),
    );
  }
}

/// ═══════════════════════════════════════════════════════════
///  画笔
/// ═══════════════════════════════════════════════════════════

/// 液态玻璃：对角高光（跟手）+ 边缘折射 + 内阴影。
///
/// **不采样背景**（不做 blur / lens）—— 宿主明确要求不能模糊、不能遮挡
/// 后面的 Live2D。玻璃的「厚度」全靠这一层自己画的光。
/// ⚠️ 这个类是**公开 API**（[GlassLayer] 与货架卡共用同一份画法）。
///    改成 public 只为了给「道具卡」这类外壳复用，画法一个字没动。
class GlassPainter extends CustomPainter {
  const GlassPainter({
    required this.lead,
    required this.phase,
    required this.radius,
  });

  final bool lead;

  /// -1~1：高光跟着手势横向走（这就是「液态」的来源）
  final double phase;

  final double radius;

  @override
  void paint(Canvas canvas, Size s) {
    final RRect rr = RRect.fromRectAndRadius(
      Offset.zero & s,
      Radius.circular(radius),
    );
    canvas.save();
    canvas.clipRRect(rr);

    // ① 对角高光（Highlight.Default）：一条斜向光带，位置跟手
    final double ph = phase.clamp(-1.0, 1.0);
    final double band = s.width * .62;
    final Rect bandRect = Rect.fromCenter(
      center: Offset(s.width * (.34 + .32 * ph), s.height * .46),
      width: band,
      height: s.height * 2,
    );
    canvas.save();
    canvas.translate(bandRect.center.dx, bandRect.center.dy);
    canvas.rotate(-.42); // ≈ −24°
    canvas.drawRect(
      Rect.fromCenter(center: Offset.zero, width: band, height: s.height * 2),
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[
                Colors.white.withAlpha(0),
                Colors.white.withAlpha(lead ? 30 : 16),
                Colors.white.withAlpha(0),
              ],
              stops: const <double>[0, .5, 1],
            ).createShader(
              Rect.fromCenter(
                center: Offset.zero,
                width: band,
                height: s.height * 2,
              ),
            ),
    );
    canvas.restore();

    // ② 边缘折射：内缩一圈的渐变描边，左上亮、右下收 —— 玻璃的厚度
    canvas.drawRRect(
      rr.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Colors.white.withAlpha(lead ? 74 : 36),
            Colors.white.withAlpha(0),
            C.blue.withAlpha(lead ? 46 : 20),
          ],
          stops: const <double>[0, .55, 1],
        ).createShader(Offset.zero & s),
    );

    // ③ 内阴影（InnerShadow）：底边内侧一圈暗 —— 厚玻璃
    final Rect low = Rect.fromLTWH(0, s.height * .60, s.width, s.height * .40);
    canvas.drawRect(
      low,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[const Color(0x00000000), const Color(0x66000000)],
        ).createShader(low),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(GlassPainter old) =>
      old.lead != lead || old.phase != phase || old.radius != radius;
}

/// 货架：左上斜切 22px —— 形状真源已提到公开 API [ShelfClipper] / [shelfPath]，
/// 这里只留一个同义别名，免得别处（与旧代码）两个名字各说各话。
class _ShelfClipper extends CustomClipper<Path> {
  const _ShelfClipper();

  @override
  Path getClip(Size s) => shelfPath(s);

  @override
  bool shouldReclip(_ShelfClipper oldClipper) => false;
}

/// 名牒：圆角矩形**挖掉一个挂孔**（真的透光）
class _TagClipper extends CustomClipper<Path> {
  const _TagClipper();

  @override
  Path getClip(Size s) {
    final Path body = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(10)),
      );
    final Path hole = Path()
      ..addOval(Rect.fromCircle(center: Offset(s.width / 2, 14), radius: 4.6));
    return Path.combine(PathOperation.difference, body, hole);
  }

  @override
  bool shouldReclip(_TagClipper oldClipper) => false;
}

/// 货架的吊钩：一条横杆 + 中央圆环
class _HookPainter extends CustomPainter {
  const _HookPainter({required this.lead});

  final bool lead;

  @override
  void paint(Canvas canvas, Size s) {
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = (lead ? C.blue : C.mist).withAlpha(lead ? 200 : 110);
    final double cx = s.width / 2;
    canvas.drawLine(Offset(cx - 26, 2), Offset(cx + 26, 2), p);
    canvas.drawCircle(Offset(cx, 7), 4, p);
  }

  @override
  bool shouldRepaint(_HookPainter old) => old.lead != lead;
}

/// 名牒的挂绳：一段竖线 + 顶端小圆
class _RopePainter extends CustomPainter {
  const _RopePainter({required this.lead});

  final bool lead;

  @override
  void paint(Canvas canvas, Size s) {
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = (lead ? C.blue : C.mist).withAlpha(lead ? 190 : 100);
    final double cx = s.width / 2;
    // 绳要从卡外一直垂到挂孔上沿（孔心在卡内 y=14、半径 4.6）
    canvas.drawLine(Offset(cx, 3), Offset(cx, s.height + 9), p);
    canvas.drawCircle(Offset(cx, 2.5), 2.2, p);
  }

  @override
  bool shouldRepaint(_RopePainter old) => old.lead != lead;
}

/// 名牒的纸纹 + 边框（未得时是虚线框）
class _PaperPainter extends CustomPainter {
  const _PaperPainter({
    required this.color,
    required this.dashed,
    required this.border,
  });

  final Color color;
  final bool dashed;
  final Color border;

  @override
  void paint(Canvas canvas, Size s) {
    final Paint line = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double y = 26; y < s.height; y += 12) {
      canvas.drawLine(Offset(0, y), Offset(s.width, y), line);
    }
    final RRect rr = RRect.fromRectAndRadius(
      Rect.fromLTWH(.8, .8, s.width - 1.6, s.height - 1.6),
      const Radius.circular(10),
    );
    final Paint b = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = border;
    if (!dashed) {
      canvas.drawRRect(rr, b);
      return;
    }
    final Path outline = Path()..addRRect(rr);
    for (final PathMetric metric in outline.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final double end = math.min(dist + 6, metric.length);
        canvas.drawPath(metric.extractPath(dist, end), b);
        dist = end + 5;
      }
    }
  }

  @override
  bool shouldRepaint(_PaperPainter old) =>
      old.color != color || old.dashed != dashed || old.border != border;
}

/// 已佩戴的刻痕
class _EtchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawLine(
      Offset(s.width * .12, s.height * .30),
      Offset(s.width * .88, s.height * .24),
      Paint()
        ..strokeWidth = 1
        ..color = C.ice.withAlpha(34),
    );
  }

  @override
  bool shouldRepaint(_EtchPainter old) => false;
}

/// 取景窗：内部网格 + 四角括号 + **一次性**扫描线
class _ViewfinderPainter extends CustomPainter {
  const _ViewfinderPainter({
    required this.lead,
    required this.sweep,
    required this.accent,
  });

  final bool lead;
  final double sweep;
  final Color accent;

  @override
  void paint(Canvas canvas, Size s) {
    // 网格压到很淡：它是「取景器」的质感，不该抢内容
    final Paint grid = Paint()
      ..color = C.blue.withAlpha(10)
      ..strokeWidth = 1;
    for (double x = 24; x < s.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), grid);
    }
    for (double y = 24; y < s.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(s.width, y), grid);
    }

    // 四角括号：领位更长更亮
    final double len = lead ? 26 : 18;
    final Paint b = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = (lead ? C.blue : C.mist).withAlpha(lead ? 220 : 120);
    const double m = 9;
    void corner(Offset o, double sx, double sy) {
      canvas.drawLine(o, o + Offset(len * sx, 0), b);
      canvas.drawLine(o, o + Offset(0, len * sy), b);
    }

    corner(const Offset(m, m), 1, 1);
    corner(Offset(s.width - m, m), -1, 1);
    corner(Offset(m, s.height - m), 1, -1);
    corner(Offset(s.width - m, s.height - m), -1, -1);

    // 扫描线：**换领位时扫一次**（ease-out 走完就没了），不是循环动画
    if (sweep > 0 && sweep < 1) {
      final double y =
          12 + (s.height - 24) * Curves.easeOutCubic.transform(sweep);
      final double fade = (1 - sweep).clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromLTWH(10, y, s.width - 20, 1.4),
        Paint()
          ..shader = LinearGradient(
            colors: <Color>[
              accent.withAlpha(0),
              accent.withAlpha((170 * fade).round()),
              accent.withAlpha(0),
            ],
          ).createShader(Rect.fromLTWH(10, y, s.width - 20, 1.4)),
      );
    }
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) =>
      old.lead != lead || old.sweep != sweep || old.accent != accent;
}

/// 六边价签底
class _HexPainter extends CustomPainter {
  const _HexPainter({required this.fill, required this.line});

  final Color fill;
  final Color line;

  @override
  void paint(Canvas canvas, Size s) {
    final double c = 8; // 斜边宽
    final Path p = Path()
      ..moveTo(c, 0)
      ..lineTo(s.width - c, 0)
      ..lineTo(s.width, s.height / 2)
      ..lineTo(s.width - c, s.height)
      ..lineTo(c, s.height)
      ..lineTo(0, s.height / 2)
      ..close();
    canvas.drawPath(p, Paint()..color = fill);
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = line,
    );
  }

  @override
  bool shouldRepaint(_HexPainter old) => old.fill != fill || old.line != line;
}

/// 牌背：三种皮肤各自的质感
class _BackPainter extends CustomPainter {
  const _BackPainter({required this.skin});

  final CardSkin skin;

  @override
  void paint(Canvas canvas, Size s) {
    if (skin == CardSkin.frame) {
      final Paint p = Paint()
        ..color = C.blue.withAlpha(110)
        ..strokeWidth = 1.2;
      canvas.drawLine(
        Offset(s.width / 2, s.height / 2 - 16),
        Offset(s.width / 2, s.height / 2 + 16),
        p,
      );
      canvas.drawLine(
        Offset(s.width / 2 - 16, s.height / 2),
        Offset(s.width / 2 + 16, s.height / 2),
        p,
      );
      canvas.drawCircle(
        Offset(s.width / 2, s.height / 2),
        22,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = C.blue.withAlpha(90),
      );
      return;
    }

    if (skin == CardSkin.tag) {
      final RRect r = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(s.width / 2, s.height / 2),
          width: s.width * .42,
          height: s.width * .42,
        ),
        const Radius.circular(4),
      );
      canvas.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = C.blue.withAlpha(120),
      );
      return;
    }

    final Paint grid = Paint()
      ..color = C.line2
      ..strokeWidth = 1;
    for (double x = 0; x <= s.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), grid);
    }
    for (double y = 0; y <= s.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(s.width, y), grid);
    }
    final double r = math.min(s.width, s.height) * .17;
    final Offset c = Offset(s.width / 2, s.height / 2);
    final Path hex = Path();
    for (int i = 0; i < 6; i++) {
      final double ang = math.pi / 3 * i - math.pi / 2;
      final Offset p = Offset(
        c.dx + r * math.cos(ang),
        c.dy + r * math.sin(ang),
      );
      if (i == 0) {
        hex.moveTo(p.dx, p.dy);
      } else {
        hex.lineTo(p.dx, p.dy);
      }
    }
    hex.close();
    canvas.drawPath(
      hex,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = C.blue.withAlpha(128),
    );
  }

  @override
  bool shouldRepaint(_BackPainter old) => old.skin != skin;
}

// ═══════════════════════════════════════════════════════════
//  第 4 套皮肤 · 主线委托（docs/33 §3.2 九区解剖）
//
//  宿主原话：「不要自己重写一套，直接搬补给页那一桌」——
//  所以外壳照抄货架的材质（[GlassLayer] / [ShelfColors] 同源），
//  只换**形状与排布**：横条铭牌（轨上）+ 竖版大牌（审视态）。
//
//  牌面九区 → 数据的映射：
//    ① 角标 MAIN · 03      card.kicker
//    ② 印位 档位字母        card.rank → accent
//    ③ 主图 六维单字印      card.glyph
//    ④ 名称 题面            card.title
//    ⑤ 规则行 时限/证据/维度 card.dutyMeta
//    ⑥ 报酬条              card.loot
//    ⑦ 代价条（有才出现）    card.cost
//    ⑧ 批注 她为什么派这单   card.note
//    ⑨ 状态线 2px           card.dutyState
// ═══════════════════════════════════════════════════════════

/// 状态线的颜色（暗青虚线 / 亮青 / 金 / 灰）。
///
/// docs/39 M-09：五态改成**形状 + 颜色双编码** —— 以前 open 与 active 是
/// 完全同款的一条亮青线，真机上分不出「能接」和「正在做」。现在：
///   可接 = 亮青**实线**；执行中 = 亮青实线 + **12px 光包 1.6s 沿 2px 线走**；
///   已完成 = 金线；待发布 = 暗青虚线；已放弃 = 灰线 + 整张压暗 .55。
/// （颜色只能扫一眼：低视力/色弱时靠的仍然是「实线/虚线/光包在不在动」。）
Color dutyLineColor(DutyState s) => switch (s) {
  DutyState.sealed => const Color(0x5538E1FF),
  DutyState.open => C.blue,
  DutyState.active => C.blue,
  DutyState.done => C.rB,
  DutyState.abandoned => const Color(0x559AA3B2),
};

/// 状态线的语义字（**不用状态文字表达"走过/脚下/未走"**那条纪律只管进度带；
/// 委托牌上允许出现「执行中 / 已完成」这类**动作读数**，因为它同时是按钮）
String dutyStateLabel(DutyState s) => switch (s) {
  DutyState.sealed => '待发布',
  DutyState.open => '可接',
  DutyState.active => '执行中',
  DutyState.done => '已完成',
  DutyState.abandoned => '已放弃',
};

extension _DutyFace on CardFace {
  // ── XS 微牌（100×72）—— 换目标预设 ──────────────────────────
  //
  // ⚠️ XS 档**塞不下九区**：只放 ① 角标 + ④ 单行名称 + ⑨ 状态线。
  //    塞规则行 / 报酬条必然裁字（§10 已知坑 4）。
  //    2026-10-12：原「横条铭牌」268×58 退役（它本质是列表项，不是牌）。
  Widget _dutyChip(BuildContext context, Dims d) {
    final bool solid = solidMaterial(context);
    final bool dim = card.dutyState == DutyState.abandoned;
    // 2026-10-23 优化：DecoratedBox → AnimatedContainer，换领位时
    // 描边与落影**补间**过渡（原来一帧硬切）。XS 微牌尺寸小、变化幅度必须更轻，
    // 所以时长比货架卡（200ms）再短一档（180ms）。
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: solid ? C.line2 : (lead ? C.blue.withAlpha(130) : C.line2),
          width: 1,
        ),
        boxShadow: <BoxShadow>[
          if (lead)
            const BoxShadow(
              color: Color(0xB3050812),
              offset: Offset(0, 12),
              blurRadius: 24,
              spreadRadius: -4,
            )
          else
            const BoxShadow(
              color: Color(0x66000000),
              offset: Offset(0, 5),
              blurRadius: 12,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: <Widget>[
            const Positioned.fill(
              child: ColoredBox(color: ShelfColors.backplate),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: solid
                      ? const LinearGradient(
                          colors: <Color>[Color(0xFF0D1B33), Color(0xFF0D1B33)],
                        )
                      : LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: dim
                              ? const <Color>[
                                  ShelfColors.offTop,
                                  ShelfColors.offBottom,
                                ]
                              : (lead
                                    ? const <Color>[
                                        ShelfColors.leadTop,
                                        ShelfColors.leadBottom,
                                      ]
                                    : const <Color>[
                                        ShelfColors.sideTop,
                                        ShelfColors.sideBottom,
                                      ]),
                        ),
                ),
              ),
            ),
            _glass(lead: lead, solid: solid, radius: 10),
            // 2026-10-23：XS 微牌补扫光 —— 竖牌与货架卡早就有，微牌缺一条，
            // 选中时的「被读了一下」缺少光上的回应。
            if (sweep > 0) _sweepBand(sweep),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // ① 角标
                    Text(
                      card.kicker ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: fs(
                        family: F.mono,
                        size: 8,
                        wght: 600,
                        ls: 1.2,
                        height: 1,
                        color: dim ? C.dim : (lead ? C.blue : C.mist),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // ④ 名称（XS 档最多两行，不再放别的区）
                    // 2026-10-23：用 AnimatedDefaultTextStyle 让「换领位」时
                    // 颜色与字重**补间**（原来 ice → blue 是一帧硬切）。
                    Expanded(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        style: fs(
                          family: F.cn,
                          size: 12,
                          wght: lead ? 700 : 500,
                          height: 1.25,
                          color: dim ? C.dim : (lead ? C.blue : C.ice),
                        ),
                        child: Text(
                          card.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ⑨ 状态线
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 2,
              child: _statusLine(),
            ),
          ],
        ),
      ),
    );
  }

  // ── 竖牌（牌扇，docs/39 M-05 起为 148×220）—— 只放「读得下的一档」──
  //
  // ⚠️ 这个盒子**放不下完整九区**（148 宽 → 内容区 124；塞满必 overflow，
  //    实机踩过 `BOTTOM OVERFLOWED BY 81 PIXELS`）。所以牌扇给的是
  //    ① 角标 / ② 印位 / ③ 字形 / ④ 名称 / ⑤ 规则行(1 行) / ⑥ 报酬(数字)
  //    / ⑨ 状态线 / 印章；**完整九区在牌屉**（`_dutyDrawer`）。
  //
  // docs/39 M-07 侧位摘要：相邻位只留 ① 角标 / ② 档位 / ④ 单行标题 / ⑨ 状态线
  //   （隐藏 kicker 之外的规则行与报酬）；±2 位**只留档位 + 状态线、不画文字**
  //   —— 侧位被压住的那 33px 上不许有字（铁律 2）。
  //
  // docs/39 M-08 排版：档位 26pt/800（辉光 blur 10）、标题 17pt、kicker 9.5、
  //   规则行 11.5、报酬 13、印章 10。
  Widget _dutyFull(BuildContext context, Dims d) {
    final Color accent = card.accent ?? C.blue;
    final bool solid = solidMaterial(context);
    final bool dim = card.dutyState == DutyState.abandoned;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: solid ? C.line2 : (lead ? C.blue.withAlpha(120) : C.line2),
        ),
        boxShadow: <BoxShadow>[
          // docs/39 M-06：领位的**青色外辉** α .45 / blur 22（换领位 200ms 淡入），
          // 黑色落影保留 —— 一个说「这张被抽出来了」，一个说「它离台面有多高」。
          if (lead && !solid)
            BoxShadow(
              color: C.blue.withAlpha((.45 * 255 * leadT).round()),
              blurRadius: 22,
              spreadRadius: -2,
            ),
          if (lead)
            const BoxShadow(
              color: Color(0xB3050812),
              offset: Offset(0, 16),
              blurRadius: 30,
              spreadRadius: -6,
            )
          else
            const BoxShadow(
              color: Color(0x66000000),
              offset: Offset(0, 7),
              blurRadius: 16,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: <Widget>[
            const Positioned.fill(
              child: ColoredBox(color: ShelfColors.backplate),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: solid
                      ? const LinearGradient(
                          colors: <Color>[Color(0xFF0D1B33), Color(0xFF0D1B33)],
                        )
                      : LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: dim
                              ? const <Color>[
                                  ShelfColors.offTop,
                                  ShelfColors.offBottom,
                                ]
                              : (lead
                                    ? const <Color>[
                                        ShelfColors.leadTop,
                                        ShelfColors.leadBottom,
                                      ]
                                    : const <Color>[
                                        ShelfColors.sideTop,
                                        ShelfColors.sideBottom,
                                      ]),
                        ),
                ),
              ),
            ),
            _glass(lead: lead, solid: solid, radius: 12),
            // docs/39 M-09「已放弃 = 整张压暗 .55」：压暗用**叠一块深底**表达，
            // 不是给整张卡套 Opacity —— 后者会 saveLayer（§5.5 红线），
            // 而且会把后面的舞台一起透出来（宿主三次反馈过的老病）。
            if (dim)
              const Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(color: Color(0x8C03060E)),
                ),
              ),
            // 稀有度色三处之一：左侧 3px 竖条
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 3,
              child: ColoredBox(color: accent),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // ① 角标 + ③ 字形（M-07：±2 位一个字都不画，全交给档位与状态线）
                  if (!far)
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            card.kicker ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: fs(
                              family: F.mono,
                              size: 9.5,
                              wght: 500,
                              ls: 1.4,
                              height: 1.2,
                              color: dim ? C.dim : C.blue,
                            ),
                          ),
                        ),
                        if (card.glyph != null)
                          Text(
                            card.glyph!,
                            style: fs(
                              family: F.cn,
                              size: 13,
                              wght: 700,
                              height: 1,
                              color: accent,
                            ),
                          ),
                      ],
                    ),
                  // M-07「±2 位只留档位 + 状态线，不画文字」：档位照样在顶部（它是
                  // 这张牌仅剩的识别信息），中间整段留白，底部交给状态线。
                  if (!far) const SizedBox(height: 6),
                  // ② 印位（docs/39 M-08：30 → 26pt，辉光 14 → blur 10 / α .45）
                  Text(
                    card.rank,
                    style: fs(
                      family: F.num,
                      size: 26,
                      wght: 800,
                      height: .9,
                      color: accent,
                      shadows: <Shadow>[
                        Shadow(color: accent.withAlpha(115), blurRadius: 10),
                      ],
                    ),
                  ),
                  if (!far) ...<Widget>[
                    const SizedBox(height: 6),
                    // ④ 名称（领位 17pt 2 行 / 侧位 17pt 1 行 → ×.84 ≈ 14.3）
                    Text(
                      card.title,
                      maxLines: lead ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: fs(
                        family: F.hd,
                        size: 17,
                        wght: 700,
                        height: 1.28,
                        color: dim ? C.dim : C.ice,
                      ),
                    ),
                  ],
                  // ⑤ 规则行：只在领位、且只一行（侧位不画，M-07）
                  if (lead && card.dutyMeta != null) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      card.dutyMeta!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: fs(
                        family: F.cn,
                        size: 11.5,
                        wght: 400,
                        height: 1.3,
                        color: C.mist,
                      ),
                    ),
                  ],
                  // 领位/相邻位用 Spacer 把报酬+印章压到底；±2 位也吃同一段留白
                  const Spacer(),
                  // ⑥ 报酬：只在领位、只留数字（M-07：侧位不画报酬）
                  if (lead && card.loot.isNotEmpty) _lootRow(compact: true),
                  if (!far) const SizedBox(height: 8),
                  if (!far) _stateStamp(),
                ],
              ),
            ),
            // ⑨ 状态线：贴底一条 2px（执行中在这条线上再叠一个光包，见 _statusLine）
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 2,
              child: _statusLine(run: run),
            ),
            // M-09「执行中 = 牌角 11pt 计时」：光包是**运动**，计时是**不动**的读数 ——
            // 两者都给，色弱也能读，静音/静止时也能读。
            if (card.dutyState == DutyState.active && card.elapsed != null)
              Positioned(
                right: 10,
                bottom: 9,
                child: Text(
                  card.elapsed!,
                  key: const Key('duty.timer'),
                  style: fs(
                    family: F.num,
                    size: 11,
                    wght: 700,
                    ls: .4,
                    height: 1,
                    color: C.blue,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── 牌屉（宽盒）—— 主线详情的**唯一**形态 ─────────────────
  //
  // 2026-10-12 重设计：原来详情是**居中**的 208×292 大牌，从屏高 19% 铺到 51%，
  // 正好把她的脸压在后面（§1.4）。现在改成从底部升起的**牌屉**，只占安全带。
  // 宽盒里九区重排成两列（左：角标/印位/名称/规则行；右：报酬/代价），
  // ⑧ 批注吸底 —— 中段那片空就是被它填掉的。
  Widget _dutyDrawer(BuildContext context, Dims d) {
    final Color accent = card.accent ?? C.blue;
    final bool solid = solidMaterial(context);
    final bool dim = card.dutyState == DutyState.abandoned;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: solid ? C.line2 : C.blue.withAlpha(110)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0xB3050812),
            offset: Offset(0, 20),
            blurRadius: 40,
            spreadRadius: -6,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: <Widget>[
            const Positioned.fill(
              child: ColoredBox(color: ShelfColors.backplate),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: solid
                      ? const LinearGradient(
                          colors: <Color>[Color(0xFF0D1B33), Color(0xFF0D1B33)],
                        )
                      : LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: dim
                              ? const <Color>[
                                  ShelfColors.offTop,
                                  ShelfColors.offBottom,
                                ]
                              : const <Color>[
                                  ShelfColors.leadTop,
                                  ShelfColors.leadBottom,
                                ],
                        ),
                ),
              ),
            ),
            _glass(lead: lead, solid: solid, radius: 16),
            // 稀有度色三处之一：左侧 3px 竖条
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 3,
              child: ColoredBox(color: accent),
            ),
            Padding(
              // docs/39 M-15：批注已经进了内容流（原来是 Positioned 吸底的），
              // 底部不再需要预留 58 那两行 —— 留 14 就够，多出来的高度给证据带。
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // ① 头部（角标 / 印位 34 / 名称 19 / 规则行 12.5 + 右侧报酬 chip）
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // ① 角标
                        Text(
                          card.kicker ?? '',
                          style: fs(
                            family: F.mono,
                            size: 9.5,
                            wght: 500,
                            ls: 1.7,
                            height: 1.2,
                            color: dim ? C.dim : C.blue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            // ② 印位（docs/39 M-15：40 → 34，别让档位字母抢了题面）
                            Text(
                              card.rank,
                              style: fs(
                                family: F.num,
                                size: 34,
                                wght: 800,
                                height: .9,
                                color: accent,
                                shadows: <Shadow>[
                                  Shadow(
                                    color: accent.withAlpha(110),
                                    blurRadius: 18,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            // ④ 名称
                            Expanded(
                              child: Text(
                                card.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: fs(
                                  family: F.hd,
                                  size: 19,
                                  wght: 700,
                                  ls: -.3,
                                  height: 1.25,
                                  color: dim ? C.dim : C.ice,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // ⑤ 规则行
                        if (card.dutyMeta != null)
                          Text(
                            card.dutyMeta!,
                            style: fs(
                              family: F.cn,
                              size: 12.5,
                              wght: 500,
                              height: 1.35,
                              color: vibrancyText(lead: lead),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  // 右列：⑥ 报酬 + ⑦ 代价
                  SizedBox(
                    width: 108,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '报酬 · REWARD',
                          style: fs(
                            family: F.mono,
                            size: 9,
                            wght: 600,
                            ls: 1.2,
                            height: 1,
                            color: C.mist,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (card.loot.isNotEmpty) _lootRow(),
                        if (card.cost != null) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            '-- ${card.cost} --',
                            style: fs(
                              family: F.mono,
                              size: 9,
                              wght: 500,
                              ls: .6,
                              height: 1.2,
                              color: C.rS.withAlpha(200),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _stateStamp(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
                  // ② 证据带（docs/39 M-16）：原来是最下面那排**牌外**的
                  //    五个无标签虚线圈（真机上是「空板下的五个空圈」）。
                  //    移进卡里，按五态给内容 —— 这一段就是被它填掉的空白。
                  const SizedBox(height: 12),
                  _evidenceBand(),
                  const SizedBox(height: 10),
                  // ③ 底部：状态线 + 她的批注（原来批注是 Positioned 吸底的，
                  //    重排后跟着内容走，不再和证据带之间空一大块）
                  Container(height: 1, color: C.line),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: card.note == null
                            ? const SizedBox.shrink()
                            : Text(
                                '» ${card.note!}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: fs(
                                  family: F.cn,
                                  size: 12.5,
                                  wght: 500,
                                  height: 1.45,
                                  color: C.mist,
                                ),
                              ),
                      ),
                      if (card.dutyState == DutyState.active &&
                          card.elapsed != null) ...<Widget>[
                        const SizedBox(width: 10),
                        Text(
                          card.elapsed!,
                          style: fs(
                            family: F.num,
                            size: 18,
                            wght: 700,
                            ls: .6,
                            height: 1,
                            color: C.blue,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // ⑨ 状态线：贴底一条 2px（card_skins 的 `_statusLine`）
            // ⑨ 状态线：贴底一条 2px
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 2,
              child: _statusLine(),
            ),
          ],
        ),
      ),
    );
  }

  /// ② 证据带（docs/39 M-15 / M-16）—— 牌屉中段那五个槽。
  ///
  /// 原来它在**牌外**（main_view 的独立托盘）：五个无标签、无数据、无点击的
  /// 虚线圈，加上牌屉卡片里 55% 的空玻璃，就是真机图 03/07 的样子。
  /// 现在移进卡里，并且按五态给内容：
  ///  · 可接   = 5 个虚线槽 + 「接单后可传证据」
  ///  · 执行中 = 已拍到的份数 + 「已拍 N/5」
  ///  · 已完成 = 只读槽 + 「N 份」
  ///  · 待发布 = 锁形占位 + 「派到你手上才能拍」
  ///  · 已放弃 = 灰槽 + 「这单作废了」
  ///
  /// ⚠️ 缩略图本轮只画**占位**：要接真图得从存档取相对路径 + 会话里的
  ///    absPath 再异步解码，那是 P1 的活；[TableCard.evidenceCount] 已经留好。
  Widget _evidenceBand() {
    final DutyState s = card.dutyState;
    final int n = card.evidenceCount.clamp(0, 5);
    final bool readonly =
        s == DutyState.done || s == DutyState.abandoned || s == DutyState.active;
    final String label = switch (s) {
      DutyState.open => '证据 · 最多 5 张',
      DutyState.active => '证据 · 已拍 $n/5',
      DutyState.done => '证据 · $n 份',
      DutyState.sealed => '证据 · 派到你手上才能拍',
      DutyState.abandoned => '证据 · 这单作废了',
    };
    final String hint = switch (s) {
      DutyState.open => '接单后可传证据',
      DutyState.active => n == 0 ? '还没拍。计时在走。' : '继续拍，凑齐 5 张。',
      DutyState.done => '提交时一起结的。',
      DutyState.sealed => '系统还没把它派给你。',
      DutyState.abandoned => '——',
    };
    return Column(
      key: const Key('duty.evidence'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              label,
              style: fs(
                family: F.mono,
                size: 10,
                wght: 600,
                ls: 1.1,
                height: 1.2,
                color: C.mist,
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: fs(
                  family: F.cn,
                  size: 10.5,
                  wght: 400,
                  height: 1.2,
                  color: C.dim,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 38,
          child: Row(
            children: <Widget>[
              for (int k = 0; k < 5; k++) ...<Widget>[
                if (k > 0) const SizedBox(width: 6),
                Expanded(
                  child: _evidenceSlot(
                    index: k,
                    filled: readonly && k < n,
                    locked: s == DutyState.sealed,
                    dead: s == DutyState.abandoned,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 证据带里的一格：虚线框（空）/ 编号占位（有）/ 锁形（待发布）
  Widget _evidenceSlot({
    required int index,
    required bool filled,
    required bool locked,
    required bool dead,
  }) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: filled
              ? C.blue.withAlpha(120)
              : (dead ? const Color(0x229AA3B2) : const Color(0x4D38E1FF)),
        ),
        gradient: filled
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[C.blue.withAlpha(30), C.blue.withAlpha(10)],
              )
            : null,
      ),
      child: locked
          ? Text(
              '锁',
              style: fs(
                family: F.cn,
                size: 10,
                wght: 400,
                height: 1,
                color: C.dim,
              ),
            )
          : filled
          ? Text(
              '${index + 1}',
              style: fs(
                family: F.num,
                size: 12,
                wght: 700,
                height: 1,
                color: C.blue.withAlpha(200),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  /// ⑨ 状态线 —— 五态**形状 + 颜色双编码**（docs/39 M-09）。
  ///
  ///  · 待发布 = 暗青**虚线**（CustomPainter 画，真正的虚线不是细线）
  ///  · 可接   = 亮青**实线** + 两端渐隐（静止）
  ///  · 执行中 = 亮青实线 + **12px 光包沿 2px 线 1.6s 走**（[_DutyRunPainter]）
  ///  · 已完成 = **金线**（C.rB）
  ///  · 已放弃 = **灰线**（整张另有一层压暗，见 [_dutyFull]）
  ///
  /// ⚠️ 光包是 CustomPainter 里画一个 12px 宽的渐变块，**不是**对整张卡做
  ///    Opacity/动画层 —— 那样每帧都 saveLayer（§5.5 红线）。
  ///    减弱动态时 [_DutyRunPainter] 不跑（`progress < 0` 直接不画）。
  Widget _statusLine({double run = -1}) {
    switch (card.dutyState) {
      case DutyState.sealed:
        return CustomPaint(painter: const _DutyDashPainter());
      case DutyState.abandoned:
        return const ColoredBox(color: Color(0x449AA3B2));
      case DutyState.done:
        return const DecoratedBox(
          decoration: BoxDecoration(
            // 金线也做两端渐隐：两端「收进去」比硬切更像刻上去的
            gradient: LinearGradient(
              colors: <Color>[
                Color(0x00FBBF24),
                Color(0xFFFBBF24),
                Color(0x00FBBF24),
              ],
            ),
          ),
        );
      case DutyState.open:
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[C.blue.withAlpha(0), C.blue, C.blue.withAlpha(0)],
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(color: C.blue.withAlpha(150), blurRadius: 10),
            ],
          ),
        );
      case DutyState.active:
        // 执行中 = 可接那条线 + 跑动的光包（两道编码叠在一起）
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    C.blue.withAlpha(0),
                    C.blue,
                    C.blue.withAlpha(0),
                  ],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(color: C.blue.withAlpha(150), blurRadius: 10),
                ],
              ),
            ),
            CustomPaint(painter: _DutyRunPainter(run)),
          ],
        );
    }
  }

  /// ⑥ 报酬条：EXP / 金币 / 六维。
  ///
  /// [compact] = 侧位摘要（铁律 2）：**只留数字**，芯片与标签一律不画 ——
  /// 侧位被压住的那半边不许有字，也不该塞满装饰。
  Widget _lootRow({bool compact = false}) {
    if (compact) {
      final String nums = card.loot
          .map((String t) => t.replaceAll(RegExp(r'^[^0-9+]*'), ''))
          .where((String s) => s.isNotEmpty)
          .join(' · ');
      return Text(
        nums,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: fs(
          family: F.num,
          size: 12,
          wght: 700,
          height: 1.2,
          color: C.mist,
        ),
      );
    }
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: <Widget>[
        for (final String t in card.loot)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0x33040E20),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: C.line2),
            ),
            child: Text(
              t,
              maxLines: 1,
              style: fs(
                family: F.mono,
                size: 9,
                wght: 700,
                height: 1,
                color: t.startsWith('EXP')
                    ? C.blue
                    : (t.startsWith('◈') ? C.rB : C.ice),
              ),
            ),
          ),
      ],
    );
  }

  /// 压印朱砂 —— 五态里**唯二**允许出现在牌面上的"字"（§4.A.4）：
  /// 已完成 = [solid] 实色印章；待发布 = 线框印章。
  /// 其余三态一律只靠状态线表达，**不写状态文字**。
  Widget _seal(String word, {bool solid = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(
          color: C.rS.withAlpha(solid ? 255 : 190),
          width: solid ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(3),
        color: solid ? C.rS.withAlpha(210) : C.rS.withAlpha(24),
      ),
      child: Text(
        word,
        style: fs(
          family: F.cn,
          size: 9,
          wght: 700,
          height: 1.1,
          ls: 1,
          color: solid ? C.ice : C.rS,
        ),
      ),
    );
  }

  /// 五态里那两枚印章（已完成 = 实色 / 待发布 = 线框）；其余三态返回空盒，
  /// 只走状态线 —— 这一条就是「禁止状态文字」的落地（§4.A.4）。
  Widget _stateStamp() => switch (card.dutyState) {
    DutyState.done => _seal(card.sealWord ?? '已完成', solid: true),
    DutyState.sealed => _seal('待发布'),
    _ => const SizedBox.shrink(),
  };
}

/// 执行中那条线上跑的**光包**（docs/39 M-09）。
///
/// 12px 宽的一段亮青，沿 2px 状态线从左往右走一圈（1.6s 循环）；
/// [progress] < 0 = 不画（reduced-motion / 非执行态）。
///
/// ⚠️ 只画这一小段 —— 不是给整条线套动画，也不是给卡加图层。
class _DutyRunPainter extends CustomPainter {
  const _DutyRunPainter(this.progress);

  /// 0~1 的相位；< 0 = 不画
  final double progress;

  /// 光包宽度（docs/39 M-09「12px 光包」）
  static const double kRunW = 12;

  @override
  void paint(Canvas canvas, Size s) {
    if (progress < 0) return;
    final double span = s.width + kRunW;
    final double head = progress.clamp(0.0, 1.0) * span;
    final double x0 = head - kRunW;
    final Rect r = Rect.fromLTWH(x0, 0, kRunW, s.height);
    final Paint glow = Paint()
      ..shader = LinearGradient(
        colors: <Color>[
          C.blue.withAlpha(0),
          C.blue.withAlpha(200),
          C.ice,
        ],
      ).createShader(r)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawRect(r, glow);
    canvas.drawRect(
      Rect.fromLTWH(head - 4, 0, 4, s.height),
      Paint()..color = C.ice,
    );
  }

  @override
  bool shouldRepaint(covariant _DutyRunPainter old) => old.progress != progress;
}

/// 待发布那条虚线状态线（`repeating-linear-gradient` 的等价物）
class _DutyDashPainter extends CustomPainter {
  const _DutyDashPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final Paint p = Paint()..color = const Color(0x5538E1FF);
    // 大牌是横向 2px、铭牌是纵向 2px —— 都按长边铺
    final bool horizontal = s.width >= s.height;
    final double len = horizontal ? s.width : s.height;
    for (double x = 0; x < len; x += 7) {
      if (horizontal) {
        canvas.drawRect(Rect.fromLTWH(x, 0, 4, s.height), p);
      } else {
        canvas.drawRect(Rect.fromLTWH(0, x, s.width, 4), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// 委托牌的状态线要不要呼吸（执行中）—— 由调用方驱动动画
extension DutyBreath on CardFace {
  bool get dutyBreathing => card.dutyState == DutyState.active;
}
