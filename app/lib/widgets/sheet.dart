import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/items.dart';
import '../data/titles.dart';
import '../design/tokens.dart';
import '../state/host_state.dart';
import 'radar.dart';

/// ═══════════════════════════════════════════════════════════
///  投影面板（app.css L78-81 `#beam` + L436-498 `#sheet`）
///  她胸口打出一道光，光落在桌面上的那块投影上——档案/补给/系统共用这一层壳。
///
///  实测盒模型（390×844）：
///    sheet [0,321,390,523]（top 38%）
///    head [0,321,390,71] · kick [20,345,124,12] · h3 [20,364,124,22] · × [334,344,36,36]
///    body [0,392,390,452]（可滚）
///    arTop [20,400,350,47] · radar [45,488,300,245]
///    secs y = 465 / 751 / 849 / 1058（每个 margin-top 18）
///    beam 顶点 (195, .31173H)
/// ═══════════════════════════════════════════════════════════
class Sheet extends StatelessWidget {
  const Sheet({
    super.key,
    required this.host,
    this.kind = SheetKind.archive,
    this.visible = true,
    this.onClose,
  });

  final HostState host;
  final SheetKind kind;
  final bool visible;
  final VoidCallback? onClose;

  static const Map<SheetKind, List<String>> _titles = <SheetKind, List<String>>{
    SheetKind.archive: <String>['ARCHIVE · 宿主档案', '档案'],
    SheetKind.supply: <String>['SUPPLY · 补给', '补给'],
    SheetKind.system: <String>['SYSTEM · 设置', '系统'],
  };

  @override
  Widget build(BuildContext context) {
    final double h = MediaQuery.sizeOf(context).height;
    final List<String> t = _titles[kind]!;

    return Positioned(
      left: 0,
      right: 0,
      top: h * .38,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          offset: visible
              ? Offset.zero
              : const Offset(0, 1.04), // translateY(104%)
          duration: const Duration(milliseconds: 550),
          curve: kOut,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0xE6061228), Color(0xF7030812)],
                stops: <double>[0, .3],
              ),
            ),
            child: Stack(
              // `.sh-edge::after` 有一半探到面板上沿外面（CSS 里 #sheet 不裁），
              // Stack 默认 hardEdge 会把它切掉
              clipBehavior: Clip.none,
              children: <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _head(t[0], t[1]),
                    Expanded(
                      child: SingleChildScrollView(
                        key: const Key('sheet.body'),
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 34),
                        child: _body(),
                      ),
                    ),
                  ],
                ),
                // .sh-edge —— 顶边那道光
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _EdgePainter(),
                      size: const Size(double.infinity, 1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// .sh-head
  Widget _head(String kicker, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // `.sh-k` 是 inline，行框被父级 16px strut 撑到 19.2、文字下沉 6px
                SizedBox(
                  height: 19.2,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      kicker,
                      key: const Key('sheet.kicker'),
                      style: fs(
                        family: F.mono,
                        size: 9.5,
                        wght: 600,
                        ls: 2.09,
                        height: 1,
                        color: C.blue,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  key: const Key('sheet.title'),
                  style: fs(
                    family: F.hd,
                    size: 22,
                    wght: 400,
                    ls: .88,
                    height: 1,
                    color: C.ice,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onClose,
            behavior: HitTestBehavior.opaque,
            child: Container(
              key: const Key('sheet.close'),
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: C.line, width: 1),
              ),
              child: Text(
                '×',
                style: fs(
                  family: F.cn,
                  size: 22,
                  wght: 400,
                  height: 1,
                  color: C.ice,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    switch (kind) {
      case SheetKind.archive:
        return _archive();
      case SheetKind.supply:
      case SheetKind.system:
        // 两步走：补给 / 系统下一步再复刻
        return const SizedBox.shrink();
    }
  }

  /// ── 档案 ──────────────────────────────────────────────
  Widget _archive() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _arTop(),
        _section(
          '六维 · 平方根刻度',
          // `.radar { width:100%; max-width:300px; margin:4px auto 0 }` —— 要居中，
          // 不能让它被 Column 的 stretch 拉满
          Center(
            child: Radar(attrs: host.attrs, weakKey: host.weakest.key),
          ),
        ),
        _section('战绩', _stats()),
        _section('称号 · 点一下挂上', _titlesGrid()),
        _section('道具', _inv()),
      ],
    );
  }

  /// .ar-top —— 大等级 + 经验条 + 称号
  Widget _arTop() {
    return Row(
      key: const Key('sheet.arTop'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            // small：10px mono，vertical-align .9em（10×.9 = 9px）
            Transform.translate(
              offset: const Offset(0, -9),
              child: Text(
                'LV',
                style: fs(
                  family: F.mono,
                  size: 10,
                  wght: 600,
                  ls: 2,
                  height: 1,
                  color: C.mist,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${host.lv}',
              style: fs(
                family: F.num,
                size: 44,
                wght: 900,
                wdth: 80,
                height: 1,
                color: const Color(0xFFF3FDFF),
                shadows: <Shadow>[
                  Shadow(color: C.blue.withAlpha(128), blurRadius: 20),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 14), // .ar-top gap
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _arRow('EXP', <InlineSpan>[
                TextSpan(
                  text: '${host.exp}',
                  style: fs(
                    family: F.num,
                    size: 11,
                    wght: 700,
                    height: 1.3,
                    color: C.ice,
                  ),
                ),
                TextSpan(text: ' / ${HostState.need(host.lv)}'),
              ]),
              const SizedBox(height: 6),
              _bar(host.expRatio),
              const SizedBox(height: 8),
              _arRow('称号', <InlineSpan>[
                TextSpan(
                  text: '「${HostTitle.nameOf(host.title)}」',
                  style: fs(
                    family: F.cn,
                    size: 10,
                    wght: 400,
                    ls: 0,
                    height: 1.3,
                    color: C.blue,
                  ),
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  /// .ar-exp p —— 左标题右读数
  Widget _arRow(String label, List<InlineSpan> right) {
    final TextStyle base = fs(
      family: F.mono,
      size: 10,
      wght: 600,
      ls: 1,
      height: 1.3,
      color: C.mist,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(label, style: base),
        Text.rich(TextSpan(children: right, style: base)),
      ],
    );
  }

  /// `.rs-bar`（档案里复用结算那条）
  Widget _bar(double frac) {
    return Container(
      key: const Key('sheet.bar'),
      height: 6,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: C.blue.withAlpha(26),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: frac.clamp(0.0, 1.0),
          heightFactor: 1,
          child: DecoratedBox(
            key: const Key('sheet.bar.fill'),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[C.blue2, C.blue, Color(0xFFDFFAFF)],
                stops: <double>[0, .7, 1],
              ),
              borderRadius: BorderRadius.circular(3),
              boxShadow: <BoxShadow>[BoxShadow(color: C.blue, blurRadius: 12)],
            ),
          ),
        ),
      ),
    );
  }

  /// .sec —— 一条 kicker + 后面拉满的细线，再挂内容
  Widget _section(String kicker, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 13,
            child: Row(
              children: <Widget>[
                Text(
                  kicker,
                  style: fs(
                    family: F.mono,
                    size: 10,
                    wght: 400,
                    ls: 1.6,
                    height: 1,
                    color: C.mist,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Container(height: 1, color: C.line2)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  /// .stats —— 四个读数
  Widget _stats() {
    final List<List<String>> cells = <List<String>>[
      <String>['${host.doneCount}', '完成'],
      <String>['${host.critCount}', '暴击'],
      <String>['${host.failCount}', '认输'],
      <String>['${host.bestStreak}', '最长连击'],
    ];
    return Row(
      key: const Key('sheet.stats'),
      children: <Widget>[
        for (int i = 0; i < cells.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
              decoration: BoxDecoration(
                color: C.blue.withAlpha(13), // rgba(56,225,255,.05)
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: <Widget>[
                  Text(
                    cells[i][0],
                    style: fs(
                      family: F.num,
                      size: 20,
                      wght: 800,
                      height: 1,
                      color: C.ice,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cells[i][1],
                    style: fs(family: F.cn, size: 10, wght: 400, color: C.mist),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// .titles —— 拿到的实心，没拿到的写「？？？ · 提示」
  Widget _titlesGrid() {
    return Wrap(
      key: const Key('sheet.titles'),
      spacing: 7,
      runSpacing: 7,
      children: <Widget>[
        for (final HostTitle t in HostTitle.all)
          _titleChip(t, host.ownedTitles.contains(t.id)),
      ],
    );
  }

  Widget _titleChip(HostTitle t, bool owned) {
    final bool equipped = owned && host.title == t.id;
    final Color fg = equipped
        ? C.deep
        : owned
        ? C.ice
        : const Color(0xFF4F607B);
    final Color border = !owned
        ? const Color(0x4D4F607B) // rgba(79,96,123,.3)
        : t.shame
        ? const Color(0x66FF4D5E) // rgba(255,77,94,.4)
        : C.line2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: equipped ? C.blue : (owned ? C.blue.withAlpha(15) : null),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: border, width: 1),
        boxShadow: equipped
            ? <BoxShadow>[
                BoxShadow(color: C.blue.withAlpha(89), blurRadius: 14),
              ]
            : null,
      ),
      child: Text(
        owned ? t.name : '？？？ · ${t.hint}',
        style: fs(
          family: F.cn,
          size: 12,
          wght: equipped ? 650 : 400,
          height: 1,
          color: fg,
        ),
      ),
    );
  }

  /// .inv —— 两列道具
  Widget _inv() {
    return Wrap(
      key: const Key('sheet.inv'),
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final Item it in Item.all)
          SizedBox(
            width: 171,
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: C.blue.withAlpha(10), // rgba(56,225,255,.04)
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: <Widget>[
                  Text(
                    it.glyph,
                    style: fs(family: F.cn, size: 15, wght: 400, color: C.ice),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        it.name,
                        style: fs(
                          family: F.cn,
                          size: 12.5,
                          wght: 400,
                          color: C.ice,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '×${host.items[it.id] ?? 0}',
                        style: fs(
                          family: F.num,
                          size: 12,
                          wght: 700,
                          color: C.blue,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

enum SheetKind { archive, supply, system }

/// `#beam` —— 从她胸口打到面板上沿的两条边 + 一个渐变三角
class SheetBeam extends StatelessWidget {
  const SheetBeam({super.key, this.visible = true});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final Size s = MediaQuery.sizeOf(context);
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 350),
          child: CustomPaint(painter: _BeamPainter(size: s)),
        ),
      ),
    );
  }
}

class _BeamPainter extends CustomPainter {
  const _BeamPainter({required this.size});

  final Size size;

  /// `Stage.toScreen(0, NY.chest + .02)` 在 panel 相机下 =
  ///   sy + (ay − chest − .02) × S，其中 sy = .34H、S = .88·H/1.95、chest = −.10737
  ///   → (.34 − .06263 × .45128)H = **.31173H**
  static double apexY(double h) => h * .31173;

  @override
  void paint(Canvas canvas, Size s) {
    final Offset apex = Offset(s.width / 2, apexY(s.height));
    final double top = s.height * .38;
    const double inset = 10;
    final Offset left = Offset(inset, top);
    final Offset right = Offset(s.width - inset, top);

    // #beamG：从 #9ff0ff@.34 到 #38e1ff@.02 的竖向渐变
    final Path tri = Path()
      ..moveTo(apex.dx, apex.dy)
      ..lineTo(right.dx, right.dy)
      ..lineTo(left.dx, left.dy)
      ..close();
    canvas.drawPath(
      tri,
      Paint()
        ..shader = ui.Gradient.linear(apex, Offset(apex.dx, top), <Color>[
          const Color(0x579FF0FF),
          const Color(0x0538E1FF),
        ]),
    );

    // #beam line：rgba(159,240,255,.55) 1px
    final Paint line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x8C9FF0FF);
    canvas.drawLine(apex, left, line);
    canvas.drawLine(apex, right, line);
  }

  @override
  bool shouldRepaint(covariant _BeamPainter o) => o.size != size;
}

/// `.sh-edge` —— 顶边一道光：中间白、两侧青，外加一层向上的辉光
class _EdgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final Rect line = Rect.fromLTWH(0, 0, s.width, 1);
    canvas.drawRect(
      line,
      Paint()
        ..shader = ui.Gradient.linear(
          line.centerLeft,
          line.centerRight,
          <Color>[
            const Color(0x0038E1FF),
            C.blue,
            Colors.white,
            C.blue,
            const Color(0x0038E1FF),
          ],
          <double>[0, .3, .5, .7, 1],
        ),
    );
    // box-shadow: 0 0 18px var(--blue)
    canvas.drawRect(
      line,
      Paint()
        ..color = C.blue
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    // ::after —— 240×60 的辉光盒子，`top:-30` 让它**以边线为中心**（上下各 30）
    final Offset c = Offset(s.width / 2, 0);
    final double r = math.min(240, 60) / 2;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(240 / 60, 1);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(c, r, <Color>[
          C.blue.withAlpha(82), // rgba(56,225,255,.32)
          C.blue.withAlpha(0),
        ]),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
