import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/data/items.dart';
import 'package:system_panel/widgets/item_rail.dart';
import 'package:system_panel/widgets/rail_base.dart';

/// 甲 · 物件台（`docs/28` §4）—— 领位抬起 / 让位退让 / 点法语义。
///
/// 几何（实测值，不是推的）：视口 266、卡 86、间距 8、一格 94。
/// 领位槽永远落在视口中心（内容坐标 133），侧卡槽 = 133 ± (94 + 14 浮动)。
/// 所以**布局矩形**的中心是 133 / 241 / 25，矩形半宽 43。
/// 测试把物件台放在 (100, 100)，全局坐标 = 100 + 内容坐标。
const Offset kAt = Offset(100, 100);
const double kMid = kItemRailViewport / 2; // 133

void main() {
  Future<void> mount(
    WidgetTester tester, {
    bool open = true,
    Map<String, int>? counts,
    Set<String>? used,
    List<String> ids = Item.execIds,
    ValueChanged<String>? onUse,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              Positioned(
                left: kAt.dx,
                top: kAt.dy,
                child: ItemRail(
                  open: open,
                  counts:
                      counts ?? <String, int>{'dbl': 1, 'crit': 1, 'shield': 1},
                  used: used ?? <String>{},
                  ids: ids,
                  onUse: onUse,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  /// 某张卡**本帧实际生效**的不透明度（读它自己的 state，不猜渲染树）
  double opacityOf(WidgetTester tester, String id) => tester
      .state<ItemCardState>(find.byKey(Key('exec.drawer.$id')))
      .opacity;

  /// 点某张卡。
  ///
  /// 用**矩形中心**而不是 `tester.getCenter`：最右那张卡会有一部分被视口
  /// 裁掉（这是设计的一部分 —— 露出边缘表示「右边还有」），它的矩形中心
  /// 可能落在视口外，`tester.tap` 会因此报警。这里把点夹回可见区内。
  Future<void> tapCard(WidgetTester tester, String id) async {
    final Rect r = tester.getRect(find.byKey(Key('exec.drawer.$id')));
    final Rect rail = tester.getRect(find.byType(ItemRail));
    final double x = r.center.dx.clamp(rail.left + 4, rail.right - 4);
    await tester.tapAt(Offset(x, r.center.dy));
    await tester.pump();
  }

  group('领位切换', () {
    testWidgets('点侧卡 → 先送它到领位，再用掉它（一步到位）', (WidgetTester tester) async {
      final List<String> used = <String>[];
      await mount(tester, onUse: used.add);
      expect(opacityOf(tester, 'dbl'), 1.0, reason: '初始领位 = dbl');

      await tapCard(tester, 'crit');
      expect(used, <String>['crit'], reason: '点侧卡 = 送位 + 使用');
      expect(opacityOf(tester, 'crit'), 1.0, reason: 'crit 已升为领位（满亮、抬起）');
      expect(opacityOf(tester, 'dbl'), closeTo(.45, 1e-9), reason: 'dbl 退到侧位（压暗 .55）');
      expect(opacityOf(tester, 'shield'), closeTo(.45, 1e-9), reason: 'shield 也退让');
    });

    testWidgets('点领位卡 → 使用 + 回调（seal 音/震在同一条路径上）', (WidgetTester tester) async {
      final List<String> used = <String>[];
      await mount(tester, onUse: used.add);

      await tapCard(tester, 'dbl');
      expect(used, <String>['dbl'], reason: '领位卡 = 使用，语义等同原 onUse(id)');
    });

    testWidgets('侧卡被送到领位后，下一次点它才在领位上', (WidgetTester tester) async {
      final List<String> used = <String>[];
      await mount(tester, onUse: used.add);

      await tapCard(tester, 'crit'); // 送位 + 用掉
      expect(used, <String>['crit']);
      await tester.pumpAndSettle();
      // 现在 crit 在领位：再点它还是它（而不是把它旁边的换上来）
      await tapCard(tester, 'crit');
      expect(used, <String>['crit', 'crit']);
      expect(opacityOf(tester, 'crit'), 1.0);
      expect(opacityOf(tester, 'shield'), closeTo(.45, 1e-9), reason: 'shield 仍未被选中');
    });

    testWidgets('⚠️ 侧卡无货：被送到领位，但不使用、不响 seal', (WidgetTester tester) async {
      final List<String> used = <String>[];
      await mount(
        tester,
        counts: <String, int>{'dbl': 1, 'crit': 0, 'shield': 1},
        onUse: used.add,
      );
      await tapCard(tester, 'crit');
      expect(used, isEmpty, reason: '无货的侧卡只送位（不回调、不响 seal）');
      // 送位成功：它现在是领位（抬起来的那一张）
      expect(tester.widget<ItemCard>(find.byKey(const Key('exec.drawer.crit'))).lead, isTrue);
      // 但「无货」是**另一层语义**：灰照旧 —— 状态条仍是 C.dim，不会假装可用
      expect(opacityOf(tester, 'crit'), kItemDisabledOpacity);
      final Container bar = tester.widget<Container>(
        find.byKey(const Key('exec.drawer.crit.bar')),
      );
      expect((bar.decoration! as BoxDecoration).color, kItemBarOut);
    });

    testWidgets('到边界不绕圈（领位在 0 时再点左边仍是 dbl）', (WidgetTester tester) async {
      final List<String> used = <String>[];
      await mount(tester, onUse: used.add);

      await tester.tapAt(kAt + const Offset(6, 56)); // 最左空白区
      await tester.pumpAndSettle();
      expect(opacityOf(tester, 'dbl'), 1.0, reason: '边界不绕圈');
      expect(used, isEmpty);
    });

    testWidgets('⚠️ 可读性铁律：退让项的正文等效字号 ≥ 13px', (WidgetTester tester) async {
      // 名称字号 15 × 侧卡缩放 .88 = 13.2px（docs/28 §3.4-6）
      expect(kItemNameSize * kItemSideScale, greaterThanOrEqualTo(13));
      expect(kItemNameSize * kItemLeadScale, greaterThanOrEqualTo(13));
      expect(kItemSideScale, greaterThanOrEqualTo(.88));
    });

    testWidgets('退让项的命中矩形仍是布局尺寸（缩放只走 Transform）', (WidgetTester tester) async {
      await mount(tester);
      expect(
        tester.getSize(find.byKey(const Key('exec.drawer.crit'))),
        const Size(kItemCardW, kItemCardH),
      );
      expect(
        tester.getSize(find.byKey(const Key('exec.drawer.dbl'))),
        const Size(kItemCardW, kItemCardH),
      );
    });
  });

  group('三种状态', () {
    testWidgets('可用：状态条暗青、不发光', (WidgetTester tester) async {
      await mount(tester);
      final Container bar = tester.widget<Container>(
        find.byKey(const Key('exec.drawer.crit.bar')),
      );
      final BoxDecoration d = bar.decoration! as BoxDecoration;
      expect(d.color, kItemBarReady);
      expect(d.boxShadow, isNull);
    });

    testWidgets('已生效：状态条实心 C.blue + 发光 + 描边转青', (WidgetTester tester) async {
      await mount(tester, used: <String>{'dbl'});
      final Container bar = tester.widget<Container>(
        find.byKey(const Key('exec.drawer.dbl.bar')),
      );
      final BoxDecoration d = bar.decoration! as BoxDecoration;
      expect(d.color, kItemBarUsed);
      expect(d.boxShadow, isNotNull, reason: '已生效的实心条要发光');
      final Container face = tester.widget<Container>(
        find.byKey(const Key('exec.drawer.dbl.face')),
      );
      expect((face.decoration! as BoxDecoration).border!.top.color, kItemBarUsed);
    });

    testWidgets('无货：灰 + opacity .35，点了不回调', (WidgetTester tester) async {
      final List<String> used = <String>[];
      await mount(
        tester,
        counts: <String, int>{'dbl': 0, 'crit': 1, 'shield': 1},
        onUse: used.add,
      );
      expect(opacityOf(tester, 'dbl'), kItemDisabledOpacity);
      final Container bar = tester.widget<Container>(
        find.byKey(const Key('exec.drawer.dbl.bar')),
      );
      expect((bar.decoration! as BoxDecoration).color, kItemBarOut);
      await tapCard(tester, 'dbl');
      expect(used, isEmpty, reason: '灰掉的不该回调');
    });

    testWidgets('无货的侧卡压暗取更暗的那个（.35 而不是 .45）', (WidgetTester tester) async {
      await mount(
        tester,
        counts: <String, int>{'dbl': 1, 'crit': 0, 'shield': 1},
      );
      expect(opacityOf(tester, 'crit'), kItemDisabledOpacity);
    });

    testWidgets('⚠️ 持有 0 但已生效 → 不灰，且仍可点仍回调', (WidgetTester tester) async {
      final List<String> used = <String>[];
      await mount(
        tester,
        counts: <String, int>{'dbl': 0, 'crit': 1, 'shield': 1},
        used: <String>{'dbl'},
        onUse: used.add,
      );
      expect(opacityOf(tester, 'dbl'), 1.0, reason: '已生效的哪怕持有 0 也不能灰');
      await tapCard(tester, 'dbl');
      expect(used, <String>['dbl'], reason: '已生效的仍可点，回调由上层判');
    });
  });

  group('边界态', () {
    testWidgets('只有 1 件 → 单卡居中、不硬撑（卡宽仍是 86）', (WidgetTester tester) async {
      await mount(tester, ids: <String>['dbl'], counts: <String, int>{'dbl': 1});
      expect(find.byKey(const Key('exec.drawer.crit')), findsNothing);
      final Rect r = tester.getRect(find.byKey(const Key('exec.drawer.dbl')));
      expect(r.width, kItemCardW, reason: '不因为只有一件就把卡撑满');
      expect(r.center.dx, closeTo(kAt.dx + kMid, .01), reason: '单卡居中领位');
    });

    testWidgets('收起时不接点击', (WidgetTester tester) async {
      final List<String> used = <String>[];
      await mount(tester, open: false, onUse: used.add);
      await tapCard(tester, 'dbl');
      await tester.tapAt(kAt + const Offset(kMid, 56));
      await tester.pump();
      expect(used, isEmpty);
    });
  });

  group('吸附与甩动（RailController）', () {
    test('不超半格 → 吸附回原位', () {
      final RailController c = RailController();
      expect(
        c.settleIndex(
          dx: -20,
          velocity: 0,
          stride: kItemStride,
          length: 3,
          startLead: 0,
        ),
        0,
      );
    });

    test('超过半格 → 翻一格（向左拖 = 看右边那一个）', () {
      final RailController c = RailController();
      expect(
        c.settleIndex(
          dx: -60,
          velocity: 0,
          stride: kItemStride,
          length: 3,
          startLead: 0,
        ),
        1,
      );
      expect(
        c.settleIndex(
          dx: 60,
          velocity: 0,
          stride: kItemStride,
          length: 3,
          startLead: 2,
        ),
        1,
      );
    });

    test('速度超阈值 → 只翻一格（不看距离）', () {
      final RailController c = RailController();
      expect(
        c.settleIndex(
          dx: -10,
          velocity: -(kRailFlingVelocity + 1),
          stride: kItemStride,
          length: 3,
          startLead: 0,
        ),
        1,
      );
      expect(
        c.settleIndex(
          dx: 10,
          velocity: kRailFlingVelocity + 1,
          stride: kItemStride,
          length: 3,
          startLead: 2,
        ),
        1,
      );
    });

    test('阈值以下的速度不翻格（只按距离吸附）', () {
      final RailController c = RailController();
      expect(
        c.settleIndex(
          dx: -10,
          velocity: -(kRailFlingVelocity - 1),
          stride: kItemStride,
          length: 3,
          startLead: 0,
        ),
        0,
      );
    });

    test('两端夹住，不越界', () {
      final RailController c = RailController();
      expect(
        c.settleIndex(
          dx: -500,
          velocity: -2000,
          stride: kItemStride,
          length: 3,
          startLead: 2,
        ),
        2,
      );
      expect(
        c.settleIndex(
          dx: 500,
          velocity: 2000,
          stride: kItemStride,
          length: 3,
          startLead: 0,
        ),
        0,
      );
    });

    test('单卡 / 空组：长度 ≤ 1 时原地不动', () {
      final RailController c = RailController();
      expect(
        c.settleIndex(
          dx: -200,
          velocity: -2000,
          stride: kItemStride,
          length: 1,
          startLead: 0,
        ),
        0,
      );
      expect(c.moveTo(1, length: 1), isFalse);
      expect(c.step(1, length: 1), isFalse);
    });

    test('moveTo 返回「是否真的动了」（调用方据此决定要不要响 rung）', () {
      final RailController c = RailController();
      expect(c.moveTo(0, length: 3), isFalse, reason: '原地不动 → 不响');
      expect(c.moveTo(2, length: 3), isTrue);
      expect(c.lead, 2);
      expect(c.moveTo(9, length: 3), isFalse, reason: '夹到 2，还是原地');
    });
  });
}
