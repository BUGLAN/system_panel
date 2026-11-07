import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:system_panel/main.dart';
import 'package:system_panel/state/sfx.dart';

/// G1.2「打开 App 会停掉用户正在听的歌」的回归网。
///
/// `flutter test` 里没有音频插件（Sfx 在总线层直接不碰播放器），所以这里钉的是
/// **判定**而不是声音：
///  1. 音频上下文的形状 —— iOS 走 ambient（跟随静音键、混音），Android 不申请焦点；
///  2. 生命周期 → 前后台的映射，以及「总开关 × 想要 × 前台」的底噪判定；
///  3. 「音效」关着时，回前台不恢复底噪（包括在后台里关掉的情形）；
///  4. main.dart 的 `didChangeAppLifecycleState` 真的把生命周期转给了 Sfx。
/// 真机上「别的 App 的歌没停 / 静音键生效 / 回桌面底噪停」只能实机验收。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Sfx 是全静态的：每条用例从「前台、不想要底噪、音效开」起步，收尾还原
  setUp(() async {
    Sfx.enabled = true;
    await Sfx.lifecycle(AppLifecycleState.resumed);
    await Sfx.ambient(false);
  });
  tearDown(() async {
    Sfx.enabled = true;
    await Sfx.lifecycle(AppLifecycleState.resumed);
    await Sfx.ambient(false);
  });

  group('音频上下文：不抢焦点、跟随静音键', () {
    test('iOS 用 ambient 类别（自带混音，不显式加 mixWithOthers）', () {
      final AudioContextIOS ios = Sfx.audioContext.iOS;
      expect(ios.category, AVAudioSessionCategory.ambient);
      // 平台接口断言：ambient 不许显式带 mixWithOthers / duckOthers
      expect(ios.options, isEmpty);
    });

    test('Android 不申请音频焦点，按游戏音效上报', () {
      final AudioContextAndroid a = Sfx.audioContext.android;
      expect(a.audioFocus, AndroidAudioFocus.none);
      expect(a.usageType, AndroidUsageType.game);
      expect(a.contentType, AndroidContentType.sonification);
      // 这两项会被插件**全局**写进 AudioManager，必须保持系统默认
      expect(a.isSpeakerphoneOn, isFalse);
      expect(a.audioMode, AndroidAudioMode.normal);
      expect(a.stayAwake, isFalse);
    });
  });

  group('生命周期 → 前后台', () {
    test('resumed 回前台；hidden / paused / detached 算后台；inactive 不改判断', () {
      expect(Sfx.foregroundOf(AppLifecycleState.resumed), isTrue);
      expect(Sfx.foregroundOf(AppLifecycleState.hidden), isFalse);
      expect(Sfx.foregroundOf(AppLifecycleState.paused), isFalse);
      expect(Sfx.foregroundOf(AppLifecycleState.detached), isFalse);
      expect(Sfx.foregroundOf(AppLifecycleState.inactive), isNull);
    });

    test('底噪判定：总开关 × 想要 × 前台，缺一不可', () {
      for (final bool e in <bool>[true, false]) {
        for (final bool w in <bool>[true, false]) {
          for (final bool f in <bool>[true, false]) {
            expect(
              Sfx.ambientShouldPlay(enabled: e, wanted: w, foreground: f),
              e && w && f,
              reason: 'enabled=$e wanted=$w foreground=$f',
            );
          }
        }
      }
    });
  });

  group('底噪跟随前后台', () {
    test('切后台停、回前台恢复（音效开着）', () async {
      await Sfx.ambient(true);
      expect(Sfx.ambientShouldPlayNow, isTrue);

      // 切后台：Flutter 依次给 inactive → hidden → paused
      await Sfx.lifecycle(AppLifecycleState.inactive);
      expect(Sfx.ambientShouldPlayNow, isTrue, reason: 'inactive 还看得见，不打断');
      await Sfx.lifecycle(AppLifecycleState.hidden);
      expect(Sfx.ambientShouldPlayNow, isFalse);
      await Sfx.lifecycle(AppLifecycleState.paused);
      expect(Sfx.ambientShouldPlayNow, isFalse);

      // 回前台：paused → hidden → inactive → resumed
      await Sfx.lifecycle(AppLifecycleState.hidden);
      await Sfx.lifecycle(AppLifecycleState.inactive);
      expect(Sfx.ambientShouldPlayNow, isFalse, reason: '还没 resumed 不提前出声');
      await Sfx.lifecycle(AppLifecycleState.resumed);
      expect(Sfx.ambientShouldPlayNow, isTrue);
    });

    test('音效关着：回前台不恢复底噪', () async {
      Sfx.enabled = false;
      await Sfx.ambient(false);
      await Sfx.lifecycle(AppLifecycleState.paused);
      await Sfx.lifecycle(AppLifecycleState.resumed);
      expect(Sfx.ambientShouldPlayNow, isFalse);
    });

    test('后台里把音效关掉：回前台按当时的设置，不恢复', () async {
      await Sfx.ambient(true);
      await Sfx.lifecycle(AppLifecycleState.paused);
      // 设置分发（main.dart `_applyAgentSettings`）的两步：先总开关，再底噪
      Sfx.enabled = false;
      await Sfx.ambient(false);
      await Sfx.lifecycle(AppLifecycleState.resumed);
      expect(Sfx.ambientShouldPlayNow, isFalse);
    });

    test('后台里打开音效：只记账不出声，回前台才响', () async {
      Sfx.enabled = false;
      await Sfx.ambient(false);
      await Sfx.lifecycle(AppLifecycleState.paused);
      Sfx.enabled = true;
      await Sfx.ambient(true);
      expect(Sfx.ambientShouldPlayNow, isFalse, reason: '后台里不许起播');
      await Sfx.lifecycle(AppLifecycleState.resumed);
      expect(Sfx.ambientShouldPlayNow, isTrue);
    });
  });

  testWidgets('主壳把生命周期转给 Sfx：切后台停底噪、回前台恢复', (WidgetTester tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SysApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    // 设置读完（默认「音效」开）→ 主壳已把底噪设为想要
    expect(Sfx.ambientShouldPlayNow, isTrue);

    // 按平台真实的过渡顺序逐个发（树上有 AppLifecycleListener，跳步会触发断言）
    Future<void> walk(List<AppLifecycleState> states) async {
      for (final AppLifecycleState s in states) {
        tester.binding.handleAppLifecycleStateChanged(s);
        await tester.pump();
      }
    }

    await walk(const <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
    expect(Sfx.ambientShouldPlayNow, isFalse);

    await walk(const <AppLifecycleState>[
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    expect(Sfx.ambientShouldPlayNow, isTrue);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
