import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/data/rarity.dart';
import 'package:system_panel/state/host_state.dart';
import 'package:system_panel/state/quest.dart';
import 'package:system_panel/widgets/plate.dart';

/// 派单板（玻璃板 + 等级骰子 + 指纹 + alt 按钮）。
/// 坐标断言来自运行中原型的实测值（C 级主线第 5 环）。
///
/// ⚠️ 同 lobby_test：`flutter test` 用占位字体（每字形 1em 宽），
/// 凡"宽度由文字撑出来"的盒子在单测里量不准，只断言与文字宽度无关的部分。
const Size kDesign = Size(390, 844);

Future<void> _mount(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(kDesign);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Stack(children: <Widget>[child])),
    ),
  );
  await tester.pump();
}

void main() {
  group('稀有度阶梯 = content.js L14-23', () {
    test('七级颜色与奖励逐个对齐', () {
      expect(Rarity.ranks, <String>['F', 'E', 'D', 'C', 'B', 'A', 'S']);
      expect(Rarity.of('F').color.toARGB32(), 0xFF9AA3B2);
      expect(Rarity.of('C').color.toARGB32(), 0xFFA78BFA);
      expect(Rarity.of('S').color.toARGB32(), 0xFFFF4D5E);
      expect(Rarity.of('C').exp, 50);
      expect(Rarity.of('C').coin, 24);
      expect(Rarity.of('C').i, 3);
      expect(Rarity.of('S').i, 6);
      expect(Rarity.of('S').exp, 200);
    });
  });

  group('委托数据', () {
    test('单号 / 环数 / 时限 / 报酬文案（ui.js + util.js）', () {
      const Quest q = Quest.demo;
      expect(q.serialText, '№ 0041');
      expect(q.kindLabel, '主线 · 第 5 环 / 8');
      expect(q.minutesText, '45 分钟');
      expect(q.rewardText, 'EXP 50 · ◈ 24体+1 力+1');
    });

    test('时限跨小时的说法（fmtMin）', () {
      const Quest base = Quest.demo;
      expect(
        Quest(
          serial: 1,
          kind: 'daily',
          ring: 0,
          ringTotal: 1,
          name: 'x',
          reason: '',
          proof: 'y',
          minutes: 60,
          rank: 'F',
          attrs: <String, int>{},
        ).minutesText,
        '1 小时',
      );
      expect(
        Quest(
          serial: 1,
          kind: 'daily',
          ring: 0,
          ringTotal: 1,
          name: 'x',
          reason: '',
          proof: 'y',
          minutes: 90,
          rank: 'F',
          attrs: <String, int>{},
        ).minutesText,
        '1 小时 30 分',
      );
      expect(base.minutes, 45);
    });
  });

  group('玻璃板', () {
    testWidgets('文案齐全：单号 / 环数 / 标题 / 附言 / 规格 / 按住', (
      WidgetTester tester,
    ) async {
      await _mount(
        tester,
        const Plate(
          quest: Quest.demo,
          host: HostState.demo,
          animateLand: false,
        ),
      );
      expect(find.text('№ 0041'), findsOneWidget);
      expect(find.text('主线 · 第 5 环 / 8'), findsOneWidget);
      expect(find.text('跑完 5 公里'), findsOneWidget);
      expect(find.text('附言'), findsOneWidget);
      expect(find.text('证明'), findsOneWidget);
      expect(find.text('跑步 App 截图'), findsOneWidget);
      expect(find.text('时限'), findsOneWidget);
      expect(find.text('45 分钟'), findsOneWidget);
      expect(find.text('报酬'), findsOneWidget);
      expect(find.text('按住 · 接下'), findsOneWidget);
      expect(find.text('HOLD TO ACCEPT'), findsOneWidget);
      expect(find.text('C'), findsOneWidget); // 骰子上的等级字
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('玻璃板 / 骰子 / 环 / 指纹 / 底缘光落在实测坐标上', (WidgetTester tester) async {
      await _mount(
        tester,
        const Plate(
          quest: Quest.demo,
          host: HostState.demo,
          animateLand: false,
        ),
      );
      expect(
        tester.getRect(find.byKey(const Key('plate'))),
        const Rect.fromLTWH(16, 396, 358, 384),
      );
      expect(
        tester.getRect(find.byKey(const Key('plate.rank'))),
        const Rect.fromLTWH(272, 430, 86, 104),
      );
      expect(
        tester.getRect(find.byKey(const Key('plate.ring'))),
        const Rect.fromLTWH(276, 430, 78, 78),
      );
      expect(
        tester.getRect(find.byKey(const Key('plate.print'))),
        const Rect.fromLTWH(36, 672, 318, 108),
      );
      // .pl-print 是「居中一行」：指纹的 x 由右边文案宽度撑出来，单测里量不准，
      // 只钉住它自己的尺寸与竖直位置（原型实测 top 692）
      final Rect fp = tester.getRect(find.byKey(const Key('plate.fp')));
      expect(fp.width, 62);
      expect(fp.height, 70);
      expect(fp.top, closeTo(691, 1.5));
      // .pl-edge { left:10%; right:10%; bottom:0; height:2 } —— 358 的 10% = 35.8
      final Rect edge = tester.getRect(find.byKey(const Key('plate.edge')));
      expect(edge.left, closeTo(51.8, .1));
      expect(edge.width, closeTo(286.4, .1));
      expect(edge.bottom, closeTo(780, .1));
      expect(edge.height, 2);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('不可见时不占位', (WidgetTester tester) async {
      await _mount(
        tester,
        const Plate(
          quest: Quest.demo,
          host: HostState.demo,
          visible: false,
          animateLand: false,
        ),
      );
      expect(find.byKey(const Key('plate')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('板下的两个按钮', () {
    testWidgets('渲染「宿主 · 」前缀与文案，并在实测坐标', (WidgetTester tester) async {
      await _mount(tester, const PlateAlt(labels: <String>['换一个', '等会儿']));
      expect(find.text('换一个'), findsOneWidget);
      expect(find.text('等会儿'), findsOneWidget);
      expect(find.text('宿主 · '), findsNWidgets(2));
      final Rect row = tester.getRect(find.byType(Row).first);
      expect(row.left, 16);
      expect(row.right, 374);
      expect(row.bottom, closeTo(826, .5)); // bottom:18 + 高 36
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('D4：点「换一个 / 等会儿」回调 onPick(0/1)', (WidgetTester tester) async {
      // 数据源 mock：业务（QuestFlow.retreat / later）在 QuestFlow，装配归 main.dart（t10）。
      // 这里按 docs/18 §1.3-D4 的接口契约用闭包记录回调，钉住索引语义：
      // 0 = retreat（换一个：降一档 / F 级换同档他单 / 当日 3 次戴「口头巨人」）
      // 1 = later（等会儿：单子留在队列、回大厅）
      final List<int> picked = <int>[];
      await _mount(
        tester,
        PlateAlt(
          labels: const <String>['换一个', '等会儿'],
          onPick: picked.add,
        ),
      );
      await tester.tap(find.byKey(const Key('plate.alt.0')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('plate.alt.1')));
      await tester.pump();
      expect(picked, <int>[0, 1]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('D4：没接线（onPick 缺省）时按下只有 :active 变色、不抛异常', (
      WidgetTester tester,
    ) async {
      await _mount(tester, const PlateAlt(labels: <String>['换一个', '等会儿']));
      await tester.tap(find.byKey(const Key('plate.alt.0')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('D4：收起时断掉命中（点不到）', (WidgetTester tester) async {
      int? picked;
      await _mount(
        tester,
        PlateAlt(
          labels: const <String>['换一个', '等会儿'],
          visible: false,
          onPick: (int i) => picked = i,
        ),
      );
      // IgnorePointer 生效时 tap 落空（warnIfMissed 关掉警告，断言确实没触发）
      await tester.tap(find.byKey(const Key('plate.alt.0')), warnIfMissed: false);
      await tester.pump();
      expect(picked, isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
  // ── 数据契约 ──────────────────────────────────────────────
  // 演示档的每个字段都必须与原型 `Store.veteran()` 的 `Store.head()` 一致。
  // 改这里的数之前，先在原型里跑一次 `Store.veteran(); console.log(Store.head())`。
  // 踩过：serial 我按印象写了 80（实为 41）、reason 漏了「46 秒」——
  // 这种小字差异在区域均值里几乎看不出来，是换成干净存档后才核对出来的。
  group('演示档数据契约', () {
    test('与 Store.veteran() 的 head 任务逐字段一致', () {
      const Quest q = Quest.demo;
      expect(q.serial, 41);
      expect(q.kind, 'main');
      expect(q.ring, 4);
      expect(q.name, '跑完 5 公里');
      expect(q.reason, '上一环你用了 38 分 46 秒。这一环，我加了点码。');
      expect(q.proof, '跑步 App 截图');
      expect(q.minutes, 45);
      expect(q.rank, 'C');
      expect(q.attrs, <String, int>{'体': 1, '力': 1});
    });
  });
}
