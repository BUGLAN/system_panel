/// 系统设置 —— 对应原型 `App.settings` + `Voice.mode`（ui.js `Sheet.system`）。
/// 行为（真正开关音效/震动/语音）等宿主约束，这里先只是数据。
class AppSettings {
  const AppSettings({
    this.sound = true,
    this.haptic = true,
    this.holo = true,
    this.voice = 'blip',
  });

  final bool sound;

  /// 震动：仅安卓有效
  final bool haptic;

  /// 她身上的电光轮廓；低端机可关
  final bool holo;

  /// 她的声音：blip 电子音 / tts 人声 / mute 静音
  final String voice;

  static const AppSettings demo = AppSettings();

  /// 那一行「她的声音」的三个选项（真源 ui.js L599）
  static const List<List<String>> voiceOptions = <List<String>>[
    <String>['blip', '电子音'],
    <String>['tts', '人声'],
    <String>['mute', '静音'],
  ];
}
