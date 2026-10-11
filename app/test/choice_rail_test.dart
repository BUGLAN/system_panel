import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/widgets/choices.dart';

/// 乙 · 铭牌轨（回应）—— 横排错位斜切铭牌。
/// 坐标按 390×844 设计基准（与 fail_test 的「回应按钮」分组同源）。
///
/// 几何真值（choice_rail.dart 的常量段）：
///   卡 268×58 · 斜切 12 · 领位抬起 8 · 让位每格缩进 14 / 下沉 6·9 / 压暗 .5·.42
///   轨高 78（8 + 58 + 12）· 外壳 left/right 20 · bottom 34 → 整体底 810
const Size kDesign = Size(390, 844);

Future<void> _mount(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(kDesign);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Stack(children: <Widget>[child])),
    ),
  );
  // 错峰入场（0/60/120ms + 420ms）走完再量
  await tester.pumpAndSettle();
}

/// 某张牌当前的不透明度（让位压暗 / 确认淡出都看它）。
/// 钥匙就挂在牌自己的 Opacity 上（挂在 Transform 里面才量得到位移）。
double _opacity(WidgetTester tester, int i) =>
    tester.widget<Opacity>(find.byKey(Key('choices.$i'))).opacity;

/// 记下确认，并**收下这一下**（`onPick` 现在要回执：false = 上层没接，
/// 整条轨保持原样，见 `widgets/choices.dart` 的 `ChoicePick`）。
ChoicePick _rec(List<int> picks) => (int i) {
  picks.add(i);
  return true;
};

const List<Choice> _two = <Choice>[Choice('……接。', main: true), Choice('今天算了。')];

const List<Choice> _three = <Choice>[
  Choice('再来一单。', main: true),
  Choice('先歇会儿。'),
  Choice('收工。'),
];

void main() {
  group('铭牌轨 · 形态', () {
    testWidgets('领位左对齐到边 + 抬起，让位向右阶梯缩进 + 下沉 + 压暗', (WidgetTester tester) async {
      await _mount(tester, const Choices(items: _two));

      final Rect lead = tester.getRect(find.byKey(const Key('choices.0')));
      final Rect side = tester.getRect(find.byKey(const Key('choices.1')));

      // 领位：左对齐到边（left 20）+ 抬起 8px（在轨内 y=0）
      expect(lead.left, 20);
      expect(lead.width, 268); // 横版薄牌
      expect(lead.height, 58);
      // 让位：向右缩进 14px + 下沉 6px（视觉上就是「抬起 8 + 下沉 6」= 14）
      expect(side.left, 34);
      expect(side.top, lead.top + 14);
      expect(_opacity(tester, 0), 1); // 领位满亮
      expect(_opacity(tester, 1), closeTo(.5, 1e-6)); // 让位压暗 .5
    });

    testWidgets('3 条时按距离递减的阶梯缩进', (WidgetTester tester) async {
      await _mount(tester, const Choices(items: _three));

      final Rect r0 = tester.getRect(find.byKey(const Key('choices.0')));
      final Rect r1 = tester.getRect(find.byKey(const Key('choices.1')));
      final Rect r2 = tester.getRect(find.byKey(const Key('choices.2')));

      expect(r0.left, 20); // 领位
      expect(r1.left, 34); // +14
      expect(r2.left, 48); // +28
      expect(r1.top, greaterThan(r0.top)); // 下沉分级
      expect(r2.top, greaterThan(r1.top));
      expect(_opacity(tester, 0), 1);
      expect(_opacity(tester, 1), closeTo(.5, 1e-6));
      expect(_opacity(tester, 2), closeTo(.42, 1e-6));
    });

    testWidgets('只剩 1 条（收工。）时居中，不孤零零贴角落', (WidgetTester tester) async {
      await _mount(
        tester,
        const Choices(items: <Choice>[Choice('收工。', main: true)]),
      );

      final Rect box = tester.getRect(find.byKey(const Key('choices')));
      final Rect only = tester.getRect(find.byKey(const Key('choices.0')));
      expect(only.width, 268); // 卡形不变
      expect(only.center.dx, closeTo(box.center.dx, .5)); // 居中
      expect(only.left, greaterThan(20)); // 不贴左边
      expect(find.text('宿主'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('铭牌轨 · 交互', () {
    testWidgets('滑动换领位：整叠刚性平移，新领位仍左对齐到边', (WidgetTester tester) async {
      await _mount(tester, Choices(items: _two, onPick: (int _) => true));
      expect(tester.getRect(find.byKey(const Key('choices.0'))).left, 20);

      // 一格 stride = 96，向左拖 120 → 领位 +1
      await tester.drag(
        find.byKey(const Key('choices')),
        const Offset(-120, 0),
      );
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byKey(const Key('choices.1'))).left, 20);
      expect(tester.getRect(find.byKey(const Key('choices.0'))).left, 6); // -14
      expect(tester.getRect(find.byKey(const Key('choices.1'))).top, 732);
      expect(_opacity(tester, 1), 1);
      expect(_opacity(tester, 0), closeTo(.5, 1e-6));
    });

    testWidgets('点侧牌 → 它变领位（送位），不顺手确认', (WidgetTester tester) async {
      final List<int> picks = <int>[];
      await _mount(tester, Choices(items: _two, onPick: _rec(picks)));

      // 让位牌只露出 L 形一条边：右 14px + 下 14px（领位下沿 790 之下）
      await tester.tapAt(const Offset(150, 797));
      await tester.pumpAndSettle();

      expect(picks, isEmpty); // 送位 ≠ 确认
      expect(tester.getRect(find.byKey(const Key('choices.1'))).left, 20);
      expect(tester.getRect(find.byKey(const Key('choices.0'))).left, 6);
      expect(_opacity(tester, 1), 1);
    });

    testWidgets('点领位牌 → 确认一次，并向左滑出 28px', (WidgetTester tester) async {
      final List<int> picks = <int>[];
      await _mount(tester, Choices(items: _two, onPick: _rec(picks)));

      await tester.tapAt(
        tester.getRect(find.byKey(const Key('choices.0'))).center,
      );
      await tester.pumpAndSettle();

      expect(picks, <int>[0]);
      expect(
        tester.getRect(find.byKey(const Key('choices.0'))).left,
        -8,
      ); // 20 - 28
      expect(_opacity(tester, 0), 0); // 淡出
    });

    testWidgets('_locked：连点两次只确认一次（一声 choose / 一次回调）', (
      WidgetTester tester,
    ) async {
      // ⚠️ 音效与震动在 widget 测试里没有可观察通道（audioplayers 的
      //    event channel 带随机 playerId，仓库也没有 mock 先例），
      //    所以这里用 onPick 回调次数证明「确认那一下只发生一次」——
      //    Sfx.play('choose') / Haptics.buzz('choose') 与 onPick 同在
      //    Choices._confirm 的同一道 _locked 守卫块里，一次即一次。
      final List<int> picks = <int>[];
      await _mount(tester, Choices(items: _two, onPick: _rec(picks)));
      final Offset at = tester
          .getRect(find.byKey(const Key('choices.0')))
          .center;

      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tapAt(at);
      await tester.pumpAndSettle();

      expect(picks, <int>[0]);
    });

    testWidgets('上层没收这一下 → 不锁、牌不滑走、可以再点（2026-10-11 实机死局回归）', (
      WidgetTester tester,
    ) async {
      // 宿主原话：「此页面会卡死，没有返回的方法」。
      // 现场：回前台打招呼那 1~3 秒里 `_busy` 关着演出闸门，宿主点【……接。】，
      // `_onChoice` 旧版 `if (_busy) return` 直接走人 —— 但整条轨照旧
      // 「锁死 + 领位牌滑出淡出」：牌没了，剩下那张也被 `_locked` 吃掉，
      // 失败页再无出路。这条测试钉住新契约：**上层没收 = 什么都没发生**。
      int calls = 0;
      await _mount(
        tester,
        Choices(
          items: _two,
          onPick: (int _) {
            calls++;
            return false; // 上层没接（闸门关着）
          },
        ),
      );
      final Offset at = tester
          .getRect(find.byKey(const Key('choices.0')))
          .center;

      await tester.tapAt(at);
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(
        tester.getRect(find.byKey(const Key('choices.0'))).left,
        20,
      ); // 没滑走
      expect(_opacity(tester, 0), 1); // 没淡出
      expect(find.byKey(const Key('choices.1')), findsOneWidget); // 另一张还在

      // 闸门放开之后，同一下还能确认 —— 不是「点一次就作废」
      int taken = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                Choices(
                  items: _two,
                  onPick: (int _) {
                    taken++;
                    return true;
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(taken, 1);
      expect(
        tester.getRect(find.byKey(const Key('choices.0'))).left,
        -8,
      ); // 这回滑走了
    });

    testWidgets('收起来再张开 = 新一问：锁解开，可以再确认一次', (WidgetTester tester) async {
      final List<int> picks = <int>[];
      Widget build({required bool visible}) =>
          Choices(items: _two, visible: visible, onPick: _rec(picks));
      await _mount(tester, build(visible: true));
      await tester.tapAt(
        tester.getRect(find.byKey(const Key('choices.0'))).center,
      );
      await tester.pumpAndSettle();
      expect(picks, <int>[0]);

      // 收起来 → 再张开（同一份 label）→ 新一问
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(children: <Widget>[build(visible: false)]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Stack(children: <Widget>[build(visible: true)])),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(
        tester.getRect(find.byKey(const Key('choices.0'))).center,
      );
      await tester.pumpAndSettle();
      expect(picks, <int>[0, 0]);
    });
  });

  group('铭牌轨 · 收起', () {
    testWidgets('visible: false → 整叠向下 28px 淡出，且不接命中', (
      WidgetTester tester,
    ) async {
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
            const Choices(items: _two, visible: false),
          ],
        ),
      );

      final Rect box = tester.getRect(find.byKey(const Key('choices')));
      expect(box.top, closeTo(760, .5)); // 732 + 28
      expect(box.bottom, closeTo(838, .5));
      final FadeTransition fade = tester.widget<FadeTransition>(
        find
            .descendant(
              of: find.byKey(const Key('choices')),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, 0); // 300ms 淡出落终态

      // 点在最深那张牌的位置上（证明这一片确实断了命中）
      await tester.tapAt(const Offset(150, 800));
      await tester.pump();
      expect(hits, 1);
    });
  });
}
