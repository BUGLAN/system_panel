import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/widgets/ask_field.dart';

/// 终端式输入（`#ask`）+ **键盘态**的布局约定（2026-10-11 宿主验收「换目标 UI 重合」）。
///
/// 背景（见 main.dart 的 `resizeToAvoidBottomInset` 注释）：
/// 舞台的矩形是按 LayoutBuilder 的可用高度算的 —— 键盘一弹、整屏一缩，矩形尺寸
/// 就变，插件 iOS 侧会重建 FBO（排空渲染队列）+ 她整条位移；而环场/命中层用的是
/// `MediaQuery.sizeOf`（整窗高），于是"她"和"环"还会错位。
/// 所以主 Scaffold 用 `resizeToAvoidBottomInset: false`，输入框自己抬到键盘之上。
///
/// 这个测试把这两条约定钉死：键盘高度必须传得到 body、输入框必须整体在键盘之上。
///
/// ⚠️ 尺寸一律用 `tester.view.physicalSize + devicePixelRatio`（不是
///    `setSurfaceSize`）—— 后者只改 surface、**不改 MediaQuery**，于是组件里
///    读到的还是 800×600（docs/39 H-08 的 clamp 上界就被它坑过 784pt）。
void main() {
  const Size kDesign = Size(390, 844);
  const double kKeyboard = 336;

  testWidgets('键盘弹起：body 不吃键盘缩屏，输入框抬到键盘之上', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    tester.view.viewInsets = const FakeViewPadding(bottom: kKeyboard * 3);
    addTearDown(tester.view.reset);

    double bodyHeight = -1;
    double seenInset = -1;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // 主 Scaffold 就是这么配的（main.dart）
          resizeToAvoidBottomInset: false,
          body: LayoutBuilder(
            builder: (BuildContext ctx, BoxConstraints c) {
              bodyHeight = c.maxHeight;
              seenInset = MediaQuery.viewInsetsOf(ctx).bottom;
              return Stack(
                children: <Widget>[
                  AskField(
                    prompt: '新目标 ›',
                    visible: true,
                    presets: const <String>['考研上岸'],
                    bottomInset: seenInset,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    // ① 键盘高度在 body 里看得见（Scaffold 只在 resize=true 时才摘掉 bottom inset）
    expect(seenInset, closeTo(kKeyboard, .5));
    // ② body 高度仍是整窗高 —— 舞台矩形不会因为键盘改变尺寸（否则插件重建 FBO）
    expect(bodyHeight, closeTo(kDesign.height, .5));
    // ③ 输入框（含预设词）整体落在键盘顶边之上，不会被键盘挡住
    final Rect r = tester.getRect(find.byType(AskField));
    expect(
      r.bottom,
      lessThanOrEqualTo(kDesign.height - kKeyboard + .5),
      reason: '输入框底边必须高于键盘顶边（bottom: 34 + viewInsets）',
    );
    expect(r.top, greaterThan(0));
  });

  testWidgets('没有键盘时：输入框贴底 34（原型 #ask 的位置不变）', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[AskField(prompt: '目标 ›', visible: true)],
          ),
        ),
      ),
    );
    await tester.pump();

    final Rect r = tester.getRect(find.byType(AskField));
    expect(r.bottom, closeTo(kDesign.height - 34, .5));
  });

  // docs/39 H-17 · 底部安全区：底边取 `math.max(34, MediaQuery.padding.bottom)`
  // 的**下限**，不是把 34 和安全区叠加（那样有手势条的机器会平白高 34pt，
  // 宿主说的"不改 MuMu 观感"就是这条）。
  group('H-17 底部安全区', () {
    Future<Rect> mountWithBottomPadding(
      WidgetTester tester,
      double bottomPadding,
    ) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      tester.view.padding = FakeViewPadding(bottom: bottomPadding * 3);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[AskField(prompt: '目标 ›', visible: true)],
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.getRect(find.byType(AskField));
    }

    testWidgets('无手势条（padding.bottom = 0）：仍是 34，观感不变', (
      WidgetTester tester,
    ) async {
      final Rect r = await mountWithBottomPadding(tester, 0);
      expect(r.bottom, closeTo(kDesign.height - 34, .5));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('iPhone 手势条（padding.bottom = 34）：max(34, 34) = 34，不叠加', (
      WidgetTester tester,
    ) async {
      final Rect r = await mountWithBottomPadding(tester, 34);
      expect(r.bottom, closeTo(kDesign.height - 34, .5));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('更大的安全区（padding.bottom = 48）：抬到 48', (
      WidgetTester tester,
    ) async {
      final Rect r = await mountWithBottomPadding(tester, 48);
      expect(r.bottom, closeTo(kDesign.height - 48, .5));
      await tester.pumpWidget(const SizedBox());
    });
  });

  // docs/39 M-24 · 换目标：牌列**不再有取消牌**。
  //
  // 走查图 04/08：CANCEL 是牌列最右一张、被 430 屏宽裁掉一半；键盘一弹整条牌列
  // 连布局都不占，取消彻底消失。现在取消 = 输入幕左上那颗常驻 44 圆（挂 main.dart），
  // 牌列只负责预设 / 入口牌 —— 绑定仪式本来就该没有取消。
  group('M-24 换目标：牌列不再出取消牌', () {
    testWidgets('预设 + 入口牌就是全部；没有「算了，不换」那一张', (WidgetTester tester) async {
      int cancels = 0;
      int entries = 0;
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                AskField(
                  prompt: '新目标 ›',
                  visible: true,
                  presets: const <String>['考研上岸', '一个月早睡早起'],
                  onEntry: () => entries++,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // 牌列在：两张预设 + 一张入口牌
      expect(find.byKey(const Key('ask.presets')), findsOneWidget);
      expect(find.byKey(const Key('table.card.preset.0')), findsOneWidget);
      expect(find.byKey(const Key('table.card.preset.1')), findsOneWidget);
      expect(find.byKey(const Key('table.card.preset.entry')), findsOneWidget);
      // 取消牌真的没了（文本与 key 两条都钉）
      expect(find.text('算了，不换'), findsNothing);
      expect(find.textContaining('CANCEL'), findsNothing);
      expect(find.byKey(const Key('table.card.preset.cancel')), findsNothing);

      // 入口牌仍然可点（证明牌列的分派没被拆坏）。
      // ⚠️ 牌桌纪律：点**侧牌只送位、不落定**（kCardSideTapCommits = false），
      //    所以要「先把它送到领位、再点领位」才是点中了。入口牌挂在最右，默认不是领位。
      await tester.tap(find.byKey(const Key('table.card.preset.entry')));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(find.byKey(const Key('table.card.preset.entry')));
      await tester.pump(const Duration(milliseconds: 700));
      expect(entries, 1);
      expect(cancels, 0);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('没有 onEntry 时牌列只有预设（绑定仪式的形态，没有取消）', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                AskField(
                  prompt: '目标 ›',
                  visible: true,
                  presets: <String>['三个月跑完半马'],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('算了，不换'), findsNothing);
      expect(find.byKey(const Key('table.card.preset.cancel')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
