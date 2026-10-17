import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:system_panel/main.dart';
import 'package:system_panel/widgets/fx_layer.dart';

/// docs/39 §5.5（宿主点名的坑）：**`FlashLayer` / `ShakeLayer` 的
/// `reduceMotion` 形参在调用点从来没传过** —— 两个组件内部早就写好了降级
/// （亮帧 alpha 砍半、震屏整个不抖），但 `main.dart` 挂载时不喂这个开关，
/// 于是「减弱动态效果」对亮帧和震屏完全无效。
///
/// 组件自身的降级行为由 `fx_test.dart` 钉住；这里钉的是**接线**：
/// 真开系统「减弱动态效果」时，App 里的这两个实例拿到的形参必须为 true。
///
/// 为什么敢整壳挂 `SysApp()`：这条接线只存在于真实装配里（`_AppShellState`
/// 的 build），任何"抽出来单独挂"的写法都测不到它。壳里的异步读档/设置/聊天
/// 都自带兜底（存储不可用 → 默认值），Live2D 的 `whenAttached` 在没有原生
/// 视图时永远不完成 —— 不产生 pending timer，也不阻塞这一条断言。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  /// 挂整壳；[reduce] = 系统是否开了「减弱动态效果」
  Future<void> mountApp(WidgetTester tester, {required bool reduce}) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: reduce);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(const SysApp());
    await tester.pump();
  }

  testWidgets('reduce 开：FlashLayer / ShakeLayer 都收到 reduceMotion: true', (
    WidgetTester tester,
  ) async {
    await mountApp(tester, reduce: true);

    final Finder flash = find.byType(FlashLayer);
    final Finder shake = find.byType(ShakeLayer);
    expect(flash, findsOneWidget, reason: '亮帧层必须挂在大厅壳里');
    expect(shake, findsOneWidget, reason: '震屏层必须挂在大厅壳里');
    expect(
      tester.widget<FlashLayer>(flash).reduceMotion,
      isTrue,
      reason: 'docs/39 §5.5：reduce 时亮帧强度要砍半（形参没接上就永远不砍）',
    );
    expect(
      tester.widget<ShakeLayer>(shake).reduceMotion,
      isTrue,
      reason: 'docs/39 §5.5：reduce 时震屏要整个不抖（形参没接上就照样抖）',
    );

    // 收干净：壳里有秒时钟与各层 ticker，别把 pending timer 留给下一条用例
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('默认路径：没开 reduce 时形参为 false —— 观感一个像素都不许变', (
    WidgetTester tester,
  ) async {
    await mountApp(tester, reduce: false);

    expect(
      tester.widget<FlashLayer>(find.byType(FlashLayer)).reduceMotion,
      isFalse,
    );
    expect(
      tester.widget<ShakeLayer>(find.byType(ShakeLayer)).reduceMotion,
      isFalse,
    );

    await tester.pumpWidget(const SizedBox());
  });
}
