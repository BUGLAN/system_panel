import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/widgets/fx_layer.dart';

/// FX 层：亮帧（`#flash`）与震屏（`#shake`）。
///
/// ⚠️ 这两件都是**瞬态**（亮帧 180~280ms、震屏 240ms），不适合做区域均值比对
/// —— 实机抓拍必然混进同时段别的动画。所以这里钉的是**参数**：
/// 颜色、峰值、screen 合成、reduced-motion 折半，与 `js/fx.js` L47-61 逐条对齐。
void main() {
  group('亮帧', () {
    testWidgets('峰值 0 时不画任何东西', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const FlashLayer(alpha: 0)));
      expect(_flashPaint(tester), isNull);
    });

    testWidgets('白 16% —— 与 docs/08 的「亮帧」一致', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const FlashLayer(alpha: .16)));
      final Color c = _flashPaint(tester)!.color;
      expect(c.a, closeTo(41 / 255, .01)); // .16 × 255
      expect(c.r, 1);
      expect(c.g, 1);
      expect(c.b, 1);
    });

    testWidgets('颜色可以按事件换（钤印是 #bff6ff .24）', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(const FlashLayer(alpha: .24, color: Color(0xFFBFF6FF))),
      );
      final Color c = _flashPaint(tester)!.color;
      expect(c.a, closeTo(61 / 255, .01)); // .24 × 255
      expect(c.r, closeTo(0xBF / 255, .01));
      expect(c.g, closeTo(0xF6 / 255, .01));
      expect(c.b, 1);
    });

    testWidgets('reduced-motion 下强度砍半（fx.js L48）', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(const FlashLayer(alpha: .16, reduceMotion: true)),
      );
      expect(_flashPaint(tester)!.color.a, closeTo(20 / 255, .01)); // .08 × 255
    });
  });

  group('震屏', () {
    testWidgets('不动的时候偏移是 0', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ShakeLayer(child: SizedBox(key: Key('inner'), width: 10)),
        ),
      );
      expect(_offsetOf(tester), Offset.zero);
    });

    testWidgets('token 一变就抖起来，抖完回到 0', (WidgetTester tester) async {
      Widget build(int token) => MaterialApp(
        home: ShakeLayer(token: token, child: const SizedBox(width: 10)),
      );
      await tester.pumpWidget(build(0));
      await tester.pumpWidget(build(1));
      await tester.pump(const Duration(milliseconds: 40));
      expect(_offsetOf(tester), isNot(Offset.zero));
      // 抖完必须精确归位（原型 `s.style.transform = ''`）
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(_offsetOf(tester), Offset.zero);
    });

    testWidgets('reduced-motion 下原型直接不抖（fx.js L53）', (
      WidgetTester tester,
    ) async {
      Widget build(int token) => MaterialApp(
        home: ShakeLayer(
          token: token,
          reduceMotion: true,
          child: const SizedBox(width: 10),
        ),
      );
      await tester.pumpWidget(build(0));
      await tester.pumpWidget(build(1));
      await tester.pump(const Duration(milliseconds: 40));
      expect(_offsetOf(tester), Offset.zero);
    });
  });
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Stack(children: <Widget>[child])),
);

/// 只认 FX 层自己画的那张 —— 框架内部也会插 `CustomPaint`
FlashPainter? _flashPaint(WidgetTester tester) {
  final Finder f = find.descendant(
    of: find.byType(FlashLayer),
    matching: find.byType(CustomPaint),
  );
  if (f.evaluate().isEmpty) return null;
  return tester.widget<CustomPaint>(f.first).painter! as FlashPainter;
}

/// 取出震屏偏移。
///
/// ⚠️ **不抖的时候 `ShakeLayer` 根本不套 `Transform`** —— 这不是省事，是必须：
/// 这层包住整个 App（含 Live2D 平台视图），而平台视图**无法应用任意变换**，
/// 祖先链上只要有一个 `Transform`，合成器就干脆不合成它
/// （症状：模型加载成功、渲染循环在跑、视图也在层级里，屏幕上却什么都没有）。
/// 所以"没有 Transform"就等于偏移 0。
Offset _offsetOf(WidgetTester tester) {
  final Finder f = find.descendant(
    of: find.byType(ShakeLayer),
    matching: find.byType(Transform),
  );
  if (f.evaluate().isEmpty) return Offset.zero;
  final Transform t = tester.widget<Transform>(f.first);
  return Offset(t.transform[12], t.transform[13]);
}
