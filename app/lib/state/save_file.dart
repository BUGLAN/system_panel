import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'goal.dart';
import 'host_state.dart';

/// ═══════════════════════════════════════════════════════════
///  存档（store.js L4 / L34-52）
///
///  原型三条做法照搬：
///   1. **在默认值上合并**（`Object.assign(fresh(), JSON.parse(raw))`）——
///      这是老存档的迁移方式：新增字段自动拿到默认值，删掉的字段不影响
///   2. key 自带版本号（`opus-v2/save/v1`），换结构时改版本号即弃旧档
///   3. `wipe()` 之后**冻结**，别再写回去（否则"重置"当场被覆盖）
/// ═══════════════════════════════════════════════════════════
class SaveFile {
  SaveFile({SharedPreferencesAsync? prefs}) : _injected = prefs;

  /// `SAVE_KEY`（store.js L4）
  static const String key = 'opus-v2/save/v1';

  final SharedPreferencesAsync? _injected;
  SharedPreferencesAsync? _prefs;
  bool _frozen = false;

  SharedPreferencesAsync _p() =>
      _prefs ??= _injected ?? SharedPreferencesAsync();

  /// 读档；没有档或读坏了就给一份默认（原型 catch 后 `this.fresh()`）
  Future<SaveData> load({SaveData? fallback}) async {
    final SaveData def = fallback ?? SaveData.fresh();
    try {
      final String? raw = await _p().getString(key);
      if (raw == null || raw.isEmpty) return def;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return def;
      return SaveData.fromJson(decoded, fallback: def);
    } catch (_) {
      return def;
    }
  }

  /// 存盘（原型会带上 `lastSeen`）
  Future<void> save(SaveData data) async {
    if (_frozen) return;
    try {
      await _p().setString(
        key,
        jsonEncode(
          data.toJson()..['lastSeen'] = DateTime.now().toIso8601String(),
        ),
      );
    } catch (e, st) {
      // 原型这里是配额爆了就把照片扔掉重存；我们暂无照片
      debugPrint('[save] FAILED: $e\n$st');
    }
  }

  /// 重置：删档 + 冻结（原型 `Store.wipe()`）
  Future<SaveData> wipe({SaveData? fallback}) async {
    _frozen = true;
    try {
      await _p().remove(key);
    } catch (_) {}
    return fallback ?? SaveData.fresh();
  }

  bool get frozen => _frozen;
}

/// 存下来的那一坨：宿主档案 + 主线。
class SaveData {
  const SaveData({required this.host, required this.goal});

  final HostState host;
  final Goal goal;

  /// 全新档 = 未绑定（原型的 `Store.fresh()`）
  factory SaveData.fresh() =>
      SaveData(host: HostState.empty, goal: Goal.empty());

  /// **在默认值上合并** —— 缺字段就走默认，这是迁移的关键
  factory SaveData.fromJson(
    Map<String, dynamic> json, {
    required SaveData fallback,
  }) {
    return SaveData(
      host: HostState.fromJson(
        json['host'] is Map
            ? Map<String, dynamic>.from(json['host'] as Map)
            : null,
        fallback: fallback.host,
      ),
      goal: Goal.fromJson(
        json['goal'] is Map
            ? Map<String, dynamic>.from(json['goal'] as Map)
            : null,
        fallback: fallback.goal,
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'host': host.toJson(),
    'goal': goal.toJson(),
  };

  SaveData copyWith({HostState? host, Goal? goal}) =>
      SaveData(host: host ?? this.host, goal: goal ?? this.goal);
}
