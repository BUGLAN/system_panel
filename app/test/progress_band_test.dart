import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/stage/camera.dart';
import 'package:system_panel/stage/progress_band.dart';

/// 进度带（docs/33 阶段 5）—— 原 `rings_test`（8 条环场画笔）的接任者。
///
/// 几何是**腰上一圈**：世界坐标 `(.30, feet + .36)`，用相机数学投到屏幕；
/// 状态（走过 / 脚下 / 未走）一律用样式表达，这里只钉可测的那几件：
/// 落点、可见性开关、重绘条件、以及"没清单就不画"。
/// 只有进度带自己画的那层 CustomPaint（Material/Scaffold 内部也有 CustomPaint，
/// 按类型数会把它们一起数进来）
bool _isBandPaint(Widget w) =>
    w is CustomPaint && w.painter is ProgressBandPainter;

void main() {
  const Size kDesign = Size(390, 844);

  group('进度带 · 几何', () {
    test('右端点落在屏幕右半边、且与相机一致', () {
      final Offset p = ProgressBand.point('full', kDesign);
      expect(p.dx, greaterThan(kDesign.width / 2));
      expect(p.dx, lessThan(kDesign.width));
      expect(p.dy, greaterThan(0));
      expect(p.dy, lessThan(kDesign.height));
      // 大厅相机比全景更近一点（同一世界点 → 更靠左下）
      final Offset l = ProgressBand.point('lobby', kDesign);
      expect(l.dx, isNot(p.dx));
    });

    test('只有一条带（不是 8 条等宽虚线）', () {
      expect(ProgressBand.kRx, .34);
      // 世界坐标：脚在负值区，带子在脚上方、发际线下方
      expect(ProgressBand.kRy, lessThan(0));
      expect(ProgressBand.kRy, greaterThan(StageAnchors.feet));
      expect(ProgressBand.kRy, lessThan(StageAnchors.hair));
      // 透视压扁后的纵向半径 = 横向半径 × .22（原「未走」环同款比例）
      // ⚠️ 高度是照「看得见」定的：放到胯/腰那一档会被裙子整圈吃掉
      expect(ProgressBand.kRyy, closeTo(ProgressBand.kRx * .22, 1e-9));
    });
  });

  group('进度带 · 可见性', () {
    testWidgets('没清单（未绑定）什么都不画', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                ProgressBand(done: 0, total: 0),
              ],
            ),
          ),
        ),
      );
      expect(find.byWidgetPredicate(_isBandPaint), findsNothing);
    });

    testWidgets('visible: false 也不画', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                ProgressBand(done: 3, total: 8, visible: false),
              ],
            ),
          ),
        ),
      );
      expect(find.byWidgetPredicate(_isBandPaint), findsNothing);
    });

    testWidgets('有清单就画一层（IgnorePointer，不挡手势）', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(children: <Widget>[ProgressBand(done: 3, total: 8)]),
          ),
        ),
      );
      expect(find.byType(ProgressBand), findsOneWidget);
      expect(find.byWidgetPredicate(_isBandPaint), findsOneWidget);
      expect(find.byType(IgnorePointer), findsWidgets);
    });
  });

  group('进度带 · 重绘', () {
    ProgressBandPainter paint({int done = 3, int total = 8, double t = 0}) =>
        ProgressBandPainter(
          done: done,
          total: total,
          cam: 'full',
          t: t,
          dim: 1,
          scan: 0,
        );

    test('进度变了 / 时间走了都要重画', () {
      expect(paint(done: 4).shouldRepaint(paint(done: 3)), isTrue);
      expect(paint(total: 9).shouldRepaint(paint(total: 8)), isTrue);
      expect(paint(t: .5).shouldRepaint(paint(t: 0)), isTrue);
    });

    test('什么都没变就不重画', () {
      expect(paint().shouldRepaint(paint()), isFalse);
    });
  });
}
