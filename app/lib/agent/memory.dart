/// 小祥的长期记忆（docs/18 §2.5）。
///
/// 独立存档 key `opus-v2/memory/v1`（不进宿主档案，与 SaveFile 互不干扰）；
/// 上限 200 条，满了按「权重低者先、同权最旧者先」淘汰；读取给 LLM 注入
/// **最相关 ≤8 条**（关键词命中优先，最近条目兜底，第一版不做 embedding）。
///
/// 铁律：读坏/存坏都兜住——坏 JSON 回空表，写失败静默（与 SaveFile 同纪律），
/// 记忆模块永远不能把 App 带崩。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 记忆来源：访谈答案 / 聊天 / 工具(remember) / 结算里程碑
enum MemorySource { interview, chat, tool, milestone }

MemorySource _sourceOf(String? s) => MemorySource.values.firstWhere(
  (MemorySource v) => v.name == s,
  orElse: () => MemorySource.chat,
);

/// 一条记忆。
class MemoryEntry {
  const MemoryEntry({
    required this.id,
    required this.text,
    required this.at,
    required this.source,
    this.weight = 1,
  });

  factory MemoryEntry.fromJson(Map<String, dynamic> j) => MemoryEntry(
    id: j['id'] is String ? j['id'] as String : '',
    text: j['text'] is String ? j['text'] as String : '',
    at: j['at'] is String
        ? (DateTime.tryParse(j['at'] as String) ??
              DateTime.fromMillisecondsSinceEpoch(0))
        : DateTime.fromMillisecondsSinceEpoch(0),
    source: _sourceOf(j['source'] is String ? j['source'] as String : null),
    weight: j['weight'] is int ? j['weight'] as int : 1,
  );

  final String id;
  final String text;
  final DateTime at;
  final MemorySource source;

  /// 权重越大越难被淘汰（访谈答案 2、工具记住 3、里程碑 4，闲聊 1）
  final int weight;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'text': text,
    'at': at.toIso8601String(),
    'source': source.name,
    'weight': weight,
  };
}

/// 长期记忆仓。
///
/// ```dart
/// final MemoryStore memory = MemoryStore();
/// await memory.add('宿主通常 1-2 点睡', source: MemorySource.interview, weight: 2);
/// final String digest = await memory.digest('几点睡'); // 注入 system prompt
/// ```
class MemoryStore {
  MemoryStore({SharedPreferencesAsync? prefs, String? storageKey})
    : _injected = prefs,
      key = storageKey ?? defaultKey;

  /// 存档 key（docs/18 §2.8）
  static const String defaultKey = 'opus-v2/memory/v1';

  /// 条目上限，满了淘汰
  static const int maxEntries = 200;

  /// LLM 每次注入的最相关条数
  static const int injectLimit = 8;

  final SharedPreferencesAsync? _injected;
  SharedPreferencesAsync? _prefs;

  /// 本实例使用的 key（测试可换）
  final String key;

  SharedPreferencesAsync get _p =>
      _prefs ??= _injected ?? SharedPreferencesAsync();

  static int _seq = 0;

  String _newId() {
    _seq = (_seq + 1) % 0xffff;
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-$_seq';
  }

  /// 全部条目（新→旧）。读坏回空表，不抛。
  Future<List<MemoryEntry>> entries() async {
    try {
      final String? raw = await _p.getString(key);
      if (raw == null || raw.isEmpty) return <MemoryEntry>[];
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return <MemoryEntry>[];
      final List<MemoryEntry> out = <MemoryEntry>[
        for (final Object? e in decoded)
          if (e is Map)
            MemoryEntry.fromJson(Map<String, dynamic>.from(e))
          else if (e is String)
            MemoryEntry(
              id: _newId(),
              text: e,
              at: DateTime.now(),
              source: MemorySource.chat,
            ),
      ];
      out.sort((MemoryEntry a, MemoryEntry b) => b.at.compareTo(a.at));
      return out;
    } catch (_) {
      return <MemoryEntry>[];
    }
  }

  /// 记一条。同文本去重（刷新时间与权重）；满 200 条按「权重低→旧」淘汰。
  Future<MemoryEntry> add(
    String text, {
    MemorySource source = MemorySource.chat,
    int weight = 1,
    DateTime? at,
  }) async {
    final String clean = text.trim();
    if (clean.isEmpty) {
      throw ArgumentError('记忆内容不能为空', 'text');
    }
    final List<MemoryEntry> all = await entries();
    MemoryEntry entry = all.firstWhere(
      (MemoryEntry e) => e.text == clean,
      orElse: () => MemoryEntry(
        id: _newId(),
        text: clean,
        at: at ?? DateTime.now(),
        source: source,
        weight: weight,
      ),
    );
    if (all.any((MemoryEntry e) => e.text == clean)) {
      // 去重：刷新时间、取较高权重
      entry = MemoryEntry(
        id: entry.id,
        text: entry.text,
        at: at ?? DateTime.now(),
        source: entry.source,
        weight: entry.weight > weight ? entry.weight : weight,
      );
      all.removeWhere((MemoryEntry e) => e.text == clean);
    }
    all.insert(0, entry);
    if (all.length > maxEntries) {
      // 淘汰序：权重低者先、同权最旧者先
      final List<MemoryEntry> doomed = <MemoryEntry>[...all]
        ..sort((MemoryEntry a, MemoryEntry b) {
          final int byWeight = a.weight.compareTo(b.weight);
          if (byWeight != 0) return byWeight;
          return a.at.compareTo(b.at);
        });
      final Set<String> dropped = <String>{
        for (final MemoryEntry e in doomed.take(all.length - maxEntries)) e.id,
      };
      all.removeWhere((MemoryEntry e) => dropped.contains(e.id));
    }
    await _save(all);
    return entry;
  }

  /// 删除一条；返回是否真的删了。
  Future<bool> remove(String id) async {
    final List<MemoryEntry> all = await entries();
    final int before = all.length;
    all.removeWhere((MemoryEntry e) => e.id == id);
    if (all.length == before) return false;
    await _save(all);
    return true;
  }

  /// 清空（wipe/reset 场景用）。
  Future<void> clear() async {
    try {
      await _p.remove(key);
    } catch (_) {}
  }

  /// 最相关 ≤[limit] 条：关键词命中优先（命中内按新→旧），
  /// 不足 [limit] 用最近的条目补齐（最近 5 条兜底的推广版）。
  Future<List<MemoryEntry>> relevant(
    String? query, {
    int limit = injectLimit,
  }) async {
    final List<MemoryEntry> all = await entries();
    final String q = (query ?? '').trim();
    if (q.isEmpty || all.isEmpty) {
      return all.take(limit).toList();
    }
    final Set<String> keys = _keywords(q);
    final List<MemoryEntry> hits = all
        .where(
          (MemoryEntry e) => _keywords(e.text).intersection(keys).isNotEmpty,
        )
        .toList();
    final List<MemoryEntry> out = <MemoryEntry>[...hits.take(limit)];
    if (out.length < limit) {
      for (final MemoryEntry e in all) {
        if (out.length >= limit) break;
        if (!out.contains(e)) out.add(e);
      }
    }
    return out;
  }

  /// 给 system prompt 注入的记忆段（`- 条目` 行；没有相关记忆返回空串）。
  Future<String> digest(String? query, {int limit = injectLimit}) async {
    final List<MemoryEntry> rel = await relevant(query, limit: limit);
    if (rel.isEmpty) return '';
    return rel.map((MemoryEntry e) => '- ${e.text}').join('\n');
  }

  Future<void> _save(List<MemoryEntry> all) async {
    try {
      await _p.setString(
        key,
        jsonEncode(<Map<String, dynamic>>[
          for (final MemoryEntry e in all) e.toJson(),
        ]),
      );
    } catch (_) {
      // 存不进去也不能崩：下次再试（与 SaveFile 纪律一致）
    }
  }

  /// 极简关键词集：整词 + 中文二元切片（无空格语言的土办法，够第一版用）。
  static Set<String> _keywords(String text) {
    final String t = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\u4e00-\u9fff]+'), ' ')
        .trim();
    final Set<String> out = <String>{};
    for (final String term in t.split(' ')) {
      if (term.isEmpty) continue;
      out.add(term);
      for (int i = 0; i + 2 <= term.length; i++) {
        out.add(term.substring(i, i + 2));
      }
    }
    return out;
  }
}
