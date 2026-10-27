import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/titles.dart';
import '../design/tokens.dart';
import '../state/haptics.dart';
import '../state/host_state.dart';
import '../state/sfx.dart';
import 'fx_layer.dart';
import 'rail_base.dart';
import 'sys_icons.dart';

/// ═══════════════════════════════════════════════════════════
///  HUD（app.css L94-117 #hud）
///  等级环 + 名字/称号/连击 + 金币 + 菜单。
///  实测盒模型（390×844，**docs/39 §3.1 H-02…H-06 的新规格**）：
///    hud [0,0,390,74] · 左右边距 20 · lv [20,22,48,48]
///    name 起点 78（20 + 48 + 10；H-02 的 76 是按 46 的环算的 —— H-03 把环
///    抬到 48 后保持同一个 10pt 间隙，名字自然落到 78）
///    coin 右缘 326 / top 30 / 高 32 · menu 视觉 [336,29,34,34]（命中盒 44）
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
  /// 本 build 的顶层就是 Positioned（ParentDataWidget），外面再包一层
  /// 带 RenderObject 的包装件会报 Incorrect use of ParentDataWidget
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

/// docs/39 H-01 · 顶部承托的高度（压在 HUD 盒 74 之上、到她眉眼上方为止）
const double kHudScrimH = 116;

/// 跨级编排的相位函数（纯函数，可单测）：给时刻 t（0~kLvTotalMs），
/// 算等级环此刻该显示成什么样。
///
///  · t < 360：旧环比往满环涨（easeOutCubic），级数还是旧级；
///  · t = 360：白闪起（峰值 16%，180ms ease-out 衰减）+ 级数切到新级
///    （数字 1.3→1 弹一下）+ 环归零；
///  · t ∈ (360, 780]：从 0 涨到新档余额（easeOutCubic，420ms）。
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
    final double k = Curves.easeOutCubic.transform(
      (t / kLvRiseMs).clamp(0.0, 1.0),
    );
    return (
      lv: fromLv,
      ratio: fromRatio + (1 - fromRatio) * k,
      flash: 0,
      pop: 1,
    );
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
    // 升级（flows.js:485 levelUp(lv)）：
    // Sound.play('levelup'); FX.flash('#e9fbff', .2, 260); buzz([30, 50, 30, 50])
    // —— 这一拍就是本工程里"升级"的唯一相位（结算的 res.ups 在 result_panel 里
    // 不建模）：HUD 在前台就是升级那一帧、被结算页压住就攒到回大厅补播的那一帧。
    // _play() 只在 _pending 翻假时被调一次（跨级、且只跨一级攒一拍），不会连发。
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
          child: Stack(
            // H-01 的承托比 HUD 盒（74）高出一截，必须允许画到盒外
            clipBehavior: Clip.none,
            children: <Widget>[
              // docs/39 H-01 · 顶部压暗：她之上、HUD 之下的一层承托。
              // 没有它名字/称号直接压在浅灰蓝头发上（真机图 01/05）。
              // 不压脸：116 只盖到她眉眼上方，脸（屏高 10%~30%）不受影响。
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: kHudScrimH,
                child: IgnorePointer(child: _TopScrim()),
              ),
              Padding(
                // docs/39 H-02：左右边距统一 20（原 16/18），高 74 不变
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
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
                    // docs/39 H-06：菜单的透明命中盒是 44（视觉仍 34、右对齐）——
                    // 多出来的 10 全落在它左边，所以这里不再另给 10：
                    // 胶囊右缘 326、汉堡条视觉左缘 336，观感间距仍是 10pt。
                    _Menu(onTap: widget.onMenu),
                  ],
                ),
              ),
            ],
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
    return Positioned(left: 0, right: 0, top: 0, height: 74, child: body);
  }
}

/// docs/39 H-01 · 顶部压暗渐变：#020610 α .78 → 0（top→bottom）。
/// 它是 HUD 的**承托**，不是氛围层：只买对比度，不循环、不吃点击。
class _TopScrim extends StatelessWidget {
  const _TopScrim();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      key: Key('hud.scrim'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xC7020610), Color(0x00020610)], // .78 → 0
        ),
      ),
    );
  }
}

/// .hud-lv —— 六边等级牌上的经验环（app.css L98-104）
///
/// flash/pop 是跨级白闪那 780ms 里的临时参数（见 [hudLevelFx]）；
/// 缺省（静态）时渲染与旧版逐字节一致。
class _LvRing extends StatelessWidget {
  const _LvRing({
    required this.lv,
    required this.ratio,
    this.flash = 0,
    this.pop = 1,
  });

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
      // docs/39 H-03：46 → 48（viewBox 48 现在 1:1，环不再被整体缩小）
      width: 48,
      height: 48,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: CustomPaint(
              // 静态辉光 .78 / blur 2（H-03）；跨级那拍才全亮
              painter: _LvRingPainter(ratio: ratio, lit: flash > 0 ? 1 : .78),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 9.5,
            child: Text(
              'LV',
              textAlign: TextAlign.center,
              style: fs(
                family: F.mono,
                size: 8.5, // H-03：7.5 → 8.5
                wght: 600,
                ls: 1.7, // .2em
                height: 1,
                color: C.mist,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 18.5,
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
        size: 20, // H-03：19 → 20
        wght: 800,
        height: 1,
        color: C.ice,
        shadows: <Shadow>[Shadow(color: C.blue.withAlpha(153), blurRadius: 10)],
      ),
    );
  }
}

/// SVG viewBox 48×48 画在 48×48 的盒子里（1:1）；r=20、stroke 3、周长 125.66
class _LvRingPainter extends CustomPainter {
  const _LvRingPainter({required this.ratio, this.lit = .78});

  final double ratio;

  /// 静态辉光强度（H-03：静态 .78；跨级那拍给 1 = 全亮）
  final double lit;

  static const double _vb = 48; // viewBox
  static const double _r = 20;
  static const double _sw = 3; // H-03：2.6 → 3

  @override
  void paint(Canvas canvas, Size s) {
    final double k = s.width / _vb;
    final Offset c = Offset(s.width / 2, s.height / 2);
    final double r = _r * k;
    final Rect rect = Rect.fromCircle(center: c, radius: r);

    // docs/48 §4「HUD 是仪表，不是图标」：
    // ① 内盘：一枚有深度的暗色表盘（中心微亮 → 边缘沉）
    canvas.drawCircle(
      c,
      r - _sw * k * .5,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -.35),
          colors: <Color>[Pal.ink3, Pal.ink1.withAlpha(235)],
        ).createShader(rect),
    );
    // ② 外圈刻度：36 格，每 9 格一根长刻（游戏仪表的读数感）
    final Paint tick = Paint()
      ..strokeWidth = .9 * k
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 36; i++) {
      final double a = -math.pi / 2 + i * math.pi / 18;
      final bool major = i % 9 == 0;
      tick.color = C.blue.withAlpha(major ? 120 : 40);
      final double r0 = r + _sw * k * .5 + 1.2 * k;
      final double r1 = r0 + (major ? 2.4 : 1.2) * k;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * r0,
        c + Offset(math.cos(a), math.sin(a)) * r1,
        tick,
      );
    }
    // ③ 轨道
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
    if (sweep <= 0) return;
    // ④ 进度弧：深青 → 冰白的扫掠渐变（越接近升级越亮）
    final Paint arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _sw * k
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.max(sweep, .01),
        transform: const GradientRotation(start),
        colors: <Color>[const Color(0xFF1C8FD8), C.blue, C.ice],
        stops: const <double>[0, .7, 1],
      ).createShader(rect);
    // filter: drop-shadow —— H-03：静态 blur 2 / .78；跨级那拍全亮（3 / .9）
    final bool hot = lit >= 1;
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _sw * k
        ..strokeCap = StrokeCap.round
        ..color = C.blue
            .withAlpha(hot ? 230 : 199) // .9 / .78
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, hot ? 3 : 2),
    );
    canvas.drawArc(rect, start, sweep, false, arc);
    // ⑤ 弧头光点：经验条「正在走」的那一点
    final double ea = start + sweep;
    final Offset head = c + Offset(math.cos(ea), math.sin(ea)) * r;
    canvas.drawCircle(
      head,
      3.2 * k,
      Paint()
        ..color = C.ice.withAlpha(150)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    canvas.drawCircle(head, 1.5 * k, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _LvRingPainter o) =>
      o.ratio != ratio || o.lit != lit;
}

/// .hud-who —— 名字 / 称号 / 连击（app.css L105-109）
///
/// docs/39 H-04：名字 15 / 称号 11.5，两者都加一层黑色投影 —— 顶部压暗
/// （H-01）是承托，投影是给亮发上那几笔留的最后一层保险。
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
            size: 15, // H-04：14 → 15
            wght: 600,
            ls: .5,
            height: 1,
            color: C.ice,
            shadows: const <Shadow>[
              Shadow(
                color: Color(0x8C000000), // rgba(0,0,0,.55)
                blurRadius: 6,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '「${HostTitle.nameOf(state.title)}」',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: fs(
            family: F.cn,
            size: 11.5, // H-04：11 → 11.5
            wght: 400,
            ls: .2,
            height: 1,
            color: C.blue,
            shadows: const <Shadow>[
              Shadow(
                color: Color(0x8C000000),
                blurRadius: 6,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 连击药丸（宿主 2026-10-11：「主界面这个联机……给它换个位置，换到这个委托的上方一点」）。
///
/// 原先是 .hud-who 里的第三行（名字 / 称号 / 连击），压在左上角那一小块里、
/// 和称号挤在一起看不出分量。现在把它**摘出来单独一颗**，贴在顶栏下沿：
/// 既离开了那个角落，又稳稳落在委托卡上方（派单板与执行面板都在屏幕下三分之一）。
///
/// 读数照旧：连击 N 天（数字走 Tektur），0 连击显示破折号。
/// docs/39 H-07：宿主决定隐藏，本轮**不动**（main.dart 仍传 visible:false）。
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
///
/// docs/39 H-05：高 30→32、内边距 9/11、图标 14、数字 16（Tektur 700）、
/// 底 .55→.62、边 .12→.16；进账时 300ms count-up + 1.12→1 的 180ms 回弹。
class _Coin extends StatefulWidget {
  const _Coin({required this.coins});

  final int coins;

  @override
  State<_Coin> createState() => _CoinState();
}

class _CoinState extends State<_Coin> with SingleTickerProviderStateMixin {
  /// 1.12 → 1 的回弹（H-05 的 180ms）
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  /// 正在显示的数值（count-up 的起点），换数时从这里滚到新值
  late int _shown;
  late int _from;

  @override
  void initState() {
    super.initState();
    _shown = widget.coins;
    _from = widget.coins;
  }

  @override
  void didUpdateWidget(covariant _Coin old) {
    super.didUpdateWidget(old);
    if (old.coins != widget.coins) {
      _from = _shown;
      _shown = widget.coins;
      _pop.forward(from: 0); // 1.12 → 1 的回弹
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // docs/39 §5.5：reduced-motion 下只保留数字变化
    final bool reduce = railReduceMotion(context);
    return Container(
      key: const Key('hud.coin'),
      height: 32,
      // ⚠️ Flutter 的 Border 会占布局空间，CSS 的 inset box-shadow 不会 ——
      // 所以用 Border 模拟 inset 描边时，padding 要各减 1px 才与原型同宽。
      padding: const EdgeInsets.fromLTRB(9, 0, 11, 0),
      // docs/48 §4：货币 = 金色（全 App 唯一的暖色读数），与青色的
      // 经验 / 状态彻底分开 —— 一眼就知道「这是钱」。
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xD9251A08), Color(0xD90B0A10)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Pal.gold.withAlpha(96), width: 1),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Pal.gold.withAlpha(28), blurRadius: 12),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SvgPicture.string(kIconCoin, width: 14, height: 14),
          const SizedBox(width: 6),
          // 进账回弹：只缩**数字**（Transform 不吃布局，也不产生 saveLayer）
          AnimatedBuilder(
            animation: _pop,
            builder: (BuildContext _, Widget? child) {
              if (reduce || !_pop.isAnimating) return child!;
              final double k =
                  1 + .12 * (1 - Curves.easeOut.transform(_pop.value));
              return Transform.scale(scale: k, child: child);
            },
            // H-05：数值变化 300ms count-up（reduced-motion 直接落终值）
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: _from.toDouble(),
                end: _shown.toDouble(),
              ),
              duration: reduce
                  ? Duration.zero
                  : const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              builder: (BuildContext _, double v, Widget? _) => Text(
                v.round().toString(),
                style: fs(
                  family: F.num,
                  size: 16, // H-05：15 → 16
                  wght: 700,
                  ls: .45,
                  height: 1,
                  color: const Color(0xFFFFE7B0),
                  shadows: <Shadow>[
                    Shadow(color: Pal.gold.withAlpha(110), blurRadius: 8),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// .hud-menu —— 三根不等长的横杠（app.css L115-117）
///
/// docs/39 H-06：视觉不变（18/12/15，杠高 1.6→2），但**透明命中扩到 44×44**；
/// 按下 bars α .72、tap 音效、补 Semantics / tooltip —— 原先 34×34 又没有任何
/// 反馈，真机上「像装饰，不像按钮」。
class _Menu extends StatefulWidget {
  const _Menu({this.onTap});

  final VoidCallback? onTap;

  @override
  State<_Menu> createState() => _MenuState();
}

class _MenuState extends State<_Menu> {
  bool _down = false;

  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final bool on = widget.onTap != null;
    return Semantics(
      button: true,
      label: '系统设置',
      child: Tooltip(
        message: '系统设置',
        child: GestureDetector(
          onTap: on
              ? () {
                  Sfx.play('tap'); // docs/39 §5.4：菜单归 tap
                  widget.onTap!();
                }
              : null,
          onTapDown: on ? (_) => _set(true) : null,
          onTapUp: on ? (_) => _set(false) : null,
          onTapCancel: on ? () => _set(false) : null,
          behavior: HitTestBehavior.opaque,
          // 44×44 命中盒；里面那颗仍是原来的 34×34 视觉盒（右对齐，
          // 所以汉堡条相对右边距 20 的位置不变）—— hud.menu 记在视觉层。
          child: SizedBox(
            width: 44,
            height: 44,
            child: Align(alignment: Alignment.centerRight, child: _bars()),
          ),
        ),
      ),
    );
  }

  Widget _bars() {
    // docs/48 §4：汉堡条落在一块斜切小铭牌上（与 CTA / 卡角同一套切角语言）
    return Container(
      key: const Key('hud.menu'),
      width: 34,
      height: 34,
      decoration: ShapeDecoration(
        color: _down ? const Color(0xCC0E2340) : const Color(0x99060E1E),
        shape: BeveledRectangleBorder(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(8),
            bottomRight: Radius.circular(8),
          ),
          side: BorderSide(color: C.blue.withAlpha(_down ? 120 : 56)),
        ),
      ),
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
    height: 2, // H-06：1.6 → 2
    decoration: BoxDecoration(
      color: _down ? c.withAlpha(184) : c, // 按下 α .72
      borderRadius: BorderRadius.circular(1),
    ),
  );
}
