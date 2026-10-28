import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:system_panel/agent/llm_client.dart';
import 'package:system_panel/agent/plan_agent.dart';
import 'package:system_panel/agent/plan_brief.dart';
import 'package:system_panel/data/rarity.dart';
import 'package:system_panel/state/goal_gen.dart';
import 'package:system_panel/state/plan_failure.dart';

/// docs/49 F3：长清单分段并行拆。
///
/// 钉三件事：切段规则（张数守恒 / 段长上限 / 档位区间首尾相接）；
/// 段校验（越区间、末段不收 S 都要抛）；整条编排拆出来的 90 张能过全量 [validatePlan]。
void main() {
  group('planSegmentsFor', () {
    test('不超过一段 / 首目标：只有一段，区间 F~S', () {
      for (final List<PlanSegment> segs in <List<PlanSegment>>[
        planSegmentsFor(kPlanSegmentSize),
        planSegmentsFor(3, firstGoal: true),
      ]) {
        expect(segs, hasLength(1));
        expect(segs.single.lo, 'F');
        expect(segs.single.hi, 'S');
        expect(segs.single.last, isTrue);
      }
    });

    test('90 张：张数守恒、每段 ≤ 段长、序号连续、档位区间首尾相接、末段收 S', () {
      for (final int total in <int>[13, 40, 90, 180, 400]) {
        final List<PlanSegment> segs = planSegmentsFor(total);
        expect(segs.length, greaterThan(1), reason: '$total 张该分段');
        expect(segs.fold<int>(0, (int a, PlanSegment s) => a + s.size), total);
        int from = 1;
        for (int i = 0; i < segs.length; i++) {
          final PlanSegment s = segs[i];
          expect(s.size, lessThanOrEqualTo(kPlanSegmentSize));
          expect(s.from, from);
          from = s.to + 1;
          expect(
            Rarity.ranks.indexOf(s.lo),
            lessThanOrEqualTo(Rarity.ranks.indexOf(s.hi)),
          );
          if (i > 0) expect(s.lo, segs[i - 1].hi, reason: '相邻段首尾相接');
        }
        expect(segs.first.lo, 'E');
        expect(segs.last.hi, 'S');
        expect(segs.last.last, isTrue);
      }
    });
  });

  group('validatePlanSegment', () {
    final PlanSegment mid = planSegmentsFor(90)[2];
    final PlanSegment end = planSegmentsFor(90).last;

    List<TaskSpec> tasksOf(
      PlanSegment s, {
      String? rank,
      String? lastRank,
    }) => <TaskSpec>[
      for (int i = 0; i < s.size; i++)
        TaskSpec(
          short: '第${s.from + i}',
          title: '第 ${s.from + i} 天做什么',
          proof: '截图',
          minutes: 10,
          rank: i == s.size - 1 && lastRank != null ? lastRank : (rank ?? s.lo),
        ),
    ];

    test('合规的一段不抛', () {
      expect(() => validatePlanSegment(mid, tasksOf(mid)), returnsNormally);
      expect(
        () => validatePlanSegment(end, tasksOf(end, lastRank: 'S')),
        returnsNormally,
      );
    });

    test('档位越出本段区间要抛', () {
      expect(
        () => validatePlanSegment(mid, tasksOf(mid, rank: 'S')),
        throwsA(isA<PlanRuleError>()),
      );
    });

    test('末段最后一张不是 S 要抛', () {
      expect(
        () => validatePlanSegment(end, tasksOf(end)),
        throwsA(isA<PlanRuleError>()),
      );
    });
  });

  test('generateTasks：90 张分段并行拆，拼回后过全量 validatePlan', () async {
    final List<PlanSegment> segs = planSegmentsFor(90);
    final RegExp range = RegExp(r'第 (\d+)~(\d+) 张');
    int requests = 0;
    final http.Client mock = MockClient((http.Request req) async {
      requests++;
      final RegExpMatch m = range.firstMatch(req.body)!;
      final int from = int.parse(m.group(1)!);
      final PlanSegment s = segs.firstWhere((PlanSegment x) => x.from == from);
      final Map<String, dynamic> args = <String, dynamic>{
        'tasks': <Map<String, dynamic>>[
          for (int i = 0; i < s.size; i++)
            <String, dynamic>{
              'short': '第${s.from + i}天',
              'title': '第 ${s.from + i} 天：慢跑',
              'proof': '跑步截图',
              'minutes': 20,
              'rank': s.last && i == s.size - 1 ? 'S' : s.lo,
            },
        ],
      };
      return http.Response(
        '{"choices":[{"message":{"content":"","tool_calls":[{"id":"c1",'
        '"type":"function","function":{"name":"set_plan","arguments":'
        '${jsonEncode(jsonEncode(args))}}}]}}]}',
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final PlanAgent agent = PlanAgent(
      client: LlmClient(
        config: const LlmConfig(apiKey: 'sk-test'),
        httpClient: mock,
      ),
    );
    final List<(int, int)> progress = <(int, int)>[];
    final List<TaskSpec> tasks = await agent.generateTasks(
      brief: PlanBrief(
        goalText: '三个月跑完半马',
        days: 90,
        taskCount: 90,
        cat: goalCats['gen']!,
      ),
      onProgress: (int d, int t) => progress.add((d, t)),
    );
    expect(requests, segs.length, reason: '一段一次请求，没有多余的查询轮');
    expect(tasks, hasLength(90));
    expect(tasks.first.short, '第1天');
    expect(tasks.last.short, '第90天');
    expect(() => validatePlan(days: 90, tasks: tasks), returnsNormally);
    expect(progress.first, (0, segs.length));
    expect(progress.last, (segs.length, segs.length));
  });
}
