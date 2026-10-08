import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/state/quest.dart';
import 'package:system_panel/state/result.dart';
import 'package:system_panel/widgets/result_panel.dart';

/// 结算面板（稀有度大字 / CLEAR 抬头 / 结算卡 / 保存战报）。
/// 坐标断言来自运行中原型的实测值。
///
/// ⚠️ 同其他页：`flutter test` 用占位字体（每字形 1em 宽），
/// 凡"宽度/高度由文字撑出来"的盒子在单测里量不准，只断言与文字无关的部分。
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
  group('结算结果数据', () {
    test('结算后经验 / 暴击率百分比', () {
      const QuestResult r = QuestResult.demo;
      expect(r.afterExp, 214 + 50);
      expect(r.chancePct, 12);
      expect(r.rarity.rank, 'C');
    });

    test('T2 新字段：demo 全走默认（不升级 / 无称号 / 队列未空 / 未推进主线）', () {
      const QuestResult r = QuestResult.demo;
      expect(r.ups, isEmpty);
      expect(r.titles, isEmpty);
      expect(r.ringClear, -1);
      expect(r.finale, isFalse);
      expect(r.redeemed, isFalse);
      expect(r.empty, isFalse);
      expect(r.tooFast, isFalse);
      expect(r.lvAfter, 7);
      expect(r.finalNeed, 340);
      expect(r.expAfterSettle, 264);
    });

    test('T2 升级口径：LV 读数换新档、经验条用新分母与余额', () {
      const QuestResult r = QuestResult(
        quest: Quest.demo,
        beforeLv: 1,
        beforeExp: 17,
        beforeNeed: 18,
        exp: 40,
        coin: 20,
        attrs: <String, int>{'体': 1},
        streak: 2,
        streakUp: true,
        crit: true,
        dbl: true,
        photos: 0,
        chance: .12,
        ups: <int>[2, 3],
        afterLv: 3,
        afterNeed: 30,
      );
      expect(r.lvAfter, 3);
      expect(r.finalNeed, 30);
      expect(r.expAfterSettle, 40, reason: '升级过 = 溢出后的余额');
    });
  });

  group('结算面板', () {
    testWidgets('文案齐全', (WidgetTester tester) async {
      await _mount(
        tester,
        const ResultPanel(result: QuestResult.demo, animate: false),
      );
      expect(find.text('保存战报'), findsOneWidget);
      expect(find.text('CLEAR · 主线第 5 环'), findsOneWidget);
      expect(find.text('跑完 5 公里'), findsOneWidget);
      expect(find.text('EXP'), findsOneWidget);
      expect(find.textContaining('+50'), findsWidgets);
      expect(find.textContaining('LV'), findsWidgets);
      expect(find.textContaining('7'), findsWidgets);
      expect(find.text('264 / 340'), findsOneWidget);
      expect(find.textContaining('+24'), findsWidgets);
      expect(find.textContaining('体质'), findsWidgets);
      expect(find.textContaining('力量'), findsWidgets);
      expect(find.textContaining('连击'), findsWidgets);
      expect(find.text('本单 0 份证据 · 暴击率只有 12%'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('结算卡 / 大字 / 经验条 / 保存按钮落在实测坐标上', (WidgetTester tester) async {
      await _mount(
        tester,
        const ResultPanel(result: QuestResult.demo, animate: false),
      );
      // .rs-stack { left:20; right:20 } → 350 宽
      final Rect stack = tester.getRect(find.byKey(const Key('result.stack')));
      expect(stack.left, 20);
      expect(stack.right, 370);
      // .rs-glyph 136×136，居中 → x=127
      final Rect glyph = tester.getRect(find.byKey(const Key('result.glyph')));
      expect(glyph.size, const Size(136, 136));
      expect(glyph.left, closeTo(127, .5));
      // .rs-card 撑满 350
      final Rect card = tester.getRect(find.byKey(const Key('result.card')));
      expect(card.left, 20);
      expect(card.right, 370);
      // .rs-bar 在卡内 padding 18 → x=38 宽 314
      final Rect bar = tester.getRect(find.byKey(const Key('result.bar')));
      expect(bar.left, 38);
      expect(bar.width, 314);
      expect(bar.height, 6);
      // .rs-save { right:18; top:86; height:34 }
      final Rect save = tester.getRect(find.byKey(const Key('result.save')));
      expect(save.right, closeTo(372, .5));
      expect(save.top, 86);
      expect(save.height, 34);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('经验条按 264/340 铺开（漏 heightFactor 会变 0 高）', (
      WidgetTester tester,
    ) async {
      await _mount(
        tester,
        const ResultPanel(result: QuestResult.demo, animate: false),
      );
      final Rect bar = tester.getRect(find.byKey(const Key('result.bar')));
      final Rect fill = tester.getRect(
        find.byKey(const Key('result.bar.fill')),
      );
      expect(fill.height, 6);
      expect(fill.left, 38);
      expect(fill.width / bar.width, closeTo(264 / 340, .01));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('暴击 / 双倍时才盖印章', (WidgetTester tester) async {
      await _mount(
        tester,
        const ResultPanel(result: QuestResult.demo, animate: false),
      );
      expect(find.text('CRIT ×2'), findsNothing);
      expect(find.text('双倍卡 ×2'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('不可见时不占位', (WidgetTester tester) async {
      await _mount(
        tester,
        const ResultPanel(
          result: QuestResult.demo,
          visible: false,
          animate: false,
        ),
      );
      expect(find.byKey(const Key('result.stack')), findsNothing);
    });

    testWidgets('T2：演出播完回调 onDone（结算页的退出选项靠它弹出）', (
      WidgetTester tester,
    ) async {
      int done = 0;
      await _mount(
        tester,
        ResultPanel(
          result: QuestResult.demo,
          onDone: () => done++,
        ),
      );
      // 演出全程 ~3.7s；播完 + 过一帧（postFrameCallback）后应恰好回调一次
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(done, 1);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(done, 1, reason: '不重复回调');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('T2：animate:false 落终态也要回调 onDone（比对模式不哑火）', (
      WidgetTester tester,
    ) async {
      int done = 0;
      await _mount(
        tester,
        ResultPanel(
          result: QuestResult.demo,
          animate: false,
          onDone: () => done++,
        ),
      );
      await tester.pump();
      expect(done, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('T2：升级过的结算显示新等级与新分母（LV3 · 40/30）', (
      WidgetTester tester,
    ) async {
      await _mount(
        tester,
        const ResultPanel(
          result: QuestResult(
            quest: Quest.demo,
            beforeLv: 1,
            beforeExp: 17,
            beforeNeed: 18,
            exp: 40,
            coin: 20,
            attrs: <String, int>{'体': 1},
            streak: 2,
            streakUp: true,
            crit: false,
            dbl: false,
            photos: 0,
            chance: .12,
            ups: <int>[2, 3],
            afterLv: 3,
            afterNeed: 30,
            endExp: 40,
          ),
          animate: false,
        ),
      );
      expect(find.text('40 / 30'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
