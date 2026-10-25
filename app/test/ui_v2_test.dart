// docs/48「UI v2」回归：游戏按键 / 舞台光 / 卡片材质 / 画质档 / 音量档。
//
// 这几条守的是**性能与可测性的底线**，不是像素：
//  · 一次性动效必须能「安定」（pumpAndSettle 不挂死 = 没有无限循环）
//  · 减弱动态 / 省电档下舞台光不开逐帧 ticker
//  · 新材质参数全开 / 全关都不抛异常
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/agent/settings_store.dart';
import 'package:system_panel/design/fidelity.dart';
import 'package:system_panel/design/tokens.dart' hide StageAnchors;
import 'package:system_panel/stage/camera.dart';
import 'package:system_panel/stage/stage_aura.dart';
import 'package:system_panel/state/sfx.dart';
import 'package:system_panel/widgets/card_skins.dart';
import 'package:system_panel/widgets/game_button.dart';

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  bool reduce = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 844),
        disableAnimations: reduce,
      ),
      child: Directionality(textDirection: TextDirection.ltr, child: child),
    ),
  );
}

void main() {
  setUp(() {
    Sfx.enabled = false; // 测试里不出声
    Fidelity.lowPower.value = false;
  });

  group('GameButton（docs/48 §4）', () {
    testWidgets('高度守 56；点按触发；扫光与回弹都能安定（无循环动画）', (WidgetTester tester) async {
      int hits = 0;
      await _mount(
        tester,
        Center(
          child: SizedBox(
            width: 240,
            child: GameButton(
              key: const Key('gb'),
              label: '去执行',
              onTap: () => hits++,
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byKey(const Key('gb'))).height, 56);
      await tester.pumpAndSettle(); // 挂载扫光必须收口
      await tester.tap(find.byKey(const Key('gb')));
      await tester.pumpAndSettle(); // 抬起回弹必须收口
      expect(hits, 1);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('无回调 = 禁用态：不响应、不扫光', (WidgetTester tester) async {
      await _mount(
        tester,
        const Center(
          child: SizedBox(width: 240, child: GameButton(label: '今日休息')),
        ),
      );
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      await tester.tap(find.text('今日休息'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('文案变化补扫一次光，随后安定', (WidgetTester tester) async {
      Widget b(String l) => Center(
        child: SizedBox(
          width: 240,
          child: GameButton(label: l, onTap: () {}),
        ),
      );
      await _mount(tester, b('去执行'));
      await tester.pumpAndSettle();
      await _mount(tester, b('继续执行'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(find.text('继续执行'), findsOneWidget);
    });
  });

  group('StageAura 画质档（docs/48 §6）', () {
    final ValueNotifier<Cam> cam = ValueNotifier<Cam>(Cam.all['lobby']!);

    testWidgets('减弱动态：静态一帧，不开 ticker', (WidgetTester tester) async {
      await _mount(
        tester,
        SizedBox.expand(
          child: Stack(children: <Widget>[StageAura(cam: cam)]),
        ),
        reduce: true,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('省电档：不开逐帧循环；脉冲仍是一次性的', (WidgetTester tester) async {
      Fidelity.lowPower.value = true;
      addTearDown(() => Fidelity.lowPower.value = false);
      await _mount(
        tester,
        SizedBox.expand(
          child: Stack(children: <Widget>[StageAura(cam: cam)]),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isFalse);
      await _mount(
        tester,
        SizedBox.expand(
          child: Stack(children: <Widget>[StageAura(cam: cam, pulse: 1)]),
        ),
      );
      await tester.pumpAndSettle(); // 脉冲必须收口
      expect(tester.takeException(), isNull);
    });

    testWidgets('富效果：逐帧呼吸在跑（限 30fps 由实现保证）', (WidgetTester tester) async {
      await _mount(
        tester,
        SizedBox.expand(
          child: Stack(
            children: <Widget>[StageAura(cam: cam, mood: StageMood.reward)],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);
      // 卸载后 ticker 必须释放
      await tester.pumpWidget(const SizedBox());
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('卡片材质 v2（docs/48 §3）', () {
    test('GlassPainter 只在参数变化时重绘', () {
      const GlassPainter a = GlassPainter(lead: true, phase: 0, radius: 12);
      const GlassPainter b = GlassPainter(lead: true, phase: 0, radius: 12);
      expect(a.shouldRepaint(b), isFalse);
      expect(
        a.shouldRepaint(
          const GlassPainter(lead: true, phase: 0, radius: 12, foil: 1),
        ),
        isTrue,
      );
      expect(
        a.shouldRepaint(
          const GlassPainter(lead: true, phase: 0, radius: 12, shine: .5),
        ),
        isTrue,
      );
    });

    testWidgets('全开（箔 + 扫光 + 角标）/ 全关都能画', (WidgetTester tester) async {
      for (final GlassPainter p in const <GlassPainter>[
        GlassPainter(
          lead: true,
          phase: .6,
          radius: 14,
          accent: C.rS,
          foil: 1,
          shine: .5,
        ),
        GlassPainter(lead: false, phase: 0, radius: 8, ornament: false),
      ]) {
        await _mount(
          tester,
          Center(
            child: SizedBox(
              width: 200,
              height: 292,
              child: CustomPaint(painter: p),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('设置：画质档 / 界面音量（docs/48 §5 §6）', () {
    test('默认 = 高画质 + 中音量；JSON 往返不丢', () {
      const AgentSettings d = AgentSettings();
      expect(d.fidelity, 'high');
      expect(d.sfxVol, 'mid');
      final AgentSettings low = d.copyWith(fidelity: 'low', sfxVol: 'lo');
      final AgentSettings back = AgentSettings.fromJson(
        low.toJson(),
        fallback: d,
      );
      expect(back.fidelity, 'low');
      expect(back.sfxVol, 'lo');
      expect(back, low);
    });

    test('音量档 → 增益单调递增', () {
      expect(AgentSettings.gainOf('lo'), lessThan(AgentSettings.gainOf('mid')));
      expect(AgentSettings.gainOf('mid'), lessThan(AgentSettings.gainOf('hi')));
      expect(AgentSettings.gainOf('???'), AgentSettings.gainOf('mid'));
    });

    test('音效规则表：过程类降音量且节流，落定类满音量', () {
      for (final MapEntry<String, SoundRule> e in SoundRule.cues.entries) {
        if (e.key.startsWith('card.commit') || e.key.startsWith('reward.')) {
          expect(e.value.gain, 1.0, reason: '${e.key} 是落定，满音量');
        } else {
          expect(e.value.gain, lessThan(1.0), reason: '${e.key} 是过程，降音量');
          expect(e.value.minGapMs, greaterThan(0), reason: '${e.key} 要节流');
        }
      }
      if (kDebugMode) expect(SoundRule.cues.containsKey('ui.tap'), isTrue);
    });
  });
}
