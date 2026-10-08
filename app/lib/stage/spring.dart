import 'dart:math' as math;

/// ═══════════════════════════════════════════════════════════
///  弹簧（`util.js` L85-98 `class Spring`）
///
///  ```js
///  constructor(v = 0, k = 120, zeta = .9) {
///    this.x = v; this.v = 0; this.t = v;
///    this.k = k; this.c = 2 * zeta * Math.sqrt(k);
///  }
///  set(t, snap) { this.t = t; if (snap) { this.x = t; this.v = 0; } }
///  step(dt) {
///    const n = Math.max(1, Math.ceil(dt / (1 / 120)));   // 子步 ≤ 1/120s
///    const h = dt / n;
///    for (let i = 0; i < n; i++) {
///      const a = -this.k * (this.x - this.t) - this.c * this.v;
///      this.v += a * h; this.x += this.v * h;
///    }
///    return this.x;
///  }
///  ```
///
///  ⚠️ **不要换成 Flutter 的 `SpringSimulation`** —— 那个走的是解析/另一套积分，
///  同样的 (k, zeta) 得到的过冲与收敛速度都不一样。这里逐行照抄原型：
///  半隐式欧拉 + 子步长不超过 1/120s（子步是为了 dt 抖动时仍然稳定）。
/// ═══════════════════════════════════════════════════════════
class Spring {
  Spring({double v = 0, this.k = 120, double zeta = .9})
    : x = v,
      t = v,
      c = 2 * zeta * math.sqrt(k);

  /// 当前位置
  double x;

  /// 速度
  double v = 0;

  /// 目标
  double t;

  /// 劲度
  final double k;

  /// 阻尼系数（由 `2 * zeta * sqrt(k)` 算出来）
  final double c;

  /// 设目标；`snap: true` 直接到位（原型 `setCam(name, snap)`）
  void set(double target, {bool snap = false}) {
    t = target;
    if (snap) {
      x = target;
      v = 0;
    }
  }

  /// 推进一步，返回新位置
  double step(double dt) {
    if (dt <= 0) return x;
    final int n = math.max(1, (dt / (1 / 120)).ceil());
    final double h = dt / n;
    for (int i = 0; i < n; i++) {
      final double a = -k * (x - t) - c * v;
      v += a * h;
      x += v * h;
    }
    return x;
  }

  /// 原型 `get done()`
  bool get done => (x - t).abs() < 1e-3 && v.abs() < 1e-3;
}
