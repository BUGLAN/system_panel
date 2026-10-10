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
  ChatService({
    this.gateway,
    this.client,
    this.tools,
    this.memory,
    this.persona = const Persona(),
    this.strict = false,
  });

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

  /// 严格模式（docs/22 §2.0）：开发构建默认开——失败**不产假台词**，
  /// 直接给一条诊断条目（HTTP 状态/超时/正文为空 + 原文）。release 关。
  final bool strict;

  /// 工具系统条目的正文前缀——chat_panel 据此换成系统条目样式
  /// （等宽读数风），历史持久化照常。
  static const String toolTag = '〔工具〕';

  /// 诊断条目前缀（严格模式下的失败出口）
  static const String diagTag = '〔诊断〕';

  /// 兜底标注前缀（非严格模式：兜底照样发生，但必须看得见）
  static const String fallbackTag = '〔兜底〕';

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

  /// 宿主档案一行（system prompt 的【宿主档案】段）。
  ///
  /// [ringDone]/[ringTotal] 是主线环进度——**必须喂**（验收 F-3）：
  /// 不喂，模型就会从聊天历史里那条旧 `〔工具〕get_status` 回执里捡数字，
  /// 于是出现「主线还挂着 6 环没动」这种过期读数，直接违背「引用真实数据」。
  static String statusLineOf({
    required String name,
    required int lv,
    required int streak,
    required int queue,
    required String goalShort,
    int? ringDone,
    int? ringTotal,
  }) =>
      '$name · LV$lv · 连击 $streak · 手里 $queue 单'
      '${goalShort.isEmpty ? '' : ' · 主线「$goalShort」'}'
      '${ringTotal == null || ringTotal == 0 ? '' : ' · 主线进度 ${ringDone ?? 0}/$ringTotal 环'}';

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
    if (gw == null || !gw.configured) {
      return _failure(userText, detail: '未配置 API Key');
    }
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
        // 端点是推理模型：max_tokens 同时算思考与正文，给太紧正文必空（docs/22 R1）
        maxTokens: 1024,
        timeout: const Duration(seconds: 12),
      );
      if (raw == null) {
        return _failure(userText, detail: _detailOf(gw));
      }
      final TaggedReply t = Persona.splitTag(raw);
      // 纯标签没有正文 = 当她没说话，走失败出口
      if (t.text.isEmpty) {
        return _failure(userText, detail: '正文只有情绪标签，没有台词');
      }
      return ChatMessage.sys(
        _id(),
        _clamp(t.text),
        emotion: t.emotion,
      );
    } catch (e) {
      return _failure(userText, detail: '异常：$e');
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
          // 端点是推理模型：思考与正文共用这个预算（docs/22 R1）
          maxTokens: 1024,
        );
        if (!r.ok) {
          out.add(_failure(
            userText,
            detail: '${r.failure?.name ?? 'unknown'} · ${r.detail ?? '无 detail'}',
          ));
          return out;
        }
        if (r.toolCalls.isEmpty) {
          final TaggedReply t = Persona.splitTag(r.text);
          if (t.text.isEmpty) {
            out.add(_failure(
              userText,
              detail: '正文为空（HTTP 200；推理模型可能把 max_tokens 用尽，'
                  'finish_reason 多半是 length）',
            ));
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
      out.add(_failure(userText, detail: '工具循环 $maxToolRounds 轮用尽仍没有终答'));
      return out;
    } catch (e) {
      return <ChatMessage>[_failure(userText, detail: '异常：$e')];
    }
  }

  /// 失败出口（docs/22 §2.0）——**兜底不许再默默发生**：
  ///
  /// - **严格模式**（开发构建）：不产假台词，给一条 `〔诊断〕` 条目，
  ///   把失败类别与原文（截断）直接摆到宿主面前，问题一眼可见。
  /// - **非严格模式**（release）：仍给兜底毒舌（无 Key/断网不得阻塞使用），
  ///   但句首 `〔兜底〕` 标注 + 括注原因——看得见降级，不会误以为她真这么说了。
  ChatMessage _failure(String seed, {String? detail}) {
    final String why =
        (detail == null || detail.trim().isEmpty) ? '未知原因' : detail.trim();
    if (strict) {
      return ChatMessage.sys(
        _id(),
        '$diagTag LLM 失败 · ${_clamp(why)}',
        emotion: 'annoyed',
      );
    }
    final String line =
        fallbackLines[_pick(fallbackLines, '$seed|${fallbackLines.length}')];
    final String short = why.length > 60 ? '${why.substring(0, 60)}…' : why;
    return ChatMessage.sys(
      _id(),
      '$fallbackTag$line（$short）',
      emotion: 'annoyed',
    );
  }

  /// 从网关捞最近一次失败原因（[CopyLlmGateway] 契约只有「失败返回 null」，
  /// 真实现 [LlmGateway] 才带得动 detail；测试替身捞不到就回 null）。
  static String? _detailOf(CopyLlmGateway gw) {
    if (gw is LlmGateway) {
      final LlmReply? r = gw.lastReply;
      if (r == null) return null;
      final String kind = r.failure?.name ?? 'unknown';
      final String detail = r.detail ?? '';
      return detail.isEmpty ? kind : '$kind · $detail';
    }
    return null;
  }

  int _seq = 0;
  String _id() =>
      'c${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
}
