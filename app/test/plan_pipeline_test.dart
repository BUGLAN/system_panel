import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:system_panel/agent/goal_match_agent.dart';
import 'package:system_panel/agent/llm_client.dart';
import 'package:system_panel/agent/mainline_tool.dart';
import 'package:system_panel/agent/plan_agent.dart';
import 'package:system_panel/agent/plan_brief.dart';
import 'package:system_panel/agent/tools.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/goal_gen.dart';
import 'package:system_panel/state/plan_failure.dart';

/// 端到端：建目标 → Agent 匹配 → Agent 拆解 → 规则校验 → 落 PlanTask
///
/// 这一组是本次事故（「两周内骑自行车 10 次」被铸成「把目标写在纸上」）的
/// **回归钉**：它同时证明 ① 匹配与拆解都走 LLM+tool、② 任务卡片结构固定、
/// ③ 任何不合规都抛而不是降级。
void main() {
  test('E2E: 两周内骑自行车10次 走 Agent，不降级', () async {
    const String goal = '两周内骑自行车10次';
    final List<String> bodies = <String>[];
    final http.Client httpClient = MockClient((http.Request req) async {
      bodies.add(req.body);
      if (req.body.contains('set_goal_category')) {
        return http.Response(
          _wrap(
            'set_goal_category',
            '{"id":"run","short":"骑自行车","days":14,"quota":10}',
          ),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }
      // 目标写「10 次」→ 清单就是 10 张（不是期限的 14 张）
      final List<String> tasks = <String>[
        for (int i = 0; i < 10; i++)
          '{"short":"骑${i + 1}","title":"第 ${i + 1} 次骑行，骑 20 分钟",'
              '"proof":"骑行 App 截图","minutes":${i == 9 ? 120 : 20},'
              '"rank":"${i == 9 ? 'S' : 'E'}"}',
      ];
      return http.Response(
        _wrap('set_plan', '{"tasks":[${tasks.join(',')}]}'),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final LlmClient client = LlmClient(
      config: const LlmConfig(apiKey: 'sk-test'),
      httpClient: httpClient,
    );

    // ① 匹配（LLM + tool）
    final GoalMatchDraft md = GoalMatchDraft();
    final StrictAgentToolRegistry mt = StrictAgentToolRegistry();
    mt.register(setGoalCategoryTool(goalText: goal, draft: md));
    final GoalMatch m = await GoalMatchAgent(client: client)
        .match(goalText: goal, tools: mt, draft: md);
    expect(m.cat.id, 'run');
    expect(m.short, '骑自行车');
    expect(m.days, 14);
    expect(m.quota, 10, reason: '「10 次」必须被读成次数配额');

    // ② 拆解：条数 = **次数配额**（不是期限天数）
    final int need = planTaskCountFor(m.days, quota: m.quota);
    expect(need, 10, reason: '两周 10 次 → 10 张，不是 14 张');
    final PlanDraft pd = PlanDraft();
    final StrictAgentToolRegistry pt = StrictAgentToolRegistry();
    pt.register(
      // 这条用例的模型脚本按「10 张」写；规则校验（档位阶梯/兑现单）
      // 在 E2E 的第 ③ 步 buildGoalFromPlan 里照常跑，这里只验条数与形状。
      setPlanTool(
        goalText: goal,
        taskCount: need,
        days: m.days,
        draft: pd,
        validate: false,
      ),
    );
    final PlanResult pr = await PlanAgent(client: client).generate(
      brief: PlanBrief(
        goalText: goal,
        days: m.days,
        taskCount: need,
        cat: m.cat,
      ),
      tools: pt,
      draft: pd,
    );
    expect(pr.tasks, hasLength(10));

    // ③ 规则校验 + 铸计划
    final Goal g = buildGoalFromPlan(
      text: goal,
      short: m.short,
      cat: m.cat,
      days: m.days,
      quota: m.quota,
      tasks: pr.tasks,
      at: DateTime(2026, 10, 23),
    );
    // ignore: avoid_print
    print(
      'PLAN len=${g.plan.length} days=${g.days} short=${g.short} cat=${g.cat}',
    );
    for (final PlanTask t in g.plan.take(3)) {
      // ignore: avoid_print
      print(
        '  [${t.rank}] ${t.minutes}min  ${t.short} | ${t.title} | ${t.proof}',
      );
    }
    expect(g.plan.length, 10);
    expect(g.plan.first.title, contains('骑行'));
    expect(g.plan.last.finalTask, isTrue);
    expect(g.plan.last.rank, 'S');
  });

  test('E2E: 目标 10 次，模型交 14 张（按天数算的旧口径）→ 直接抛，不截断', () async {
    const String goal = '两周内骑自行车10次';
    final http.Client httpClient = MockClient((http.Request req) async {
      final List<String> tasks = <String>[
        // 模型按「期限 14 天」交 14 张 —— 正是真机事故里多出来的那 4 张
        for (int i = 0; i < 14; i++)
          '{"short":"骑${i + 1}","title":"第 ${i + 1} 次骑行",'
              '"proof":"截图","minutes":20,"rank":"E"}',
      ];
      return http.Response(
        _wrap('set_plan', '{"tasks":[${tasks.join(',')}]}'),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final PlanDraft pd = PlanDraft();
    final StrictAgentToolRegistry pt = StrictAgentToolRegistry();
    // 条数按次数配额要 10 张，模型却交了 14 张 → 形状层直接抛
    pt.register(
      setPlanTool(
        goalText: goal,
        taskCount: 10,
        days: 14,
        draft: pd,
        validate: false,
      ),
    );
    final PlanAgent agent = PlanAgent(
      client: LlmClient(
        config: const LlmConfig(apiKey: 'sk-test'),
        httpClient: httpClient,
      ),
    );
    await expectLater(
      agent.generate(
        brief: PlanBrief(
          goalText: goal,
          days: 14,
          taskCount: 10,
          cat: goalCats['run']!,
        ),
        tools: pt,
        draft: pd,
      ),
      throwsA(isA<PlanShapeError>()),
    );
  });
}

/// 把工具参数包成 OpenAI 兼容的 tool_calls 响应
String _wrap(String name, String args) {
  final String escaped = args.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  return '{"choices":[{"message":{"content":"","tool_calls":[{"id":"c1",'
      '"type":"function","function":{"name":"$name","arguments":"$escaped"}}]}}]}';
}
