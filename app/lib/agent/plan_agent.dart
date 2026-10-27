/// 拆计划的 Agent —— 她**作为 agent** 拆目标，而不是当 JSON 生成器。
///
/// ═══════════════════════════════════════════════════════════
///  2026-10-23 宿主定调（本次重写的全部理由）
/// ═══════════════════════════════════════════════════════════
///  ① **不许兜底/降级**：旧版失败时 `hasPlan=false`，调用方静默退回类别模板
///     —— 于是「两周骑 10 次」被铸成「把目标写在纸上」×4，宿主只看到坏清单。
///     现在任何失败都抛 [PlanFailure]，`PlanAgent.generate()` 只有两种结局：
///     交出一份**过完规则校验**的任务池，或者抛异常。没有第三条路。
///  ② **匹配/拆解都走 LLM Agent**：类别与内容都不再靠关键词表与模板，
///     由她自己 `get_status` → （必要时 `recall`）→ `set_plan`。
///  ③ **任务卡片结构稳定**：唯一出口是 `set_plan` 的 JSON Schema，
///     落成 `List<TaskSpec>` → `PlanTask`，字段/类型/顺序全固定。
///
/// 时序（与 `ChatService.respond` 同一套 function calling 循环）：
///   ① system = 人设 + 宿主档案 + 长期记忆（`Persona.buildConversation`）
///   ② 她调 `get_status` / `recall`
///   ③ 她调 `set_plan` 交出 N 张任务（结构化输出走 JSON Schema）
///   ④ 形状不对 → 工具**抛** [PlanShapeError]，循环当场终止（不给她「重来」）
///   ⑤ 她输出一句话解释为什么这么排（剥 [情绪] 标签）
library;

import '../state/goal_gen.dart';
import '../state/plan_failure.dart';
import 'llm_client.dart';
import 'mainline_tool.dart';
import 'memory.dart';
import 'persona.dart';
import 'plan_brief.dart';
import 'tools.dart';

/// 一轮拆解的结果。**只有成功才会被构造出来**（失败一律抛异常）。
class PlanResult {
  const PlanResult({
    required this.tasks,
    required this.line,
    required this.emotion,
    required this.receipts,
    required this.rounds,
  });

  /// 她交上来的任务（形状已过 schema 校验；规则校验在 `buildGoalFromPlan`）
  final List<TaskSpec> tasks;

  /// 她解释为什么这么排（已剥情绪标签）。null = 她只交了工具没说话。
  final String? line;

  /// 情绪标签（舞台用），解析不到就是 neutral。
  final String emotion;

  /// 〔工具〕回执（诊断用）
  final List<String> receipts;

  /// 实际跑了几轮
  final int rounds;
}

class PlanAgent {
  PlanAgent({
    required this.client,
    this.persona = const Persona(),
    this.memory,
    // 宿主 2026-10-12：「不用那么省」，而且允许她**改版**（第一版往往不是
    // 最好的），所以轮数放宽到 6。
    this.maxRounds = 6,
    // 立主线**要**思考（权衡等级/连败/最弱维）：预算给足。
    this.maxTokens = kPlanMaxTokens,
  });

  final LlmClient client;
  final Persona persona;
  final MemoryStore? memory;
  final int maxRounds;
  final int maxTokens;

  /// 跑一轮拆解。**成功返回结果，任何失败都抛 [PlanFailure]**。
  ///
  /// [tools] 必须已经注册好 `set_plan`（用 [setPlanTool] 造），通常还会带上
  /// `get_status` / `recall`；且**必须是 [StrictAgentToolRegistry]**，
  /// 否则工具失败会被折成回执而不是抛出。
  Future<PlanResult> generate({
    required PlanBrief brief,
    required AgentToolRegistry tools,
    required PlanDraft draft,
  }) async {
    if (client.config.apiKey.trim().isEmpty) {
      throw const PlanGenerationError(
        PlanFailureCode.noKey,
        '未配置 API Key：拆解只能走 LLM，没有 Key 就没有计划',
      );
    }
    // 宽容版注册表会把工具失败折成"回执"回填给模型 —— 那就把失败藏进了多轮
    // 循环里（本次改造要根除的东西）。这里直接挡住，让装配错误当场暴露。
    if (tools is! StrictAgentToolRegistry) {
      throw StateError(
        'PlanAgent 必须用 StrictAgentToolRegistry（收到 undefined）：'
        '宽容版会把工具失败折成回执，失败就看不见了',
      );
    }
    final List<String> receipts = <String>[];
    final String digest = await memory?.digest(brief.goalText) ?? '';
    final List<Map<String, dynamic>> msgs = persona.buildConversation(
      userText: brief.userText,
      statusLine: brief.statusLine,
      memoryDigest: digest,
      scenario: brief.scenario,
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
        temperature: 0.7,
        maxTokens: maxTokens,
        reasoningEffort: planReasoningEffort(client.config.reasoningEffort),
        // 拆解是长推理 + 工具循环：单轮 40s 属正常（12s 会误判成超时）
        timeout: const Duration(seconds: 90),
      );
      if (!r.ok) {
        throw PlanGenerationError(
          _codeOf(r.failure),
          '第 $round 轮请求失败：${r.failure?.name ?? 'unknown'} · ${r.detail ?? '无 detail'}',
        );
      }
      if (r.toolCalls.isEmpty) {
        if (draft.tasks == null) {
          throw PlanGenerationError(
            PlanFailureCode.noPlan,
            '第 $round 轮她只说了话、没有调用 set_plan（正文：${_clip(r.text)}）',
          );
        }
        final TaggedReply t = Persona.splitTag(r.text);
        return PlanResult(
          tasks: draft.tasks!,
          line: t.text.isEmpty ? null : t.text,
          emotion: t.emotion,
          receipts: receipts,
          rounds: round,
        );
      }
      // 执行工具 → 回执回填，让她据结果继续。
      //
      // ⚠️ 形状错（`PlanShapeError`）**给它看一次原因、重交一次**：
      //    真机实测本地微调模型会自造类别 id / 条数差一张，直接抛会把
      //    「模型差一点就对了」误报成产品故障。规则错（`PlanRuleError`）
      //    与其它一切异常仍然直接抛，不重试。
      final StringBuffer feed = StringBuffer();
      for (final LlmToolCall c in r.toolCalls) {
        try {
          final ToolOutcome oc = await tools.execute(c.name, c.arguments);
          final String line = '${c.name}：${oc.message}';
          receipts.add(line);
          feed.writeln(line);
        } on PlanShapeError catch (e) {
          if (round >= maxRounds) rethrow;
          final String line = '${c.name} 参数不合法：${e.detail}';
          receipts.add(line);
          feed.writeln(line);
        } on PlanRuleError catch (e) {
          // ⚠️ 规则错（档位越界 / 首目标给了 S / 条数不对）同样是「模型差一点
          //    就对了」：把原因回填让她重交，而不是整份计划直接作废。
          //    只有轮数用尽才把最后一次原因抛出去（界面照实显示）。
          if (round >= maxRounds) rethrow;
          final String line = '${c.name} 被规则驳回：${e.detail}。请按规则重交整份计划。';
          receipts.add(line);
          feed.writeln(line);
        }
      }
      // 工具已经交上计划且这一轮没干别的 → **立刻收工**。
      //
      // ⚠️ 不能要求"这一轮必须带一句台词"：模型调 set_plan 时 content 常常是
      //    空的（结构化输出走 tool_calls），那样会一直空转到轮数用尽再抛，
      //    明明计划已经拿到了。她的解释可以为 null（PlanResult.line 允许空）。
      if (draft.tasks != null) {
        final bool otherCalls = r.toolCalls.any(
          (LlmToolCall c) => c.name != 'set_plan',
        );
        if (!otherCalls) {
          final TaggedReply t = Persona.splitTag(r.text);
          return PlanResult(
            tasks: draft.tasks!,
            line: t.text.isEmpty ? null : t.text,
            emotion: t.emotion,
            receipts: receipts,
            rounds: round,
          );
        }
      }
      msgs.add(<String, dynamic>{
        'role': 'assistant',
        'content': r.text.trim().isEmpty ? '（她正在翻宿主的档案……）' : r.text.trim(),
      });
      msgs.add(<String, dynamic>{
        'role': 'user',
        'content':
            '〔系统回执〕刚才的工具调用结果：\n${feed.toString().trim()}'
            '${draft.tasks == null ? '\n\n（主线还没交上来：调用 set_plan 把 ${brief.taskCount} 张交上来。）' : '\n\n（主线已收到。**现在就不要再调用任何工具**，只用一句话告诉他为什么这么排。）'}',
      });
    }
    throw PlanGenerationError(
      PlanFailureCode.noPlan,
      '工具循环 $maxRounds 轮用尽仍没拿到 set_plan 的任务池（回执：${receipts.join(' | ')}）',
    );
  }

  /// [LlmFailure] → [PlanFailureCode]（失败类别原样往上抛，不折叠）
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
