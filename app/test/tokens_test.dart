import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/data/content.dart';
import 'package:system_panel/design/ref.dart';
import 'package:system_panel/design/tokens.dart';

// 原 boot_and_tokens_test.dart：2026-11-06 旧开机屏 BootScreen 已删（main.dart
// 早就改用 RefBoot，它不再渲染），只测它的 9 条 widget 测试与「字体族名」一条
// 随之删除；令牌与文案部分留下来改名为 tokens_test.dart。

void main() {
  group('视觉令牌 = 原型 app.css 的 :root', () {
    test('基底与主色逐个对齐', () {
      expect(C.voidBg.toARGB32(), 0xFF03060E); // --void
      expect(C.abyss.toARGB32(), 0xFF060F20); // --abyss
      expect(C.navy.toARGB32(), 0xFF0B1A36); // --navy
      expect(C.deep.toARGB32(), 0xFF021022); // --deep
      expect(C.blue.toARGB32(), 0xFF38E1FF); // --blue
      expect(C.blue2.toARGB32(), 0xFF1F8BFF); // --blue2
      expect(C.ice.toARGB32(), 0xFFE9FBFF); // --ice
      expect(C.mist.toARGB32(), 0xFF8FA6C4); // --mist
      expect(C.dim.toARGB32(), 0xFF4B5E7C); // --dim
      expect(C.line.toARGB32(), 0x4238E1FF); // rgba(56,225,255,.26)
      expect(C.line2.toARGB32(), 0x1F38E1FF); // rgba(56,225,255,.12)
    });

    test('稀有度色谱对齐', () {
      expect(C.rF.toARGB32(), 0xFF9AA3B2);
      expect(C.rE.toARGB32(), 0xFF4ADE80);
      expect(C.rD.toARGB32(), 0xFF38BDF8);
      expect(C.rC.toARGB32(), 0xFFA78BFA);
      expect(C.rB.toARGB32(), 0xFFFBBF24);
      expect(C.rA.toARGB32(), 0xFFFB923C);
      expect(C.rS.toARGB32(), 0xFFFF4D5E);
    });

    // 旧字体族 F（FangYuan 等）已撤出安装包；fs() 仍给聊天面板用，
    // 现在只会被喂 Ref 的三套字体 —— 可变字体的字重照样必须走 fontVariations。
    test('可变字体必须带 fontVariations，否则字重不生效', () {
      final TextStyle s = fs(family: Ref.fc, size: 17, wght: 500);
      expect(s.fontFamily, 'NotoSansSC');
      expect(s.fontVariations, contains(const FontVariation('wght', 500)));
      expect(s.fontWeight, isNull); // 不许靠 fontWeight
      expect(s.height, 1.2, reason: '不传行高就钉 1.2，不继承 Material 的 1.43');
    });

    test('背景大字字号按 setWord 的公式（拉丁 / 中文两套）', () {
      expect(WordSpec.fontSize('SYSTEM'), 93); // min(120, 560/6) = 93.33 → 93
      expect(
        WordSpec.fontSize('跑完半马', latin: false),
        90,
      ); // min(175, 360/4) = 90
      expect(WordSpec.isLatin('SYSTEM'), isTrue);
      expect(WordSpec.isLatin('跑完半马'), isFalse);
      expect(WordSpec.scale, 0.910);
    });
  });

  group('文案真源', () {
    test('开机日志条数与原型一致（v3 开机序列逐条读它）', () {
      expect(LINES.bootLog.length, 5);
      expect(LINES.bootLog[3], '链接宿主档案 …… {host}');
    });
  });
}
