import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/state/voice.dart';

/// 口型包络（`audio.js` L180-230）+ 波形条缩放（`ui.js` L70-73）。
void main() {
  group('一个字设一次目标', () {
    test('标点闭嘴', () {
      final VoiceEnvelope v = VoiceEnvelope();
      v.syllable('好'); // 先张着
      expect(v.target, greaterThan(0));
      for (final String p in <String>[
        '，',
        '。',
        '！',
        '？',
        '、',
        '…',
        '—',
        '：',
        ' ',
        '「',
        '」',
      ]) {
        v.syllable(p);
        expect(v.target, 0, reason: '「$p」应该闭嘴');
      }
    });

    test('实字的目标落在 .55~1（原型 `rand(.55, 1)`）', () {
      final VoiceEnvelope v = VoiceEnvelope(rnd: math.Random(7));
      final Set<double> seen = <double>{};
      for (int i = 0; i < 200; i++) {
        v.syllable('字');
        seen.add(v.target);
        expect(v.target, greaterThanOrEqualTo(.55));
        expect(v.target, lessThan(1.0));
      }
      expect(seen.length, greaterThan(50), reason: '应该是随机的，不是固定值');
    });
  });

  group('指数逼近（`mouth += (target-mouth) * (1-pow(.00002, dt))`）', () {
    test('按公式收敛，且永不越过目标', () {
      final VoiceEnvelope v = VoiceEnvelope();
      v.target = 1;
      double prev = 0;
      for (int i = 0; i < 60; i++) {
        v.tick(1 / 60);
        expect(v.mouth, greaterThan(prev));
        expect(v.mouth, lessThanOrEqualTo(1.0));
        prev = v.mouth;
      }
      // 60 帧（1 秒）后应该非常接近目标
      expect(v.mouth, greaterThan(.99));
    });

    test('单帧步进量与公式一致（dt = 1/60）', () {
      final VoiceEnvelope v = VoiceEnvelope();
      v.target = 1;
      v.tick(1 / 60);
      final double want = 1 * (1 - math.pow(.00002, 1 / 60).toDouble());
      expect(v.mouth, closeTo(want, 1e-12));
    });

    test('dt 为 0 不动（免得清零时除出 NaN）', () {
      final VoiceEnvelope v = VoiceEnvelope();
      v.target = 1;
      v.tick(0);
      expect(v.mouth, 0);
      v.tick(-1);
      expect(v.mouth, 0);
    });

    test('收尾：hush 之后会自己降下来', () {
      final VoiceEnvelope v = VoiceEnvelope(rnd: math.Random(1));
      v.syllable('字');
      for (int i = 0; i < 60; i++) {
        v.tick(1 / 60);
      }
      expect(v.mouth, greaterThan(.5));
      v.hush();
      expect(v.target, 0);
      for (int i = 0; i < 60; i++) {
        v.tick(1 / 60);
      }
      expect(v.mouth, lessThan(.02));
    });

    test('reset 立刻归零（切页时不留残影）', () {
      final VoiceEnvelope v = VoiceEnvelope(rnd: math.Random(2));
      v.syllable('字');
      for (int i = 0; i < 30; i++) {
        v.tick(1 / 60);
      }
      expect(v.mouth, greaterThan(0));
      v.reset();
      expect(v.mouth, 0);
      expect(v.target, 0);
    });
  });

  group('波形条缩放 `clamp(.14 + m*(.55+.45*sin(t+i*1.7)), .12, 1)`', () {
    test('静止时所有条都是 .14 —— 和 CSS 的 .15 几乎一致，不破坏既有截图', () {
      for (int i = 0; i < 5; i++) {
        expect(VoiceEnvelope.barScale(i, 0, 12.34), closeTo(.14, 1e-9));
      }
    });

    test('开口时逐条相位错开（i * 1.7）', () {
      const double m = 1;
      const double t = 3.0;
      final List<double> vals = <double>[
        for (int i = 0; i < 5; i++) VoiceEnvelope.barScale(i, m, t),
      ];
      // 相邻两条不应相等（除非恰好同相）
      final Set<String> rounded = vals
          .map((double v) => v.toStringAsFixed(4))
          .toSet();
      expect(rounded.length, greaterThan(2));
      // 第一条与第二条的相位差正是 1.7
      expect(
        VoiceEnvelope.barScale(1, m, t),
        closeTo(VoiceEnvelope.barScale(0, m, t + 1.7), 1e-9),
      );
    });

    test('夹在 .12 ~ 1 之间（mouth 拉满也不越界）', () {
      for (double m = 0; m <= 1.0001; m += .05) {
        for (double t = 0; t < 20; t += .37) {
          for (int i = 0; i < 5; i++) {
            final double v = VoiceEnvelope.barScale(i, m, t);
            expect(v, greaterThanOrEqualTo(.12));
            expect(v, lessThanOrEqualTo(1.0));
          }
        }
      }
    });
  });
}
