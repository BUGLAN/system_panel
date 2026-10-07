import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../state/host_state.dart';
import '../state/quest.dart';

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
class Plate extends StatefulWidget {
  const Plate({
    super.key,
    required this.quest,
    required this.host,
    this.visible = true,
    this.animateLand = true,
    this.onAccept,
  });

  final Quest quest;
  final HostState host;
  final bool visible;

  /// 砸落动画（ui.js `land()`）；比对截图时也会自然落到终态
  final bool animateLand;

  /// 按住指纹 0.9s 才接单——按住逻辑是行为，先只留一个"点头"的入口
  final VoidCallback? onAccept;

  @override
  State<Plate> createState() => _PlateState();
}

class _PlateState extends State<Plate> with SingleTickerProviderStateMixin {
  // CSS cubic-bezier(.2,.75,.25,1)
  static const Curve _landCurve = Cubic(.2, .75, .25, 1);

  late final AnimationController _land = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animateLand) {
      _land.forward();
    } else {
      _land.value = 1;
    }
  }

  @override
  void dispose() {
    _land.dispose();
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
          final double inv = 1 - t;
          final Matrix4 m = Matrix4.identity()
            ..setEntry(3, 2, -1 / 900) // perspective: 900px
            ..translateByDouble(fromX * inv, fromY * inv, 0, 1)
            ..rotateX(55 * math.pi / 180 * inv)
            ..scaleByDouble(.16 + .84 * t, .16 + .84 * t, 1, 1);
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
        ),
      ),
    );
  }
}

class _Glass extends StatelessWidget {
  const _Glass({
    super.key,
    required this.quest,
    required this.host,
    this.onAccept,
  });

  final Quest quest;
  final HostState host;
  final VoidCallback? onAccept;

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
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 64),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 92),
                    child: Text(
                      quest.name,
                      style: fs(
                        family: F.hd,
                        size: 26,
                        wght: 400,
                        ls: .52,
                        height: 1.22,
                        color: const Color(0xFFF4FDFF),
                        shadows: <Shadow>[
                          Shadow(color: C.blue.withAlpha(89), blurRadius: 18),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _why(),
                const SizedBox(height: 14),
                _spec(),
                const Spacer(), // .pl-print 的 margin-top: auto
                _print(rk),
              ],
            ),
          ),
        ),
        // .pl-rank
        Positioned(
          right: 16,
          top: 34,
          width: 86,
          height: 104,
          child: _Rank(key: const Key('plate.rank'), quest: quest),
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
        Text(quest.serialText, style: base),
      ],
    );
  }

  /// .pl-why —— 带「附言」小牌的那句
  Widget _why() {
    if (quest.reason.isEmpty) return const SizedBox.shrink();
    return Text.rich(
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
    final TextStyle num = fs(
      family: F.num,
      size: 13,
      wght: 700,
      ls: .39,
      color: C.blue,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _specRow('证明', Text(quest.proof, style: dd), dt),
        const SizedBox(height: 7),
        _specRow('时限', Text(quest.minutesText, style: dd), dt),
        const SizedBox(height: 7),
        _specRow(
          '报酬',
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(text: 'EXP ${quest.rarity.exp}', style: num),
                TextSpan(text: ' · ◈ ${quest.rarity.coin}', style: dd),
                TextSpan(
                  text: quest.attrs.entries
                      .map((MapEntry<String, int> e) => '${e.key}+${e.value}')
                      .join(' '),
                  style: fs(
                    family: F.cn,
                    size: 12,
                    wght: 400,
                    color: const Color(0xFFCFE9FF),
                  ),
                ),
              ],
            ),
          ),
          dt,
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

  /// .pl-print —— 按住指纹那一块（按住 0.9s 才算接单，长短按是行为）
  Widget _print(Color rk) {
    return GestureDetector(
      onTap: onAccept,
      behavior: HitTestBehavior.opaque,
      child: Container(
        key: const Key('plate.print'),
        height: 108,
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0x2938E1FF), width: 1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const SizedBox(
              key: Key('plate.fp'),
              width: 62,
              height: 70,
              child: _Fingerprint(),
            ),
            const SizedBox(width: 16),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '按住 · 接下',
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
                  'HOLD TO ACCEPT',
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
  const _Rank({super.key, required this.quest});

  final Quest quest;

  @override
  Widget build(BuildContext context) {
    final Color rk = quest.rarity.color;
    final int i = quest.rarity.i;
    return Column(
      children: <Widget>[
        SizedBox(
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
                quest.rank,
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
        ),
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
  const _Fingerprint();

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
              child: CustomPaint(painter: const _FingerprintPainter()),
            ),
          ],
        );
      },
    );
  }
}

class _FingerprintPainter extends CustomPainter {
  const _FingerprintPainter();

  static const double _cx = 31;
  static const double _cy = 38;
  static const List<double> _radii = <double>[4, 8.5, 13, 17.5, 22, 26.5, 31];

  @override
  void paint(Canvas canvas, Size s) {
    final double k = s.width / 62;
    canvas.save();
    canvas.scale(k);
    final Path path = Path();
    for (int i = 0; i < _radii.length; i++) {
      final double r = _radii[i];
      final double a0 = (196 + i * 7) * math.pi / 180;
      final double a1 = (520 - i * 9) * math.pi / 180;
      final Rect rect = Rect.fromCenter(
        center: const Offset(_cx, _cy),
        width: 2 * r,
        height: 2 * r * 1.12,
      );
      path.arcTo(rect, a0, a1 - a0, true);
    }
    final Paint base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = C.blue.withAlpha(66); // rgba(56,225,255,.26)
    canvas.drawPath(path, base);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = C.blue
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = C.blue,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// #plateAlt —— 板子下面那两个「宿主 · …」按钮（app.css L299-303）
class PlateAlt extends StatelessWidget {
  const PlateAlt({super.key, required this.labels, this.visible = true});

  final List<String> labels;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 18,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 400),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (int i = 0; i < labels.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 10),
              Container(
                height: 36,
                // Border 占布局、CSS 的 inset 阴影不占 → padding 各减 1px
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xDB040C1C), // rgba(4,12,28,.86)
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0x4D8FA6C4),
                    width: 1,
                  ), // rgba(143,166,196,.3)
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
                        color: const Color(0xFFC3D2E6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
