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

    testWidgets('记录行与补救单收进「失败卡」背板（t26/TODO-14）', (WidgetTester tester) async {
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
      final double h = MediaQuery.sizeOf(
        tester.element(find.byKey(const Key('fail.card'))),
      ).height;
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
    // 【本轮改形状】回应从「底部竖排堆 2 颗胶囊」换成「横排错位斜切铭牌轨」
    // （docs/23 §5 · 乙 · 铭牌轨）：卡 268×58 横版斜切薄牌，领位左对齐到边
    // 并抬起 8px，让位向右阶梯缩进 14px + 下沉 6px。旧的竖堆盒模型
    // （350×50 / gap 9 / 整体 109 高）随之作废，断言换成新的横排形状。
    testWidgets('横排斜切铭牌：领位左对齐到边、让位向右阶梯缩进', (WidgetTester tester) async {
      await _mount(
        tester,
        const Choices(
          items: <Choice>[Choice('……接。', main: true), Choice('今天算了。')],
        ),
      );
      // 错峰入场（0/60/120ms + 420ms）走完再量
      await tester.pumpAndSettle();

      final Rect box = tester.getRect(find.byKey(const Key('choices')));
      expect(box.left, 20);
      expect(box.right, 370);
      expect(box.bottom, closeTo(810, .5)); // bottom 34
      expect(box.height, 78); // 抬起 8 + 牌高 58 + 最深让位下沉 12

      final Rect lead = tester.getRect(find.byKey(const Key('choices.0')));
      expect(lead.left, 20); // 领位左对齐到边
      expect(lead.width, 268); // 横版薄牌（不是甲的竖版厚卡）
      expect(lead.height, 58);
      expect(lead.top, closeTo(732, .5)); // 810 - 78

      final Rect side = tester.getRect(find.byKey(const Key('choices.1')));
      expect(side.left, 34); // 让位向右缩进 14px
      expect(side.top, lead.top + 14); // 领位抬起 8 + 让位下沉 6

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
      // 先证明这一枪确实打在「收起的回应」上（否则这条测试会悄悄变成空转）：
      // 收起 = 整叠向下 28px 淡出 → 盒子在 760..838，但命中必须照样打穿
      final Rect box = tester.getRect(find.byKey(const Key('choices')));
      expect(box.contains(const Offset(195, 780)), isTrue);
      await tester.tapAt(const Offset(195, 780)); // 正好压在收起的铭牌轨上
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

  group('失败页 · 系统返回键硬出口（main.dart 的 PopScope 挂点）', () {
    // 「永远有补救」不能只押在那两张铭牌上：2026-10-11 的死局恰恰是铭牌
    // 自己把自己拆了（`Choices._confirm` 先锁死、`_onChoice` 被 `_busy` 挡掉），
    // 于是失败页再无出路。返回键是最后一道门 —— 但它挂在 main.dart 的
    // build 里（那里整棵子树包不了 widget 测试），所以这里只钉**挂点形态**：
    // `PopScope` 向 `ModalRoute` 注册 pop entry，**不需要包住任何东西** ——
    // main.dart 里它就是 Stack 里一颗 0×0 的空壳（包住 Scaffold 会让
    // `dart format` 把 600+ 行整棵 build 树重排）。这个挂法若失效，
    // 硬出口会**静默失效**，所以必须有测试看着。
    testWidgets('0×0 的 PopScope 挂在 Stack 里，系统返回键照样被接住', (
      WidgetTester tester,
    ) async {
      int hits = 0;
      await _mount(
        tester,
        PopScope(
          canPop: false, // = 失败页
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (!didPop) hits++;
          },
          child: const SizedBox.shrink(), // 挂点：不占位、不参与命中
        ),
      );

      // 系统返回键在框架里的入口（`SystemChannels.navigation` 的 popRoute）
      final bool handled = await tester.binding.handlePopRoute();
      await tester.pump();

      expect(handled, isTrue); // 框架接住了：没有退到系统去关 App
      expect(hits, 1); // 回调到了 → 失败页那一下就是「今天算了。」
    });

    testWidgets('不在失败页（canPop: true）→ 回调不响，交回系统默认行为', (
      WidgetTester tester,
    ) async {
      int hits = 0;
      await _mount(
        tester,
        PopScope(
          canPop: true,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (!didPop) hits++;
          },
          child: const SizedBox.shrink(),
        ),
      );

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(hits, 0); // 别处照旧：返回键该退桌面就退桌面
    });
  });
}
