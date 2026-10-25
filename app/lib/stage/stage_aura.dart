import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../design/fidelity.dart';
import '../design/tokens.dart' hide StageAnchors;
import 'camera.dart';

/// ═══════════════════════════════════════════════════════════
///  舞台光（docs/48 §2「Live2D 舞台化」）
///
///  她是主角，所以她身后/脚下有一整套**只为她服务**的灯光：
///
///   ① 暗角      —— 以她胸口为圆心，屏幕四周压暗：视线自然收向她
///   ② 背光晕    —— 头与胸之间一团冷青辉光（跟情绪换色、跟心跳呼吸）
///   ③ 顶光束    —— 自屏顶落到她脚下的一道极淡光锥（舞台追光）
///   ④ 暖边光    —— 右上方一团暖色 key light（她被「照亮」而不是「贴上去」）
///   ⑤ 地台      —— 脚下一圈透视椭圆：落地阴影 + 三道环 + 旋转刻度 + 扫描弧
///   ⑥ 浮尘      —— 光锥里缓缓上升的十几粒光点（只在富效果档）
///   ⑦ 脉冲      —— 戳她 / 落定时，从地台扩散一圈光环、背光闪亮一拍
///
///  全部画在**一张**画布上（一个 CustomPainter），位置全部由相机 [Cam]
///  反算（与 Live2D 平台视图、进度环同源），镜头推到哪光就跟到哪。
///
///  层级：天幕之上、**她之下**（main.dart）—— 光永远在她身后，不盖她。
///
///  性能：
///   · 画布外包 RepaintBoundary；painter 只订阅 cam + 自己的帧号，widget 树不动
///   · 逐帧循环只在 [FxLevel.rich] 开，且**限到 30fps**（光的呼吸不需要 60）
///   · 省电 / 减弱动态效果：画一帧静态的光，不开 ticker（零逐帧成本）
///   · 不用 MaskFilter.blur / saveLayer：柔边全部用径向渐变出（便宜且稳定）
/// ═══════════════════════════════════════════════════════════
class StageAura extends StatefulWidget {
  const StageAura({
    super.key,
    required this.cam,
    this.mood = StageMood.calm,
    this.pulse = 0,
    this.intensity = 1,
    this.showDais = true,
  });

  /// 相机（与 Live2DStage 同一个 ValueNotifier）
  final ValueListenable<Cam> cam;

  final StageMood mood;

  /// 脉冲令牌：每 +1 播一次「光环扩散 + 背光闪亮」
  final int pulse;

  /// 整体亮度 0~1（派单/结算压暗时调低，让 UI 说话）
  final double intensity;

  /// 地台（主线页/面板态她脚下被 UI 盖住时可以关掉省一笔）
  final bool showDais;

  @override
  State<StageAura> createState() => _StageAuraState();
}

class _StageAuraState extends State<StageAura> with TickerProviderStateMixin {
  /// 帧时钟（秒）。painter 订阅它；30fps 节流在 [_onTick]。
  final ValueNotifier<double> _t = ValueNotifier<double>(0);
  Ticker? _ticker;
  Duration _lastPaint = Duration.zero;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// 情绪色过渡（700ms）
  late final AnimationController _moodT = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..value = 1;
  late Color _fromHalo = Pal.moodHalo(widget.mood);
  late Color _toHalo = Pal.moodHalo(widget.mood);

  late final AnimationController _int = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: Motion.sceneChromeMs),
    value: widget.intensity,
  );

  FxLevel _level = FxLevel.rich;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLevel();
  }

  @override
  void initState() {
    super.initState();
    Fidelity.lowPower.addListener(_syncLevel);
  }

  void _syncLevel() {
    if (!mounted) return;
    final FxLevel lv = Fidelity.of(context);
    _level = lv;
    if (lv == FxLevel.rich) {
      _ticker ??= createTicker(_onTick);
      if (!_ticker!.isActive) _ticker!.start();
    } else {
      _ticker?.stop();
      _t.value = 1.7; // 静态帧取一个好看的相位
    }
  }

  void _onTick(Duration e) {
    if (e - _lastPaint < const Duration(milliseconds: 33)) return;
    _lastPaint = e;
    _t.value = e.inMicroseconds / 1e6;
  }

  @override
  void didUpdateWidget(covariant StageAura old) {
    super.didUpdateWidget(old);
    if (old.pulse != widget.pulse && _level != FxLevel.still) {
      _pulse.forward(from: 0);
    }
    if (old.mood != widget.mood) {
      _fromHalo = Color.lerp(_fromHalo, _toHalo, _moodT.value)!;
      _toHalo = Pal.moodHalo(widget.mood);
      if (_level == FxLevel.still) {
        _moodT.value = 1;
      } else {
        _moodT.forward(from: 0);
      }
    }
    if (old.intensity != widget.intensity) {
      _int.animateTo(widget.intensity, curve: Ease.glide);
    }
  }

  @override
  void dispose() {
    Fidelity.lowPower.removeListener(_syncLevel);
    _ticker?.dispose();
    _pulse.dispose();
    _moodT.dispose();
    _int.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            key: const Key('stage.aura'),
            painter: StageAuraPainter(
              cam: widget.cam,
              t: _t,
              pulse: _pulse,
              moodT: _moodT,
              intensity: _int,
              fromHalo: _fromHalo,
              toHalo: _toHalo,
              mood: widget.mood,
              motes: _level == FxLevel.rich,
              showDais: widget.showDais,
            ),
          ),
        ),
      ),
    );
  }
}

/// 舞台光画家（公开：测试与「卡片陈列页」可以单独画它）
class StageAuraPainter extends CustomPainter {
  StageAuraPainter({
    required this.cam,
    required this.t,
    required this.pulse,
    required this.moodT,
    required this.intensity,
    required this.fromHalo,
    required this.toHalo,
    required this.mood,
    required this.motes,
    required this.showDais,
  }) : super(
         repaint: Listenable.merge(<Listenable>[
           cam,
           t,
           pulse,
           moodT,
           intensity,
         ]),
       );

  final ValueListenable<Cam> cam;
  final ValueListenable<double> t;
  final Animation<double> pulse;
  final Animation<double> moodT;
  final Animation<double> intensity;
  final Color fromHalo;
  final Color toHalo;
  final StageMood mood;
  final bool motes;
  final bool showDais;

  static Color _a(Color c, double a) =>
      c.withAlpha((a.clamp(0.0, 1.0) * 255).round());

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Cam c = cam.value;
    final double unit = c.scale(size.height); // 世界 1 单位 = 多少 px
    final Offset head = c.toScreen(0, StageAnchors.hair, size);
    final Offset chest = c.toScreen(0, StageAnchors.chest, size);
    final Offset feet = c.toScreen(0, StageAnchors.feet + .04, size);
    final double time = t.value;
    final double k = intensity.value.clamp(0.0, 1.0);
    final Color halo = Color.lerp(fromHalo, toHalo, moodT.value)!;
    final double p = pulse.value; // 0~1
    final double pulseLift = p <= 0 ? 0 : math.sin(p * math.pi) * (1 - p * .4);

    // 呼吸：心跳 2.4s 一拍；专注时快一点，睡着慢一点
    final double period = switch (mood) {
      StageMood.focus => 1.9,
      StageMood.sleep => 4.2,
      StageMood.reward => 1.6,
      _ => Motion.heartMs / 1000,
    };
    final double breath = .5 + .5 * math.sin(time * 2 * math.pi / period);

    // ① 暗角：以她胸口为心，边缘压暗（画在她身后，所以不会把她压暗）
    final double vr = size.longestSide * .78;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            _a(Pal.ink0, 0),
            _a(Pal.ink0, .18 + .12 * (1 - k)),
            _a(Pal.ink0, .62),
          ],
          stops: const <double>[.35, .7, 1],
        ).createShader(Rect.fromCircle(center: chest, radius: vr)),
    );

    // ③ 顶光束：屏顶 → 她脚下的窄光锥
    final double topHalf = unit * .16;
    final double footHalf = unit * .82;
    final double coneBottom = math.min(feet.dy + unit * .08, size.height + 40);
    final Path cone = Path()
      ..moveTo(head.dx - topHalf, 0)
      ..lineTo(head.dx + topHalf, 0)
      ..lineTo(head.dx + footHalf, coneBottom)
      ..lineTo(head.dx - footHalf, coneBottom)
      ..close();
    final double flicker =
        .85 + .15 * math.sin(time * 1.3) * math.sin(time * .7 + 1);
    canvas.drawPath(
      cone,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            _a(Colors.white, .055 * k * flicker),
            _a(halo, .045 * k * flicker),
            _a(halo, .0),
          ],
          stops: const <double>[0, .62, 1],
        ).createShader(Rect.fromLTRB(0, 0, size.width, coneBottom)),
    );

    // ② 背光晕：头胸之间，呼吸 ±15%
    final Offset haloC = Offset(head.dx, head.dy + (chest.dy - head.dy) * .55);
    final double haloR = unit * (1.02 + .05 * breath + .12 * pulseLift);
    canvas.drawCircle(
      haloC,
      haloR,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            _a(halo, (.26 + .06 * breath + .22 * pulseLift) * k),
            _a(halo, (.09 + .02 * breath) * k),
            _a(halo, 0),
          ],
          stops: const <double>[0, .45, 1],
        ).createShader(Rect.fromCircle(center: haloC, radius: haloR)),
    );

    // ④ 暖边光：右上方
    final Offset rimC = Offset(head.dx + unit * .55, head.dy - unit * .05);
    final double rimR = unit * .9;
    canvas.drawCircle(
      rimC,
      rimR,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            _a(mood == StageMood.fail ? Pal.text4 : Pal.rim, .10 * k),
            _a(Pal.rim, 0),
          ],
        ).createShader(Rect.fromCircle(center: rimC, radius: rimR)),
    );

    // ⑤ 地台（脚在画外就不画）
    if (showDais && feet.dy < size.height + unit * .3) {
      _dais(canvas, size, feet, unit, halo, time, k, breath, p);
    }

    // ⑥ 浮尘
    if (motes && k > .05) {
      _motes(canvas, head, feet, unit, halo, time, k);
    }
  }

  void _dais(
    Canvas canvas,
    Size size,
    Offset feet,
    double unit,
    Color halo,
    double time,
    double k,
    double breath,
    double p,
  ) {
    final double rx = unit * .78;
    const double squash = .24; // 透视压扁
    canvas.save();
    canvas.translate(feet.dx, feet.dy);
    canvas.scale(1, squash);

    // 地面辉光（大）
    canvas.drawCircle(
      Offset.zero,
      rx * 1.5,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            _a(halo, (.30 + .06 * breath) * k),
            _a(halo, .08 * k),
            _a(halo, 0),
          ],
          stops: const <double>[0, .5, 1],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: rx * 1.5)),
    );
    // 落地阴影（她站得住的关键）
    canvas.drawCircle(
      Offset.zero,
      rx * .5,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[_a(Pal.ink0, .70), _a(Pal.ink0, 0)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: rx * .5)),
    );

    // 三道环（压扁后自然成透视椭圆）—— 描边宽度要除以 squash 补偿
    final Paint ring = Paint()..style = PaintingStyle.stroke;
    for (final (double r, double a) in <(double, double)>[
      (.62, .38),
      (.86, .22),
      (1.1, .12),
    ]) {
      ring
        ..strokeWidth = 1.1 / squash * .55
        ..color = _a(halo, a * k);
      canvas.drawCircle(Offset.zero, rx * r, ring);
    }

    // 旋转刻度环：后半圈暗、前半圈亮（透视的「近亮远暗」）
    const int ticks = 56;
    final double rot = time * .18;
    final Paint tick = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < ticks; i++) {
      final double a = rot + i * 2 * math.pi / ticks;
      final double front = .5 + .5 * math.sin(a); // sin>0 = 靠近观众（下半）
      final double len = i % 7 == 0 ? .075 : .035;
      tick.color = _a(halo, (.10 + .38 * front) * k);
      final Offset dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(dir * (rx * .97), dir * (rx * (.97 + len)), tick);
    }

    // 扫描弧：一段亮弧绕地台走
    final double sweepA = time * .9;
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: rx * .86),
      sweepA,
      .9,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 / squash * .5
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: sweepA,
          endAngle: sweepA + .9,
          colors: <Color>[_a(halo, 0), _a(Colors.white, .55 * k)],
          transform: GradientRotation(0),
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: rx)),
    );

    // ⑦ 脉冲：一圈光环扩散
    if (p > 0 && p < 1) {
      final double e = Curves.easeOutCubic.transform(p);
      canvas.drawCircle(
        Offset.zero,
        rx * (.45 + 1.4 * e),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (3 * (1 - e) + .6) / squash * .5
          ..color = _a(Color.lerp(halo, Colors.white, .4)!, .75 * (1 - e)),
      );
    }
    canvas.restore();
  }

  void _motes(
    Canvas canvas,
    Offset head,
    Offset feet,
    double unit,
    Color halo,
    double time,
    double k,
  ) {
    final double span = (feet.dy - head.dy).abs().clamp(80.0, 2000.0);
    final Paint dot = Paint();
    for (int i = 0; i < 16; i++) {
      // 确定性伪随机：每粒有自己的周期 / 横向位置 / 摆幅
      final double seed = (i * 0.61803398875) % 1;
      final double seed2 = (i * 0.41421356237 + .3) % 1;
      final double period = 6 + seed * 6;
      final double ph = ((time + seed2 * period) % period) / period; // 0~1
      final double y = feet.dy - ph * span * 1.05;
      final double x =
          feet.dx +
          (seed - .5) * unit * 1.3 * (1 - ph * .5) +
          math.sin(time * .8 + i) * unit * .04;
      final double env = math.sin(ph * math.pi); // 出生/消亡淡入淡出
      final double r = 0.9 + seed2 * 1.4;
      dot.color = _a(Color.lerp(halo, Colors.white, .5)!, .55 * env * k);
      canvas.drawCircle(Offset(x, y), r, dot);
    }
  }

  @override
  bool shouldRepaint(StageAuraPainter old) =>
      old.fromHalo != fromHalo ||
      old.toHalo != toHalo ||
      old.mood != mood ||
      old.motes != motes ||
      old.showDais != showDais ||
      old.cam != cam;
}
