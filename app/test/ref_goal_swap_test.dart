import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/design/ref.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/sfx.dart';
import 'package:system_panel/ui/ref/ref_goal_swap.dart';
import 'package:system_panel/ui/ref/ref_loading.dart';

/// docs/49 C/D：换目标页（v3 重写）与拆解加载卡的冒烟网。
///
/// 钉三件事：两档屏宽不溢出；空输入时主键不可点、有字才可点；
/// 给了 loading 之后表单整块换成加载卡（这就是「点了像卡死」的修复点）。
void main() {
  setUp(() => Sfx.enabled = false); // 测试环境没有音频插件

  Future<void> mountAt(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = Size(size.width * 3, size.height * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(backgroundColor: Ref.bg, body: child),
      ),
    );
    // RefReveal 逐层显影：最后一层 140 + 5×80 = 540ms 起播，680ms 播完
    await tester.pump(const Duration(milliseconds: 1400));
  }

  testWidgets('RefGoalSwap 两档都不溢出，当前主线卡 / 输入 / 两键都在', (
    WidgetTester tester,
  ) async {
    for (final Size s in <Size>[const Size(390, 844), const Size(320, 640)]) {
      final TextEditingController c = TextEditingController();
      addTearDown(c.dispose);
      await mountAt(
        tester,
        s,
        RefGoalSwap(
          goal: Goal.demo(),
          controller: c,
          presets: const <String>['半年减重 10 斤', '考研上岸'],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('REWRITE · 换目标'), findsOneWidget);
      expect(find.byKey(const Key('ref.swap.current')), findsOneWidget);
      expect(find.byKey(const Key('ref.swap.input')), findsOneWidget);
      expect(find.byKey(const Key('ref.swap.submit')), findsOneWidget);
      expect(find.byKey(const Key('ref.swap.cancel')), findsOneWidget);
    }
  });

  testWidgets('空输入不提交；点预设词后可提交', (WidgetTester tester) async {
    final TextEditingController c = TextEditingController();
    addTearDown(c.dispose);
    int submits = 0;
    await mountAt(
      tester,
      const Size(390, 844),
      RefGoalSwap(
        goal: Goal.demo(),
        controller: c,
        presets: const <String>['半年减重 10 斤'],
        onSubmit: () => submits++,
      ),
    );
    final Finder submit = find.byKey(const Key('ref.swap.submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 600));
    expect(submits, 0);

    final Finder chip = find.text('半年减重 10 斤');
    await tester.ensureVisible(chip);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(chip);
    await tester.pump();
    expect(c.text, '半年减重 10 斤');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
    expect(submits, 1);
  });

  testWidgets('给了 loading：表单整块换成加载卡，分步与计时都在', (WidgetTester tester) async {
    final TextEditingController c = TextEditingController(text: '考研上岸');
    addTearDown(c.dispose);
    await mountAt(
      tester,
      const Size(390, 844),
      RefGoalSwap(
        goal: Goal.demo(),
        controller: c,
        presets: const <String>[],
        loading: const RefPlanLoading(
          steps: <String>['匹配类别与期限', '拆解任务清单', '规则校验'],
          stage: 1,
          goal: '考研上岸',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('ref.planLoading')), findsOneWidget);
    expect(find.byKey(const Key('ref.swap.input')), findsNothing);
    expect(find.text('拆解任务清单'), findsOneWidget);
    expect(find.byKey(const Key('ref.planLoading.clock')), findsOneWidget);
    // 第 1 步已完成（打勾），第 2 步进行中
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('拆解中…'), findsOneWidget);
  });
}
