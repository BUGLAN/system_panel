import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'goal.dart';
import 'host_state.dart';
import 'quest.dart';
import 'quest_flow.dart';

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
        // 原型 `save()` 先 `S.lastSeen = Clock.now()` 再 stringify
        jsonEncode(data.copyWith(lastSeen: DateTime.now()).toJson()),
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

  /// 解冻。
  ///
  /// ⚠️ 原型 `wipe()` 之后紧跟一句 `location.reload()` —— **重载会把冻结一起重置**，
  /// 所以原型不需要这个方法。我们没有重载：重置后回到绑定仪式、绑定完要存盘，
  /// 不手动解冻的话那次存盘会被 `save()` 开头的 `if (_frozen) return` **静默跳过**
  /// （踩过：绑定完目标活不过一次重启，查了半天以为是 Android 侧通道坏了）。
  void unfreeze() => _frozen = false;

  /// 调试用：直接把原始字符串读回来（区分"没写进去"和"写进去了解析不出来"）
  Future<String?> rawRead() async {
    try {
      return await _p().getString(key);
    } catch (e) {
      return 'THREW: $e';
    }
  }

  /// 自检：写一个探针键再读回来。
  ///
  /// 加这个是因为**实机曾经静默不落盘**（`setString` 不抛异常、回读却是空的、
  /// 数据目录下一个文件都没有）—— 与其让它继续悄悄失败，不如启动时问一句
  /// 「这套存储到底能不能用」。返回 null 表示通过，否则是失败原因。
  Future<String?> selfTest() async {
    const String probe = 'opus-v2/__selftest';
    try {
      final String want = DateTime.now().microsecondsSinceEpoch.toString();
      await _p().setString(probe, want);
      final String? got = await _p().getString(probe);
      await _p().remove(probe);
      if (got == want) return null;
      return '写后回读不一致（写入 $want，读回 ${got ?? 'null'}）';
    } catch (e) {
      return '抛异常：$e';
    }
  }

  bool get frozen => _frozen;
}

/// 存下来的那一坨：宿主档案 + 主线 + 她手里的队列 + 执行中单据。
class SaveData {
  const SaveData({
    required this.host,
    required this.goal,
    this.queue = const <Quest>[],
    this.activeJson,
    this.lastSeen,
  });

  final HostState host;
  final Goal goal;

  /// 她手里还没派出去的单（T2 起随档走：结算后杀进程，队列还在）。
  /// 老档缺这个字段 → 默认空表，读档后由 QuestFlow 按现状补种子（合并式迁移）。
  final List<Quest> queue;

  /// 执行中单据的存档形态（t16/B3：接单后杀进程，任务/计时起点/证据保持）。
  /// 由 `QuestFlow.activeToSaveJson()` 产出、`restoreActiveFromJson()` 消费；
  /// 这里只当不透明 map 搬运 —— 老档缺字段 = null（无执行中单）。
  final Map<String, dynamic>? activeJson;

  /// 上次离开的时间（原型 `S.prevSeen` / `S.lastSeen`）—— 回来时算"你走了多久"用
  final DateTime? lastSeen;

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
      queue: json['queue'] is List
          ? <Quest>[
              for (final Object? q in json['queue'] as List)
                if (q is Map)
                  QuestFlow.questFromJson(Map<String, dynamic>.from(q)),
            ]
          : fallback.queue,
      activeJson: json['active'] is Map
          ? Map<String, dynamic>.from(json['active'] as Map)
          : fallback.activeJson,
      lastSeen: json['lastSeen'] is String
          ? (DateTime.tryParse(json['lastSeen'] as String) ?? fallback.lastSeen)
          : fallback.lastSeen,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'host': host.toJson(),
    'goal': goal.toJson(),
    'queue': <Map<String, dynamic>>[
      for (final Quest q in queue) QuestFlow.questToJson(q),
    ],
    if (activeJson != null) 'active': activeJson,
    if (lastSeen != null) 'lastSeen': lastSeen!.toIso8601String(),
  };

  SaveData copyWith({
    HostState? host,
    Goal? goal,
    List<Quest>? queue,
    Map<String, dynamic>? activeJson,
    DateTime? lastSeen,
  }) => SaveData(
    host: host ?? this.host,
    goal: goal ?? this.goal,
    queue: queue ?? this.queue,
    activeJson: activeJson ?? this.activeJson,
    lastSeen: lastSeen ?? this.lastSeen,
  );
}
