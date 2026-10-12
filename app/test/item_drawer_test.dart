import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/data/items.dart';
import 'package:system_panel/widgets/card_table.dart';
import 'package:system_panel/widgets/item_drawer.dart';

/// 道具抽屉（`ui.js` L430-448 `Exec.drawer()`）。
///
/// ⚠️ 2026-10-11 宿主最终裁决：「道具卡样式和动效都没有啊，你为什么不直接搬过来，
///    反而重写？」—— 抽屉**不再自己画一套**，直接放补给页同一张牌桌
///    （`CardTable` + `skin: shelf` + `size: l`）。所以这一版测试从
///    「自绘卡面的内部结构」改成**牌桌的对外语义**：
///      · 三样执行道具、与执行面板共用 [Item.execIds] 一份清单
///      · 领位落在第一件「有货或已生效」的牌上，点领位 = 用掉它
///      · 无货且没生效 → 不可用（点了不回调）
///      · 收起时整桌不接命中
///    每张牌的 key 是 `table.card.<id>`（CardTable 统一发）。
///
/// 被删掉的 `item_rail.dart`（甲 · 物件台）是这次改版前的自绘轨，
/// 改走牌桌后**全仓已无引用**，连同它那份测试一并移除（见提交说明）。
void main() {
  Future<void> mount(
    WidgetTester tester, {
    bool open = true,
    Map<String, int>? counts,
    Set<String>? used,
    ValueChanged<String>? onUse,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
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
                coins: 340,
                onUse: onUse,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// 抽屉这一层的不透明度（开合动画挂在 CardTable **外面**的 AnimatedOpacity 上）。
  ///
  /// ⚠️ 别去读牌自己的 Opacity：那一个是「侧卡压暗」（`_sideOp`），
  ///    收起抽屉时它一点不变 —— 用它判开合会永远看不出区别。
  double drawerOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find
            .ancestor(
              of: find.byType(CardTable),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      )
      .opacity;

  Finder card(String id) => find.byKey(Key('table.card.$id'));

  /// 点某张牌（用矩形中心；侧卡可能被视口裁掉一半，夹回可见区）
  Future<void> tapCard(WidgetTester tester, String id) async {
    final Rect r = tester.getRect(card(id));
    final Rect table = tester.getRect(find.byType(CardTable));
    final double x = r.center.dx.clamp(table.left + 4, table.right - 4);
    await tester.tapAt(Offset(x, r.center.dy));
    await tester.pump();
  }

  /// 点**领位**（牌桌正中那张）—— 牌桌的语义是「点领位 = 落定」
  Future<void> tapLead(WidgetTester tester) async {
    await tester.tapAt(tester.getCenter(find.byType(CardTable)));
    await tester.pump();
  }

  group('内容', () {
    testWidgets('三样执行道具，一共三张牌', (WidgetTester tester) async {
      await mount(tester);
      expect(find.byType(CardFace), findsNWidgets(3));
      expect(find.text('双倍卡'), findsOneWidget);
      expect(find.text('暴击芯片'), findsOneWidget);
      expect(find.text('免死金牌'), findsOneWidget);
      // 与执行面板共用同一份清单，不是各写一份
      expect(ItemDrawer.execIds, <String>['dbl', 'crit', 'shield']);
    });

    testWidgets('⚠️「去补给」键已删除（宿主指定），牌桌就是全部', (WidgetTester tester) async {
      await mount(tester);
      expect(find.text('去补给'), findsNothing);
    });
  });

  group('可用性', () {
    testWidgets('持有 0 但已经生效的**不能**灰（灰了就看不出挂上了）', (
      WidgetTester tester,
    ) async {
      final List<String> used = <String>[];
      await mount(
        tester,
        counts: <String, int>{'dbl': 0, 'crit': 1, 'shield': 1},
        used: <String>{'dbl'},
        onUse: used.add,
      );
      // 已生效 → 牌面角标是「已生效」，且**仍然可用**：领位就是它，点得动
      expect(find.text('已生效'), findsOneWidget);
      await tapLead(tester);
      expect(used, <String>['dbl'], reason: '持有 0 但已生效 → 仍要能点（不灰）');
    });

    testWidgets('持有 0 且没生效 → 灰掉且点了没反应', (WidgetTester tester) async {
      final List<String> used = <String>[];
      // 三张全无货、全无生效 → `_firstUsable` 退回中位，领位那张也是禁用的，
      // 于是「点领位」正好是在点一张不可用的牌。
      await mount(
        tester,
        counts: <String, int>{'dbl': 0, 'crit': 0, 'shield': 0},
        onUse: used.add,
      );
      expect(find.text('持有 ×0'), findsNWidgets(3));
      await tapLead(tester);
      expect(used, isEmpty, reason: '无货且没生效的牌点了不该回调');
    });

    testWidgets('领位跳过第一张无货的牌（落在 crit 上）', (WidgetTester tester) async {
      final List<String> used = <String>[];
      // dbl 无货也没生效 → 领位应当是 crit
      await mount(
        tester,
        counts: <String, int>{'dbl': 0, 'crit': 1, 'shield': 1},
        onUse: used.add,
      );
      await tapLead(tester);
      expect(used, <String>['crit']);
    });

    testWidgets('已生效的牌即使持有 0 也能当领位（落在 dbl 上）', (WidgetTester tester) async {
      // ⚠️ 必须**另起一条用例**：同一个 tester 里第二次 pumpWidget 会复用
      //    CardTable 的 State（同类型同位置），`initState` 不再跑、领位不会重算
      //    —— 合在一起写会读到上一轮的领位（crit）。
      final List<String> used = <String>[];
      await mount(
        tester,
        counts: <String, int>{'dbl': 0, 'crit': 1, 'shield': 1},
        used: <String>{'dbl'},
        onUse: used.add,
      );
      await tapLead(tester);
      expect(used, <String>['dbl']);
    });
  });

  group('开合', () {
    testWidgets('收起时不接点击（原型 `pointer-events: none`）', (WidgetTester tester) async {
      final List<String> used = <String>[];
      await mount(tester, open: false, onUse: used.add);
      await tapCard(tester, 'crit');
      expect(used, isEmpty);
    });

    testWidgets('收起 → 不透明度 0；展开 → 可见', (WidgetTester tester) async {
      await mount(tester, open: false);
      expect(drawerOpacity(tester), 0);
      await mount(tester);
      expect(drawerOpacity(tester), 1);
    });
  });
}
