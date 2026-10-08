import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/data/format.dart';
import 'package:system_panel/stage/camera.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/widgets/main_view.dart';
import 'package:system_panel/widgets/ring_labels.dart';
import 'package:system_panel/widgets/ring_tag.dart';

/// 主线全景（抬头 / 环挂签 / 详情卡 / 底部两颗）。
/// 坐标断言来自运行中原型的实测值。
///
/// ⚠️ 这块面板是按百分比/相机数学定位的，必须用 `tester.view` 设尺寸
/// （`setSurfaceSize` 不改 MediaQuery，见 app/PORTING-NOTES.md 第 13 条）。
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
  group('主线数据', () {
    test('8 环，第 5 环脚下', () {
      final Goal g = Goal.demo();
      expect(g.rings.length, 8);
      expect(g.doneCount, 4);
      expect(g.currentIndex, 4);
      expect(g.rings[4].short, '五公里');
      expect(g.rings[7].finalRing, isTrue);
      expect(g.startedText, matches(RegExp(r'^\d+ 月 \d+ 日$')));
    });

    test('三种状态各自的说法', () {
      final Goal g = Goal.demo();
      expect(g.rings[0].statusText(), startsWith('已完成 · '));
      expect(g.rings[0].statusText(), contains('用时 11 分 56 秒'));
      expect(g.rings[4].statusText(), '你在这一环');
      expect(g.rings[5].statusText(), '未解锁');
      expect(RingState.of('cur'), RingState.cur);
      expect(RingState.of('nonsense'), RingState.lock);
    });

    test('fmtDur 四档（util.js L37）', () {
      expect(fmtDur(const Duration(seconds: 42)), '42 秒');
      expect(fmtDur(const Duration(minutes: 5)), '5 分');
      expect(fmtDur(const Duration(minutes: 11, seconds: 56)), '11 分 56 秒');
      expect(fmtDur(const Duration(hours: 2)), '2 小时');
      expect(fmtDur(const Duration(days: 3)), '3 天');
    });
  });

  group('相机数学（stage.js L252-380）', () {
    test('camFit 与 full 相机', () {
      expect(Cam.camFit(844), closeTo(844 / 1.9499558739357568, 1e-9));
      final Cam full = Cam.byName('full');
      expect(full.scale(844), closeTo(844 / 1.9499558739357568 * .68, 1e-9));
      expect(Cam.byName('不存在的相机').s, .92); // 退回 lobby
    });

    test('第 1 环的右端点与原型实测一致', () {
      const Size s = Size(390, 844);
      final RingGeom g0 = RingGeom.of(0, 8, finalRing: false);
      expect(g0.rx, closeTo(.30, 1e-9));
      expect(g0.ry, closeTo(-1.311338876207752, 1e-9));
      final Offset p = g0.point('full', s);
      // 原型 getBoundingClientRect 实测：(267.697, 616.736)
      expect(p.dx, closeTo(267.70, .05));
      expect(p.dy, closeTo(616.74, .05));
    });

    test('她头顶那一环是特例', () {
      const Size s = Size(390, 844);
      final RingGeom gf = RingGeom.of(7, 8, finalRing: true);
      expect(gf.rx, .42);
      expect(gf.ry, closeTo(.6386169977280048, 1e-9)); // NY.hair + .20
      final Offset p = gf.point('full', s);
      expect(p.dx, closeTo(303.02, .05));
      expect(p.dy, closeTo(42.82, .05));
    });
  });

  group('主线面板', () {
    testWidgets('抬头 + 详情卡 + 两颗按钮', (WidgetTester tester) async {
      final Goal g = Goal.demo();
      await _mount(tester, MainView(goal: g, selected: 4, canDispatch: true));
      expect(find.text('MAINLINE · 主线'), findsOneWidget);
      expect(find.text('三个月跑完半马'), findsOneWidget);
      expect(find.textContaining('4'), findsWidgets);
      expect(find.textContaining('/ 8 环 · 起于'), findsWidgets);
      expect(find.text('RING 5 · C 级'), findsOneWidget);
      expect(find.text('跑完 5 公里'), findsOneWidget);
      expect(find.textContaining('你在这一环'), findsWidgets);
      expect(find.textContaining('证明：跑步 App 截图 · 时限 45 分钟'), findsWidgets);
      expect(find.text('让她派这一环'), findsOneWidget);
      expect(find.text('换目标'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('没展开时只有抬头，不给详情卡', (WidgetTester tester) async {
      await _mount(tester, MainView(goal: Goal.demo()));
      expect(find.byKey(const Key('main.detail')), findsNothing);
      expect(find.text('换目标'), findsOneWidget);
    });

    testWidgets('不给派单时只剩「换目标」', (WidgetTester tester) async {
      await _mount(tester, MainView(goal: Goal.demo(), canDispatch: false));
      expect(find.byKey(const Key('main.dispatch')), findsNothing);
      expect(find.text('换目标'), findsOneWidget);
    });

    testWidgets('「换目标」可点（D5：main.dart 由此唤起小祥对话）', (WidgetTester tester) async {
      final List<int> taps = <int>[];
      await _mount(
        tester,
        MainView(goal: Goal.demo(), onNewGoal: () => taps.add(1)),
      );
      await tester.tap(find.byKey(const Key('main.newGoal')));
      await tester.pump();
      expect(taps, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('抬头与详情卡落在实测坐标上', (WidgetTester tester) async {
      await _mount(tester, MainView(goal: Goal.demo(), selected: 4));
      final Rect top = tester.getRect(find.byKey(const Key('main.top')));
      expect(top.left, 20);
      expect(top.right, 370);
      expect(top.top, 22);
      final Rect close = tester.getRect(find.byKey(const Key('main.close')));
      expect(close.size, const Size(38, 38));
      expect(close.right, closeTo(370, .5));
      final Rect detail = tester.getRect(find.byKey(const Key('main.detail')));
      expect(detail.left, 20);
      expect(detail.right, 370);
      expect(detail.bottom, closeTo(752, .5)); // bottom 92
      final Rect low = tester.getRect(find.byKey(const Key('main.low')));
      expect(low.bottom, closeTo(818, .5)); // bottom 26
      final Rect ghost = tester.getRect(find.byKey(const Key('main.newGoal')));
      expect(ghost.height, 54);
      expect(ghost.bottom, closeTo(818, .5));
    });
  });

  group('环挂签', () {
    testWidgets('八条挂签，位置由相机数学给出', (WidgetTester tester) async {
      await _mount(tester, RingLabels(goal: Goal.demo()));
      for (int i = 0; i < 8; i++) {
        expect(find.byKey(Key('ring.label.$i')), findsOneWidget);
      }
      // 原型实测：R1 [272,610,100,14]（左 = 环位 x + 4、垂直居中）
      final Rect l0 = tester.getRect(find.byKey(const Key('ring.label.0')));
      expect(l0.left, closeTo(271.7, .5));
      expect(l0.center.dy, closeTo(616.74, .5));
      // ★ 她头顶那一环 [307,35,81,16]
      final Rect l7 = tester.getRect(find.byKey(const Key('ring.label.7')));
      expect(l7.left, closeTo(307.02, .5));
      expect(l7.center.dy, closeTo(42.82, .5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('点挂签能回报是第几环', (WidgetTester tester) async {
      int? picked;
      await _mount(
        tester,
        RingLabels(goal: Goal.demo(), onPick: (int i) => picked = i),
      );
      final Rect l4 = tester.getRect(find.byKey(const Key('ring.label.4')));
      await tester.tapAt(l4.center);
      await tester.pump();
      expect(picked, 4);
    });

    testWidgets('收起来时不偷点击', (WidgetTester tester) async {
      int hits = 0;
      await _mount(
        tester,
        Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => hits++,
                child: const SizedBox.expand(),
              ),
            ),
            RingLabels(
              goal: Goal.demo(),
              visible: false,
              onPick: (int i) => hits += 100,
            ),
          ],
        ),
      );
      await tester.tapAt(const Offset(300, 616));
      await tester.pump();
      expect(hits, 1);
    });
  });
  // ── 当前环的挂签（大厅里挂在她脚下那一环的右端）────────────────
  // 出处：app.css L128-138 `.ringtag`；落点由 Flow.place() 给：
  //   translate(round(p.x+4), round(p.y-14))，p = Stage.ringPoint(curRing, 1)
  //   用的是**大厅相机**（不是全景那套），实测 tag [305,387,69,44]。
  group('当前环挂签', () {
    testWidgets('落点是环位 +4 / −14，用的是大厅相机', (WidgetTester tester) async {
      await _mount(tester, RingTag(goal: Goal.demo()));
      // 大厅相机下的第 5 环：ringPoint(4,1) = (301.19, 400.61)
      final Offset p = RingGeom.of(
        4,
        8,
        finalRing: false,
      ).point('lobby', kDesign);
      expect(p.dx, closeTo(301.19, .01));
      expect(p.dy, closeTo(400.61, .01));
      final Rect tag = tester.getRect(find.byKey(const Key('ringTag')));
      expect(tag.left, closeTo(305, .01)); // round(301.19 + 4)
      expect(tag.top, closeTo(387, .01)); // round(400.61 - 14)
      // 宽高与字体有关（flutter test 用占位字体，每个字都是 1em 宽），
      // 按约定只断言与字体无关的坐标 —— 尺寸由实机比对把关
    });

    testWidgets('三行内容：主线 / R5/8 / 五公里', (WidgetTester tester) async {
      await _mount(tester, RingTag(goal: Goal.demo()));
      expect(find.text('主线'), findsOneWidget);
      expect(find.textContaining('R5'), findsWidgets);
      expect(find.textContaining('/8'), findsWidgets);
      expect(find.text('五公里'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('字幕在的时候暗到 18%', (WidgetTester tester) async {
      await _mount(tester, RingTag(goal: Goal.demo(), dimmed: true));
      // 断言 AnimatedOpacity 的目标值，不断言渲染出来的 Opacity
      // （ImplicitlyAnimatedWidget 内部是 FadeTransition，树里没有 Opacity）
      final AnimatedOpacity op = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(RingTag),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(op.opacity, .18);
    });

    testWidgets('点它进主线全景', (WidgetTester tester) async {
      int taps = 0;
      await _mount(tester, RingTag(goal: Goal.demo(), onTap: () => taps++));
      await tester.tap(find.byKey(const Key('ringTag')));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('收起来时不偷点击', (WidgetTester tester) async {
      int hits = 0;
      await _mount(
        tester,
        Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => hits++,
                child: const SizedBox.expand(),
              ),
            ),
            RingTag(
              goal: Goal.demo(),
              visible: false,
              onTap: () => hits += 100,
            ),
          ],
        ),
      );
      await tester.tapAt(const Offset(320, 400));
      await tester.pump();
      expect(hits, 1);
    });
  });
}
