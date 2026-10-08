import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/widgets/hold_button.dart';

/// 按住类按钮（原型三处：指纹接单 0.9s / 认输 1.2s / 重置 2s）。
///
/// 关键差别：**松手是固定速率退回**，不是"反向播放"——
/// 用 `AnimationController` 的 forward/reverse 会让退回速度跟按住进度挂钩，
/// 手感完全不同。这一条用测试钉住。
Future<void> _mount(
  WidgetTester tester, {
  required Duration duration,
  required Duration decay,
  required VoidCallback onComplete,
  ValueChanged<double>? onProgress,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: HoldButton(
            duration: duration,
            decay: decay,
            onComplete: onComplete,
            onProgress: onProgress,
            builder: (BuildContext _, double p) =>
                SizedBox(width: 200, height: 48, child: Text('p=$p')),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// 一帧帧推（step 会把 dt 夹到 .05，所以不能一步跨过去）
Future<void> _pumpFrames(
  WidgetTester tester,
  Duration total, {
  double frameMs = 16,
}) async {
  final int n = (total.inMilliseconds / frameMs).round();
  for (int i = 0; i < n; i++) {
    await tester.pump(Duration(microseconds: (frameMs * 1000).round()));
  }
}

Future<double> _hold(
  WidgetTester tester,
  Duration total, {
  double frameMs = 16,
}) async {
  await _pumpFrames(tester, total, frameMs: frameMs);
  return _progress(tester);
}

double _progress(WidgetTester tester) {
  final Text t = tester.widget<Text>(find.byType(Text));
  return double.parse(t.data!.substring(2));
}

void main() {
  group('按满', () {
    testWidgets('0.9s 按满触发（指纹接单）', (WidgetTester tester) async {
      int done = 0;
      await _mount(
        tester,
        duration: const Duration(milliseconds: 900),
        decay: const Duration(milliseconds: 350),
        onComplete: () => done++,
      );
      final TestGesture g = await tester.startGesture(
        tester.getCenter(find.byType(HoldButton)),
      );
      await _hold(tester, const Duration(milliseconds: 500));
      expect(done, 0);
      expect(_progress(tester), greaterThan(.4));
      await _hold(tester, const Duration(milliseconds: 500));
      expect(done, 1);
      await g.up();
      await tester.pump();
    });

    testWidgets('松手太早不算数', (WidgetTester tester) async {
      int done = 0;
      await _mount(
        tester,
        duration: const Duration(milliseconds: 900),
        decay: const Duration(milliseconds: 350),
        onComplete: () => done++,
      );
      final TestGesture g = await tester.startGesture(
        tester.getCenter(find.byType(HoldButton)),
      );
      await _hold(tester, const Duration(milliseconds: 300));
      await g.up();
      await _hold(tester, const Duration(milliseconds: 600));
      expect(done, 0);
      expect(_progress(tester), 0); // 退回到底了
    });
  });

  group('退回是固定速率', () {
    testWidgets('按到 80% 松手，0.35s 内退完（不是按比例的）', (WidgetTester tester) async {
      await _mount(
        tester,
        duration: const Duration(milliseconds: 900),
        decay: const Duration(milliseconds: 350),
        onComplete: () {},
      );
      final TestGesture g = await tester.startGesture(
        tester.getCenter(find.byType(HoldButton)),
      );
      await _hold(tester, const Duration(milliseconds: 720)); // ≈80%
      final double peak = _progress(tester);
      expect(peak, greaterThan(.7));
      await g.up();
      // 半程（175ms）应该退掉一半左右
      await _hold(tester, const Duration(milliseconds: 175));
      final double half = _progress(tester);
      expect(half, closeTo(peak - .5, .12));
      await _hold(tester, const Duration(milliseconds: 220));
      expect(_progress(tester), 0);
    });

    testWidgets('重置存档退得最慢（1s）', (WidgetTester tester) async {
      await _mount(
        tester,
        duration: const Duration(seconds: 2),
        decay: const Duration(seconds: 1),
        onComplete: () {},
      );
      final TestGesture g = await tester.startGesture(
        tester.getCenter(find.byType(HoldButton)),
      );
      await _hold(tester, const Duration(milliseconds: 1000)); // ≈50%
      final double peak = _progress(tester);
      expect(peak, greaterThan(.4));
      await g.up();
      await _hold(tester, const Duration(milliseconds: 500)); // 半程
      expect(_progress(tester), closeTo(peak - .5, .15));
      await _hold(tester, const Duration(milliseconds: 600));
      expect(_progress(tester), 0);
    });
  });

  group('进度回调', () {
    testWidgets('每一帧回报（认输用它驱动 veil）', (WidgetTester tester) async {
      final List<double> seen = <double>[];
      await _mount(
        tester,
        duration: const Duration(milliseconds: 1200),
        decay: const Duration(milliseconds: 300),
        onComplete: () {},
        onProgress: seen.add,
      );
      final TestGesture g = await tester.startGesture(
        tester.getCenter(find.byType(HoldButton)),
      );
      await _hold(tester, const Duration(milliseconds: 600));
      await g.up();
      await _hold(tester, const Duration(milliseconds: 400));
      expect(seen.length, greaterThan(20));
      expect(seen.first, lessThan(.1));
      expect(
        seen.reduce((double a, double b) => a > b ? a : b),
        greaterThan(.4),
      );
      expect(seen.last, 0); // 退回底之后仍会报一次 0
    });

    testWidgets('打点回调按 1/steps 触发（指纹是 8 下）', (WidgetTester tester) async {
      final List<double> steps = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: HoldButton(
                duration: const Duration(milliseconds: 900),
                steps: 8,
                onStep: steps.add,
                onComplete: () {},
                builder: (BuildContext _, double p) =>
                    const SizedBox(width: 100, height: 40),
              ),
            ),
          ),
        ),
      );
      final TestGesture g = await tester.startGesture(const Offset(400, 300));
      await _pumpFrames(tester, const Duration(milliseconds: 850));
      await g.up();
      expect(steps.length, greaterThanOrEqualTo(6));
    });
  });

  group('布局', () {
    testWidgets('按住条是整高的一条，宽度跟着 p（`.quit i` / `.danger i`）', (
      WidgetTester tester,
    ) async {
      await _mount(
        tester,
        duration: const Duration(seconds: 1),
        decay: const Duration(seconds: 1),
        onComplete: () {},
      );
      expect(tester.takeException(), isNull);
      // 用真实的两个宿主组件各渲染一遍，确认约束合法
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: HoldButton(
                duration: const Duration(seconds: 2),
                decay: const Duration(seconds: 1),
                onComplete: () {},
                builder: (BuildContext _, double p) => Container(
                  key: const Key('bar'),
                  height: 36,
                  width: 120,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.red, width: 1),
                  ),
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: p,
                            heightFactor: 1,
                            child: const ColoredBox(color: Colors.red),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
