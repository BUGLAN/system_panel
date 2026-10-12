import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'spring.dart';

import 'dart:ui';

/// ═══════════════════════════════════════════════════════════
///  舞台摄像机 —— 真源 prototype/opus-v2-dir/js/stage.js L252-275。
///
///  原型是 WebGL 里的 Live2D，但**相机与环位的换算全是纯数学**：
///  把角色锚点（NY 表）投到屏幕上，就得到「环挂签」这些 DOM 元素该在哪。
///  这一层先落地，舞台本体（Live2D）上台时直接复用。
///
///  世界坐标：x 是横向、w 是纵向（越往上越大），单位是「她占满屏高 = 1.95」。
/// ═══════════════════════════════════════════════════════════

/// 角色锚点表（stage.js L17 的 `NY`）。
///
/// ⚠️ **这里写的是 Live2D 模型实测后的值，不是 stage.js 里那张静态表。**
/// 静态表是 `hair: .44 / shoulder: .01 / feet: -1.51 / chest: -.12`，
/// 模型加载后会被实测值覆盖，而 `camFit` 用的是覆盖后的跨度。
/// 拿静态表去算，环位 y 会差 0.2~0.4px —— 而 x 恰好不受影响，
/// 只看 x 会以为公式已经对上了（踩过）。
class StageAnchors {
  const StageAnchors._();

  /// 发际线（她头顶那一环的高度基准）
  static const double hair = .4386169977280048;

  static const double shoulder = .009626705462138396;

  static const double feet = -1.511338876207752;

  /// 胸口 —— 只给投影光束用（`NY.chest + .02`）
  static const double chest = -.10737064697400722;

  /// 她的整体高度（世界单位）—— 注意不是 1.95
  static const double bodySpan = hair - feet; // 1.9499558739357568
}

/// 一套相机预设：`S = camFit(H) × s`，`sx = W × sxF`，`sy = H × syF`
class Cam {
  const Cam(this.s, this.ax, this.ay, this.sxF, this.syF);

  final double s;
  final double ax;
  final double ay;
  final double sxF;
  final double syF;

  /// 她正好占满屏高时的 S（`camFit(H)`）
  static double camFit(double h) => h / StageAnchors.bodySpan;

  double scale(double h) => camFit(h) * s;

  Offset screenCenter(Size size) => Offset(size.width * sxF, size.height * syF);

  /// 世界 (x, w) → 屏幕 css px（stage.js L269）
  Offset toScreen(double x, double w, Size size) {
    final double sc = scale(size.height);
    final Offset c = screenCenter(size);
    return Offset(c.dx + (x - ax) * sc, c.dy + (ay - w) * sc);
  }

  /// 八个预设（stage.js L253-260）
  static const Map<String, Cam> all = <String, Cam>{
    'boot': Cam(.64, 0, -.30, .5, .444),
    'lobby': Cam(.92, 0, -.535, .5, .505),
    'talk': Cam(1.70, 0, .30, .5, .14),
    'exec': Cam(.72, 0, -.50, .76, .42),
    'result': Cam(1.05, 0, .18, .5, .26),
    'full': Cam(.68, 0, -.535, .46, .46),
    'panel': Cam(.88, 0, -.15, .5, .34),
    'fail': Cam(.72, 0, -.45, .5, .40),
  };

  static Cam byName(String name) => all[name] ?? all['lobby']!;
}

/// 一个环的椭圆参数（stage.js L368-380）
/// 相机的五个量各挂一根弹簧（`stage.js` L100-103）
///
/// ```js
/// this.cam = {
///   S:  new Spring(F * .62, 70, .95), ax: new Spring(0, 70, .95), ay: new Spring(-.3, 70, .95),
///   sx: new Spring(this.W / 2, 70, .95), sy: new Spring(this.H * .3, 70, .95),
/// };
/// ```
/// `setCam(name)` 只改**目标**，每帧 `step(dt)` 逼近 —— 所以切页是"推镜头"而不是瞬移。
/// ⚠️ 原型的 `setCam` 里 `snap` 为真时直接到位（换模型/尺寸变化后重设用）。
class CamSpring {
  CamSpring();

  /// 原型里五根都是 (70, .95)
  static const double stiff = 70;
  static const double zeta = .95;

  final Spring _s = Spring(k: stiff, zeta: zeta);
  final Spring _ax = Spring(k: stiff, zeta: zeta);
  final Spring _ay = Spring(k: stiff, zeta: zeta);
  final Spring _sx = Spring(k: stiff, zeta: zeta);
  final Spring _sy = Spring(k: stiff, zeta: zeta);

  String name = 'boot';
  Size _size = const Size(390, 844);
  bool _inited = false;

  Size get size => _size;

  /// ── 慢推（2026-10-11 宿主验收：「从这个小的 live2d 过渡到正常的 live2d，
  ///    它是直接切过去了，而不是慢慢地放大」）────────────────────────────
  ///
  /// 弹簧 (70, .95) 冲得快（约 0.5s 到位），配上唤醒那一拍亮帧/界面淡入，
  /// 观感就是"跳"过去。所以**换景别**这类要看得见的推镜头改走缓动补间：
  /// 五个量按 easeInOutCubic 从当前值慢慢推到目标值，时长由调用方给。
  ///
  /// 实现上每帧把「插值值」同时当作弹簧的目标并 snap 到位（v=0）——
  /// 于是过渡期间没有任何过冲/抖动，播完弹簧正好停在目标上（`done` 为真）。
  bool _gliding = false;
  double _glideT = 0; // 已走过的毫秒
  double _glideMs = 0;
  final List<double> _from = List<double>.filled(5, 0);
  final List<double> _to = List<double>.filled(5, 0);

  /// 缓动 = 原型 `ease.inOutCubic`（util.js），照抄那个式子
  static double _easeInOutCubic(double t) =>
      t < .5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;

  /// 正在慢推？（`done` 会把它算进去）
  bool get gliding => _gliding;

  /// 切到某个预设（`setCam(name, snap)`）
  void set(String camName, Size size, {bool snap = false}) {
    _size = size;
    name = camName;
    _gliding = false; // 新的硬切指令作废进行中的慢推
    final Cam c = Cam.byName(camName);
    final double sc = c.scale(size.height);
    final Offset center = c.screenCenter(size);
    _s.set(sc, snap: snap || !_inited);
    _ax.set(c.ax, snap: snap || !_inited);
    _ay.set(c.ay, snap: snap || !_inited);
    _sx.set(center.dx, snap: snap || !_inited);
    _sy.set(center.dy, snap: snap || !_inited);
    _inited = true;
  }

  /// 慢推到某个预设：把五个量按缓动从**当前值**推到目标，[ms] 是整段时长。
  /// 目标值 = `set` 会算出来的那一组（所以两者可以互换，落点完全一致）。
  void glideTo(String camName, Size size, {int ms = 1200}) {
    _size = size;
    name = camName;
    final Cam c = Cam.byName(camName);
    final Offset center = c.screenCenter(size);
    if (!_inited) {
      set(camName, size, snap: true);
      return;
    }
    _from[0] = _s.x;
    _from[1] = _ax.x;
    _from[2] = _ay.x;
    _from[3] = _sx.x;
    _from[4] = _sy.x;
    _to[0] = c.scale(size.height);
    _to[1] = c.ax;
    _to[2] = c.ay;
    _to[3] = center.dx;
    _to[4] = center.dy;
    _glideMs = ms.toDouble();
    _glideT = 0;
    _gliding = true;
  }

  /// 推进一帧
  void step(double dt) {
    if (_gliding) {
      _glideT += dt * 1000;
      final double t = _glideMs <= 0
          ? 1
          : (_glideT / _glideMs).clamp(0.0, 1.0);
      final double e = _easeInOutCubic(t);
      _s.set(_lerp(_from[0], _to[0], e), snap: true);
      _ax.set(_lerp(_from[1], _to[1], e), snap: true);
      _ay.set(_lerp(_from[2], _to[2], e), snap: true);
      _sx.set(_lerp(_from[3], _to[3], e), snap: true);
      _sy.set(_lerp(_from[4], _to[4], e), snap: true);
      if (t >= 1) {
        _gliding = false;
        _glideT = 0;
      }
      return;
    }
    _s.step(dt);
    _ax.step(dt);
    _ay.step(dt);
    _sx.step(dt);
    _sy.step(dt);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  bool get done =>
      !_gliding && _s.done && _ax.done && _ay.done && _sx.done && _sy.done;

  /// 当前这一帧的相机（尺寸变化时 sxF/syF 换算成分数）
  Cam get cam => Cam(
    _s.x / Cam.camFit(_size.height),
    _ax.x,
    _ay.x,
    _sx.x / _size.width,
    _sy.x / _size.height,
  );
}
