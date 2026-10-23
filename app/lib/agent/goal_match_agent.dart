/// 目标匹配 Agent —— 判断类别 / 天幕短字 / 期限。
///
/// 2026-10-23 宿主定调：匹配环节也走 LLM + 既有 Agent 能力，
/// **不再用正则关键词表**（旧表里没有「骑/自行车」，于是骑行目标掉进兜底
/// 类别 gen，被拆成「把目标写在纸上」）。
///
/// 与 [PlanAgent] 同一套循环：她先 `get_status`（必要时 `recall`），
/// 再调 `set_goal_category` 交结果。失败一律抛，不猜、不兜底。
library;

import '../state/plan_failure.dart';
import 'copy.dart';
import 'llm_client.dart';
import 'mainline_tool.dart';
import 'memory.dart';
import 'persona.dart';
import 'tools.dart';

class GoalMatchAgent {
  GoalMatchAgent({
    required this.client,
    this.persona = const Persona(),
    this.memory,
    this.maxRounds = 4,
    this.maxTokens = kLineMaxTokens,
  });

  final LlmClient client;
  final Persona persona;
  final MemoryStore? memory;
  final int maxRounds;
  final int maxTokens;

  /// 匹配 [goalText]。成功返回 [GoalMatch]，任何失败都抛 [PlanFailure]。
  Future<GoalMatch> match({
    required String goalText,
    required AgentToolRegistry tools,
    required GoalMatchDraft draft,
    String? statusLine,
  }) async {
    if (client.config.apiKey.trim().isEmpty) {
      throw const PlanGenerationError(
        PlanFailureCode.noKey,
        '未配置 API Key：目标匹配只能走 LLM，没有 Key 就分不出类别',
      );
    }
    // 同 PlanAgent：宽容版注册表会把工具失败折成回执，失败就看不见了
    if (tools is! StrictAgentToolRegistry) {
      throw StateError(
        'GoalMatchAgent 必须用 StrictAgentToolRegistry（收到 undefined）',
      );
    }
    final String digest = await memory?.digest(goalText) ?? '';
    final List<Map<String, dynamic>> msgs = persona.buildConversation(
      userText: '宿主立了目标：「$goalText」。\n'
          '用 set_goal_category 告诉我：它属于哪一类、天幕短字写什么、期限多少天。',
      statusLine: statusLine,
      memoryDigest: digest,
      scenario: '识别目标：判断类别/短字/期限，交给 set_goal_category。',
    );
    final List<LlmTool> defs = <LlmTool>[
      for (final AgentTool t in tools.all)
        LlmTool(
          name: t.name,
          description: t.description,
          parameters: t.parameters,
        ),
    ];
    for (int round = 1; round <= maxRounds; round++) {
      final LlmReply r = await client.chat(
        messages: <LlmMessage>[
          for (final Map<String, dynamic> m in msgs)
            LlmMessage('${m['role']}', '${m['content']}'),
        ],
        tools: defs,
        temperature: 0.3,
        maxTokens: maxTokens,
        reasoningEffort: planReasoningEffort(client.config.reasoningEffort),
      );
      if (!r.ok) {
        throw PlanGenerationError(
          _codeOf(r.failure),
          '第 $round 轮匹配请求失败：${r.failure?.name ?? 'unknown'} · ${r.detail ?? '无 detail'}',
        );
      }
      if (r.toolCalls.isEmpty) {
        final GoalMatch? got = draft.match;
        if (got == null) {
          throw PlanGenerationError(
            PlanFailureCode.noPlan,
            '第 $round 轮她没调用 set_goal_category（正文：${_clip(r.text)}）',
          );
        }
        return got;
      }
      final StringBuffer feed = StringBuffer();
      for (final LlmToolCall c in r.toolCalls) {
        try {
          final ToolOutcome oc = await tools.execute(c.name, c.arguments);
          feed.writeln('${c.name}：${oc.message}');
        } on PlanShapeError catch (e) {
          // 形状错 = 模型没按 schema 交。**只给它看一次原因再重交**；
          // 下一轮还错就直接抛（不无限重试，也不猜）。
          if (round >= maxRounds) rethrow;
          feed.writeln('${c.name} 参数不合法：${e.detail}');
        }
      }
      final GoalMatch? got = draft.match;
      if (got != null) return got;
      msgs.add(<String, dynamic>{
        'role': 'assistant',
        'content': r.text.trim().isEmpty ? '（她在看这条目标……）' : r.text.trim(),
      });
      msgs.add(<String, dynamic>{
        'role': 'user',
        'content': '〔系统回执〕\n${feed.toString().trim()}\n\n'
            '（还没交上来：调用 set_goal_category。）',
      });
    }
    throw PlanGenerationError(
      PlanFailureCode.noPlan,
      '匹配循环 $maxRounds 轮用尽仍没拿到 set_goal_category 的结果',
    );
  }

  static PlanFailureCode _codeOf(LlmFailure? f) => switch (f) {
    LlmFailure.noKey => PlanFailureCode.noKey,
    LlmFailure.network => PlanFailureCode.network,
    LlmFailure.timeout => PlanFailureCode.timeout,
    LlmFailure.httpError => PlanFailureCode.httpError,
    LlmFailure.badResponse => PlanFailureCode.badResponse,
    null => PlanFailureCode.badResponse,
  };

  static String _clip(String s) {
    final String t = s.trim().replaceAll('\n', ' ');
    return t.length <= 120 ? t : '${t.substring(0, 120)}…';
  }
}
