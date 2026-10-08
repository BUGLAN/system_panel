import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// ═══════════════════════════════════════════════════════════
///  对话历史（docs/18 §2.6）
///
///  key = `opus-v2/chat/v1`（独立于存档，杀进程重启可查）。
///  滚动窗口 **200 条**，满删最旧。坏档/读失败 → 空表，永不崩。
///  迁移语义：首次读没有档 = 空历史（新功能，无老档要迁）。
/// ═══════════════════════════════════════════════════════════

/// 一条对话消息。[fromHost] = 宿主（右侧气泡）/ 她（左侧气泡）。
/// 她的话带 [emotion]（舞台 mood 用，Persona.emotions 表内）。
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.fromHost,
    required this.text,
    required this.at,
    this.emotion = 'neutral',
  });

  ChatMessage.host(this.id, this.text, {DateTime? at})
    : fromHost = true,
      at = at ?? DateTime.now(),
      emotion = 'neutral';

  ChatMessage.sys(this.id, this.text, {this.emotion = 'neutral', DateTime? at})
    : fromHost = false,
      at = at ?? DateTime.now();

  final String id;
  final bool fromHost;
  final String text;
  final DateTime at;
  final String emotion;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'from': fromHost ? 'host' : 'sys',
    'text': text,
    'at': at.toIso8601String(),
    if (emotion != 'neutral') 'emotion': emotion,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    id: '${j['id'] ?? ''}',
    fromHost: j['from'] != 'sys',
    text: '${j['text'] ?? ''}',
    at: DateTime.tryParse('${j['at'] ?? ''}') ?? DateTime.now(),
    emotion: '${j['emotion'] ?? 'neutral'}',
  );
}

class ChatHistory {
  ChatHistory({SharedPreferencesAsync? prefs}) : _injected = prefs;

  /// docs/18 §2.8 的聊天 key
  static const String key = 'opus-v2/chat/v1';

  /// 滚动窗口：满 200 删最旧
  static const int maxEntries = 200;

  final SharedPreferencesAsync? _injected;
  SharedPreferencesAsync? _prefs;
  bool _loaded = false;

  SharedPreferencesAsync _p() =>
      _prefs ??= _injected ?? SharedPreferencesAsync();

  /// 旧 → 新
  List<ChatMessage> messages = <ChatMessage>[];

  bool get loaded => _loaded;

  /// 读档；没有档/读坏了都给空表
  Future<void> load() async {
    try {
      final String? raw = await _p().getString(key);
      if (raw == null || raw.isEmpty) {
        messages = <ChatMessage>[];
      } else {
        final Object? decoded = jsonDecode(raw);
        messages = decoded is List
            ? <ChatMessage>[
                for (final Object? e in decoded)
                  if (e is Map)
                    ChatMessage.fromJson(Map<String, dynamic>.from(e)),
              ]
            : <ChatMessage>[];
      }
    } catch (_) {
      messages = <ChatMessage>[];
    }
    _loaded = true;
  }

  /// 追加一条 + 滚动 200 + 落盘。失败不抛（内存里这一条还在，下次写再试）。
  Future<void> append(ChatMessage m) async {
    messages = <ChatMessage>[...messages, m];
    if (messages.length > maxEntries) {
      messages = messages.sublist(messages.length - maxEntries);
    }
    try {
      await _p().setString(
        key,
        jsonEncode(<Map<String, dynamic>>[
          for (final ChatMessage e in messages) e.toJson(),
        ]),
      );
    } catch (_) {}
  }

  /// 时间分组头（docs/18 §2.6：今天/昨天/M月D日）。跨年也给 M月D日（够用）。
  static String dayLabel(DateTime d) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime that = DateTime(d.year, d.month, d.day);
    final int diff = today.difference(that).inDays;
    if (diff <= 0) return '今天';
    if (diff == 1) return '昨天';
    return '${d.month}月${d.day}日';
  }
}
