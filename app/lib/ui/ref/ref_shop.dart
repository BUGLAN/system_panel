import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/items.dart';
import '../../design/ref.dart';
import 'ref_inputs.dart';
import 'ref_kit.dart';

/// ═══════════════════════════════════════════════════════════
///  补给 —— 参考稿 #sc-shop（CSS L385-404，DOM L789-799）
///
///  .sh（eyebrow + h1 补给 + xbtn）→ .shop-q 她的话 → .car 商品卡轮播
///  → .ruler 刻度 → .shop-foot（[使用] ghost + [购买] pri）
///
///  商品卡复用 .gcard（L190-216）的材质，专属区是
///  .it-top（竖条 + 编号）→ .it-ic 96 双层旋转环 → .it-n 24 名
///  → .it-d 说明 → .it-f（持有 ×N + .ptag 六边价签）
/// ═══════════════════════════════════════════════════════════
class RefShop extends StatefulWidget {
  const RefShop({
    super.key,
    required this.items,
    required this.owned,
    required this.coins,
    this.lead = 0,
    this.onBack,
    this.onPick,
    this.onBuy,
    this.onUse,
  });

  final List<Item> items;

  /// item id → 持有数
  final Map<String, int> owned;
  final int coins;

  final int lead;
  final VoidCallback? onBack;
  final ValueChanged<int>? onPick;
  final ValueChanged<Item>? onBuy;
  final ValueChanged<Item>? onUse;

  @override
  State<RefShop> createState() => _RefShopState();
}

class _RefShopState extends State<RefShop> {
  late int _lead = widget.lead.clamp(0, math.max(0, widget.items.length - 1));

  @override
  void didUpdateWidget(RefShop old) {
    super.didUpdateWidget(old);
    if (widget.lead != old.lead) {
      _lead = widget.lead.clamp(0, math.max(0, widget.items.length - 1));
    }
  }

  Item? get _cur => widget.items.isEmpty
      ? null
      : widget.items[_lead.clamp(0, widget.items.length - 1)];

  @override
  Widget build(BuildContext context) {
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    // ⚠️ 参考稿里档案/补给是**整页场景**（不是浮层）：正文从场景顶边开始。
    //    保留「屏高 46%」那种舞台让位的话，整页只剩半屏（真机截图）。
    final double top = safe.top + Ref.sceneTop;
    final Item? it = _cur;
    final int have = it == null ? 0 : (widget.owned[it.id] ?? 0);
    final bool afford = it != null && widget.coins >= it.price;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Ref.gutter,
        top,
        Ref.gutter,
        safe.bottom + Ref.sceneBottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _head(),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '「晶核是你流的汗变的。花吧，别犹豫。」',
              style: refText(
                family: Ref.fc,
                size: 14,
                wght: 500,
                height: 1.5,
                color: Ref.dim,
              ),
            ),
          ),
          Expanded(
            child: it == null ? const SizedBox() : _card(it, have, afford),
          ),
          _ruler(),
          const SizedBox(height: 12),
          _foot(it, have, afford),
        ],
      ),
    );
  }

  /// .sh（L63）
  Widget _head() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const RefEyebrow(text: 'SUPPLY · 补给站', accent: Ref.mint),
              const SizedBox(height: 8),
              Text('补给', style: RefType.h1),
            ],
          ),
        ),
        RefXButton(onTap: widget.onBack, back: true, accent: Ref.mint),
      ],
    );
  }

  /// 商品卡（.gcard 材质 + .it-* 专属区）
  Widget _card(Item it, int have, bool afford) {
    final Color gc = Ref.mint;
    return Center(
      child: GestureDetector(
        onTap: widget.onPick == null ? null : () => widget.onPick!(_lead),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final double h = math.min(360.0, box.maxHeight);
            final double w = math.min(250.0, h * .7);
            return Container(
              width: w,
              height: h,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  begin: Alignment(-.8, -.9),
                  end: Alignment(.8, .9),
                  colors: <Color>[
                    Color(0xFF1E2C33),
                    Color(0xFF121A1E),
                    Color(0xFF0A1114),
                  ],
                  stops: <double>[0, .52, 1],
                ),
                border: Border.all(color: Ref.a(gc, .35), width: 1.5),
                boxShadow: <BoxShadow>[
                  const BoxShadow(
                    color: Color(0xC0000000),
                    offset: Offset(0, 30),
                    blurRadius: 50,
                    spreadRadius: -12,
                  ),
                  BoxShadow(
                    color: Ref.a(gc, .3),
                    blurRadius: 46,
                    spreadRadius: -8,
                  ),
                ],
              ),
              // ⚠️ 卡内容定高（顶栏 + 96 图标 + 24 名 + 3 行说明 + 底部持有/价签），
              //    矮屏（320×640）的卡高被压到 346 时溢出 14px。内容整体可滚，
              //    底部「持有 / 价签」那行固定贴底。
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _itTop(it),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SizedBox(
                            height: 100,
                            child: Center(
                              child: SizedBox(
                                width: 96,
                                height: 96,
                                child: _ItemIconPainter(
                                  glyph: it.glyph,
                                  color: gc,
                                ),
                              ),
                            ),
                          ),
                          Text(
                            it.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: refText(
                              family: Ref.fc,
                              size: 24,
                              wght: 900,
                              height: 1.2,
                              color: Ref.txt,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            it.desc,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: refText(
                              family: Ref.fc,
                              size: 13,
                              wght: 400,
                              height: 1.55,
                              color: Ref.dim,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '持有',
                            style: refText(
                              family: Ref.fc,
                              size: 12,
                              wght: 500,
                              height: 1,
                              color: Ref.dim,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '×$have',
                            style: refText(
                              family: Ref.fd,
                              size: 15,
                              wght: 700,
                              height: 1,
                              color: Ref.txt,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      RefHexTag(
                        label: '晶核 ${it.price}',
                        color: afford ? gc : Ref.dim2,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// .it-top（L387-389）：3×14 竖条 + 编号
  Widget _itTop(Item it) {
    return Row(
      children: <Widget>[
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: Ref.mint,
            boxShadow: <BoxShadow>[BoxShadow(color: Ref.mint, blurRadius: 8)],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'SUPPLY · ${it.id.toUpperCase()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: refText(
              family: Ref.fm,
              size: 11,
              wght: 700,
              ls: 3,
              height: 1,
              color: Ref.mint,
            ),
          ),
        ),
      ],
    );
  }

  /// .ruler（L225-228）
  Widget _ruler() {
    if (widget.items.length <= 1) return const SizedBox.shrink();
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 7,
      runSpacing: 6,
      children: <Widget>[
        for (int i = 0; i < widget.items.length; i++)
          GestureDetector(
            onTap: () => setState(() => _lead = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Ref.ease,
              width: i == _lead ? 30 : 14,
              height: 4,
              decoration: BoxDecoration(
                color: i == _lead ? Ref.acid : const Color(0x1FFFFFFF),
                borderRadius: BorderRadius.circular(2),
                boxShadow: i == _lead
                    ? <BoxShadow>[BoxShadow(color: Ref.acid, blurRadius: 10)]
                    : null,
              ),
            ),
          ),
      ],
    );
  }

  /// .shop-foot（L403-404）：[使用] ghost sm + [购买] pri flex 1
  Widget _foot(Item? it, int have, bool afford) {
    return Row(
      children: <Widget>[
        // 参考稿 JS L1621：只有**补签券**有「使用」这种即时消耗；
        // 双倍卡/暴击芯片是执行页装载的，补给页不该出现「使用」。
        if (it != null && it.id == 'patch' && have > 0) ...<Widget>[
          RefButton(
            key: const Key('ref.shop.use'),
            label: '使用',
            primary: false,
            small: true,
            animateSheen: false,
            onTap: () => widget.onUse!(it),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: RefButton(
            key: const Key('ref.shop.buy'),
            label: it == null ? '购买' : '购买 · 晶核 ${it.price}',
            enabled: afford,
            onTap: it == null || widget.onBuy == null || !afford
                ? null
                : () => widget.onBuy!(it),
          ),
        ),
      ],
    );
  }
}

/// .it-ic（L390-393）：96 内 2px 虚线环 12s 转 + inset 12 的实线环 24 辉光 + 图标
class _ItemIconPainter extends StatefulWidget {
  const _ItemIconPainter({required this.glyph, required this.color});

  final String glyph;
  final Color color;

  @override
  State<_ItemIconPainter> createState() => _ItemIconPainterState();
}

class _ItemIconPainterState extends State<_ItemIconPainter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        AnimatedBuilder(
          animation: _c,
          builder: (BuildContext context, Widget? child) => Transform.rotate(
            angle: _c.value * 2 * math.pi,
            child: CustomPaint(
              size: const Size(96, 96),
              painter: _DashedRingPainter(color: widget.color),
            ),
          ),
        ),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: widget.color, width: 2),
            boxShadow: <BoxShadow>[
              BoxShadow(color: widget.color, blurRadius: 24),
              BoxShadow(
                color: widget.color.withAlpha(102),
                blurRadius: 18,
                spreadRadius: -6,
              ),
            ],
          ),
          child: Center(
            child: Text(
              widget.glyph,
              style: refText(
                family: Ref.fc,
                size: 28,
                wght: 900,
                height: 1,
                color: widget.color,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// .it-ic::before：2px 虚线环（参考稿用 border-style:dashed 的圆环）
class _DashedRingPainter extends CustomPainter {
  const _DashedRingPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final Offset c = s.center(Offset.zero);
    final double r = s.width / 2 - 1;
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color.withAlpha(153);
    const double dash = 9;
    const double gap = 7;
    final double step = (dash + gap) / r;
    for (double a = 0; a < 2 * math.pi; a += step) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        a,
        dash / r,
        false,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter o) => o.color != color;
}
