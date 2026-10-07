import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/widgets/choices.dart';
import 'package:system_panel/widgets/fail_layer.dart';

/// 失败 / 补救（记录行 / 补救单 / 回应按钮）。
/// 坐标断言来自运行中原型的实测值。
///
/// ⚠️ 同其他页：`flutter test` 用占位字体（每字形 1em 宽），
/// 凡"宽度/高度由文字撑出来"的盒子在单测里量不准。
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
  group('补救单', () {
    test('时限文案（fmtMin）', () {
      expect(Remedy.demo.minutesText, '35 分钟');
      expect(
        const Remedy(
          name: 'x',
          minutes: 90,
          deadline: '明天 20:02',
          rank: 'D',
        ).minutesText,
        '1 小时 30 分',
      );
      expect(
        const Remedy(
          name: 'x',
          minutes: 60,
          deadline: '明天 20:02',
          rank: 'D',
        ).minutesText,
        '1 小时',
      );
    });
  });

  group('失败层', () {
    testWidgets('认输记录 + 补救单文案齐全', (WidgetTester tester) async {
      await _mount(
        tester,
        const FailLayer(recordedAt: '20:02', remedy: Remedy.demo),
      );
      expect(find.textContaining('认输 · 已记录'), findsWidgets);
      expect(find.textContaining('20:02'), findsWidgets);
      expect(find.text('补救 · REMEDY'), findsOneWidget);
      expect(find.textContaining('跑完 8 公里，跑后拉伸 10 分钟'), findsWidgets);
      expect(find.textContaining('做到了，这一笔划掉'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('超时态把「认输」换成「超时」', (WidgetTester tester) async {
      await _mount(
        tester,
        const FailLayer(
          recordedAt: '21:30',
          timeout: true,
          remedy: Remedy.demo,
        ),
      );
      expect(find.textContaining('超时 · 已记录'), findsWidgets);
      expect(find.textContaining('认输'), findsNothing);
    });

    testWidgets('记录行与补救单落在实测坐标上', (WidgetTester tester) async {
      await _mount(
        tester,
        const FailLayer(recordedAt: '20:02', remedy: Remedy.demo),
      );
      final Rect rec = tester.getRect(find.byKey(const Key('fail.rec')));
      expect(rec.left, 0);
      expect(rec.right, 390);
      expect(rec.top, 84);
      final Rect remedy = tester.getRect(find.byKey(const Key('fail.remedy')));
      expect(remedy.left, 24);
      expect(remedy.right, 366);
      expect(remedy.bottom, closeTo(666, .5)); // bottom 178
    });

    testWidgets('没有补救单时只有记录行', (WidgetTester tester) async {
      await _mount(tester, const FailLayer(recordedAt: '20:02'));
      expect(find.byKey(const Key('fail.rec')), findsOneWidget);
      expect(find.byKey(const Key('fail.remedy')), findsNothing);
    });

    testWidgets('不可见时不占位', (WidgetTester tester) async {
      await _mount(
        tester,
        const FailLayer(
          recordedAt: '20:02',
          remedy: Remedy.demo,
          visible: false,
        ),
      );
      expect(find.byKey(const Key('fail.rec')), findsNothing);
    });
  });

  group('回应按钮', () {
    testWidgets('两颗各 50 高、右缘 370、整体底 810', (WidgetTester tester) async {
      await _mount(
        tester,
        const Choices(
          items: <Choice>[Choice('……接。', main: true), Choice('今天算了。')],
        ),
      );
      final Rect box = tester.getRect(find.byKey(const Key('choices')));
      expect(box.left, 20);
      expect(box.right, 370);
      expect(box.bottom, closeTo(810, .5)); // bottom 34
      expect(box.height, 109); // 50 + gap 9 + 50
      for (final String k in <String>['choices.0', 'choices.1']) {
        final Rect r = tester.getRect(find.byKey(Key(k)));
        expect(r.left, 20);
        expect(r.right, 370);
        expect(r.height, 50);
      }
      expect(find.text('宿主'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('收起来时不偷点击（隐形按钮会吃掉下面那颗指纹）', (WidgetTester tester) async {
      int hits = 0;
      await _mount(
        tester,
        Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => hits++,
                child: const SizedBox.expand(),
              ),
            ),
            const Choices(
              items: <Choice>[Choice('……接。', main: true)],
              visible: false,
            ),
          ],
        ),
      );
      await tester.tapAt(const Offset(195, 780)); // 正好压在收起的回应按钮上
      await tester.pump();
      expect(hits, 1);
    });
  });

  group('认输滤镜', () {
    test('saturate(.2) brightness(.55) 的矩阵第一行', () {
      // 0.213+0.787*0.2 = 0.3704，再乘 0.55
      expect(kFailColorMatrix[0], closeTo(0.20372, 1e-5));
      expect(kFailColorMatrix[1], closeTo(0.3146, 1e-5));
      expect(kFailColorMatrix[6], closeTo(0.4246, 1e-5));
    });
  });
}
