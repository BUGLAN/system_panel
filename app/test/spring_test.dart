import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/stage/camera.dart';
import 'package:system_panel/stage/spring.dart';

/// 弹簧（`util.js` L85-98）与相机弹簧（`stage.js` L100-103）。
///
/// 这里**刻意不用 Flutter 的 `SpringSimulation`** —— 同样的 (k, ζ) 它给出的
/// 过冲与收敛速度跟原型不是一回事。既然原型把积分式子写出来了，就照抄。
void main() {
  group('Spring 本身', () {
    test('停在目标上就不动', () {
      final Spring s = Spring(v: 3, k: 70, zeta: .95);
      for (int i = 0; i < 10; i++) {
        s.step(1 / 60);
      }
      expect(s.x, closeTo(3, 1e-9));
      expect(s.v, 0);
      expect(s.done, isTrue);
    });

    test('阻尼系数 c = 2ζ√k', () {
      final Spring s = Spring(k: 70, zeta: .95);
      expect(s.c, closeTo(2 * .95 * math.sqrt(70), 1e-12));
    });

    test('设了目标会往那边走，并最终收敛（ζ<1 会过冲一次）', () {
      final Spring s = Spring(k: 70, zeta: .95);
      s.set(10);
      double maxX = 0;
      for (int i = 0; i < 600; i++) {
        s.step(1 / 60);
        maxX = math.max(maxX, s.x);
      }
      expect(s.done, isTrue);
      expect(s.x, closeTo(10, 1e-3));
      // ζ = .95 → 理论过冲约 e^(-πζ/√(1-ζ²)) ≈ 22%
      expect(maxX, greaterThan(10));
      expect(maxX, lessThan(10 * 1.35));
    });

    test('临界阻尼不冲过头', () {
      final Spring s = Spring(k: 70, zeta: 1);
      s.set(10);
      double maxX = 0;
      for (int i = 0; i < 600; i++) {
        s.step(1 / 60);
        maxX = math.max(maxX, s.x);
      }
      expect(maxX, lessThanOrEqualTo(10 + 1e-6));
    });

    test('⚠️ 子步长 ≤ 1/120s：一大步 ≈ 拆成小步', () {
      final Spring a = Spring(k: 70, zeta: .95)..set(10);
      final Spring b = Spring(k: 70, zeta: .95)..set(10);
      a.step(1 / 15); // 一大步（内部会自己拆）
      for (int i = 0; i < 4; i++) {
        b.step(1 / 60);
      }
      expect(a.x, closeTo(b.x, .02));
    });

    test('snap 直接到位、速度归零', () {
      final Spring s = Spring(k: 70, zeta: .95)..set(5);
      s.step(1 / 60);
      expect(s.x, greaterThan(0));
      s.set(100, snap: true);
      expect(s.x, 100);
      expect(s.v, 0);
      expect(s.done, isTrue);
    });

    test('dt <= 0 不动（防除零）', () {
      final Spring s = Spring(k: 70, zeta: .95)..set(10);
      s.step(0);
      s.step(-1);
      expect(s.x, 0);
    });
  });

  group('相机弹簧', () {
    const Size size = Size(390, 844);

    test('第一次 set 直接到位（没有"从 0 飞进来"）', () {
      final CamSpring c = CamSpring()..set('lobby', size);
      final Cam want = Cam.byName('lobby');
      expect(c.cam.s, closeTo(want.s, 1e-9));
      expect(c.cam.ax, closeTo(want.ax, 1e-9));
      expect(c.cam.ay, closeTo(want.ay, 1e-9));
      expect(c.cam.sxF, closeTo(want.sxF, 1e-9));
      expect(c.cam.syF, closeTo(want.syF, 1e-9));
    });

    test('⚠️ 切页后收敛到静态预设 —— 否则所有比对都会歪', () {
      final CamSpring c = CamSpring()..set('boot', size);
      for (final String name in <String>[
        'lobby',
        'talk',
        'exec',
        'result',
        'full',
        'panel',
        'fail',
      ]) {
        c.set(name, size);
        for (int i = 0; i < 900 && !c.done; i++) {
          c.step(1 / 60);
        }
        final Cam want = Cam.byName(name);
        expect(c.cam.s, closeTo(want.s, 1e-3), reason: '$name 的 S');
        expect(c.cam.ax, closeTo(want.ax, 1e-3), reason: '$name 的 ax');
        expect(c.cam.ay, closeTo(want.ay, 1e-3), reason: '$name 的 ay');
        expect(c.cam.sxF, closeTo(want.sxF, 1e-3), reason: '$name 的 sxF');
        expect(c.cam.syF, closeTo(want.syF, 1e-3), reason: '$name 的 syF');
      }
    });

    test('刚切过去的一刹那还没到（真的在"推镜头"）', () {
      final CamSpring c = CamSpring()..set('boot', size);
      final double before = c.cam.s;
      c.set('talk', size);
      expect(c.done, isFalse);
      c.step(1 / 60);
      expect(c.cam.s, isNot(closeTo(Cam.byName('talk').s, 1e-6)));
      expect(c.cam.s, greaterThan(before), reason: 'talk 是拉近，S 应该变大');
      expect(c.cam.s, lessThan(Cam.byName('talk').s), reason: '一帧还没到');
    });

    test('视觉上收敛是"几百毫秒"量级（不是瞬移，也不拖沓）', () {
      // ⚠️ `done` 用的是**绝对**容差 1e-3 —— 对 ~700px 的跳变要 100 多帧才满足，
      // 那是容差问题、不是弹簧慢。这里按"差半个像素就算到了"来量。
      final CamSpring c = CamSpring()..set('boot', size);
      final double target = Cam.byName('talk').scale(size.height);
      c.set('talk', size);
      int frames = 0;
      while ((c.cam.scale(size.height) - target).abs() > .5 && frames < 1000) {
        c.step(1 / 60);
        frames++;
      }
      expect(frames, greaterThan(8)); // 别一帧就到
      // 实测 ~62 帧（约 1.05s）—— ζ=.95 很阻尼，镜头是"缓缓推过去"而不是弹一下；
      // 这是原型 (k=70, ζ=.95) 本身的手感，不是实现问题
      expect(frames, lessThan(90));
    });
  });
}
