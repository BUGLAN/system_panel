import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/data/format.dart';
import 'package:system_panel/state/quest.dart';
import 'package:system_panel/widgets/exec_panel.dart';

/// 执行面板（大字计时器 / 时限条 / 观看眼 / 证据槽 / 暴击率 / 道具 + 提交）。
/// 坐标断言来自运行中原型的实测值。
///
/// ⚠️ 同 lobby_test：`flutter test` 用占位字体（每字形 1em 宽），
/// 凡"宽度由文字撑出来"的盒子在单测里量不准，只断言与文字宽度无关的部分。
const Size kDesign = Size(390, 844);

Future<void> _mount(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(kDesign);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Stack(children: <Widget>[child])),
    ),
  );
  await tester.pump();
}

void main() {
  group('时间格式 = util.js', () {
    test('fmtClock：1 小时以内 MM:SS，超过 H:MM:SS（L46）', () {
      expect(fmtClock(const Duration(seconds: 7)), '00:07');
      expect(fmtClock(const Duration(minutes: 45)), '45:00');
      expect(fmtClock(const Duration(minutes: 7)), '07:00');
      expect(
        fmtClock(const Duration(hours: 1, minutes: 5, seconds: 3)),
        '1:05:03',
      );
      expect(fmtClock(const Duration(seconds: -5)), '00:00');
    });

    test('fmtMin：分钟 / 小时 / 小时+分（L51）', () {
      expect(fmtMin(45), '45 分钟');
      expect(fmtMin(60), '1 小时');
      expect(fmtMin(90), '1 小时 30 分');
    });
  });

  group('执行面板', () {
    testWidgets('文案齐全', (WidgetTester tester) async {
      await _mount(
        tester,
        const ExecPanel(
          quest: Quest.demo,
          elapsed: Duration(minutes: 7),
          critChance: .12,
          itemCount: 3,
          evidenceCount: 0,
        ),
      );
      expect(find.text('执行中 · RING 5/8'), findsOneWidget);
      expect(find.text('跑完 5 公里'), findsOneWidget);
      expect(find.text('07:00'), findsOneWidget);
      expect(find.text('/ 45:00'), findsOneWidget);
      expect(find.text('SYSTEM 正在看着你'), findsOneWidget);
      expect(find.text('证据 · 跑步 App 截图'), findsOneWidget);
      expect(find.textContaining('暴击率'), findsWidgets);
      expect(find.textContaining('12%'), findsWidgets);
      expect(find.text('道具'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('提交 · 让她验收'), findsOneWidget);
      expect(find.text('按住 · 认输'), findsOneWidget);
      expect(find.text('收起 ▾'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('各件落在原型实测坐标上', (WidgetTester tester) async {
      await _mount(
        tester,
        const ExecPanel(
          quest: Quest.demo,
          elapsed: Duration(minutes: 7),
          critChance: .12,
          itemCount: 3,
          evidenceCount: 0,
        ),
      );
      // .ex-col：left 22 / top 92 / 宽 62%（390 → 241.8）
      final Rect col = tester.getRect(find.byKey(const Key('exec.col')));
      expect(col.left, 22);
      expect(col.top, 92);
      expect(col.width, closeTo(241.8, .5));
      // .ex-k .rk → [22,92,22,22]
      expect(
        tester.getRect(find.byKey(const Key('exec.rk'))),
        const Rect.fromLTWH(22, 92, 22, 22),
      );
      // 三个证据槽 x=22/88/154，各 58×58，y=349
      for (int i = 0; i < 3; i++) {
        final Rect s = tester.getRect(find.byKey(Key('exec.slot.$i')));
        expect(s.left, 22 + i * 66);
        expect(s.top, 349);
        expect(s.size, const Size(58, 58));
      }
      // .ex-act [20,708,350,54]；道具 [20,708,88,54]；提交 [118,708,252,54]
      final Rect act = tester.getRect(find.byKey(const Key('exec.act')));
      expect(act.left, 20);
      expect(act.right, 370);
      expect(act.bottom, closeTo(762, .5));
      expect(tester.getRect(find.byKey(const Key('exec.item'))).left, 20);
      expect(tester.getRect(find.byKey(const Key('exec.item'))).height, 54);
      expect(tester.getRect(find.byKey(const Key('exec.go'))).right, 370);
      // .ex-low [20,778,350,40]
      expect(tester.getRect(find.byKey(const Key('exec.quit'))).top, 778);
      expect(tester.getRect(find.byKey(const Key('exec.quit'))).height, 40);
      expect(tester.getRect(find.byKey(const Key('exec.min'))).right, 370);
    });

    testWidgets('时限条真的有高度，且按进度铺开', (WidgetTester tester) async {
      await _mount(
        tester,
        const ExecPanel(
          quest: Quest.demo,
          elapsed: Duration(minutes: 7), // 7/45 = 15.6%
          critChance: .12,
          itemCount: 3,
          evidenceCount: 0,
        ),
      );
      // 回归：FractionallySizedBox 少了 heightFactor，无子元素的 DecoratedBox 会被量成 0 高
      final Rect bar = tester.getRect(find.byKey(const Key('exec.bar')));
      final Rect fill = tester.getRect(find.byKey(const Key('exec.bar.fill')));
      expect(fill.height, 3);
      expect(fill.left, closeTo(22, .5));
      // 条的宽度由右边文案撑）——所以只断言"填充占整条的比例"，与字体无关
      expect(fill.width / bar.width, closeTo(7 / 45, .01));
    });

    testWidgets('超时前 85% 不进入 warn，超过则变白（`.ex-t.warn`）', (
      WidgetTester tester,
    ) async {
      await _mount(
        tester,
        const ExecPanel(
          quest: Quest.demo,
          elapsed: Duration(minutes: 40), // 40/45 = 88.9% > 85%
          critChance: .12,
          itemCount: 0,
          evidenceCount: 0,
        ),
      );
      final Text t = tester.widget<Text>(
        find.byWidgetPredicate((Widget w) => w is Text && w.data == '40:00'),
      );
      expect(t.style?.color, Colors.white);
      expect(find.text('道具'), findsOneWidget); // 道具数为 0 时不显数字
      expect(find.text('0'), findsNothing);
    });

    testWidgets('不可见时不占位', (WidgetTester tester) async {
      await _mount(
        tester,
        const ExecPanel(
          quest: Quest.demo,
          elapsed: Duration(minutes: 7),
          critChance: .12,
          itemCount: 0,
          evidenceCount: 0,
          visible: false,
        ),
      );
      expect(find.byKey(const Key('exec.col')), findsNothing);
    });
  });
}
