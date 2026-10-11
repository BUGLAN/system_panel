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

  testWidgets('没有键盘时：输入框贴底 34（原型 #ask 的位置不变）', (
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
              AskField(prompt: '目标 ›', visible: true),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final Rect r = tester.getRect(find.byType(AskField));
    expect(r.bottom, closeTo(kDesign.height - 34, .5));
  });
}
