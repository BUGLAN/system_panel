import 'package:flutter/widgets.dart';

/// ═══════════════════════════════════════════════════════════
///  画质档（docs/48 §5 性能策略）
///
///  两个输入，一个出口：
///   · [Fidelity.lowPower] —— 设置页「舞台特效：高 / 省电」（AgentSettings.fidelity）
///   · 系统「减弱动态效果」（MediaQuery.disableAnimations）
///  出口 [Fidelity.of]：组件只问一句「这里能不能做富效果」。
///
///  省电档砍掉的是**循环与逐帧绘制**（舞台光呼吸、浮尘、卡面全息箔漂移、
///  按钮扫光），保留**一次性反馈**（按压、落定、翻面）——反馈是可用性，
///  循环是氛围。减弱动态效果在省电之上再砍掉位移类过渡。
/// ═══════════════════════════════════════════════════════════
enum FxLevel {
  /// 全部效果：逐帧循环 + 粒子 + 箔漂移
  rich,

  /// 省电：静态舞台光、无粒子、无循环扫光；一次性反馈保留
  lite,

  /// 减弱动态效果：在 lite 之上再去掉位移/缩放类过渡
  still,
}

class Fidelity {
  const Fidelity._();

  /// 设置页的省电开关（main.dart `_applyAgentSettings` 落地）
  static final ValueNotifier<bool> lowPower = ValueNotifier<bool>(false);

  /// 当前档位（读 MediaQuery，所以要 context）
  static FxLevel of(BuildContext context) {
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) return FxLevel.still;
    if (lowPower.value) return FxLevel.lite;
    return FxLevel.rich;
  }

  static bool rich(BuildContext context) => of(context) == FxLevel.rich;
}
