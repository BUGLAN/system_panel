import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/items.dart';
import '../../design/ref.dart';
import '../../state/sfx.dart';
import '../../widgets/fx_particles.dart';
import 'ref_carousel.dart';
import 'ref_inputs.dart';
import 'ref_kit.dart';
import 'ref_motion.dart';
import 'ref_svg.dart';
import 'ref_tcard.dart' show RefDashedRRectPainter, refCssLinear;

/// ═══════════════════════════════════════════════════════════
///  补给站 —— 参考稿 #sc-shop（CSS L385-404，DOM L789-799，JS L1610-1636）
///
///  .sh（SUPPLY · 补给站 / 补给 / 返回）→ .shop-q 她的话
///  → #shopCar（3D 轮播，复用 .gcard 材质）→ .ruler → .shop-foot
///  （[使用]（只有补签券且持有时出现）+ [购买 · ◆价]）
///
///  购买（JS buy）：锁级 → 卡抖 + 报错；钱不够 → 按钮抖 + 嘴；
///  成功 → 扣钱 + 卡面 pop（亮 1.9 / 饱和 1.4）+ 爆点 + 环。
///  点焦点卡 = 购买（JS onTap: () => buy()）。
/// ═══════════════════════════════════════════════════════════
class RefShop extends StatefulWidget {
  const RefShop({
    super.key,
    required this.items,
    required this.owned,
    required this.coins,
    this.lv = 1,
    this.lead = 0,
    this.fx,
    this.onBack,
    this.onBuy,
    this.onUse,
    this.onToast,
  });

  final List<Item> items;

  /// item id → 持有数
  final Map<String, int> owned;
  final int coins;
  final int lv;
  final int lead;
  final FxController? fx;
  final VoidCallback? onBack;

  /// 真正扣钱入库；返回是否成功
  final bool Function(Item it)? onBuy;

  /// 使用（补签券）；返回是否成功
  final bool Function(Item it)? onUse;

  final void Function(String msg, {bool bad})? onToast;

  @override
  State<RefShop> createState() => _RefShopState();
}

class _RefShopState extends State<RefShop> with RefTimers<RefShop> {
  final RefCarouselController _car = RefCarouselController();
  final GlobalKey _carKey = GlobalKey();
  final math.Random _rnd = math.Random();
  late int _i = widget.lead.clamp(0, math.max(0, widget.items.length - 1));
  int _popTok = 0;
  int _popIdx = -1;
  int _shakeCard = 0;
  int _shakeBtn = 0;

  @override
  void dispose() {
    _car.dispose();
    super.dispose();
  }

  Item get _it => widget.items[_i.clamp(0, widget.items.length - 1)];
  bool _locked(Item it) => it.lv > 0 && widget.lv < it.lv;
  int _own(Item it) => widget.owned[it.id] ?? 0;

  Offset? _cardCenter() {
    final RenderBox? me = context.findRenderObject() as RenderBox?;
    final RenderBox? car =
        _carKey.currentContext?.findRenderObject() as RenderBox?;
    if (me == null || car == null || !car.hasSize) return null;
    return me.globalToLocal(car.localToGlobal(car.size.center(Offset.zero)));
  }

  void _toast(String m, {bool bad = false}) =>
      widget.onToast?.call(m, bad: bad);

  void _buy() {
    final Item it = _it;
    if (_locked(it)) {
      unawaited(Sfx.play('error'));
      setState(() => _shakeCard++);
      _toast('LV${it.lv} 才能买。先去升级，宿主。', bad: true);
      return;
    }
    if (widget.coins < it.price) {
      unawaited(Sfx.play('error'));
      setState(() => _shakeBtn++);
      const List<String> lines = <String>[
        '钱包比你的决心还薄。',
        '晶核不够。汗还没流够。',
        '她看了看你的余额，沉默了。',
      ];
      _toast(lines[_rnd.nextInt(lines.length)], bad: true);
      return;
    }
    final bool ok = widget.onBuy?.call(it) ?? false;
    if (!ok) return;
    unawaited(Sfx.play('buy'));
    later(const Duration(milliseconds: 520), () {
      if (!mounted) return;
      setState(() {
        _popIdx = _i;
        _popTok++;
      });
      final Offset? c = _cardCenter();
      final Color gc = Color(it.color);
      if (c != null) {
        widget.fx?.burst(
          c.dx,
          c.dy,
          n: 38,
          cols: <Color>[gc, Colors.white],
          min: 180,
          max: 720,
          life: .6,
        );
        widget.fx?.ripple(c.dx, c.dy, r1: 160, color: gc, w: 4, ms: 500);
      }
      final List<String> lines = <String>[
        '成交。她把${it.name}塞给你，假装很不情愿。',
        '${it.name} ×1 入库。别浪费。',
      ];
      _toast(lines[_rnd.nextInt(lines.length)]);
    });
  }

  void _use() {
    final Item it = _it;
    if (_own(it) <= 0) return;
    final bool ok = widget.onUse?.call(it) ?? false;
    if (!ok) return;
    unawaited(Sfx.play('success'));
    _toast('补签成功，连胜 +1。这叫补救，不叫作弊。');
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    final Item it = _it;
    final bool lk = _locked(it);
    final int short = it.price - widget.coins;
    final bool bad = lk || short > 0;
    final String buyTxt = lk
        ? 'LV${it.lv} 解锁'
        : (short > 0 ? '还差 ◆$short' : '购买 · ◆${it.price}');
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Ref.gutter,
        safe.top + Ref.sceneTop,
        Ref.gutter,
        safe.bottom + Ref.sceneBottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          RefReveal(
            index: 0,
            child: Row(
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
                RefXButton(onTap: widget.onBack, accent: Ref.mint, back: true),
              ],
            ),
          ),
          RefReveal(
            index: 1,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '“晶核是你流的汗变的。花吧，别犹豫。”',
                style: refText(
                  size: 14,
                  wght: 500,
                  height: 1.5,
                  color: Ref.dim,
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints box) =>
                    OverflowBox(
                      minWidth: box.maxWidth + Ref.gutter * 2,
                      maxWidth: box.maxWidth + Ref.gutter * 2,
                      minHeight: math.max(250, box.maxHeight),
                      maxHeight: math.max(250, box.maxHeight),
                      child: RefCarousel(
                        key: _carKey,
                        controller: _car,
                        count: widget.items.length,
                        start: _i,
                        onFocus: (int i) {
                          if (mounted) setState(() => _i = i);
                        },
                        onTap: (_) => _buy(),
                        itemBuilder:
                            (BuildContext _, int i, RefCarouselSlot slot) {
                              final Item x = widget.items[i];
                              Widget card = _ShopCard(
                                item: x,
                                own: _own(x),
                                locked: _locked(x),
                                slot: slot,
                                popToken: _popIdx == i ? _popTok : 0,
                              );
                              if (i == _i) {
                                card = RefShakeX(
                                  token: _shakeCard,
                                  child: card,
                                );
                              }
                              return card;
                            },
                      ),
                    ),
              ),
            ),
          ),
          RefReveal(index: 2, child: _ruler()),
          RefReveal(
            index: 3,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: <Widget>[
                  if (it.use == 'shop' && _own(it) > 0) ...<Widget>[
                    RefButton(
                      key: const Key('ref.shop.use'),
                      label: '使用',
                      primary: false,
                      small: true,
                      animateSheen: false,
                      onTap: _use,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: RefShakeX(
                      token: _shakeBtn,
                      child: RefButton(
                        key: const Key('ref.shop.buy'),
                        label: buyTxt,
                        accent: bad ? const Color(0xFF2C2944) : Ref.acid,
                        ink: bad ? Ref.dim : null,
                        onTap: _buy,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// .ruler（L225-228）：14×4 胶囊，焦点 30 宽 acid
  Widget _ruler() {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          for (int i = 0; i < widget.items.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 7),
            GestureDetector(
              onTap: () => _car.go(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Ref.ease,
                width: i == _i ? 30 : 14,
                height: 4,
                decoration: BoxDecoration(
                  color: i == _i ? Ref.acid : const Color(0x1FFFFFFF),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: i == _i
                      ? const <BoxShadow>[
                          BoxShadow(color: Ref.acid, blurRadius: 10),
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
}

/// .gcard（L190-216）+ 商品专属区（L386-400）
class _ShopCard extends StatefulWidget {
  const _ShopCard({
    required this.item,
    required this.own,
    required this.locked,
    required this.slot,
    required this.popToken,
  });
  final Item item;
  final int own;
  final bool locked;
  final RefCarouselSlot slot;
  final int popToken;

  @override
  State<_ShopCard> createState() => _ShopCardState();
}

class _ShopCardState extends State<_ShopCard> with TickerProviderStateMixin {
  /// .it-ic::before 12s 旋转
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  /// .gcard.pop：.5s，30% 处亮 1.9 / 饱和 1.4
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  @override
  void initState() {
    super.initState();
    _syncSpin();
  }

  @override
  void didUpdateWidget(_ShopCard old) {
    super.didUpdateWidget(old);
    if (widget.popToken != old.popToken && widget.popToken != 0) {
      _pop.forward(from: 0);
    }
    _syncSpin();
  }

  void _syncSpin() {
    final bool reduce = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    if (widget.slot.focus && !reduce) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Item it = widget.item;
    final Color gc = Color(it.color);
    final bool focus = widget.slot.focus;
    final BorderRadius r = BorderRadius.circular(22);
    final Widget face = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(focus ? 0xD9000000 : 0xBF000000),
            offset: const Offset(0, 30),
            blurRadius: focus ? 60 : 50,
            spreadRadius: focus ? -10 : -12,
          ),
          if (focus)
            BoxShadow(color: Ref.a(gc, .6), blurRadius: 46, spreadRadius: -8),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: refCssLinear(
                  155,
                  const <Color>[
                    Color(0xFF231E40),
                    Color(0xFF131124),
                    Color(0xFF0B0A15),
                  ],
                  const <double>[0, .52, 1],
                ),
              ),
            ),
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 1,
              child: ColoredBox(color: Color(0x1FFFFFFF)),
            ),
            // .deco：右下 170px 描边首字母
            Positioned(
              right: -30,
              bottom: -40,
              child: Text(
                it.code.substring(0, 1),
                style: TextStyle(
                  fontFamily: Ref.fd,
                  fontSize: 170,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  fontStyle: FontStyle.italic,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 1.5
                    ..color = Ref.a(gc, .2),
                ),
              ),
            ),
            Padding(padding: const EdgeInsets.all(18), child: _body(it, gc)),
            // ::after 高光（mx 30% / my 0%）
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-.4, -1),
                    radius: .9,
                    colors: <Color>[Color(0x2BFFFFFF), Color(0x00FFFFFF)],
                    stops: <double>[0, .48],
                  ),
                ),
              ),
            ),
            // ::before 1.5px 渐变描边（非焦点 .35）
            IgnorePointer(
              child: CustomPaint(
                painter: _GBorderPainter(gc: gc, opacity: focus ? 1 : .35),
              ),
            ),
            if (widget.slot.shade > .001)
              IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: widget.slot.shade),
                ),
              ),
          ],
        ),
      ),
    );
    return AnimatedBuilder(
      animation: _pop,
      child: face,
      builder: (BuildContext _, Widget? c) {
        if (!_pop.isAnimating) return c!;
        final double v = _pop.value;
        final double k = v < .3 ? v / .3 : (1 - v) / .7;
        // brightness(1 + .9k) 用白色加色近似
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            c!,
            IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: ColoredBox(
                  color: Color.lerp(
                    Colors.white,
                    gc,
                    .4,
                  )!.withValues(alpha: .35 * k),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _body(Item it, Color gc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // .it-top
        Row(
          children: <Widget>[
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: gc,
                boxShadow: <BoxShadow>[BoxShadow(color: gc, blurRadius: 8)],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'ITEM · ${it.code}',
              style: refText(
                family: Ref.fm,
                size: 11,
                wght: 700,
                ls: 3,
                height: 1.2,
                color: gc,
              ),
            ),
            const Spacer(),
            Text(
              '持有 ×${widget.own}',
              style: refText(
                family: Ref.fm,
                size: 11,
                wght: 700,
                ls: 1,
                height: 1.2,
                color: Ref.dim,
              ),
            ),
          ],
        ),
        // .it-ic 96：虚线旋转环 + 实环辉光 + 34 图标
        Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 16),
          child: Center(
            child: SizedBox(
              width: 96,
              height: 96,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  RotationTransition(
                    turns: _spin,
                    child: CustomPaint(
                      size: const Size.square(96),
                      painter: RefDashedRRectPainter(
                        color: Ref.a(gc, .6),
                        radius: 48,
                        width: 2,
                        dash: 6,
                        gap: 5,
                      ),
                    ),
                  ),
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: gc, width: 2),
                      gradient: RadialGradient(
                        colors: <Color>[Ref.a(gc, 0), Ref.a(gc, .4)],
                        stops: const <double>[.55, 1],
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(color: gc, blurRadius: 24),
                      ],
                    ),
                  ),
                  Container(
                    width: 68,
                    height: 68,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF151227),
                    ),
                  ),
                  RefSvgIcon(
                    paths: RefIcons.of(it.id),
                    color: gc,
                    size: 34,
                    glow: 8,
                  ),
                ],
              ),
            ),
          ),
        ),
        Text(
          it.name,
          style: refText(size: 24, wght: 900, height: 1.3, color: Ref.txt),
        ),
        const SizedBox(height: 6),
        Text(
          it.desc,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: refText(size: 13, wght: 400, height: 1.55, color: Ref.dim),
        ),
        const Spacer(),
        // .it-f
        Row(
          children: <Widget>[
            Text.rich(
              TextSpan(
                text: '持有 ',
                style: refText(size: 12, wght: 500, color: Ref.dim),
                children: <InlineSpan>[
                  TextSpan(
                    text: '×${widget.own}',
                    style: refText(
                      family: Ref.fd,
                      size: 15,
                      wght: 700,
                      color: Ref.txt,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            _PriceTag(
              text: widget.locked ? '🔒 LV${it.lv}' : '◆ ${it.price}',
              color: widget.locked ? Ref.dim : gc,
              border: widget.locked ? Ref.dim2 : gc,
            ),
          ],
        ),
      ],
    );
  }
}

/// .ptag（L399-400）：两端尖角价签
class _PriceTag extends StatelessWidget {
  const _PriceTag({
    required this.text,
    required this.color,
    required this.border,
  });
  final String text;
  final Color color;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TagPainter(border),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Text(
          text,
          style: refText(
            family: Ref.fd,
            size: 16,
            wght: 700,
            height: 1.2,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _TagPainter extends CustomPainter {
  const _TagPainter(this.c);
  final Color c;
  @override
  void paint(Canvas canvas, Size s) {
    Path tag(Rect r) => Path()
      ..moveTo(r.left + 10, r.top)
      ..lineTo(r.right - 10, r.top)
      ..lineTo(r.right, r.center.dy)
      ..lineTo(r.right - 10, r.bottom)
      ..lineTo(r.left + 10, r.bottom)
      ..lineTo(r.left, r.center.dy)
      ..close();
    final Rect r = Offset.zero & s;
    canvas.drawPath(tag(r), Paint()..color = Ref.a(c, .12));
    canvas.drawPath(
      tag(r.deflate(.75)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = c,
    );
  }

  @override
  bool shouldRepaint(_TagPainter o) => o.c != c;
}

/// .gcard::before：1.5px、160° gc → 白 8%（35%）→ 透明（60%）→ gc
class _GBorderPainter extends CustomPainter {
  const _GBorderPainter({required this.gc, required this.opacity});
  final Color gc;
  final double opacity;

  @override
  void paint(Canvas canvas, Size s) {
    final Rect r = Offset.zero & s;
    final RRect o = RRect.fromRectAndRadius(r, const Radius.circular(22));
    canvas.drawDRRect(
      o,
      o.deflate(1.5),
      Paint()
        ..shader = refCssLinear(
          160,
          <Color>[
            Ref.a(gc, opacity),
            Color.fromRGBO(255, 255, 255, .08 * opacity),
            const Color(0x00000000),
            Ref.a(gc, opacity),
          ],
          const <double>[0, .35, .6, 1],
        ).createShader(r),
    );
  }

  @override
  bool shouldRepaint(_GBorderPainter o) => o.gc != gc || o.opacity != opacity;
}
