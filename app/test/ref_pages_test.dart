import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/data/attrs.dart';
import 'package:system_panel/data/items.dart';
import 'package:system_panel/data/titles.dart';
import 'package:system_panel/design/ref.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/host_state.dart';
import 'package:system_panel/ui/ref/ref_archive.dart';
import 'package:system_panel/ui/ref/ref_boot.dart';
import 'package:system_panel/ui/ref/ref_main.dart';
import 'package:system_panel/ui/ref/ref_shop.dart';
import 'package:system_panel/ui/ref/ref_tray.dart';

/// 第二轮补的五个页面（主线 / 档案 / 补给 / 托盘 / 开机）的冒烟网。
///
/// 只钉「能起来 + 不溢出 + 关键元素在树上」这三件 —— flutter test 用占位
/// 字体，量像素没有意义；真正的排版核对靠离屏出图。
void main() {
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

  testWidgets('RefMain 两档都不溢出，抬头与两键都在', (WidgetTester tester) async {
    for (final Size s in <Size>[const Size(390, 844), const Size(320, 640)]) {
      await mountAt(tester, s, RefMain(goal: Goal.demo()));
      expect(tester.takeException(), isNull);
      expect(find.text('MAINLINE · 主线'), findsOneWidget);
      expect(find.byKey(const Key('ref.main.toBoard')), findsOneWidget);
      expect(find.byKey(const Key('ref.main.swapGoal')), findsOneWidget);
      expect(find.byKey(const Key('ref.main.card')), findsOneWidget);
    }
  });

  testWidgets('RefArchive 四列读数 / 名牒 / 六维都在', (WidgetTester tester) async {
    await mountAt(
      tester,
      const Size(390, 844),
      RefArchive(
        host: HostState.demo,
        ownedCount: 2,
        totalTitles: HostTitle.all.length,
        onBack: () {},
        onEquip: (_) => true,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('ARCHIVE · 宿主档案'), findsOneWidget);
    // 名牒册与六维在首屏之外（参考稿也是滚动区），滚到它再断言
    final Finder scroll = find
        .descendant(
          of: find.byKey(const Key('ref.archive.scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('ref.archive.plates')),
      240,
      scrollable: scroll,
    );
    expect(find.byKey(const Key('ref.archive.plates')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('六维 · 当前数值'),
      240,
      scrollable: scroll,
    );
    expect(find.text(Attr.all.first.name), findsWidgets);
  });

  testWidgets('RefShop 商品与两键', (WidgetTester tester) async {
    await mountAt(
      tester,
      const Size(390, 844),
      RefShop(
        items: Item.all,
        owned: const <String, int>{},
        coins: 0,
        onBack: () {},
        onBuy: (_) => true,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('SUPPLY · 补给站'), findsOneWidget);
    expect(find.byKey(const Key('ref.shop.buy')), findsOneWidget);
    expect(find.byKey(const Key('ref.shop.use')), findsNothing);

    // 参考稿 L1621：只有**补签券**且持有 >0 才显示「使用」。
    await mountAt(
      tester,
      const Size(390, 844),
      RefShop(
        items: Item.all,
        owned: <String, int>{'patch': 2},
        coins: 9999,
        onBack: () {},
        onBuy: (_) => true,
        onUse: (_) => true,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('ref.shop.use')),
      findsNothing,
      reason: '选中第一件商品（非补签券）时不该出现使用键',
    );
  });

  testWidgets('RefItemTray 空态不占位，有道具时展开可读', (WidgetTester tester) async {
    Widget wrap(Widget tray) => MaterialApp(
      home: Scaffold(
        backgroundColor: Ref.bg,
        body: Stack(
          children: <Widget>[
            const Positioned.fill(child: ColoredBox(color: Ref.bg)),
            tray,
          ],
        ),
      ),
    );

    await tester.pumpWidget(
      wrap(
        RefItemTray(items: Item.all, owned: const <String, int>{}, open: true),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      wrap(
        RefItemTray(
          items: Item.all,
          owned: <String, int>{Item.all.first.id: 1},
          open: true,
          equipped: <String>{Item.all.first.id},
          onPick: (_) {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
    expect(find.text('LOADOUT · 选择装载道具'), findsOneWidget);
    expect(find.text('✓ 已装载'), findsOneWidget);
  });

  testWidgets('RefBoot 字标 / 副标题 / 日志 / 唤醒键都在', (WidgetTester tester) async {
    await mountAt(
      tester,
      const Size(390, 844),
      RefBoot(
        lines: const <String>['读取存档 ✓', '校验名牒册 ✓'],
        progress: .7,
        ready: true,
        onWake: () {},
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('HOST'), findsOneWidget);
    expect(find.text('SYSTEM'), findsOneWidget);
    expect(find.text('宿 主 养 成 计 划'), findsOneWidget);
    expect(find.text('点击唤醒系统'), findsOneWidget);
    expect(find.text('TAP TO START'), findsOneWidget);
  });

  testWidgets('RefBoot 未就绪时唤醒键不可见，点了会回调', (WidgetTester tester) async {
    int woke = 0;
    await mountAt(
      tester,
      const Size(390, 844),
      RefBoot(
        lines: const <String>[],
        progress: 0,
        ready: false,
        onWake: () => woke++,
      ),
    );
    final Opacity op = tester.widget<Opacity>(
      find
          .ancestor(of: find.text('点击唤醒系统'), matching: find.byType(Opacity))
          .first,
    );
    expect(op.opacity, 0);
    await tester.tapAt(const Offset(195, 422));
    await tester.pump();
    expect(woke, 1);
  });
}
