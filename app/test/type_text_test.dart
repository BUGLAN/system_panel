import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/widgets/type_text.dart';

/// 打字机（`ui.js` L77-112 `Line.say`）。
///
/// 设备上抓不到打字段 —— adb 一个来回就 0.6s，而整句 990ms 就打完了。
/// 所以把关放在这里：**逐字的时间轴**可以精确断言。
Future<void> _mount(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

/// 从渲染树里取出每个字当前的 alpha
List<double> _alphas(WidgetTester tester) {
  final Text t = tester.widget<Text>(find.byType(Text).first);
  final TextSpan span = t.textSpan! as TextSpan;
  return <double>[
    for (final InlineSpan s in span.children!)
      ((s as TextSpan).style!.color!.a * 255).round() / 255,
  ];
}

void main() {
  group('时间轴', () {
    testWidgets('第一帧一个字都没显形', (WidgetTester tester) async {
      await _mount(tester, const TypeText(text: '我手里有 4 单。'));
      expect(_alphas(tester).every((double a) => a == 0), isTrue);
    });

    testWidgets('每字 34ms，标点额外停顿', (WidgetTester tester) async {
      // '我手里有 4 单。' —— 8 个字，最后一个是句号
      await _mount(tester, const TypeText(text: '我手里有 4 单。'));
      // 34ms 后：第 1 个字开始淡入（120ms 内到 1），第 2 个还没动
      await tester.pump(const Duration(milliseconds: 34));
      final List<double> a1 = _alphas(tester);
      expect(a1[0], greaterThan(0));
      expect(a1[1], 0);
      // 再走 120ms：第 1 个字完全显形，第 2 个开始
      await tester.pump(const Duration(milliseconds: 120));
      final List<double> a2 = _alphas(tester);
      expect(a2[0], 1);
      expect(a2[1], greaterThan(0));
    });

    testWidgets('句号多停 240ms', (WidgetTester tester) async {
      // '甲。乙'：甲后停 34+240=274ms
      await _mount(tester, const TypeText(text: '甲。乙'));
      await tester.pump(const Duration(milliseconds: 150));
      List<double> a = _alphas(tester);
      expect(a[0], 1); // 甲显完
      expect(a[2], 0); // 乙还没动
      await tester.pump(const Duration(milliseconds: 200)); // 累计 350 > 274
      a = _alphas(tester);
      expect(a[2], greaterThan(0));
    });

    testWidgets('soft 台词用 42ms/字', (WidgetTester tester) async {
      await _mount(tester, const TypeText(text: '甲乙丙', soft: true));
      await tester.pump(const Duration(milliseconds: 40));
      expect(_alphas(tester)[1], 0); // 40 < 42，第 2 个字还没动
      await tester.pump(const Duration(milliseconds: 10));
      expect(_alphas(tester)[1], greaterThan(0));
    });

    testWidgets('打完回调一次', (WidgetTester tester) async {
      int done = 0;
      await _mount(tester, TypeText(text: '甲。乙', onDone: () => done++));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(done, 1);
    });
  });

  group('点一下跳过', () {
    testWidgets('skipToken 一变，剩下的字立刻开始显形', (WidgetTester tester) async {
      await _mount(tester, const TypeText(text: '甲乙丙丁戊己', skipToken: 0));
      await tester.pump(const Duration(milliseconds: 40));
      expect(_alphas(tester).last, 0);
      await _mount(tester, const TypeText(text: '甲乙丙丁戊己', skipToken: 1));
      await tester.pump();
      // 跳过 = 所有字同时开始那 120ms 淡入
      // （原型 `spans.forEach(s => s.classList.add('on'))`）——
      // 最后一刻冒出来的那几个字此刻还在淡入中途，这是对的
      expect(_alphas(tester).last, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 130));
      expect(_alphas(tester).every((double a) => a == 1), isTrue);
    });
  });

  group('富文本标记', () {
    testWidgets('[[…]] 之间是高亮片段（青色 + 650 字重）', (WidgetTester tester) async {
      await _mount(tester, const TypeText(text: '你想变成[[什么样]]？'));
      await tester.pumpAndSettle();
      final Text t = tester.widget<Text>(find.byType(Text).first);
      final List<InlineSpan> kids = (t.textSpan! as TextSpan).children!;
      // '你想变成' 4 个字普通，'什么样' 3 个字高亮，'？' 普通
      expect(kids.length, 8);
      final TextSpan plain = kids[1] as TextSpan;
      final TextSpan em = kids[5] as TextSpan;
      expect(plain.style!.color!.b, greaterThan(.9)); // 冰白
      expect(em.style!.color!.b, 1); // 青
      expect(em.style!.fontVariations!.first.value, 650);
      expect(em.style!.shadows, isNotEmpty);
    });

    testWidgets('soft 台词里高亮片段改成灰白、无辉光', (WidgetTester tester) async {
      await _mount(tester, const TypeText(text: '[[甲]]乙', soft: true));
      await tester.pumpAndSettle();
      final Text t = tester.widget<Text>(find.byType(Text).first);
      final TextSpan em = (t.textSpan! as TextSpan).children!.first as TextSpan;
      expect(em.style!.shadows, isNull);
      expect(em.style!.color!.r, closeTo(0xD5 / 255, .01));
    });
  });
}
