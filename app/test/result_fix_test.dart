import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/state/result.dart';
import 'package:system_panel/stage/camera.dart';
import 'package:system_panel/stage/live2d_stage.dart';
import 'package:system_panel/widgets/result_panel.dart';

/// ═══════════════════════════════════════════════════════════
///  结算页三修（2026-10-23 宿主报障）
///   ① Live2D 头部被裁  ② 奖励数字看不清  ③ 无法退出页面
/// ═══════════════════════════════════════════════════════════
void main() {
  group('① 结算相机：头部必须完整可见', () {
    // 可见世界带 = [ay - span/2, ay + span/2]（与分辨率无关）
    // 头顶屏高占比 = sy + (ay - hair)·s/span
    double headAt(Cam c, double h) =>
        c.syF + (c.ay - StageAnchors.hair) * c.s / StageAnchors.bodySpan;

    test('result 相机：头顶落在屏高 5%~20%', () {
      final Cam c = Cam.byName('result');
      final double y = headAt(c, 844);
      expect(y, greaterThan(0.05), reason: '头顶不能在屏幕外（负值即被裁）');
      expect(y, lessThan(0.20), reason: '也不能太靠下，留出抬头空间');
    });

    test('result 相机的视图矩形顶端不得溢出屏幕（负值 = 被裁的根因）', () {
      final Cam c = Cam.byName('result');
      for (final double h in <double>[640, 844, 932, 1180]) {
        final double top = c.syF - c.s / 2;
        expect(top, greaterThanOrEqualTo(-0.001), reason: '屏高 $h');
      }
    });

    test('所有相机都不许把头顶推出屏幕外', () {
      // talk 是「推到她跟前」的特写，允许主动裁掉头顶以上（-2%），
      // 但**结算页这种全景**不许。
      const List<String> panoramas = <String>[
        'lobby', 'result', 'full', 'panel', 'fail', 'exec', 'boot',
      ];
      for (final String n in panoramas) {
        final double y = headAt(Cam.byName(n), 844);
        expect(y, greaterThan(0.0), reason: '$n 的头顶出画了');
      }
    });

    test('viewRect 保持画布比例（否则插件按宽度适配会裁头脚）', () {
      final Cam c = Cam.byName('result');
      const Size size = Size(390, 844);
      final Rect r = Live2DStage.viewRect(1.05, c, size);
      expect(r.width / r.height, closeTo(Live2DStage.kCanvasAspect, 0.001));
    });
  });

  group('③ 返回主界面按钮', () {
    Future<void> mount(WidgetTester tester, Widget w, Size size) async {
      tester.view.physicalSize = Size(size.width * 3, size.height * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Stack(children: <Widget>[w]))));
      await tester.pump(const Duration(milliseconds: 1200));
    }

    testWidgets('按钮存在、可见、可点，且回调真的触发', (WidgetTester tester) async {
      int taps = 0;
      await mount(
        tester,
        ResultPanel(result: QuestResult.demo, onExit: () => taps++, visible: true),
        const Size(390, 844),
      );
      final Finder btn = find.byKey(const Key('result.exit'));
      expect(btn, findsOneWidget);
      expect(tester.getSize(btn).height, greaterThan(0));
      await tester.tap(btn);
      await tester.pump();
      expect(taps, 1, reason: '点一下必须真的回大厅');
    });

    testWidgets('按钮不依赖演出进度（刚上屏就能点）', (WidgetTester tester) async {
      int taps = 0;
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                ResultPanel(result: QuestResult.demo, onExit: () => taps++, visible: true),
              ],
            ),
          ),
        ),
      );
      // 首帧就要在、就要能点 —— 演出这时候一秒都没走。
      // （不套 _rise 的意义就在这里：入场动效会让按钮首帧是透明的）
      expect(find.byKey(const Key('result.exit')), findsOneWidget);
      await tester.tap(find.byKey(const Key('result.exit')));
      expect(taps, 1, reason: '演出没播完也得能退出');
      // 收尾：让演出把定时器跑完，否则 fake_async 报「pending timers」。
      // 不能用 pumpAndSettle —— 结算页有常驻循环动画，永远 settle 不了。
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('小屏（360×640）与桌面宽屏（1280×800）都在屏内且可点',
        (WidgetTester tester) async {
      for (final Size size in <Size>[const Size(360, 640), const Size(1280, 800)]) {
        int taps = 0;
        await mount(
          tester,
          ResultPanel(result: QuestResult.demo, onExit: () => taps++, visible: true),
          size,
        );
        final Finder btn = find.byKey(const Key('result.exit'));
        expect(btn, findsOneWidget, reason: '$size');
        final Rect r = tester.getRect(btn);
        expect(r.left, greaterThanOrEqualTo(0), reason: '$size 左边越界');
        expect(r.right, lessThanOrEqualTo(size.width + .5), reason: '$size 右边越界');
        expect(r.top, greaterThanOrEqualTo(0), reason: '$size 顶部越界');
        await tester.tap(btn);
        await tester.pump();
        expect(taps, 1, reason: '$size 点不动');
      }
    });

    testWidgets('未传 onExit 时不渲染按钮（不造假出口）', (WidgetTester tester) async {
      await mount(
        tester,
        ResultPanel(result: QuestResult.demo, visible: true),
        const Size(390, 844),
      );
      expect(find.byKey(const Key('result.exit')), findsNothing);
    });
  });

  group('② 奖励数字', () {
    testWidgets('EXP 数字字号 ≥ 44 且带描边（不再糊成一团）', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                ResultPanel(result: QuestResult.demo, visible: true),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 2000));
      final Iterable<Text> texts = tester.widgetList<Text>(find.byType(Text));
      final Iterable<Text> expNums = texts.where((Text t) =>
          t.style?.fontSize != null && t.style!.fontSize! >= 44);
      expect(expNums, isNotEmpty, reason: 'EXP 大字必须够大');
      for (final Text t in expNums) {
        expect(t.style!.shadows, isNotNull);
        expect(t.style!.shadows!.length, greaterThanOrEqualTo(2),
            reason: '至少 1 层描边 + 1 层辉光，才在深底上读得清');
      }
    });
  });
}
