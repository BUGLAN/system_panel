import '../agent/copy.dart';
import '../agent/llm_gateway.dart';
import '../agent/memory.dart';
import '../agent/persona.dart';
import 'chat_history.dart';

/// ═══════════════════════════════════════════════════════════
///  聊天回复服务（docs/18 §2.6 消息流）
///
///  发送 → persona（人设+铁律）+ memory（相关 ≤8 条）+ 近几轮历史
///  → [LlmGateway]（OpenAI 兼容）→ `[情绪] 正文` → 气泡 + 舞台 mood。
///  **兜底铁律**：没配 Key / 无网 / 超时 / 空话 → 固定 5 句毒舌之一，
///  聊天链路永不抛、永不阻塞 UI。
///
///  纯本地可用：gateway 传 null（或没配 Key）时直接走兜底句。
/// ═══════════════════════════════════════════════════════════
class ChatService {
  ChatService({this.gateway, this.memory, this.persona = const Persona()});

  /// t9 的 OpenAI 兼容客户端经 [LlmGateway] 适配进来；null = 全走兜底。
  /// 只依赖 [CopyLlmGateway] 最小面（测试可注入假网关）
  final CopyLlmGateway? gateway;

  /// 长期记忆（每轮注入最相关 ≤8 条；重启仍在）
  final MemoryStore? memory;
  final Persona persona;

  /// 兜底句（docs/18 §2.6：固定 5 句毒舌之一）——句句毒舌但给下一步
  static const List<String> fallbackLines = <String>[
    '线路断了。……正好，省得你拿「在聊」当「在做」。先把今天那单交了。',
    '这会儿连不上我。连不上也得干活——你手里那单不会自己完成。',
    '……嘴暂时借不到网。跑步、背书、收拾屋子，挑一样，现在。',
    '回复晚点补。不过「等回复」不在今天的清单里，你的单在。',
    '信号不好，听不清。目标可没信号问题——它还在原地等你。',
  ];

  /// 与 copy.dart 同款 300 字符钳制（LLM 气话不能刷屏）
  static String _clamp(String s) =>
      s.length > 300 ? s.substring(0, 300) : s;

  /// 确定性选句（同输入稳定，可测；换句话说不必每次都同一句）
  static int _pick(List<String> pool, String seed) {
    int h = 0;
    for (final int c in seed.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h % pool.length;
  }

  /// 宿主档案一行（system prompt 的【宿主档案】段）
  static String statusLineOf({
    required String name,
    required int lv,
    required int streak,
    required int queue,
    required String goalShort,
  }) =>
      '$name · LV$lv · 连击 $streak · 手里 $queue 单'
      '${goalShort.isEmpty ? '' : ' · 主线「$goalShort」'}';

  /// 回一句。失败/无 LLM → 兜底毒舌（emotion=annoyed）。
  /// [scenario] 传「找小祥说说 / 换目标」等场合上下文（docs/18 §2.7）。
  Future<ChatMessage> reply(
    String userText, {
    List<ChatMessage> history = const <ChatMessage>[],
    String? scenario,
    String? statusLine,
  }) async {
    final CopyLlmGateway? gw = gateway;
    if (gw == null || !gw.configured) return _fallback(userText);
    try {
      // 近 12 轮做上下文（旧→新）；更早的交给长期记忆
      final List<Map<String, dynamic>> wire = <Map<String, dynamic>>[
        for (final ChatMessage m
            in history.length > 12 ? history.sublist(history.length - 12) : history)
          <String, dynamic>{
            'role': m.fromHost ? 'user' : 'assistant',
            'content': m.text,
          },
      ];
      final String digest = await memory?.digest(userText) ?? '';
      final String? raw = await gw.complete(
        messages: persona.buildConversation(
          userText: userText,
          history: wire,
          statusLine: statusLine,
          memoryDigest: digest,
          scenario: scenario,
        ),
        temperature: 0.8,
        maxTokens: 200,
        timeout: const Duration(seconds: 12),
      );
      if (raw == null) return _fallback(userText);
      final TaggedReply t = Persona.splitTag(raw);
      // 纯标签没有正文 = 当她没说话，走兜底
      if (t.text.isEmpty) return _fallback(userText);
      return ChatMessage.sys(
        _id(),
        _clamp(t.text),
        emotion: t.emotion,
      );
    } catch (_) {
      return _fallback(userText);
    }
  }

  ChatMessage _fallback(String seed) => ChatMessage.sys(
        _id(),
        fallbackLines[_pick(fallbackLines, '$seed|${fallbackLines.length}')],
        emotion: 'annoyed',
      );

  int _seq = 0;
  String _id() =>
      'c${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
}
