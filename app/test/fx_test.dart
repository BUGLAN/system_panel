import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/chat/chat_history.dart';
import 'package:system_panel/chat/chat_panel.dart';
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

    testWidgets('白 16% ——「亮帧」', (WidgetTester tester) async {
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

  group('就地白晕（FlashBloom · t26/P2 HUD 跨级白闪的载体）', () {
    testWidgets('峰值 0 时不画任何东西', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const FlashBloom(alpha: 0)));
      expect(_bloomPaint(tester), isNull);
    });

    testWidgets('峰值 16% —— 与 #flash 的亮帧同源', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const FlashBloom(alpha: .16)));
      final Color c = _bloomPaint(tester)!.color;
      expect(c.a, closeTo(41 / 255, .01)); // .16 × 255
      expect(c.r, 1);
      expect(c.g, 1);
      expect(c.b, 1);
    });
  });

  // ── LLM 思考态呼吸（t26/P2-3）─────────────────────────────
  //
  // 三个点各 600ms 循环 opacity .35→1、相位差 200ms（MOTION-ANALYSIS §3）。
  group('LLM 思考态呼吸（t26/P2-3）', () {
    double opOf(WidgetTester tester, int i) =>
        tester.widget<Opacity>(find.byKey(Key('chat.thinking.dot.$i'))).opacity;

    Future<void> mount(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                ChatPanel(messages: const <ChatMessage>[], thinking: true),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('三颗点循环呼吸：谷底 .35、峰值 1、相位差 1/3 循环', (WidgetTester tester) async {
      await mount(tester);
      await tester.pump(); // 相位 0（不推时钟）
      expect(opOf(tester, 0), closeTo(.35, .01)); // 谷底
      expect(opOf(tester, 1), closeTo(.35 + .65 * .75, .02)); // 相位 1/3
      expect(opOf(tester, 2), closeTo(.35 + .65 * .75, .02)); // 相位 2/3
      await tester.pump(const Duration(milliseconds: 100)); // 相位 1/6
      expect(opOf(tester, 0), closeTo(.35 + .65 * .25, .02));
      expect(opOf(tester, 1), closeTo(1.0, .02)); // 峰值
      expect(opOf(tester, 2), closeTo(.35 + .65 * .25, .02));
      await tester.pump(const Duration(milliseconds: 500)); // 跨过整个循环
      for (int i = 0; i < 3; i++) {
        expect(opOf(tester, i), greaterThanOrEqualTo(.34));
        expect(opOf(tester, i), lessThanOrEqualTo(1.01));
      }
    });
  });
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Stack(children: <Widget>[child])),
);

/// 取出白晕画笔
FlashBloomPainter? _bloomPaint(WidgetTester tester) {
  final Finder f = find.descendant(
    of: find.byType(FlashBloom),
    matching: find.byType(CustomPaint),
  );
  if (f.evaluate().isEmpty) return null;
  return tester.widget<CustomPaint>(f.first).painter! as FlashBloomPainter;
}

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
/// 这层包住整个 App，**任意变换会连带重挂整棵子树**，
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
