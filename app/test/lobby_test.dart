import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/state/host_state.dart';
import 'package:system_panel/widgets/dock.dart';
import 'package:system_panel/widgets/hud.dart';
import 'package:system_panel/widgets/line_layer.dart';

/// 大厅页（HUD / 字幕 / 底栏）。
///
/// 这里的坐标断言全部来自**运行中的原型实测值**（getBoundingClientRect 换算到
/// #app 的逻辑坐标，390×844）。原型一改，这里必须跟着改 —— 这就是回归网。
///
/// ⚠️ `flutter test` 用的是占位字体：**每个字形都按 1em 宽**渲染，真实字体资产
/// 不参与排版。所以凡是"宽度由文字撑出来"的坐标（金币芯片的左缘、.cta-n 的宽度…）
/// 在单测里量不准，这里只断言与文字宽度无关的部分；真实字体的观感与坐标由
/// 真机截图 + 原型比对负责（见 .verify/step2-compare.png）。
const Size kDesign = Size(390, 844);

Future<void> _mount(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(kDesign);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Stack(children: <Widget>[child]))),
  );
  await tester.pump();
}

void main() {
  group('宿主档案', () {
    test('升级所需经验 = 60 + lv*40（store.js L5）', () {
      expect(HostState.need(1), 100);
      expect(HostState.need(7), 340);
    });

    test('演示档与原型「老宿主 · 第 23 天」一致', () {
      const HostState s = HostState.demo;
      expect(s.name, '林深');
      expect(s.lv, 7);
      expect(s.exp, 214);
      expect(s.coins, 340);
      expect(s.streak, 6);
      expect(s.title, '惯犯');
      expect(s.queue, 5);
      expect(s.expRatio, closeTo(214 / 340, 1e-9));
    });
  });

  group('HUD', () {
    testWidgets('名字 / 称号 / 连击 / 金币 / 等级都渲染', (WidgetTester tester) async {
      await _mount(tester, const Hud(state: HostState.demo));
      expect(find.text('林深'), findsOneWidget);
      expect(find.text('「惯犯」'), findsOneWidget);
      expect(find.text('340'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('LV'), findsOneWidget);
      expect(find.textContaining('连击'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('各件落在原型实测坐标上', (WidgetTester tester) async {
      await _mount(tester, const Hud(state: HostState.demo));
      // 原型实测：lv [16,23,46,46] · coin [261,31,69,30] · menu [340,29,34,34]
      expect(tester.getRect(find.byKey(const Key('hud.lv'))), const Rect.fromLTWH(16, 23, 46, 46));
      expect(tester.getRect(find.byKey(const Key('hud.menu'))), const Rect.fromLTWH(340, 29, 34, 34));
      final Rect coin = tester.getRect(find.byKey(const Key('hud.coin')));
      // 右缘由「菜单固定 34 + 间距 10 + 右边距 16」定死，与文字宽度无关
      expect(coin.right, closeTo(330, .5));
      expect(coin.top, 31);
      expect(coin.height, 30);
    });
  });

  group('底栏', () {
    testWidgets('三颗侧键 + 委托环 + 底注都在', (WidgetTester tester) async {
      await _mount(tester, const Dock(state: HostState.demo));
      expect(find.text('主线'), findsOneWidget);
      expect(find.text('档案'), findsOneWidget);
      expect(find.text('补给'), findsOneWidget);
      expect(find.text('委托'), findsOneWidget);
      expect(find.text('TASK'), findsOneWidget);
      expect(find.text('5'), findsOneWidget); // .cta-n 上的单数
      expect(find.text('她手里有 5 单'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('各件落在原型实测坐标上', (WidgetTester tester) async {
      await _mount(tester, const Dock(state: HostState.demo));
      // 原型实测：cta [268,712,104,104] · core [276,720,88,88]
      //           cta-n [346,714,24,24] · cap [268,823,104,13] · 侧键一 [18,749,58,63]
      expect(tester.getRect(find.byKey(const Key('dock.cta'))), const Rect.fromLTWH(268, 712, 104, 104));
      expect(tester.getRect(find.byKey(const Key('dock.cta.core'))), const Rect.fromLTWH(276, 720, 88, 88));
      // .cta-n 是 min-width:24 的胶囊：右/上/高与文字无关，宽度至少 24
      final Rect n = tester.getRect(find.byKey(const Key('dock.cta.n')));
      expect(n.right, closeTo(370, .5));
      expect(n.top, 714);
      expect(n.height, 24);
      expect(n.width, greaterThanOrEqualTo(24));
      final Rect cap = tester.getRect(find.byKey(const Key('dock.cap')));
      expect(cap.left, 268);
      expect(cap.width, 104);
      expect(cap.bottom, closeTo(836, .5));
      final Rect k1 = tester.getRect(find.byKey(const Key('dock.key.main')));
      expect(k1.left, 18);
      expect(k1.top, closeTo(749, 1));
      expect(k1.width, 58);
      final Rect k3 = tester.getRect(find.byKey(const Key('dock.key.supply')));
      expect(k3.left, 146);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('隐藏态整条底栏沉到屏幕外（app.css L211）', (WidgetTester tester) async {
      await _mount(tester, const Dock(state: HostState.demo, visible: false));
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.getRect(find.byKey(const Key('dock.cta'))).top, greaterThan(844));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('字幕', () {
    testWidgets('渲染文本 / SYSTEM / 情绪词，且落在实测坐标', (WidgetTester tester) async {
      await _mount(
        tester,
        const LineLayer(text: '我手里有 5 单。都是给你的。', mood: '尚可', y: 506.4),
      );
      expect(find.text('我手里有 5 单。都是给你的。'), findsOneWidget);
      expect(find.text('SYSTEM'), findsOneWidget);
      expect(find.textContaining('尚可'), findsWidgets);

      // 原型实测：line [20,506,350,71]
      final Rect line = tester.getRect(find.byKey(const Key('line')));
      expect(line.left, 20);
      expect(line.right, 370);
      expect(line.top, closeTo(506.4, .5));
      expect(line.height, closeTo(71, 1.5));
      await tester.pumpWidget(const SizedBox());
    });
  });
}
