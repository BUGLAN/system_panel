import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/widgets/card_skins.dart';
import 'package:system_panel/widgets/main_view.dart';

/// 主线页（docs/33 卡片式新视图）—— 数据读数 + 委托轨窗口 + 五态 + 手势。
///
/// ⚠️ 这一页按百分比/相机数学定位，必须用 `tester.view` 设尺寸
/// （`setSurfaceSize` 不改 MediaQuery，见 app/PORTING-NOTES.md 第 13 条）。
const Size kDesign = Size(390, 844);

Future<void> _mount(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = Size(kDesign.width * 3, kDesign.height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Stack(children: <Widget>[child]))),
  );
  await tester.pump();
}

/// 一张「全待办」的 12 天清单（测轨窗口/状态用，绕开演示档的固定形态）
Goal _planOf({int days = 12, int done = 0}) => Goal(
  text: '半年内坚持健身',
  short: '健身',
  at: DateTime(2026, 10, 12),
  days: days,
  plan: <PlanTask>[
    for (int i = 0; i < days; i++)
      PlanTask(
        index: i,
        short: '第 ${i + 1} 张',
        title: '第 ${i + 1} 张的题面',
        proof: '截图',
        minutes: 20,
        rank: i == days - 1 ? 'S' : 'D',
        state: i < done ? PlanState.done : PlanState.todo,
        finalTask: i == days - 1,
      ),
  ],
);

void main() {
  group('计划数据（docs/33：目标 = 一句话 + 期限 + 任务清单）', () {
    test('演示档：8 张、第 5 张脚下、末张是兑现单', () {
      final Goal g = Goal.demo();
      expect(g.totalTasks, 8);
      expect(g.doneCount, 4);
      expect(g.firstOpenIndex, 4);
      expect(g.plan[4].short, '五公里');
      expect(g.plan[7].finalTask, isTrue);
      expect(g.plan[7].rank, 'S');
      expect(g.plan[0].statusText(), startsWith('已完成 · '));
      expect(g.plan[4].statusText(), '正在执行');
      expect(g.plan[5].statusText(), '待发布');
    });

    test('状态码兼容老档（cur/lock 都读得回来）', () {
      expect(PlanState.of('cur'), PlanState.active);
      expect(PlanState.of('done'), PlanState.done);
      expect(PlanState.of('lock'), PlanState.todo);
      expect(PlanState.of('nonsense'), PlanState.todo);
    });

    test('抬头读数：已过 N/M 天 · 完成 X 单', () {
      // 演示档那条主线是「三个月跑完半马」→ 期限 90 天（清单 8 张是环时代残留形态）
      final Goal g = Goal.demo();
      expect(g.days, 90);
      expect(g.progressText(g.at), '已过 1/90 天 · 完成 4 单');
      expect(g.remainingDays(g.at), 89);
    });

    test('空目标 = 没有清单（未绑定）', () {
      expect(Goal.empty().isEmpty, isTrue);
      expect(Goal.empty().totalTasks, 0);
      expect(Goal.empty().firstOpenIndex, -1);
    });
  });

  group('委托轨（第 4 套皮肤 duty）', () {
    test('尺寸：轨上 268×58、审视 208×292（docs/32 §4.2 的 W 条牌 / L 大牌）', () {
      expect(dimsOf(CardSkin.duty, CardTableSize.m).w, 268);
      expect(dimsOf(CardSkin.duty, CardTableSize.m).h, 58);
      expect(dimsOf(CardSkin.duty, CardTableSize.l).w, 208);
      expect(dimsOf(CardSkin.duty, CardTableSize.l).h, 292);
    });

    test('窗口：从第一张没做完的往前带一张，往后最多 6 张', () {
      // 12 天全待办 → 第 0 张起（往前带不了）最多 6 张
      expect(MainView(goal: _planOf()).railIndices(), <int>[0, 1, 2, 3, 4, 5]);
      // 做完 4 张 → 第一张没做完的是 4，往前带第 3 张 → 3..8
      expect(
        MainView(goal: _planOf(done: 4)).railIndices(),
        <int>[3, 4, 5, 6, 7, 8],
      );
      // 全走完 → 停在最后两张（往前带一张的既有口径）
      expect(
        MainView(goal: _planOf(days: 12, done: 12)).railIndices(),
        <int>[10, 11],
      );
    });

    test('五态：已完成 / 执行中 / 可接 / 待发布 / 已放弃', () {
      final Goal g = _planOf(days: 6, done: 1);
      final MainView v = MainView(goal: g, published: {2, 3}, activeIndex: 2);
      expect(v.stateOf(0), DutyState.done);
      expect(v.stateOf(2), DutyState.active);
      expect(v.stateOf(3), DutyState.open);
      expect(v.stateOf(5), DutyState.sealed);
      final Goal ab = g.copyWith(
        plan: <PlanTask>[
          g.plan[0],
          g.plan[1].copyWith(state: PlanState.abandoned),
          ...g.plan.sublist(2),
        ],
      );
      expect(MainView(goal: ab).stateOf(1), DutyState.abandoned);
    });

    test('牌面九区映射：角标 / 印位 / 规则行 / 报酬条', () {
      final Goal g = _planOf(days: 6, done: 1);
      final TableCard c = MainView(goal: g, published: {2}).cardOf(2);
      expect(c.kicker, 'MAIN · 03');
      expect(c.rank, g.plan[2].rank);
      expect(c.dutyMeta, contains('20 分钟'));
      expect(c.dutyMeta, contains('截图'));
      expect(c.loot.first, startsWith('EXP '));
      expect(c.dutyState, DutyState.open);
    });
  });

  group('主线页 · 交互', () {
    testWidgets('点一条 → 展开 L 大牌；按住可接的那条 → 接单', (WidgetTester tester) async {
      final Goal g = _planOf(days: 6, done: 1);
      int? picked;
      int? taken;
      await _mount(
        tester,
        MainView(
          goal: g,
          published: const <int>{2, 3},
          activeIndex: 2,
          onSelect: (int i) => picked = i,
          onAccept: (int i) => taken = i,
        ),
      );
      expect(find.byKey(const Key('main.top')), findsOneWidget);
      expect(find.byKey(const Key('main.rail')), findsOneWidget);
      expect(find.byKey(const Key('main.newGoal')), findsOneWidget);

      await tester.tap(find.byKey(const Key('main.card.3')));
      expect(picked, 3);

      await tester.longPress(find.byKey(const Key('main.card.3')));
      expect(taken, 3);
    });

    testWidgets('审视态：L 大牌 + 接这张；点「收起」回轨', (WidgetTester tester) async {
      final Goal g = _planOf(days: 6, done: 1);
      int? picked;
      int? taken;
      await _mount(
        tester,
        MainView(
          goal: g,
          published: const <int>{2, 3},
          selected: 3,
          onSelect: (int i) => picked = i,
          onAccept: (int i) => taken = i,
        ),
      );
      expect(find.byKey(const Key('main.detail')), findsOneWidget);
      expect(find.byKey(const Key('main.rail')), findsNothing);
      await tester.tap(find.byKey(const Key('main.take')));
      expect(taken, 3);
      await tester.tap(find.byKey(const Key('main.back')));
      expect(picked, -1);
    });

    testWidgets('待发布那张没有「接这张」（只读读数）', (WidgetTester tester) async {
      await _mount(
        tester,
        MainView(goal: _planOf(days: 6, done: 1), selected: 5),
      );
      expect(find.byKey(const Key('main.take')), findsNothing);
      expect(find.byKey(const Key('main.detail')), findsOneWidget);
    });
  });
}
