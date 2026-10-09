import '../agent/copy.dart';
import '../agent/llm_client.dart';
import '../agent/llm_gateway.dart';
import '../agent/memory.dart';
import '../agent/persona.dart';
import '../agent/tools.dart';
import 'chat_history.dart';

/// ═══════════════════════════════════════════════════════════
///  聊天回复服务（docs/18 §2.6 消息流 + docs/19 §A3 工具接线）
///
///  发送 → persona（人设+铁律）+ memory（相关 ≤8 条）+ 近几轮历史
///  → [LlmGateway]（OpenAI 兼容）→ `[情绪] 正文` → 气泡 + 舞台 mood。
///  **兜底铁律**：没配 Key / 无网 / 超时 / 空话 → 固定 5 句毒舌之一，
///  聊天链路永不抛、永不阻塞 UI。
///
///  **工具接线（A3）**：装配了 [client]+[tools] 且配了 Key 时走
///  function calling 循环：LLM 请求工具 → 注册表执行 → **结果回填**再问
///  → 最终回复；每次工具调用产出一条〔工具〕系统条目（写进聊天历史，
///  UI 可见）。没配 Key / 没接工具时 `respond` 退化为单条 [reply]——
///  快捷 chip 不经 LLM、直接 `registry.execute`，全部本地可用。
/// ═══════════════════════════════════════════════════════════
class ChatService {
  ChatService({this.gateway, this.client, this.tools, this.memory, this.persona = const Persona()});

  /// t9 的 OpenAI 兼容客户端经 [LlmGateway] 适配进来；null = 全走兜底。
  /// 只依赖 [CopyLlmGateway] 最小面（测试可注入假网关）
  final CopyLlmGateway? gateway;

  /// function calling 用的原始客户端（[tools] 非空时启用工具循环；
  /// LlmMessage 没有 tool_call_id 槽位——t9 文件，不动——所以回填走
  /// 「系统回执」用户消息，任何 OpenAI 兼容端点都收）
  final LlmClient? client;

  /// agent 工具注册表（docs/19 §A3：查状态/换任务/调整计划/记住/查记忆/总结）
  final AgentToolRegistry? tools;

  /// 长期记忆（每轮注入最相关 ≤8 条；重启仍在）
  final MemoryStore? memory;
  final Persona persona;

  /// 工具系统条目的正文前缀——chat_panel 据此换成系统条目样式
  /// （等宽读数风），历史持久化照常。
  static const String toolTag = '〔工具〕';

  /// function calling 的最大轮数（防模型无限要工具）
  static const int maxToolRounds = 3;

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
  /// 要工具循环（含〔工具〕系统条目）用 [respond]。
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

  /// 回一轮（docs/19 §A3）。**产物是一条列表**：LLM 要工具时，先产出
  /// 〔工具〕系统条目（每次调用一条，写进历史、UI 可见），最后一条才是
  /// 她的正式回复。没配 Key / 没接工具 / 客户端失败 → 退化为 [reply] 单条。
  Future<List<ChatMessage>> respond(
    String userText, {
    List<ChatMessage> history = const <ChatMessage>[],
    String? scenario,
    String? statusLine,
  }) async {
    final LlmClient? cli = client;
    final AgentToolRegistry? reg = tools;
    if (cli == null || reg == null || reg.isEmpty || cli.config.apiKey.trim().isEmpty) {
      return <ChatMessage>[
        await reply(userText, history: history, scenario: scenario, statusLine: statusLine),
      ];
    }
    try {
      final List<Map<String, dynamic>> wire = <Map<String, dynamic>>[
        for (final ChatMessage m
            in history.length > 12 ? history.sublist(history.length - 12) : history)
          <String, dynamic>{
            'role': m.fromHost ? 'user' : 'assistant',
            'content': m.text,
          },
      ];
      final String digest = await memory?.digest(userText) ?? '';
      final List<Map<String, dynamic>> msgs = persona.buildConversation(
        userText: userText,
        history: wire,
        statusLine: statusLine,
        memoryDigest: digest,
        scenario: scenario,
      );
      final List<LlmTool> defs = <LlmTool>[
        for (final AgentTool t in reg.all)
          LlmTool(name: t.name, description: t.description, parameters: t.parameters),
      ];
      final List<ChatMessage> out = <ChatMessage>[];
      for (int round = 0; round < maxToolRounds; round++) {
        final LlmReply r = await cli.chat(
          messages: <LlmMessage>[
            for (final Map<String, dynamic> m in msgs)
              LlmMessage('${m['role']}', '${m['content']}'),
          ],
          tools: defs,
          temperature: 0.8,
          maxTokens: 200,
        );
        if (!r.ok) {
          out.add(_fallback(userText));
          return out;
        }
        if (r.toolCalls.isEmpty) {
          final TaggedReply t = Persona.splitTag(r.text);
          if (t.text.isEmpty) {
            out.add(_fallback(userText));
            return out;
          }
          out.add(ChatMessage.sys(_id(), _clamp(t.text), emotion: t.emotion));
          return out;
        }
        // 执行 → 每次调用一条〔工具〕系统条目（写历史 + UI 可见）
        final StringBuffer receipts = StringBuffer();
        for (final LlmToolCall c in r.toolCalls) {
          final ToolOutcome oc = await reg.execute(c.name, c.arguments);
          final String line = '${c.name}：${oc.message}';
          receipts.writeln(line);
          out.add(ChatMessage.sys(_id(), '$toolTag$line', emotion: 'neutral'));
        }
        // 结果回填：她的上一条 + 系统回执（端点兼容形态），再要终答
        msgs.add(<String, dynamic>{
          'role': 'assistant',
          'content': r.text.trim().isEmpty ? '（正在翻你的档案……）' : r.text.trim(),
        });
        msgs.add(<String, dynamic>{
          'role': 'user',
          'content': '〔系统回执 · 刚才的工具调用结果，供你作答〕\n${receipts.toString().trim()}',
        });
      }
      out.add(_fallback(userText)); // 轮次用尽还没终答——兜底收口，不吊着用户
      return out;
    } catch (_) {
      return <ChatMessage>[_fallback(userText)];
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
