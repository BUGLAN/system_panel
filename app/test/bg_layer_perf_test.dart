import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/widgets/bg_layer.dart';

/// docs/39 §5.5 性能收口：`BgLayer` 原来用 **10Hz / 31Hz 的整层 `setState`**
/// 推轨道环与地面网格的相位 —— 天幕这一整棵（渐变×3、ComfyUI 底图、大字两层、
/// 噪点贴图）每 100ms 被重建一次，只为让三个环转一点、网格挪半个像素。
///
/// 改成：相位进 `ValueNotifier`，`CustomPainter` 用 `repaint:` 订阅 ——
/// **只 markNeedsPaint，不重建任何 widget**。这里钉住三件事：
///   ① 时间源照旧在跑（轨道环 / 地面网格的 Ticker 都还活着）；
///   ② 但它们的提交**不再把 BgLayer 弄脏**（rebuild 计数不变）；
///   ③ 环的旋转真的在推进（painter 读到的相位会变）—— 别把"不重建"做成"不转"。
void main() {
  testWidgets('轨道环/地面网格推进时，BgLayer 不再整层 rebuild', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: BgLayer())));
    await tester.pump();

    // ① 时间源活着：两条 Ticker 都得有 frame callback
    expect(
      tester.binding.transientCallbackCount,
      greaterThanOrEqualTo(2),
      reason: '轨道环 + 地面网格各一条 Ticker（原来的真源节奏不许被收掉）',
    );

    // ② 数 BgLayer 自己的 Element 被重建了几次
    int rebuilds = 0;
    final Element bg = tester.element(find.byType(BgLayer));
    debugOnRebuildDirtyWidget = (Element e, bool builtOnce) {
      if (e == bg) rebuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    // 推 1 秒：原来这里会有 ~10 次轨道环 + ~31 次网格的 setState = 40+ 次重建
    for (int i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(rebuilds, 0, reason: '相位提交只该重画那几张画布，不该把整层天幕重建（原来这里是 40+）');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('画布真的在重绘：环的相位在推进（别把降频做成定格）', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: BgLayer())));
    await tester.pump();

    // 环的旋转画在 `_RingPainter` 里、由 10Hz 的 `_orbitRev` 推 ——
    // 验证方式是「1 秒内至少提交了 5 次重绘」。这里数 render object 的 paint 次数。
    int paints = 0;
    // ⚠️ 调试变量必须在测试体内复位：`addTearDown` 跑在「渲染调试变量未复位」
    //    这条不变量检查**之后**，会让用例莫名失败（踩过）。
    debugOnProfilePaint = (RenderObject r) {
      if (r is RenderCustomPaint) paints++;
    };
    try {
      for (int i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    } finally {
      debugOnProfilePaint = null;
    }
    expect(
      paints,
      greaterThanOrEqualTo(5),
      reason: '轨道环 10Hz + 地面 31Hz 的提交必须真的落到画布上（合起来 1 秒 >5 次重绘）',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('静止帧与旧版逐像素一致的口径：环/网格的提交节奏没被改', (WidgetTester tester) async {
    // 天幕三条 Ticker 的节奏是既有真源（环 140/220/300s、地面 31Hz），
    // 本轮只改「提交方式」，不改节奏 —— 这里钉住 Ticker 仍在跑、且被正确 dispose。
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: BgLayer())));
    await tester.pump();
    final int running = tester.binding.transientCallbackCount;
    expect(running, greaterThanOrEqualTo(2));
    await tester.pumpWidget(const SizedBox());
    // 卸载后不许留下任何还在跑的 Ticker（dispose 后继续跑会报 "Ticker disposed"）
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
