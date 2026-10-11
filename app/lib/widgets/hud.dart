import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/titles.dart';
import '../design/tokens.dart';
import '../state/haptics.dart';
import '../state/host_state.dart';
import '../state/sfx.dart';
import 'fx_layer.dart';
import 'sys_icons.dart';

/// ═══════════════════════════════════════════════════════════
///  HUD（app.css L94-117 `#hud`）
///  等级环 + 名字/称号/连击 + 金币 + 菜单。
///  实测盒模型（390×844）：hud [0,0,390,74] · lv [16,23,46,46]
///  · name [72,22,179,17] · coin [261,31,69,30] · menu [340,29,34,34]
///
///  t26/P2 · 跨级白闪：结算出账升级的那拍 HUD 被结算页压住（visible=false），
///  回大厅（visible 翻真）时等级环播一遍 AGENTS.md「经验条上涨」的跨级编排——
///  涨满 360ms → 白闪 16%/180ms + 换级数 → 归零 → 再涨到余额 420ms。
///  相位函数 [hudLevelFx] 是纯函数，fx_test 钉死。
/// ═══════════════════════════════════════════════════════════
class Hud extends StatefulWidget {
  const Hud({
    super.key,
    required this.state,
    this.visible = true,
    this.onMenu,
    this.fade,
  });

  /// 唤醒过场用的淡入动画（0→1）。⚠️ 必须在**本组件内部**套 Opacity：
  /// 本 build 的顶层就是 `Positioned`（ParentDataWidget），外面再包一层
  /// 带 RenderObject 的包装件会报 `Incorrect use of ParentDataWidget`
  /// （2026-10-11 实测：HUD/底栏各抛一次）。
  final Animation<double>? fade;

  /// 点右上角那三根横杠（原型没有承载物，这里接「系统」面板）
  final VoidCallback? onMenu;

  final HostState state;

  /// 开机中 / 聚焦态时整条 HUD 上滑隐藏（app.css L97）
  final bool visible;

  @override
  State<Hud> createState() => _HudState();
}

/// 跨级编排的分段时长（ms）—— AGENTS.md「动效参数 · 经验条上涨」逐条对齐
const double kLvRiseMs = 360; // 涨满
const double kLvFlashMs = 180; // 白闪（亮帧同源：16% / 180ms）
const double kLvSecondMs = 420; // 归零后再涨到余额
const double kLvTotalMs = kLvRiseMs + kLvSecondMs;

/// 跨级编排的相位函数（纯函数，可单测）：给时刻 `t`（0~`kLvTotalMs`），
/// 算等级环此刻该显示成什么样。
///
///  · `t < 360`：旧环比往满环涨（easeOutCubic），级数还是旧级；
///  · `t = 360`：白闪起（峰值 16%，180ms ease-out 衰减）+ 级数切到新级
///    （数字 1.3→1 弹一下）+ 环归零；
///  · `t ∈ (360, 780]`：从 0 涨到新档余额（easeOutCubic，420ms）。
({int lv, double ratio, double flash, double pop}) hudLevelFx({
  required double t,
  required int fromLv,
  required int toLv,
  required double fromRatio,
  required double toRatio,
}) {
  if (t <= 0) {
    return (lv: fromLv, ratio: fromRatio, flash: 0, pop: 1);
  }
  if (t < kLvRiseMs) {
    final double k = Curves.easeOutCubic.transform((t / kLvRiseMs).clamp(0.0, 1.0));
    return (lv: fromLv, ratio: fromRatio + (1 - fromRatio) * k, flash: 0, pop: 1);
  }
  final double ft = ((t - kLvRiseMs) / kLvFlashMs).clamp(0.0, 1.0);
  final double flash = .16 * (1 - Curves.easeOut.transform(ft));
  final double pop = 1 + .3 * (1 - Curves.easeOut.transform(ft));
  final double k = Curves.easeOutCubic.transform(
    ((t - kLvRiseMs) / kLvSecondMs).clamp(0.0, 1.0),
  );
  return (lv: toLv, ratio: toRatio * k, flash: flash, pop: pop);
}

class _HudState extends State<Hud> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: kLvTotalMs.round()),
  );

  /// 已经"见过"的等级 / 环比（跨级编排的起点）
  int _seenLv = 0;
  double _lastRatio = 0;

  /// 升级发生在后台（结算页压着 HUD）时攒一拍，回到大厅再播
  bool _pending = false;

  /// 编排参数（开播时定格）
  int _fromLv = 0;
  double _fromRatio = 0;
  double _toRatio = 0;

  @override
  void initState() {
    super.initState();
    _seenLv = widget.state.lv;
    _lastRatio = widget.state.expRatio;
  }

  @override
  void didUpdateWidget(covariant Hud old) {
    super.didUpdateWidget(old);
    final int lv = widget.state.lv;
    final double ratio = widget.state.expRatio;
    if (lv > _seenLv && _seenLv > 0) {
      // 跨级：记下旧环比 → 新环比；HUD 在前台就当场播，被压住就攒着
      _fromLv = _seenLv;
      _fromRatio = _lastRatio;
      _toRatio = ratio;
      _pending = true;
      if (widget.visible) _play();
    } else if (lv < _seenLv) {
      // 回档 / 清档：直接吸附，不播
      _pending = false;
      if (_c.isAnimating) _c.stop();
      _lastRatio = ratio;
    } else if (!_c.isAnimating) {
      _lastRatio = ratio;
    }
    _seenLv = lv;
    if (!old.visible && widget.visible && _pending) _play();
  }

  void _play() {
    _pending = false;
    // 升级（`flows.js:485` `levelUp(lv)`）：
    // `Sound.play('levelup'); FX.flash('#e9fbff', .2, 260); buzz([30, 50, 30, 50])`
    // —— 这一拍就是本工程里"升级"的唯一相位（结算的 `res.ups` 在 result_panel 里
    // 不建模）：HUD 在前台就是升级那一帧、被结算页压住就攒到回大厅补播的那一帧。
    // `_play()` 只在 `_pending` 翻假时被调一次（跨级、且只跨一级攒一拍），不会连发。
    Sfx.play('levelup');
    Haptics.buzz('levelup');
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget body = IgnorePointer(
        ignoring: !widget.visible,
        child: AnimatedSlide(
          offset: widget.visible ? Offset.zero : const Offset(0, -1.10),
          duration: const Duration(milliseconds: 500),
          curve: kOut,
          child: AnimatedOpacity(
            opacity: widget.visible ? 1 : 0,
            duration: const Duration(milliseconds: 400),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: Row(
                children: <Widget>[
                  AnimatedBuilder(
                    animation: _c,
                    builder: (BuildContext _, Widget? _) {
                      if (!_c.isAnimating) {
                        // 静态（含首挂）：与旧版逐字节一致
                        return _LvRing(
                          lv: widget.state.lv,
                          ratio: widget.state.expRatio,
                        );
                      }
                      final ({int lv, double ratio, double flash, double pop})
                      s = hudLevelFx(
                        t: _c.value * kLvTotalMs,
                        fromLv: _fromLv,
                        toLv: widget.state.lv,
                        fromRatio: _fromRatio,
                        toRatio: _toRatio,
                      );
                      return _LvRing(
                        lv: s.lv,
                        ratio: s.ratio,
                        flash: s.flash,
                        pop: s.pop,
                      );
                    },
                  ),
                  const SizedBox(width: 10), // #hud gap
                  Expanded(child: _Who(state: widget.state)),
                  const SizedBox(width: 10),
                  _Coin(coins: widget.state.coins),
                  const SizedBox(width: 10),
                  _Menu(onTap: widget.onMenu),
                ],
              ),
            ),
          ),
        ),
      );
    if (widget.fade != null) {
      final Animation<double> f = widget.fade!;
      body = AnimatedBuilder(
        animation: f,
        builder: (BuildContext _, Widget? c) => Opacity(
          opacity: Curves.easeOut.transform(f.value.clamp(0.0, 1.0)),
          child: c,
        ),
        child: body,
      );
    }
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: 74,
      child: body,
    );
  }
}

/// .hud-lv —— 六边等级牌上的经验环（app.css L98-104）
///
/// `flash`/`pop` 是跨级白闪那 780ms 里的临时参数（见 [hudLevelFx]）；
/// 缺省（静态）时渲染与旧版逐字节一致。
class _LvRing extends StatelessWidget {
  const _LvRing({required this.lv, required this.ratio, this.flash = 0, this.pop = 1});

  final int lv;
  final double ratio;

  /// 白闪强度（0~1；1 ≙ 峰值 16% 白）
  final double flash;

  /// LV 数字的弹跳（1 = 原大）
  final double pop;

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
            child: pop == 1
                ? _lvText()
                : Transform.scale(scale: pop, child: _lvText()),
          ),
          // 跨级白闪：环上炸开一朵 16% 白（FlashBloom 与 #flash 同源）
          if (flash > 0)
            Positioned.fill(
              key: const Key('hud.flash'),
              child: FlashBloom(alpha: flash),
            ),
        ],
      ),
    );
  }

  Widget _lvText() {
    return Text(
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
          '「${HostTitle.nameOf(state.title)}」',
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
      ],
    );
  }
}

/// 连击药丸（宿主 2026-10-11：「主界面这个联机……给它换个位置，换到这个委托的上方一点」）。
///
/// 原先是 `.hud-who` 里的第三行（名字 / 称号 / 连击），压在左上角那一小块里、
/// 和称号挤在一起看不出分量。现在把它**摘出来单独一颗**，贴在顶栏下沿居中：
/// 既离开了那个角落，又稳稳落在委托卡上方（派单板与执行面板都在屏幕下三分之一）。
///
/// 读数照旧：`连击 <b>N</b> 天`（数字走 Tektur），0 连击显示破折号。
class StreakPill extends StatelessWidget {
  const StreakPill({super.key, required this.streak, this.visible = true});

  /// 当前连击天数（0 = 还没连上）
  final int streak;

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      // ⚠️ 位置踩过一次坑：原先贴顶栏下沿**居中**（top 46），结果正撞在
      //    「执行中 00:59」那颗计时药丸上（它 top:80、也居中）—— 两颗药丸叠在一起。
      //    现在**右上角**、压在金币与菜单那一列上方：既离开了左上角那个小方块，
      //    又和居中的计时药丸彻底错开。
      top: 30,
      right: 16,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          curve: kOut,
          child: Align(
            alignment: Alignment.topRight,
            child: Container(
              key: const Key('hud.streak'),
              padding: const EdgeInsets.fromLTRB(11, 5, 11, 5),
              decoration: BoxDecoration(
                color: const Color(0xB3040E20), // rgba(4,14,32,.7)：与对话圆钮同款玻璃
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: C.line2, width: 1),
              ),
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: streak > 0 ? '连击 ' : '连击 —',
                      style: fs(
                        family: F.mono,
                        size: 9.5,
                        wght: 500,
                        ls: .95,
                        height: 1,
                        color: C.mist,
                      ),
                    ),
                    if (streak > 0) ...<InlineSpan>[
                      TextSpan(
                        text: '$streak',
                        style: fs(
                          family: F.num,
                          size: 11,
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
            ),
          ),
        ),
      ),
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
  const _Menu({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: _bars(),
    );
  }

  Widget _bars() {
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
