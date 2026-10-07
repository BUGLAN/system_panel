import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/main.dart';

void main() {
  group('环境自检页', () {
    testWidgets('渲染三套字体且各自 fontFamily 正确', (WidgetTester tester) async {
      await tester.pumpWidget(const SystemPanelApp());

      final Text title = tester.widget<Text>(find.text('环境自检 · 字体三件套'));
      expect(title.style?.fontFamily, 'NotoSansSC');

      final Text rajdhani = tester.widget<Text>(find.text('LV.07 · EXP 1,240'));
      expect(rajdhani.style?.fontFamily, 'Rajdhani');

      final Text noto = tester.widget<Text>(find.text('宿主已绑定无限变强系统。'));
      expect(noto.style?.fontFamily, 'NotoSansSC');
      expect(noto.style?.fontVariations, isNotNull);

      final Text mono = tester.widget<Text>(find.text('01:24:07 · 六维 力敏体智知魅'));
      expect(mono.style?.fontFamily, 'JetBrainsMono');

      expect(tester.takeException(), isNull);
    });

    testWidgets('背景是锁定的深蓝虚空 #0A0E1A', (WidgetTester tester) async {
      await tester.pumpWidget(const SystemPanelApp());
      final Scaffold scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor ?? Hud.voidBg, Hud.voidBg);
    });
  });

  group('主题色锁定', () {
    test('锁定色值未被改动', () {
      expect(Hud.voidBg.toARGB32(), 0xFF0A0E1A);
      expect(Hud.cyan.toARGB32(), 0xFF38E1FF);
      expect(Hud.dim.toARGB32(), 0xFF9AA3B2);
    });
  });
}
