import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'llm_client.dart';

/// ═══════════════════════════════════════════════════════════
///  设置存取（docs/18 §2.4 / §2.8）
///
///  key = `opus-v2/settings/v1`。迁移策略沿用 save_file 的惯例：
///  **在默认值上合并** —— 老档缺字段自动补默认，永不要求清档。
///  除 LLM·视觉校验组外，系统页四个开关（音效/她的声音/震动/全息描边，D8）
///  也持久化在这里：同一张设置表、同一套合并语义。
///
///  ⚠️ Key 只存本机 SharedPreferences（隐私注：见设置页文案）。
///  load/save 全部吞异常 —— 存储层坏了也不能让 App 崩。
/// ═══════════════════════════════════════════════════════════
class AgentSettings {
  const AgentSettings({
    this.visionEnabled = true,
    this.baseUrl = LlmConfig.kDefaultBase,
    this.apiKey = '',
    this.model = LlmConfig.kDefaultModel,
    this.sound = true,
    this.haptic = true,
    this.holo = true,
    this.voice = 'blip',
  });

  /// 视觉校验开关（关 = 纯信任模式，证据全按「未校验」计）
  final bool visionEnabled;

  /// OpenAI 兼容端点 base（默认 https://api.deepseek.com）
  final String baseUrl;

  /// API Key（掩码显示，只存本机）
  final String apiKey;

  /// 模型名（默认 deepseek-v4.1flash，请求前由 LlmClient 归一化）
  final String model;

  // ── D8：系统页四个开关（与 AppSettings 同名同义） ──
  final bool sound;
  final bool haptic;
  final bool holo;

  /// 她的声音：blip 电子音 / tts 人声 / mute 静音
  final String voice;

  factory AgentSettings.fromJson(
    Map<String, dynamic>? json, {
    required AgentSettings fallback,
  }) {
    if (json == null) return fallback;
    T pick<T>(String k, T def) => json[k] is T ? json[k] as T : def;
    return AgentSettings(
      visionEnabled: pick<bool>('visionEnabled', fallback.visionEnabled),
      baseUrl: pick<String>('baseUrl', fallback.baseUrl),
      apiKey: pick<String>('apiKey', fallback.apiKey),
      model: pick<String>('model', fallback.model),
      sound: pick<bool>('sound', fallback.sound),
      haptic: pick<bool>('haptic', fallback.haptic),
      holo: pick<bool>('holo', fallback.holo),
      voice: pick<String>('voice', fallback.voice),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'visionEnabled': visionEnabled,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
    'sound': sound,
    'haptic': haptic,
    'holo': holo,
    'voice': voice,
  };

  AgentSettings copyWith({
    bool? visionEnabled,
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? sound,
    bool? haptic,
    bool? holo,
    String? voice,
  }) => AgentSettings(
    visionEnabled: visionEnabled ?? this.visionEnabled,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
    sound: sound ?? this.sound,
    haptic: haptic ?? this.haptic,
    holo: holo ?? this.holo,
    voice: voice ?? this.voice,
  );

  @override
  bool operator ==(Object other) =>
      other is AgentSettings &&
      other.visionEnabled == visionEnabled &&
      other.baseUrl == baseUrl &&
      other.apiKey == apiKey &&
      other.model == model &&
      other.sound == sound &&
      other.haptic == haptic &&
      other.holo == holo &&
      other.voice == voice;

  @override
  int get hashCode => Object.hash(
    visionEnabled, baseUrl, apiKey, model, sound, haptic, holo, voice,
  );
}

class SettingsStore {
  SettingsStore({SharedPreferencesAsync? prefs}) : _injected = prefs;

  /// docs/18 §2.8 的设置 key（LLM/视觉 + 四开关同表）
  static const String key = 'opus-v2/settings/v1';

  // ── 变更通知（TODO-07 聊天网关热更，docs/20 遗留观察①）──────────
  //
  // 设置页（sheet）、视觉校验（vision）、聊天装配（main._initAgent）各自
  // `new SettingsStore()`，实例之间互不相识——所以通知必须是**类级广播**：
  // 任何实例 save() 落盘后，全部监听者都拿到新设置。聊天/文案装配据此
  // 重建 LlmClient / LlmGateway / ChatService，改 Key/BaseURL/模型名
  // 即时生效免重启。
  static final List<void Function(AgentSettings)> _listeners =
      <void Function(AgentSettings)>[];

  /// 广播版本号：每 save 一次 +1（从未存过 = 0）。
  /// 测试/诊断可断言「这次 save 确实通知出去了」。
  static int _version = 0;
  static int get version => _version;

  /// 订阅设置变更（聊天装配在 init 时挂、dispose 时摘）。
  static void addListener(void Function(AgentSettings s) onSettings) {
    _listeners.add(onSettings);
  }

  /// 退订（State 卸载后不再收回调）。
  static void removeListener(void Function(AgentSettings s) onSettings) {
    _listeners.remove(onSettings);
  }

  /// 类级广播：版本号先自增，再逐个通知。监听者列表走**快照**遍历
  /// （监听者在回调里退订也不炸迭代），单个监听者抛异常只吞掉自己，
  /// 不拖垮保存方——存设置的（设置页）永远不能被收听的（网关装配）连累。
  static void _broadcast(AgentSettings s) {
    _version++;
    for (final void Function(AgentSettings) fn
        in List<void Function(AgentSettings)>.of(_listeners)) {
      try {
        fn(s);
      } catch (_) {}
    }
  }

  final SharedPreferencesAsync? _injected;
  SharedPreferencesAsync? _prefs;

  SharedPreferencesAsync _p() =>
      _prefs ??= _injected ?? SharedPreferencesAsync();

  /// 读设置；没有档或读坏了就给默认（合并语义在 [AgentSettings.fromJson]）
  Future<AgentSettings> load() async {
    try {
      final String? raw = await _p().getString(key);
      if (raw == null || raw.isEmpty) return const AgentSettings();
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const AgentSettings();
      return AgentSettings.fromJson(decoded, fallback: const AgentSettings());
    } catch (_) {
      return const AgentSettings();
    }
  }

  /// 存设置；磁盘写失败静默（下次改设置再写），但**照样广播**——
  /// 存储层坏了也不能让宿主这次改的 Key 在内存里失效（网关热更靠它）。
  Future<void> save(AgentSettings s) async {
    try {
      await _p().setString(key, jsonEncode(s.toJson()));
    } catch (_) {}
    _broadcast(s);
  }
}
