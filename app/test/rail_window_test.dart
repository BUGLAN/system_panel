import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/widgets/main_view.dart';

/// ═══════════════════════════════════════════════════════════
///  牌扇张数（2026-10-23 宿主裁定）：清单有几张就挂几张，**不裁**
///
///  事故：10 张清单只挂 5 张，界面无任何说明 → 宿主滑了几下数到 7 张，
///  与「1/10 单」对不上，报成「卡片数与统计数不一致」。
///
///  当时的补丁是「加一行第 N 张·共 M 单」，**被宿主否掉** ——
///  那是给「被裁」写说明，而不是不裁。正解在牌扇这一侧：
///  全量上桌，靠间距（strideScale）吸收张数，不靠丢牌。
/// ═══════════════════════════════════════════════════════════
void main() {
  Goal goalOf(int n, {int done = 0}) => Goal(
    text: '两周内骑自行车10次',
    short: '骑自行车',
    at: DateTime(2026, 10, 23),
    days: 14,
    cat: 'run',
    plan: <PlanTask>[
      for (int i = 0; i < n; i++)
        PlanTask(
          index: i,
          short: '骑${i + 1}',
          title: '第 ${i + 1} 次骑行',
          proof: '轨迹截图',
          minutes: 20,
          rank: i == n - 1 ? 'S' : 'E',
          state: i < done ? PlanState.done : PlanState.todo,
          finalTask: i == n - 1,
        ),
    ],
  );

  Future<void> mount(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Stack(children: <Widget>[child]))),
    );
    await tester.pump();
  }

  group('牌扇挂满全部清单', () {
    test('10 张清单 → 牌扇 10 张（与「1/10 单」的 10 一致）', () {
      final MainView v = MainView(goal: goalOf(10, done: 1));
      expect(v.goal.plan.length, 10);
      expect(v.railIndices(), <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    });

    test('任意张数都全量上桌（2 / 5 / 14 / 180）', () {
      for (final int n in <int>[2, 5, 14, 180]) {
        final MainView v = MainView(goal: goalOf(n));
        expect(v.railIndices().length, n, reason: '$n 张就该挂 $n 张');
        expect(v.railIndices().first, 0);
        expect(v.railIndices().last, n - 1);
      }
    });

    test('完成度不影响上桌张数（不再有窗口滑动）', () {
      for (final int done in <int>[0, 1, 5, 9]) {
        final MainView v = MainView(goal: goalOf(10, done: done));
        expect(v.railIndices().length, 10, reason: 'done=$done');
      }
    });

    test('空清单 → 0 张（不崩）', () {
      final MainView v = MainView(goal: goalOf(0));
      expect(v.railIndices(), isEmpty);
    });
  });

  group('张数靠间距吸收，不靠丢牌', () {
    test('≤ kRailComfort 张：步距原样（视觉不变）', () {
      for (final int n in <int>[2, 5, MainView.kRailComfort]) {
        expect(MainView(goal: goalOf(n)).railStrideScale, 1.0, reason: '$n 张');
      }
    });

    test('超过 kRailComfort：步距按张数收窄，且不低于下限', () {
      expect(MainView(goal: goalOf(10)).railStrideScale, lessThan(1.0));
      expect(
        MainView(goal: goalOf(180)).railStrideScale,
        MainView.kRailMinStrideScale,
        reason: '再多也不能窄到叠成一摞',
      );
    });

    test('窗口标签的 API 已彻底移除（不留死代码）', () {
      // 那行「第 N 张 · 共 M 单」是给「被裁」写的说明，裁撤后一并撤掉。
      // 这里钉的是：不裁之后**不需要**那个读数，所以它不该回来。
      final List<String> src = <String>[
        'lib/widgets/main_view.dart',
      ];
      for (final String f in src) {
        expect(
          File(f).readAsStringSync(),
          isNot(contains('main.railWindow')),
          reason: '窗口标签必须已删除，否则又变成「给被裁写说明」',
        );
      }
    });
  });

  group('渲染', () {
    testWidgets('10 张：牌扇渲染成功，且不再有窗口标签', (WidgetTester tester) async {
      await mount(tester, MainView(goal: goalOf(10, done: 1), visible: true));
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.byKey(const Key('main.rail')), findsOneWidget);
      expect(find.byKey(const Key('main.railWindow')), findsNothing);
    });

    testWidgets('180 张也不抛（全量上桌 + 收窄步距）', (WidgetTester tester) async {
      await mount(tester, MainView(goal: goalOf(180), visible: true));
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('main.rail')), findsOneWidget);
    });
  });
}
