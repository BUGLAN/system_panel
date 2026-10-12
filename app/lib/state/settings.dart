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
    this.paceMs = AgentSettings.kDefaultPaceMs,
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

  /// 对白节奏（docs/22 §R4 / 裁决 D-h）：她每字显形的毫秒数，
  /// 三档 = 慢 / 标准 / 快（见 [paceOptions]）。默认引用
  /// `AgentSettings.kDefaultPaceMs`（34）——同 [strictMode] 的纪律，
  /// 默认值只有 settings_store 一个真源，这里不写第二份字面量。
  /// 真正消费方是 main.dart 的装配（喂给 LineLayer / ChatPanel）。
  final int paceMs;

  static const AppSettings demo = AppSettings();

  /// 那一行「她的声音」的三个选项（真源 ui.js L599）
  static const List<List<String>> voiceOptions = <List<String>>[
    <String>['blip', '电子音'],
    <String>['tts', '人声'],
    <String>['mute', '静音'],
  ];

  /// 那一行「思考档位」的三个选项（docs/22 §R1-2；默认停在 low）
  /// 「思考档位」四档。宿主 2026-10-12 定调「不用为省 token 做取舍」，
  /// 所以默认仍停在 `low`（会思考、台词更活）；`关` 是给"想让她说话更快"
  /// 时用的开关 —— 注意它**只影响台词/聊天**，拆解与工具循环有
  /// `kPlanReasoningEffort` 兜住下限（见 llm_client.dart）。
  static const List<List<String>> reasoningOptions = <List<String>>[
    <String>['none', '关'],
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

  /// 那一行「对白节奏」的三个选项（docs/22 §R4 / 裁决 D-h；默认停在标准 34）。
  /// 值是**毫秒数的字符串**（分段开关按字符串比对/回传，与上面两张表同形），
  /// 但三个数都从 [AgentSettings] 的常量插值而来 —— 表里不再写第二份字面量。
  static const List<List<String>> paceOptions = <List<String>>[
    <String>['${AgentSettings.kPaceSlowMs}', '慢'],
    <String>['${AgentSettings.kDefaultPaceMs}', '标准'],
    <String>['${AgentSettings.kPaceFastMs}', '快'],
  ];
}
