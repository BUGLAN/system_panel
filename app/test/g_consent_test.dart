import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:system_panel/agent/goal_match_agent.dart';
import 'package:system_panel/agent/llm_client.dart';
import 'package:system_panel/agent/llm_telemetry.dart';
import 'package:system_panel/agent/mainline_tool.dart';
import 'package:system_panel/agent/tools.dart';
import 'package:system_panel/design/ref.dart';
import 'package:system_panel/main.dart';
import 'package:system_panel/state/consent.dart';
import 'package:system_panel/state/plan_failure.dart';
import 'package:system_panel/state/save_file.dart';
import 'package:system_panel/state/sfx.dart';
import 'package:system_panel/ui/ref/ref_boot.dart';
import 'package:system_panel/ui/ref/ref_consent.dart';
import 'package:system_panel/ui/ref/ref_sheet.dart';
import 'package:system_panel/ui/ref/ref_text.dart';

/// G2.1 隐私同意框架。
///
/// 钉四件事：
///  1. 同意状态的读写（独立 key、读坏按未同意、协议版本变了要重签、重置存档不清它）；
///  2. LlmClient 的类级闸门：拦下时**一个请求都不发**（MockClient 断言零请求），
///     失败类别是 noConsent、上层（目标匹配）映射成 PlanFailureCode.noConsent；
///  3. 同意页 / 协议全文页 / 设置抽屉入口：两种尺寸不溢出、回调接得上；
///  4. 整壳接线：唤醒 → 同意页 → 同意后放行；返回键在同意页上 = 不同意。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
    Sfx.enabled = false; // 测试环境没有音频插件
    LlmClient.consentGate = LlmClient.allowAll;
    LlmTelemetry.reset();
  });

  tearDown(() => LlmClient.consentGate = LlmClient.allowAll);

  // ═══════════════════════════════════════════════════════
  group('同意状态（ConsentStore）', () {
    test('全新安装：没有记录 = 未同意', () async {
      final ConsentStore s = ConsentStore();
      expect(await s.load(), isNull);
      expect(await s.isAccepted(), isFalse);
    });

    test('同意 → 记下当前版本号与时间；读回来一致', () async {
      final DateTime at = DateTime(2026, 11, 6, 9, 30);
      expect(await ConsentStore().accept(at: at), isTrue);
      final ConsentRecord? r = await ConsentStore().load();
      expect(r, isNotNull);
      expect(r!.version, kPolicyVersion);
      expect(r.at, at);
      expect(await ConsentStore().isAccepted(), isTrue);
    });

    test('独立 key：不写进主存档那一格', () async {
      await ConsentStore().accept();
      final String? raw = await SharedPreferencesAsync().getString(
        ConsentStore.key,
      );
      expect(ConsentStore.key, 'opus-v2/consent/v1');
      expect(ConsentStore.key, isNot(SaveFile.key));
      expect(jsonDecode(raw!), containsPair('v', kPolicyVersion));
    });

    test('协议版本变了 → 旧同意不算数，要重签；重签后放行', () async {
      await ConsentStore(policyVersion: 1).accept();
      final ConsentStore v2 = ConsentStore(policyVersion: 2);
      expect(await v2.isAccepted(), isFalse, reason: '同意的是 v1，不能顶 v2');
      // 记录还在（主壳据此显示「协议已更新」而不是首启文案）
      final ConsentRecord? old = await v2.load();
      expect(old?.version, 1);
      expect(old!.coversVersion(2), isFalse);

      await v2.accept();
      expect(await v2.isAccepted(), isTrue);
      expect(
        await ConsentStore(policyVersion: 1).isAccepted(),
        isFalse,
        reason: '只认相等：降级装回 v1 也要重看旧正文',
      );
    });

    test('撤回 → 未同意', () async {
      await ConsentStore().accept();
      await ConsentStore().revoke();
      expect(await ConsentStore().isAccepted(), isFalse);
      expect(await ConsentStore().load(), isNull);
    });

    test('读坏了按未同意（坏 JSON / 形状不对）', () async {
      for (final String bad in <String>[
        'not json',
        '[]',
        '{"v":"1","at":"2026-11-06T00:00:00.000"}',
        '{"v":1}',
        '{"v":1,"at":"昨天"}',
      ]) {
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.withData(<String, Object>{
              ConsentStore.key: bad,
            });
        expect(await ConsentStore().isAccepted(), isFalse, reason: bad);
      }
    });

    test('存储本身抛异常：读按未同意、写返回 false、撤回不抛', () async {
      final ConsentStore s = ConsentStore(prefs: _ThrowingPrefs());
      expect(await s.load(), isNull);
      expect(await s.isAccepted(), isFalse);
      expect(await s.accept(), isFalse);
      await s.revoke(); // 不抛就算过
    });

    test('重置存档不清同意（同意是对 App 的，不是对某份存档的）', () async {
      await ConsentStore().accept();
      await SaveFile().wipe();
      expect(await ConsentStore().isAccepted(), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════
  group('LLM 闸门（LlmClient.consentGate）', () {
    http.Response okBody(String content) => http.Response(
      jsonEncode(<String, dynamic>{
        'choices': <dynamic>[
          <String, dynamic>{
            'message': <String, dynamic>{'content': content},
          },
        ],
      }),
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );

    /// 计数用的假端点：每发一个请求 +1
    LlmClient counted(List<http.Request> sent) => LlmClient(
      config: const LlmConfig(apiKey: 'sk-test'),
      httpClient: MockClient((http.Request r) async {
        sent.add(r);
        return okBody('收到');
      }),
    );

    final List<LlmMessage> msgs = <LlmMessage>[LlmMessage.user('你好')];

    test('默认放行：不接闸门的客户端照常出网（现有测试不受影响）', () async {
      final List<http.Request> sent = <http.Request>[];
      final LlmReply r = await counted(sent).chat(messages: msgs);
      expect(r.ok, isTrue);
      expect(sent, hasLength(1));
    });

    test('未同意 → 零请求，失败类别 noConsent，遥测记一笔', () async {
      LlmClient.consentGate = () => false;
      final List<http.Request> sent = <http.Request>[];
      final LlmReply r = await counted(sent).chat(
        messages: <LlmMessage>[
          LlmMessage.user(
            '看看这张证据',
            images: <String>['data:image/jpeg;base64,AAAA'],
          ),
        ],
      );
      expect(sent, isEmpty, reason: '目标原文 / 聊天 / 证据照片一个字节都不许出门');
      expect(r.ok, isFalse);
      expect(r.failure, LlmFailure.noConsent);
      expect(r.detail, contains('未同意'));
      expect(LlmTelemetry.byKind[LlmFailure.noConsent], 1);
    });

    test('异步闸门（主壳那种先等读档再判）同样拦得住；ping 也拦', () async {
      LlmClient.consentGate = () async => false;
      final List<http.Request> sent = <http.Request>[];
      final LlmClient c = counted(sent);
      expect((await c.chat(messages: msgs)).failure, LlmFailure.noConsent);
      expect((await c.ping()).failure, LlmFailure.noConsent);
      expect(sent, isEmpty);
    });

    test('闸门自己抛异常 → 按拦截处理（隐私上宁可不发）', () async {
      LlmClient.consentGate = () => throw StateError('读不到同意状态');
      final List<http.Request> sent = <http.Request>[];
      final LlmReply r = await counted(sent).chat(messages: msgs);
      expect(r.failure, LlmFailure.noConsent);
      expect(sent, isEmpty);
    });

    test('接上 ConsentStore：同意前拦、同意后放、撤回后立刻又拦', () async {
      final ConsentStore store = ConsentStore();
      LlmClient.consentGate = store.isAccepted;
      final List<http.Request> sent = <http.Request>[];
      final LlmClient c = counted(sent);

      expect((await c.chat(messages: msgs)).ok, isFalse);
      expect(sent, isEmpty);

      await store.accept();
      expect((await c.chat(messages: msgs)).ok, isTrue);
      expect(sent, hasLength(1));

      await store.revoke();
      expect((await c.chat(messages: msgs)).failure, LlmFailure.noConsent);
      expect(sent, hasLength(1), reason: '撤回后不再多发一个');
    });

    test('目标匹配被拦 → 抛 PlanFailureCode.noConsent（不冒充 noKey / 网络）', () async {
      LlmClient.consentGate = () => false;
      final List<http.Request> sent = <http.Request>[];
      final GoalMatchDraft draft = GoalMatchDraft();
      final StrictAgentToolRegistry tools = StrictAgentToolRegistry()
        ..register(setGoalCategoryTool(goalText: '三个月学会弹吉他', draft: draft));
      await expectLater(
        GoalMatchAgent(client: counted(sent))
            .match(goalText: '三个月学会弹吉他', tools: tools, draft: draft),
        throwsA(
          isA<PlanGenerationError>().having(
            (PlanGenerationError e) => e.code,
            'code',
            PlanFailureCode.noConsent,
          ),
        ),
      );
      expect(sent, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════
  Future<void> mountAt(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = Size(size.width * 3, size.height * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(backgroundColor: Ref.bg, body: child),
      ),
    );
    // 显影（RefReveal）最晚一层 140 + 4×80 + 680ms ≈ 1.14s。
    // 要**逐帧**推：一次 pump 一大段只出一帧，计时器到点后才起的动画还停在第 0 帧
    // （位移 30px 还没收回，点按会落空）。核心常转，不能用 pumpAndSettle。
    for (int i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  const List<Size> sizes = <Size>[Size(390, 844), Size(320, 640)];

  group('同意页（RefConsent）', () {
    testWidgets('390×844 与 320×640：三种状态都不溢出，两颗键都在', (
      WidgetTester tester,
    ) async {
      for (final Size size in sizes) {
        for (final (bool declined, bool renew) in <(bool, bool)>[
          (false, false),
          (true, false),
          (false, true),
        ]) {
          await mountAt(
            tester,
            size,
            RefConsent(
              declined: declined,
              renew: renew,
              onAgree: () {},
              onDecline: () {},
              onOpenDoc: (LegalDoc _) {},
            ),
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$size $declined $renew',
          );
          expect(find.byKey(const Key('ref.consent.agree')), findsOneWidget);
          expect(find.byKey(const Key('ref.consent.decline')), findsOneWidget);
          // 底部两颗键钉死在屏内（不随内容滚走）
          final Rect agree = tester.getRect(
            find.byKey(const Key('ref.consent.agree')),
          );
          expect(agree.bottom, lessThanOrEqualTo(size.height));
        }
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('按钮回调：同意 / 不同意 / 两篇协议入口', (WidgetTester tester) async {
      int agrees = 0;
      int declines = 0;
      final List<LegalDoc> opened = <LegalDoc>[];
      await mountAt(
        tester,
        const Size(320, 640),
        RefConsent(
          onAgree: () => agrees++,
          onDecline: () => declines++,
          onOpenDoc: opened.add,
        ),
      );
      await tester.tap(find.byKey(const Key('ref.consent.agree')));
      await tester.tap(find.byKey(const Key('ref.consent.decline')));
      for (final LegalDoc d in LegalDoc.values) {
        final Finder row = find.byKey(Key('ref.consent.doc.${d.name}'));
        await tester.ensureVisible(row); // 小屏上在滚动区下方
        await tester.pump();
        await tester.tap(row);
      }
      await tester.pump();
      expect(agrees, 1);
      expect(declines, 1);
      expect(opened, <LegalDoc>[LegalDoc.agreement, LegalDoc.privacy]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('台词随状态换：首启 / 协议更新 / 不同意', (WidgetTester tester) async {
      String lineOf() => tester
          .widget<RefTypewriter>(find.byKey(const Key('ref.consent.line')))
          .text;
      Widget page({bool declined = false, bool renew = false}) => RefConsent(
        declined: declined,
        renew: renew,
        onAgree: () {},
        onDecline: () {},
        onOpenDoc: (LegalDoc _) {},
      );
      await mountAt(tester, const Size(390, 844), page());
      expect(lineOf(), RefConsent.lineIntro);
      await mountAt(tester, const Size(390, 844), page(renew: true));
      expect(lineOf(), RefConsent.lineRenew);
      expect(find.text('PRIVACY · 协议已更新'), findsOneWidget);
      await mountAt(tester, const Size(390, 844), page(declined: true));
      expect(lineOf(), RefConsent.lineDeclined);
      expect(RefConsent.lineDeclined, contains('没法工作'));
      await tester.pumpWidget(const SizedBox());
    });
  });

  // ═══════════════════════════════════════════════════════
  group('协议全文（RefLegalPage）', () {
    test('按行解析：# 标题分级 / 列表 / 占位 / 空行折叠', () {
      final List<LegalLine> ls = parseLegalText(
        '【占位】正文待宿主提供。\n\n\n# 隐私政策\n## 一、收集\n- 目标原文\n正文一行\n',
      );
      expect(ls.map((LegalLine l) => l.kind).toList(), <LegalLineKind>[
        LegalLineKind.placeholder,
        LegalLineKind.blank,
        LegalLineKind.heading,
        LegalLineKind.heading,
        LegalLineKind.bullet,
        LegalLineKind.body,
        LegalLineKind.blank,
      ]);
      expect(ls[2].text, '隐私政策');
      expect(ls[2].level, 1);
      expect(ls[3].text, '一、收集');
      expect(ls[3].level, 2);
      expect(ls[4].text, '目标原文');
    });

    test('两篇占位正文都打进包里：以「【占位】」开头，章节齐全', () async {
      for (final LegalDoc d in LegalDoc.values) {
        final String raw = await rootBundle.loadString(d.asset);
        expect(raw.startsWith('【占位】正文待宿主提供'), isTrue, reason: d.asset);
        for (final String chapter in <String>[
          '收集哪些信息',
          '用途',
          '第三方 AI 服务',
          '存储与删除',
          '权利',
          '未成年人',
          '联系方式',
        ]) {
          expect(raw, contains(chapter), reason: '${d.asset} 缺「$chapter」');
        }
      }
    });

    testWidgets('两种尺寸不溢出；标题按 # 渲染；返回键回调', (WidgetTester tester) async {
      int closes = 0;
      for (final Size size in sizes) {
        await mountAt(
          tester,
          size,
          RefLegalPage(
            doc: LegalDoc.privacy,
            onClose: () => closes++,
            loader: (String asset) async =>
                '【占位】正文待宿主提供。\n# 隐私政策\n## 一、我们收集哪些信息\n'
                '${'很长的一段正文，' * 40}\n- 列表项',
          ),
        );
        expect(tester.takeException(), isNull, reason: '$size');
        expect(find.text('《隐私政策》'), findsOneWidget);
        expect(find.text('一、我们收集哪些信息'), findsOneWidget);
        expect(find.text('【占位】正文待宿主提供。'), findsOneWidget);
      }
      await tester.tap(find.byKey(const Key('ref.legal.close')));
      expect(closes, 1);
      await tester.pumpWidget(const SizedBox());
    });
  });

  // ═══════════════════════════════════════════════════════
  group('系统设置抽屉入口', () {
    testWidgets('隐私政策 / 用户协议 / 撤回同意三个入口都接得上', (WidgetTester tester) async {
      final List<String> hits = <String>[];
      for (final Size size in sizes) {
        await mountAt(
          tester,
          size,
          RefSheet(
            visible: true,
            sound: true,
            onSound: (bool _) {},
            onClose: () {},
            onReset: () {},
            onAgreement: () => hits.add('agreement'),
            onPrivacy: () => hits.add('privacy'),
            onRevoke: () => hits.add('revoke'),
          ),
        );
        expect(tester.takeException(), isNull, reason: '$size');
        expect(find.byKey(const Key('ref.sheet.legal')), findsOneWidget);
        // 抽屉不可滚：三颗签必须一行排下（折两行会把 debug 抽屉的标题顶出 320×640）
        final double top = tester
            .getRect(find.byKey(const Key('ref.sheet.agreement')))
            .top;
        expect(
          tester.getRect(find.byKey(const Key('ref.sheet.revoke'))).top,
          top,
          reason: '$size',
        );
      }
      for (final String k in <String>['agreement', 'privacy', 'revoke']) {
        await tester.tap(find.byKey(Key('ref.sheet.$k')));
      }
      expect(hits, <String>['agreement', 'privacy', 'revoke']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('不给回调就不出这一行（向后兼容老调用点）', (WidgetTester tester) async {
      await mountAt(
        tester,
        const Size(390, 844),
        RefSheet(
          visible: true,
          sound: true,
          onSound: (bool _) {},
          onClose: () {},
        ),
      );
      expect(find.byKey(const Key('ref.sheet.legal')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  // ═══════════════════════════════════════════════════════
  group('整壳接线', () {
    Future<void> mountShell(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const SysApp());
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('未同意：闸门关着；唤醒先出同意页；返回键 = 不同意；同意后放行并落盘', (
      WidgetTester tester,
    ) async {
      await mountShell(tester);
      expect(await LlmClient.consentGate(), isFalse, reason: '主壳接上了真实同意状态');

      await tester.tap(find.byType(RefBoot));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.byKey(const Key('ref.consent')), findsOneWidget);
      expect(find.byType(RefBoot), findsOneWidget, reason: '同意前不推进场景');

      // 系统返回键：不退 App，她换成「没法工作」那句
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(
        tester
            .widget<RefTypewriter>(find.byKey(const Key('ref.consent.line')))
            .text,
        RefConsent.lineDeclined,
      );
      expect(find.byKey(const Key('ref.consent')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ref.consent.agree')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.byKey(const Key('ref.consent')), findsNothing);
      expect(find.byType(RefBoot), findsNothing, reason: '同意后接着唤醒');
      expect(await LlmClient.consentGate(), isTrue);
      expect(await ConsentStore().isAccepted(), isTrue, reason: '同意已落盘');

      await tester.pumpWidget(const SizedBox());
      expect(await LlmClient.consentGate(), isTrue, reason: '壳卸载后闸门复原成默认放行');
    });

    testWidgets('已同意当前版本：唤醒不出同意页', (WidgetTester tester) async {
      await ConsentStore().accept();
      await mountShell(tester);
      expect(await LlmClient.consentGate(), isTrue);
      await tester.tap(find.byType(RefBoot));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.byKey(const Key('ref.consent')), findsNothing);
      expect(find.byType(RefBoot), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

/// 一碰就抛的存储（模拟实机「存储不可用」）
class _ThrowingPrefs implements SharedPreferencesAsync {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('存储不可用：${invocation.memberName}');
}
