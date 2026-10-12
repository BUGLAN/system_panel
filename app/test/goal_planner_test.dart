import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/agent/copy.dart';
import 'package:system_panel/agent/goal_planner.dart';
import 'package:system_panel/data/rarity.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/goal_gen.dart';

/// 目标拆解（docs/06）—— 2026-10-12 接入 LLM 后的回归网。
///
/// 关键纪律：
///  · 内容听模型，**难度阶梯不交给模型**（档位/时限上限/末环「兑现」由规则收口）
///  · 任何失败都返回 null → 调用方逐字回退类别模板（她不会铸不出主线）
void main() {
  /// 只回一句话的假网关（与 copy/chat 链路同一个最小面）
  _FakeGateway fake(String? reply, {bool configured = true}) =>
      _FakeGateway(reply, configured: configured);

  String ringsJson(int n) => jsonEncode(<String, dynamic>{
    'rings': <Map<String, dynamic>>[
      for (int i = 0; i < n; i++)
        <String, dynamic>{
          'short': '环${i + 1}',
          'title': '第 ${i + 1} 步：做一件具体的事',
          'proof': '截图${i + 1}',
          'minutes': 10 + i * 5,
          'rank': kNextGoalRankSeq[i.clamp(0, kNextGoalRankSeq.length - 1)],
        },
    ],
  });

  final GoalCategory cat = goalCats['gen']!;

  group('GoalPlanner.plan · 成功路径', () {
    test('正常 JSON → 拿到 N 环，内容逐字来自模型', () async {
      final GoalPlanner p = GoalPlanner(llm: fake(ringsJson(3)));
      final GoalPlan? plan = await p.plan(goalText: '半年减重 10 斤', ringCount: 3, cat: cat);
      expect(plan, isNotNull);
      expect(plan!.rings.length, 3);
      expect(plan.rings.first.title, '第 1 步：做一件具体的事');
      expect(plan.rings[2].proof, '截图3');
    });

    test('模型把 JSON 包在 ```json 围栏里、前后还带废话 → 照样抠出来', () async {
      final String wrapped =
          '好的，我来拆解：\n```json\n${ringsJson(5)}\n```\n以上就是拆解结果。';
      final GoalPlanner p = GoalPlanner(llm: fake(wrapped));
      final GoalPlan? plan = await p.plan(goalText: '一周跑三次', ringCount: 5, cat: cat);
      expect(plan, isNotNull);
      expect(plan!.rings.length, 5);
    });

    test('正文里的花括号不会把抠 JSON 带偏', () async {
      final String messy =
          '说明{这不是 JSON}，真正的在下面：${ringsJson(6)}';
      final GoalPlanner p = GoalPlanner(llm: fake(messy));
      final GoalPlan? plan = await p.plan(goalText: '两个月练吉他', ringCount: 6, cat: cat);
      expect(plan, isNotNull);
      expect(plan!.rings.length, 6);
    });
  });

  group('GoalPlanner.plan · 兜底（一律 null，交给类别模板）', () {
    test('没配 Key → 一个请求都不发', () async {
      final _FakeGateway gw = fake(ringsJson(3), configured: false);
      final GoalPlanner p = GoalPlanner(llm: gw);
      expect(await p.plan(goalText: '随便', ringCount: 3, cat: cat), isNull);
      expect(gw.calls, 0);
    });

    test('网关为 null（没装配）→ null', () async {
      final GoalPlanner p = GoalPlanner();
      expect(await p.plan(goalText: '随便', ringCount: 3, cat: cat), isNull);
    });

    test('网关抛异常 → null，不冒泡', () async {
      final GoalPlanner p = GoalPlanner(llm: _ThrowingGateway());
      expect(await p.plan(goalText: '随便', ringCount: 3, cat: cat), isNull);
    });

    test('空正文 / 纯废话 → null', () async {
      for (final String? reply in <String?>[null, '', '   ', '我觉得这个目标很好。']) {
        final GoalPlanner p = GoalPlanner(llm: fake(reply));
        expect(
          await p.plan(goalText: '随便', ringCount: 3, cat: cat),
          isNull,
          reason: 'reply=$reply',
        );
      }
    });

    test('环数不对（少一环 / 多一环）→ null，不铸半条链', () async {
      for (final int got in <int>[2, 4]) {
        final GoalPlanner p = GoalPlanner(llm: fake(ringsJson(got)));
        expect(
          await p.plan(goalText: '随便', ringCount: 3, cat: cat),
          isNull,
          reason: '模型给了 $got 环，要的是 3 环',
        );
      }
    });

    test('字段缺失 / 空串 / 档位非法 / 分钟数非正 → null', () async {
      final List<String> bad = <String>[
        jsonEncode(<String, dynamic>{
          'rings': <dynamic>[
            <String, dynamic>{'short': '', 'title': 't', 'proof': 'p', 'minutes': 10, 'rank': 'E'},
          ],
        }),
        jsonEncode(<String, dynamic>{
          'rings': <dynamic>[
            <String, dynamic>{'short': 's', 'title': 't', 'proof': 'p', 'minutes': 10, 'rank': 'Z'},
          ],
        }),
        jsonEncode(<String, dynamic>{
          'rings': <dynamic>[
            <String, dynamic>{'short': 's', 'title': 't', 'proof': 'p', 'minutes': 0, 'rank': 'E'},
          ],
        }),
        jsonEncode(<String, dynamic>{
          'rings': <dynamic>[
            <String, dynamic>{'short': 's', 'title': 't', 'minutes': 10, 'rank': 'E'},
          ],
        }),
      ];
      for (final String body in bad) {
        final GoalPlanner p = GoalPlanner(llm: fake(body));
        expect(
          await p.plan(goalText: '随便', ringCount: 1, cat: cat),
          isNull,
          reason: body,
        );
      }
    });
  });

  group('拆解产物落链：内容听模型，阶梯仍按规则', () {
    test('buildNextGoal(planned:) 用计划内容（含末环），档位仍走规则阶梯', () {
      final Goal prev = buildFirstGoal(text: '起步', cat: cat);
      final List<RingSpec> planned = <RingSpec>[
        for (int i = 0; i < 8; i++)
          RingSpec(
            short: '计划${i + 1}',
            title: '计划行动 ${i + 1}',
            proof: '证据${i + 1}',
            // 故意给出「全都很轻」的建议值，看阶梯是否照样收口
            minutes: 6,
            rank: 'E',
          ),
      ];
      final Goal g = buildNextGoal(
        prev: prev,
        cleared: 0,
        total: prev.rings.length,
        level: 1,
        text: '半年减重 10 斤',
        planned: planned,
      );
      expect(g.rings.length, inInclusiveRange(kNextGoalMinRings, kNextGoalMaxRings));
      // ① 内容来自计划 —— **整条**，含末环（模型给的收尾也是可执行的动作）
      expect(g.rings.first.title, '计划行动 1');
      expect(g.rings[1].title, '计划行动 2');
      expect(g.rings.last.title, '计划行动 8', reason: '末环内容不该被通用「兑现它」顶掉');
      // ② 档位仍是规则的阶梯（不因为模型说 E 就全 E），末环强制 S
      expect(g.rings.first.rank, 'E');
      expect(g.rings.last.rank, 'S');
      expect(g.rings.last.finalRing, isTrue);
      for (int i = 1; i < g.rings.length; i++) {
        expect(
          Rarity.ranks.indexOf(g.rings[i].rank),
          greaterThanOrEqualTo(Rarity.ranks.indexOf(g.rings[i - 1].rank)),
          reason: '第 ${i + 1} 环档位倒退',
        );
      }
      // ③ 时限夹在该档上限内（计划说 6 分钟，C 档上限 60 → 仍是 6）
      for (final GoalRing r in g.rings) {
        expect(r.minutes, inInclusiveRange(5, rankCapMinutes(r.rank)));
      }
    });

    test('末环保持计划的短验收时长，不被硬拉成 120 分钟', () {
      // 模型的收尾常常是「同一台秤复称对比」这种**几分钟**的验证动作；
      // 强行按模板给它 120 分钟就成了「花两小时称体重」。
      final Goal prev = buildFirstGoal(text: '起步', cat: cat);
      final List<RingSpec> planned = <RingSpec>[
        for (int i = 0; i < 5; i++)
          RingSpec(
            short: '环${i + 1}',
            title: '行动 ${i + 1}',
            proof: '证${i + 1}',
            minutes: i == 4 ? 5 : 20,
            rank: 'E',
          ),
      ];
      final Goal g = buildNextGoal(
        prev: prev,
        cleared: 0,
        total: prev.rings.length,
        level: 1,
        text: '一周跑三次',
        planned: planned,
      );
      expect(g.rings.last.minutes, 5);
      expect(g.rings.last.rank, 'S');
    });

    test('planned 为 null / 空 → 逐字退回类别模板（与老行为一致）', () {
      final Goal prev = buildFirstGoal(text: '起步', cat: cat);
      // ⚠️ 退回的是**识别出来的那个类别**的模板（「半年减重 10 斤」→ slim），
      //    不是这里传进去的 gen。
      final GoalCategory expectCat = detectCategory('半年减重 10 斤');
      for (final List<RingSpec>? p in <List<RingSpec>?>[null, <RingSpec>[]]) {
        final Goal g = buildNextGoal(
          prev: prev,
          cleared: 0,
          total: prev.rings.length,
          level: 1,
          text: '半年减重 10 斤',
          planned: p,
        );
        expect(g.rings.first.title, expectCat.firstRings.first.title);
        // 模板路径的末环仍是「兑现」（计划路径才保留模型自己的收尾）
        expect(g.rings.last.short, '兑现');
      }
    });

    test('buildFirstGoal(planned:) 环数必须是 3 才采用（docs/05 固定 3 天 3 环）', () {
      final List<RingSpec> three = <RingSpec>[
        for (int i = 0; i < 3; i++)
          RingSpec(short: '起步${i + 1}', title: '起步行动 ${i + 1}', proof: '证${i + 1}', minutes: 5, rank: 'E'),
      ];
      final Goal ok = buildFirstGoal(text: '早睡早起', cat: cat, planned: three);
      expect(ok.rings.length, kFirstGoalDays);
      expect(ok.rings.first.title, '起步行动 1');
      // 档位仍是 E/D/C 三天阶梯（docs/05 锁定，不听模型的 rank）
      expect(ok.rings.map((r) => r.rank).toList(), kFirstGoalRanks);

      // 条数不对 → 整条退回模板，不铸半条
      final Goal fallback = buildFirstGoal(
        text: '早睡早起',
        cat: cat,
        planned: three.sublist(0, 2),
      );
      expect(fallback.rings.first.title, cat.firstRings.first.title);
    });
  });
}

class _FakeGateway implements CopyLlmGateway {
  _FakeGateway(this.reply, {this.configured = true});

  final String? reply;
  @override
  final bool configured;
  int calls = 0;

  @override
  Future<String?> complete({
    required List<Map<String, dynamic>> messages,
    double? temperature,
    int? maxTokens,
    Duration? timeout,
    String? reasoningEffort,
  }) async {
    calls++;
    return reply;
  }
}

class _ThrowingGateway implements CopyLlmGateway {
  @override
  bool get configured => true;

  @override
  Future<String?> complete({
    required List<Map<String, dynamic>> messages,
    double? temperature,
    int? maxTokens,
    Duration? timeout,
    String? reasoningEffort,
  }) async => throw StateError('boom');
}
