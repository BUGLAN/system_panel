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
///
///  G1.1 坏档保护（原型没有，是我们补的）：原来读坏 = 静默给空白档，读档完成后
///  第一次自动存档就把坏档覆盖 —— 全部进度丢失、没有备份。现在：
///   · 每次存盘前把**上一份好档**滚到 [bakKey]（只滚能解析的：自己写出去的串、
///     或读档时完整解析过的串；坏档绝不进 bak）
///   · 主档读坏 → 原串先另存 [corruptKey]（在任何覆盖之前）→ 退回 bak →
///     bak 也不行才给空白档。[loadDetailed] 告诉调用方走的是哪条路
/// ═══════════════════════════════════════════════════════════
class SaveFile {
  SaveFile({SharedPreferencesAsync? prefs}) : _injected = prefs;

  /// `SAVE_KEY`（store.js L4）
  static const String key = 'opus-v2/save/v1';

  /// 上一份好档（每次存盘前滚一次）
  static const String bakKey = '$key.bak';

  /// 读坏的主档原串（留给人工抢救；重置时一并删）
  static const String corruptKey = '$key.corrupt';

  final SharedPreferencesAsync? _injected;
  SharedPreferencesAsync? _prefs;
  bool _frozen = false;

  /// 已知能解析的最近一份主档串（首次读到的 / 上次成功写出去的）——
  /// 下次存盘把它写成 bak。记在内存里，免得每次存盘先读一遍盘（写放大）
  String? _lastGood;

  /// 已知 bak 里现在是什么（相同就不重写）
  String? _bakMirror;

  SharedPreferencesAsync _p() =>
      _prefs ??= _injected ?? SharedPreferencesAsync();

  /// 读档；没有档或读坏了就给一份默认（原型 catch 后 `this.fresh()`）。
  /// 坏档的备份/退回逻辑见 [loadDetailed]，这里只要数据。
  Future<SaveData> load({SaveData? fallback}) async =>
      (await loadDetailed(fallback: fallback)).data;

  /// 读档并说明来源（[SaveSource]）。
  ///
  /// ⚠️ **没有主档 = 没有档**，不去翻 bak：主档只有 [wipe] 会删（它先删 bak），
  /// 主档没了还去翻 bak，就是把「重置」掉的旧档复活。
  Future<SaveLoad> loadDetailed({SaveData? fallback}) async {
    final SaveData def = fallback ?? SaveData.fresh();
    final String? raw;
    try {
      raw = await _p().getString(key);
    } catch (e) {
      // 存储本身读不出来（不是档坏了）—— 不碰 corrupt/bak，照旧给默认
      debugPrint('[save] 读档抛异常：$e');
      return SaveLoad(def, SaveSource.none);
    }
    if (raw == null) return SaveLoad(def, SaveSource.none);

    final SaveData? main = _parse(raw, def);
    if (main != null) {
      _lastGood = raw;
      return SaveLoad(main, SaveSource.primary);
    }

    // 主档坏了：先把原串留一份（空串没得留），再退回 bak
    if (raw.isNotEmpty) {
      try {
        await _p().setString(corruptKey, raw);
      } catch (e) {
        debugPrint('[save] ⚠️ 坏档另存失败：$e');
      }
    }
    String? bak;
    try {
      bak = await _p().getString(bakKey);
    } catch (_) {
      bak = null;
    }
    final SaveData? restored = bak == null ? null : _parse(bak, def);
    if (restored != null) {
      // 下次存盘：bak 已经是这份好档了，不用再滚；主档会被好数据写回
      _lastGood = bak;
      _bakMirror = bak;
      return SaveLoad(restored, SaveSource.backup);
    }
    return SaveLoad(def, SaveSource.corrupt);
  }

  /// 能完整解析成存档就返回，否则 null（JSON 坏 / 不是对象 / fromJson 抛）
  static SaveData? _parse(String raw, SaveData def) {
    if (raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return SaveData.fromJson(decoded, fallback: def);
    } catch (_) {
      return null;
    }
  }

  /// 存盘（原型会带上 `lastSeen`）。先把上一份好档滚进 bak，再写主档。
  Future<void> save(SaveData data) async {
    if (_frozen) return;
    try {
      // 原型 `save()` 先 `S.lastSeen = Clock.now()` 再 stringify
      final String raw = jsonEncode(
        data.copyWith(lastSeen: DateTime.now()).toJson(),
      );
      final String? prev = _lastGood;
      if (prev != null && prev != _bakMirror) {
        await _p().setString(bakKey, prev);
        _bakMirror = prev;
      }
      await _p().setString(key, raw);
      _lastGood = raw; // 自己 jsonEncode 出来的，必然能解析
    } catch (e, st) {
      // 原型这里是配额爆了就把照片扔掉重存；我们暂无照片
      debugPrint('[save] FAILED: $e\n$st');
    }
  }

  /// 重置：删档 + 冻结（原型 `Store.wipe()`）。
  ///
  /// bak / corrupt 一并删、而且**先删它们再删主档**：主档没了读档就当「没有档」，
  /// 可要是 bak 还留着，哪天主档坏一次就会把重置前的旧档复活。
  /// 内存里记的上一份好档也清掉 —— 否则重新绑定后第一次存盘会把旧档滚进 bak。
  Future<SaveData> wipe({SaveData? fallback}) async {
    _frozen = true;
    _lastGood = null;
    _bakMirror = null;
    for (final String k in <String>[bakKey, corruptKey, key]) {
      try {
        await _p().remove(k);
      } catch (_) {}
    }
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

/// 读档走的是哪条路（G1.1）
enum SaveSource {
  /// 主档读到了
  primary,

  /// 主档坏了，从 bak 恢复（原串已另存 corrupt；下次存盘把好数据写回主档）
  backup,

  /// 没有档（新装 / 重置后）—— 空白档
  none,

  /// 主档坏了、bak 也没有或也坏 —— 空白档（原串已另存 corrupt）
  corrupt,
}

/// [SaveFile.loadDetailed] 的结果：数据 + 来源
class SaveLoad {
  const SaveLoad(this.data, this.source);

  final SaveData data;
  final SaveSource source;
}

/// 存下来的那一坨：宿主档案 + 主线 + 她手里的队列 + 执行中单据。
class SaveData {
  const SaveData({
    required this.host,
    required this.goal,
    this.queue = const <Quest>[],
    this.activeJson,
    this.lastSeen,
    this.pendingGoal = '',
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

  /// C5（docs/50）：拆解失败后「暂时跳过」时宿主输入过的那句目标。
  /// 有它、但还没有主线 → 大厅 / 主线页的主按钮是「重试拆解」；拆成功后清空。
  /// 老档缺这个字段 → 默认空串（合并式迁移，不影响老档）。
  final String pendingGoal;

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
      pendingGoal: json['pendingGoal'] is String
          ? (json['pendingGoal'] as String).trim()
          : fallback.pendingGoal,
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
    if (pendingGoal.isNotEmpty) 'pendingGoal': pendingGoal,
  };

  SaveData copyWith({
    HostState? host,
    Goal? goal,
    List<Quest>? queue,
    Map<String, dynamic>? activeJson,
    DateTime? lastSeen,
    String? pendingGoal,
  }) => SaveData(
    host: host ?? this.host,
    goal: goal ?? this.goal,
    queue: queue ?? this.queue,
    activeJson: activeJson ?? this.activeJson,
    lastSeen: lastSeen ?? this.lastSeen,
    pendingGoal: pendingGoal ?? this.pendingGoal,
  );
}
