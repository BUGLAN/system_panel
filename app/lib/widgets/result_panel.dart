import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'settle_timeline.dart';

import 'package:flutter_svg/flutter_svg.dart';

import '../data/attrs.dart';
import '../design/tokens.dart';
import '../state/result.dart';
import 'sys_icons.dart';

/// ═══════════════════════════════════════════════════════════
///  结算（app.css L358-401 `#result` · ui.js `ResultUI.build`）
///  一层压暗 → 稀有度大字砸下来（一圈实环 + 一圈虚线环）→
///  CLEAR 抬头 → 结算卡：EXP 跳数 / 经验条 / LV 读数 / 筹码 / 一句近况，
///  右上角常驻「保存战报」。
///
///  实测盒模型（390×844，C 级）：
///    save [275,86,97,34] · stack [20,214,350,394]
///    glyph [127,214,136,136] · glyphB [171,230,48,104]
///    head [130,364,130,51]（kick 369 / h3 390）
///    card [20,428,350,180] · exp [38,444,314,40] · bar [38,496,314,6]
///    lv [38,509,314,16] · gain [38,539,314,28] · near [38,577,314,15]
///    chips x=38/91/165/238 各高 28
///
///  跳数 / 盖章 / 经验条上涨 / 保存战报都是行为，等宿主约束；
///  这里渲染的是「已经结算完」的静态样子。
/// ═══════════════════════════════════════════════════════════
class ResultPanel extends StatefulWidget {
  const ResultPanel({
    super.key,
    required this.result,
    this.visible = true,
    this.onSave,
    this.animate = true,
    this.onImpact,
  });

  final QuestResult result;
  final bool visible;
  final VoidCallback? onSave;

  /// 演出开关；比对截图时用 `false` 直接落终态
  final bool animate;

  /// 印章砸下那一刻（原型在这里 flash + shake + burst）
  final ValueChanged<int>? onImpact;

  @override
  State<ResultPanel> createState() => _ResultPanelState();
}

class _ResultPanelState extends State<ResultPanel>
    with SingleTickerProviderStateMixin {
  /// CSS `--out: cubic-bezier(.16, 1, .3, 1)`
  static const Curve _out = Cubic(.16, 1, .3, 1);

  late final AnimationController _c = AnimationController(vsync: this);
  late SettleTimeline _tl;

  /// 下面这些渲染方法原本是 Stateless 时写的，用 getter 接上 widget 的字段
  QuestResult get result => widget.result;
  VoidCallback? get onSave => widget.onSave;

  /// 当前时刻（ms）
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _tl = _makeTimeline();
    if (widget.visible) _start();
  }

  /// ⚠️ 和派单板同一个坑：`ResultPanel` 也一直挂在树里（只是 `visible: false`），
  /// 所以演出必须跟着"变可见"走，不能在 initState 里跑。
  @override
  void didUpdateWidget(covariant ResultPanel old) {
    super.didUpdateWidget(old);
    if (!old.visible && widget.visible) {
      _tl = _makeTimeline();
      _start();
    }
  }

  SettleTimeline _makeTimeline() => SettleTimeline(
    baseExp: widget.result.baseExp,
    finalExp: widget.result.exp,
    crit: widget.result.crit,
    dbl: widget.result.dbl,
    chipCount:
        1 + widget.result.attrs.length + (widget.result.streakUp ? 1 : 0),
  );

  void _start() {
    if (!widget.animate) {
      _t = _tl.total;
      _c.value = 1;
      return;
    }
    _t = 0;
    _c
      ..duration = Duration(milliseconds: _tl.total.round())
      ..addListener(_onTick);
    _c.forward(from: 0);
    // 印章砸下那一下的 FX（原型在 `w(820)` 之后）
    Future<void>.delayed(Duration(milliseconds: _tl.impactAt.round()), () {
      if (mounted) widget.onImpact?.call(widget.result.rarity.i);
    });
  }

  void _onTick() {
    final double t = _c.value * _tl.total;
    // 刚跨过某个门时通知一次（原型是加 `.on` 类）
    setState(() => _t = t);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// CSS `.rs-head { opacity:0; translateY(8px); transition: all .45s var(--out) }`
  Widget _rise(double startMs, double durMs, double dy, Widget child) {
    final double k = ((_t - startMs) / durMs).clamp(0.0, 1.0);
    final double e = _out.transform(k);
    return Opacity(
      opacity: e,
      child: Transform.translate(offset: Offset(0, dy * (1 - e)), child: child),
    );
  }

  /// `.chip { opacity:0; translateY(6px) scale(.9); transition: all .45s var(--spring) }`
  Widget _pop(double startMs, Widget child) {
    final double k = ((_t - startMs) / 450).clamp(0.0, 1.0);
    final double e = Curves.easeOutBack.transform(
      k,
    ); // 近似那条 --spring（有 1.12 的过冲）
    return Opacity(
      opacity: k,
      child: Transform.translate(
        offset: Offset(0, 6 * (1 - e)),
        child: Transform.scale(scale: .9 + .1 * e, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    final QuestResult result = widget.result;
    final Color rk = result.rarity.color;
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (BuildContext _, BoxConstraints c) => Stack(
          children: <Widget>[
            // #result::before —— 从 34% 往下的一层压暗
            Positioned(
              left: 0,
              right: 0,
              top: c.maxHeight * .34,
              bottom: 0,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        const Color(0x0002060E),
                        const Color(0xD102060E), // rgba(2,6,14,.82)
                        const Color(0xF202050C), // rgba(2,5,12,.95)
                      ],
                      stops: const <double>[0, .24, 1],
                    ),
                  ),
                ),
              ),
            ),
            // ① 验收：扫描线从上扫到下（`scan.animate` 780ms）
            if (widget.animate && _t < SettleTimeline.scanDur)
              Positioned(
                left: 0,
                right: 0,
                top: c.maxHeight * _tl.scanTopPct(_t),
                height: 2,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: _tl.scanOpacity(_t),
                    child: const DecoratedBox(
                      key: Key('result.scan'),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[
                            Color(0x009FF0FF),
                            Color(0xFF9FF0FF),
                            Color(0x009FF0FF),
                          ],
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(color: Color(0xFF38E1FF), blurRadius: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // .rs-save
            Positioned(
              right: 18,
              top: 86,
              child: _rise(_tl.saveAt, 400, 0, _saveButton()),
            ),
            // .rs-stack
            Positioned(
              left: 20,
              right: 20,
              bottom: 236,
              child: Column(
                key: const Key('result.stack'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: _Glyph(
                      rank: result.quest.rank,
                      color: rk,
                      // 砸下来那一下（`@keyframes slam`）；null = 还没开始，整块藏着。
                      // `animate: false`（比对）时直接按终态渲染，零变化。
                      slam: widget.animate ? _tl.slamAt(_t) : null,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _rise(_tl.headAt, 450, 8, _head(rk)),
                  const SizedBox(height: 14),
                  _rise(_tl.cardAt, 500, 12, _card()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// .rs-save
  Widget _saveButton() {
    return GestureDetector(
      onTap: onSave,
      behavior: HitTestBehavior.opaque,
      child: Container(
        key: const Key('result.save'),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: const Color(0xA6040E20), // rgba(4,14,32,.65)
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: C.line, width: 1),
        ),
        child: Row(
          children: <Widget>[
            SvgPicture.string(kIconDownload, width: 14, height: 14),
            const SizedBox(width: 7),
            Text(
              '保存战报',
              style: fs(family: F.cn, size: 12, wght: 400, color: C.ice),
            ),
          ],
        ),
      ),
    );
  }

  /// .rs-head —— CLEAR 抬头 + 任务名
  Widget _head(Color rk) {
    final String kick = result.quest.kind == 'main'
        ? 'CLEAR · 主线第 ${result.quest.ring + 1} 环'
        : result.quest.kind == 'remedy'
        ? 'CLEAR · 补救'
        : 'CLEAR · 日常';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // `.rs-head` 里这行 kick 也是 inline，行框被 16px strut 撑到 19.2、文字下沉 5px
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            kick,
            textAlign: TextAlign.center,
            style: fs(
              family: F.mono,
              size: 10,
              wght: 400,
              ls: 1.6,
              height: 1.28,
              color: C.blue,
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          result.quest.name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: fs(
            family: F.hd,
            size: 19,
            wght: 400,
            ls: .57,
            height: 1.3,
            color: C.ice,
          ),
        ),
      ],
    );
  }

  /// .rs-card
  Widget _card() {
    return Container(
      key: const Key('result.card'),
      padding: const EdgeInsets.fromLTRB(17, 15, 17, 15),
      decoration: BoxDecoration(
        color: const Color(0xC7050E20), // rgba(5,14,32,.78)
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.line2, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _expRow(),
          const SizedBox(height: 12),
          _bar(),
          const SizedBox(height: 7),
          _lvRow(),
          const SizedBox(height: 14),
          _chips(),
          const SizedBox(height: 10),
          _near(),
        ],
      ),
    );
  }

  /// .rs-exp —— 小加号 + 40px 大字
  Widget _expRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        SizedBox(
          width: 34,
          child: Text(
            'EXP',
            style: fs(
              family: F.mono,
              size: 10,
              wght: 400,
              ls: 1.6,
              color: C.blue,
            ),
          ),
        ),
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: '+',
                style: fs(
                  family: F.num,
                  size: 24,
                  wght: 800,
                  wdth: 85,
                  height: 1,
                  color: C.blue,
                ),
              ),
              TextSpan(
                // 数字往上跳（原型那个 `count()`）
                text: '${_tl.expAt(_t)}',
                style: fs(
                  family: F.num,
                  size: 40,
                  wght: 800,
                  wdth: 85,
                  ls: .4,
                  height: 1,
                  color: const Color(0xFFF3FDFF),
                  shadows: <Shadow>[
                    Shadow(color: C.blue.withAlpha(140), blurRadius: 20),
                  ],
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const Spacer(),
        // .rs-tags —— 暴击 / 双倍印章（各自到点才盖下去，`animation: stampIn`）
        if (result.crit && _tl.stampAt(_t) >= 1) _stamp('CRIT ×2', false),
        if (result.crit && result.dbl) const SizedBox(width: 6),
        if (result.dbl && _tl.stampAt(_t) >= 2) _stamp('双倍卡 ×2', true),
      ],
    );
  }

  Widget _stamp(String text, bool dbl) {
    return Transform.rotate(
      angle: (dbl ? 4 : -6) * math.pi / 180,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: dbl ? C.blue : Colors.white,
          borderRadius: BorderRadius.circular(4),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: dbl ? C.blue.withAlpha(179) : Colors.white.withAlpha(179),
              blurRadius: 22,
            ),
          ],
        ),
        child: Text(
          text,
          style: fs(
            family: F.num,
            size: 13,
            wght: 900,
            ls: 1.3,
            height: 1,
            color: C.deep,
          ),
        ),
      ),
    );
  }

  /// .rs-bar
  Widget _bar() {
    // 原型：条的起点是"结算前"，`expTo` 涨到"结算后"（`.rs-bar i` 的 width 过渡）
    final double before = (result.beforeExp / result.beforeNeed).clamp(
      0.0,
      1.0,
    );
    final double after = (result.afterExp / result.beforeNeed).clamp(0.0, 1.0);
    final double frac = before + (after - before) * _tl.barProgressAt(_t);
    return Container(
      key: const Key('result.bar'),
      height: 6,
      // CSS `.rs-bar` 有 overflow:hidden，会把填充的 box-shadow 裁在条内；
      // Flutter 的 Container 默认不裁，辉光会漏到下面一行去
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: C.blue.withAlpha(26), // rgba(56,225,255,.1)
        borderRadius: BorderRadius.circular(3),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: frac,
          // 不加 heightFactor 的话无子元素的 DecoratedBox 会被量成 0 高
          heightFactor: 1,
          child: DecoratedBox(
            key: const Key('result.bar.fill'),
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

  /// .rs-lv —— 左边 LV 读数，右边 已得/所需
  Widget _lvRow() {
    final TextStyle base = fs(
      family: F.mono,
      size: 10,
      wght: 600,
      ls: 1,
      // CSS `.rs-lv` 没给 b 写行高 → normal（Tektur 1.3×12=15.6），
      // 传 height:1 会让这一行矮 3px，而结算卡是底部锚定的 —— 整张卡会往下挪
      color: C.mist,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(text: 'LV ', style: base),
              TextSpan(
                text: '${result.beforeLv}',
                style: fs(
                  family: F.num,
                  size: 12,
                  wght: 800,
                  height: 1,
                  color: C.ice,
                ),
              ),
            ],
          ),
        ),
        Text('${result.afterExp} / ${result.beforeNeed}', style: base),
      ],
    );
  }

  /// .rs-gain —— 金币 / 六维 / 连击 一串筹码
  Widget _chips() {
    final List<Widget> chips = <Widget>[
      _chip(<InlineSpan>[
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: SvgPicture.string(kIconCoin, width: 11, height: 11),
        ),
        const WidgetSpan(child: SizedBox(width: 6)),
        TextSpan(text: '+${result.coin}', style: _chipNum),
      ]),
    ];
    result.attrs.forEach((String k, int v) {
      chips.add(
        _chip(<InlineSpan>[
          // 存档里是单字键（体/力），界面上显示全名（体质/力量）
          TextSpan(text: '${Attr.nameOf(k)} ', style: _chipText),
          TextSpan(text: '+$v', style: _chipNum),
        ]),
      );
    });
    if (result.streakUp) {
      chips.add(
        _chip(<InlineSpan>[
          TextSpan(text: '连击 ', style: _chipText),
          TextSpan(text: '${result.streak}', style: _chipNum),
          TextSpan(text: ' 天', style: _chipText),
        ]),
      );
    }
    return Wrap(
      key: const Key('result.gain'),
      spacing: 7,
      runSpacing: 7,
      // 每枚筹码隔 110ms 弹出来（原型 `await w(110)` 再 `ResultUI.chip()`）
      // 占位一直保留（原型 `.chip { opacity: 0 }` 也占位），所以 Wrap 不会重排
      children: <Widget>[
        for (int i = 0; i < chips.length; i++) _pop(_tl.chipAtOf(i), chips[i]),
      ],
    );
  }

  TextStyle get _chipText =>
      fs(family: F.cn, size: 12.5, wght: 400, ls: 0, color: C.ice);
  TextStyle get _chipNum =>
      fs(family: F.num, size: 13, wght: 800, color: C.blue);

  Widget _chip(List<InlineSpan> spans) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: C.blue.withAlpha(20), // rgba(56,225,255,.08)
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.line2, width: 1),
      ),
      child: Center(
        widthFactor: 1,
        child: Text.rich(TextSpan(children: spans)),
      ),
    );
  }

  /// .rs-near —— 一句近况。**两个条件都不成立时整行不显示**（原型只在
  /// `res.near` 有值、或"没暴击且 0 份证据"时才 `classList.add('on')`）。
  ///
  /// ```js
  /// if (res.near) $('#rsNear').innerHTML = `暴击判定：差 <b>${res.near}%</b>。下次多拍一张证据。`
  /// else if (!res.crit && !res.photos) $('#rsNear').innerHTML =
  ///   '本单 0 份证据 · 暴击率只有 <b>' + Math.round(res.chance*100) + '%</b>'
  /// // 否则什么都不设 —— 那一行保持 opacity 0
  /// ```
  Widget _near() {
    final String? text;
    if (result.near > 0) {
      text = '暴击判定：差 [[${result.near}%]]。下次多拍一张证据。';
    } else if (!result.crit && result.photos == 0) {
      text = '本单 0 份证据 · 暴击率只有 [[${result.chancePct}%]]';
    } else {
      text = null; // 不显示
    }
    if (text == null) return const SizedBox.shrink();
    final TextStyle base = fs(
      family: F.mono,
      size: 10.5,
      wght: 500,
      ls: .63,
      height: 1.4,
      color: C.mist,
    );
    // 就地拆一次 `[[…]]`（只有一处高亮，不必上完整的富文本解析器）
    final int i0 = text.indexOf('[[');
    final int i1 = text.indexOf(']]');
    final Widget body = (i0 >= 0 && i1 > i0)
        ? Text.rich(
            TextSpan(
              style: base,
              children: <InlineSpan>[
                TextSpan(text: text.substring(0, i0)),
                // `.rs-near b { color: var(--ice) }`
                TextSpan(
                  text: text.substring(i0 + 2, i1),
                  style: base.copyWith(color: C.ice),
                ),
                TextSpan(text: text.substring(i1 + 2)),
              ],
            ),
          )
        : Text(text, style: base);
    // `.rs-near { opacity: 0; transition: opacity .4s }` + `.on { opacity: 1 }`
    final bool on = !widget.animate || _tl.nearOn(_t);
    return AnimatedOpacity(
      key: const Key('result.near'),
      opacity: on ? 1 : 0,
      duration: const Duration(milliseconds: 400),
      child: body,
    );
  }
}

/// .rs-glyph —— 砸下来的稀有度大字：一圈实环 + 一圈虚线环 + 104px 大字
class _Glyph extends StatefulWidget {
  const _Glyph({required this.rank, required this.color, this.slam});

  final String rank;
  final Color color;

  /// `@keyframes slam` 的进度；`null` = 不演（静态终态）
  final double? slam;

  @override
  State<_Glyph> createState() => _GlyphState();
}

class _GlyphState extends State<_Glyph> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color rk = widget.color;
    final Widget body = SizedBox(
      key: const Key('result.glyph'),
      width: 136,
      height: 136,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // .halo2 —— inset -16 的虚线环，10s 转一圈
          Positioned(
            left: -16,
            top: -16,
            width: 168,
            height: 168,
            child: AnimatedBuilder(
              animation: _spin,
              builder: (BuildContext _, Widget? _) => Transform.rotate(
                angle: _spin.value * 2 * math.pi,
                child: const CustomPaint(painter: _DashedRingPainter()),
              ),
            ),
          ),
          // .halo —— 2px 实环 + 外发光 + 内发光（inset 0 0 40px 30%）
          // 两个坑都踩过：① RadialGradient 会把整块底点亮；② Flutter 的 BoxShadow 会把
          // 外发光**透进透明的内部**（CSS 的外阴影只画在 border-box 外面）——
          // 所以三者统一交给 painter。
          Positioned.fill(
            child: CustomPaint(painter: _HaloPainter(color: rk)),
          ),
          Text(
            widget.rank,
            style: fs(
              family: F.num,
              size: 104,
              wght: 900,
              wdth: 75,
              height: 1,
              color: rk,
              shadows: <Shadow>[
                Shadow(color: rk, blurRadius: 30),
                const Shadow(color: Colors.white, blurRadius: 2),
              ],
            ),
          ),
        ],
      ),
    );
    // `@keyframes slam { 0% { scale(2.4); opacity: 0; brightness(3) }
    //                     30% { opacity: 1 } 100% { none } }` —— 700ms
    // 亮度那一下没做（要用 ColorFilter.matrix 拼一条亮度矩阵），缩放 + 淡入已经够了
    final double? k = widget.slam;
    if (k == null) return body;
    final double e = Curves.easeOutBack.transform(k); // 近似 `--spring` 的过冲
    return Opacity(
      opacity: k < .3 ? k / .3 : 1,
      child: Transform.scale(scale: 2.4 - 1.4 * e, child: body),
    );
  }
}

/// `.halo` —— 三层叠加：`0 0 50px 55%` 外发光 + `inset 0 0 40px 30%` 内发光
/// + `inset 0 0 0 2px` 实环。三样都不能用 Flutter 的现成装饰表达（见调用处注释）。
class _HaloPainter extends CustomPainter {
  const _HaloPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final Offset c = Offset(s.width / 2, s.height / 2);
    final double r = s.width / 2;
    // 外发光：描边的模糊圆，只往外散
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = color.withAlpha(140)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    // 内发光：CSS 的 inset 阴影在边缘只有约一半强度、而且衰减很快
    // （实测：距边缘 8px 处原型只加 ~6 亮度）—— 所以峰值压低、前 8px 就收掉大半
    final double e8 = (r - 8) / r;
    final double e30 = (r - 30) / r;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          r,
          <Color>[
            color.withAlpha(0),
            color.withAlpha(0),
            color.withAlpha(10),
            color.withAlpha(38),
          ],
          <double>[0, e30, e8, 1],
        ),
    );
    // 2px 实环
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _HaloPainter o) => o.color != color;
}

/// `.halo2` 的 1px 虚线圆
class _DashedRingPainter extends CustomPainter {
  const _DashedRingPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final Offset c = Offset(s.width / 2, s.height / 2);
    final double r = s.width / 2 - .5;
    final Rect rect = Rect.fromCircle(center: c, radius: r);
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = C.blue.withAlpha(128); // rgba(56,225,255,.5)
    const double dash = 4, gap = 4;
    final double step = (dash + gap) / r;
    for (double a = 0; a < 2 * math.pi; a += step) {
      canvas.drawArc(rect, a, dash / r, false, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
