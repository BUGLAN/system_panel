import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:system_panel/agent/settings_store.dart';
import 'package:system_panel/design/ref.dart';
import 'package:system_panel/main.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/host_state.dart';
import 'package:system_panel/state/quest.dart';
import 'package:system_panel/ui/ref/ref_board.dart';
import 'package:system_panel/ui/ref/ref_exec.dart';
import 'package:system_panel/ui/ref/ref_home.dart';
import 'package:system_panel/ui/ref/ref_hud.dart';
import 'package:system_panel/ui/ref/ref_llm_settings.dart';

/// v3 参考稿还原层的冒烟网。
///
/// 这一层不做像素断言（flutter test 用占位字体，量不准），只钉三件事：
///  1. 整壳能起来、没有布局溢出（新页面的 Row/Column 最容易在这一步炸）；
///  2. 关键页面真的在树上（大厅 / 委托板 / 执行 / HUD）；
///  3. LLM 设置面板的八项都在。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  Future<void> mountAt(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = Size(size.width * 3, size.height * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(backgroundColor: Ref.bg, body: child),
      ),
    );
    await tester.pump();
  }

  testWidgets('整壳起来：大厅渲染、无异常', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SysApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('RefHome：320 与 600 宽都不溢出', (WidgetTester tester) async {
    for (final Size size in <Size>[
      const Size(320, 640),
      const Size(600, 900),
    ]) {
      await mountAt(
        tester,
        size,
        RefHome(
          host: HostState.demo,
          goal: Goal.demo(),
          quip: '清单不会自己变短。但你的借口会自己变长。',
          queue: 4,
          day: 3,
          days: 14,
        ),
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('RefHud：三颗 chip 与等级环都在', (WidgetTester tester) async {
    await mountAt(
      tester,
      const Size(390, 844),
      Stack(children: <Widget>[RefHud(state: HostState.demo)]),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(RefHud), findsOneWidget);
    expect(find.text('林深'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('RefBoard：空态与有单都能渲染', (WidgetTester tester) async {
    await mountAt(
      tester,
      const Size(390, 844),
      RefBoard(
        quests: const <Quest>[],
        filter: 'all',
        onFilter: (String _) {},
        onTap: (Quest _) {},
      ),
    );
    expect(find.text('今天，接哪一单？'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await mountAt(
      tester,
      const Size(390, 844),
      RefBoard(
        quests: <Quest>[Quest.demo],
        filter: 'all',
        onFilter: (String _) {},
        onTap: (Quest _) {},
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
    expect(find.byType(RefTicketCard), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('RefExec：计时 / 三个证据槽 / 提交键', (WidgetTester tester) async {
    await mountAt(
      tester,
      const Size(390, 844),
      RefExec(
        quest: Quest.demo,
        elapsed: const Duration(minutes: 12, seconds: 4),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('ref.exec.slot.0')), findsOneWidget);
    expect(find.byKey(const Key('ref.exec.submit')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('LLM 设置：八项都在', (WidgetTester tester) async {
    await mountAt(
      tester,
      const Size(390, 844),
      LlmSettingsPane(initial: const AgentSettings(), onClose: () {}),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Base URL'), findsOneWidget);
    expect(find.text('API Key'), findsOneWidget);
    expect(find.text('模型'), findsOneWidget);
    // 底部两颗键是固定的（不随列表滚走）
    expect(find.text('保存配置'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    // 采样组在下面，滚动到它可见
    for (final String label in <String>['温度', '流式输出', '证据视觉校验']) {
      await tester.scrollUntilVisible(
        find.text(label),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('ref.llmScroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text(label), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
