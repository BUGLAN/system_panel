import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/data/items.dart';
import 'package:system_panel/data/titles.dart';
import 'package:system_panel/state/host_state.dart';
import 'package:system_panel/widgets/radar.dart';
import 'package:system_panel/widgets/sheet.dart';

/// 投影面板 · 档案（面板外壳 / 六维雷达 / 战绩 / 称号 / 道具）。
/// 坐标断言来自运行中原型的实测值。
///
/// ⚠️ 同其他页：`flutter test` 用占位字体（每字形 1em 宽），
/// 凡"宽度/高度由文字撑出来"的盒子在单测里量不准，只断言与文字无关的部分。
const Size kDesign = Size(390, 844);

Future<void> _mount(WidgetTester tester, Widget child) async {
  // ⚠️ `setSurfaceSize` 只改布局约束，**MediaQuery 仍报默认的 800×600**——
  // 凡是按百分比定位的组件（这块面板的 top:38% 就是）必须用 view 来设，
  // 否则单测里的位置和真机对不上。
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
  group('宿主数据', () {
    test('演示档与原型「老宿主 · 第 23 天」一致', () {
      const HostState s = HostState.demo;
      expect(s.lv, 7);
      expect(s.exp, 214);
      expect(HostState.need(s.lv), 340);
      expect(s.attrs, <String, int>{
        '力': 9,
        '敏': 12,
        '体': 17,
        '智': 6,
        '知': 8,
        '魅': 4,
      });
      expect(s.weakest.key, '魅'); // 最弱那一维的轴名会变灰
      expect(s.weakest.value, 4);
      expect(s.doneCount, 31);
      expect(s.critCount, 6);
      expect(s.failCount, 4);
      expect(s.bestStreak, 6);
      expect(s.ownedTitles.length, 7);
      expect(s.items['dbl'], 1);
    });

    test('称号表 12 条，只有一条是耻辱称号', () {
      expect(HostTitle.all.length, 12);
      expect(HostTitle.all.where((HostTitle t) => t.shame).length, 1);
      expect(HostTitle.nameOf('done15'), '惯犯');
      expect(HostTitle.nameOf('mouth'), '口头巨人');
    });

    test('道具表 4 条，金币唯一去处', () {
      expect(Item.all.length, 4);
      expect(Item.all.map((Item i) => i.id).toList(), <String>[
        'dbl',
        'crit',
        'shield',
        'swap',
      ]);
      expect(Item.byId('shield')!.price, 90);
    });
  });

  group('投影面板外壳', () {
    testWidgets('面板从 38% 处起、贴在底边', (WidgetTester tester) async {
      await _mount(tester, const Sheet(host: HostState.demo));
      final Rect r = tester.getRect(find.byKey(const Key('sheet.body')));
      expect(r.left, 0); // 滚动容器本体占满宽，内边距在里面
      expect(r.right, 390);
      expect(r.top, closeTo(320.72 + 71, .5)); // 38% + 头部高
      expect(r.bottom, 844);
      final Rect close = tester.getRect(find.byKey(const Key('sheet.close')));
      expect(close.size, const Size(36, 36));
      expect(close.right, closeTo(370, .5)); // padding 20
      expect(close.top, closeTo(320.72 + 18, .5)); // 38% + head padding 18
    });

    testWidgets('抬头与该页文案', (WidgetTester tester) async {
      await _mount(tester, const Sheet(host: HostState.demo));
      expect(find.text('ARCHIVE · 宿主档案'), findsOneWidget);
      expect(find.text('档案'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('补给页：四件道具 + 价格 + 买不起时禁用', (WidgetTester tester) async {
      await _mount(
        tester,
        const Sheet(host: HostState.demo, kind: SheetKind.supply),
      );
      expect(find.text('SUPPLY · 补给'), findsOneWidget);
      expect(find.text('补给'), findsOneWidget);
      expect(find.text('金币 ◈ 340 · 只能花在这'), findsOneWidget);
      for (final Item it in Item.all) {
        // 名字与「持有 ×N」在同一个 Text.rich 里，得用 textContaining
        expect(find.textContaining(it.name), findsWidgets);
        expect(find.text(it.desc), findsOneWidget);
        expect(find.text('${it.price}'), findsOneWidget);
      }
      // 持有数（veteran 档）：双倍卡 1 / 暴击芯片 1 / 免死金牌 1 / 换单券 2
      // （
      //   之前那版「×undefined」是被玩脏的存档造成的，不是原型的问题）
      expect(find.textContaining('持有 ×2'), findsOneWidget);
      expect(find.textContaining('持有 ×1'), findsNWidgets(3));
      expect(find.textContaining('持有 ×0'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('系统页：四行开关 + 一行按住重置 + 页脚', (WidgetTester tester) async {
      await _mount(
        tester,
        const Sheet(host: HostState.demo, kind: SheetKind.system),
      );
      expect(find.text('SYSTEM · 设置'), findsOneWidget);
      expect(find.text('系统'), findsOneWidget);
      for (final String s in <String>['音效', '她的声音', '震动', '全息描边', '重置存档']) {
        expect(find.text(s), findsOneWidget);
      }
      expect(find.text('全部现场合成，没有音频文件'), findsOneWidget);
      expect(find.text('人声用浏览器自带中文语音，效果看设备'), findsOneWidget);
      expect(find.text('按住 2 秒'), findsOneWidget);
      expect(find.textContaining('SYSTEM · opus-v2-dir'), findsOneWidget);
      // 「开」四个分段开关默认都停在开上
      expect(find.text('开'), findsNWidgets(3));
      expect(find.text('电子音'), findsOneWidget);
      expect(find.text('人声'), findsOneWidget);
      expect(find.text('静音'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('档案内容', () {
    testWidgets('雷达 300×245 居中', (WidgetTester tester) async {
      await _mount(tester, const Sheet(host: HostState.demo));
      final Rect r = tester.getRect(find.byKey(const Key('sheet.radar')));
      expect(r.width, closeTo(300, .5));
      expect(r.height, closeTo(245, .5));
      expect(r.left, closeTo(45, .5)); // (350-300)/2 + 20
    });

    testWidgets('经验条按 214/340 铺开（漏 heightFactor 会变 0 高）', (
      WidgetTester tester,
    ) async {
      await _mount(tester, const Sheet(host: HostState.demo));
      final Rect bar = tester.getRect(find.byKey(const Key('sheet.bar')));
      final Rect fill = tester.getRect(find.byKey(const Key('sheet.bar.fill')));
      expect(bar.height, 6);
      expect(fill.height, 6);
      expect(fill.width / bar.width, closeTo(214 / 340, .01));
    });

    testWidgets('四格战绩 + 12 个称号 + 4 件道具都在', (WidgetTester tester) async {
      await _mount(tester, const Sheet(host: HostState.demo));
      for (final String t in <String>['31', '6', '4']) {
        expect(find.text(t), findsWidgets);
      }
      for (final String t in <String>['完成', '暴击', '认输', '最长连击']) {
        expect(find.text(t), findsOneWidget);
      }
      // 没拿到的写「？？？ · 提示」
      expect(find.text('惯犯'), findsOneWidget);
      expect(find.textContaining('？？？ · 完成一张 S 级'), findsOneWidget);
      for (final Item it in Item.all) {
        expect(find.text(it.name), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('最弱那一维的轴名在雷达里（不抛异常）', (WidgetTester tester) async {
      await _mount(
        tester,
        const Radar(
          attrs: <String, int>{
            '力': 9,
            '敏': 12,
            '体': 17,
            '智': 6,
            '知': 8,
            '魅': 4,
          },
          weakKey: '魅',
        ),
      );
      expect(find.byType(Radar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
