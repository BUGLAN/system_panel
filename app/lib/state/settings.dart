/// 系统设置 —— 对应原型 `App.settings` + `Voice.mode`（ui.js `Sheet.system`）。
/// 行为（真正开关音效/震动/语音）等宿主约束，这里先只是数据。
///
/// 同理，[reasoningEffort] / [strictMode] 这里也只是**首帧 seed + 选项表**：
/// **真源是 `agent/settings_store.dart` 的 `AgentSettings`**（真正落盘、
/// 真正被 `main.dart` 装配消费的那份）。默认值刻意**引用同一个常量**
/// 而不是各写一份字面量——验收 F-4 指出的漂移风险就出在这里。
library;

import '../agent/llm_client.dart';
import '../agent/settings_store.dart';

class AppSettings {
  const AppSettings({
    this.sound = true,
    this.haptic = true,
    this.holo = true,
    this.voice = 'blip',
    this.reasoningEffort = LlmConfig.kDefaultReasoningEffort,
    this.strictMode = AgentSettings.kDefaultStrictMode,
  });

  final bool sound;

  /// 震动：仅安卓有效
  final bool haptic;

  /// 她身上的电光轮廓；低端机可关
  final bool holo;

  /// 她的声音：blip 电子音 / tts 人声 / mute 静音
  final String voice;

  /// 思考档位（docs/22 §R1-2）：low / high / max，默认 low。
  /// 真正行为由 main.dart 的装配消费，这里只是数据。
  final String reasoningEffort;

  /// 严格模式（docs/22 §2.0）：auto / on / off，默认 auto。
  /// 真正行为由 main.dart 的装配消费（auto＝debug/profile 报错不兜底），
  /// 这里只是数据。
  final String strictMode;

  static const AppSettings demo = AppSettings();

  /// 那一行「她的声音」的三个选项（真源 ui.js L599）
  static const List<List<String>> voiceOptions = <List<String>>[
    <String>['blip', '电子音'],
    <String>['tts', '人声'],
    <String>['mute', '静音'],
  ];

  /// 那一行「思考档位」的三个选项（docs/22 §R1-2；默认停在 low）
  static const List<List<String>> reasoningOptions = <List<String>>[
    <String>['low', '低'],
    <String>['high', '高'],
    <String>['max', '最高'],
  ];

  /// 那一行「严格模式」的三个选项（docs/22 §2.0；默认停在 auto）
  static const List<List<String>> strictOptions = <List<String>>[
    <String>['auto', '自动'],
    <String>['on', '开'],
    <String>['off', '关'],
  ];
}
