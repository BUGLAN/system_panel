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
        const FailLayer(
          recordedAt: '20:02',
          remedy: Remedy.demo,
          animate: false,
        ),
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
          animate: false,
          recordedAt: '21:30',
          timeout: true,
          remedy: Remedy.demo,
        ),
      );
      expect(find.textContaining('超时 · 已记录'), findsWidgets);
      expect(find.textContaining('认输'), findsNothing);
    });

    testWidgets('记录行与补救单收进「失败卡」背板（t26/TODO-14）', (
      WidgetTester tester,
    ) async {
      await _mount(
        tester,
        const FailLayer(
          recordedAt: '20:02',
          remedy: Remedy.demo,
          animate: false,
        ),
      );
      // 失败卡：left/right 20 · bottom 182（回应按钮上方）· ≤62% 屏高钳制
      final Rect card = tester.getRect(find.byKey(const Key('fail.card')));
      expect(card.left, 20);
      expect(card.right, 370);
      expect(card.bottom, closeTo(662, .5)); // 844 - 182
      final ConstrainedBox cb = tester.widget<ConstrainedBox>(
        find
            .ancestor(
              of: find.byKey(const Key('fail.card')),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      // 62% 屏高钳制（h 与实现同源：测试里 setSurfaceSize 不改 view 尺寸，
      // MediaQuery 还是 800×600，所以不能写死 844×.62）
      final double h =
          MediaQuery.sizeOf(tester.element(find.byKey(const Key('fail.card'))))
              .height;
      expect(cb.constraints.maxHeight, closeTo(h * .62, .5));
      // 背板 = rgba(2,6,14,.78) 圆角 12 + 1px line2 描边（与结算卡同款语言）
      // —— 背板装饰就挂在 fail.card 这个 DecoratedBox 上
      final DecoratedBox board = tester.widget<DecoratedBox>(
        find.byKey(const Key('fail.card')),
      );
      final BoxDecoration d = board.decoration as BoxDecoration;
      expect(d.color, const Color(0xC702060E));
      expect(d.border!.top.width, 1);
      expect(d.borderRadius, BorderRadius.circular(12));
      // 记录行在背板上（不再悬在 top:84 压头发），青色抬头
      final Rect rec = tester.getRect(find.byKey(const Key('fail.rec')));
      expect(rec.top, greaterThan(card.top));
      expect(rec.left, greaterThan(card.left));
      // 补救单也在卡内，不越过背板
      final Rect remedy = tester.getRect(find.byKey(const Key('fail.remedy')));
      expect(remedy.left, greaterThan(card.left));
      expect(remedy.right, lessThan(card.right));
      expect(remedy.bottom, lessThanOrEqualTo(card.bottom + .5));
      // 「不被角色遮挡」的最后保障：背板 78% 不透明（α≈199/255）
      expect(d.color!.a, greaterThan(.75));
    });

    testWidgets('没有补救单时只有记录行', (WidgetTester tester) async {
      await _mount(
        tester,
        const FailLayer(recordedAt: '20:02', animate: false),
      );
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
