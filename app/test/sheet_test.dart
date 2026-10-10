import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:system_panel/agent/llm_client.dart';
import 'package:system_panel/agent/llm_telemetry.dart';
import 'package:system_panel/agent/settings_store.dart';
import 'package:system_panel/data/items.dart';
import 'package:system_panel/data/rewards.dart';
import 'package:system_panel/data/titles.dart';
import 'package:system_panel/state/host_state.dart';
import 'package:system_panel/state/quest_flow.dart';
import 'package:system_panel/widgets/radar.dart';
import 'package:system_panel/widgets/sheet.dart';

/// 投影面板 · 档案（面板外壳 / 六维雷达 / 战绩 / 称号 / 道具）。
/// 坐标断言来自运行中原型的实测值。
///
/// ⚠️ 同其他页：`flutter test` 用占位字体（每字形 1em 宽），
/// 凡"宽度/高度由文字撑出来"的盒子在单测里量不准，只断言与文字无关的部分。
const Size kDesign = Size(390, 844);

/// 干净的内存设置存储（SharedPreferencesAsync 走新平台接口，
/// SharedPreferences.setMockInitialValues 只对旧 legacy API 生效）
void _mockPrefs([Map<String, Object>? seed]) {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData(
        Map<String, Object>.from(seed ?? <String, Object>{}),
      );
}

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
      // t24：升级曲线单一真源（Rewards.needFor = 12+lv×6）。旧曲线 60+7×40=340
      // 已废 —— 它让经验环在 LV7 显示 /340（真实 need 54，环常年看着空着）
      expect(HostState.need(s.lv), 54);
      expect(HostState.need(s.lv), Rewards.needFor(s.lv));
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

    testWidgets('系统页：四行开关 + 一行对白节奏 + LLM 设置组 + 一行按住重置 + 页脚', (
      WidgetTester tester,
    ) async {
      _mockPrefs();
      await _mount(
        tester,
        const Sheet(host: HostState.demo, kind: SheetKind.system),
      );
      await tester.pumpAndSettle(); // 等设置异步加载完
      expect(find.text('SYSTEM · 设置'), findsOneWidget);
      expect(find.text('系统'), findsOneWidget);
      for (final String s in <String>[
        '音效',
        '她的声音',
        // docs/22 §R4：对白节奏三档（慢 42 / 标准 34 / 快 24）
        '对白节奏',
        '震动',
        '全息描边',
        '重置存档',
      ]) {
        expect(find.text(s), findsOneWidget);
      }
      // 文案如实（宿主裁决 B′）：音效是离线包、单发正常，但**逐字电子音在这台
      // 模拟器上不响**是已知限制——不再写"打字机逐字有电子音"这种没兑现的承诺。
      expect(find.text('离线音效包（76 件）· 单发音效正常；逐字电子音已知限制（见下）'), findsOneWidget);
      expect(find.text('人声用浏览器自带中文语音，效果看设备'), findsOneWidget);
      expect(find.text('真波形震动（15 处节奏）· 模拟器不震，真机才有手感'), findsOneWidget);
      expect(find.text('按住 2 秒'), findsOneWidget);
      expect(find.textContaining('SYSTEM · opus-v2-dir'), findsOneWidget);
      // 「开」五个分段开关默认都停在开上
      // （音效/震动/全息描边/视觉校验 + 严格模式的「开」档）
      expect(find.text('开'), findsNWidgets(5));
      expect(find.text('电子音'), findsOneWidget);
      expect(find.text('人声'), findsOneWidget);
      expect(find.text('静音'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('LLM · 视觉校验设置组（docs/18 §2.4）', () {
    testWidgets('开关/BaseURL/Key(掩码)/模型名(默认 v4.1flash)/测试连接 齐全', (
      WidgetTester tester,
    ) async {
      _mockPrefs();
      await _mount(
        tester,
        const Sheet(host: HostState.demo, kind: SheetKind.system),
      );
      await tester.pumpAndSettle();
      expect(find.text('LLM · 视觉校验'), findsOneWidget);
      expect(find.text('视觉校验'), findsOneWidget);
      expect(find.text('接口地址'), findsOneWidget);
      expect(find.text('API Key'), findsOneWidget);
      expect(find.text('模型名'), findsOneWidget);

      final TextField base = tester.widget<TextField>(
        find.byKey(const Key('sheet.llm.base')),
      );
      expect(base.controller!.text, 'https://api.deepseek.com');
      final TextField key = tester.widget<TextField>(
        find.byKey(const Key('sheet.llm.key')),
      );
      expect(key.obscureText, isTrue); // Key 掩码显示
      final TextField model = tester.widget<TextField>(
        find.byKey(const Key('sheet.llm.model')),
      );
      expect(model.controller!.text, 'deepseek-v4.1flash'); // 宿主钦定的默认名
      expect(find.byKey(const Key('sheet.llm.test')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('改字段即时生效并落盘（防抖后）', (WidgetTester tester) async {
      _mockPrefs();
      await _mount(
        tester,
        const Sheet(host: HostState.demo, kind: SheetKind.system),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('sheet.llm.model')),
        'deepseek-v4-pro',
      );
      await tester.pump(const Duration(milliseconds: 500)); // 过 400ms 防抖
      final AgentSettings s = await SettingsStore().load();
      expect(s.model, 'deepseek-v4-pro');
    });

    testWidgets('测试连接：无 Key 时立即给结论（不发请求不挂死）', (WidgetTester tester) async {
      _mockPrefs();
      await _mount(
        tester,
        const Sheet(host: HostState.demo, kind: SheetKind.system),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('sheet.llm.test')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet.llm.test')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('sheet.llm.status'))).data,
        '失败 · 未配置 API Key',
      );
      expect(tester.takeException(), isNull);
    });
    // （「测试连接」的成功/断网路径属于真网行为，不在单测里打真网；
    //   别名归一化与四情形兜底已由 llm_client_test / vision_test 全 mock 覆盖。）

    test('设置持久化：写入 → 新实例读回（重启保留语义，docs/18 §2.8）', () async {
      _mockPrefs();
      final SettingsStore store = SettingsStore();
      final AgentSettings s = await store.load();
      // 缺省值
      expect(s.visionEnabled, isTrue);
      expect(s.baseUrl, 'https://api.deepseek.com');
      expect(s.apiKey, isEmpty);
      expect(s.model, 'deepseek-v4.1flash');
      expect(s.sound, isTrue);
      expect(s.voice, 'blip');
      expect(s.reasoningEffort, 'low'); // docs/22 §R1-2 默认低档
      expect(s.strictMode, 'auto'); // docs/22 §2.0 默认自动
      expect(s.paceMs, 34); // docs/22 §R4：默认档 = 标准 34（真源 kDefaultPaceMs）
      // 写入（这一份同时当「读回后应当等于什么」的期望值）
      final AgentSettings want = s.copyWith(
        apiKey: 'sk-test',
        visionEnabled: false,
        sound: false,
        voice: 'tts',
        model: 'deepseek-v4-pro',
        reasoningEffort: 'max',
        strictMode: 'on',
        paceMs: 24, // 快档
      );
      await store.save(want);
      // 新实例（= 重启后）读回
      final AgentSettings s2 = await SettingsStore().load();
      expect(s2.apiKey, 'sk-test');
      expect(s2.visionEnabled, isFalse);
      expect(s2.sound, isFalse);
      expect(s2.voice, 'tts');
      expect(s2.model, 'deepseek-v4-pro');
      expect(s2.reasoningEffort, 'max');
      expect(s2.strictMode, 'on');
      expect(s2.paceMs, 24); // 档位往返不丢（同 key opus-v2/settings/v1）
      // `==`/`hashCode` 也把 paceMs 算进去：整份相等，只改节奏的两份不相等
      expect(s2, want);
      expect(s2 == want.copyWith(paceMs: 42), isFalse);
    });

    test('老档/坏档迁移：缺字段补默认，坏 JSON 不炸', () async {
      _mockPrefs(<String, Object>{
        SettingsStore.key: jsonEncode(<String, dynamic>{
          'apiKey': 'sk-old', // 只有这一个字段（老版本档）
        }),
      });
      final AgentSettings s = await SettingsStore().load();
      expect(s.apiKey, 'sk-old');
      expect(s.visionEnabled, isTrue); // 缺的补默认
      expect(s.model, 'deepseek-v4.1flash');

      _mockPrefs(<String, Object>{SettingsStore.key: '{broken json'});
      final AgentSettings s2 = await SettingsStore().load();
      expect(s2.model, 'deepseek-v4.1flash'); // 回到默认，不抛异常
    });

    test('老档缺 reasoningEffort/strictMode/paceMs：补默认、不清档、不炸（docs/22 §2.0/§R4）', () async {
      // 只有旧字段的老档（本轮三个新字段一个都没有）
      _mockPrefs(<String, Object>{
        SettingsStore.key: jsonEncode(<String, dynamic>{
          'apiKey': 'sk-old',
          'visionEnabled': false,
          'voice': 'tts',
        }),
      });
      final AgentSettings s = await SettingsStore().load();
      // 旧字段照旧读回来（合并=在默认值上盖，不是整档重来）
      expect(s.apiKey, 'sk-old');
      expect(s.visionEnabled, isFalse);
      expect(s.voice, 'tts');
      // 缺的三个新字段补默认
      expect(s.reasoningEffort, 'low');
      expect(s.strictMode, 'auto');
      expect(s.paceMs, 34); // 老档没有 paceMs → 标准档，不写迁移代码
      // 补默认后回写一轮：老字段一个不少，新字段落进 JSON
      await SettingsStore().save(s);
      final AgentSettings s2 = await SettingsStore().load();
      expect(s2.apiKey, 'sk-old');
      expect(s2.visionEnabled, isFalse);
      expect(s2.reasoningEffort, 'low');
      expect(s2.strictMode, 'auto');
      expect(s2.paceMs, 34);
    });

    testWidgets('思考档位/严格模式/对白节奏：三行三档都在、可点、点后落盘', (WidgetTester tester) async {
      _mockPrefs();
      await _mount(
        tester,
        const Sheet(host: HostState.demo, kind: SheetKind.system),
      );
      await tester.pumpAndSettle();
      expect(find.text('思考档位'), findsOneWidget);
      expect(find.text('严格模式'), findsOneWidget);
      expect(find.text('对白节奏'), findsOneWidget);
      for (final String k in <String>['low', 'high', 'max']) {
        expect(find.byKey(Key('sheet.seg.effort.$k')), findsOneWidget);
      }
      for (final String k in <String>['auto', 'on', 'off']) {
        expect(find.byKey(Key('sheet.seg.strict.$k')), findsOneWidget);
      }
      // docs/22 §R4：三档 = 慢 42 / 标准 34 / 快 24（值是毫秒数的字符串）
      for (final String k in <String>['42', '34', '24']) {
        expect(find.byKey(Key('sheet.seg.pace.$k')), findsOneWidget);
      }
      // 默认停在 low / auto / 34（表里读出来的，不是硬编码）
      final AgentSettings before = await SettingsStore().load();
      expect(before.reasoningEffort, 'low');
      expect(before.strictMode, 'auto');
      expect(before.paceMs, 34);

      // 三行在面板下半截，先滚进视口再点
      await tester.ensureVisible(find.byKey(const Key('sheet.seg.effort.max')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet.seg.effort.max')));
      await tester.ensureVisible(find.byKey(const Key('sheet.seg.strict.on')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet.seg.strict.on')));
      // 对白节奏那一行在「她的声音」下面，滚回上去点「快」档
      await tester.ensureVisible(find.byKey(const Key('sheet.seg.pace.24')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet.seg.pace.24')));
      await tester.pump(const Duration(milliseconds: 500)); // 过 400ms 防抖

      final AgentSettings s = await SettingsStore().load();
      expect(s.reasoningEffort, 'max'); // 落盘了
      expect(s.strictMode, 'on');
      expect(s.paceMs, 24); // 快档落盘（切完就存，不用重启）
      expect(s.haptic, isTrue); // 没动过的保持原样
      expect(tester.takeException(), isNull);
    });

    testWidgets('最近一次 LLM 失败：只读回显 detail ?? —，副行给失败计数', (
      WidgetTester tester,
    ) async {
      _mockPrefs();
      LlmTelemetry.reset();
      addTearDown(LlmTelemetry.reset);
      await _mount(
        tester,
        const Sheet(host: HostState.demo, kind: SheetKind.system),
      );
      await tester.pumpAndSettle();
      expect(find.text('最近一次 LLM 失败'), findsOneWidget);
      // 从未失败：占位符，不裸奔
      expect(
        tester.widget<Text>(find.byKey(const Key('sheet.llm.lastFail'))).data,
        '—',
      );
      expect(find.text('— · —'), findsOneWidget); // summary · kindSummary

      // 遥测是内存态仪表：测试里直接摆一次失败（不写工厂、不落盘）
      LlmTelemetry.calls = 3;
      LlmTelemetry.ok = 2;
      LlmTelemetry.failures = 1;
      LlmTelemetry.lastDetail = 'HTTP 401 · 回执片段';
      LlmTelemetry.byKind[LlmFailure.httpError] = 1;
      await _mount(
        tester,
        const Sheet(host: HostState.demo, kind: SheetKind.system),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('sheet.llm.lastFail'))).data,
        'HTTP 401 · 回执片段',
      );
      final Text hint = tester.widget<Text>(find.textContaining('httpError=1'));
      expect(hint.data, '2/3 成功 · 1 失败 · httpError=1');
    });

    testWidgets('D8：四开关可切且落盘（点「关」→ store 里 sound=false）', (
      WidgetTester tester,
    ) async {
      _mockPrefs();
      await _mount(
        tester,
        const Sheet(host: HostState.demo, kind: SheetKind.system),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet.seg.sound.0'))); // 关
      await tester.tap(find.byKey(const Key('sheet.seg.vision.0'))); // 视觉校验关
      await tester.pump(const Duration(milliseconds: 500)); // 过防抖
      final AgentSettings s = await SettingsStore().load();
      expect(s.sound, isFalse);
      expect(s.visionEnabled, isFalse);
      expect(s.haptic, isTrue); // 没动的保持
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

    testWidgets('经验条按 exp/need 铺开（分母 = 结算曲线；漏 heightFactor 会变 0 高）', (
      WidgetTester tester,
    ) async {
      // 演示档 214 已越过 LV7 的 need=54 → clamp 满环
      await _mount(tester, const Sheet(host: HostState.demo));
      final Rect bar = tester.getRect(find.byKey(const Key('sheet.bar')));
      final Rect fill = tester.getRect(find.byKey(const Key('sheet.bar.fill')));
      expect(bar.height, 6);
      expect(fill.height, 6);
      expect(fill.width / bar.width, closeTo(1, .01)); // 214 / 54 → clamp 到 1

      // 未满档：20 / 54 —— 旧曲线 /340 会画成 5.9%，一眼能看出换没换曲线
      await _mount(
        tester,
        Sheet(host: HostState.demo.copyWith(exp: 20)),
      );
      final Rect bar2 = tester.getRect(find.byKey(const Key('sheet.bar')));
      final Rect fill2 = tester.getRect(find.byKey(const Key('sheet.bar.fill')));
      expect(
        fill2.width / bar2.width,
        closeTo(20 / Rewards.needFor(7), .01),
      );
    });

    testWidgets('经验环分母读的是 rewards.need(lv)（LV7 = /54，不是 /340）', (
      WidgetTester tester,
    ) async {
      await _mount(tester, const Sheet(host: HostState.demo));
      final Finder row = find.byKey(const Key('sheet.arTop'));
      expect(row, findsOneWidget);
      final Iterable<String> texts = tester
          .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
          .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '');
      expect(
        texts.any((String s) => s.contains(' / ${Rewards.needFor(7)}')),
        isTrue,
        reason: '经验环读数必须是 /54',
      );
      expect(texts.any((String s) => s.contains('/ 340')), isFalse);
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

  group('D6 · 称号佩戴（store.js equip 语义）', () {
    testWidgets('点已解锁称号 → 触发佩戴回调', (WidgetTester tester) async {
      _mockPrefs();
      String? equipped;
      await _mount(
        tester,
        Sheet(
          host: HostState.demo,
          onEquipTitle: (String id) => equipped = id,
        ),
      );
      // 称号区在雷达/战绩下面，先把目标 chip 滚进视口再点
      await tester.ensureVisible(find.byKey(const Key('sheet.title.crit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet.title.crit')));
      expect(equipped, 'crit');
    });

    testWidgets('口头巨人生效中：换挂全部禁止（耻辱章摘不掉）', (WidgetTester tester) async {
      _mockPrefs();
      String? equipped;
      await _mount(
        tester,
        Sheet(
          host: HostState.demo.copyWith(title: 'mouth'),
          onEquipTitle: (String id) => equipped = id,
        ),
      );
      await tester.ensureVisible(find.byKey(const Key('sheet.title.first')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet.title.first')));
      await tester.tap(find.byKey(const Key('sheet.title.mouth')));
      expect(equipped, isNull);
    });

    testWidgets('未解锁的称号点不动', (WidgetTester tester) async {
      _mockPrefs();
      String? equipped;
      await _mount(
        tester,
        Sheet(
          host: HostState.demo,
          onEquipTitle: (String id) => equipped = id,
        ),
      );
      await tester.ensureVisible(find.byKey(const Key('sheet.title.rankS')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet.title.rankS')));
      expect(equipped, isNull);
    });

    testWidgets('佩戴回调链路全程：宿主侧换档重挂 → 档案头称号跟随', (WidgetTester tester) async {
      _mockPrefs();
      HostState host = HostState.demo;
      Sheet build() => Sheet(
            host: host,
            onEquipTitle: (String id) {
              // 宿主侧（T2 接 QuestFlow.equip）的语义：owned && title!=='mouth'
              if (host.ownedTitles.contains(id) && host.title != 'mouth') {
                host = host.copyWith(title: id);
              }
            },
          );
      await _mount(tester, build());
      await tester.ensureVisible(find.byKey(const Key('sheet.title.crit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet.title.crit')));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Stack(children: <Widget>[build()])),
        ),
      );
      expect(find.text('「被暴击眷顾」'), findsOneWidget); // arTop 的称号行
    });
  });

  group('D7 · 补给购买（store.js buy 语义）', () {
    testWidgets('买得起 → 触发购买回调；买不起 → 点不动', (WidgetTester tester) async {
      _mockPrefs();
      final List<String> bought = <String>[];
      await _mount(
        tester,
        Sheet(
          host: HostState.demo,
          kind: SheetKind.supply,
          onBuyItem: bought.add,
        ),
      );
      await tester.tap(find.byKey(const Key('sheet.buy.swap'))); // 30 ≤ 340
      expect(bought, <String>['swap']);

      // 换穷档：换单券都买不起
      bought.clear();
      await _mount(
        tester,
        Sheet(
          host: HostState.demo.copyWith(coins: 10),
          kind: SheetKind.supply,
          onBuyItem: bought.add,
        ),
      );
      await tester.tap(find.byKey(const Key('sheet.buy.swap'))); // 30 > 10
      await tester.tap(find.byKey(const Key('sheet.buy.dbl'))); // 60 > 10
      expect(bought, isEmpty);
    });

    testWidgets('购买扣币加道具（回调链路全程，对照 Store.buy）', (WidgetTester tester) async {
      _mockPrefs();
      HostState host = HostState.demo;
      Sheet build() => Sheet(
            host: host,
            kind: SheetKind.supply,
            onBuyItem: (String id) {
              // 宿主侧（T2 接 QuestFlow.buy）的语义：coins 够则扣币加道具
              final Item it = Item.byId(id)!;
              if (host.coins >= it.price) {
                host = host.copyWith(
                  coins: host.coins - it.price,
                  items: <String, int>{
                    ...host.items,
                    id: (host.items[id] ?? 0) + 1,
                  },
                );
              }
            },
          );
      await _mount(tester, build());
      await tester.tap(find.byKey(const Key('sheet.buy.swap')));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(children: <Widget>[build()]),
          ),
        ),
      );
      expect(find.text('金币 ◈ 310 · 只能花在这'), findsOneWidget); // 340 - 30
      expect(find.textContaining('持有 ×3'), findsOneWidget); // swap 2 → 3
    });
  });

  group('回顾（A6 · t21）', () {
    HistoryEntry entry(
      DateTime at, {
      String rank = 'E',
      String result = 'clear',
      int exp = 1,
      int coin = 5,
      Map<String, int> attrs = const <String, int>{'体': 1},
    }) => HistoryEntry(
          at: at,
          name: '测试单 $rank',
          rank: rank,
          kind: 'daily',
          exp: exp,
          coin: coin,
          streak: 1,
          result: result,
          attrs: attrs,
        );

    testWidgets('档案页有「本周回顾」入口，点开回顾 pane（空态不裸奔）', (
      WidgetTester tester,
    ) async {
      _mockPrefs();
      await _mount(tester, const Sheet(host: HostState.demo));
      expect(find.byKey(const Key('sheet.reviewEntry')), findsOneWidget);
      // 入口在档案内容最底部（道具段之后），先滚到可见再点
      // （sheet.body 是页面里唯一的滚动容器，取它内部的 Scrollable）
      await tester.scrollUntilVisible(
        find.byKey(const Key('sheet.reviewEntry')),
        160.0,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('sheet.body')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const Key('sheet.reviewEntry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sheet.review')), findsOneWidget);
      expect(find.byKey(const Key('stats.pane')), findsOneWidget);
      // 空态：概览照显 + 一句开场，不裸奔
      expect(find.byKey(const Key('stats.overview')), findsOneWidget);
      expect(find.text('还没战绩。第一单就从今天开始。'), findsOneWidget);
      // 返回档案
      await tester.tap(find.byKey(const Key('sheet.reviewBack')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sheet.reviewEntry')), findsOneWidget);
    });

    testWidgets('有数据态：概览读数 + 六维行 + 战绩列表（稀有度色标）', (
      WidgetTester tester,
    ) async {
      final DateTime now = DateTime.now();
      _mockPrefs(<String, Object>{
        HistoryLog.key: jsonEncode(<Map<String, dynamic>>[
          entry(now.subtract(const Duration(hours: 2))).toJson(),
          entry(
            now.subtract(const Duration(hours: 5)),
            rank: 'C',
            result: 'quit',
            exp: 0,
            coin: 0,
            attrs: const <String, int>{}, // 认输不出账
          ).toJson(),
        ]),
      });
      await _mount(tester, const Sheet(host: HostState.demo));
      // 先证 seed 本身可读（排除平台 mock 层问题）
      expect((await HistoryLog().entries()).length, 2);
      await tester.scrollUntilVisible(
        find.byKey(const Key('sheet.reviewEntry')),
        160.0,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('sheet.body')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const Key('sheet.reviewEntry')));
      await tester.pumpAndSettle();
      // 概览：本周 1 完成 / EXP 1 / 金币 5 / 连击 1
      expect(find.text('1'), findsWidgets);
      expect(find.text('5'), findsWidgets);
      // 六维 6 行都在
      expect(find.byKey(const Key('stats.attrs')), findsOneWidget);
      // 战绩：两条 + 认输结果标记 + 稀有度色标
      expect(find.byKey(const Key('stats.recent')), findsOneWidget);
      expect(find.textContaining('CLEAR'), findsOneWidget);
      expect(find.textContaining('认输'), findsOneWidget);
      expect(find.textContaining('测试单 C'), findsOneWidget);
    });
  });
}
