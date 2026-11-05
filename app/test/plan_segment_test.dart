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

/// 滚动生成的窗口 + 窗口内分段并行拆（docs/50 C1 / C7）。
///
/// 钉四件事：窗口规则（≤ kPlanWindowSize 张 / 档位按全链位置取阶梯、全链不倒退 /
/// 只有最后一段收 S）；窗口切段（≤12 不切、14 切 2×7、首尾相接）；
/// 段校验（越区间、末段不收 S 都要抛）；整条编排拆出来的一段能过 [validatePlanWindow]。
void main() {
  int ri(String r) => Rarity.ranks.indexOf(r);

  group('planWindowFor（滚动生成：一次只拆一个窗口）', () {
    test('180 天：只拆 14 张；总数更少就按总数', () {
      final PlanWindow w = planWindowFor(total: 180);
      expect(w.from, 1);
      expect(w.size, kPlanWindowSize);
      expect(w.to, 14);
      expect(w.total, 180);
      expect(w.last, isFalse, reason: '兑现单在最后一段');
      expect(w.whole, isFalse);
      final PlanWindow short = planWindowFor(total: 10);
      expect(short.size, 10);
      expect(short.whole, isTrue);
      expect(short.last, isTrue);
      expect(short.lo, 'F');
      expect(short.hi, 'S');
    });

    test('一段段往下拆：序号连续、张数守恒、档位全链不倒退、只有最后一段收 S', () {
      for (final int total in <int>[14, 15, 30, 90, 180, 400]) {
        int planned = 0;
        String? prev;
        int windows = 0;
        while (planned < total) {
          final PlanWindow w = planWindowFor(total: total, planned: planned);
          windows++;
          expect(w.from, planned + 1);
          expect(w.size, lessThanOrEqualTo(kPlanWindowSize));
          expect(ri(w.lo), lessThanOrEqualTo(ri(w.hi)));
          if (prev != null) {
            expect(ri(w.lo), greaterThanOrEqualTo(ri(prev)), reason: '全链不倒退');
          }
          expect(w.last, w.to == total);
          expect(w.index, windows - 1);
          expect(w.count, (total / kPlanWindowSize).ceil());
          // 模拟模型把这一段顶到上限交上来
          prev = w.last ? 'S' : w.hi;
          planned = w.to;
        }
        expect(planned, total);
        expect(prev, 'S');
      }
    });

    test('首目标第一段：E~C，不摆兑现单（总数 ≤ 14 也一样）', () {
      for (final int total in <int>[3, 14, 180]) {
        final PlanWindow w = planWindowFor(total: total, firstGoal: true);
        expect(w.lo, 'E');
        expect(w.hi, 'C');
        expect(w.last, isFalse);
        expect(w.size, total < kPlanWindowSize ? total : kPlanWindowSize);
      }
    });
  });

  group('planSegmentsFor（窗口内分段并行）', () {
    test('窗口 ≤ 12 张：只有一段，区间 = 窗口区间', () {
      for (final PlanWindow w in <PlanWindow>[
        PlanWindow.whole(kPlanSegmentSize),
        planWindowFor(total: 3, firstGoal: true),
        planWindowFor(total: 180, planned: 174),
      ]) {
        final List<PlanSegment> segs = planSegmentsFor(w);
        expect(segs, hasLength(1));
        expect(segs.single.lo, w.lo);
        expect(segs.single.hi, w.hi);
        expect(segs.single.last, w.last);
      }
    });

    test('默认窗口 14 张 > 12：切成 2×7 并行（首尾相接）', () {
      final List<PlanSegment> segs = planSegmentsFor(planWindowFor(total: 180));
      expect(segs.map((PlanSegment s) => s.size).toList(), <int>[7, 7]);
      expect(segs[1].from, 8);
      expect(segs[1].lo, segs[0].hi);
    });

    test('整份长清单（老口径）：张数守恒、每段 ≤ 段长、序号连续、区间首尾相接、末段收 S', () {
      for (final int total in <int>[13, 40, 90, 180, 400]) {
        final List<PlanSegment> segs = planSegmentsFor(PlanWindow.whole(total));
        expect(segs.length, greaterThan(1), reason: '$total 张该分段');
        expect(segs.fold<int>(0, (int a, PlanSegment s) => a + s.size), total);
        int from = 1;
        for (int i = 0; i < segs.length; i++) {
          final PlanSegment s = segs[i];
          expect(s.size, lessThanOrEqualTo(kPlanSegmentSize));
          expect(s.from, from);
          from = s.to + 1;
          expect(ri(s.lo), lessThanOrEqualTo(ri(s.hi)));
          if (i > 0) expect(s.lo, segs[i - 1].hi, reason: '相邻段首尾相接');
          expect(s.last, i == segs.length - 1);
        }
        expect(segs.first.lo, 'F');
        expect(segs.last.hi, 'S');
      }
    });
  });

  group('validatePlanSegment / validatePlanWindow', () {
    final List<PlanSegment> whole90 = planSegmentsFor(PlanWindow.whole(90));
    final PlanSegment mid = whole90[2];
    final PlanSegment end = whole90.last;

    List<TaskSpec> tasksOf(
      int from,
      int size,
      String lo, {
      String? rank,
      String? lastRank,
    }) => <TaskSpec>[
      for (int i = 0; i < size; i++)
        TaskSpec(
          short: '第${from + i}',
          title: '第 ${from + i} 天做什么',
          proof: '截图',
          minutes: 10,
          rank: i == size - 1 && lastRank != null ? lastRank : (rank ?? lo),
        ),
    ];

    test('合规的一段不抛', () {
      expect(
        () => validatePlanSegment(mid, tasksOf(mid.from, mid.size, mid.lo)),
        returnsNormally,
      );
      expect(
        () => validatePlanSegment(
          end,
          tasksOf(end.from, end.size, end.lo, lastRank: 'S'),
        ),
        returnsNormally,
      );
    });

    test('档位越出本段区间要抛', () {
      expect(
        () => validatePlanSegment(
          mid,
          tasksOf(mid.from, mid.size, mid.lo, rank: 'S'),
        ),
        throwsA(isA<PlanRuleError>()),
      );
    });

    test('末段最后一张不是 S 要抛', () {
      expect(
        () => validatePlanSegment(end, tasksOf(end.from, end.size, end.lo)),
        throwsA(isA<PlanRuleError>()),
      );
    });

    test('窗口：张数不对 / 中间段提前收 S 都要抛', () {
      final PlanWindow w = planWindowFor(total: 180, planned: 14);
      expect(
        () => validatePlanWindow(w, tasksOf(w.from, w.size, w.lo)),
        returnsNormally,
      );
      expect(
        () => validatePlanWindow(w, tasksOf(w.from, w.size - 1, w.lo)),
        throwsA(isA<PlanRuleError>()),
      );
      expect(
        () =>
            validatePlanWindow(w, tasksOf(w.from, w.size, w.lo, lastRank: 'S')),
        throwsA(isA<PlanRuleError>()),
        reason: '中间段没有兑现单，S 越出区间',
      );
    });
  });

  /// 按请求体里「第 x~y 张」的**最后一处**（段 > 窗口）回一段合规任务
  http.Client mockSegments(List<PlanSegment> segs, void Function() onReq) {
    final RegExp range = RegExp(r'第 (\d+)~(\d+) 张');
    return MockClient((http.Request req) async {
      onReq();
      final String body = req.body;
      final List<RegExpMatch> ms = range.allMatches(body).toList();
      // 段的范围写在窗口之后；不分段时只有窗口那一处
      final int from = segs.length == 1
          ? segs.single.from
          : ms
                .map((RegExpMatch m) => int.parse(m.group(1)!))
                .lastWhere((int f) => segs.any((PlanSegment s) => s.from == f));
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
  }

  test('generateTasks：老口径 90 张分段并行拆，拼回后过整份校验', () async {
    final List<PlanSegment> segs = planSegmentsFor(PlanWindow.whole(90));
    int requests = 0;
    final PlanAgent agent = PlanAgent(
      client: LlmClient(
        config: const LlmConfig(apiKey: 'sk-test'),
        httpClient: mockSegments(segs, () => requests++),
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
    expect(
      () => validatePlanWindow(PlanWindow.whole(90), tasks),
      returnsNormally,
    );
    expect(progress.first, (0, segs.length));
    expect(progress.last, (segs.length, segs.length));
  });

  test('generateTasks：180 天目标只拆第一个窗口（14 张 = 2×7 并行）', () async {
    final PlanWindow w = planWindowFor(total: 180);
    final List<PlanSegment> segs = planSegmentsFor(w);
    int requests = 0;
    final PlanAgent agent = PlanAgent(
      client: LlmClient(
        config: const LlmConfig(apiKey: 'sk-test'),
        httpClient: mockSegments(segs, () => requests++),
      ),
    );
    final List<TaskSpec> tasks = await agent.generateTasks(
      brief: PlanBrief(
        goalText: '半年减重 10 斤',
        days: 180,
        taskCount: w.size,
        cat: goalCats['gen']!,
        window: w,
      ),
    );
    expect(requests, 2);
    expect(tasks, hasLength(kPlanWindowSize));
    expect(tasks.last.short, '第14天');
    expect(() => validatePlanWindow(w, tasks), returnsNormally);
    expect(() => validatePlan(days: 180, tasks: tasks), returnsNormally);
  });
}
