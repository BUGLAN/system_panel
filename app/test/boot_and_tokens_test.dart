import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/data/content.dart';
import 'package:system_panel/design/tokens.dart';
import 'package:system_panel/screens/boot_screen.dart';
import 'package:system_panel/widgets/bg_layer.dart';

void main() {
  group('视觉令牌 = 原型 app.css 的 :root', () {
    test('基底与主色逐个对齐', () {
      expect(C.voidBg.toARGB32(), 0xFF03060E); // --void
      expect(C.abyss.toARGB32(), 0xFF060F20); // --abyss
      expect(C.navy.toARGB32(), 0xFF0B1A36); // --navy
      expect(C.deep.toARGB32(), 0xFF021022); // --deep
      expect(C.blue.toARGB32(), 0xFF38E1FF); // --blue
      expect(C.blue2.toARGB32(), 0xFF1F8BFF); // --blue2
      expect(C.ice.toARGB32(), 0xFFE9FBFF); // --ice
      expect(C.mist.toARGB32(), 0xFF8FA6C4); // --mist
      expect(C.dim.toARGB32(), 0xFF4B5E7C); // --dim
      expect(C.line.toARGB32(), 0x4238E1FF); // rgba(56,225,255,.26)
      expect(C.line2.toARGB32(), 0x1F38E1FF); // rgba(56,225,255,.12)
    });

    test('稀有度色谱对齐', () {
      expect(C.rF.toARGB32(), 0xFF9AA3B2);
      expect(C.rE.toARGB32(), 0xFF4ADE80);
      expect(C.rD.toARGB32(), 0xFF38BDF8);
      expect(C.rC.toARGB32(), 0xFFA78BFA);
      expect(C.rB.toARGB32(), 0xFFFBBF24);
      expect(C.rA.toARGB32(), 0xFFFB923C);
      expect(C.rS.toARGB32(), 0xFFFF4D5E);
    });

    test('字体族名与 @font-face 一致', () {
      expect(F.cn, 'FangYuan');
      expect(F.hd, 'ShuHei');
      expect(F.num, 'Tektur');
      expect(F.mono, 'KodeMono');
    });

    test('可变字体必须带 fontVariations，否则字重不生效', () {
      final TextStyle s = fs(family: F.cn, size: 17, wght: 500);
      expect(s.fontFamily, 'FangYuan');
      expect(s.fontVariations, contains(const FontVariation('wght', 500)));
      expect(s.fontWeight, isNull); // 不许靠 fontWeight
    });

    test('背景大字字号按 setWord 的公式（拉丁 / 中文两套）', () {
      expect(WordSpec.fontSize('SYSTEM'), 93); // min(120, 560/6) = 93.33 → 93
      expect(
        WordSpec.fontSize('跑完半马', latin: false),
        90,
      ); // min(175, 360/4) = 90
      expect(WordSpec.isLatin('SYSTEM'), isTrue);
      expect(WordSpec.isLatin('跑完半马'), isFalse);
      expect(WordSpec.scale, 0.910);
    });
  });

  group('开机屏', () {
    testWidgets('品牌字 / 副题 / TIPS 前缀都在，且走完序列后出现唤醒提示', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BootScreen())),
      );
      await tester.pump();

      expect(find.text('SYS//BOOT · v2'), findsOneWidget);
      expect(find.text('宿 主 · 系 统'), findsOneWidget);
      expect(find.textContaining('TIPS · '), findsOneWidget);

      // 开机序列：日志 + 进度 + ready
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('触碰屏幕 · 唤醒系统'), findsOneWidget);
      expect(find.textContaining('唤醒序列就绪'), findsOneWidget);
      expect(find.textContaining('校准良心'), findsOneWidget);

      // 卸载以取消定时器（时钟 / TIPS / 呼吸）
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('日志最多留 5 行：最早的被挤掉', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BootScreen())),
      );
      await tester.pump(const Duration(seconds: 4));

      // 一共发了 7 条，只留最近 5 条 —— 前两条必须已经滚出去
      expect(find.textContaining('链路建立'), findsNothing);
      expect(find.textContaining('字形载入'), findsNothing);
      // 留下的最后一条
      expect(find.textContaining('唤醒序列就绪'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('进度条真的有高度（FractionallySizedBox 漏 heightFactor 会变 0 高）', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BootScreen())),
      );
      await tester.pump(const Duration(seconds: 4));
      final Rect fill = tester.getRect(find.byKey(const Key('boot.bar.fill')));
      expect(fill.height, 2);
      expect(fill.width, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('宿主名会填进「链接宿主档案」那一行', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: BootScreen(host: '林深 · LV7')),
        ),
      );
      await tester.pump(const Duration(seconds: 4));
      expect(find.textContaining('林深 · LV7'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('点一下才消失（不是自动跳走）', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BootScreen())),
      );
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('SYS//BOOT · v2'), findsOneWidget);

      await tester.tap(find.byType(BootScreen));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      final AnimatedOpacity fade = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(BootScreen),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(fade.opacity, 0);
      await tester.pumpWidget(const SizedBox());
    });

    // ── 门禁（docs/22 §R5 裁决 D-m）：点任意处 = 触发唤醒这一拍 ──

    testWidgets('门禁①：日志没滚完时点一下 → 先快进铺完最终 5 行，再触发一次唤醒', (
      WidgetTester tester,
    ) async {
      int wakes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BootScreen(host: '林深 · LV7', onWake: () => wakes++),
          ),
        ),
      );
      // t=300ms：脚本才走到第二拍，日志还有 5 行没铺
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('› '), findsNWidgets(2));
      expect(find.textContaining('唤醒序列就绪'), findsNothing);
      expect(wakes, 0, reason: '开机屏不会自己走，门禁一直等她被点');

      await tester.tap(find.byType(BootScreen));
      await tester.pump(); // 快进那一帧：剩下的 5 行 + 进度条 100% 一次到位

      // 终态 5 行（不是中途状态）：最早两条照样被挤掉
      expect(find.textContaining('› '), findsNWidgets(5));
      expect(find.textContaining('› 就绪'), findsOneWidget);
      expect(find.textContaining('挂载人格模块 …… 毒舌'), findsOneWidget);
      expect(find.textContaining('校准良心'), findsOneWidget);
      expect(find.textContaining('林深 · LV7'), findsOneWidget);
      expect(find.textContaining('唤醒序列就绪'), findsOneWidget);
      expect(find.textContaining('链路建立'), findsNothing);
      expect(find.textContaining('字形载入'), findsNothing);
      expect(wakes, 0, reason: '快进是「先铺完」，唤醒要等行入场走完这一拍');

      await tester.pump(const Duration(milliseconds: 300)); // 入场走完
      expect(wakes, 1, reason: 'onWake 恰好一次');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('门禁②：演出起来后再点不重复触发（快进节拍里也不许插队）', (WidgetTester tester) async {
      int wakes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BootScreen(onWake: () => wakes++)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byType(BootScreen)); // 第一次点击：快进 + 唤醒
      await tester.pump();
      // 快进的 300ms 节拍里再点一下：门禁闩已落下 → 进不来
      await tester.tap(find.byType(BootScreen), warnIfMissed: false);
      await tester.pump();
      expect(wakes, 0);

      await tester.pump(const Duration(milliseconds: 400));
      expect(wakes, 1);

      // 演出已经开始：画面淡出 + 不收点击，再点两下也不动
      final AnimatedOpacity fade = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(BootScreen),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(fade.opacity, 0);
      expect(
        tester
            .widget<IgnorePointer>(
              find.descendant(
                of: find.byType(BootScreen),
                matching: find.byType(IgnorePointer),
              ),
            )
            .ignoring,
        isTrue,
      );
      await tester.tap(find.byType(BootScreen), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(BootScreen), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(wakes, 1, reason: 'onWake 全程恰好一次');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('门禁③：日志已滚完时点一下 → 立刻唤醒（不多等一拍）', (WidgetTester tester) async {
      int wakes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BootScreen(onWake: () => wakes++)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 2000)); // 1780ms 就滚完了
      expect(find.textContaining('唤醒序列就绪'), findsOneWidget);
      expect(wakes, 0);

      await tester.tap(find.byType(BootScreen));
      expect(wakes, 1, reason: '按下即触发，不等快进节拍');

      await tester.pump();
      final AnimatedOpacity fade = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(BootScreen),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(fade.opacity, 0);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('进度条与「唤醒序列就绪」落在同一拍（按真机 16ms 逐帧读）', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BootScreen())),
      );
      final double track = tester
          .getRect(find.byKey(const Key('boot.bar')))
          .width;
      double ratioWhenLastLine = -1;
      for (int i = 0; i < 140; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (find.textContaining('唤醒序列就绪').evaluate().isNotEmpty) {
          ratioWhenLastLine =
              tester.getRect(find.byKey(const Key('boot.bar.fill'))).width /
              track;
          break;
        }
      }
      expect(
        ratioWhenLastLine,
        greaterThan(.98),
        reason: '最后一行落下的那一拍，条已经走满（同一个 _kBarTravel）',
      );
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('天幕', () {
    testWidgets('能渲染，且大字用 Tektur', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BgLayer())),
      );
      await tester.pump();

      // 大字画两层：渐变填充 + 描边（app.css L60-62）
      final Finder word = find.text('SYSTEM');
      expect(word, findsNWidgets(2));

      final Text fill = tester.widget<Text>(word.first);
      expect(fill.style?.fontFamily, 'Tektur');
      expect(fill.style?.fontSize, 93);
      expect(
        fill.style?.fontVariations,
        contains(const FontVariation('wdth', 75)),
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('文案真源', () {
    test('开机日志与 TIPS 条数与原型一致', () {
      expect(LINES.bootLog.length, 5);
      expect(LINES.tips.length, 6);
      expect(LINES.bootLog[3], '链接宿主档案 …… {host}');
    });
  });
}
