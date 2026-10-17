import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/state/voice.dart';
import 'package:system_panel/widgets/voice_bars.dart';

/// docs/39 §5.5 性能收口：`VoiceBars` 原来是**常驻 60fps Ticker**
/// （只有 `enabled=false` 才停）—— 这排条挂在每一页的字幕带上，她一个字
/// 都没说的时候也在满帧刷五根 2px 的条。现在改成：
///   · 说话中（包络目标抬起来 / 还没落回去）→ 60fps Ticker（公式照旧）；
///   · 没台词 → Ticker **停**，换一条不产帧的探针等下一个字；
///   · 说完落回静止 → 画面与旧版逐像素相同（五根都是 .14 定高）。
///
/// 这里用 `transientCallbackCount` 钉「ticker 真的停了」：一个活跃的 Ticker
/// 会常驻一个 frame callback，停掉之后计数归零。
void main() {
  /// 第 i 根条的实际高度（= 12 × scaleY；量 Container 的渲染尺寸最稳）
  double barHeight(WidgetTester tester, int i) =>
      tester.getSize(find.byType(Container).at(i)).height;

  Widget mount(VoiceEnvelope voice, {bool enabled = true}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: VoiceBars(
          voice: voice,
          color: const Color(0xFF38E1FF),
          enabled: enabled,
        ),
      ),
    ),
  );

  testWidgets('没台词：Ticker 不跑（0 个 frame callback），五根条是静止高度', (
    WidgetTester tester,
  ) async {
    final VoiceEnvelope v = VoiceEnvelope();
    await tester.pumpWidget(mount(v));
    await tester.pump();

    expect(
      tester.binding.transientCallbackCount,
      0,
      reason: '没在说话时不该有常驻 ticker（原来这条恒为 1）',
    );
    // 静止 = VoiceEnvelope.barScale(i, 0, t) = .14 → 12 × .14 = 1.68
    for (int i = 0; i < 5; i++) {
      expect(
        barHeight(tester, i),
        closeTo(12 * .14, .01),
        reason: '静止高度必须是 .14（与旧版一致）',
      );
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('开口：Ticker 立刻接手，波形条动起来', (WidgetTester tester) async {
    final VoiceEnvelope v = VoiceEnvelope();
    await tester.pumpWidget(mount(v));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);

    v.syllable('字'); // 打字机把目标抬起来（这里是同一条链路的下游）
    await tester.pump(const Duration(milliseconds: 50)); // 探针一拍发现
    expect(
      tester.binding.transientCallbackCount,
      greaterThan(0),
      reason: '有台词时必须回到 60fps（探针只负责发现"开始了"）',
    );
    expect(v.mouth, greaterThan(0));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('说完：mouth 落回 0 之后 Ticker 自己停（不再满帧跑）', (
    WidgetTester tester,
  ) async {
    final VoiceEnvelope v = VoiceEnvelope();
    v.syllable('字');
    await tester.pumpWidget(mount(v));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    v.hush();
    // 指数逼近：1 秒后 mouth < .02（voice_test 同口径），这里推 1.2s 更稳
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      tester.binding.transientCallbackCount,
      0,
      reason: '说完之后不该继续 60fps（探针不产帧）',
    );
    expect(v.mouth, 0, reason: '落底后要精确归零，与旧版静止态一致');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('enabled=false：完全静态（不跑 ticker、也不留探针）', (
    WidgetTester tester,
  ) async {
    final VoiceEnvelope v = VoiceEnvelope()..syllable('字');
    await tester.pumpWidget(mount(v, enabled: false));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.binding.transientCallbackCount, 0);
    expect(
      barHeight(tester, 0),
      closeTo(12 * .15, .01),
      reason: 'enabled=false 的静态高度 .15 照旧',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
