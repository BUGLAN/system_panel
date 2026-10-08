import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/widgets/item_drawer.dart';

/// 道具抽屉（`ui.js` L430-448 `Exec.drawer()`）。
///
/// 显示逻辑里有一条容易漏：`disabled` 的条件是 **`!n && !used`** ——
/// 已经挂上生效的道具，哪怕持有数清零了也不能是灰的。
void main() {
  Future<void> mount(
    WidgetTester tester, {
    bool open = true,
    Map<String, int>? counts,
    Set<String>? used,
    int coins = 340,
    ValueChanged<String>? onUse,
    VoidCallback? onShop,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              ItemDrawer(
                open: open,
                counts:
                    counts ?? <String, int>{'dbl': 1, 'crit': 1, 'shield': 1},
                used: used ?? <String>{},
                coins: coins,
                onUse: onUse,
                onShop: onShop,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('内容', () {
    testWidgets('三样执行道具 + 去补给，一共四格', (WidgetTester tester) async {
      await mount(tester);
      expect(find.byKey(const Key('exec.drawer.dbl')), findsOneWidget);
      expect(find.byKey(const Key('exec.drawer.crit')), findsOneWidget);
      expect(find.byKey(const Key('exec.drawer.shield')), findsOneWidget);
      expect(find.byKey(const Key('exec.drawer.shop')), findsOneWidget);
      expect(find.text('双倍卡'), findsOneWidget);
      expect(find.text('暴击芯片'), findsOneWidget);
      expect(find.text('免死金牌'), findsOneWidget);
      expect(find.text('去补给'), findsOneWidget);
    });

    testWidgets('换单券不在执行期抽屉里（它只在派单时用）', (WidgetTester tester) async {
      await mount(tester);
      expect(find.text('换单券'), findsNothing);
    });

    testWidgets('副标题显示持有数；去补给显示金币', (WidgetTester tester) async {
      await mount(tester);
      expect(find.text('持有 ×1'), findsNWidgets(3));
      expect(find.text('金币 340'), findsOneWidget);
    });

    testWidgets('挂上生效的显示「已生效」', (WidgetTester tester) async {
      await mount(tester, used: <String>{'dbl'});
      expect(find.text('已生效'), findsOneWidget);
      expect(find.text('持有 ×1'), findsNWidgets(2));
    });
  });

  group('可用性', () {
    testWidgets('持有 0 且没生效 → 灰掉且点了没反应', (WidgetTester tester) async {
      final List<String> used = <String>[];
      await mount(
        tester,
        counts: <String, int>{'dbl': 0, 'crit': 1, 'shield': 1},
        onUse: used.add,
      );
      await tester.tap(find.byKey(const Key('exec.drawer.dbl')));
      await tester.pump();
      expect(used, isEmpty, reason: '灰掉的不该回调');
      // 有货的照常
      await tester.tap(find.byKey(const Key('exec.drawer.crit')));
      await tester.pump();
      expect(used, <String>['crit']);
    });

    testWidgets('⚠️ 持有 0 但已经生效的**不能**灰（灰了就看不出挂上了）', (
      WidgetTester tester,
    ) async {
      final List<String> used = <String>[];
      await mount(
        tester,
        counts: <String, int>{'dbl': 0, 'crit': 1, 'shield': 1},
        used: <String>{'dbl'},
        onUse: used.add,
      );
      expect(find.text('已生效'), findsOneWidget);
      await tester.tap(find.byKey(const Key('exec.drawer.dbl')));
      await tester.pump();
      expect(used, <String>['dbl'], reason: '已生效的仍可点（原型会 return，回调由上层判）');
    });

    testWidgets('「去补给」走 onShop', (WidgetTester tester) async {
      int shops = 0;
      await mount(tester, onShop: () => shops++);
      await tester.tap(find.byKey(const Key('exec.drawer.shop')));
      await tester.pump();
      expect(shops, 1);
    });
  });

  group('开合', () {
    testWidgets('收起时不接点击（原型 `pointer-events: none`）', (
      WidgetTester tester,
    ) async {
      final List<String> used = <String>[];
      await mount(tester, open: false, onUse: used.add);
      await tester.tap(
        find.byKey(const Key('exec.drawer.dbl')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(used, isEmpty);
    });
  });
}
