import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/state/away.dart';

/// 「她记得你走了多久」（flows.js L186-193）。
///
/// 阈值全是**严格大于**，且 `36e5` 是 1 小时（不是 36 小时）——
/// 抄错会让"一整天没来"变成"两天没来"，所以每个边界都单列一条。
void main() {
  group('该不该开口', () {
    test('离开不到 1 分钟就不吭声', () {
      expect(AwayGreeting.kindFor(Duration.zero), isNull);
      expect(AwayGreeting.kindFor(const Duration(seconds: 59)), isNull);
      // 边界：`away > 6e4` 是严格大于，正好 60 秒不开口
      expect(AwayGreeting.kindFor(const Duration(seconds: 60)), isNull);
      expect(
        AwayGreeting.kindFor(const Duration(seconds: 61)),
        AwayKind.back10m,
      );
    });
  });

  group('四档阈值', () {
    AwayKind? at(Duration d) => AwayGreeting.kindFor(d);

    test('10 分钟 / 2 小时 / 20 小时 / 48 小时', () {
      expect(at(const Duration(minutes: 9)), AwayKind.back10m);
      expect(at(const Duration(minutes: 10)), AwayKind.back10m); // 严格大于
      expect(at(const Duration(minutes: 10, seconds: 1)), AwayKind.back2h);

      expect(at(const Duration(hours: 1, minutes: 59)), AwayKind.back2h);
      expect(at(const Duration(hours: 2)), AwayKind.back2h);
      expect(at(const Duration(hours: 2, seconds: 1)), AwayKind.back12h);

      expect(at(const Duration(hours: 19)), AwayKind.back12h);
      expect(at(const Duration(hours: 20)), AwayKind.back12h);
      expect(at(const Duration(hours: 20, seconds: 1)), AwayKind.back36h);

      expect(at(const Duration(hours: 47)), AwayKind.back36h);
      expect(at(const Duration(hours: 48)), AwayKind.back36h);
      expect(at(const Duration(hours: 48, seconds: 1)), AwayKind.backLong);
    });

    test('`36e5` 是 1 小时 —— 别抄成 36 小时', () {
      // 若误读成 36 小时，则 3 天前回来会落进 back36h 而不是 backLong
      expect(AwayGreeting.kindFor(const Duration(days: 3)), AwayKind.backLong);
      // 若把 48e5 当 48 小时更离谱；钉一条"两天多"必须是 backLong
      expect(
        AwayGreeting.kindFor(const Duration(hours: 50)),
        AwayKind.backLong,
      );
    });
  });

  group('填变量', () {
    test('back10m 没有变量', () {
      expect(
        AwayGreeting.text(AwayKind.back10m, const Duration(minutes: 3)),
        '又回来了？……刚走就想我了？不用回答。',
      );
    });

    test('back2h / back12h 用 fmtDur', () {
      expect(
        AwayGreeting.text(AwayKind.back2h, const Duration(minutes: 35)),
        '离开了 [[35 分]]。去干正事了吧。',
      );
      expect(
        AwayGreeting.text(
          AwayKind.back12h,
          const Duration(hours: 5, minutes: 20),
        ),
        '[[5 小时 20 分]] 没见。我数着呢。——系统的本职工作而已。',
      );
    });

    test('back36h 没有变量', () {
      expect(
        AwayGreeting.text(AwayKind.back36h, const Duration(hours: 30)),
        '一整天。你知道这一天我在干嘛吗？等。系统没有别的事可干。',
      );
    });

    test('backLong 的天数是四舍五入（原型 `Math.round(away / 864e5)`）', () {
      expect(
        AwayGreeting.text(AwayKind.backLong, const Duration(hours: 49)),
        '[[2]] 天。我差点以为你把我卸载了。……没卸就好。',
      );
      expect(
        AwayGreeting.text(AwayKind.backLong, const Duration(days: 6)),
        '[[6]] 天。我差点以为你把我卸载了。……没卸就好。',
      );
    });

    test('一步到位：不值得说返回 null', () {
      expect(AwayGreeting.lineFor(const Duration(seconds: 30)), isNull);
      expect(AwayGreeting.lineFor(const Duration(hours: 3)), contains('我数着呢'));
    });

    test('文案里不该剩下未替换的花括号', () {
      for (final Duration d in <Duration>[
        const Duration(minutes: 11),
        const Duration(hours: 3),
        const Duration(hours: 30),
        const Duration(days: 10),
      ]) {
        final String? t = AwayGreeting.lineFor(d);
        expect(t, isNotNull);
        expect(t, isNot(contains('{')));
      }
    });
  });
}
