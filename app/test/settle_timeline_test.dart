import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/widgets/settle_timeline.dart';

/// 结算演出时序（`flows.js` L365-430）。
///
/// 原型整段是 `await sleep/tween` 串的，抽成"给时刻算状态"才测得了。
/// 这里钉住三种组合：不暴击 / 暴击 / 暴击+双倍 —— 因为两个 `await w()`
/// 是**只在对应条件成立时才等**的，抄成无条件会白白多出 360ms。
void main() {
  SettleTimeline plain() =>
      SettleTimeline(baseExp: 50, finalExp: 50, chipCount: 3);
  SettleTimeline crit() =>
      SettleTimeline(baseExp: 50, finalExp: 100, crit: true, chipCount: 4);
  SettleTimeline both() => SettleTimeline(
    baseExp: 50,
    finalExp: 100,
    crit: true,
    dbl: true,
    chipCount: 4,
  );

  group('段落起点', () {
    test('不暴击：820 → 380 → 180 → 160 → 800', () {
      final SettleTimeline t = plain();
      expect(t.impactAt, 820);
      expect(t.headAt, 1200);
      expect(t.cardAt, 1380);
      expect(t.countAt, 1540);
      expect(t.countEnd, 2340);
      // 没有暴击/双倍，那两个等待都不发生
      expect(t.critAt, 2340);
      expect(t.dblAt, 2340);
      expect(t.barAt, 2340);
      expect(t.barEnd, 2860);
      expect(t.chipAt, 2980);
    });

    test('暴击：多等 200 再跳 520', () {
      final SettleTimeline t = crit();
      expect(t.critAt, 2540); // 2340 + 200
      expect(t.critEnd, 3060);
      expect(t.dblAt, 3060, reason: '没双倍就不该再等 160');
      expect(t.barAt, 3060);
    });

    test('暴击 + 双倍：再等 160 跳 480', () {
      final SettleTimeline t = both();
      expect(t.critAt, 2540);
      expect(t.critEnd, 3060);
      expect(t.dblAt, 3220); // 3060 + 160
      expect(t.dblEnd, 3700);
      expect(t.barAt, 3700);
    });

    test('筹码每枚隔 110ms，保存键在最后一枚之后', () {
      final SettleTimeline t = plain();
      expect(t.chipAtOf(0), 2980);
      expect(t.chipAtOf(1), 3090);
      expect(t.chipAtOf(2), 3200);
      expect(t.saveAt, 3420); // 3200 + 220
      expect(t.total, greaterThan(t.saveAt));
    });
  });

  group('数字往上跳', () {
    test('到点之前是 0，之后线性涨到 baseExp', () {
      final SettleTimeline t = plain();
      expect(t.expAt(0), 0);
      expect(t.expAt(t.countAt - 1), 0);
      expect(t.expAt(t.countAt), 0);
      expect(t.expAt(t.countAt + 400), 25); // 一半
      expect(t.expAt(t.countEnd), 50);
    });

    test('暴击翻倍', () {
      final SettleTimeline t = crit();
      expect(t.expAt(t.critAt), 50, reason: '打 CRIT 时停在基础值');
      expect(t.expAt(t.critAt + 260), 75);
      expect(t.expAt(t.critEnd), 100);
    });

    test('双倍卡接着往 finalExp 涨', () {
      final SettleTimeline t = both();
      expect(t.expAt(t.dblAt), 100);
      expect(t.expAt(t.dblAt + 240), 100);
      expect(t.expAt(t.dblEnd), 100); // demo 里 finalExp=100，翻不动了
    });

    test('都不出现时停在 baseExp，不会跳到 finalExp 之外', () {
      final SettleTimeline t = SettleTimeline(baseExp: 50, finalExp: 50);
      expect(t.expAt(t.total), 50);
      expect(t.expAt(1e9), 50);
    });
  });

  group('印章与经验条', () {
    test('CRIT / 双倍卡先后出现，且不早于各自时刻', () {
      final SettleTimeline t = both();
      expect(t.stampAt(0), 0);
      expect(t.stampAt(t.critAt - 1), 0);
      expect(t.stampAt(t.critAt), 1);
      expect(t.stampAt(t.dblAt - 1), 1);
      expect(t.stampAt(t.dblAt), 2);
    });

    test('没有暴击就永远不盖 CRIT 章', () {
      final SettleTimeline t = plain();
      expect(t.stampAt(1e9), 0);
    });

    test('经验条：涨之前是 0，涨完是 1，中间线性', () {
      final SettleTimeline t = plain();
      expect(t.barProgressAt(t.barAt), 0);
      expect(t.barProgressAt(t.barAt + 260), closeTo(.5, 1e-9));
      expect(t.barProgressAt(t.barEnd), 1);
      expect(t.barProgressAt(1e9), 1);
    });
  });

  group('扫描线', () {
    test('从上往下扫：6% → 58%', () {
      final SettleTimeline t = plain();
      expect(t.scanTopPct(0), closeTo(.06, 1e-9));
      expect(t.scanTopPct(SettleTimeline.scanDur), closeTo(.58, 1e-9));
      expect(t.scanTopPct(SettleTimeline.scanDur / 2), closeTo(.32, 1e-9));
    });

    test('透明度关键帧：0% → 0，15% → 1，100% → 0', () {
      final SettleTimeline t = plain();
      expect(t.scanOpacity(0), 0);
      expect(t.scanOpacity(SettleTimeline.scanDur * .15), closeTo(1, 1e-9));
      expect(t.scanOpacity(SettleTimeline.scanDur), closeTo(0, 1e-9));
      // 中途半个
      expect(
        t.scanOpacity(SettleTimeline.scanDur * (.15 + .425)),
        closeTo(.5, .02),
      );
    });

    test('证据飞行的错峰是每道 90ms', () {
      expect(SettleTimeline.streakDelay(0), 0);
      expect(SettleTimeline.streakDelay(3), 270);
    });
  });
}
