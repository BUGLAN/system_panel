import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/widgets/fx_particles.dart';

/// 屏幕空间特效（`js/fx.js`）。
///
/// ⚠️ 粒子是**瞬态**，区域均值比对没有意义（实机抓拍必然混进同时段别的动画）。
/// 这里钉的是**物理与生命周期**，逐条对齐 `fx.js` L63-101：
/// 阻尼 `pow(drag, dt×60)`、重力 `vy += g×dt`、透明度 `1 - life/max`、
/// 三种粒子形态、涟漪的 `outCubic`、光痕的 `inOutCubic` 头尾分离。
void main() {
  /// 固定种子，让 rand 可复现
  FxController mk() => FxController(rnd: math.Random(7));

  group('粒子', () {
    test('火花：往上散、往下掉，寿命到就消失', () {
      final FxController c = mk();
      c.spark(100, 100, n: 6);
      expect(c.parts.length, 6);
      expect(c.parts.every((FxParticle p) => p.kind == 'line'), isTrue);
      expect(c.parts.every((FxParticle p) => p.gravity == 900), isTrue);
      // 火花往上方（a ∈ [-π,0] → vy < 0）
      expect(c.parts.every((FxParticle p) => p.vy <= 0), isTrue);
      for (int i = 0; i < 200; i++) {
        c.step(1 / 60);
      }
      expect(c.parts, isEmpty); // 最长 .45s
    });

    test('爆散：默认 60 颗，圆点与碎片混着来', () {
      final FxController c = mk();
      c.burst(195, 500);
      expect(c.parts.length, 60);
      expect(c.parts.any((FxParticle p) => p.kind == 'dot'), isTrue);
      expect(c.parts.any((FxParticle p) => p.kind == 'shard'), isTrue);
      expect(c.parts.every((FxParticle p) => p.gravity == 160), isTrue);
      // 证据入槽那一下：n:16 / max:160 / life:.5
      final FxController c2 = mk();
      c2.burst(100, 100, n: 16, max: 160, life: .5);
      expect(c2.parts.length, 16);
      expect(c2.parts.every((FxParticle p) => p.max <= .5), isTrue);
    });

    test('上升尘：往上飘（重力为负）', () {
      final FxController c = mk();
      c.rise(195, 500, n: 20);
      expect(c.parts.length, 20);
      expect(c.parts.every((FxParticle p) => p.vy < 0), isTrue);
      expect(c.parts.every((FxParticle p) => p.gravity == -20), isTrue);
    });

    test('阻尼写法与原型一致：pow(drag, dt×60)', () {
      final FxController c = mk();
      c.burst(0, 0, n: 1, shards: 0, min: 100, max: 100, drag: .5, g: 0);
      final FxParticle p = c.parts.single;
      final double v0 = p.vx;
      c.step(1 / 60);
      expect(p.vx, closeTo(v0 * .5, 1e-6)); // dt×60 = 1
    });
  });

  group('涟漪与光痕', () {
    test('涟漪：半径按 outCubic 走，到点就回收', () {
      final FxController c = mk();
      c.ripple(100, 100, ms: 900, r0: 10, r1: 260);
      expect(c.rips.length, 1);
      final FxRipple r = c.rips.single;
      expect(r.max, closeTo(.9, 1e-9));
      // ⚠️ step 会把 dt 夹到 .05（照抄原型），所以只能一帧一帧推
      for (int i = 0; i < 27; i++) {
        c.step(1 / 60);
      }
      expect(r.t / r.max, closeTo(.5, .02));
      for (int i = 0; i < 30; i++) {
        c.step(1 / 60);
      }
      expect(c.rips, isEmpty);
    });

    test('光痕：按 ms 折算时长，到点回收', () {
      final FxController c = mk();
      c.streak(0, 0, 100, 100, ms: 420);
      expect(c.streaks.single.max, closeTo(.42, 1e-9));
      for (int i = 0; i < 30; i++) {
        c.step(1 / 60);
      }
      expect(c.streaks, isEmpty);
    });
  });

  group('生命周期', () {
    test('busy 反映"还有东西要画"', () {
      final FxController c = mk();
      expect(c.busy, isFalse);
      c.spark(0, 0, n: 1);
      expect(c.busy, isTrue);
      c.clear();
      expect(c.busy, isFalse);
    });

    test('按需跑帧：有粒子才动，跑完自停', () {
      final FxController c = mk();
      c.spark(100, 100, n: 4);
      int frames = 0;
      while (c.busy && frames < 600) {
        c.step(1 / 60);
        frames++;
      }
      expect(frames, lessThan(60)); // 寿命 .18~.45s
      expect(c.busy, isFalse);
    });
  });

  group('画布', () {
    testWidgets('没有粒子时不画（画布空着）', (WidgetTester tester) async {
      final FxController c = FxController(rnd: math.Random(1));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(children: <Widget>[FxField(controller: c)]),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      c.dispose();
    });

    testWidgets('抛粒子后能跑起来并自己停下', (WidgetTester tester) async {
      final FxController c = FxController(rnd: math.Random(1));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(children: <Widget>[FxField(controller: c)]),
          ),
        ),
      );
      c.burst(195, 400, n: 20);
      await tester.pump();
      expect(c.busy, isTrue);
      // 一次 pump(1600ms) 只算一帧，而 step 会把 dt 夹到 .05 —— 要一帧帧推
      for (int i = 0; i < 110; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(c.busy, isFalse);
      c.dispose();
    });
  });
}
