import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:system_panel/agent/copy.dart';
import 'package:system_panel/agent/llm_client.dart';
import 'package:system_panel/agent/llm_gateway.dart';
import 'package:system_panel/agent/settings_store.dart';
import 'package:system_panel/agent/vision.dart';
import 'package:system_panel/state/evidence_checks.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/host_state.dart';
import 'package:system_panel/state/quest.dart';
import 'package:system_panel/state/quest_flow.dart';
import 'package:system_panel/state/result.dart';
import 'package:system_panel/ui/ref/ref_sheet.dart';

/// 批次 G2.4（视觉校验时限 / 超时不重试 / 用完关客户端 / 迟到结论丢弃）
/// + G2.3 ①②③（删流式、温度与上下文真接进主链路与视觉校验、系统抽屉的视觉开关）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // QuestFlow.settle 会顺手写执行历史（SharedPreferencesAsync）
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  http.Response okBody(String content, {String? finish}) => http.Response(
    jsonEncode(<String, dynamic>{
      'choices': <dynamic>[
        <String, dynamic>{
          'finish_reason': ?finish,
          'message': <String, dynamic>{'content': content},
        },
      ],
    }),
    200,
    headers: <String, String>{'content-type': 'application/json'},
  );

  // ═══════════ G2.4 · LlmClient 超时不重试 ═══════════
  group('G2.4 · 超时不重试，断网 / 502·503·504 照旧重试', () {
    test('先断网（重试）再超时 → 当场返回 timeout，detail 如实写重试 1 次', () async {
      int calls = 0;
      final LlmClient c = LlmClient(
        config: const LlmConfig(apiKey: 'k'),
        timeout: const Duration(milliseconds: 20),
        httpClient: MockClient((http.Request r) async {
          calls++;
          if (calls == 1) throw http.ClientException('断网');
          await Future<void>.delayed(const Duration(milliseconds: 80));
          return okBody('迟到');
        }),
      );
      final LlmReply r = await c.chat(
        messages: <LlmMessage>[LlmMessage.user('x')],
      );
      expect(calls, 2);
      expect(r.failure, LlmFailure.timeout);
      expect(r.detail, contains('已重试 1 次'));
    });

    test('调用点放宽的时限（拆解 90s 那种）照样只等一份，不翻倍', () async {
      int calls = 0;
      final LlmClient c = LlmClient(
        config: const LlmConfig(apiKey: 'k'),
        httpClient: MockClient((http.Request r) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 80));
          return okBody('迟到');
        }),
      );
      final LlmReply r = await c.chat(
        messages: <LlmMessage>[LlmMessage.user('x')],
        timeout: const Duration(milliseconds: 25),
      );
      expect(r.failure, LlmFailure.timeout);
      expect(calls, 1, reason: '没有第二趟');
    });

    test('严格模式超时同样只发一次', () async {
      int calls = 0;
      final LlmClient c = LlmClient(
        config: const LlmConfig(apiKey: 'k', strict: true),
        timeout: const Duration(milliseconds: 20),
        httpClient: MockClient((http.Request r) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 60));
          return okBody('迟到');
        }),
      );
      final LlmReply r = await c.chat(
        messages: <LlmMessage>[LlmMessage.user('x')],
      );
      expect(r.failure, LlmFailure.timeout);
      expect(calls, 1);
    });

    test('503 非严格模式仍重试 1 次（A5 不变）', () async {
      int calls = 0;
      final LlmClient c = LlmClient(
        config: const LlmConfig(apiKey: 'k'),
        httpClient: MockClient((http.Request r) async {
          calls++;
          return calls == 1
              ? http.Response('No available channel', 503)
              : okBody('好了');
        }),
      );
      final LlmReply r = await c.chat(
        messages: <LlmMessage>[LlmMessage.user('x')],
      );
      expect(calls, 2);
      expect(r.text, '好了');
    });
  });

  // ═══════════ G2.4 · 视觉校验 30s / 用完关客户端 ═══════════
  group('G2.4 · VisionService', () {
    const Quest quest = Quest.demo;

    test('视觉校验时限集中成常量 30s，生产客户端用的就是它', () {
      expect(VisionService.kVerifyTimeout, const Duration(seconds: 30));
      final LlmClient c = VisionService.defaultClient(const LlmConfig());
      expect(c.timeout, VisionService.kVerifyTimeout);
      c.close();
      // 交单等待（宿主 C7 定案）不跟着动
      expect(EvidenceChecks.kSubmitWait, const Duration(seconds: 20));
    });

    test('自己建的客户端：校验完就 close（成功、超时都关）', () async {
      for (final Duration delay in <Duration>[
        Duration.zero,
        const Duration(milliseconds: 80),
      ]) {
        final _Spy spy = _Spy((http.Request r) async {
          await Future<void>.delayed(delay);
          return okBody('{"match": true, "note": "可信"}');
        });
        final VisionService v = VisionService(
          clientFactory: (LlmConfig c) => LlmClient(
            config: c,
            timeout: const Duration(milliseconds: 30),
            httpClient: spy,
          ),
          ownsClients: true,
        );
        await v.verify(
          quest: quest,
          base64Images: <String>['QUJD'],
          settings: const AgentSettings(apiKey: 'k'),
        );
        expect(spy.closed, isTrue, reason: 'delay=$delay');
      }
    });

    test('注入的工厂默认不关：反复交回同一个客户端也不会被关坏', () async {
      final _Spy spy = _Spy(
        (http.Request r) async => okBody('{"match": true, "note": "可信"}'),
      );
      final LlmClient shared = LlmClient(
        config: const LlmConfig(apiKey: 'k'),
        httpClient: spy,
      );
      final VisionService v = VisionService(clientFactory: (_) => shared);
      for (int i = 0; i < 2; i++) {
        final VisionVerdict r = await v.verify(
          quest: quest,
          base64Images: <String>['QUJD'],
          settings: const AgentSettings(apiKey: 'k'),
        );
        expect(r.status, EvidenceStatus.verified);
      }
      expect(spy.closed, isFalse);
      expect(spy.requests, 2);
    });

    test('视觉校验的配置跟设置走：上下文钳 max_tokens，温度由调用点 0 优先', () async {
      LlmConfig? seen;
      Map<String, dynamic>? body;
      final VisionService v = VisionService(
        clientFactory: (LlmConfig c) {
          seen = c;
          return LlmClient(
            config: c,
            httpClient: MockClient((http.Request r) async {
              body = jsonDecode(r.body) as Map<String, dynamic>;
              return okBody('{"match": true, "note": "可信"}');
            }),
          );
        },
      );
      await v.verify(
        quest: quest,
        base64Images: <String>['QUJD'],
        settings: const AgentSettings(
          apiKey: 'k',
          temperature: 1.2,
          contextLen: 2048,
          reasoningEffort: 'high',
        ),
      );
      expect(seen?.temperature, 1.2);
      expect(seen?.contextLen, 2048);
      expect(body!['temperature'], 0, reason: '判词要稳：调用点显式 0 优先');
      expect(body!['max_tokens'], 512, reason: '512 < 上限 2048，原样');
      expect(body!['reasoning_effort'], 'high');
      expect(body!.containsKey('stream'), isFalse);
    });
  });

  // ═══════════ G2.4 · 交单即封存：迟到的结论不改已结算的单 ═══════════
  group('G2.4 · 结算后才回来的校验结论被丢弃', () {
    EvidenceShot shot(String id) => EvidenceShot(
      id: id,
      path: '',
      status: EvidenceStatus.unverified,
      takenAt: DateTime(2026, 11, 6),
    );

    test('收官那单 await 拆解期间回来的「不符」：gone，结算读数是交单那一刻的', () async {
      final Goal oneRing = Goal(
        text: '测试目标',
        short: '测试',
        at: DateTime(2026, 1, 1),
        plan: const <PlanTask>[
          PlanTask(
            index: 0,
            short: '一环',
            title: '唯一的一环',
            proof: '截图',
            minutes: 15,
            rank: 'E',
          ),
        ],
      );
      final QuestFlow f = QuestFlow(host: HostState.empty, goal: oneRing);
      final Completer<Goal> mint = Completer<Goal>();
      f.nextGoalHook = (Goal prev, int c, int t, int l) => mint.future;
      f.accept(
        Quest(
          serial: 908,
          kind: 'main',
          planIndex: 0,
          planTotal: 1,
          goalId: oneRing.id,
          name: '唯一的一环',
          reason: '',
          proof: '截图',
          minutes: 15,
          rank: 'E',
          attrs: const <String, int>{'体': 1},
        ),
      );
      final EvidenceChecks checks = EvidenceChecks(
        submitWait: const Duration(milliseconds: 20),
      );
      final Completer<VisionVerdict> slow = Completer<VisionVerdict>();
      final List<EvidenceApply> applied = <EvidenceApply>[];
      // 主壳 `_admitEvidence` + `_onEvidenceVerdict` 的同款接线
      for (final String id in <String>['a', 'b']) {
        expect(f.addEvidence(shot(id)), isTrue);
        checks.start(
          id,
          id == 'a'
              ? slow.future
              : Future<VisionVerdict>.value(const VisionVerdict.verified('可信')),
          (VisionVerdict v) => applied.add(f.applyVerdict(id, v)),
        );
      }
      // 交单：b 等到了（已校验），a 没等到（20s 上限）→ 照收按未校验计
      expect(await checks.waitFor(<String>['a', 'b']), isFalse);
      final ActiveQuest settling = f.active!;
      final Future<QuestResult> settled = f.settle(forceCrit: false);
      expect(settling.sealed, isTrue);
      // G4.1：交单即结清，await 拆解期间执行中已经清空（单据本身还在 settling 手里）
      expect(f.active, isNull, reason: '还在 await 拆解，但这一单已结清');

      // a 的「不符」这时才回来 —— 不许把证据从已入账的单里撤掉
      slow.complete(const VisionVerdict.mismatch('这是一束花'));
      await Future<void>.delayed(Duration.zero);
      expect(applied, <EvidenceApply>[EvidenceApply.kept, EvidenceApply.gone]);
      expect(settling.photos, 2);

      mint.complete(
        Goal(
          text: '下一条',
          short: '下一条',
          at: DateTime(2030, 1, 1),
          plan: const <PlanTask>[
            PlanTask(
              index: 0,
              short: '一',
              title: '下一条 · 一',
              proof: '截图',
              minutes: 20,
              rank: 'E',
            ),
          ],
        ),
      );
      final QuestResult r = await settled;
      expect(r.photos, 2);
      expect(r.verified, 1);
      expect(r.chance, closeTo(.06 + .07 + .04, 1e-9));
      expect(f.active, isNull);
    });

    test('普通结算后回来的结论 / 下一单接上后回来的结论：都是 gone，不碰新单', () async {
      final QuestFlow f = QuestFlow(host: HostState.empty, goal: Goal.demo());
      f.accept(Quest.demo);
      f.addEvidence(shot('old'));
      await f.settle(forceCrit: false);
      expect(
        f.applyVerdict('old', const VisionVerdict.mismatch('晚了')),
        EvidenceApply.gone,
      );
      // 下一单接上、也有自己的证据：旧 id 的结论落不到它头上
      f.accept(Quest.demo);
      f.addEvidence(shot('new'));
      expect(
        f.applyVerdict('old', const VisionVerdict.mismatch('晚了')),
        EvidenceApply.gone,
      );
      expect(f.active!.sealed, isFalse);
      expect(f.active!.evidence.single.id, 'new');
    });
  });

  // ═══════════ G2.3 · 设置 → 配置（唯一折算点）═══════════
  group('G2.3 · AgentSettings.llmConfig', () {
    test('温度 / 上下文 / 端点三件套 / 思考档位 / 严格模式全部带上', () {
      const AgentSettings s = AgentSettings(
        apiKey: 'k',
        baseUrl: 'https://x.test/v1',
        model: 'm',
        reasoningEffort: 'max',
        temperature: .3,
        contextLen: 4096,
      );
      final LlmConfig c = s.llmConfig(strict: true);
      expect(c.apiKey, 'k');
      expect(c.baseUrl, 'https://x.test/v1');
      expect(c.model, 'm');
      expect(c.reasoningEffort, 'max');
      expect(c.temperature, .3);
      expect(c.contextLen, 4096);
      expect(c.strict, isTrue);
      expect(s.llmConfig().strict, isFalse);
    });

    test('「没变就不重建」守卫：只改温度 / 只改上下文都算变了，全同才相等', () {
      const AgentSettings base = AgentSettings(apiKey: 'k');
      expect(base.llmConfig(), base.llmConfig());
      expect(base.llmConfig().hashCode, base.llmConfig().hashCode);
      expect(
        base.copyWith(temperature: .2).llmConfig(),
        isNot(base.llmConfig()),
      );
      expect(
        base.copyWith(contextLen: 2048).llmConfig(),
        isNot(base.llmConfig()),
      );
      expect(base.llmConfig(strict: true), isNot(base.llmConfig()));
      // 非 LLM 字段（音效 / 视觉开关）不影响配置 → 不重建网关
      expect(
        base.copyWith(sound: false, visionEnabled: false).llmConfig(),
        base.llmConfig(),
      );
    });

    test('老档里存了 stream:true：读得进来，但不再生效、下次存档就消失', () async {
      final AgentSettings s = AgentSettings.fromJson(<String, dynamic>{
        'apiKey': 'k',
        'stream': true,
      }, fallback: const AgentSettings());
      expect(s.toJson().containsKey('stream'), isFalse);
      Map<String, dynamic>? body;
      final LlmClient c = LlmClient(
        config: s.llmConfig(),
        httpClient: MockClient((http.Request r) async {
          body = jsonDecode(r.body) as Map<String, dynamic>;
          return okBody('嗯。');
        }),
      );
      await c.chat(messages: <LlmMessage>[LlmMessage.user('x')]);
      expect(body!.containsKey('stream'), isFalse);
    });
  });

  // ═══════════ G2.3 · 主链路真的用上了设置页的温度 / 上下文 ═══════════
  group('G2.3 · 主链路请求体', () {
    Future<Map<String, dynamic>> lineBody(AgentSettings s) async {
      Map<String, dynamic>? body;
      final LlmClient client = LlmClient(
        config: s.llmConfig(),
        httpClient: MockClient((http.Request r) async {
          body = jsonDecode(r.body) as Map<String, dynamic>;
          return okBody('[smug]行吧。');
        }),
      );
      final SystemCopyProvider p = SystemCopyProvider(llm: LlmGateway(client));
      await p.dispatchLine(const CopyContext());
      return body!;
    }

    test('台词跟设置页温度；默认仍是 0.8（与改造前硬编码同值）', () async {
      expect(
        (await lineBody(const AgentSettings(apiKey: 'k')))['temperature'],
        .8,
      );
      expect(
        (await lineBody(
          const AgentSettings(apiKey: 'k', temperature: .3),
        ))['temperature'],
        .3,
      );
    });

    test('上下文上限钳台词预算（4k → 2k）；0 = 不钳', () async {
      expect(
        (await lineBody(
          const AgentSettings(apiKey: 'k', contextLen: 2048),
        ))['max_tokens'],
        2048,
      );
      expect(
        (await lineBody(const AgentSettings(apiKey: 'k')))['max_tokens'],
        kLineMaxTokens,
      );
    });

    test('上限把「思考吃光就抬预算」钳回原值时不白跑第二趟', () async {
      Future<List<int>> budgets(int contextLen) async {
        final List<int> seen = <int>[];
        final LlmClient c = LlmClient(
          config: LlmConfig(apiKey: 'k', contextLen: contextLen),
          httpClient: MockClient((http.Request r) async {
            seen.add(
              (jsonDecode(r.body) as Map<String, dynamic>)['max_tokens'] as int,
            );
            return okBody('', finish: 'length');
          }),
        );
        await c.chat(
          messages: <LlmMessage>[LlmMessage.user('x')],
          maxTokens: 4096,
        );
        return seen;
      }

      expect(await budgets(2048), <int>[2048], reason: '抬不动 → 只发一次');
      expect(await budgets(8192), <int>[4096, 8192], reason: '能抬到上限就抬');
      expect(await budgets(0), <int>[4096, 12288], reason: '不钳制时照旧 ×3');
    });
  });

  // ═══════════ G2.3 · 系统抽屉的视觉校验开关（所有构建都露）═══════════
  group('G2.3 · RefSheet 视觉校验开关', () {
    Future<void> pumpSheet(
      WidgetTester tester, {
      required bool vision,
      ValueChanged<bool>? onVision,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RefSheet(
              visible: true,
              sound: true,
              onSound: (bool _) {},
              onClose: () {},
              vision: vision,
              onVision: onVision,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
    }

    testWidgets('有接线就显示，点一下回调取反', (WidgetTester tester) async {
      final List<bool> got = <bool>[];
      await pumpSheet(tester, vision: true, onVision: got.add);
      expect(find.text('证据视觉校验'), findsOneWidget);
      await tester.tap(find.text('证据视觉校验'));
      await tester.pump();
      expect(got, <bool>[false]);
    });

    testWidgets('没接线（onVision 为 null）不显示这一行', (WidgetTester tester) async {
      await pumpSheet(tester, vision: true);
      expect(find.text('证据视觉校验'), findsNothing);
    });
  });
}

/// 记录 close 与请求次数的假传输层
class _Spy extends http.BaseClient {
  _Spy(this._handler);

  final Future<http.Response> Function(http.Request r) _handler;
  bool closed = false;
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    final http.Request r = request as http.Request;
    final http.Response resp = await _handler(r);
    return http.StreamedResponse(
      Stream<List<int>>.value(resp.bodyBytes),
      resp.statusCode,
      headers: resp.headers,
      request: request,
    );
  }

  @override
  void close() => closed = true;
}
