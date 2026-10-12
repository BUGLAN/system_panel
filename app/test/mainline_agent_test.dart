import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:system_panel/agent/llm_client.dart';
import 'package:system_panel/agent/mainline_agent.dart';
import 'package:system_panel/agent/mainline_tool.dart';
import 'package:system_panel/agent/memory.dart';
import 'package:system_panel/agent/tools.dart';
import 'package:system_panel/state/quest.dart';

/// 立主线的 agent 循环（2026-10-12 宿主指出的改造）。
///
/// 要点：
///  · 拆解走 **function calling 的结构化输出**（不是"求它输出 JSON 再手抠"）
///  · 形状不合格 → 工具返回 fail → **她看得见原因并重来**（guardrail 在工具层）
///  · 没配 Key / 她没交主线 / 循环用尽 → `hasRings == false`，调用方退回类别模板
void main() {
  /// 8 环的合法参数（内容不重要，形状对就行）
  Map<String, dynamic> goodRings([int n = 8]) => <String, dynamic>{
    'rings': <Map<String, dynamic>>[
      for (int i = 0; i < n; i++)
        <String, dynamic>{
          'short': '环${i + 1}',
          'title': '第 ${i + 1} 步做什么',
          'proof': '证据${i + 1}',
          'minutes': 10 + i,
          'rank': 'E',
        },
    ],
  };

  String toolCall(
    String name, [
    Map<String, dynamic> args = const <String, dynamic>{},
  ]) =>
      '{"choices":[{"message":{"content":"","tool_calls":[{"id":"c1",'
      '"type":"function","function":{"name":"$name","arguments":'
      '${jsonEncode(jsonEncode(args))}}}]}}]}';

  String says(String text) =>
      '{"choices":[{"message":{"content":${jsonEncode(text)}}}]}';

  /// 按顺序回话的假 HTTP（录下每个请求体）
  http.Client scripted(List<String> bodies, List<String> responses) =>
      MockClient((http.Request req) async {
        bodies.add(req.body);
        return http.Response(
          responses.isEmpty ? says('（没了）') : responses.removeAt(0),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });

  AgentToolRegistry registryWith(MainlineDraft draft, {int ringCount = 8}) {
    final AgentToolRegistry reg = AgentToolRegistry();
    reg.registerAll(
      defaultAgentTools(
        context: MockAgentContext(queue: <Quest>[]),
        memory: MemoryStore(),
      ).all,
    );
    reg.register(
      setMainlineTool(
        goalText: '半年减重 10 斤',
        ringCount: ringCount,
        draft: draft,
      ),
    );
    return reg;
  }

  group('set_mainline 工具 · 形状校验（guardrail 在工具执行层）', () {
    test('合法 8 环 → ok，草案写入，回执给首尾环', () async {
      final MainlineDraft draft = MainlineDraft();
      final AgentToolRegistry reg = registryWith(draft);
      final ToolOutcome oc = await reg.execute('set_mainline', goodRings());
      expect(oc.ok, isTrue);
      expect(draft.rings, hasLength(8));
      expect(draft.rings!.first.short, '环1');
      expect(oc.message, contains('8 环'));
      expect((oc.data!['rings'] as List<dynamic>), hasLength(8));
    });

    test('⚠️ 条数不对 → fail 且**不写入草案**（她必须重来，不能截断或补齐）', () async {
      for (final int n in <int>[6, 7, 9]) {
        final MainlineDraft draft = MainlineDraft();
        final AgentToolRegistry reg = registryWith(draft);
        final ToolOutcome oc = await reg.execute('set_mainline', goodRings(n));
        expect(oc.ok, isFalse, reason: '给了 $n 环');
        expect(oc.message, contains('正好 8 环'), reason: '要说清差在哪');
        expect(oc.message, contains('$n 环'), reason: '要把实际条数报给她');
        expect(draft.rings, isNull, reason: '不合格的一律不落草案');
      }
    });

    test('rings 缺失 / 不是数组 / 是空数组 → fail', () async {
      for (final Object? raw in <Object?>[
        null,
        'notalist',
        <dynamic>[],
        <String, dynamic>{},
      ]) {
        final MainlineDraft draft = MainlineDraft();
        final AgentToolRegistry reg = registryWith(draft);
        final ToolOutcome oc = await reg.execute('set_mainline', <String, dynamic>{
          'rings': raw,
        });
        expect(oc.ok, isFalse, reason: 'rings=$raw');
        expect(draft.rings, isNull);
      }
    });

    test('字段空 / 档位非法 / 分钟数非正 → fail，并指明是第几环', () async {
      final List<Map<String, dynamic>> bad = <Map<String, dynamic>>[
        <String, dynamic>{'short': '', 'title': 't', 'proof': 'p', 'minutes': 10, 'rank': 'E'},
        <String, dynamic>{'short': 's', 'title': '  ', 'proof': 'p', 'minutes': 10, 'rank': 'E'},
        <String, dynamic>{'short': 's', 'title': 't', 'proof': 'p', 'minutes': 10, 'rank': 'Z'},
        <String, dynamic>{'short': 's', 'title': 't', 'proof': 'p', 'minutes': 0, 'rank': 'E'},
        <String, dynamic>{'short': 's', 'title': 't', 'proof': 'p', 'minutes': -5, 'rank': 'E'},
        <String, dynamic>{'short': 's', 'title': 't', 'proof': 'p', 'rank': 'E'},
      ];
      for (final Map<String, dynamic> one in bad) {
        final MainlineDraft draft = MainlineDraft();
        final AgentToolRegistry reg = registryWith(draft, ringCount: 1);
        final ToolOutcome oc = await reg.execute('set_mainline', <String, dynamic>{
          'rings': <Map<String, dynamic>>[one],
        });
        expect(oc.ok, isFalse, reason: '$one');
        expect(oc.message, contains('第 1 环'), reason: '要指出是哪一环坏了：$one');
        expect(draft.rings, isNull);
      }
    });

    test('schema 把环数写进描述（模型据此知道要几条）', () {
      final Map<String, dynamic> schema = setMainlineSchema(5);
      final Map<String, dynamic> rings =
          (schema['properties'] as Map<String, dynamic>)['rings'] as Map<String, dynamic>;
      expect(rings['minItems'], 5);
      expect(rings['maxItems'], 5);
      expect('${rings['description']}', contains('正好 5 环'));
      final Map<String, dynamic> item =
          ((rings['items'] as Map<String, dynamic>)['properties'] as Map<String, dynamic>);
      expect((item['rank'] as Map<String, dynamic>)['enum'], contains('S'));
      expect((rings['items'] as Map<String, dynamic>)['required'],
          containsAll(<String>['short', 'title', 'proof', 'minutes', 'rank']));
    });
  });

  group('思考档位策略（宿主可在设置页关掉思考换速度）', () {
    test('拆解/工具循环有下限：设置成关/最低也只降到 low', () {
      for (final String off in <String>['', 'none', 'minimal', 'NONE', '  ']) {
        expect(planReasoningEffort(off), kPlanReasoningEffort, reason: 'off="$off"');
      }
    });

    test('设置成 low/high/max 时原样透传（宿主说了算）', () {
      for (final String e in <String>['low', 'high', 'max', 'High']) {
        expect(planReasoningEffort(e), e.trim().toLowerCase());
      }
    });
  });

  group('MainlineAgent.run · 真正的 agent 循环', () {
    test('get_status → set_mainline → 她解释（两轮收敛）', () async {
      final List<String> bodies = <String>[];
      final MainlineDraft draft = MainlineDraft();
      final AgentToolRegistry reg = registryWith(draft);
      final MainlineAgent agent = MainlineAgent(
        client: LlmClient(
          config: const LlmConfig(apiKey: 'sk-test'),
          httpClient: scripted(bodies, <String>[
            // 第 1 轮：她先查状态、同轮把主线交上来
            '{"choices":[{"message":{"content":"","tool_calls":['
                '{"id":"c1","type":"function","function":{"name":"get_status","arguments":"{}"}},'
                '{"id":"c2","type":"function","function":{"name":"set_mainline","arguments":'
                '${jsonEncode(jsonEncode(goodRings()))}}}]}}]}',
            // 第 2 轮：她解释
            says('[smug]你连败两次，第一环我给你压到 10 分钟。八环，别再断。'),
          ]),
        ),
      );
      final MainlineResult r = await agent.run(
        goalText: '半年减重 10 斤',
        ringCount: 8,
        tools: reg,
        draft: draft,
        statusLine: 'LV1 · 连败 2 次',
      );
      expect(r.rounds, 2);
      expect(r.failure, isNull);
      expect(r.hasRings, isTrue);
      expect(r.rings, hasLength(8));
      expect(r.line, '你连败两次，第一环我给你压到 10 分钟。八环，别再断。');
      expect(r.emotion, 'smug', reason: '情绪标签要剥出来给舞台用');
      expect(r.receipts, hasLength(2));
      expect(r.receipts.first, contains('get_status'));
      expect(r.receipts.last, contains('set_mainline'));
      // 请求里真的带上了工具的 JSON Schema（结构化输出，不是让她自由写 JSON）
      expect(bodies.first, contains('"set_mainline"'));
      expect(bodies.first, contains('"parameters"'));
      // 立主线**要**思考：预算给足（宿主定调不用省），档位走"至少 low"
      expect(bodies.first, contains('"max_tokens":$kPlanMaxTokens'));
      expect(bodies.first, contains('"reasoning_effort":"low"'));
    });

    test('⚠️ 交错了条数 → 工具 fail → 她看见原因重来 → 最终成功', () async {
      final List<String> bodies = <String>[];
      final MainlineDraft draft = MainlineDraft();
      final AgentToolRegistry reg = registryWith(draft);
      final MainlineAgent agent = MainlineAgent(
        client: LlmClient(
          config: const LlmConfig(apiKey: 'sk-test'),
          httpClient: scripted(bodies, <String>[
            toolCall('set_mainline', goodRings(6)), // 错了：要 8 环
            toolCall('set_mainline', goodRings(8)), // 看见回执后改对
            says('[cold]行。八环钉上了。'),
          ]),
        ),
      );
      final MainlineResult r = await agent.run(
        goalText: '半年减重 10 斤',
        ringCount: 8,
        tools: reg,
        draft: draft,
      );
      expect(r.rounds, 3);
      expect(r.failure, isNull);
      expect(r.rings, hasLength(8));
      expect(r.line, '行。八环钉上了。');
      // 第一次的失败回执必须回填给她（否则她没法知道差在哪）
      expect(r.receipts.first, contains('正好 8 环'));
      // 回填的第二条里明确提示她「主线还没交上来」
      expect(bodies[1], contains('主线还没交上来'));

      // ⚠️ 主线收到之后必须明确说「别再调工具」——真机实测她会在成功后
      //    再交一版（白烧 700 个思考 token，看着还像改了主意）
      // 回执是拼进**下一次**请求的，所以这条提示在第 3 个请求体里
      expect(bodies.last, contains('不要再调用任何工具'));
    });

    test('她聊完却没调用 set_mainline → hasRings=false（调用方退回模板）', () async {
      final MainlineDraft draft = MainlineDraft();
      final AgentToolRegistry reg = registryWith(draft);
      final MainlineAgent agent = MainlineAgent(
        client: LlmClient(
          config: const LlmConfig(apiKey: 'sk-test'),
          httpClient: scripted(<String>[], <String>[says('[cold]这个目标挺好的，加油。')]),
        ),
      );
      final MainlineResult r = await agent.run(
        goalText: '半年减重 10 斤',
        ringCount: 8,
        tools: reg,
        draft: draft,
      );
      expect(r.hasRings, isFalse);
      expect(r.failure, contains('没调用 set_mainline'));
      expect(r.line, '这个目标挺好的，加油。');
    });

    test('没配 Key → 一个请求都不发，hasRings=false', () async {
      final List<String> bodies = <String>[];
      final MainlineDraft draft = MainlineDraft();
      final MainlineAgent agent = MainlineAgent(
        client: LlmClient(
          config: const LlmConfig(),
          httpClient: scripted(bodies, <String>[says('不该被调用')]),
        ),
      );
      final MainlineResult r = await agent.run(
        goalText: '半年减重 10 斤',
        ringCount: 8,
        tools: registryWith(draft),
        draft: draft,
      );
      expect(r.failure, '未配置 API Key');
      expect(bodies, isEmpty);
      expect(r.rounds, 0);
    });

    test('循环用尽仍有主线 → hasRings 为真（她交上来的东西不许丢）', () async {
      final MainlineDraft draft = MainlineDraft();
      final AgentToolRegistry reg = registryWith(draft);
      final MainlineAgent agent = MainlineAgent(
        maxRounds: 2,
        client: LlmClient(
          config: const LlmConfig(apiKey: 'sk-test'),
          httpClient: scripted(<String>[], <String>[
            toolCall('set_mainline', goodRings(8)),
            toolCall('get_status'), // 她一直调工具，不给终答
          ]),
        ),
      );
      final MainlineResult r = await agent.run(
        goalText: '半年减重 10 斤',
        ringCount: 8,
        tools: reg,
        draft: draft,
      );
      expect(r.failure, contains('用尽'));
      expect(r.hasRings, isTrue, reason: '主线已经交上来了，不能因为没终答就丢');
    });
  });
}
