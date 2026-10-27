import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/attrs.dart';
import '../../data/titles.dart';
import '../../design/ref.dart';
import '../../state/host_state.dart';
import 'ref_inputs.dart';
import 'ref_kit.dart';

/// ═══════════════════════════════════════════════════════════
///  档案 —— 参考稿 #sc-archive（CSS L330-384，DOM L767-787）
///
///  .sh（eyebrow + h1 档案 + .cnt 03/12 紫色斜体 + xbtn）
///  → .prof 四列小卡 → 雷达 300×270（5s 扫描）→ 名牒册（挂绳卡片 138×188）
///  → 数据·本周回顾（柱状图 + 2×2 小卡）→ 六维（40/1fr/26 三列）
///
///  ⚠️ nohud 场景（上边距 30）。列表区可滚，头固定。
/// ═══════════════════════════════════════════════════════════
class RefArchive extends StatelessWidget {
  const RefArchive({
    super.key,
    required this.host,
    required this.ownedCount,
    required this.totalTitles,
    required this.onBack,
    required this.onEquip,
  });

  final HostState host;

  /// 已解锁名牒数 / 总数（.cnt 与 .sec-h b 都读它）
  final int ownedCount;
  final int totalTitles;

  final VoidCallback? onBack;
  final ValueChanged<String>? onEquip;

  @override
  Widget build(BuildContext context) {
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    // ⚠️ 参考稿里档案/补给是**整页场景**（不是浮层）：正文从场景顶边开始。
    //    保留「屏高 46%」那种舞台让位的话，整页只剩半屏（真机截图）。
    final double top = safe.top + Ref.sceneTopNoHud;
    return Padding(
      padding: EdgeInsets.fromLTRB(Ref.gutter, top, Ref.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _head(),
          Expanded(
            child: ListView(
              key: const Key('ref.archive.scroll'),
              padding: EdgeInsets.only(top: 6, bottom: safe.bottom + 40),
              children: <Widget>[
                _prof(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Center(
                    child: SizedBox(
                      width: 340,
                      child: AspectRatio(
                        aspectRatio: 300 / 270,
                        child: CustomPaint(
                          painter: _RadarPainter(
                            attrs: host.attrs,
                            weakKey: host.weakest.key,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                RefSectionHeader(
                  title: '名牒册 · 点击佩戴',
                  trailing: '${_pad(ownedCount)}/${_pad(totalTitles)} 张',
                  accent: Ref.violet,
                ),
                _plates(),
                const RefSectionHeader(title: '数据 · 本周回顾'),
                _week(),
                const RefSectionHeader(title: '六维 · 当前数值'),
                _attrs(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// .sh（L63）+ .cnt（L331）
  Widget _head() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const RefEyebrow(text: 'ARCHIVE · 宿主档案', accent: Ref.violet),
              const SizedBox(height: 8),
              Text('档案', style: RefType.h1),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${_pad(ownedCount)} / ${_pad(totalTitles)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: refText(
                  family: Ref.fd,
                  size: 30,
                  wght: 700,
                  italic: true,
                  height: 1,
                  color: Ref.violet,
                  shadows: <Shadow>[Shadow(color: Ref.violet, blurRadius: 20)],
                ),
              ),
            ),
            const SizedBox(height: 6),
            RefXButton(onTap: onBack, accent: Ref.violet),
          ],
        ),
      ],
    );
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  /// .prof（L334-337）：四列、gap 8、每格 r14 + 22 数字 + 11 标签
  Widget _prof() {
    final List<(String, String)> items = <(String, String)>[
      ('LV ${host.lv}', '等级'),
      (host.streak.toString(), '连胜'),
      (host.doneCount.toString(), '完成'),
      (host.critCount.toString(), '暴击'),
    ];
    return Row(
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0x09FFFFFF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Ref.line),
              ),
              child: Column(
                children: <Widget>[
                  Text(
                    items[i].$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: refText(
                      family: Ref.fd,
                      size: 22,
                      wght: 700,
                      height: 1.1,
                      color: Ref.txt,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    items[i].$2,
                    style: refText(
                      family: Ref.fc,
                      size: 11,
                      wght: 500,
                      height: 1,
                      color: Ref.dim,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// .plates（L346-365）：横向滚动、每张 138×188 挂绳牌
  Widget _plates() {
    return SizedBox(
      height: 216,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        key: const Key('ref.archive.plates'),
        padding: const EdgeInsets.only(top: 4, bottom: 18),
        itemCount: HostTitle.all.length,
        separatorBuilder: (BuildContext context, int i) =>
            const SizedBox(width: 14),
        itemBuilder: (BuildContext context, int i) {
          final HostTitle t = HostTitle.all[i];
          final bool owned = host.ownedTitles.contains(t.id);
          final bool eq = host.title == t.id;
          return _Plate(
            index: i,
            title: t,
            owned: owned,
            equipped: eq,
            onTap: owned && onEquip != null ? () => onEquip!(t.id) : null,
          );
        },
      ),
    );
  }

  /// .weekc（L367-377）：柱状图 + 2×2 小卡
  Widget _week() {
    final List<int> days = <int>[
      for (int i = 6; i >= 0; i--)
        math.max(0, (host.doneCount - i).clamp(0, 9)),
    ];
    final int mx = days.fold<int>(1, math.max);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Ref.line),
      ),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (int i = 0; i < 7; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          days[i].toString(),
                          style: refText(
                            family: Ref.fd,
                            size: 11,
                            wght: 700,
                            height: 1,
                            color: Ref.txt,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: math.max(3, 74 * days[i] / mx),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: i == 6
                                  ? <Color>[Ref.acid, Ref.a(Ref.acid, .2)]
                                  : <Color>[Ref.violet, Ref.a(Ref.violet, .2)],
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                              bottom: Radius.circular(2),
                            ),
                            boxShadow: i == 6
                                ? <BoxShadow>[
                                    BoxShadow(
                                      color: Ref.a(Ref.acid, .35),
                                      blurRadius: 16,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          i == 6 ? '今天' : 'D-${6 - i}',
                          style: refText(
                            family: Ref.fc,
                            size: 11,
                            wght: 500,
                            height: 1,
                            color: Ref.dim,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(child: _stat(host.doneCount.toString(), '本周完成')),
              const SizedBox(width: 8),
              Expanded(child: _stat(host.bestStreak.toString(), '最长连胜')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(child: _stat(host.critCount.toString(), '暴击次数')),
              const SizedBox(width: 8),
              Expanded(child: _stat(host.failCount.toString(), '认输/超时')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String v, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            v,
            style: refText(
              family: Ref.fd,
              size: 20,
              wght: 700,
              height: 1,
              color: Ref.txt,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: refText(
              family: Ref.fc,
              size: 11,
              wght: 500,
              height: 1,
              color: Ref.dim,
            ),
          ),
        ],
      ),
    );
  }

  /// .attrs（L378-382）：40px 标签 / 1fr 条 / 26px 读数
  Widget _attrs() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Ref.line),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < Attr.all.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: 9),
            _attrRow(Attr.all[i]),
          ],
        ],
      ),
    );
  }

  Widget _attrRow(Attr a) {
    final int v = host.attrs[a.k] ?? 0;
    const int full = 50; // 与旧雷达同一刻度（线性 50 满值）
    return Row(
      children: <Widget>[
        SizedBox(
          width: 40,
          child: Text(
            a.name,
            style: refText(
              family: Ref.fc,
              size: 12,
              wght: 500,
              height: 1,
              color: Ref.dim,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: <Widget>[
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0x12FFFFFF)),
                  ),
                  FractionallySizedBox(
                    widthFactor: (v / full).clamp(0.0, 1.0),
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[Ref.violet, Ref.cyan],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 26,
          child: Text(
            v.toString(),
            textAlign: TextAlign.right,
            style: refText(
              family: Ref.fd,
              size: 13,
              wght: 700,
              height: 1,
              color: Ref.txt,
            ),
          ),
        ),
      ],
    );
  }
}

/// .pw（L348-365）名牒：12 挂孔 + 18 挂绳 + 138×188 牌
/// 牌面：repeating-linear-gradient(0deg, 3% 0 1px, transparent 1px 14px)
/// + 160 度渐变 + 1.5px 白 .1 描边；已拥有转紫、佩戴中转 acid + 26 辉光
class _Plate extends StatelessWidget {
  const _Plate({
    required this.index,
    required this.title,
    required this.owned,
    required this.equipped,
    this.onTap,
  });

  final int index;
  final HostTitle title;
  final bool owned;
  final bool equipped;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 138,
      child: Column(
        children: <Widget>[
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1B1830),
              border: Border.all(color: Ref.dim2, width: 2),
            ),
          ),
          Container(
            width: 2,
            height: 18,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Ref.dim2, Color(0x4DFFFFFF)],
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                width: 138,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: owned
                        ? const <Color>[Color(0xFF2B2152), Color(0xFF100D20)]
                        : const <Color>[Color(0xFF211C39), Color(0xFF0D0B18)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: equipped
                        ? Ref.acid
                        : (owned
                              ? Ref.a(Ref.violet, .5)
                              : const Color(0x1AFFFFFF)),
                    width: 1.5,
                  ),
                  boxShadow: equipped
                      ? <BoxShadow>[
                          BoxShadow(
                            color: Ref.a(Ref.acid, .35),
                            blurRadius: 26,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Ref.violet),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          _num(),
                          style: refText(
                            family: Ref.fm,
                            size: 11,
                            wght: 700,
                            height: 1,
                            color: Ref.violet,
                          ),
                        ),
                      ),
                    ),
                    if (!owned)
                      Expanded(
                        child: Center(
                          child: Text(
                            '?',
                            style: refText(
                              family: Ref.fd,
                              size: 46,
                              wght: 700,
                              height: 1,
                              color: Ref.dim2,
                            ),
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    Text(
                      owned ? title.name : '？？？',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: refText(
                        family: Ref.fc,
                        size: 19,
                        wght: 900,
                        height: 1.25,
                        color: owned ? Ref.txt : Ref.dim2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title.hint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: refText(
                        family: Ref.fc,
                        size: 11,
                        wght: 400,
                        height: 1.4,
                        color: Ref.dim,
                      ),
                    ),
                    Container(
                      height: 2,
                      margin: const EdgeInsets.only(top: 10),
                      decoration: BoxDecoration(
                        color: owned ? null : const Color(0x1FFFFFFF),
                        gradient: owned
                            ? const LinearGradient(
                                colors: <Color>[Ref.violet, Ref.cyan],
                              )
                            : null,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        Text(
                          owned ? '已解锁' : '未解锁',
                          style: refText(
                            family: Ref.fc,
                            size: 11,
                            wght: 500,
                            height: 1,
                            color: equipped ? Ref.acid : Ref.dim,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          equipped ? '佩戴中' : '',
                          style: refText(
                            family: Ref.fc,
                            size: 11,
                            wght: 500,
                            height: 1,
                            color: Ref.acid,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _num() => (index + 1).toString().padLeft(2, '0');
}

/// .radar（L338-342）：viewBox 300×270、半径 92、圆心 (150,135)、
/// 5 圈（奇圈填充）、六轴、多边形、sweep 5s 扫描扇形
class _RadarPainter extends CustomPainter {
  const _RadarPainter({required this.attrs, this.weakKey});

  final Map<String, int> attrs;
  final String? weakKey;

  static const double _cx = 150, _cy = 135, _r = 92;

  double _rad(int v) => v <= 0 ? 0 : _r * math.pow(v / 50, .56).toDouble();

  @override
  void paint(Canvas canvas, Size s) {
    if (s.isEmpty) return;
    final double k = math.min(s.width / 300, s.height / 270);
    canvas.save();
    canvas.translate((s.width - 300 * k) / 2, (s.height - 270 * k) / 2);
    canvas.scale(k);

    final List<String> ks = Attr.all.map((Attr a) => a.k).toList();
    Offset pt(int i, double r) {
      final double a = -math.pi / 2 + i * math.pi / 3;
      return Offset(_cx + r * math.cos(a), _cy + r * math.sin(a));
    }

    Path poly(double r) {
      final Path p = Path();
      for (int i = 0; i < 6; i++) {
        final Offset o = pt(i, r);
        if (i == 0) {
          p.moveTo(o.dx, o.dy);
        } else {
          p.lineTo(o.dx, o.dy);
        }
      }
      return p..close();
    }

    for (int ring = 5; ring >= 1; ring--) {
      final double r = _r * ring / 5;
      if (ring.isOdd) {
        canvas.drawPath(poly(r), Paint()..color = const Color(0x0B8F6BFF));
      }
      canvas.drawPath(
        poly(r),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring == 5 ? 1.6 : 1
          ..color = ring == 5
              ? const Color(0x578F6BFF)
              : const Color(0x248F6BFF),
      );
    }
    for (int i = 0; i < 6; i++) {
      canvas.drawLine(
        const Offset(_cx, _cy),
        pt(i, _r),
        Paint()
          ..strokeWidth = 1
          ..color = const Color(0x248F6BFF),
      );
    }
    final List<Offset> vals = <Offset>[
      for (int i = 0; i < 6; i++) pt(i, _rad(attrs[ks[i]] ?? 0)),
    ];
    final Path shape = Path()..moveTo(vals[0].dx, vals[0].dy);
    for (int i = 1; i < 6; i++) {
      shape.lineTo(vals[i].dx, vals[i].dy);
    }
    shape.close();
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = Ref.a(Ref.violet, .35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(shape, Paint()..color = const Color(0x298F6BFF));
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Ref.violet,
    );
    for (int i = 0; i < 6; i++) {
      canvas.drawCircle(vals[i], 2.4, Paint()..color = Colors.white);
      final Offset lp = pt(i, _r + 22);
      _text(
        canvas,
        Attr.nameOf(ks[i]),
        Offset(lp.dx, lp.dy - 8),
        refText(
          family: Ref.fc,
          size: 13,
          wght: 500,
          height: 1,
          color: ks[i] == weakKey ? Ref.dim : Ref.txt,
        ),
      );
      _text(
        canvas,
        (attrs[ks[i]] ?? 0).toString(),
        Offset(lp.dx, lp.dy + 10),
        refText(
          family: Ref.fd,
          size: 15,
          wght: 700,
          height: 1,
          color: Ref.violet,
        ),
      );
    }
    canvas.restore();
  }

  void _text(Canvas canvas, String t, Offset center, TextStyle style) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: t, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_RadarPainter o) =>
      o.attrs != attrs || o.weakKey != weakKey;
}
