import 'dart:math' as math;
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
/// ⚠️ 原型里 `NY.chest` 会被 Live2D 模型实测值覆盖（实测 −.10737），
/// 但**环位只用到 hair / feet / shoulder**，这三项是静态的。
class StageAnchors {
  const StageAnchors._();

  static const double hair = .44;
  static const double shoulder = .01;
  static const double feet = -1.51;

  /// 她的整体高度（世界单位）
  static const double bodySpan = hair - feet; // 1.95
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
class RingGeom {
  const RingGeom({required this.rx, required this.ry, required this.ryy});

  /// 横向半径（世界单位）
  final double rx;

  /// 所在高度
  final double ry;

  /// 纵向半径（透视压扁后的）
  final double ryy;

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// `i` 是环序（0 基），`n` 是总环数，`finalRing` 是「她头顶那一环」
  static RingGeom of(int i, int n, {required bool finalRing}) {
    if (finalRing) {
      return const RingGeom(rx: .42, ry: StageAnchors.hair + .20, ryy: .055);
    }
    final double m = math.max(1, n - 2).toDouble();
    final double f = i / m;
    final double rx = _lerp(.30, .25, f);
    return RingGeom(
      rx: rx,
      ry: _lerp(StageAnchors.feet + .20, StageAnchors.shoulder - .06, f),
      ryy: rx * _lerp(.22, .15, f),
    );
  }

  /// 环的右/左端点（`Stage.ringPoint`）—— DOM 标签就挂在这儿
  Offset point(String cam, Size size, {double side = 1, double scaleMul = 1}) {
    return Cam.byName(cam).toScreen(side * rx * scaleMul, ry, size);
  }
}
