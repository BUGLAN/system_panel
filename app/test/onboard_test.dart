import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/widgets/ask_field.dart';
import 'package:system_panel/widgets/banner.dart';

/// 绑定仪式（终端式输入）+ 横幅。
/// 坐标断言来自运行中原型的实测值。
///
/// ⚠️ 按百分比/贴底定位，必须用 `tester.view` 设尺寸（见 app/PORTING-NOTES.md 第 13 条）。
const Size kDesign = Size(390, 844);

const List<String> kPresets = <String>[
  '三个月跑完半马',
  '一个月早睡早起',
  '考研上岸',
  '半年减重 10 斤',
  '学会画画',
  '变优秀',
];

Future<void> _mount(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Stack(children: <Widget>[child])),
    ),
  );
  await tester.pump();
}

void main() {
  group('绑定仪式的输入框', () {
    testWidgets('提示词 / 占位符 / 确定键都在', (WidgetTester tester) async {
      await _mount(
        tester,
        const AskField(
          prompt: '目标 ›',
          placeholder: '比如：三个月跑完半马',
          presets: kPresets,
        ),
      );
      expect(find.text('目标 ›'), findsOneWidget);
      expect(find.text('比如：三个月跑完半马'), findsOneWidget);
      expect(find.text('确定'), findsOneWidget);
      for (final String p in kPresets) {
        expect(find.text(p), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('整块贴底 34，XS 微牌牌列 + 54 高的输入条', (WidgetTester tester) async {
      await _mount(
        tester,
        const AskField(
          prompt: '目标 ›',
          placeholder: '比如：三个月跑完半马',
          presets: kPresets,
        ),
      );
      final Rect ask = tester.getRect(find.byKey(const Key('ask')));
      expect(ask.left, 20);
      expect(ask.right, 370);
      expect(ask.bottom, closeTo(810, .5)); // bottom 34
      expect(ask.height, closeTo(232, .5)); // 牌列 166 + 12 + 54
      // 牌列 = CardTable（XS 微牌）：牌高 72 + topPad 26 + dy2 38 + 尾隙 30
      final Rect presets = tester.getRect(find.byKey(const Key('ask.presets')));
      expect(presets.left, 20); // 牌列铺满输入条那条轨（20 → 370）
      expect(presets.right, 370);
      expect(presets.height, closeTo(166, .5));
      final Rect submit = tester.getRect(find.byKey(const Key('ask.submit')));
      expect(submit.height, 42);
      expect(submit.right, closeTo(364, .5)); // 370 - 6
    });

    testWidgets('预设排成 XS 微牌，一张一张，不许被拉满', (WidgetTester tester) async {
      await _mount(
        tester,
        const AskField(
          prompt: '目标 ›',
          placeholder: '比如：三个月跑完半马',
          presets: kPresets,
        ),
      );
      // 牌桌给每张牌挂的 key 是 `table.card.<id>`；一张预设 = 一张 XS 微牌
      // （100×72）。轨宽 350，牌宽 100 —— 内容宽度，不许被拉满。
      for (int i = 0; i < kPresets.length; i++) {
        final Rect r = tester.getRect(find.byKey(Key('table.card.preset.$i')));
        expect(r.width, 100);
        expect(r.height, 72);
        expect(r.width, lessThan(200));
      }
      // 领位那张（6 张的中间一张）居中在整条轨上，牌心 = 屏心
      final Rect lead = tester.getRect(
        find.byKey(const Key('table.card.preset.2')),
      );
      expect(lead.center.dx, closeTo(195, .5));
      expect(lead.left, closeTo(145, .5));
    });

    testWidgets('没有预设时就只有输入条', (WidgetTester tester) async {
      await _mount(tester, const AskField(prompt: '名字 ›'));
      expect(find.byKey(const Key('ask.presets')), findsNothing);
      final Rect ask = tester.getRect(find.byKey(const Key('ask')));
      expect(ask.height, closeTo(54, .5));
    });

    testWidgets('收起来时不偷点击', (WidgetTester tester) async {
      int hits = 0;
      await _mount(
        tester,
        Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => hits++,
                child: const SizedBox.expand(),
              ),
            ),
            const AskField(
              prompt: '目标 ›',
              presets: kPresets,
              visible: false,
              // onPreset 给了也不该被点到
            ),
          ],
        ),
      );
      await tester.tapAt(const Offset(80, 780));
      await tester.pump();
      expect(hits, 1);
    });
  });

  group('横幅', () {
    testWidgets('居中挂在 top 86，称号与文案都在', (WidgetTester tester) async {
      await _mount(
        tester,
        const SysBanner(kicker: '见面礼', text: '双倍卡 ×1', glyph: '×2'),
      );
      expect(find.text('见面礼'), findsOneWidget);
      expect(find.text('双倍卡 ×1'), findsOneWidget);
      expect(find.text('×2'), findsOneWidget);
      final Rect b = tester.getRect(find.byKey(const Key('banner')));
      expect(b.top, closeTo(86, .5));
      expect(b.center.dx, closeTo(195, .5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('收起来时不占位也不吃点击', (WidgetTester tester) async {
      int hits = 0;
      await _mount(
        tester,
        Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => hits++,
                child: const SizedBox.expand(),
              ),
            ),
            const SysBanner(kicker: '见面礼', text: '双倍卡 ×1', visible: false),
          ],
        ),
      );
      await tester.tapAt(const Offset(195, 100));
      await tester.pump();
      expect(hits, 1);
    });
  });
}
