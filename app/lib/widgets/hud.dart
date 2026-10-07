import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../design/tokens.dart';
import '../state/host_state.dart';
import 'sys_icons.dart';

/// ═══════════════════════════════════════════════════════════
///  HUD（app.css L94-117 `#hud`）
///  等级环 + 名字/称号/连击 + 金币 + 菜单。
///  实测盒模型（390×844）：hud [0,0,390,74] · lv [16,23,46,46]
///  · name [72,22,179,17] · coin [261,31,69,30] · menu [340,29,34,34]
/// ═══════════════════════════════════════════════════════════
class Hud extends StatelessWidget {
  const Hud({super.key, required this.state, this.visible = true});

  final HostState state;

  /// 开机中 / 聚焦态时整条 HUD 上滑隐藏（app.css L97）
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: 74,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, -1.10),
        duration: const Duration(milliseconds: 500),
        curve: kOut,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 400),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: Row(
              children: <Widget>[
                _LvRing(lv: state.lv, ratio: state.expRatio),
                const SizedBox(width: 10), // #hud gap
                Expanded(child: _Who(state: state)),
                const SizedBox(width: 10),
                _Coin(coins: state.coins),
                const SizedBox(width: 10),
                const _Menu(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// .hud-lv —— 六边等级牌上的经验环（app.css L98-104）
class _LvRing extends StatelessWidget {
  const _LvRing({required this.lv, required this.ratio});

  final int lv;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('hud.lv'),
      width: 46,
      height: 46,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: CustomPaint(painter: _LvRingPainter(ratio: ratio)),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 9,
            child: Text(
              'LV',
              textAlign: TextAlign.center,
              style: fs(
                family: F.mono,
                size: 7.5,
                wght: 600,
                ls: 1.5, // .2em
                height: 1,
                color: C.mist,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 17,
            child: Text(
              '$lv',
              textAlign: TextAlign.center,
              style: fs(
                family: F.num,
                size: 19,
                wght: 800,
                height: 1,
                color: C.ice,
                shadows: <Shadow>[
                  Shadow(color: C.blue.withAlpha(153), blurRadius: 10),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// SVG viewBox 48×48 画在 46×46 的盒子里；r=20、stroke 2.6、周长 125.66
class _LvRingPainter extends CustomPainter {
  const _LvRingPainter({required this.ratio});

  final double ratio;

  static const double _vb = 48; // viewBox
  static const double _r = 20;
  static const double _sw = 2.6;

  @override
  void paint(Canvas canvas, Size s) {
    final double k = s.width / _vb;
    final Offset c = Offset(s.width / 2, s.height / 2);
    final double r = _r * k;
    final Rect rect = Rect.fromCircle(center: c, radius: r);

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _sw * k
        ..color = C.blue.withAlpha(36), // rgba(56,225,255,.14)
    );

    // transform: rotate(-90deg)，从正上方起画
    const double start = -math.pi / 2;
    final double sweep = 2 * math.pi * ratio.clamp(0.0, 1.0);
    final Paint arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _sw * k
      ..strokeCap = StrokeCap.round
      ..color = C.blue;
    // filter: drop-shadow(0 0 3px rgba(56,225,255,.9))
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _sw * k
        ..strokeCap = StrokeCap.round
        ..color = C.blue.withAlpha(230)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawArc(rect, start, sweep, false, arc);
  }

  @override
  bool shouldRepaint(covariant _LvRingPainter o) => o.ratio != ratio;
}

/// .hud-who —— 名字 / 称号 / 连击（app.css L105-109）
class _Who extends StatelessWidget {
  const _Who({required this.state});

  final HostState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          state.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: fs(
            family: F.cn,
            size: 14,
            wght: 600,
            ls: .56,
            height: 1,
            color: C.ice,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '「${state.title}」',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: fs(
            family: F.cn,
            size: 11,
            wght: 400,
            ls: .22,
            height: 1,
            color: C.blue,
          ),
        ),
        const SizedBox(height: 3),
        // `连击 <b>6</b> 天`：数字是 Tektur
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: state.streak > 0 ? '连击 ' : '连击 —',
                style: fs(
                  family: F.mono,
                  size: 9.5,
                  wght: 500,
                  ls: .95,
                  height: 1,
                  color: C.mist,
                ),
              ),
              if (state.streak > 0) ...<InlineSpan>[
                TextSpan(
                  text: '${state.streak}',
                  style: fs(
                    family: F.num,
                    size: 10,
                    wght: 700,
                    height: 1,
                    color: C.ice,
                  ),
                ),
                TextSpan(
                  text: ' 天',
                  style: fs(
                    family: F.mono,
                    size: 9.5,
                    wght: 500,
                    ls: .95,
                    height: 1,
                    color: C.mist,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// .hud-coin（app.css L110-112）
class _Coin extends StatelessWidget {
  const _Coin({required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('hud.coin'),
      height: 30,
      // ⚠️ Flutter 的 Border 会占布局空间，CSS 的 inset box-shadow 不会 ——
      // 所以用 Border 模拟 inset 描边时，padding 要各减 1px 才与原型同宽。
      padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
      decoration: BoxDecoration(
        color: const Color(0x8C08142A), // rgba(8,20,42,.55)
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: C.line2, width: 1), // inset 0 0 0 1px
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SvgPicture.string(kIconCoin, width: 13, height: 13),
          const SizedBox(width: 6),
          Text(
            '$coins',
            style: fs(
              family: F.num,
              size: 15,
              wght: 700,
              ls: .45,
              height: 1,
              color: C.ice,
            ),
          ),
        ],
      ),
    );
  }
}

/// .hud-menu —— 三根不等长的横杠（app.css L115-117）
class _Menu extends StatelessWidget {
  const _Menu();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('hud.menu'),
      width: 34,
      height: 34,
      child: Padding(
        padding: const EdgeInsets.only(right: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _bar(18, C.ice),
            const SizedBox(height: 4),
            _bar(12, C.blue),
            const SizedBox(height: 4),
            _bar(15, C.ice),
          ],
        ),
      ),
    );
  }

  Widget _bar(double w, Color c) => Container(
    width: w,
    height: 1.6,
    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(1)),
  );
}
