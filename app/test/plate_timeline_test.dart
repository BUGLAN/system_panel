import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/widgets/plate_timeline.dart';

/// 派单揭晓的两条时间线（原型 `Plate.rankRoll` / `Plate.engrave`）。
///
/// 这两个循环在原型里全是 `await sleep(...)`，直接照抄成 `Future.delayed`
/// 的话 `flutter test` 的假时钟推不动（PORTING-NOTES #23）。
/// 所以抽成"给时刻算状态"，时序就能在这里钉死。
void main() {
  group('稀有度滚动', () {
    test('逐级的停留时长 `(60 + i*26)`', () {
      final RankRollTimeline t = RankRollTimeline(target: 4);
      expect(t.dwellMs(0), 60);
      expect(t.dwellMs(1), 86);
      expect(t.dwellMs(2), 112);
      expect(t.dwellMs(3), 138);
      expect(t.dwellMs(4), 164);
    });

    test('每级出现的时刻是前面停留的累加', () {
      final RankRollTimeline t = RankRollTimeline(target: 4);
      expect(t.startOf(0), 0);
      expect(t.startOf(1), 60);
      expect(t.startOf(2), 146);
      expect(t.startOf(3), 258);
      expect(t.startOf(4), 396);
      expect(t.total, 396); // 末级不再等
    });

    test('⚠️ 顶档 S 要在 A 上多停一拍（560ms，不是 190ms）', () {
      final RankRollTimeline s = RankRollTimeline(target: 6);
      expect(s.dwellMs(5), 560);
      // 不是 S 的时候还是按公式
      final RankRollTimeline c = RankRollTimeline(target: 5);
      expect(c.dwellMs(5), 190);
      // 其它级不受影响
      expect(s.dwellMs(4), 164);
    });

    test('`fast` 把停留乘 .6（但 S 那一拍不乘 —— 原型也写在分支里）', () {
      final RankRollTimeline t = RankRollTimeline(target: 4, fast: true);
      expect(t.dwellMs(0), closeTo(36, 1e-9));
      expect(t.dwellMs(2), closeTo(67.2, 1e-9));
      final RankRollTimeline s = RankRollTimeline(target: 6, fast: true);
      expect(s.dwellMs(5), 560, reason: 'S 那一下原型是写死的 560');
    });

    test('`indexAt` 在边界上前一级还没让位', () {
      final RankRollTimeline t = RankRollTimeline(target: 4);
      expect(t.indexAt(0), 0);
      expect(t.indexAt(59.9), 0);
      expect(t.indexAt(60), 1);
      expect(t.indexAt(145.9), 1);
      expect(t.indexAt(146), 2);
      expect(t.indexAt(999), 4); // 不会超过 target
    });

    test('从中间往上升（`from` 非 0）', () {
      final RankRollTimeline t = RankRollTimeline(target: 5, from: 3);
      expect(t.startOf(3), 0);
      expect(t.startOf(4), 138);
      expect(t.total, 138 + 164);
      expect(t.indexAt(0), 3);
      expect(t.indexAt(138), 4);
    });
  });

  group('激光刻字', () {
    test('单段时长 `clamp(字数*17, 110, 460)`', () {
      final EngraveTimeline e = EngraveTimeline(<int>[10, 3, 30]);
      expect(e.durOf(0), 170); // 10*17
      expect(e.durOf(1), 110); // 3*17=51 → 夹到下限
      expect(e.durOf(2), 460); // 30*17=510 → 夹到上限
    });

    test('逐段串行，总时长是各段之和', () {
      final EngraveTimeline e = EngraveTimeline(<int>[10, 3, 30]);
      expect(e.startOf(0), 0);
      expect(e.startOf(1), 170);
      expect(e.startOf(2), 280);
      expect(e.total, 740);
    });

    test('`fast` 把每段乘 .55', () {
      final EngraveTimeline e = EngraveTimeline(<int>[10], fast: true);
      expect(e.durOf(0), closeTo(93.5, 1e-9));
    });

    test('`kAt` 是这一段的进度，不是整段的', () {
      final EngraveTimeline e = EngraveTimeline(<int>[10, 10]);
      expect(e.kAt(0, 0), 0);
      expect(e.kAt(0, 85), closeTo(.5, 1e-9));
      expect(e.kAt(0, 170), 1);
      expect(e.kAt(1, 170), 0, reason: '第二段刚开始');
      expect(e.kAt(1, 255), closeTo(.5, 1e-9));
      expect(e.kAt(1, 400), 1);
      // 还没轮到的那段是 0，不是负数
      expect(e.kAt(1, 0), 0);
    });

    test('`activeAt` 指出此刻激光在哪一段，刻完返回 -1', () {
      final EngraveTimeline e = EngraveTimeline(<int>[10, 3]);
      expect(e.activeAt(0), 0);
      expect(e.activeAt(169.9), 0);
      expect(e.activeAt(170), 1);
      expect(e.activeAt(279.9), 1);
      expect(e.activeAt(280), -1);
      expect(e.activeAt(9999), -1);
    });

    test('`.hot` 在刻完后还热 420ms（原型那段 setTimeout）', () {
      final EngraveTimeline e = EngraveTimeline(<int>[10]);
      expect(e.hotAt(0, 0), isTrue);
      expect(e.hotAt(0, 170), isTrue);
      expect(e.hotAt(0, 590), isTrue);
      expect(e.hotAt(0, 591), isFalse);
    });
  });

  group('环形刻度', () {
    test('`226 * (1 - (i+1)/7)`：F 只点亮一小段，S 是整圈', () {
      expect(rankRingOffset(0), closeTo(226 * (1 - 1 / 7), 1e-9));
      expect(rankRingOffset(6), 0);
      // 逐级递减
      for (int i = 0; i < 6; i++) {
        expect(rankRingOffset(i), greaterThan(rankRingOffset(i + 1)));
      }
      // 七档名字
      expect(kRanks.length, 7);
      expect(kRanks.first, 'F');
      expect(kRanks.last, 'S');
    });
  });

  group('落板关键帧（ui.js L231-236）', () {
    test('起点：scale .16 / rotateX 55°', () {
      final ({double scale, double rxDeg}) k = landKeyframes(0);
      expect(k.scale, closeTo(.16, 1e-9));
      expect(k.rxDeg, closeTo(55, 1e-9));
    });

    test('终点：scale 1 / rotateX 0°', () {
      final ({double scale, double rxDeg}) k = landKeyframes(1);
      expect(k.scale, closeTo(1, 1e-9));
      expect(k.rxDeg, closeTo(0, 1e-9));
    });

    test('⚠️ .8 处是**过冲**：scale 1.035、rotateX -5°', () {
      final ({double scale, double rxDeg}) k = landKeyframes(.8);
      expect(k.scale, closeTo(1.035, 1e-9));
      expect(k.rxDeg, closeTo(-5, 1e-9));
    });

    test('全程最大 scale 就是 1.035（过冲一次就回落）', () {
      double maxScale = 0;
      for (int i = 0; i <= 100; i++) {
        maxScale = math.max(maxScale, landKeyframes(i / 100).scale);
      }
      expect(maxScale, closeTo(1.035, 1e-9));
    });

    test('rotateX 先正后负（前倾 55° → 后仰 -5° → 回正）', () {
      expect(landKeyframes(.4).rxDeg, greaterThan(0));
      expect(landKeyframes(.9).rxDeg, lessThan(0));
      expect(landKeyframes(1).rxDeg, closeTo(0, 1e-9));
    });

    test('越界钳制', () {
      expect(landKeyframes(-1).scale, closeTo(.16, 1e-9));
      expect(landKeyframes(2).scale, closeTo(1, 1e-9));
    });
  });
}
