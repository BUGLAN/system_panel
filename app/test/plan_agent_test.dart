import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:system_panel/agent/goal_match_agent.dart';
import 'package:system_panel/agent/llm_client.dart';
import 'package:system_panel/agent/mainline_tool.dart';
import 'package:system_panel/agent/memory.dart';
import 'package:system_panel/agent/plan_agent.dart';
import 'package:system_panel/agent/plan_brief.dart';
import 'package:system_panel/agent/tools.dart';
import 'package:system_panel/state/goal_gen.dart';
import 'package:system_panel/state/plan_failure.dart';
import 'package:system_panel/state/quest.dart';

/// 目标拆解 = Agent 调 tool（2026-10-23 宿主定调）。
///
/// 这一组测试钉三件事：
///  ① **匹配与拆解都走 Agent**：类别由 set_goal_category 交、内容由 set_plan 交；
///  ② **任务卡片 schema 稳定**：字段/类型/枚举/必填项固定，下游直接消费；
///  ③ **fail fast**：任何失败都抛 PlanFailure，不吞、不降级、不返回默认值。
void main() {
  /// 合法任务池（形状对就行，内容不重要）
  Map<String, dynamic> goodPlan([int n = 8]) => <String, dynamic>{
    'tasks': <Map<String, dynamic>>[
      for (int i = 0; i < n; i++)
        <String, dynamic>{
          'short': '任务${i + 1}',
          'title': '第 ${i + 1} 步做什么',
          'proof': '证据${i + 1}',
          'minutes': 10 + i,
          'rank': 'E',
        },
    ],
  };

  Map<String, dynamic> goodMatch({int quota = 10}) => <String, dynamic>{
    'id': 'run',
    'short': '骑自行车',
    'days': 14,
    'quota': quota,
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

  LlmClient clientOf(http.Client http, {String key = 'sk-test'}) => LlmClient(
    config: LlmConfig(apiKey: key),
    httpClient: http,
  );

  /// 严格注册表 + set_plan（生产装配就是这个形状）
  AgentToolRegistry planTools(PlanDraft draft, {int taskCount = 8}) {
    final AgentToolRegistry reg = StrictAgentToolRegistry();
    reg.registerAll(
      defaultAgentTools(
        context: MockAgentContext(queue: <Quest>[]),
        memory: MemoryStore(),
      ).all,
    );
    reg.register(
      setPlanTool(
        goalText: '两周内骑自行车10次',
        taskCount: taskCount,
        days: 14,
        draft: draft,
      ),
    );
    return reg;
  }

  PlanBrief brief({int taskCount = 8, int days = 14}) => PlanBrief(
    goalText: '两周内骑自行车10次',
    days: days,
    taskCount: taskCount,
    cat: goalCats['gen']!,
  );

  // ═══════════════════════════════════════════════════════
  group('set_plan 的 schema（任务卡片结构的唯一真源）', () {
    test('字段名 / 类型 / 枚举 / 必填项全部钉死', () {
      final Map<String, dynamic> schema = setPlanSchema(14);
      final Map<String, dynamic> tasks =
          (schema['properties'] as Map<String, dynamic>)['tasks']
              as Map<String, dynamic>;
      expect(tasks['type'], 'array');
      expect(tasks['minItems'], 14);
      expect(tasks['maxItems'], 14);
      final Map<String, dynamic> item = tasks['items'] as Map<String, dynamic>;
      final Map<String, dynamic> props =
          item['properties'] as Map<String, dynamic>;
      expect(props.keys.toList(), <String>[
        'short',
        'title',
        'proof',
        'minutes',
        'rank',
      ]);
      expect((props['short'] as Map<String, dynamic>)['type'], 'string');
      expect((props['title'] as Map<String, dynamic>)['type'], 'string');
      expect((props['proof'] as Map<String, dynamic>)['type'], 'string');
      expect((props['minutes'] as Map<String, dynamic>)['type'], 'integer');
      expect((props['rank'] as Map<String, dynamic>)['type'], 'string');
      expect(
        (props['rank'] as Map<String, dynamic>)['enum'],
        <String>['F', 'E', 'D', 'C', 'B', 'A', 'S'],
      );
      expect(item['required'], <String>[
        'short',
        'title',
        'proof',
        'minutes',
        'rank',
      ]);
      expect(schema['required'], <String>['tasks']);
    });

    test('描述里带上了期限与条数（旧版漏了它们，模型只能瞎编）', () {
      final Map<String, dynamic> schema = setPlanSchema(14);
      final String desc =
          ((schema['properties'] as Map<String, dynamic>)['tasks']
                  as Map<String, dynamic>)['description']
              as String;
      expect(desc, contains('正好 14 张'));
      expect(desc, contains('兑现单'));
    });

    test('工具 description 写明目标与期限', () {
      final AgentTool t = setPlanTool(
        goalText: '两周内骑自行车10次',
        taskCount: 14,
        days: 14,
        draft: PlanDraft(),
      );
      expect(t.name, 'set_plan');
      expect(t.description, contains('两周内骑自行车10次'));
      expect(t.description, contains('14 天'));
    });
  });

  // ═══════════════════════════════════════════════════════
  group('set_plan 形状校验 **fail fast**（不回填让她重来）', () {
    test('合法 8 张 → ok，草案写入，回执给首尾张', () async {
      final PlanDraft draft = PlanDraft();
      final ToolOutcome oc = await planTools(draft).execute(
        'set_plan',
        goodPlan(),
      );
      expect(oc.ok, isTrue);
      expect(draft.tasks, hasLength(8));
      expect(draft.tasks!.first.short, '任务1');
      expect(oc.message, contains('8 张'));
    });

    test('条数不对 → 抛 PlanShapeError（不截断、不补齐）', () async {
      for (final int n in <int>[6, 7, 9]) {
        final PlanDraft draft = PlanDraft();
        await expectLater(
          planTools(draft).execute('set_plan', goodPlan(n)),
          throwsA(
            isA<PlanShapeError>().having(
              (PlanShapeError e) => e.detail,
              'detail',
              allOf(contains('正好 8 张'), contains('$n 张')),
            ),
          ),
        );
        expect(draft.tasks, isNull, reason: '不合格的一律不落草案');
      }
    });

    test('tasks 缺失 / 不是数组 / 空数组 → 抛', () async {
      for (final Object? raw in <Object?>[
        null,
        'notalist',
        <dynamic>[],
        <String, dynamic>{},
      ]) {
        final PlanDraft draft = PlanDraft();
        await expectLater(
          planTools(draft).execute('set_plan', <String, dynamic>{
            'tasks': raw,
          }),
          throwsA(isA<PlanShapeError>()),
          reason: 'tasks=$raw',
        );
        expect(draft.tasks, isNull);
      }
    });

    test('字段空 / 档位非法 / 分钟数非正 → 抛，并指明是第几张哪个字段', () async {
      final List<Map<String, dynamic>> bad = <Map<String, dynamic>>[
        <String, dynamic>{
          'short': '',
          'title': 't',
          'proof': 'p',
          'minutes': 10,
          'rank': 'E',
        },
        <String, dynamic>{
          'short': 's',
          'title': '  ',
          'proof': 'p',
          'minutes': 10,
          'rank': 'E',
        },
        <String, dynamic>{
          'short': 's',
          'title': 't',
          'proof': 'p',
          'minutes': 10,
          'rank': 'Z',
        },
        <String, dynamic>{
          'short': 's',
          'title': 't',
          'proof': 'p',
          'minutes': 0,
          'rank': 'E',
        },
        <String, dynamic>{
          'short': 's',
          'title': 't',
          'proof': 'p',
          'rank': 'E',
        },
      ];
      for (final Map<String, dynamic> one in bad) {
        final PlanDraft draft = PlanDraft();
        await expectLater(
          planTools(draft, taskCount: 1).execute('set_plan', <String, dynamic>{
            'tasks': <Map<String, dynamic>>[one],
          }),
          throwsA(
            isA<PlanShapeError>().having(
              (PlanShapeError e) => e.where,
              'where',
              contains('第 1 张'),
            ),
          ),
          reason: '$one',
        );
        expect(draft.tasks, isNull);
      }
    });
  });

  // ═══════════════════════════════════════════════════════
  group('set_goal_category（匹配也走 Agent）', () {
    test('合法三件套 → 草案写入；类别 id 必须在十类里', () async {
      final GoalMatchDraft draft = GoalMatchDraft();
      final AgentToolRegistry reg = StrictAgentToolRegistry();
      reg.register(setGoalCategoryTool(goalText: '两周内骑自行车10次', draft: draft));
      final ToolOutcome oc = await reg.execute(
        'set_goal_category',
        goodMatch(),
      );
      expect(oc.ok, isTrue);
      expect(draft.match, isNotNull);
      expect(draft.match!.cat.id, 'run');
      expect(draft.match!.short, '骑自行车');
      expect(draft.match!.days, 14);
    });

    test('类别 id 不在表里 / 短字空 / 期限非法 → 抛 PlanShapeError', () async {
      final List<Map<String, dynamic>> bad = <Map<String, dynamic>>[
        <String, dynamic>{'id': '骑行', 'short': '骑车', 'days': 14, 'quota': 10},
        <String, dynamic>{'id': 'run', 'short': '  ', 'days': 14, 'quota': 10},
        <String, dynamic>{'id': 'run', 'short': '骑车', 'days': 0, 'quota': 10},
        <String, dynamic>{'id': 'run', 'short': '骑车', 'days': 99999, 'quota': 10},
        <String, dynamic>{'id': 'run', 'short': '骑车', 'quota': 10},
      ];
      for (final Map<String, dynamic> one in bad) {
        final GoalMatchDraft draft = GoalMatchDraft();
        final AgentToolRegistry reg = StrictAgentToolRegistry();
        reg.register(setGoalCategoryTool(goalText: 'x', draft: draft));
        await expectLater(
          reg.execute('set_goal_category', one),
          throwsA(isA<PlanShapeError>()),
          reason: '$one',
        );
        expect(draft.match, isNull);
      }
    });

    test('schema 的 id 枚举 = 十类 id', () {
      final Map<String, dynamic> schema = setGoalCategorySchema();
      final Map<String, dynamic> props =
          schema['properties'] as Map<String, dynamic>;
      expect((props['id'] as Map<String, dynamic>)['enum'], goalCategoryIds);
      expect(schema['required'], <String>['id', 'short', 'days', 'quota']);
    });
  });

  // ═══════════════════════════════════════════════════════
  group('严格注册表：工具失败一律抛（不折成回执）', () {
    test('未知工具 → ToolExecutionError', () async {
      final AgentToolRegistry reg = StrictAgentToolRegistry();
      await expectLater(
        reg.execute('不存在的工具'),
        throwsA(isA<ToolExecutionError>()),
      );
    });

    test('工具内部抛异常 → 包成 ToolExecutionError（带原因）', () async {
      final AgentToolRegistry reg = StrictAgentToolRegistry();
      reg.register(
        AgentTool(
          name: 'boom',
          description: '内部抛异常的工具',
          parameters: const <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{},
          },
          run: (Map<String, dynamic> args) async => throw StateError('炸了'),
        ),
      );
      await expectLater(
        reg.execute('boom'),
        throwsA(
          isA<ToolExecutionError>()
              .having((ToolExecutionError e) => e.tool, 'tool', 'boom')
              .having((ToolExecutionError e) => '${e.cause}', 'cause', contains('炸了')),
        ),
      );
    });

    test('工具返回 ok=false → 抛（不把失败当回执回填给模型）', () async {
      final AgentToolRegistry reg = StrictAgentToolRegistry();
      reg.register(
        AgentTool(
          name: 'refuse',
          description: '返回 fail 的工具',
          parameters: const <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{},
          },
          run: (Map<String, dynamic> args) async =>
              ToolOutcome.fail('条件不满足'),
        ),
      );
      await expectLater(
        reg.execute('refuse'),
        throwsA(
          isA<ToolExecutionError>().having(
            (ToolExecutionError e) => e.detail,
            'detail',
            '条件不满足',
          ),
        ),
      );
    });
  });

  // ═══════════════════════════════════════════════════════
  group('装配守卫：Agent 必须配严格注册表', () {
    test('PlanAgent 收到宽容版注册表 → 当场抛 StateError（否则失败会被折成回执）', () async {
      final PlanDraft draft = PlanDraft();
      final AgentToolRegistry loose = AgentToolRegistry();
      loose.register(
        setPlanTool(
          goalText: '两周内骑自行车10次',
          taskCount: 8,
          days: 14,
          draft: draft,
        ),
      );
      final PlanAgent agent = PlanAgent(
        client: clientOf(scripted(<String>[], <String>[says('不该被调用')])),
      );
      await expectLater(
        agent.generate(brief: brief(), tools: loose, draft: draft),
        throwsA(isA<StateError>()),
      );
    });

    test('GoalMatchAgent 收到宽容版注册表 → 同样抛', () async {
      final GoalMatchDraft draft = GoalMatchDraft();
      final AgentToolRegistry loose = AgentToolRegistry();
      loose.register(setGoalCategoryTool(goalText: 'x', draft: draft));
      final GoalMatchAgent agent = GoalMatchAgent(
        client: clientOf(scripted(<String>[], <String>[says('不该被调用')])),
      );
      await expectLater(
        agent.match(goalText: 'x', tools: loose, draft: draft),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════
  group('PlanAgent · 真正的 agent 循环', () {
    test('get_status → set_plan → 她解释（两轮收敛）', () async {
      final List<String> bodies = <String>[];
      final PlanDraft draft = PlanDraft();
      final PlanAgent agent = PlanAgent(
        client: clientOf(
          scripted(bodies, <String>[
            '{"choices":[{"message":{"content":"","tool_calls":['
                '{"id":"c1","type":"function","function":{"name":"get_status","arguments":"{}"}},'
                '{"id":"c2","type":"function","function":{"name":"set_plan","arguments":'
                '${jsonEncode(jsonEncode(goodPlan()))}}}]}}]}',
            says('[smug]两周十次骑行，第一张我给你压到 20 分钟。'),
          ]),
        ),
      );
      final PlanResult r = await agent.generate(
        brief: brief(),
        tools: planTools(draft),
        draft: draft,
      );
      expect(r.rounds, 2);
      expect(r.tasks, hasLength(8));
      expect(r.line, '两周十次骑行，第一张我给你压到 20 分钟。');
      expect(r.emotion, 'smug');
      expect(r.receipts, hasLength(2));
      expect(bodies.first, contains('"set_plan"'));
      expect(bodies.first, contains('"parameters"'));
      expect(bodies.first, contains('"max_tokens":$kPlanMaxTokens'));
      expect(bodies.first, contains('"reasoning_effort":"low"'));
      // 期限与条数必须真的进了 prompt（旧版漏了它们）
      expect(bodies.first, contains('14 天'));
      expect(bodies.first, contains('8 张'));
    });

    test('交错了条数 → 回填原因**重交一次**；改对了就收下', () async {
      final List<String> bodies = <String>[];
      final PlanDraft draft = PlanDraft();
      final PlanAgent agent = PlanAgent(
        client: clientOf(
          scripted(bodies, <String>[
            toolCall('set_plan', goodPlan(6)), // 少 2 张
            toolCall('set_plan', goodPlan(8)), // 看见原因后改对
          ]),
        ),
      );
      final PlanResult r = await agent.generate(
        brief: brief(),
        tools: planTools(draft),
        draft: draft,
      );
      expect(r.tasks, hasLength(8));
      expect(bodies, hasLength(2));
      // 第 2 次请求里必须带着「正好 8 张」这条原因，模型才知道差在哪
      expect(bodies[1], contains('正好 8 张'));
    });

    test('⚠️ 条数一直不对 → 轮数用尽照样抛（不无限重试、不截断补齐）', () async {
      final List<String> bodies = <String>[];
      final PlanDraft draft = PlanDraft();
      final PlanAgent agent = PlanAgent(
        maxRounds: 2,
        client: clientOf(
          scripted(bodies, <String>[
            toolCall('set_plan', goodPlan(6)),
            toolCall('set_plan', goodPlan(7)), // 还是不对
          ]),
        ),
      );
      await expectLater(
        agent.generate(brief: brief(), tools: planTools(draft), draft: draft),
        throwsA(isA<PlanShapeError>()),
      );
      expect(draft.tasks, isNull);
    });

    test('她聊完却没调用 set_plan → 抛 noPlan（不返回默认值）', () async {
      final PlanDraft draft = PlanDraft();
      final PlanAgent agent = PlanAgent(
        client: clientOf(
          scripted(<String>[], <String>[says('[cold]这个目标挺好的，加油。')]),
        ),
      );
      await expectLater(
        agent.generate(brief: brief(), tools: planTools(draft), draft: draft),
        throwsA(
          isA<PlanGenerationError>().having(
            (PlanGenerationError e) => e.code,
            'code',
            PlanFailureCode.noPlan,
          ),
        ),
      );
    });

    test('没配 Key → 一个请求都不发，抛 noKey', () async {
      final List<String> bodies = <String>[];
      final PlanDraft draft = PlanDraft();
      final PlanAgent agent = PlanAgent(
        client: clientOf(scripted(bodies, <String>[says('不该被调用')]), key: ''),
      );
      await expectLater(
        agent.generate(brief: brief(), tools: planTools(draft), draft: draft),
        throwsA(
          isA<PlanGenerationError>().having(
            (PlanGenerationError e) => e.code,
            'code',
            PlanFailureCode.noKey,
          ),
        ),
      );
      expect(bodies, isEmpty);
    });

    test('HTTP 500 → 抛 httpError（不静默退回模板）', () async {
      final PlanDraft draft = PlanDraft();
      final PlanAgent agent = PlanAgent(
        client: LlmClient(
          config: const LlmConfig(apiKey: 'sk-test'),
          httpClient: MockClient(
            (http.Request req) async => http.Response('boom', 500),
          ),
        ),
      );
      await expectLater(
        agent.generate(brief: brief(), tools: planTools(draft), draft: draft),
        throwsA(
          isA<PlanGenerationError>().having(
            (PlanGenerationError e) => e.code,
            'code',
            PlanFailureCode.httpError,
          ),
        ),
      );
    });

    test('循环用尽仍没交 → 抛 noPlan，带上回执（可诊断）', () async {
      final PlanDraft draft = PlanDraft();
      final PlanAgent agent = PlanAgent(
        maxRounds: 2,
        client: clientOf(
          scripted(<String>[], <String>[
            toolCall('get_status'),
            toolCall('get_status'),
          ]),
        ),
      );
      await expectLater(
        agent.generate(brief: brief(), tools: planTools(draft), draft: draft),
        throwsA(
          isA<PlanGenerationError>()
              .having(
                (PlanGenerationError e) => e.code,
                'code',
                PlanFailureCode.noPlan,
              )
              .having(
                (PlanGenerationError e) => e.detail,
                'detail',
                contains('get_status'),
              ),
        ),
      );
    });
  });

  // ═══════════════════════════════════════════════════════
  group('GoalMatchAgent · 匹配也走 agent 循环', () {
    test('一轮交出匹配结果', () async {
      final GoalMatchDraft draft = GoalMatchDraft();
      final AgentToolRegistry reg = StrictAgentToolRegistry();
      reg.register(setGoalCategoryTool(goalText: '两周内骑自行车10次', draft: draft));
      final GoalMatchAgent agent = GoalMatchAgent(
        client: clientOf(
          scripted(<String>[], <String>[toolCall('set_goal_category', goodMatch())]),
        ),
      );
      final GoalMatch m = await agent.match(
        goalText: '两周内骑自行车10次',
        tools: reg,
        draft: draft,
      );
      expect(m.cat.id, 'run');
      expect(m.short, '骑自行车');
      expect(m.days, 14);
    });

    test('她只说话不调工具 → 抛 noPlan', () async {
      final GoalMatchDraft draft = GoalMatchDraft();
      final AgentToolRegistry reg = StrictAgentToolRegistry();
      reg.register(setGoalCategoryTool(goalText: 'x', draft: draft));
      final GoalMatchAgent agent = GoalMatchAgent(
        client: clientOf(scripted(<String>[], <String>[says('[cold]挺好的。')])),
      );
      await expectLater(
        agent.match(goalText: 'x', tools: reg, draft: draft),
        throwsA(isA<PlanGenerationError>()),
      );
    });

    test('没配 Key → 抛 noKey，零请求', () async {
      final GoalMatchDraft draft = GoalMatchDraft();
      final AgentToolRegistry reg = StrictAgentToolRegistry();
      reg.register(setGoalCategoryTool(goalText: 'x', draft: draft));
      final List<String> bodies = <String>[];
      final GoalMatchAgent agent = GoalMatchAgent(
        client: clientOf(scripted(bodies, <String>[says('不该被调用')]), key: ''),
      );
      await expectLater(
        agent.match(goalText: 'x', tools: reg, draft: draft),
        throwsA(isA<PlanGenerationError>()),
      );
      expect(bodies, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════
  group('PlanBrief（喂给 Agent 的上下文）', () {
    test('期限、条数、类别、访谈答案都进了正文', () {
      final PlanBrief b = PlanBrief(
        goalText: '两周内骑自行车10次',
        days: 14,
        taskCount: 14,
        cat: goalCats['sleep']!,
        interview: const <String, String>{
          'sleep.schedule': '1-2 点睡 9 点后起',
        },
      );
      expect(b.userText, contains('两周内骑自行车10次'));
      expect(b.userText, contains('期限 14 天'));
      expect(b.userText, contains('14 张'));
      expect(b.userText, contains('早起'));
      // 卡 id 被还原成问题原文（模型才读得懂）
      expect(b.userText, contains('现在几点起、几点睡？'));
      expect(b.userText, contains('1-2 点睡 9 点后起'));
      expect(b.scenario, contains('14 张'));
    });

    test('首目标额外写明 3 张 E/D/C', () {
      final PlanBrief b = PlanBrief(
        goalText: '一个月早睡早起',
        days: kFirstGoalDays,
        taskCount: kFirstGoalDays,
        cat: goalCats['sleep']!,
        firstGoal: true,
      );
      expect(b.userText, contains('首目标'));
      expect(b.userText, contains('E/D/C'));
    });
  });
}

/// 档位全表（顺序同 Rarity.ranks；测试里少写一个 import 前缀）
