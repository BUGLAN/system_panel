import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/stage/camera.dart';
import 'package:system_panel/stage/ring_painter.dart';
import 'package:system_panel/state/goal.dart';

/// 环场（`stage.js` L568-663 `_drawRings`）。
///
/// 真源是画布上的像素，**单元测试断言不了"辉光对不对"** —— 把关靠
/// `.verify/cmp_step16.py`（实机 vs 原型逐环取均值，八个环 |Δ|≤9.3、
/// 整片环区 -1.7）。这里只钉结构与几何，防止改动时把参数接错。
const Size kDesign = Size(390, 844);

Future<void> _mount(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Stack(children: <Widget>[child])),
    ),
  );
  await tester.pump();
}

void main() {
  group('环场', () {
    testWidgets('八个环都画（收起时一笔不画）', (WidgetTester tester) async {
      await _mount(tester, RingField(goal: Goal.demo()));
      expect(find.byType(CustomPaint), findsWidgets);
      await _mount(tester, RingField(goal: Goal.demo(), visible: false));
      expect(
        find.descendant(
          of: find.byType(RingField),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    });

    testWidgets('每个环的椭圆中心就是环位落点', (WidgetTester tester) async {
      // 环是 `toScreen(0, g.ry)` 为心、rx/ryy × S 为半轴的椭圆
      final Cam c = Cam.byName('full');
      final double s = c.scale(844);
      expect(s, closeTo(294.3246, .01));
      // rx 实测：.30 → .25 线性递减，最后一环是特例 .42（stage.js L368-380）
      const List<double> wantRx = <double>[
        88.30,
        85.85,
        83.39,
        80.94,
        78.49,
        76.03,
        73.58,
        123.62,
      ];
      for (int i = 0; i < 8; i++) {
        final GoalRing r = Goal.demo().rings[i];
        final RingGeom g = RingGeom.of(i, 8, finalRing: r.finalRing);
        final Offset p = c.toScreen(0, g.ry, kDesign);
        expect(p.dx, c.screenCenter(kDesign).dx); // 环心落在 x 正中的竖线上
        expect(g.rx * s, closeTo(wantRx[i], .05));
      }
    });

    test('相机换算与原型一致（S / 中心点）', () {
      const Size z = Size(390, 844);
      final Cam c = Cam.byName('full');
      expect(c.screenCenter(z), const Offset(179.4, 388.24));
      expect(c.scale(844), closeTo(294.32461, 1e-4));
    });

    test('参数变了要重画，没变不重画', () {
      RingFieldPainter p({double t = 0, double dim = 1, String cam = 'full'}) =>
          RingFieldPainter(
            goal: Goal.demo(),
            cam: cam,
            t: t,
            dim: dim,
            scan: .2,
          );
      expect(p().shouldRepaint(p()), isFalse);
      expect(p(t: 1).shouldRepaint(p()), isTrue);
      expect(p(dim: .5).shouldRepaint(p()), isTrue);
      expect(p(cam: 'lobby').shouldRepaint(p()), isTrue);
    });
  });
}
