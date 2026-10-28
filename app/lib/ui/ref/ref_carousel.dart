import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// ═══════════════════════════════════════════════════════════
///  3D 卡轮播 —— 参考稿 `Carousel()`（JS L1190-1226）
///
///  一套物理同时喂主线大牌（#mainCar）与补给货架（#shopCar）：
///   · 尺寸：cw = min(W × wf, max)，ch = cw / ar；ch 超过 H − pad 时按高收
///   · 每张卡：d = i − pos，a = |d|
///       x  = sign(d)·(min(a,1)·cw·.74 + max(0,a−1)·cw·.2)
///       y  = min(a,3)·16 ；z = −min(a,4)·150
///       ry = −clamp(d,±1.5)·26° ；rz = d·3° ；scale = 1 − min(a,3)·.07
///       perspective 1100
///   · 追随：每帧 pos += (target − pos)·.15（这里按帧率归一）
///   · 拖拽：pos = clamp(p0 − dx/(cw·.74), −.35, n − .65)；
///     松手 target = round(pos − v·200/(cw·.74))（v = px/ms，半衰平滑）
///   · 位移 < 6px 算点：点中焦点卡 → onTap；点中侧卡 → 转过去
///   · shade 模式（主线）：卡面压暗 sh = min(a,1.4)·.5，a > 2.6 渐隐
///     非 shade（补给）：brightness(1 − min(a,1.4)·.42)，同样渐隐
///   · 入场：每张 translateY(90) rotateX(−25°) scale(.82) → 原位，
///     700ms，delay 200 + |i − start|·90，cubic(.2,1.1,.3,1)
///
///  性能：卡面包 RepaintBoundary，拖拽只改 Transform（合成层），
///  不重画卡面；物理用一颗 Ticker，静止即停。
/// ═══════════════════════════════════════════════════════════
class RefCarouselController extends ChangeNotifier {
  _RefCarouselState? _s;

  /// 当前焦点（四舍五入后的 pos）
  int get index => _s?._idx ?? 0;

  void go(int i) => _s?._goTo(i);
  void next(int d) => _s?._goTo(((_s?._target ?? 0).round()) + d);
}

/// 卡面渲染时拿到的「这张卡此刻的状态」
class RefCarouselSlot {
  const RefCarouselSlot({
    required this.focus,
    required this.compact,
    required this.shade,
    required this.width,
    required this.height,
  });

  /// a < .5
  final bool focus;

  /// ch < compactH（矮屏紧凑版）
  final bool compact;

  /// 0..1：卡面要盖的暗度（shade 模式 = `--sh`；否则 = brightness 的补）
  final double shade;
  final double width;
  final double height;
}

class RefCarousel extends StatefulWidget {
  const RefCarousel({
    super.key,
    required this.count,
    required this.itemBuilder,
    this.start = 0,
    this.ar = .7,
    this.wf = .62,
    this.maxW = 270,
    this.pad = 24,
    this.shadeMode = false,
    this.compactH,
    this.onFocus,
    this.onTap,
    this.controller,
    this.dealIn = true,
    this.underlay,
  });

  final int count;
  final Widget Function(BuildContext context, int i, RefCarouselSlot slot)
  itemBuilder;
  final int start;
  final double ar;
  final double wf;
  final double maxW;
  final double pad;
  final bool shadeMode;
  final double? compactH;
  final ValueChanged<int>? onFocus;
  final ValueChanged<int>? onTap;
  final RefCarouselController? controller;
  final bool dealIn;

  /// 垫在所有卡下面的一层（主线的 .ped 光台）
  final Widget? underlay;

  @override
  State<RefCarousel> createState() => _RefCarouselState();
}

class _RefCarouselState extends State<RefCarousel>
    with TickerProviderStateMixin {
  late double _pos = widget.start.toDouble();
  late double _target = widget.start.toDouble();
  int _idx = -1;
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  // 拖拽
  bool _drag = false;
  double _dx0 = 0;
  double _p0 = 0;
  double _lx = 0;
  int _lt = 0;
  double _v = 0;
  double _moved = 0;
  int? _downCard;

  double _cw = 0;
  double _ch = 0;

  late final AnimationController _deal = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 900 + 90 * math.max(1, widget.count)),
  );

  static const Cubic _dealCurve = Cubic(.2, 1.1, .3, 1);

  @override
  void initState() {
    super.initState();
    widget.controller?._s = this;
    _idx = _pos.round().clamp(0, math.max(0, widget.count - 1));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onFocus?.call(_idx);
    });
    final bool reduce = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    if (widget.dealIn && !reduce) {
      _deal.forward();
    } else {
      _deal.value = 1;
    }
  }

  @override
  void didUpdateWidget(RefCarousel old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._s = null;
      widget.controller?._s = this;
    }
    if (widget.count != old.count) {
      _target = _target.clamp(0, math.max(0, widget.count - 1)).toDouble();
      _pos = _pos.clamp(-.35, math.max(0, widget.count - .65)).toDouble();
      _kick();
    }
  }

  @override
  void dispose() {
    if (widget.controller?._s == this) widget.controller?._s = null;
    _ticker.dispose();
    _deal.dispose();
    super.dispose();
  }

  void _goTo(int i) {
    _target = i.clamp(0, math.max(0, widget.count - 1)).toDouble();
    _kick();
  }

  void _kick() {
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration now) {
    final double dt = _last == Duration.zero
        ? 1 / 60
        : (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (!_drag) {
      final double d = _target - _pos;
      // 参考稿每帧 .15（60fps）→ 帧率无关：1 − .85^(dt·60)
      final double k = 1 - math.pow(.85, (dt * 60).clamp(0, 4)).toDouble();
      _pos += d * k;
      if ((_target - _pos).abs() < .0008) _pos = _target;
    }
    final int idx = _pos.round().clamp(0, math.max(0, widget.count - 1));
    if (idx != _idx) {
      _idx = idx;
      widget.onFocus?.call(idx);
    }
    setState(() {});
    if (!_drag && _pos == _target) _ticker.stop();
  }

  void _down(PointerDownEvent e) {
    _drag = true;
    _dx0 = e.position.dx;
    _p0 = _pos;
    _lx = e.position.dx;
    _lt = e.timeStamp.inMilliseconds;
    _v = 0;
    _moved = 0;
    _kick();
  }

  void _move(PointerMoveEvent e) {
    if (!_drag || _cw <= 0) return;
    final double dx = e.position.dx - _dx0;
    final int now = e.timeStamp.inMilliseconds;
    _moved = math.max(_moved, dx.abs());
    _v = _v * .5 + ((e.position.dx - _lx) / math.max(1, now - _lt)) * .5;
    _lx = e.position.dx;
    _lt = now;
    _pos = (_p0 - dx / (_cw * .74)).clamp(-.35, widget.count - .65).toDouble();
    _kick();
  }

  void _up(PointerEvent e) {
    if (!_drag) return;
    _drag = false;
    if (_moved < 6) {
      final int? c = _downCard;
      if (c != null) {
        if (c == _idx) {
          widget.onTap?.call(c);
        } else {
          _goTo(c);
        }
      }
    } else if (_cw > 0) {
      _target = (_pos - _v * 200 / (_cw * .74))
          .round()
          .clamp(0, math.max(0, widget.count - 1))
          .toDouble();
    }
    _downCard = null;
    _kick();
  }

  Matrix4 _matrixFor(int i, double a, double d) {
    final double s = d.sign;
    final double x =
        s * (math.min(a, 1) * _cw * .74 + math.max(0, a - 1) * _cw * .2);
    final double y = math.min(a, 3) * 16;
    final double z = -math.min(a, 4) * 150;
    final double ry = -d.clamp(-1.5, 1.5) * 26 * math.pi / 180;
    final double rz = d * 3 * math.pi / 180;
    final double sc = 1 - math.min(a, 3) * .07;
    final Matrix4 m = Matrix4.identity()
      ..setEntry(3, 2, -1 / 1100)
      ..translateByDouble(x, y, z, 1)
      ..rotateY(ry)
      ..rotateZ(rz)
      ..scaleByDouble(sc, sc, sc, 1);
    return m;
  }

  /// 入场：translateY(90) rotateX(−25°) scale(.82)，opacity 0 → 1
  Matrix4 _dealMatrix(double k) {
    final double t = 1 - k;
    return Matrix4.identity()
      ..setEntry(3, 2, -1 / 1100)
      ..translateByDouble(0, 90 * t, 0, 1)
      ..rotateX(-25 * math.pi / 180 * t)
      ..scaleByDouble(1 - .18 * t, 1 - .18 * t, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final int n = widget.count;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double W = box.maxWidth;
        final double H = box.maxHeight;
        double cw = math.min(W * widget.wf, widget.maxW);
        double ch = cw / widget.ar;
        if (ch > H - widget.pad) {
          ch = math.max(0, H - widget.pad);
          cw = ch * widget.ar;
        }
        _cw = cw;
        _ch = ch;
        final bool compact = widget.compactH != null && ch < widget.compactH!;
        final double left = (W - cw) / 2;
        final double top = (H - ch) / 2;

        // 远的先画（z-index = 100 − round(a·10)）
        final List<int> order = List<int>.generate(n, (int i) => i)
          ..sort((int p, int q) {
            final double ap = (p - _pos).abs();
            final double aq = (q - _pos).abs();
            return aq.compareTo(ap);
          });

        final List<Widget> kids = <Widget>[
          if (widget.underlay != null) Positioned.fill(child: widget.underlay!),
        ];
        for (final int i in order) {
          final double d = i - _pos;
          final double a = d.abs();
          // a > 3.6 完全看不见：不建树
          if (a > 3.25) continue;
          final double op = a > 2.6 ? math.max(0, 3.2 - a) : 1;
          final double shade = widget.shadeMode
              ? math.min(a, 1.4) * .5
              : math.min(a, 1.4) * .42;
          final RefCarouselSlot slot = RefCarouselSlot(
            focus: a < .5,
            compact: compact,
            shade: shade,
            width: cw,
            height: ch,
          );
          Widget card = RepaintBoundary(
            child: SizedBox(
              width: cw,
              height: ch,
              child: widget.itemBuilder(context, i, slot),
            ),
          );
          if (op < 1) card = Opacity(opacity: op.clamp(0, 1), child: card);
          // ⚠️ Listener 必须在 Transform **里面**：RenderTransform 不按自身
          //    未变换的矩形判命中，而是把点逆变换给孩子 —— 侧卡才点得中。
          card = Transform(
            alignment: const Alignment(0, .2), // transform-origin: 50% 60%
            transform: _matrixFor(i, a, d),
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => _downCard = i,
              child: card,
            ),
          );
          // 入场
          card = AnimatedBuilder(
            animation: _deal,
            child: card,
            builder: (BuildContext _, Widget? c) {
              if (_deal.value >= 1) return c!;
              final int total = _deal.duration!.inMilliseconds;
              final double startMs = 200.0 + (i - widget.start).abs() * 90.0;
              final double k = ((_deal.value * total - startMs) / 700).clamp(
                0.0,
                1.0,
              );
              final double e = _dealCurve.transform(k);
              if (e >= 1) return c!;
              return Transform(
                alignment: Alignment.center,
                transform: _dealMatrix(e),
                child: Opacity(opacity: k.clamp(0.0, 1.0), child: c),
              );
            },
          );
          kids.add(
            Positioned(
              left: left,
              top: top,
              width: cw,
              height: ch,
              child: card,
            ),
          );
        }

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _up,
          onPointerSignal: (PointerSignalEvent e) {
            if (e is PointerScrollEvent) {
              final double dd = e.scrollDelta.dx.abs() > e.scrollDelta.dy.abs()
                  ? e.scrollDelta.dx
                  : e.scrollDelta.dy;
              if (dd.abs() >= 4) _goTo(_target.round() + (dd > 0 ? 1 : -1));
            }
          },
          child: Stack(clipBehavior: Clip.none, children: kids),
        );
      },
    );
  }

  double get cardHeight => _ch;
}
