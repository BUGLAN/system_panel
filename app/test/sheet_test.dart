import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

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

/// 投影面板 · 档案（面板外壳 / 六维雷达 / 战绩 / 称号）与系统页二级菜单。
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

/// 打开设置页的某个一级分类（宿主指定：二级菜单）。
///
/// 一级 `sheet.setMenu.<name>` → 二级 `sheet.setPane.<name>`，
/// 分类名与 `_SetCat` 的 enum 名一致（sound / voice / live2d / llm / system）。
Future<void> _openSetCat(WidgetTester tester, String cat) async {
  await tester.tap(find.byKey(Key('sheet.setMenu.$cat')));
  await tester.pumpAndSettle();
  expect(find.byKey(Key('sheet.setPane.$cat')), findsOneWidget);
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

    testWidgets('系统页一级菜单：五类模块 + 当前值回显 + 控制台状态条', (
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
      // 一级只有模块清单：五类，每类一行，带「当前值」回显（菜单即仪表）
      for (final String s in <String>['音效', '声音', 'Live2D', 'LLM', '本机']) {
        expect(find.text(s), findsOneWidget);
      }
      expect(find.text('SOUND · 音效'), findsOneWidget);
      expect(find.text('VOICE · 她的声音'), findsOneWidget);
      expect(find.text('LIVE2D · 角色'), findsOneWidget);
      expect(find.text('LLM · 视觉校验'), findsOneWidget);
      expect(find.text('SYSTEM · 控制台'), findsOneWidget);
      // 默认值：音效开 / 电子音 34ms / 描边开 / 校验开 / 震动开
      expect(
        tester.widget<Text>(find.byKey(const Key('sheet.setSum.sound'))).data,
        '开',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('sheet.setSum.voice'))).data,
        '电子音 · 34ms',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('sheet.setSum.live2d'))).data,
        '描边 开',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('sheet.setSum.llm'))).data,
        '校验 开',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('sheet.setSum.system'))).data,
        '震动 开',
      );
      // 一级不该出现任何控件：分段开关 / 输入框 / 按住重置都不在这层
      expect(find.byKey(const Key('sheet.seg.sound.0')), findsNothing);
      expect(find.byKey(const Key('sheet.llm.base')), findsNothing);
      expect(find.byKey(const Key('sheet.danger')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('系统页二级：点进各分类才见控件（音效 / 声音 / Live2D / 系统）', (
      WidgetTester tester,
    ) async {
      _mockPrefs();
      await _mount(
        tester,
        const Sheet(host: HostState.demo, kind: SheetKind.system),
      );
      await tester.pumpAndSettle();

      await _openSetCat(tester, 'sound');
      // 文案如实（宿主裁决 B′）：音效是离线包、单发正常，但**逐字电子音在这台
      // 模拟器上不响**是已知限制——不再写"打字机逐字有电子音"这种没兑现的承诺。
      expect(find.text('离线音效包（76 件）· 单发音效正常；逐字电子音已知限制（见下）'), findsOneWidget);
      expect(find.byKey(const Key('sheet.seg.sound.0')), findsOneWidget);
      await tester.tap(find.byKey(const Key('sheet.setBack')));
      await tester.pumpAndSettle();

      await _openSetCat(tester, 'voice');
      expect(find.text('人声用浏览器自带中文语音，效果看设备'), findsOneWidget);
      expect(find.text('电子音'), findsOneWidget);
      expect(find.text('人声'), findsOneWidget);
      expect(find.text('静音'), findsOneWidget);
      expect(find.byKey(const Key('sheet.seg.pace.34')), findsOneWidget);
      await tester.tap(find.byKey(const Key('sheet.setBack')));
      await tester.pumpAndSettle();

      await _openSetCat(tester, 'live2d');
      expect(find.text('她身上的电光轮廓；低端机可关'), findsOneWidget);
      expect(find.text('角色模型'), findsOneWidget);
      await tester.tap(find.byKey(const Key('sheet.setBack')));
      await tester.pumpAndSettle();

      await _openSetCat(tester, 'system');
      expect(find.text('真波形震动（15 处节奏）· 模拟器不震，真机才有手感'), findsOneWidget);
      expect(find.text('按住 2 秒'), findsOneWidget);
      expect(find.byKey(const Key('sheet.danger')), findsOneWidget);
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
      await _openSetCat(tester, 'llm'); // 二级菜单：LLM 那一类
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
      await _openSetCat(tester, 'llm');
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
      await _openSetCat(tester, 'llm');
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
      // 三处控件现在分居两个二级分类：思考档位/严格模式在「系统」，
      // 对白节奏在「声音」（二级菜单，2026-10-11 宿主指定）。
      await _openSetCat(tester, 'system');
      expect(find.text('思考档位'), findsOneWidget);
      expect(find.text('严格模式'), findsOneWidget);
      for (final String k in <String>['low', 'high', 'max']) {
        expect(find.byKey(Key('sheet.seg.effort.$k')), findsOneWidget);
      }
      for (final String k in <String>['auto', 'on', 'off']) {
        expect(find.byKey(Key('sheet.seg.strict.$k')), findsOneWidget);
      }
      // 默认停在 low / auto（表里读出来的，不是硬编码）
      final AgentSettings before = await SettingsStore().load();
      expect(before.reasoningEffort, 'low');
      expect(before.strictMode, 'auto');
      expect(before.paceMs, 34);

      await tester.ensureVisible(find.byKey(const Key('sheet.seg.effort.max')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet.seg.effort.max')));
      await tester.ensureVisible(find.byKey(const Key('sheet.seg.strict.on')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet.seg.strict.on')));
      // 回一级 → 进「声音」点对白节奏的「快」档
      await tester.tap(find.byKey(const Key('sheet.setBack')));
      await tester.pumpAndSettle();
      await _openSetCat(tester, 'voice');
      expect(find.text('对白节奏'), findsOneWidget);
      // docs/22 §R4：三档 = 慢 42 / 标准 34 / 快 24（值是毫秒数的字符串）
      for (final String k in <String>['42', '34', '24']) {
        expect(find.byKey(Key('sheet.seg.pace.$k')), findsOneWidget);
      }
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
      await _openSetCat(tester, 'llm');
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
      await _openSetCat(tester, 'sound');
      await tester.tap(find.byKey(const Key('sheet.seg.sound.0'))); // 关
      await tester.tap(find.byKey(const Key('sheet.setBack')));
      await tester.pumpAndSettle();
      await _openSetCat(tester, 'llm');
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
      // 称号是**就地挂**的名牒 chip（D6）：拿到的实心、没拿到的写「？？？ · 提示」
      expect(find.text('惯犯'), findsOneWidget);
      expect(find.textContaining('？？？ · 完成一张 S 级'), findsWidgets);
      expect(find.byKey(const Key('sheet.title.crit')), findsOneWidget);
      // ⚠️ 「道具」那一段**已按宿主指定删除**（2026-10-11：主页面已有，显示冗余）——
      //    四件道具的持有数在补给货架（sheet.shop）上都有，所以这里不再断言道具名。
      expect(find.byKey(const Key('sheet.inv')), findsNothing);
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
      // 补给页现在是**牌桌 · 货架**（docs/27）：领位落在第一件买得起的牌上，
      // 点领位即落定购买。340 金币 → 领位 = 双倍卡（60，第一件买得起的）。
      await tester.tapAt(tester.getCenter(find.byKey(const Key('sheet.shop'))));
      await tester.pumpAndSettle();
      expect(bought, <String>['dbl']);

      // 换穷档：一件都买不起（最便宜 30 > 10）→ 领位退回中位，点了不落定
      bought.clear();
      await _mount(
        tester,
        Sheet(
          host: HostState.demo.copyWith(coins: 10),
          kind: SheetKind.supply,
          onBuyItem: bought.add,
        ),
      );
      await tester.tapAt(tester.getCenter(find.byKey(const Key('sheet.shop'))));
      await tester.pumpAndSettle();
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
      // 领位 = 双倍卡（60）：点它落定购买
      await tester.tapAt(tester.getCenter(find.byKey(const Key('sheet.shop'))));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(children: <Widget>[build()]),
          ),
        ),
      );
      expect(find.text('金币 ◈ 280 · 只能花在这'), findsOneWidget); // 340 - 60
      expect(find.textContaining('持有 ×2'), findsWidgets); // dbl 1 → 2
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

  group('雷达刻度（线性 50 满值 + 溢出带）', () {
    // Radar 是 CustomPaint 画的：只断言「不抛异常」等于没验。这里把它渲成
    // 300×245 的 1:1 位图（RepaintBoundary 套在测试侧，雷达本身不背这个包袱），
    // 直接量顶点落在哪一像素上。
    //
    // 量的时候有两个坑：
    //  ① 值为 0 的维顶点全叠在圆心 —— 那一坨白点也在 x=150 这一列上，
    //     所以按「离预期位置最近的那段亮像素」取，而不是取整列的亮像素平均；
    //  ② 溢出维的读数文本也是冰蓝，会和顶点在像素上连成一片 —— 那一维只能量亮块上缘。
    List<int> px(ByteData d, int x, int y) {
      final int o = (y * 300 + x) * 4;
      return <int>[
        d.getUint8(o),
        d.getUint8(o + 1),
        d.getUint8(o + 2),
        d.getUint8(o + 3),
      ];
    }

    bool lit(List<int> p) => p[0] > 200 && p[1] > 200 && p[2] > 200;

    /// 把一版雷达渲成位图（rawRgba · 300×245 · 1:1）
    Future<ByteData> shot(WidgetTester tester, Map<String, int> attrs) async {
      await _mount(
        tester,
        RepaintBoundary(
          key: const Key('t.radar.cap'),
          child: Radar(attrs: attrs),
        ),
      );
      final ByteData d = (await tester.runAsync(() async {
        final RenderRepaintBoundary b = tester
            .renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('t.radar.cap')),
            );
        final ui.Image img = await b.toImage();
        final ByteData? bd = await img.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        return bd!;
      }))!;
      return d;
    }

    /// x 列上离 near 最近的那段连续亮像素的中心 y
    double? runY(ByteData d, int x, int near) {
      double? best;
      double bestGap = double.infinity;
      int y = 0;
      while (y < 245) {
        if (!lit(px(d, x, y))) {
          y++;
          continue;
        }
        final int from = y;
        while (y < 245 && lit(px(d, x, y))) {
          y++;
        }
        final int to = y - 1;
        final double gap = near < from
            ? (from - near).toDouble()
            : (near > to ? (near - to).toDouble() : 0);
        if (gap < bestGap) {
          bestGap = gap;
          best = (from + to + 1) / 2;
        }
      }
      return best;
    }

    /// x 列上那段亮像素有几行（≈ 顶点白点的直径：r2.2 出 4 行、溢出冰点 r3.0 出 6 行）
    int runLen(ByteData d, int x, int y) {
      int from = y;
      while (from > 0 && lit(px(d, x, from - 1))) {
        from--;
      }
      int to = y;
      while (to < 244 && lit(px(d, x, to + 1))) {
        to++;
      }
      return to - from + 1;
    }

    /// x 列上最上面那个亮像素的 y
    int firstY(ByteData d, int x) {
      for (int y = 0; y < 245; y++) {
        if (lit(px(d, x, y))) return y;
      }
      return -1;
    }

    /// (x,y) 附近 3×3 里有没有亮像素
    bool brightNear(ByteData d, double x, double y) {
      for (int dx = -1; dx <= 1; dx++) {
        for (int dy = -1; dy <= 1; dy++) {
          if (lit(px(d, (x + dx).round(), (y + dy).round()))) return true;
        }
      }
      return false;
    }

    test('刻度公式：50 分正好落在满值环 92，100 分撞几何护栏 117', () {
      expect(radarRadiusFor(0), 0);
      expect(radarRadiusFor(kRadarFull), closeTo(kRadarR, .001));
      // 理论落点是 122（kRadarRMax），但正上方只有 120 的余量，
      // 所以实际被 kRadarRClamp=117 削住 —— 护栏不是刻度，只吃掉 v≳95 那一段。
      expect(radarRadiusFor(100), closeTo(kRadarRClamp, .001));
      expect(kRadarRClamp, lessThan(kRadarRMax));
      // 分界点两侧得接得上，差多了满值环上会闪出一条缝
      expect(radarRadiusFor(50) - radarRadiusFor(49), lessThan(3));
      // 护栏必须留在画布内：cy=120 到上边只剩 120、到左右各 150/150
      expect(kRadarRClamp, lessThanOrEqualTo(120 - 3)); // 留 3px 给顶点圆点与发光
      expect(kRadarRMax, lessThan(245 - 120));
      expect(kRadarRMax, lessThan(150));
    });

    test('刻度公式：0~100 单调外扩；低值不缩成针、高值不早顶格', () {
      double prev = -1;
      for (int v = 0; v <= 100; v++) {
        final double rr = radarRadiusFor(v);
        expect(rr, greaterThanOrEqualTo(prev), reason: 'v=$v 不该比 v=${v - 1} 更靠里');
        prev = rr;
      }
      expect(radarRadiusFor(17), closeTo(50, 1.5)); // 任务书给的落点：v=17 → ≈50
      expect(radarRadiusFor(25), greaterThan(60)); // 半值也还看得见
      expect(radarRadiusFor(49), lessThan(kRadarR)); // 没满分就不顶格
      expect(radarRadiusFor(80), inInclusiveRange(kRadarR, kRadarRMax));
    });

    testWidgets('六维全 0：退化成中心一点，不抛异常也不画 NaN', (WidgetTester tester) async {
      final ByteData d = await shot(tester, const <String, int>{'力': 0, '敏': 0, '体': 0, '智': 0, '知': 0, '魅': 0});
      expect(tester.takeException(), isNull);
      final Rect r = tester.getRect(find.byKey(const Key('sheet.radar')));
      expect(r.width, closeTo(300, .5));
      expect(r.height, closeTo(245, .5));
      final double? y = runY(d, 150, 120);
      debugPrint('[radar] 全 0 量到亮块中心 y=$y（圆心 120）');
      expect(y, isNotNull, reason: '六个顶点叠在圆心，那里必须有点东西');
      expect(y!, closeTo(120, 1.5));
      expect(px(d, 150, 120)[3], greaterThan(0));
      expect(px(d, 150, 5)[3], 0, reason: '全 0 不该在满值环外留任何痕迹');
      expect(px(d, 5, 5)[3], 0);
    });

    testWidgets('超过 50 的维度：不抛异常、尺寸仍 300×245、顶点落在 92~122 之间', (
      WidgetTester tester,
    ) async {
      final ByteData d = await shot(tester, const <String, int>{
        '力': 80,
        '敏': 0,
        '体': 0,
        '智': 0,
        '知': 0,
        '魅': 0,
      });
      expect(tester.takeException(), isNull);
      final Rect r = tester.getRect(find.byKey(const Key('sheet.radar')));
      expect(r.width, closeTo(300, .5));
      expect(r.height, closeTo(245, .5));
      final double rr = radarRadiusFor(80);
      expect(rr, greaterThan(kRadarR));
      expect(rr, lessThan(kRadarRMax));
      // 力 在正上方：亮块上缘 = 120 − 顶点半径 − 冰点半径(3.0)，量出来应当就在那儿
      final int top = firstY(d, 150);
      debugPrint('[radar] 力=80 量到亮块上缘 y=$top，公式 ${120 - rr - 3.0}');
      expect(top, closeTo(120 - rr - 3.0, 1));
      expect(120 - rr, greaterThanOrEqualTo(0), reason: '顶点没跑出画布上边');
    });

    testWidgets('现有 demo 六维（力9/敏12/体17/智6/知8/魅4）仍能渲染', (
      WidgetTester tester,
    ) async {
      const Map<String, int> demo = <String, int>{
        '力': 9,
        '敏': 12,
        '体': 17,
        '智': 6,
        '知': 8,
        '魅': 4,
      };
      final ByteData d = await shot(tester, demo);
      expect(find.byType(Radar), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final int v in demo.values) {
        expect(radarRadiusFor(v), lessThanOrEqualTo(kRadarR)); // 全在满值环里
      }
      // 力 在正上方：顶点应当落在 r≈35.2 的白点上
      final double want = 120 - radarRadiusFor(9);
      final double? y = runY(d, 150, want.round());
      debugPrint('[radar] demo 力=9 量到顶点 y=$y，公式 $want');
      expect(y, isNotNull);
      expect(y!, closeTo(want, 1.5));
      // 满值环的顶点位置反而不能有点：说明六维都没到 50
      expect(brightNear(d, 150, 28), isFalse);
    });

    testWidgets('像素级：50 分的顶点正好落在满值环上（±0.5px）', (WidgetTester tester) async {
      final ByteData d = await shot(tester, const <String, int>{
        '力': 50,
        '敏': 0,
        '体': 0,
        '智': 0,
        '知': 0,
        '魅': 0,
      });
      final double? y = runY(d, 150, 28);
      debugPrint('[radar] 力=50 量到顶点 y=$y，满值环顶点在 ${120 - kRadarR}');
      expect(y, isNotNull);
      expect(y!, closeTo(120 - kRadarR, .5)); // 顶点半径量出来就是 92
      expect(120 - y, closeTo(kRadarR, .5));
      expect(runLen(d, 150, 28), inInclusiveRange(4, 5)); // 白点 r2.2
      expect(px(d, 150, 5)[3], 0, reason: '满值环上方再远处是干净的');
    });

    testWidgets('像素级：溢出维轴加亮、顶点换冰蓝并放大、读数也换冰蓝', (WidgetTester tester) async {
      // 轴：旁边五维固定 60，只把 力 从 50 推到 80 —— 单维独大时多边形的边正好压在轴上，
      // 那样量到的永远是描边色，量不出轴本身换没换色
      final ByteData a = await shot(tester, const <String, int>{
        '力': 50,
        '敏': 60,
        '体': 60,
        '智': 60,
        '知': 60,
        '魅': 60,
      });
      final ByteData b = await shot(tester, const <String, int>{
        '力': 80,
        '敏': 60,
        '体': 60,
        '智': 60,
        '知': 60,
        '魅': 60,
      });
      final int axis50 = px(a, 150, 110)[0];
      final int axis80 = px(b, 150, 110)[0];
      debugPrint('[radar] 力轴 (150,110) 红通道：50 分 → $axis50，80 分 → $axis80');
      expect(axis80, greaterThan(axis50 * 1.8));

      // 顶点：白点（R=255）→ 冰点（C.ice R=233）
      final ByteData c = await shot(tester, const <String, int>{
        '力': 80,
        '敏': 0,
        '体': 0,
        '智': 0,
        '知': 0,
        '魅': 0,
      });
      final int top = firstY(c, 150);
      debugPrint(
        '[radar] 力=80 顶点上缘 y=$top，公式 ${120 - radarRadiusFor(80) - 3.0}；'
        '顶点像素 ${px(c, 150, 7)}',
      );
      expect(top, closeTo(120 - radarRadiusFor(80) - 3.0, 1));
      expect(px(c, 150, 7)[0], greaterThan(200));
      expect(px(c, 150, 7)[0], lessThan(250), reason: '冰蓝不是纯白');

      // 智（正下方）溢出：亮块 6 行（r3.0），不溢出的白点只有 4 行（r2.2）
      final ByteData e = await shot(tester, const <String, int>{
        '力': 0,
        '敏': 0,
        '体': 0,
        '智': 80,
        '知': 0,
        '魅': 0,
      });
      final double rr = radarRadiusFor(80);
      final double? cy = runY(e, 150, (120 + rr).round());
      debugPrint(
        '[radar] 智=80 量到顶点 y=$cy，公式 ${120 + rr}；亮块 ${runLen(e, 150, 233)} 行',
      );
      expect(cy, isNotNull);
      expect(cy!, closeTo(120 + rr, 1.5));
      expect(runLen(e, 150, 233), 6);
      expect(120 + rr + 3, lessThan(245), reason: '顶点连冰点整块都在画布内，不出界');

      // 读数文本：智 溢出 → 冰蓝（R=233）；智 不溢出（力=80 那版）→ 青（R=56）
      debugPrint(
        '[radar] 智 读数像素 R：溢出 ${px(e, 150, 240)[0]}，不溢出 ${px(c, 150, 240)[0]}',
      );
      expect(px(e, 150, 240)[0], greaterThan(200));
      expect(px(c, 150, 240)[0], lessThan(120));
    });
  });
}
