import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:system_panel/agent/llm_client.dart';
import 'package:system_panel/agent/settings_store.dart';
import 'package:system_panel/agent/vision.dart';
import 'package:system_panel/state/quest.dart';
import 'package:system_panel/widgets/exec_panel.dart';

/// 视觉校验链路单测（docs/18 §2.4 · D9）。
/// 全部 mock：picker/落盘/LLM 都是注入件，**不打真网、不触真盘**。
void main() {
  const Quest quest = Quest.demo; // C 级主线第 5 环「跑完 5 公里」

  /// http.Response 默认 latin1，含中文的应答体会当场抛
  /// "Contains invalid characters" —— 声明 application/json（http 1.6 按
  /// Content-Type 选 utf8 编解码），测试应答不再炸构造。
  http.Response jsonResp(Map<String, dynamic> json, [int status = 200]) =>
      http.Response(
        jsonEncode(json),
        status,
        headers: <String, String>{'content-type': 'application/json'},
      );

  LlmClient fakeLlm(
    LlmConfig config, {
    String content = '{"match": true, "note": "完成得不错"}',
    int status = 200,
    Duration delay = Duration.zero,
  }) => LlmClient(
    config: config,
    httpClient: MockClient((http.Request r) async {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      if (status != 200) return http.Response('err', status);
      return jsonResp(<String, dynamic>{
        'choices': <dynamic>[
          <String, dynamic>{
            'message': <String, dynamic>{'content': content},
          },
        ],
      });
    }),
  );

  group('暴击率联动（7% / 4%，封顶 .85）', () {
    test('已校验证据每张 +7%', () {
      expect(evidenceCritBonus(verified: 1, unverified: 0), closeTo(.07, 1e-9));
      expect(evidenceCritBonus(verified: 3, unverified: 0), closeTo(.21, 1e-9));
    });

    test('未校验证据每张 +4%', () {
      expect(evidenceCritBonus(verified: 0, unverified: 1), closeTo(.04, 1e-9));
      expect(evidenceCritBonus(verified: 0, unverified: 3), closeTo(.12, 1e-9));
    });

    test('混合：1 已校验 + 2 未校验 = 15%', () {
      expect(
        evidenceCritBonus(verified: 1, unverified: 2),
        closeTo(.15, 1e-9),
      );
    });

    test('critChance 完整公式（对照原型：base .06 + 连击 1%×min(10) + 芯片 .25）', () {
      expect(critChance(), closeTo(.06, 1e-9));
      expect(
        critChance(verified: 3, unverified: 0, streak: 6, critItem: true),
        closeTo(.06 + .21 + .06 + .25, 1e-9),
      );
      // 连击封 10
      expect(
        critChance(verified: 0, unverified: 0, streak: 99),
        closeTo(.06 + .10, 1e-9),
      );
    });

    test('封顶 .85（验收条款）', () {
      expect(
        critChance(verified: 99, unverified: 0),
        .85,
      );
      expect(
        critChance(verified: 20, unverified: 20, streak: 99, critItem: true),
        .85,
      );
    });
  });

  group('parseVerdict · 应答解析', () {
    final VisionService v = VisionService();

    test('match=true → 已校验', () {
      final VisionVerdict r = v.parseVerdict(
        '{"match": true, "note": "跑步截图可信"}',
      );
      expect(r.status, EvidenceStatus.verified);
      expect(r.note, '跑步截图可信');
    });

    test('```json 栅栏与前后缀说明文字都容忍', () {
      final VisionVerdict r = v.parseVerdict(
        '好的，结论如下：\n```json\n{"match": false, "note": "看不出在跑步"}\n```\n以上。',
      );
      expect(r.status, EvidenceStatus.suspect);
      expect(r.note, '看不出在跑步');
    });

    test('unsure → 存疑', () {
      final VisionVerdict r = v.parseVerdict('{"match": "unsure", "note": "太糊"}');
      expect(r.status, EvidenceStatus.suspect);
      expect(r.note, '太糊');
    });

    test('false 且无 note → 存疑兜底文案', () {
      final VisionVerdict r = v.parseVerdict('{"match": false}');
      expect(r.status, EvidenceStatus.suspect);
      expect(r.note, '证据存疑');
    });

    test('坏输出一律「未校验」：纯文本 / 数字 match / 空串', () {
      expect(v.parseVerdict('压根不是 JSON').status, EvidenceStatus.unverified);
      expect(v.parseVerdict('{"match": 42}').status, EvidenceStatus.unverified);
      expect(v.parseVerdict('').status, EvidenceStatus.unverified);
    });

    test('note >40 字按码点钳到 40（docs/18 §2.4）', () {
      final String long = '跑' * 50;
      final VisionVerdict r = v.parseVerdict(
        '{"match": true, "note": "$long"}',
      );
      expect(r.note.runes.length, 40);
    });
  });

  group('四情形兜底（不抛异常、标「未校验」）', () {
    test('无 Key：请求都不发', () async {
      int calls = 0;
      final VisionService v = VisionService(
        clientFactory: (LlmConfig c) => LlmClient(
          config: c,
          httpClient: MockClient((http.Request r) async {
            calls++;
            return http.Response('{}', 200);
          }),
        ),
      );
      final VisionVerdict r = await v.verify(
        quest: quest,
        base64Images: <String>['QUJD'],
        settings: const AgentSettings(apiKey: ''),
      );
      final VisionVerdict r2 = await v.verify(
        quest: quest,
        base64Images: <String>['QUJD'],
        settings: const AgentSettings(apiKey: '   '),
      );
      expect(r.status, EvidenceStatus.unverified);
      expect(r2.status, EvidenceStatus.unverified);
      expect(calls, 0);
    });

    test('校验关（纯信任模式）：请求都不发', () async {
      int calls = 0;
      final VisionService v = VisionService(
        clientFactory: (LlmConfig c) => LlmClient(
          config: c,
          httpClient: MockClient((http.Request r) async {
            calls++;
            return http.Response('{}', 200);
          }),
        ),
      );
      final VisionVerdict r = await v.verify(
        quest: quest,
        base64Images: <String>['QUJD'],
        settings: const AgentSettings(apiKey: 'k', visionEnabled: false),
      );
      expect(r.status, EvidenceStatus.unverified);
      expect(calls, 0);
    });

    test('断网：传输层异常 → 未校验', () async {
      final VisionService v = VisionService(
        clientFactory: (LlmConfig c) => LlmClient(
          config: c,
          retries: 0,
          httpClient: MockClient((http.Request r) async {
            throw http.ClientException('断网');
          }),
        ),
      );
      final VisionVerdict r = await v.verify(
        quest: quest,
        base64Images: <String>['QUJD'],
        settings: const AgentSettings(apiKey: 'k'),
      );
      expect(r.status, EvidenceStatus.unverified);
      expect(r.note, contains('网络不可达'));
    });

    test('超时（含重试 1 次）→ 未校验', () async {
      final VisionService v = VisionService(
        clientFactory: (LlmConfig c) => LlmClient(
          config: c,
          timeout: const Duration(milliseconds: 10),
          httpClient: MockClient((http.Request r) async {
            await Future<void>.delayed(const Duration(milliseconds: 60));
            return http.Response('{}', 200);
          }),
        ),
      );
      final VisionVerdict r = await v.verify(
        quest: quest,
        base64Images: <String>['QUJD'],
        settings: const AgentSettings(apiKey: 'k'),
      );
      expect(r.status, EvidenceStatus.unverified);
      expect(r.note, contains('超时'));
    });

    test('坏 JSON 响应 → 未校验', () async {
      final VisionService v = VisionService(
        clientFactory: (LlmConfig c) =>
            fakeLlm(c, content: '模型今天不想输出 JSON'),
      );
      final VisionVerdict r = await v.verify(
        quest: quest,
        base64Images: <String>['QUJD'],
        settings: const AgentSettings(apiKey: 'k'),
      );
      expect(r.status, EvidenceStatus.unverified);
    });

    test('HTTP 401 → 未校验', () async {
      final VisionService v = VisionService(
        clientFactory: (LlmConfig c) => fakeLlm(c, status: 401),
      );
      final VisionVerdict r = await v.verify(
        quest: quest,
        base64Images: <String>['QUJD'],
        settings: const AgentSettings(apiKey: 'bad'),
      );
      expect(r.status, EvidenceStatus.unverified);
      expect(r.note, contains('HTTP 401'));
    });
  });

  group('capture · 拍照→落盘→校验 管线', () {
    test('压缩参数照 docs/18 §2.4 传给 picker（≤1280 / JPEG q80）', () async {
      ImageSource? src;
      double? mw;
      double? mh;
      int? q;
      final VisionService v = VisionService(
        pickImage: (ImageSource s,
            {double? maxWidth, double? maxHeight, int? imageQuality}) async {
          src = s;
          mw = maxWidth;
          mh = maxHeight;
          q = imageQuality;
          return null; // 用户取消
        },
      );
      final EvidenceShot? out = await v.capture(
        quest: quest,
        source: ImageSource.gallery,
      );
      expect(out, isNull); // 取消不进槽
      expect(src, ImageSource.gallery);
      expect(mw, 1280);
      expect(mh, 1280);
      expect(q, 80);
    });

    test('全流程：落盘钩子收到字节、校验通过 → verified + 相对路径', () async {
      final Map<String, List<int>> writes = <String, List<int>>{};
      String? requestBody;
      final VisionService v = VisionService(
        pickImage: (ImageSource s,
            {double? maxWidth, double? maxHeight, int? imageQuality}) async {
          return XFile.fromData(
            utf8.encode('fake-jpeg-bytes'),
            name: 'shot.jpg',
            mimeType: 'image/jpeg',
          );
        },
        docsDirectory: () async => Directory('Z:/docs-virt'),
        writeBytes: (String p, dynamic bytes) async => writes[p] = bytes,
        clientFactory: (LlmConfig c) => LlmClient(
          config: c,
          httpClient: MockClient((http.Request r) async {
            requestBody = r.body;
            return jsonResp(<String, dynamic>{
              'choices': <dynamic>[
                <String, dynamic>{
                  'message': <String, dynamic>{
                    'content': '{"match": true, "note": "没问题"}',
                  },
                },
              ],
            });
          }),
        ),
      );
      final EvidenceShot? shot = await v.capture(
        quest: quest,
        settings: const AgentSettings(apiKey: 'k'),
      );
      expect(shot, isNotNull);
      expect(shot!.status, EvidenceStatus.verified);
      expect(shot.note, '没问题');
      expect(shot.path, startsWith('evidence/q41/'));
      expect(shot.path.endsWith('.jpg'), isTrue);
      expect(writes[shot.absPath!], isNotNull); // 落盘钩子真的收到了字节
      expect(requestBody, contains('data:image/jpeg;base64,'));
      expect(requestBody, contains('跑完 5 公里')); // 任务名进了校验 prompt
    });

    test('落盘失败不阻塞：证据照收、缩略图路径降级为空', () async {
      final VisionService v = VisionService(
        pickImage: (ImageSource s,
            {double? maxWidth, double? maxHeight, int? imageQuality}) async {
          return XFile.fromData(utf8.encode('x'), name: 'a.jpg');
        },
        docsDirectory: () async => Directory('Z:/docs-virt'),
        writeBytes: (String p, dynamic bytes) async {
          throw const FileSystemException('盘满了');
        },
        clientFactory: (LlmConfig c) => fakeLlm(c),
      );
      final EvidenceShot? shot = await v.capture(
        quest: quest,
        settings: const AgentSettings(apiKey: 'k'),
      );
      expect(shot, isNotNull);
      expect(shot!.absPath, isNull); // 降级
      expect(shot.status, EvidenceStatus.verified); // 校验结果不受落盘影响
    });
  });

  test('EvidenceShot JSON 往返：存档只存相对路径，absPath 不进 JSON', () {
    final EvidenceShot shot = EvidenceShot(
      id: 'q41-1',
      path: 'evidence/q41/1.jpg',
      absPath: 'Z:/docs/evidence/q41/1.jpg',
      status: EvidenceStatus.suspect,
      note: '存疑一下',
      takenAt: DateTime.parse('2026-01-02T03:04:05'),
    );
    final Map<String, dynamic> json = shot.toJson();
    expect(json.containsKey('absPath'), isFalse);
    final EvidenceShot back = EvidenceShot.fromJson(json);
    expect(back.id, shot.id);
    expect(back.path, shot.path);
    expect(back.status, EvidenceStatus.suspect);
    expect(back.note, shot.note);
    expect(back.takenAt, shot.takenAt);
  });

  // ── D9 · 执行面板证据槽（widget 级，注入件全 mock） ──────────────
  group('执行面板 · 证据槽（D9）', () {
    Future<void> mount(
      WidgetTester tester,
      ExecPanel panel,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Stack(children: <Widget>[panel]))),
      );
      await tester.pump();
    }

    EvidenceShot shot(
      EvidenceStatus status, {
      String note = '',
      String? absPath,
    }) => EvidenceShot(
      id: 's-$status',
      path: 'evidence/q41/${status.name}.jpg',
      absPath: absPath,
      status: status,
      note: note,
      takenAt: DateTime.now(),
    );

    String critTextOf(WidgetTester tester) {
      final Text t = tester.widget<Text>(find.byKey(const Key('exec.crit.value')));
      final TextSpan span = t.textSpan! as TextSpan;
      return (span.children![1] as TextSpan).text!;
    }

    testWidgets('三种标记齐全：✓/存疑/未校验 + 存疑 note 可见 + 暴击率 7%/4% 联动', (
      WidgetTester tester,
    ) async {
      await mount(
        tester,
        ExecPanel(
          quest: quest,
          elapsed: const Duration(minutes: 7),
          critChance: .12,
          itemCount: 0,
          evidenceCount: 0,
          evidence: <EvidenceShot>[
            shot(EvidenceStatus.verified),
            shot(EvidenceStatus.suspect, note: '太糊了'),
            shot(EvidenceStatus.unverified),
          ],
        ),
      );
      expect(find.text('✓'), findsOneWidget);
      expect(find.text('存疑'), findsOneWidget);
      expect(find.text('未校验'), findsOneWidget);
      expect(find.text('存疑 · 太糊了'), findsOneWidget);
      // .12 + .07 + .04 + .04 = .27 → 27%
      expect(critTextOf(tester), '27%');
      expect(tester.takeException(), isNull);
    });

    testWidgets('暴击率封顶 .85 显示', (WidgetTester tester) async {
      await mount(
        tester,
        ExecPanel(
          quest: quest,
          elapsed: const Duration(minutes: 7),
          critChance: .8,
          itemCount: 0,
          evidenceCount: 0,
          evidence: <EvidenceShot>[
            shot(EvidenceStatus.verified),
            shot(EvidenceStatus.verified),
            shot(EvidenceStatus.verified),
          ], // .8 + .21 = 1.01 → 封顶
        ),
      );
      expect(critTextOf(tester), '85%');
    });

    testWidgets('点 + → 拍照 → 校验请求发出 → 缩略图入槽 + 暴击率上涨 + 回传宿主', (
      WidgetTester tester,
    ) async {
      // 设置里配好 Key（走 in-memory 平台层，与 save_file_test 同款）
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
        SettingsStore.key: jsonEncode(<String, dynamic>{'apiKey': 'sk-test'}),
      });
      addTearDown(() {
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.withData(<String, Object>{});
      });

      String? requestBody;
      final VisionService fake = VisionService(
        pickImage: (ImageSource s,
            {double? maxWidth, double? maxHeight, int? imageQuality}) async {
          return XFile.fromData(utf8.encode('jpg'), name: 'e.jpg');
        },
        docsDirectory: () async => Directory('Z:/docs-virt'),
        writeBytes: (String p, dynamic bytes) async {},
        clientFactory: (LlmConfig c) => LlmClient(
          config: c,
          httpClient: MockClient((http.Request r) async {
            requestBody = r.body;
            return jsonResp(<String, dynamic>{
              'choices': <dynamic>[
                <String, dynamic>{
                  'message': <String, dynamic>{
                    'content': '{"match": true, "note": "现场照片"}',
                  },
                },
              ],
            });
          }),
        ),
      );

      List<EvidenceShot>? reported;
      await mount(
        tester,
        ExecPanel(
          quest: quest,
          elapsed: const Duration(minutes: 7),
          critChance: .12,
          itemCount: 0,
          evidenceCount: 0,
          vision: fake,
          onEvidenceChanged: (List<EvidenceShot> shots) => reported = shots,
        ),
      );
      expect(critTextOf(tester), '12%'); // 无证据时原样显示

      await tester.tap(find.byKey(const Key('exec.slot.0')));
      await tester.pumpAndSettle(); // 底部弹层（拍照/相册）
      await tester.tap(find.text('拍照'));
      await tester.pumpAndSettle(); // picker(假) → 落盘(假) → LLM(假)

      expect(requestBody, contains('data:image/jpeg;base64,'));
      expect(find.text('✓'), findsOneWidget);
      expect(critTextOf(tester), '19%'); // .12 + .07
      expect(reported, hasLength(1));
      expect(reported!.single.status, EvidenceStatus.verified);
      expect(tester.takeException(), isNull);
    });

    testWidgets('无 Key 兜底：证据照收、标「未校验」、暴击率按 4% 联动', (
      WidgetTester tester,
    ) async {
      // 不配 Key（干净内存存储）
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{});
      int llmCalls = 0;
      final VisionService fake = VisionService(
        pickImage: (ImageSource s,
            {double? maxWidth, double? maxHeight, int? imageQuality}) async {
          return XFile.fromData(utf8.encode('jpg'), name: 'e.jpg');
        },
        docsDirectory: () async => Directory('Z:/docs-virt'),
        writeBytes: (String p, dynamic bytes) async {},
        clientFactory: (LlmConfig c) => LlmClient(
          config: c,
          httpClient: MockClient((http.Request r) async {
            llmCalls++;
            return http.Response('{}', 200);
          }),
        ),
      );
      await mount(
        tester,
        ExecPanel(
          quest: quest,
          elapsed: const Duration(minutes: 7),
          critChance: .12,
          itemCount: 0,
          evidenceCount: 0,
          vision: fake,
        ),
      );
      await tester.tap(find.byKey(const Key('exec.slot.0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('拍照'));
      await tester.pumpAndSettle();

      expect(llmCalls, 0); // 无 Key 根本不发请求
      expect(find.text('未校验'), findsOneWidget);
      expect(find.textContaining('未校验 · 未配置 Key'), findsOneWidget);
      expect(critTextOf(tester), '16%'); // .12 + .04
      expect(tester.takeException(), isNull);
    });

    testWidgets('受控模式：长按已填槽 → onRemoveEvidence(i)', (WidgetTester tester) async {
      int? removed;
      await mount(
        tester,
        ExecPanel(
          quest: quest,
          elapsed: const Duration(minutes: 7),
          critChance: .12,
          itemCount: 0,
          evidenceCount: 0,
          evidence: <EvidenceShot>[shot(EvidenceStatus.verified)],
          onRemoveEvidence: (int i) => removed = i,
        ),
      );
      await tester.longPress(find.byKey(const Key('exec.slot.0')));
      await tester.pump();
      expect(removed, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('内部流：加一张再长按移除 → 槽清空、暴击率回落、宿主收到空表', (
      WidgetTester tester,
    ) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
        SettingsStore.key: jsonEncode(<String, dynamic>{'apiKey': 'sk-test'}),
      });
      final VisionService fake = VisionService(
        pickImage: (ImageSource s,
            {double? maxWidth, double? maxHeight, int? imageQuality}) async {
          return XFile.fromData(utf8.encode('jpg'), name: 'e.jpg');
        },
        docsDirectory: () async => Directory('Z:/docs-virt'),
        writeBytes: (String p, dynamic bytes) async {},
        clientFactory: (LlmConfig c) => LlmClient(
          config: c,
          httpClient: MockClient((http.Request r) async => jsonResp(
            <String, dynamic>{
              'choices': <dynamic>[
                <String, dynamic>{
                  'message': <String, dynamic>{
                    'content': '{"match": false, "note": "不像现场拍的"}',
                  },
                },
              ],
            },
          )),
        ),
      );
      List<EvidenceShot>? reported;
      await mount(
        tester,
        ExecPanel(
          quest: quest,
          elapsed: const Duration(minutes: 7),
          critChance: .12,
          itemCount: 0,
          evidenceCount: 0,
          vision: fake,
          onEvidenceChanged: (List<EvidenceShot> shots) => reported = shots,
        ),
      );
      // 加一张（LLM 判 false → 存疑）
      await tester.tap(find.byKey(const Key('exec.slot.0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('拍照'));
      await tester.pumpAndSettle();
      expect(find.text('存疑'), findsOneWidget);
      expect(find.text('存疑 · 不像现场拍的'), findsOneWidget);
      expect(critTextOf(tester), '16%');
      expect(reported, hasLength(1));
      // 长按移除
      await tester.longPress(find.byKey(const Key('exec.slot.0')));
      await tester.pumpAndSettle();
      expect(find.text('存疑'), findsNothing);
      expect(critTextOf(tester), '12%'); // 回到基础值
      expect(reported, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}
