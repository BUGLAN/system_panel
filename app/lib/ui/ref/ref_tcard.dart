import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../design/ref.dart';

/// ═══════════════════════════════════════════════════════════
///  主线收藏卡 v2 —— 参考稿「MAINLINE · COLLECTIBLE CARDS v2」
///  （CSS L517-663，DOM 由 JS `mainCard()` L1287-1315 生成）
///
///   正面 .tc-front：.tc-frame（2px 渐变框 + 内框 + 四角括号）
///     → .tc-head（MAIN 06 /10 · 稀有度菱形 · 类别菱形）
///     → .tc-art（插画窗：网格 + 扫描带 + 水印档位字 + kind / big 标签 + SVG）
///     → .tc-mid（−30 上叠：六边奖章 + meta 胶囊）
///     → .tc-t（900 18/1.38 两行）→ .tc-stats（三格）→ .tc-foot（40 高 CTA）
///     + .stamp（已完成压印）+ .tc-holo（镭射箔）+ .tc-glare（高光）
///   背面：.cb（封印：旋转纹章 + 情报）或 .tcrec（战报：评级 + 三行 + 批注）
///   翻转：.tc rotateY(180°)，.8s cubic(.3,1.3,.4,1)
/// ═══════════════════════════════════════════════════════════
enum RefTCardState { done, cur, lock }

/// 插画种类（JS `tcArt` 的 kind）
enum RefArtKind { clock, route, hill, cup, boss }

class RefTCardData {
  const RefTCardData({
    required this.index,
    required this.total,
    required this.rank,
    required this.cat,
    required this.catName,
    required this.title,
    required this.minutes,
    required this.proof,
    required this.exp,
    required this.coin,
    this.prefix = 'MAIN',
    this.boss = false,
    this.bike = false,
  });

  final String prefix;
  final int index;
  final int total;
  final String rank;

  /// 类别单字（菱形里那个）
  final String cat;

  /// 类别全名（stats 第三格 / 情报行）
  final String catName;
  final String title;
  final int minutes;
  final String proof;
  final int exp;
  final int coin;
  final bool boss;

  /// 画单车（骑行类目标）；否则画系统之眼
  final bool bike;

  Color get gc => boss ? Ref.gold : Ref.rankOf(rank);

  int get pips => boss ? 5 : (Ref.rankPips[rank] ?? 1);

  /// JS：`/(\d+)\s*公里/` → route；`/坡/` → hill；`/咖啡/` → cup；boss
  RefArtKind get kind {
    if (boss) return RefArtKind.boss;
    if (RegExp(r'坡|爬山|爬楼').hasMatch(title)) return RefArtKind.hill;
    if (km != null) return RefArtKind.route;
    if (RegExp(r'咖啡|买|采购|取').hasMatch(title)) return RefArtKind.cup;
    return RefArtKind.clock;
  }

  String? get km {
    final RegExpMatch? m = RegExp(
      r'(\d+(?:\.\d+)?)\s*(?:公里|km|KM|千米)',
    ).firstMatch(title);
    return m?.group(1);
  }
}

/// 战报（JS `recOf`）
class RefTCardRecord {
  const RefTCardRecord({
    required this.rank,
    required this.time,
    required this.exp,
    required this.coin,
    required this.day,
    this.crit = false,
    this.quote = '',
  });

  final String rank;
  final Duration time;
  final int exp;
  final int coin;
  final int day;
  final bool crit;
  final String quote;
}

String _pad2(int n) => n.toString().padLeft(2, '0');
String _mmss(Duration d) =>
    '${_pad2(d.inMinutes)}:${_pad2(d.inSeconds.remainder(60))}';

/// 参考稿 `REC_Q`（L1265）：战报批注
const Map<String, List<String>> kRecQuotes = <String, List<String>>{
  'S': <String>['……我无话可说。这次算你狠。', '暴击收场。别得意，我只是记下了。'],
  'A': <String>['达标。我记下了，别指望我夸你。', '节奏稳定。勉强像个宿主了。'],
  'B': <String>['及格线上蹭过去的。我看见了。', '下次别让我等这么久。'],
  'C': <String>['到此一游式完成。我很宽容。', '这也算？……算吧。'],
};

/// 评级色（verdict `--rc`：S 白 / A acid / B cyan / C hot；战报用 GC）
Color refRecColor(String r) => Ref.rankOf(r);

class RefTCard extends StatefulWidget {
  const RefTCard({
    super.key,
    required this.data,
    required this.state,
    this.active = false,
    this.flipped = false,
    this.focus = false,
    this.compact = false,
    this.shade = 0,
    this.record,
    this.stamp,
  });

  /// 压印进度（justDone 演出：0 → 1 = scale 3.4 → 1 砸下）；null = 静态
  final Animation<double>? stamp;

  final RefTCardData data;
  final RefTCardState state;

  /// 当前单正在执行（foot 文案换成「执行中 · 点击返回」）
  final bool active;

  /// 已完成卡被点开看战报
  final bool flipped;
  final bool focus;
  final bool compact;

  /// 卡面压暗（`--sh`）
  final double shade;
  final RefTCardRecord? record;

  /// 封印态（.fd）：锁着的卡默认背面朝上
  bool get sealed => state == RefTCardState.lock;

  @override
  State<RefTCard> createState() => _RefTCardState();
}

class _RefTCardState extends State<RefTCard> with TickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
    value: _showBack ? 1 : 0,
  );

  /// 卡面常驻动效的时钟（秒）—— 只有焦点卡在走，其余定格（参考稿
  /// `animation-play-state: paused`），十张卡不会一起重画。
  final ValueNotifier<double> _t = ValueNotifier<double>(0);
  Timer? _tTimer;
  double _t0 = 0;
  double _tAccum = 0;

  bool get _showBack => widget.sealed || widget.flipped;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(RefTCard old) {
    super.didUpdateWidget(old);
    final bool wasBack = old.sealed || old.flipped;
    if (_showBack != wasBack) {
      if (_showBack) {
        _flip.animateTo(1, curve: Ref.flip);
      } else {
        _flip.animateTo(0, curve: Ref.flip);
      }
    }
    _syncTicker();
  }

  void _syncTicker() {
    final bool reduce = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    final bool want = widget.focus && !reduce;
    if (want && _tTimer == null) {
      _t0 = _t.value;
      _tAccum = 0;
      _tTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        _tAccum += .05;
        _t.value = _t0 + _tAccum;
      });
    } else if (!want && _tTimer != null) {
      _tTimer?.cancel();
      _tTimer = null;
    }
  }

  @override
  void dispose() {
    _tTimer?.cancel();
    _flip.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget front = _Face(
      data: widget.data,
      state: widget.state,
      focus: widget.focus,
      shade: widget.shade,
      boss: widget.data.boss,
      child: _FrontBody(
        data: widget.data,
        state: widget.state,
        active: widget.active,
        compact: widget.compact,
        focus: widget.focus,
        record: widget.record,
        t: _t,
        stamp: widget.stamp,
      ),
      t: _t,
      holo: widget.state == RefTCardState.done || widget.data.boss,
      animFrame: widget.state == RefTCardState.cur,
    );
    final Widget back = _Face(
      data: widget.data,
      state: widget.state,
      focus: widget.focus,
      shade: widget.shade,
      boss: false,
      recordBg: widget.state == RefTCardState.done
          ? refRecColor(widget.record?.rank ?? 'A')
          : null,
      t: _t,
      holo: widget.state != RefTCardState.done,
      animFrame: false,
      child: widget.state == RefTCardState.done
          ? _RecordBack(
              data: widget.data,
              record: widget.record,
              compact: widget.compact,
            )
          : _SealedBack(data: widget.data, compact: widget.compact, t: _t),
    );
    return AnimatedBuilder(
      animation: _flip,
      builder: (BuildContext context, Widget? _) {
        final double v = _flip.value; // 可能过冲到 >1
        final double ang = v * math.pi;
        final bool backUp =
            (ang % (2 * math.pi)) > math.pi / 2 &&
            (ang % (2 * math.pi)) < 3 * math.pi / 2;
        final Matrix4 m = Matrix4.identity()
          ..setEntry(3, 2, -1 / 1100)
          ..rotateY(ang);
        return Transform(
          alignment: Alignment.center,
          transform: m,
          child: backUp
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: back,
                )
              : front,
        );
      },
    );
  }
}

/// .tc-face：20 圆角、165° 三段渐变、投影；外加框 / 箔 / 高光 / 压暗
class _Face extends StatelessWidget {
  const _Face({
    required this.data,
    required this.state,
    required this.focus,
    required this.shade,
    required this.boss,
    required this.child,
    required this.t,
    required this.holo,
    required this.animFrame,
    this.recordBg,
  });

  final RefTCardData data;
  final RefTCardState state;
  final bool focus;
  final double shade;
  final bool boss;
  final Widget child;
  final ValueNotifier<double> t;
  final bool holo;
  final bool animFrame;
  final Color? recordBg;

  @override
  Widget build(BuildContext context) {
    final Color gc = data.gc;
    final BorderRadius r = BorderRadius.circular(20);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(focus ? 0xF2000000 : 0xE6000000),
            offset: Offset(0, focus ? 40 : 34),
            blurRadius: focus ? 70 : 60,
            spreadRadius: focus ? -16 : -18,
          ),
          if (focus)
            BoxShadow(color: Ref.a(gc, .55), blurRadius: 70, spreadRadius: -12),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // 底：正面 165° #1f1a3a → #110f21 → #09080f；boss 160° 金褐
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: boss
                    ? refCssLinear(
                        160,
                        const <Color>[
                          Color(0xFF3D2C10),
                          Color(0xFF1B1322),
                          Color(0xFF0B0A15),
                        ],
                        const <double>[0, .5, 1],
                      )
                    : refCssLinear(
                        165,
                        const <Color>[
                          Color(0xFF1F1A3A),
                          Color(0xFF110F21),
                          Color(0xFF09080F),
                        ],
                        const <double>[0, .55, 1],
                      ),
              ),
            ),
            if (recordBg != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: refCssLinear(
                    165,
                    const <Color>[Color(0xFF1D1838), Color(0xFF0A0914)],
                    const <double>[0, 1],
                  ),
                ),
              ),
            if (recordBg != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -.4),
                    radius: .75,
                    colors: <Color>[Ref.a(recordBg!, .2), Ref.a(recordBg!, 0)],
                    stops: const <double>[0, .7],
                  ),
                ),
              ),
            // 顶边 1px 内高光（inset 0 1px 0 rgba(255,255,255,.12)）
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 1,
              child: ColoredBox(color: Color(0x1FFFFFFF)),
            ),
            child,
            if (holo)
              IgnorePointer(
                child: CustomPaint(
                  painter: _HoloPainter(t: t, opacity: focus ? .5 : .22),
                ),
              ),
            if (focus)
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(-.4, -1),
                      radius: .9,
                      colors: <Color>[Color(0x33FFFFFF), Color(0x00FFFFFF)],
                      stops: <double>[0, .46],
                    ),
                  ),
                ),
              ),
            IgnorePointer(
              child: CustomPaint(
                painter: _FramePainter(gc: gc, t: t, conic: animFrame),
              ),
            ),
            if (shade > .001)
              IgnorePointer(
                child: ColoredBox(
                  color: Color(0xFF05040A).withValues(alpha: shade.clamp(0, 1)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// CSS `linear-gradient(<deg>, …)` 的近似：方向向量 (sinθ, −cosθ)
LinearGradient refCssLinear(
  double deg,
  List<Color> colors,
  List<double> stops,
) {
  final double a = deg * math.pi / 180;
  final double dx = math.sin(a);
  final double dy = -math.cos(a);
  final double k = 1 / math.max(dx.abs(), dy.abs());
  return LinearGradient(
    begin: Alignment(-dx * k, -dy * k),
    end: Alignment(dx * k, dy * k),
    colors: colors,
    stops: stops,
  );
}

/// .tc-frame（L533-542）：2px 渐变框（cur 为旋转锥形）+ 6px 内框 + 四角
class _FramePainter extends CustomPainter {
  _FramePainter({required this.gc, required this.t, required this.conic})
    : super(repaint: conic ? t : null);

  final Color gc;
  final ValueNotifier<double> t;
  final bool conic;

  @override
  void paint(Canvas canvas, Size s) {
    final Rect rect = Offset.zero & s;
    final RRect outer = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(20),
    );
    final RRect inner = outer.deflate(2);
    final Paint p = Paint();
    if (conic) {
      final double ang = (t.value / 3.2) * 2 * math.pi;
      p.shader = SweepGradient(
        colors: <Color>[gc, Ref.a(gc, 0), Ref.acid, Ref.a(Ref.acid, 0), gc],
        stops: const <double>[0, .22, .45, .70, 1],
        transform: GradientRotation(ang - math.pi / 2),
      ).createShader(rect);
    } else {
      p.shader = refCssLinear(
        150,
        <Color>[gc, Ref.a(gc, .18), Ref.a(gc, 0), Ref.a(gc, .22), gc],
        const <double>[0, .30, .50, .72, 1],
      ).createShader(rect);
    }
    canvas.drawDRRect(outer, inner, p);
    // ::after 内框
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(6), const Radius.circular(15)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Ref.a(gc, .2),
    );
    // 四角括号 16×16 / 2px / 外角圆 8 / drop-shadow 4
    final Paint glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = gc
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final Paint line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = gc;
    for (int i = 0; i < 4; i++) {
      final bool right = i.isOdd;
      final bool bottom = i >= 2;
      final double x0 = right ? s.width - 4 - 1 : 4 + 1;
      final double y0 = bottom ? s.height - 4 - 1 : 4 + 1;
      final double sx = right ? -1 : 1;
      final double sy = bottom ? -1 : 1;
      final Path path = Path()
        ..moveTo(x0, y0 + sy * 15)
        ..lineTo(x0, y0 + sy * 7)
        ..arcToPoint(
          Offset(x0 + sx * 7, y0),
          radius: const Radius.circular(7),
          clockwise: (sx * sy) > 0,
        )
        ..lineTo(x0 + sx * 15, y0);
      canvas.drawPath(path, glow);
      canvas.drawPath(path, line);
    }
  }

  @override
  bool shouldRepaint(_FramePainter o) => o.gc != gc || o.conic != conic;
}

/// .tc-holo（L592-598）：color-dodge 彩虹箔 + 两层闪点
class _HoloPainter extends CustomPainter {
  _HoloPainter({required this.t, required this.opacity}) : super(repaint: t);

  final ValueNotifier<double> t;
  final double opacity;

  @override
  void paint(Canvas canvas, Size s) {
    // 参考稿用 color-dodge：在深色卡面上只把亮部提一点点。Impeller 在
    // 模拟器上跑 colorDodge 会卡死光栅线程，这里换成 plus（加色）并把强度
    // 压到 ~30%，深底上的观感与 dodge 等价。
    final double opacity = this.opacity * .3;
    final double sec = t.value;
    // 5s alternate：0% 30% ↔ 100% 70%
    final double ph = (sec / 5) % 2;
    final double k = Curves.easeInOut.transform(ph <= 1 ? ph : 2 - ph);
    // background-size 260%：把 2.6 倍大的渐变平移
    final double bw = s.width * 2.6;
    final double bh = s.height * 2.6;
    final double ox = -(bw - s.width) * k;
    final double oy = -(bh - s.height) * (.3 + .4 * k);
    final Rect big = Rect.fromLTWH(ox, oy, bw, bh);
    final Paint p = Paint()
      ..blendMode = BlendMode.plus
      ..shader = refCssLinear(
        115,
        <Color>[
          const Color(0x00000000),
          Ref.a(Ref.hot, .55 * opacity),
          Ref.a(Ref.gold, .5 * opacity),
          Ref.a(Ref.mint, .5 * opacity),
          Ref.a(Ref.cyan, .55 * opacity),
          Ref.a(Ref.violet, .55 * opacity),
          const Color(0x00000000),
        ],
        const <double>[.18, .30, .38, .46, .54, .62, .74],
      ).createShader(big);
    canvas.drawRect(Offset.zero & s, p);
    // 闪点（steps(4) 2.4s：.55 ↔ .15）
    final int step = ((sec / 2.4) * 4).floor() % 4;
    final double sa = (step < 2 ? .55 : .15) * opacity;
    final Paint dot = Paint()..blendMode = BlendMode.plus;
    dot.color = Colors.white.withValues(alpha: .9 * sa);
    for (double y = 5; y < s.height; y += 29) {
      for (double x = 3; x < s.width; x += 23) {
        canvas.drawCircle(Offset(x, y), 1, dot);
      }
    }
    dot.color = Colors.white.withValues(alpha: .6 * sa);
    for (double y = 2; y < s.height; y += 13) {
      for (double x = 9; x < s.width; x += 17) {
        canvas.drawCircle(Offset(x, y), .8, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_HoloPainter o) => o.opacity != opacity;
}

// ─────────────────────────────────────────────────────────────
//  正面
// ─────────────────────────────────────────────────────────────
class _FrontBody extends StatelessWidget {
  const _FrontBody({
    required this.data,
    required this.state,
    required this.active,
    required this.compact,
    required this.focus,
    required this.record,
    required this.t,
    this.stamp,
  });

  final Animation<double>? stamp;
  final RefTCardData data;
  final RefTCardState state;
  final bool active;
  final bool compact;
  final bool focus;
  final RefTCardRecord? record;
  final ValueNotifier<double> t;

  @override
  Widget build(BuildContext context) {
    final Color gc = data.gc;
    final double medalH = compact ? 50 : 68;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _head(gc),
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned(
                    left: compact ? 8 : 10,
                    right: compact ? 8 : 10,
                    top: compact ? 8 : 12,
                    bottom: medalH - (compact ? 20 : 30),
                    child: _ArtWindow(
                      data: data,
                      compact: compact,
                      focus: focus,
                      t: t,
                    ),
                  ),
                  Positioned(
                    left: compact ? 10 : 14,
                    right: compact ? 10 : 14,
                    bottom: 0,
                    child: _mid(gc),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 12 : 16,
                compact ? 7 : 10,
                compact ? 12 : 16,
                0,
              ),
              child: Text(
                data.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: refText(
                  size: compact ? 15 : 18,
                  wght: 900,
                  height: 1.38,
                  color: Ref.txt,
                ),
              ),
            ),
            _stats(),
            _foot(gc),
          ],
        ),
        if (data.boss)
          Positioned(
            top: 58,
            right: -34,
            child: Transform.rotate(
              angle: 38 * math.pi / 180,
              child: Container(
                color: Ref.gold,
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 4,
                ),
                child: Text(
                  'BOSS',
                  style: refText(
                    family: Ref.fm,
                    size: 11,
                    wght: 700,
                    ls: 4,
                    height: 1.2,
                    color: const Color(0xFF140F00),
                  ),
                ),
              ),
            ),
          ),
        if (state == RefTCardState.done)
          Positioned(
            top: 0,
            bottom: 0,
            right: 12,
            child: Align(
              alignment: const Alignment(0, -.48), // top: 26%
              child: stamp == null
                  ? RefStamp(scale: compact ? .8 : 1)
                  : AnimatedBuilder(
                      animation: stamp!,
                      builder: (BuildContext _, Widget? _) {
                        final double k = stamp!.value;
                        if (k <= 0) return const SizedBox.shrink();
                        return Opacity(
                          opacity: k.clamp(0.0, 1.0),
                          child: RefStamp(
                            scale: (compact ? .8 : 1) * (3.4 - 2.4 * k),
                          ),
                        );
                      },
                    ),
            ),
          ),
      ],
    );
  }

  Widget _head(Color gc) {
    final Color hc = Ref.mix(gc, Colors.white, .25);
    final TextStyle mono = refText(
      family: Ref.fm,
      size: compact ? 9 : 10,
      wght: 700,
      ls: 3,
      height: 1,
      color: hc,
    );
    final double pip = compact ? 6 : 7;
    final double cat = compact ? 22 : 26;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 13 : 16,
        compact ? 10 : 14,
        compact ? 13 : 16,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Text(data.prefix, style: mono),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              _pad2(data.index + 1),
              style: refText(
                family: Ref.fd,
                size: compact ? 17 : 21,
                wght: 700,
                italic: true,
                height: 1,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '/${data.total}',
            style: mono.copyWith(letterSpacing: 1, color: Ref.a(hc, .45)),
          ),
          const Spacer(),
          for (int k = 0; k < 5; k++) ...<Widget>[
            if (k > 0) const SizedBox(width: 4),
            Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: pip,
                height: pip,
                decoration: BoxDecoration(
                  color: k < data.pips ? gc : const Color(0x21FFFFFF),
                  boxShadow: k < data.pips
                      ? <BoxShadow>[BoxShadow(color: gc, blurRadius: 6)]
                      : null,
                ),
              ),
            ),
          ],
          const SizedBox(width: 8 + 4),
          RefCatDiamond(char: data.cat, color: gc, size: cat),
        ],
      ),
    );
  }

  Widget _mid(Color gc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        RefHexMedal(
          rank: data.boss ? (data.rank) : data.rank,
          color: gc,
          compact: compact,
        ),
        SizedBox(width: compact ? 8 : 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              children: <Widget>[
                _chip('⏱', '${data.minutes} 分钟', gc),
                _chip('EV', data.proof, gc),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String icon, String text, Color gc) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: const Color(0xBF080710),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            icon,
            style: refText(
              family: Ref.fd,
              size: 10,
              wght: 700,
              height: 1.2,
              color: gc,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: refText(
                size: compact ? 10 : 11,
                wght: 500,
                height: 1.2,
                color: Ref.txt,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stats() {
    Widget cell(String label, String v, Color c, {bool first = false}) {
      return Expanded(
        child: Container(
          padding: EdgeInsets.only(
            top: compact ? 3 : 6,
            bottom: compact ? 3 : 5,
          ),
          decoration: first
              ? null
              : const BoxDecoration(
                  border: Border(left: BorderSide(color: Color(0x12FFFFFF))),
                ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: refText(
                  size: compact ? 8 : 9,
                  wght: 500,
                  ls: 1,
                  height: 1.2,
                  color: Ref.dim,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                v,
                style: refText(
                  family: Ref.fd,
                  size: compact ? 13 : 16,
                  wght: 700,
                  height: 1.15,
                  color: c,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: EdgeInsets.fromLTRB(
        compact ? 9 : 12,
        compact ? 7 : 11,
        compact ? 9 : 12,
        0,
      ),
      decoration: BoxDecoration(
        color: const Color(0x09FFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x12FFFFFF)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            cell('经验 EXP', '+${data.exp}', Ref.acid, first: true),
            cell('晶核 ◆', '${data.coin}', Ref.cyan),
            cell(data.catName, '+1', Ref.mint),
          ],
        ),
      ),
    );
  }

  Widget _foot(Color gc) {
    final double h = compact ? 32 : 40;
    final EdgeInsets m = EdgeInsets.fromLTRB(
      compact ? 9 : 12,
      compact ? 7 : 10,
      compact ? 9 : 12,
      compact ? 9 : 12,
    );
    switch (state) {
      case RefTCardState.cur:
        return Padding(
          padding: m,
          child: SizedBox(
            height: h,
            child: ClipPath(
              clipper: const RefChamferClipper(10),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  const ColoredBox(color: Ref.acid),
                  IgnorePointer(
                    child: CustomPaint(painter: _FootSheenPainter(t: t)),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      CustomPaint(
                        size: const Size(8, 12),
                        painter: _TriPainter(Ref.onAccent),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        active ? '执行中 · 点击返回' : '当前目标 · 点击接取',
                        style: refText(
                          size: compact ? 11 : 13,
                          wght: 900,
                          ls: 2,
                          height: 1.2,
                          color: Ref.onAccent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      case RefTCardState.done:
        final String r = record?.rank ?? 'A';
        final Color rc = refRecColor(r);
        return Padding(
          padding: m,
          child: CustomPaint(
            painter: RefDashedRRectPainter(color: Ref.a(gc, .45), radius: 10),
            child: SizedBox(
              height: h,
              child: Center(
                child: Text.rich(
                  TextSpan(
                    style: refText(
                      size: compact ? 10 : 11,
                      wght: 500,
                      ls: 1,
                      height: 1.2,
                      color: Ref.dim,
                    ),
                    children: <InlineSpan>[
                      const TextSpan(text: '评级 '),
                      TextSpan(
                        text: r,
                        style: refText(
                          family: Ref.fd,
                          size: 15,
                          wght: 700,
                          italic: true,
                          height: 1,
                          color: rc,
                          shadows: <Shadow>[Shadow(color: rc, blurRadius: 10)],
                        ),
                      ),
                      const TextSpan(text: ' · 点击翻看战报 ⟲'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      case RefTCardState.lock:
        return Padding(
          padding: m,
          child: Container(
            height: h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x1AFFFFFF)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const RefLockIcon(size: 15, color: Ref.dim),
                const SizedBox(width: 8),
                Text(
                  '完成上一单解锁',
                  style: refText(
                    size: 12,
                    wght: 500,
                    ls: 1,
                    height: 1.2,
                    color: Ref.dim,
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }
}

/// .tc-foot::after（cur）：105° 白光扫过，2.2s ease-in-out，60%~100% 停
class _FootSheenPainter extends CustomPainter {
  _FootSheenPainter({required this.t}) : super(repaint: t);
  final ValueNotifier<double> t;

  @override
  void paint(Canvas canvas, Size s) {
    final double ph = (t.value % 2.2) / 2.2;
    final double k = ph >= .6 ? 1 : Curves.easeInOut.transform(ph / .6);
    // background-position 150% → −60%，size 250%
    final double bw = s.width * 2.5;
    final double pos = 1.5 + (-.6 - 1.5) * k;
    final double ox = (s.width - bw) * pos;
    final Rect big = Rect.fromLTWH(ox, 0, bw, s.height);
    canvas.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = refCssLinear(
          105,
          const <Color>[
            Color(0x00FFFFFF),
            Color(0xB3FFFFFF),
            Color(0x00FFFFFF),
          ],
          const <double>[.35, .5, .65],
        ).createShader(big),
    );
  }

  @override
  bool shouldRepaint(_FootSheenPainter o) => false;
}

class _TriPainter extends CustomPainter {
  const _TriPainter(this.c);
  final Color c;
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(s.width, s.height / 2)
        ..lineTo(0, s.height)
        ..close(),
      Paint()..color = c,
    );
  }

  @override
  bool shouldRepaint(_TriPainter o) => o.c != c;
}

/// clip-path: polygon(c 0,100% 0,100% calc(100% − c),calc(100% − c) 100%,0 100%,0 c)
class RefChamferClipper extends CustomClipper<Path> {
  const RefChamferClipper(this.c);
  final double c;
  @override
  Path getClip(Size s) => Path()
    ..moveTo(c, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width, s.height - c)
    ..lineTo(s.width - c, s.height)
    ..lineTo(0, s.height)
    ..lineTo(0, c)
    ..close();
  @override
  bool shouldReclip(RefChamferClipper o) => o.c != c;
}

/// 虚线圆角框（CSS `border: 1px dashed`）
class RefDashedRRectPainter extends CustomPainter {
  const RefDashedRRectPainter({
    required this.color,
    this.radius = 10,
    this.width = 1,
    this.dash = 4,
    this.gap = 3,
  });
  final Color color;
  final double radius;
  final double width;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size s) {
    final Path src = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & s).deflate(width / 2),
          Radius.circular(radius),
        ),
      );
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    for (final ui.PathMetric m in src.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), p);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(RefDashedRRectPainter o) =>
      o.color != color || o.radius != radius;
}

/// .tc-cat：26 菱形描边 + 900 13 单字
class RefCatDiamond extends StatelessWidget {
  const RefCatDiamond({
    super.key,
    required this.char,
    required this.color,
    this.size = 26,
  });
  final String char;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: math.pi / 4,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Transform.rotate(
          angle: -math.pi / 4,
          child: Text(
            char,
            style: refText(size: size * .5, wght: 900, height: 1, color: color),
          ),
        ),
      ),
    );
  }
}

/// .tc-medal（L570-572）：60×68 六边奖章（外渐变 + 内深底 + italic 档位字）
class RefHexMedal extends StatelessWidget {
  const RefHexMedal({
    super.key,
    required this.rank,
    required this.color,
    this.compact = false,
  });
  final String rank;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double w = compact ? 44 : 60;
    final double h = compact ? 50 : 68;
    return SizedBox(
      width: w,
      height: h,
      child: CustomPaint(
        painter: _HexMedalPainter(color),
        child: Center(
          child: Text(
            rank,
            style: refText(
              family: Ref.fd,
              size: compact ? 24 : 34,
              wght: 700,
              italic: true,
              height: 1,
              color: color,
              shadows: <Shadow>[Shadow(color: color, blurRadius: 14)],
            ),
          ),
        ),
      ),
    );
  }
}

Path _hex(Rect r) => Path()
  ..moveTo(r.center.dx, r.top)
  ..lineTo(r.right, r.top + r.height * .25)
  ..lineTo(r.right, r.top + r.height * .75)
  ..lineTo(r.center.dx, r.bottom)
  ..lineTo(r.left, r.top + r.height * .75)
  ..lineTo(r.left, r.top + r.height * .25)
  ..close();

class _HexMedalPainter extends CustomPainter {
  const _HexMedalPainter(this.c);
  final Color c;

  @override
  void paint(Canvas canvas, Size s) {
    final Rect o = Offset.zero & s;
    final Path outer = _hex(o);
    // filter: drop-shadow(0 0 12px gc80%) drop-shadow(0 6px 10px #0009)
    canvas.drawPath(
      outer.shift(const Offset(0, 6)),
      Paint()
        ..color = const Color(0x99000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(
      outer,
      Paint()
        ..color = Ref.a(c, .8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      outer,
      Paint()
        ..shader = refCssLinear(
          160,
          <Color>[Colors.white, c, Ref.mix(c, Colors.black, .6)],
          const <double>[-.2, .35, 1],
        ).createShader(o),
    );
    final double iw = s.width * 50 / 60;
    final double ih = s.height * 57 / 68;
    final Rect ir = Rect.fromCenter(center: o.center, width: iw, height: ih);
    canvas.drawPath(
      _hex(ir),
      Paint()
        ..shader = refCssLinear(
          170,
          const <Color>[Color(0xFF1C1834), Color(0xFF0A0914)],
          const <double>[0, 1],
        ).createShader(ir),
    );
  }

  @override
  bool shouldRepaint(_HexMedalPainter o) => o.c != c;
}

/// .stamp（L206-207）：3px 双线 hot 压印「已完成 / CLEAR」，−14°
class RefStamp extends StatelessWidget {
  const RefStamp({
    super.key,
    this.text = '已完成',
    this.sub = 'CLEAR',
    this.color = Ref.hot,
    this.scale = 1,
  });
  final String text;
  final String sub;
  final Color color;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -14 * math.pi / 180,
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: .92,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Ref.a(color, .06),
              borderRadius: BorderRadius.circular(8),
              boxShadow: <BoxShadow>[
                BoxShadow(color: Ref.a(color, .3), blurRadius: 18),
              ],
            ),
            foregroundDecoration: _DoubleBorder(color),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  text,
                  style: refText(
                    size: 18,
                    wght: 900,
                    ls: 3,
                    height: 1.2,
                    color: color,
                    shadows: <Shadow>[
                      Shadow(color: Ref.a(color, .6), blurRadius: 10),
                    ],
                  ),
                ),
                Text(
                  sub,
                  style: refText(
                    family: Ref.fm,
                    size: 9,
                    wght: 700,
                    ls: 4,
                    height: 1.2,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DoubleBorder extends Decoration {
  const _DoubleBorder(this.c);
  final Color c;
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _DoubleBorderP(c);
}

class _DoubleBorderP extends BoxPainter {
  _DoubleBorderP(this.c);
  final Color c;
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final Rect r = offset & (cfg.size ?? Size.zero);
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = c;
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.deflate(.5), const Radius.circular(8)),
      p,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.deflate(2.5), const Radius.circular(6)),
      p,
    );
  }
}

/// IC.lock：14 线宽 2 的小锁
class RefLockIcon extends StatelessWidget {
  const RefLockIcon({super.key, this.size = 14, this.color = Ref.dim});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _LockP(color));
}

class _LockP extends CustomPainter {
  const _LockP(this.c);
  final Color c;
  @override
  void paint(Canvas canvas, Size s) {
    final double k = s.width / 24;
    canvas.scale(k);
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 / k * (s.width / 24) * 2
      ..color = c;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(5, 11, 14, 10),
        const Radius.circular(2),
      ),
      p,
    );
    canvas.drawPath(
      Path()
        ..moveTo(8, 11)
        ..lineTo(8, 8)
        ..arcToPoint(const Offset(16, 8), radius: const Radius.circular(4))
        ..lineTo(16, 11),
      p,
    );
  }

  @override
  bool shouldRepaint(_LockP o) => o.c != c;
}

// ─────────────────────────────────────────────────────────────
//  插画窗 .tc-art
// ─────────────────────────────────────────────────────────────
class _ArtWindow extends StatelessWidget {
  const _ArtWindow({
    required this.data,
    required this.compact,
    required this.focus,
    required this.t,
  });

  final RefTCardData data;
  final bool compact;
  final bool focus;
  final ValueNotifier<double> t;

  @override
  Widget build(BuildContext context) {
    final Color gc = data.gc;
    final RefArtKind kind = data.kind;
    final String lab = switch (kind) {
      RefArtKind.clock => 'TIME TRIAL',
      RefArtKind.route => 'ROUTE',
      RefArtKind.hill => 'CLIMB',
      RefArtKind.cup => 'ERRAND',
      RefArtKind.boss => 'FINAL · BOSS',
    };
    final (String, String)? big = switch (kind) {
      RefArtKind.clock || RefArtKind.boss => ('${data.minutes}', 'MIN'),
      RefArtKind.route => (data.km ?? '', 'KM'),
      RefArtKind.hill => ('12', '%'),
      RefArtKind.cup => null,
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          CustomPaint(
            painter: _ArtBgPainter(gc: gc, t: t, scan: focus),
          ),
          Positioned(
            right: -8,
            bottom: -30,
            child: Text(
              data.rank,
              style: TextStyle(
                fontFamily: Ref.fd,
                fontSize: 150,
                height: 1,
                fontWeight: FontWeight.w700,
                fontStyle: FontStyle.italic,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 1.5
                  ..color = Ref.a(gc, .26),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _ArtFigurePainter(
                kind: kind,
                gc: gc,
                minutes: data.minutes,
                bike: data.bike,
                t: t,
              ),
            ),
          ),
          Positioned(
            left: compact ? 6 : 9,
            top: compact ? 6 : 9,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0x80000000),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Ref.a(gc, .4)),
              ),
              child: Text(
                lab,
                style: refText(
                  family: Ref.fm,
                  size: compact ? 8 : 9,
                  wght: 700,
                  ls: 2,
                  height: 1.2,
                  color: gc,
                ),
              ),
            ),
          ),
          if (big != null && big.$1.isNotEmpty)
            Positioned(
              right: 11,
              top: 5,
              child: Text.rich(
                TextSpan(
                  text: big.$1,
                  style: refText(
                    family: Ref.fd,
                    size: compact ? 22 : 30,
                    wght: 700,
                    italic: true,
                    height: 1.1,
                    color: Colors.white,
                    shadows: <Shadow>[Shadow(color: gc, blurRadius: 16)],
                  ),
                  children: <InlineSpan>[
                    const WidgetSpan(child: SizedBox(width: 2)),
                    TextSpan(
                      text: big.$2,
                      style: refText(
                        family: Ref.fd,
                        size: 12,
                        wght: 700,
                        ls: 1,
                        height: 1.1,
                        color: gc,
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
}

/// 插画窗底：径向光 + 线性底 + 遮罩网格 + 焦点扫描带 + 1px 描边
class _ArtBgPainter extends CustomPainter {
  _ArtBgPainter({required this.gc, required this.t, required this.scan})
    : super(repaint: scan ? t : null);
  final Color gc;
  final ValueNotifier<double> t;
  final bool scan;

  @override
  void paint(Canvas canvas, Size s) {
    final Rect r = Offset.zero & s;
    canvas.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF15122A), Color(0xFF0B0A17)],
        ).createShader(r),
    );
    // radial-gradient(110% 80% at 50% 100%, gc30%, transparent 62%)
    canvas.save();
    final double rx = s.width * 1.1;
    final double ry = s.height * .8;
    canvas.translate(s.width / 2, s.height);
    canvas.scale(rx / ry, 1);
    canvas.drawCircle(
      Offset.zero,
      ry,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[Ref.a(gc, .3), Ref.a(gc, 0)],
          stops: const <double>[0, .62],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: ry)),
    );
    canvas.restore();
    // 16px 网格，按 50% 70% 处径向淡出
    final Offset mc = Offset(s.width * .5, s.height * .7);
    final double mr = math.sqrt(s.width * s.width + s.height * s.height) * .6;
    final Paint grid = Paint()
      ..strokeWidth = 1
      ..shader = RadialGradient(
        colors: const <Color>[Color(0x0DFFFFFF), Color(0x00FFFFFF)],
        stops: const <double>[0, .75],
      ).createShader(Rect.fromCircle(center: mc, radius: mr));
    for (double y = .5; y < s.height; y += 16) {
      canvas.drawLine(Offset(0, y), Offset(s.width, y), grid);
    }
    for (double x = .5; x < s.width; x += 16) {
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), grid);
    }
    // 扫描带 3.6s：top −40% → 110%
    if (scan) {
      final double k = (t.value % 3.6) / 3.6;
      final double h = s.height * .4;
      final double top = -h + k * (s.height * 1.1 + h);
      final Rect band = Rect.fromLTWH(0, top, s.width, h);
      canvas.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Ref.a(gc, 0), Ref.a(gc, .16), Ref.a(gc, 0)],
          ).createShader(band),
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.deflate(.5), const Radius.circular(13)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x12FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_ArtBgPainter o) => o.gc != gc || o.scan != scan;
}

/// JS `tcArt` 的 SVG（viewBox 240×150，meet，non-scaling-stroke，
/// drop-shadow gc70% 5px）
class _ArtFigurePainter extends CustomPainter {
  _ArtFigurePainter({
    required this.kind,
    required this.gc,
    required this.minutes,
    required this.bike,
    required this.t,
  }) : super(repaint: t);

  final RefArtKind kind;
  final Color gc;
  final int minutes;
  final bool bike;
  final ValueNotifier<double> t;

  late double _k;

  @override
  void paint(Canvas canvas, Size s) {
    _k = math.min(s.width / 240, s.height / 150);
    final double ox = (s.width - 240 * _k) / 2;
    final double oy = (s.height - 150 * _k) / 2;
    canvas.save();
    canvas.translate(ox, oy);
    final double sec = t.value;
    switch (kind) {
      case RefArtKind.clock:
        _clock(canvas);
      case RefArtKind.route:
        _route(canvas, sec);
      case RefArtKind.hill:
        _hill(canvas);
      case RefArtKind.cup:
        _cup(canvas, sec);
      case RefArtKind.boss:
        _boss(canvas, sec);
    }
    if (kind != RefArtKind.hill) _speed(canvas, sec);
    if (kind == RefArtKind.hill) {
      canvas.save();
      canvas.translate(120 * _k, 108 * _k);
      canvas.rotate(-14 * math.pi / 180);
      canvas.translate(-120 * _k, -108 * _k);
      _figure(canvas, 120, 112, .9, sec);
      canvas.restore();
    } else {
      _figure(canvas, 122, 112, 1, sec);
    }
    canvas.restore();
  }

  Offset _p(double x, double y) => Offset(x * _k, y * _k);

  /// 描边 + 发光（drop-shadow gc70% 5px）
  void _stroke(
    Canvas c,
    Path p,
    Color color,
    double w, {
    double op = 1,
    bool round = false,
  }) {
    final Paint glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w + 1
      ..strokeCap = round ? StrokeCap.round : StrokeCap.butt
      ..strokeJoin = StrokeJoin.round
      ..color = Ref.a(gc, .7 * op)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    c.drawPath(p, glow);
    c.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = round ? StrokeCap.round : StrokeCap.butt
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: color.a * op),
    );
  }

  void _fill(Canvas c, Path p, Color color, {double op = 1}) {
    c.drawPath(
      p,
      Paint()
        ..color = Ref.a(gc, .7 * op)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    c.drawPath(p, Paint()..color = color.withValues(alpha: color.a * op));
  }

  Path _dashed(Path src, double dash, double gap, double offset) {
    final Path out = Path();
    for (final ui.PathMetric m in src.computeMetrics()) {
      final double period = dash + gap;
      double d = -(offset % period);
      while (d < m.length) {
        final double a = math.max(0, d);
        final double b = math.min(m.length, d + dash);
        if (b > a) out.addPath(m.extractPath(a, b), Offset.zero);
        d += period;
      }
    }
    return out;
  }

  void _clock(Canvas c) {
    final double f = math.min(1, minutes / 60);
    final Offset ctr = _p(120, 80);
    final double r = 58 * _k;
    _stroke(
      c,
      Path()..addOval(Rect.fromCircle(center: ctr, radius: r)),
      gc,
      1,
      op: .18,
    );
    _stroke(
      c,
      Path()..addArc(
        Rect.fromCircle(center: ctr, radius: r),
        -math.pi / 2,
        2 * math.pi * f,
      ),
      gc,
      3,
      op: .75,
      round: true,
    );
    for (int k = 0; k < 12; k++) {
      final double a = k / 12 * math.pi * 2;
      _stroke(
        c,
        Path()
          ..moveTo(
            ctr.dx + math.sin(a) * 48 * _k,
            ctr.dy - math.cos(a) * 48 * _k,
          )
          ..lineTo(
            ctr.dx + math.sin(a) * 53 * _k,
            ctr.dy - math.cos(a) * 53 * _k,
          ),
        gc,
        1.4,
        op: .5,
      );
    }
  }

  void _route(Canvas c, double sec) {
    final Path p = Path()
      ..moveTo(22 * _k, 44 * _k)
      ..cubicTo(60 * _k, 10 * _k, 84 * _k, 70 * _k, 120 * _k, 40 * _k)
      // S182 18 218 36：反射控制点 (156,10)
      ..cubicTo(156 * _k, 10 * _k, 182 * _k, 18 * _k, 218 * _k, 36 * _k);
    _stroke(c, _dashed(p, 5, 9, sec * 28), gc, 2.2, round: true);
    _fill(
      c,
      Path()..addOval(Rect.fromCircle(center: _p(22, 44), radius: 4)),
      gc,
    );
    final double ph = (sec % 1.6) / 1.6;
    final double sc = 1 + .35 * math.sin(ph * math.pi);
    final double op = 1 - .5 * math.sin(ph * math.pi);
    _stroke(
      c,
      Path()
        ..addOval(Rect.fromCircle(center: _p(218, 36), radius: 6 * _k * sc)),
      Colors.white,
      1.5,
      op: op,
    );
    _fill(
      c,
      Path()..addOval(Rect.fromCircle(center: _p(218, 36), radius: 3 * _k)),
      Colors.white,
    );
  }

  void _hill(Canvas c) {
    final Path area = Path()
      ..moveTo(0, 132 * _k)
      ..lineTo(70 * _k, 120 * _k)
      ..lineTo(150 * _k, 52 * _k)
      ..lineTo(240 * _k, 40 * _k)
      ..lineTo(240 * _k, 150 * _k)
      ..lineTo(0, 150 * _k)
      ..close();
    c.drawPath(area, Paint()..color = Ref.a(gc, .12));
    _stroke(
      c,
      Path()
        ..moveTo(0, 132 * _k)
        ..lineTo(70 * _k, 120 * _k)
        ..lineTo(150 * _k, 52 * _k)
        ..lineTo(240 * _k, 40 * _k),
      gc,
      2.2,
      op: .8,
    );
    _fill(
      c,
      Path()
        ..moveTo(150 * _k, 52 * _k)
        ..lineTo(150 * _k, 36 * _k)
        ..lineTo(162 * _k, 41 * _k)
        ..lineTo(150 * _k, 46 * _k)
        ..close(),
      gc,
    );
  }

  void _cup(Canvas c, double sec) {
    c.save();
    c.translate(176 * _k, 22 * _k);
    _stroke(
      c,
      Path()
        ..moveTo(0, 14 * _k)
        ..lineTo(26 * _k, 14 * _k)
        ..lineTo(23 * _k, 40 * _k)
        ..lineTo(3 * _k, 40 * _k)
        ..close(),
      gc,
      2,
    );
    _stroke(
      c,
      Path()
        ..moveTo(26 * _k, 19 * _k)
        ..lineTo(31 * _k, 19 * _k)
        ..arcToPoint(Offset(31 * _k, 29 * _k), radius: Radius.circular(5 * _k))
        ..lineTo(25 * _k, 29 * _k),
      gc,
      2,
    );
    for (final double x in <double>[7, 15]) {
      final Path steam = Path()
        ..moveTo(x * _k, 10 * _k)
        ..quadraticBezierTo((x - 3) * _k, 6 * _k, x * _k, 4 * _k)
        ..quadraticBezierTo((x + 3) * _k, 2 * _k, x * _k, 0);
      _stroke(c, _dashed(steam, 5, 9, sec * 28), Colors.white, 1.2);
    }
    c.restore();
  }

  void _boss(Canvas c, double sec) {
    for (int k = 0; k < 14; k++) {
      final double a = k / 14 * math.pi * 2;
      c.drawLine(
        _p(120 + math.cos(a) * 40, 70 + math.sin(a) * 40),
        _p(120 + math.cos(a) * 120, 70 + math.sin(a) * 120),
        Paint()
          ..strokeWidth = 1
          ..color = Ref.a(gc, .22),
      );
    }
    final double ph = (sec % 1.6) / 1.6;
    final double sc = 1 + .35 * math.sin(ph * math.pi);
    final double op = 1 - .5 * math.sin(ph * math.pi);
    c.save();
    final Offset ctr = _p(120, 43);
    c.translate(ctr.dx, ctr.dy);
    c.scale(sc);
    c.translate(-ctr.dx, -ctr.dy);
    _fill(
      c,
      Path()
        ..moveTo(98 * _k, 52 * _k)
        ..relativeLineTo(8 * _k, -18 * _k)
        ..relativeLineTo(14 * _k, 12 * _k)
        ..relativeLineTo(14 * _k, -12 * _k)
        ..relativeLineTo(8 * _k, 18 * _k)
        ..close(),
      gc,
      op: op,
    );
    c.restore();
  }

  void _speed(Canvas c, double sec) {
    final double off = sec * 28;
    _stroke(
      c,
      _dashed(
        Path()
          ..moveTo(14 * _k, 132 * _k)
          ..lineTo(226 * _k, 132 * _k),
        5,
        9,
        off,
      ),
      gc,
      1.5,
      op: .6,
    );
    final Path lines = Path()
      ..moveTo(18 * _k, 92 * _k)
      ..lineTo(58 * _k, 92 * _k)
      ..moveTo(10 * _k, 104 * _k)
      ..lineTo(50 * _k, 104 * _k)
      ..moveTo(24 * _k, 116 * _k)
      ..lineTo(62 * _k, 116 * _k);
    _stroke(c, _dashed(lines, 5, 9, off), Colors.white, 1.2, op: .35);
  }

  /// 主角：单车（JS tcBike）或系统之眼
  void _figure(Canvas c, double x, double y, double s, double sec) {
    if (!bike) {
      _eye(c, x, y - 30, s);
      return;
    }
    final double r = 21 * s;
    final double dx = 34 * s;
    final double spin = (sec % 1.6) / 1.6 * 2 * math.pi;
    for (final double cx in <double>[x - dx, x + dx]) {
      _stroke(
        c,
        Path()..addOval(Rect.fromCircle(center: _p(cx, y), radius: r * _k)),
        gc,
        2.4,
      );
      c.save();
      final Offset ctr = _p(cx, y);
      c.translate(ctr.dx, ctr.dy);
      c.rotate(spin);
      final double a = (r - 3) * _k;
      final double d = r * .68 * _k;
      final Path spokes = Path()
        ..moveTo(-a, 0)
        ..lineTo(a, 0)
        ..moveTo(0, -a)
        ..lineTo(0, a)
        ..moveTo(-d, -d)
        ..lineTo(d, d)
        ..moveTo(-d, d)
        ..lineTo(d, -d);
      c.drawPath(
        spokes,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Ref.a(gc, .55),
      );
      c.restore();
      _fill(
        c,
        Path()..addOval(Rect.fromCircle(center: _p(cx, y), radius: 2.6 * _k)),
        gc,
      );
    }
    final Path frame = Path()
      ..moveTo((x - dx) * _k, y * _k)
      ..lineTo((x - 10 * s) * _k, (y - 30 * s) * _k)
      ..lineTo((x + 22 * s) * _k, (y - 30 * s) * _k)
      ..lineTo((x + dx) * _k, y * _k)
      ..moveTo((x - 10 * s) * _k, (y - 30 * s) * _k)
      ..lineTo(x * _k, y * _k)
      ..lineTo((x - dx) * _k, y * _k)
      ..moveTo((x + 22 * s) * _k, (y - 30 * s) * _k)
      ..lineTo(x * _k, y * _k)
      ..moveTo((x - 15 * s) * _k, (y - 38 * s) * _k)
      ..lineTo((x - 3 * s) * _k, (y - 38 * s) * _k)
      ..moveTo((x + 19 * s) * _k, (y - 36 * s) * _k)
      ..lineTo((x + 24 * s) * _k, (y - 42 * s) * _k)
      ..lineTo((x + 31 * s) * _k, (y - 40 * s) * _k);
    _stroke(c, frame, Colors.white, 2.6, round: true);
  }

  /// 非骑行目标：系统之眼（同 .cb-emb 的眼形 + 虹膜）
  void _eye(Canvas c, double x, double y, double s) {
    final double w = 46 * s;
    final Path eye = Path()
      ..moveTo((x - w) * _k, y * _k)
      ..quadraticBezierTo(x * _k, (y - 40 * s) * _k, (x + w) * _k, y * _k)
      ..quadraticBezierTo(x * _k, (y + 40 * s) * _k, (x - w) * _k, y * _k)
      ..close();
    c.drawPath(eye, Paint()..color = const Color(0xE606050E));
    _stroke(c, eye, Colors.white, 2.6, round: true);
    _stroke(
      c,
      Path()..addOval(Rect.fromCircle(center: _p(x, y), radius: 17 * s * _k)),
      gc,
      2,
    );
    _fill(
      c,
      Path()..addOval(Rect.fromCircle(center: _p(x, y), radius: 8 * s * _k)),
      gc,
    );
    c.drawCircle(
      _p(x - 6 * s, y - 6 * s),
      3 * s * _k,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_ArtFigurePainter o) =>
      o.kind != kind || o.gc != gc || o.bike != bike || o.minutes != minutes;
}

// ─────────────────────────────────────────────────────────────
//  背面
// ─────────────────────────────────────────────────────────────
/// .tc-back.cb（L603-617）：封印
class _SealedBack extends StatelessWidget {
  const _SealedBack({
    required this.data,
    required this.compact,
    required this.t,
  });
  final RefTCardData data;
  final bool compact;
  final ValueNotifier<double> t;

  @override
  Widget build(BuildContext context) {
    final Color gc = data.gc;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        CustomPaint(painter: _SealBgPainter(gc)),
        Padding(
          padding: EdgeInsets.all(compact ? 12 : 20),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              final double emb = box.maxWidth * (compact ? .32 : .46);
              final double gap = compact ? 7 : 12;
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  SizedBox(
                    width: emb,
                    height: emb,
                    child: CustomPaint(
                      painter: _EmblemPainter(gc: gc, t: t),
                    ),
                  ),
                  SizedBox(height: gap),
                  Text.rich(
                    TextSpan(
                      style: refText(
                        family: Ref.fd,
                        size: compact ? 13 : 17,
                        wght: 700,
                        italic: true,
                        ls: 4,
                        height: 1.2,
                        color: Colors.white,
                      ),
                      children: <InlineSpan>[
                        const TextSpan(text: 'HOST '),
                        TextSpan(
                          text: '//',
                          style: TextStyle(
                            color: gc,
                            fontStyle: FontStyle.normal,
                          ),
                        ),
                        const TextSpan(text: ' SYSTEM'),
                      ],
                    ),
                  ),
                  SizedBox(height: gap),
                  Text(
                    '${data.prefix} ${_pad2(data.index + 1)} · '
                    '${data.boss ? 'FINAL ' : ''}SEALED',
                    style: refText(
                      family: Ref.fm,
                      size: 9,
                      wght: 700,
                      ls: 3,
                      height: 1.2,
                      color: Ref.dim,
                    ),
                  ),
                  SizedBox(height: gap + (compact ? 2 : 6)),
                  CustomPaint(
                    painter: const RefDashedRRectPainter(
                      color: Color(0x24FFFFFF),
                      radius: 10,
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 9 : 12,
                        vertical: compact ? 7 : 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x66000000),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '情报 · ${data.rank} 级 · ${data.catName}',
                            style: refText(
                              family: Ref.fm,
                              size: 9,
                              wght: 700,
                              ls: 2,
                              height: 1.2,
                              color: gc,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            data.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: refText(
                              size: compact ? 12 : 13,
                              wght: 700,
                              height: 1.4,
                              color: const Color(0xBFFFFFFF),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${data.minutes} 分钟 · ${data.proof}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: refText(
                              size: 11,
                              wght: 400,
                              height: 1.4,
                              color: Ref.dim,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: gap),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const RefLockIcon(size: 14, color: Ref.dim),
                      const SizedBox(width: 6),
                      Text(
                        '完成上一单解封',
                        style: refText(
                          size: 11,
                          wght: 500,
                          height: 1.2,
                          color: Ref.dim,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SealBgPainter extends CustomPainter {
  const _SealBgPainter(this.gc);
  final Color gc;
  @override
  void paint(Canvas canvas, Size s) {
    final Rect r = Offset.zero & s;
    canvas.drawRect(
      r,
      Paint()
        ..shader = refCssLinear(
          165,
          const <Color>[Color(0xFF1B1533), Color(0xFF0A0914)],
          const <double>[0, 1],
        ).createShader(r),
    );
    // ±60° 交叉细线（14px 间距，白 3.5%）
    final Paint ln = Paint()
      ..strokeWidth = 1
      ..color = const Color(0x09FFFFFF);
    final double step = 14 / math.sin(math.pi / 3);
    final double span = s.width + s.height;
    for (double d = -span; d < span; d += step) {
      final double k = math.tan(math.pi / 6);
      canvas.drawLine(Offset(d, 0), Offset(d + s.height * k, s.height), ln);
      canvas.drawLine(Offset(d, s.height), Offset(d + s.height * k, 0), ln);
    }
    final Offset c = Offset(s.width / 2, s.height * .4);
    final double rr = math.max(s.width, s.height) * .55;
    canvas.drawCircle(
      c,
      rr,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[Ref.a(gc, .24), Ref.a(gc, 0)],
        ).createShader(Rect.fromCircle(center: c, radius: rr)),
    );
  }

  @override
  bool shouldRepaint(_SealBgPainter o) => o.gc != gc;
}

/// .cb-emb：两圈反向旋转虚线环 + 眼
class _EmblemPainter extends CustomPainter {
  _EmblemPainter({required this.gc, required this.t}) : super(repaint: t);
  final Color gc;
  final ValueNotifier<double> t;

  @override
  void paint(Canvas canvas, Size s) {
    final double k = s.width / 100;
    final Offset c = Offset(s.width / 2, s.height / 2);
    final double sec = t.value;
    Paint st(double w, Color col) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..color = col;
    Paint glow(double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w + 1
      ..color = gc
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    void ring(
      double r,
      double w,
      double dash,
      double gap,
      double rot,
      double op,
    ) {
      final Path p = Path();
      final double circ = 2 * math.pi * r * k;
      final int n = (circ / ((dash + gap) * k)).floor();
      for (int i = 0; i < n; i++) {
        final double a0 = rot + i * (dash + gap) * k / (r * k);
        p.addArc(Rect.fromCircle(center: c, radius: r * k), a0, dash / r);
      }
      canvas.drawPath(p, glow(w));
      canvas.drawPath(p, st(w, gc.withValues(alpha: op)));
    }

    ring(46, 1.5, 18, 7, sec / 14 * 2 * math.pi, 1);
    ring(37, 1, 3, 5, -sec / 9 * 2 * math.pi, .7);
    final Path eye = Path()
      ..moveTo(18 * k, 50 * k)
      ..quadraticBezierTo(50 * k, 22 * k, 82 * k, 50 * k)
      ..quadraticBezierTo(50 * k, 78 * k, 18 * k, 50 * k)
      ..close();
    canvas.drawPath(eye, glow(2));
    canvas.drawPath(eye, st(2, Colors.white));
    canvas.drawCircle(c, 10 * k, Paint()..color = gc);
    canvas.drawCircle(
      Offset(54 * k, 46 * k),
      3 * k,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_EmblemPainter o) => o.gc != gc;
}

/// .tc-back.tcrec（L618-629）：战报
class _RecordBack extends StatelessWidget {
  const _RecordBack({
    required this.data,
    required this.record,
    required this.compact,
  });
  final RefTCardData data;
  final RefTCardRecord? record;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final RefTCardRecord r =
        record ??
        RefTCardRecord(
          rank: 'A',
          time: Duration(minutes: data.minutes),
          exp: data.exp,
          coin: data.coin,
          day: 1,
        );
    final Color rc = refRecColor(r.rank);
    final Color gc = data.gc;
    final String quote = r.quote.isNotEmpty
        ? r.quote
        : (kRecQuotes[r.rank] ?? kRecQuotes['A']!)[data.index % 2];
    Widget row(String k, InlineSpan v) => Container(
      margin: EdgeInsets.only(top: compact ? 4 : 6),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 7,
      ),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Text(
            k,
            style: refText(
              size: compact ? 11 : 12,
              wght: 500,
              height: 1.3,
              color: Ref.dim,
            ),
          ),
          const Spacer(),
          Text.rich(
            v,
            style: refText(
              family: Ref.fd,
              size: compact ? 12 : 14,
              wght: 700,
              height: 1.3,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 16,
        compact ? 12 : 16,
        compact ? 12 : 16,
        compact ? 10 : 14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'RECORD · 战报',
                style: refText(
                  family: Ref.fm,
                  size: compact ? 8 : 10,
                  wght: 700,
                  ls: compact ? 2 : 3,
                  height: 1.2,
                  color: gc,
                ),
              ),
              const Spacer(),
              Text(
                '${data.prefix} ${_pad2(data.index + 1)}',
                style: refText(
                  family: Ref.fm,
                  size: compact ? 8 : 10,
                  wght: 700,
                  ls: compact ? 2 : 3,
                  height: 1.2,
                  color: gc,
                ),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.only(top: compact ? 4 : 8, bottom: 2),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: <Widget>[
                Column(
                  children: <Widget>[
                    Text(
                      r.rank,
                      style: refText(
                        family: Ref.fd,
                        size: compact ? 56 : 92,
                        wght: 700,
                        italic: true,
                        height: 1,
                        color: rc,
                        shadows: <Shadow>[Shadow(color: rc, blurRadius: 30)],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '验收评级 · GRADE',
                      style: refText(
                        family: Ref.fm,
                        size: 9,
                        wght: 700,
                        ls: 4,
                        height: 1.2,
                        color: Ref.dim,
                      ),
                    ),
                  ],
                ),
                if (r.crit)
                  Positioned(
                    right: 12,
                    top: 6,
                    child: Transform.rotate(
                      angle: 12 * math.pi / 180,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Ref.hot,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'CRIT',
                          style: refText(
                            family: Ref.fm,
                            size: 10,
                            wght: 700,
                            ls: 2,
                            height: 1.2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: compact ? 2 : 4),
          row(
            '用时',
            TextSpan(
              text: '${_mmss(r.time)} ',
              children: <InlineSpan>[
                TextSpan(
                  text: '/ ${_pad2(data.minutes)}:00',
                  style: refText(
                    family: Ref.fd,
                    size: 11,
                    wght: 400,
                    color: Ref.dim,
                  ),
                ),
              ],
            ),
          ),
          row('获得', TextSpan(text: 'EXP +${r.exp} · ◆ ${r.coin}')),
          row('完成于', TextSpan(text: 'DAY ${_pad2(r.day)}')),
          const Spacer(),
          Container(
            padding: EdgeInsets.only(top: compact ? 6 : 10, bottom: 2),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'SYSTEM 批注',
                  style: refText(
                    family: Ref.fm,
                    size: 9,
                    wght: 700,
                    ls: 2,
                    height: 1.2,
                    color: gc,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  quote,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: refText(
                    size: compact ? 11 : 12,
                    wght: 500,
                    height: 1.5,
                    color: const Color(0xCCFFFFFF),
                  ),
                ),
              ],
            ),
          ),
          if (!compact)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '点击翻回正面',
                textAlign: TextAlign.center,
                style: refText(
                  size: 10,
                  wght: 500,
                  ls: 1,
                  height: 1.2,
                  color: Ref.dim,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// .ped（L630-636）：卡下光台 —— 光柱 + 模糊椭圆 + 两圈 78° 透视环
class RefPedestal extends StatefulWidget {
  const RefPedestal({super.key, required this.color});
  final Color color;

  @override
  State<RefPedestal> createState() => _RefPedestalState();
}

class _RefPedestalState extends State<RefPedestal> {
  /// 208s 的光台旋转是极慢环境动画。用 Timer 10fps 推进，而不是
  /// 60fps Ticker：后者即使画面不变也会每帧调度渲染，白白点亮 GPU。
  Timer? _timer;
  double _phase = 0;
  final ValueNotifier<int> _rev = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    if (!WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations) {
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        _phase = (_phase + .1) % 208;
        _rev.value++;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rev.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: widget.color),
      duration: const Duration(milliseconds: 450),
      builder: (BuildContext _, Color? pc, Widget? _) => RepaintBoundary(
        child: CustomPaint(
          painter: _PedPainter(
            color: pc ?? widget.color,
            phase: () => _phase,
            repaint: _rev,
          ),
        ),
      ),
    );
  }
}

class _PedPainter extends CustomPainter {
  _PedPainter({required this.color, required this.phase, Listenable? repaint})
    : super(repaint: repaint);
  final Color color;
  final double Function() phase;

  @override
  void paint(Canvas canvas, Size s) {
    // .ped：left 50% / bottom −4 / 宽 84% / 高 64
    final double w = s.width * .84;
    final Rect ped = Rect.fromLTWH((s.width - w) / 2, s.height + 4 - 64, w, 64);
    // 光柱 b：left/right 14%，bottom 30，高 320，梯形，水平两端淡出
    final Rect beam = Rect.fromLTRB(
      ped.left + w * .14,
      ped.bottom - 30 - 320,
      ped.right - w * .14,
      ped.bottom - 30,
    );
    final Path trap = Path()
      ..moveTo(beam.left + beam.width * .06, beam.bottom)
      ..lineTo(beam.right - beam.width * .06, beam.bottom)
      ..lineTo(beam.right, beam.top)
      ..lineTo(beam.left, beam.top)
      ..close();
    canvas.saveLayer(beam, Paint());
    canvas.drawPath(
      trap,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[Ref.a(color, .13), Ref.a(color, 0)],
          stops: const <double>[0, .7],
        ).createShader(beam),
    );
    canvas.drawRect(
      beam,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(
          colors: <Color>[
            Color(0x00000000),
            Color(0xFF000000),
            Color(0xFF000000),
            Color(0x00000000),
          ],
          stops: <double>[0, .25, .75, 1],
        ).createShader(beam),
    );
    canvas.restore();
    // ::before：inset 4 0，椭圆 closest-side 径向，blur 4
    final Rect glow = Rect.fromLTRB(
      ped.left,
      ped.top + 4,
      ped.right,
      ped.bottom - 4,
    );
    canvas.save();
    canvas.translate(glow.center.dx, glow.center.dy);
    canvas.scale(glow.width / glow.height, 1);
    final double gr = glow.height / 2;
    canvas.drawCircle(
      Offset.zero,
      gr,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[Ref.a(color, .5), Ref.a(color, 0)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: gr))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.restore();
    // 两圈 rotateX(78°)：竖向压到 cos78 ≈ .208
    final double sec = phase();
    final Offset c = ped.center;
    void ring(double d, double speed, bool dashed, double op, double dir) {
      final double rx = d / 2;
      final double ry = d / 2 * math.cos(78 * math.pi / 180);
      final Paint p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Ref.a(color, op);
      if (!dashed) {
        canvas.drawOval(
          Rect.fromCenter(center: c, width: rx * 2, height: ry * 2),
          p,
        );
        return;
      }
      // 虚线沿圆周转（rotate 绕法线 = 椭圆上的相位移动）
      final double rot = dir * sec / speed * 2 * math.pi;
      const int n = 56;
      for (int i = 0; i < n; i += 2) {
        final double a0 = rot + i / n * 2 * math.pi;
        final double a1 = rot + (i + 1) / n * 2 * math.pi;
        canvas.drawLine(
          c + Offset(math.cos(a0) * rx, math.sin(a0) * ry),
          c + Offset(math.cos(a1) * rx, math.sin(a1) * ry),
          p,
        );
      }
    }

    ring(250, 16, true, .7, 1);
    ring(310, 26, false, .25, -1);
  }

  @override
  bool shouldRepaint(_PedPainter o) => o.color != color;
}
