import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/goal_gen.dart';
import 'package:system_panel/widgets/interview_deck.dart';

/// ═══════════════════════════════════════════════════════════
///  绑定流 · 卡片式访谈（T6-1）
///
///  覆盖宿主验收的前两环（装配进 main.dart 的 onboard 幕归 T8）：
///    输入目标 → 依目标生成 3~5 张访谈卡 → 完成访谈 → 建立主线
///    （首目标 3 天 3 环 E/D/C）；访谈答案逐卡入档。
/// ═══════════════════════════════════════════════════════════
void main() {
  /// sleep 类卡组（= docs/18 §2.1 示例卡组；lv1 恰 3 张）
  List<InterviewCard> sleepCards({int level = 1}) =>
      interviewCardsFor(goalCats['sleep']!, level: level);

  Future<void> mount(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    );
    await tester.pump();
  }

  group('访谈卡组件（InterviewDeck）', () {
    testWidgets('首卡：问题 / 选项 chip / 自己写 / 进度都在', (WidgetTester tester) async {
      await mount(
        tester,
        InterviewDeck(cards: sleepCards(), onDone: (_) {}),
      );

      expect(find.text('现在几点起、几点睡？'), findsOneWidget);
      expect(find.text('0 点前睡 7 点前起'), findsOneWidget);
      expect(find.text('没有固定'), findsOneWidget);
      expect(find.text('自己写'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('deck.progress'))).data,
        '01 / 03',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('点选项推进：01→02→03，最后一张答完回调全部答案', (
      WidgetTester tester,
    ) async {
      final List<String> answered = <String>[];
      Map<String, String>? done;
      await mount(
        tester,
        InterviewDeck(
          cards: sleepCards(),
          onCardAnswered:
              (InterviewCard c, String a) => answered.add('${c.id}=$a'),
          onDone: (Map<String, String> a) => done = a,
        ),
      );

      await tester.tap(find.text('1-2 点睡 9 点后起'));
      await tester.pumpAndSettle();
      expect(find.text('最近几天作息如何？'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('deck.progress'))).data,
        '02 / 03',
      );
      expect(answered, <String>['sleep.schedule=1-2 点睡 9 点后起']);

      await tester.tap(find.text('天天熬夜'));
      await tester.pumpAndSettle();
      expect(find.text('愿意做怎样的坚持？'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('deck.progress'))).data,
        '03 / 03',
      );

      await tester.tap(find.text('睡前不碰手机'));
      await tester.pumpAndSettle();

      expect(done, isNotNull);
      expect(done!.length, 3);
      expect(done!['sleep.recent'], '天天熬夜');
      expect(done!['sleep.persist'], '睡前不碰手机');
      expect(answered.length, 3);
    });

    testWidgets('「自己写」自由输入也能过卡', (WidgetTester tester) async {
      Map<String, String>? done;
      await mount(
        tester,
        InterviewDeck(cards: sleepCards(), onDone: (Map<String, String> a) => done = a),
      );

      await tester.tap(find.byKey(const Key('deck.custom')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deck.custom.input')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('deck.custom.input')),
        '工作日 23 点睡，周末补觉不超过 1 小时',
      );
      await tester.tap(find.byKey(const Key('deck.custom.submit')));
      await tester.pumpAndSettle();

      // 只提交了第一张：推进到第 2 张，答案已记下
      expect(find.text('最近几天作息如何？'), findsOneWidget);
      expect(done, isNull); // 还没答完，不回调
    });

    testWidgets('自己写为空时不偷跑', (WidgetTester tester) async {
      Map<String, String>? done;
      await mount(
        tester,
        InterviewDeck(
          cards: sleepCards(),
          onDone: (Map<String, String> a) => done = a,
        ),
      );

      await tester.tap(find.byKey(const Key('deck.custom')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deck.custom.submit')));
      await tester.pumpAndSettle();

      expect(find.text('现在几点起、几点睡？'), findsOneWidget); // 还在第一张
      expect(done, isNull);
    });

    testWidgets('五张卡组（lv4+）走完回调 5 条答案', (WidgetTester tester) async {
      Map<String, String>? done;
      final List<InterviewCard> five = sleepCards(level: 4);
      expect(five.length, 5);
      await mount(
        tester,
        InterviewDeck(cards: five, onDone: (Map<String, String> a) => done = a),
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('deck.progress'))).data,
        '01 / 05',
      );

      // sleep 3 张 + common.slot + common.history，全点第一个选项
      final List<String> picks = <String>[
        '0 点前睡 7 点前起',
        '基本规律',
        '固定起床闹钟',
        '2 个',
        '坚持了几天',
      ];
      for (int i = 0; i < picks.length; i++) {
        await tester.tap(find.text(picks[i]));
        await tester.pumpAndSettle();
      }

      expect(done, isNotNull);
      expect(done!.length, 5);
      expect(done!.keys, <String>[
        'sleep.schedule',
        'sleep.recent',
        'sleep.persist',
        'common.slot',
        'common.history',
      ]);
    });
  });

  group('绑定流组件链（目标 → 访谈 → 建立主线）', () {
    testWidgets('早睡早起：3 张卡答完 → 首目标 3 天 3 张 E/D/C 入档', (
      WidgetTester tester,
    ) async {
      // ① 宿主输入目标 → Agent 判类别（这里直接用类别表里的 sleep）
      const String goalText = '一个月早睡早起';
      final GoalCategory cat = goalCats['sleep']!;
      final List<String> answered = <String>[];
      Map<String, String>? answers;

      await mount(
        tester,
        InterviewDeck(
          cards: interviewCardsFor(cat),
          onCardAnswered: (InterviewCard c, String a) => answered.add(a),
          onDone: (Map<String, String> a) => answers = a,
        ),
      );

      // ② 依次答完（天天熬夜 → 负担重的样本）
      for (final String pick in <String>[
        '1-2 点睡 9 点后起',
        '天天熬夜',
        '固定起床闹钟',
      ]) {
        await tester.tap(find.text(pick));
        await tester.pumpAndSettle();
      }
      expect(answers, isNotNull);
      expect(answered.length, 3);

      // ③ 访谈答案 → Agent 拆解（这里直接喂一份合规的「她交上来的」任务池，
      //    只验落库形状；Agent 本身的行为见 plan_agent_test.dart）
      final Goal goal = buildGoalFromPlan(
        text: goalText,
        short: '早起',
        cat: cat,
        days: kFirstGoalDays,
        tasks: const <TaskSpec>[
          TaskSpec(
            short: '先早一点',
            title: '比昨天早睡 15 分钟',
            proof: '屏幕使用时间截图',
            minutes: 10,
            rank: 'E',
          ),
          TaskSpec(
            short: '23:30',
            title: '今晚 23:30 前放下手机上床',
            proof: '屏幕使用时间截图',
            minutes: 20,
            rank: 'D',
          ),
          TaskSpec(
            short: '不赖床',
            title: '闹钟响后 5 分钟内起床',
            proof: '起床时间截图',
            minutes: 10,
            rank: 'C',
          ),
        ],
        answers: answers!,
        firstGoal: true,
      );
      expect(goal.days, 3);
      expect(goal.cat, 'sleep');
      expect(goal.plan.length, 3);
      expect(goal.plan.map((PlanTask r) => r.rank).toList(), <String>[
        'E',
        'D',
        'C',
      ]);
      expect(goal.plan.first.state, PlanState.todo);
      expect(goal.firstOpenIndex, 0);
      // 「她」按访谈答案把第 1 张压到 15 分钟以内
      expect(goal.plan.first.title, '比昨天早睡 15 分钟');
      expect(goal.interview.length, 3);
      expect(shouldOnboard(goal), isFalse); // 主线已立，不再触发绑定流

      // ④ 记忆导出（T5 收口）
      final List<String> mem = memoriesFromInterview(
        cat: cat,
        answers: answers!,
        goalText: goalText,
      );
      expect(mem.first, contains('一个月早睡早起'));
      expect(mem.length, 4);
    });

    testWidgets('换一类目标（考研上岸）卡组跟着变', (WidgetTester tester) async {
      const String goalText = '考研上岸';
      final GoalCategory cat = goalCats['exam']!;

      Map<String, String>? answers;
      await mount(
        tester,
        InterviewDeck(
          cards: interviewCardsFor(cat),
          onDone: (Map<String, String> a) => answers = a,
        ),
      );

      expect(find.text('备考到什么阶段了？'), findsOneWidget);
      expect(find.text('现在几点起、几点睡？'), findsNothing); // 不是 sleep 的题

      for (final String pick in <String>['刚开始', '2~3 小时', '专业课']) {
        await tester.tap(find.text(pick));
        await tester.pumpAndSettle();
      }

      final Goal goal = buildGoalFromPlan(
        text: goalText,
        short: '上岸',
        cat: cat,
        days: kFirstGoalDays,
        tasks: const <TaskSpec>[
          TaskSpec(
            short: '清桌',
            title: '清空书桌，只留下要用的一本书',
            proof: '桌面照片',
            minutes: 10,
            rank: 'E',
          ),
          TaskSpec(
            short: '三小时',
            title: '今天专注复习 3 小时',
            proof: '计时截图',
            minutes: 25,
            rank: 'D',
          ),
          TaskSpec(
            short: '真题',
            title: '做一套真题并复盘错题',
            proof: '试卷照片',
            minutes: 30,
            rank: 'C',
          ),
        ],
        answers: answers!,
        firstGoal: true,
      );
      expect(goal.days, 3);
      expect(goal.short, '上岸');
      expect(goal.plan.first.title, '清空书桌，只留下要用的一本书');
      expect(goal.plan.first.title, isNot('比昨天早睡 15 分钟'));
    });
  });
}
