import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/state/app_clock.dart';

/// 每秒时钟与读数（`flows.js` `App.second()` + `ui.js` `Exec.tick()`）。
///
/// 关键：计时**不是累加**出来的，是 `现在 - startAt` 推出来的
/// —— 息屏/切后台回来照样对。这一条必须钉住。
void main() {
  final DateTime t0 = DateTime(2026, 10, 8, 20, 2, 0);

  group('执行读数', () {
    test('从 startAt 推出已用时长', () {
      final ExecReadout r = ExecReadout.of(
        startAt: t0,
        now: t0.add(const Duration(minutes: 7)),
        limit: const Duration(minutes: 45),
      );
      expect(r.elapsed, const Duration(minutes: 7));
      expect(r.limit, const Duration(minutes: 45));
      expect(r.progress, closeTo(7 / 45, 1e-9));
      expect(r.warn, isFalse);
      expect(r.timedOut, isFalse);
      expect(r.remaining, const Duration(minutes: 38));
    });

    test('跨过 85% 转白警示（原型 `e > lim * .85`）', () {
      ExecReadout at(double min) => ExecReadout.of(
        startAt: t0,
        now: t0.add(Duration(milliseconds: (min * 60000).round())),
        limit: const Duration(minutes: 45),
      );
      expect(at(38.24).warn, isFalse); // 84.98%
      expect(at(38.3).warn, isTrue); // 85.1%
    });

    test('到点判负，进度条不再涨过 100%', () {
      final ExecReadout r = ExecReadout.of(
        startAt: t0,
        now: t0.add(const Duration(minutes: 50)),
        limit: const Duration(minutes: 45),
      );
      expect(r.timedOut, isTrue);
      expect(r.progress, 1);
      expect(r.remaining.isNegative, isTrue);
    });

    test('时钟回拨（现在是过去）不会给出负数', () {
      final ExecReadout r = ExecReadout.of(
        startAt: t0,
        now: t0.subtract(const Duration(minutes: 3)),
        limit: const Duration(minutes: 45),
      );
      expect(r.elapsed, Duration.zero);
      expect(r.progress, 0);
    });

    test('久了也不会溢出（推导而非累加的好处）', () {
      final ExecReadout r = ExecReadout.of(
        startAt: t0,
        now: t0.add(const Duration(hours: 9)),
        limit: const Duration(minutes: 45),
      );
      expect(r.elapsed, const Duration(hours: 9));
      expect(r.warn, isTrue);
      expect(r.timedOut, isTrue);
    });
  });

  group('她开口的排期', () {
    test('大厅 26~42s 一句，且要等宿主安静 6s', () {
      final ChatterScheduler s = ChatterScheduler(
        rand: (double a, double b) => a, // 取下界，可复现
      );
      s.resetIdle(Duration.zero);
      expect(s.idleNextAt, const Duration(seconds: 26));
      expect(
        s.idleDue(
          const Duration(seconds: 25),
          const Duration(seconds: 30),
          lineQuiet: true,
        ),
        isFalse,
      );
      expect(
        s.idleDue(
          const Duration(seconds: 26),
          const Duration(seconds: 30),
          lineQuiet: true,
        ),
        isTrue,
      );
      // 宿主刚动过（< 6s）就不吭声
      expect(
        s.idleDue(
          const Duration(seconds: 26),
          const Duration(seconds: 5),
          lineQuiet: true,
        ),
        isFalse,
      );
      // 她自己还在说话也不吭声
      expect(
        s.idleDue(
          const Duration(seconds: 26),
          const Duration(seconds: 30),
          lineQuiet: false,
        ),
        isFalse,
      );
    });

    test('执行中 45~75s 一句', () {
      final ChatterScheduler s = ChatterScheduler(
        rand: (double a, double b) => b,
      );
      s.resetExec(Duration.zero);
      expect(s.execNextAt, const Duration(seconds: 75));
      expect(s.execDue(const Duration(seconds: 74), lineQuiet: true), isFalse);
      expect(s.execDue(const Duration(seconds: 75), lineQuiet: true), isTrue);
    });

    test('静默阈值是 80s（走神）', () {
      expect(ChatterScheduler.dozeAfter, const Duration(seconds: 80));
    });
  });

  group('时钟本身', () {
    test('1 秒一次回调，可以停', () async {
      int n = 0;
      final AppClock c = AppClock();
      expect(c.running, isFalse);
      c.startSeconds(() => n++);
      expect(c.running, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      c.dispose();
      expect(n, lessThan(3)); // 50ms 内不该跑满
    });
  });
}
