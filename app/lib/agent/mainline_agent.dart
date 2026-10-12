/// 拆计划的 agent 循环 —— 她**作为 agent** 拆目标，而不是当 JSON 生成器。
///
/// 时序（与 `ChatService.respond` 同一套 function calling 循环，见 docs/18 §2.5）：
///
///   ① system = 人设 + 宿主档案 + 长期记忆      （`Persona.buildConversation`）
///   ② 她调 `get_status`（看等级/连败/最弱维）· 必要时 `recall`（翻记忆）
///   ③ 她调 `set_plan` 交出 N 张任务        ← 结构化输出走 JSON Schema
///   ④ 参数不合格 → 工具返回 fail → **她看得见原因并当场重来**
///   ⑤ 她输出一句话解释为什么这么排（剥 `[情绪]` 标签）
///
/// 与旧的一次性 `GoalPlanner` 的区别就是宿主指出的那一点：这条路**接工具、
/// 接状态、接记忆**，而且失败是可见、可重试的。
///
/// ⚠️ 兜底铁律不变：没配 Key / 无网 / 她把工具用糊了 → [MainlineResult.committed]
///    为 false，调用方逐字退回类别模板（`goal_gen` 的既有路径）。
library;

import '../state/goal_gen.dart';
import 'llm_client.dart';
import 'mainline_tool.dart';
import 'memory.dart';
import 'persona.dart';
import 'tools.dart';

/// 一轮立主线的结果。
class MainlineResult {
  const MainlineResult({
    required this.tasks,
    required this.line,
    required this.emotion,
    required this.receipts,
    required this.rounds,
    required this.failure,
  });

  /// 她交上来的任务（形状已过校验、**阶梯还没收口**）。null = 她没交出来。
  final List<TaskSpec>? tasks;

  /// 她解释为什么这么排（已剥情绪标签）。null = 她没给话。
  final String? line;

  /// 情绪标签（舞台用），解析不到就是 neutral。
  final String emotion;

  /// 〔工具〕回执（诊断 / 需要时可显给宿主看）
  final List<String> receipts;

  /// 实际跑了几轮
  final int rounds;

  /// 失败原因（正常收敛时为 null）
  final String? failure;

  /// 她真的把主线交出来了吗
  bool get hasPlan => tasks != null && tasks!.isNotEmpty;
}

class MainlineAgent {
  MainlineAgent({
    required this.client,
    this.persona = const Persona(),
    this.memory,
    // 宿主 2026-10-12：「不用那么省」，而且允许她**改版**（第一版往往不是
    // 最好的），所以轮数放宽到 6。
    this.maxRounds = 6,
    // 立主线**要**思考（权衡等级/连败/最弱维）：预算给足，
    // 档位跟随设置页但**至少 low** —— 详见 kPlanReasoningEffort。
    this.maxTokens = kPlanMaxTokens,
  });

  final LlmClient client;
  final Persona persona;
  final MemoryStore? memory;
  final int maxRounds;
  final int maxTokens;

  /// 跑一轮：[tools] 里必须已经注册好 `set_plan`（用 [setPlanTool] 造），
  /// 通常还会带上 `get_status` / `recall`。
  ///
  /// [statusLine] 是宿主档案一行（`get_status` 之外再给一次摘要，省她一轮）。
  Future<MainlineResult> run({
    required String goalText,
    required int taskCount,
    required AgentToolRegistry tools,
    required PlanDraft draft,
    String? statusLine,
  }) async {
    final List<String> receipts = <String>[];
    if (client.config.apiKey.trim().isEmpty) {
      return MainlineResult(
        tasks: null,
        line: null,
        emotion: 'neutral',
        receipts: receipts,
        rounds: 0,
        failure: '未配置 API Key',
      );
    }
    try {
      final String digest = await memory?.digest(goalText) ?? '';
      final List<Map<String, dynamic>> msgs = persona.buildConversation(
        userText: _brief(goalText, taskCount),
        statusLine: statusLine,
        memoryDigest: digest,
        scenario: '拆计划：把宿主刚说的目标拆成 $taskCount 张单次可执行的任务。先看清楚他现在的状态。',
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
        );
        if (!r.ok) {
          return MainlineResult(
            tasks: draft.tasks,
            line: null,
            emotion: 'neutral',
            receipts: receipts,
            rounds: round,
            failure: '${r.failure?.name ?? 'unknown'} · ${r.detail ?? ''}',
          );
        }
        if (r.toolCalls.isEmpty) {
          final TaggedReply t = Persona.splitTag(r.text);
          return MainlineResult(
            tasks: draft.tasks,
            line: t.text.isEmpty ? null : t.text,
            emotion: t.emotion,
            receipts: receipts,
            rounds: round,
            // 她聊完了却没交主线 —— 也算失败（调用方退回模板）
            failure: draft.tasks == null ? '她没调用 set_plan' : null,
          );
        }
        // 执行工具 → 回执回填，让她据结果继续（失败也一样回填，她要重试）
        final StringBuffer feed = StringBuffer();
        for (final LlmToolCall c in r.toolCalls) {
          final ToolOutcome oc = await tools.execute(c.name, c.arguments);
          final String line = '${c.name}：${oc.message}';
          receipts.add(line);
          feed.writeln(line);
        }
        msgs.add(<String, dynamic>{
          'role': 'assistant',
          'content': r.text.trim().isEmpty ? '（她正在翻宿主的档案……）' : r.text.trim(),
        });
        msgs.add(<String, dynamic>{
          'role': 'user',
          'content': '〔系统回执〕刚才的工具调用结果：\n${feed.toString().trim()}'
              // 主线收到之后：**允许她改版**（宿主定调「不用那么省」，而且
              // 真机实测第二版常常更好：跨度从"三天"排到"两周"），但要说清
              // 「不改就给话」，否则她会一直空转工具、不给终答。
              '${draft.tasks == null ? '\n\n（主线还没交上来：调用 set_plan 把 $taskCount 张交上来。）' : '\n\n（主线已收到。若你觉得还能排得更好，可以再用 set_plan 改一版；否则**现在就不要再调用任何工具**，只用一句话告诉他为什么这么排。）'}',
        });
      }
      return MainlineResult(
        tasks: draft.tasks,
        line: null,
        emotion: 'neutral',
        receipts: receipts,
        rounds: maxRounds,
        failure: '工具循环 $maxRounds 轮用尽',
      );
    } catch (e) {
      // 兜底铁律：这条链路上任何异常都折回模板
      return MainlineResult(
        tasks: draft.tasks,
        line: null,
        emotion: 'neutral',
        receipts: receipts,
        rounds: 0,
        failure: '异常：$e',
      );
    }
  }

  String _brief(String goalText, int taskCount) =>
      '宿主刚立了目标：「$goalText」。\n'
      '把它拆成 $taskCount 张主线，用 set_plan 交给我。\n'
      '拆之前先看清他现在的状态（get_status），有必要就 recall 翻记忆；'
      '交完用一句话说明为什么这么排。';
}
