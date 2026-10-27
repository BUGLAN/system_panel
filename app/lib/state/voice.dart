import 'dart:math' as math;

/// ═══════════════════════════════════════════════════════════
///  口型包络（audio.js L180-230 `Voice`）
///
///  原型用**合成音节**驱动口型：打一个字就把目标开合度设一下，
///  然后指数逼近过去。真源：
///  ```js
///  syllable(ch) {
///    if (/[，。！？、…—\s…]/.test(ch)) { this._target = 0; return; }  // 标点闭嘴
///    this._target = rand(.55, 1);
///  },
///  tick(dt) { this.mouth += (this._target - this.mouth) * (1 - Math.pow(.00002, dt)); },
///  ```
///
///  **这条链路不需要角色模型**：SYSTEM 后面那排波形条就是它驱动的
///  （`ui.js` L70-73）。AGENTS.md 说的"电子音节先行"正是指这个 ——
///  先把口型/波形做出来，模型到位后 `ParamMouthOpenY` 直接读同一个 `mouth`。
/// ═══════════════════════════════════════════════════════════
class VoiceEnvelope {
  VoiceEnvelope({math.Random? rnd}) : _rnd = rnd ?? math.Random();

  /// 标点/空白：闭嘴（原型那条正则）
  static final RegExp _silent = RegExp(r'[，。！？、…—\s,.!?「」『』（）()：:；;"“”‘’]');

  /// `1 - pow(.00002, dt)` 里的常数
  static const double _rate = .00002;

  final math.Random _rnd;

  /// 当前开口度 0~1
  double mouth = 0;

  /// 目标开口度
  double target = 0;

  /// 一个字（原型 `Voice.syllable`）
  void syllable(String ch) {
    if (_silent.hasMatch(ch)) {
      target = 0;
      return;
    }
    target = .55 + _rnd.nextDouble() * .45; // rand(.55, 1)
  }

  /// 每帧逼近（原型 `Voice.tick(dt)`）—— dt 是秒
  void tick(double dt) {
    if (dt <= 0) return;
    mouth += (target - mouth) * (1 - math.pow(_rate, dt).toDouble());
  }

  /// 闭嘴：整句说完 / 被跳过 / 字幕收起（原型 `Voice.hush()`）
  void hush() {
    target = 0;
  }

  /// 立刻归零（切页面时用，免得上一条残留的开口度带过去）
  void reset() {
    target = 0;
    mouth = 0;
  }

  /// 某根波形条此刻的缩放（`ui.js` L71-72）
  ///
  /// `scaleY(clamp(.14 + m * (.55 + .45 * sin(t + i * 1.7)), .12, 1))`
  /// —— `i * 1.7` 是逐条相位差，所以五根条是错开的。
  static double barScale(int i, double m, double t) =>
      (.14 + m * (.55 + .45 * math.sin(t + i * 1.7))).clamp(.12, 1.0);
}
