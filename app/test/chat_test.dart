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
import 'package:system_panel/agent/memory.dart';
import 'package:system_panel/agent/settings_store.dart';
import 'package:system_panel/agent/tools.dart';
import 'package:system_panel/chat/chat_history.dart';
import 'package:system_panel/chat/chat_panel.dart';
import 'package:system_panel/chat/chat_service.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/host_state.dart';
import 'package:system_panel/state/quest.dart';
import 'package:system_panel/state/result.dart';
import 'package:system_panel/widgets/chat_bar.dart';
import 'package:system_panel/widgets/result_panel.dart';
import 'package:system_panel/widgets/type_text.dart';

/// 对话层三件（docs/18 §2.6）：历史持久化 / 回复服务兜底 / 面板 UI。
/// 全离线：存储用内存实现，LLM 用假网关。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 每个用例一块干净的内存存储
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  group('ChatHistory（opus-v2/chat/v1）', () {
    test('追加 → 新实例读回，逐条一致（重启仍在）', () async {
      final ChatHistory h = ChatHistory()
        ..messages = <ChatMessage>[];
      await h.append(ChatMessage.host('m1', '今天不想跑'));
      await h.append(
        ChatMessage.sys('m2', '腿长在你身上。跑。', emotion: 'annoyed'),
      );
      final ChatHistory back = ChatHistory();
      await back.load();
      expect(back.loaded, isTrue);
      expect(back.messages.length, 2);
      expect(back.messages[0].fromHost, isTrue);
      expect(back.messages[0].text, '今天不想跑');
      expect(back.messages[1].fromHost, isFalse);
      expect(back.messages[1].text, '腿长在你身上。跑。');
      expect(back.messages[1].emotion, 'annoyed');
    });

    test('滚动窗口：满 200 删最旧', () async {
      final ChatHistory h = ChatHistory();
      for (int i = 0; i < ChatHistory.maxEntries + 5; i++) {
        await h.append(ChatMessage.host('m$i', '第 $i 句'));
      }
      expect(h.messages.length, ChatHistory.maxEntries);
      expect(h.messages.first.text, '第 5 句'); // 最旧的 5 条被滚掉
      final ChatHistory back = ChatHistory();
      await back.load();
      expect(back.messages.length, ChatHistory.maxEntries);
      expect(back.messages.first.text, '第 5 句');
    });

    test('坏档 → 空表不崩', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
        ChatHistory.key: '{not json',
      });
      final ChatHistory h = ChatHistory();
      await h.load();
      expect(h.messages, isEmpty);
    });

    test('时间分组头：今天 / 昨天 / M月D日', () {
      final DateTime now = DateTime.now();
      expect(
        ChatHistory.dayLabel(now.subtract(const Duration(hours: 1))),
        '今天',
      );
      expect(
        ChatHistory.dayLabel(now.subtract(const Duration(days: 1))),
        '昨天',
      );
      expect(
        ChatHistory.dayLabel(now.subtract(const Duration(days: 9))),
        '${now.subtract(const Duration(days: 9)).month}月'
        '${now.subtract(const Duration(days: 9)).day}日',
      );
    });
  });

  group('ChatService（人设 + 记忆 + LLM，兜底铁律）', () {
    test('无网关（未配 Key 等价态）→ 固定 5 句兜底之一，情绪 annoyed', () async {
      final ChatMessage r = await ChatService().reply('在吗');
      expect(ChatService.fallbackLines, contains(r.text));
      expect(r.emotion, 'annoyed');
      expect(r.fromHost, isFalse);
    });

    test('LLM 回复：剥 [情绪] 标签，正文进气泡', () async {
      final ChatService svc = ChatService(
        gateway: _FakeGateway('[smug]哼，行吧。给你个眼神。'),
      );
      final ChatMessage r = await svc.reply('我做到了');
      expect(r.text, '哼，行吧。给你个眼神。');
      expect(r.emotion, 'smug');
    });

    test('LLM 空话/失败 → 兜底', () async {
      expect(
        (await ChatService(gateway: _FakeGateway('   ')).reply('x')).text,
        isNot('   '),
      );
      expect(
        (await ChatService(gateway: const _NullGateway()).reply('x')).text,
        isIn(ChatService.fallbackLines),
      );
    });

    test('记忆注入：digest 结果进 messages（凭据可见）', () async {
      final MemoryStore mem = MemoryStore();
      await mem.add('宿主通常 1-2 点睡', source: MemorySource.chat);
      String? sent;
      final ChatService svc = ChatService(
        gateway: _RecordingGateway('[neutral]收到。', onMessages: (m) => sent = m),
        memory: mem,
      );
      await svc.reply('几点睡算熬夜？');
      expect(sent, isNotNull);
      expect(sent!, contains('宿主通常 1-2 点睡'));
    });

    test('近几轮历史带进上下文（role 对齐）', () async {
      String? sent;
      final ChatService svc = ChatService(
        gateway: _RecordingGateway('[neutral]好。', onMessages: (m) => sent = m),
      );
      final List<ChatMessage> history = <ChatMessage>[
        ChatMessage.host('a', '上一句'),
        ChatMessage.sys('b', '上一答'),
      ];
      await svc.reply('这一句', history: history);
      // system prompt 永远在首（人设保持机制），本轮用户输入收尾
      expect(sent!, contains('role: system'));
      expect(sent!, contains('role: user'));
      expect(sent!, contains('role: assistant'));
      expect(sent!.indexOf('role: system'), lessThan(sent!.indexOf('role: user')));
      expect(sent!, contains('上一句'));
      expect(sent!, contains('上一答'));
      expect(sent!.lastIndexOf('这一句'), greaterThan(sent!.indexOf('上一答')));
    });
  });

  group('ChatPanel（名牌 / 双向气泡 / 时间分组 / 语音预留）', () {
    Future<void> mount(
      WidgetTester tester,
      List<ChatMessage> messages, {
      bool thinking = false,
      bool settle = true,
      ValueChanged<String>? onSend,
      VoidCallback? onVoiceTap,
    }) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                ChatPanel(
                  visible: true,
                  messages: messages,
                  thinking: thinking,
                  onSend: onSend,
                  onVoiceTap: onVoiceTap,
                ),
              ],
            ),
          ),
        ),
      );
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
      }
    }

    testWidgets('名牌 + 双向气泡 + 分组头都在，层序压在最上（不遮挡命中）', (
      WidgetTester tester,
    ) async {
      Widget panel(List<ChatMessage> messages) => MaterialApp(
            home: Scaffold(
              body: Stack(
                children: <Widget>[
                  ChatPanel(visible: true, messages: messages),
                ],
              ),
            ),
          );
      // 先只挂宿主那条（历史：已读过，不打字）
      await tester.pumpWidget(panel(<ChatMessage>[ChatMessage.host('a', '今天不想跑')]));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat.name')), findsOneWidget);
      expect(find.text('小祥'), findsOneWidget);
      expect(find.text('系统娘 · 在线'), findsOneWidget);
      expect(find.text('今天不想跑'), findsOneWidget); // 宿主（右）
      expect(find.byType(TypeText), findsNothing); // 历史不打字
      // 她回复到达（main.dart setState 追加）→ 最新一条进气泡打字机
      await tester.pumpWidget(panel(<ChatMessage>[
        ChatMessage.host('a', '今天不想跑'),
        ChatMessage.sys('b', '腿长在你身上。', emotion: 'annoyed'),
      ]));
      await tester.pump();
      expect(find.byType(TypeText), findsOneWidget);
      // 打完 → 落成纯文本（打字机只演一次）
      await tester.pumpAndSettle();
      expect(find.byType(TypeText), findsNothing);
      expect(find.text('腿长在你身上。'), findsOneWidget);
      // 时间分组头
      expect(find.byKey(const Key('chat.day.0')), findsOneWidget);
      // 语音入口：按钮 + 「即将支持」角标同屏
      expect(find.byKey(const Key('chat.voice')), findsOneWidget);
      expect(find.text('即将支持'), findsOneWidget);
      // 文本入口：输入框 + 发送同屏
      expect(find.byKey(const Key('chat.input')), findsOneWidget);
      expect(find.byKey(const Key('chat.send')), findsOneWidget);
      // 关闭钮
      expect(find.byKey(const Key('chat.close')), findsOneWidget);
    });

    testWidgets('发送：输入 + 回车/发送都回调', (WidgetTester tester) async {
      final List<String> sent = <String>[];
      await mount(tester, <ChatMessage>[], onSend: sent.add);
      await tester.enterText(find.byKey(const Key('chat.input')), '打卡了');
      await tester.tap(find.byKey(const Key('chat.send')));
      await tester.pump();
      expect(sent, <String>['打卡了']);
    });

    testWidgets('语音钮点击回调（上层弹插话），不假装可用', (WidgetTester tester) async {
      int taps = 0;
      await mount(tester, <ChatMessage>[], onVoiceTap: () => taps++);
      await tester.tap(find.byKey(const Key('chat.voice')));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('thinking：占位行出现', (WidgetTester tester) async {
      await mount(
        tester,
        <ChatMessage>[ChatMessage.host('a', 'hi')],
        thinking: true,
      );
      expect(find.byKey(const Key('chat.thinking')), findsOneWidget);
      // t26/P2-3：静态「思考中…」换成「思考中」+ 三点呼吸（600ms 循环、
      // 相位差 200ms，参数钉在 fx_test）。chat_test 不在本卡 inScope，
      // 这里只随文案口径改这一个字（越界但必要，照 t24 惯例申报）。
      expect(find.text('思考中'), findsOneWidget);
    });

    testWidgets('收起时断命中（IgnorePointer）', (WidgetTester tester) async {
      int closed = 0;
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                ChatPanel(
                  visible: false,
                  messages: const <ChatMessage>[],
                  onClose: () => closed++,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat.close')), warnIfMissed: false);
      await tester.pump();
      expect(closed, 0);
    });
  });

  group('ChatBar（输入栏本体）', () {
    testWidgets('enabled=false（thinking 锁）：有字也不发送', (WidgetTester tester) async {
      final List<String> sent = <String>[];
      final TextEditingController c = TextEditingController(text: '你好');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatBar(controller: c, enabled: false, onSend: sent.add),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('chat.send')));
      await tester.pump();
      expect(sent, isEmpty);
    });

    testWidgets('空文本/纯空白不发送', (WidgetTester tester) async {
      final List<String> sent = <String>[];
      final TextEditingController c = TextEditingController(text: '   ');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatBar(controller: c, onSend: sent.add)),
        ),
      );
      await tester.tap(find.byKey(const Key('chat.send')));
      await tester.pump();
      expect(sent, isEmpty);
    });
  });

  group('对话入口与「找小祥说说」', () {
    testWidgets('ChatEntryButton：点它开聊', (WidgetTester tester) async {
      int opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                Center(child: ChatEntryButton(onTap: () => opens++)),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('chat.entry')));
      await tester.pump();
      expect(opens, 1);
    });

    testWidgets('结算页「找小祥说说」次级钮：渲染且可点', (WidgetTester tester) async {
      int talks = 0;
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                ResultPanel(
                  result: QuestResult.demo,
                  visible: true,
                  animate: false,
                  onTalk: () => talks++,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('找小祥说说'), findsOneWidget);
      await tester.tap(find.byKey(const Key('result.talk')));
      await tester.pump();
      expect(talks, 1);
    });
  });

  // ═══════════ A3 · 工具接线（docs/19 §A3）═══════════

  group('A3 · function calling 全链路（mock LlmClient，配 Key）', () {
    /// 一张日常（MockAgentContext 队列用）
    Quest daily({int serial = 77, String rank = 'D', int minutes = 30}) => Quest(
      serial: serial,
      kind: 'daily',
      ring: 0,
      ringTotal: 0,
      name: '夜跑 3 公里',
      reason: '',
      proof: '跑步 App 截图',
      minutes: minutes,
      rank: rank,
      attrs: const <String, int>{'体': 1},
    );

    /// 工具调用 / 正常回复的 OpenAI 线格式。
    /// ⚠️ arguments 是**字符串化的 JSON**——外层再 encode 一次才有合法转义。
    String toolCall(String name, [Map<String, dynamic> args = const <String, dynamic>{}]) =>
        '{"choices":[{"message":{"content":"","tool_calls":[{"id":"c1",'
        '"type":"function","function":{"name":"$name","arguments":'
        '${jsonEncode(jsonEncode(args))}}}]}}]}';
    String says(String text) =>
        '{"choices":[{"message":{"content":${jsonEncode(text)}}}]}';

    /// 按 (body, status) 序列回话的假 HTTP（录下每个请求体）。
    /// ⚠️ 必须带 utf-8 charset：http 包对无 charset 的响应按 latin1 解码，
    /// 中文响应体会炸「Contains invalid characters」（真端点都带 utf-8 头）。
    http.Client scripted(List<String> bodies, List<(String, int)> responses) =>
        MockClient((http.Request req) async {
          bodies.add(req.body);
          final (String body, int status) = responses.removeAt(0);
          return http.Response(body, status, headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          });
        });

    test('查状态：工具调用 → 执行 → 回填 → 终答（两跳，回执可见）', () async {
      final List<String> bodies = <String>[];
      final LlmClient client = LlmClient(
        config: const LlmConfig(apiKey: 'sk-test'),
        httpClient: scripted(bodies, <(String, int)>[
          (toolCall('get_status'), 200),
          (says('[cold]查完了。一单没交，问什么。'), 200),
        ]),
      );
      final MockAgentContext ctx = MockAgentContext(
        host: HostState.demo,
        goal: Goal.demo(),
        queue: <Quest>[daily()],
      );
      final ChatService svc = ChatService(
        client: client,
        tools: defaultAgentTools(context: ctx, memory: MemoryStore()),
      );
      final List<ChatMessage> out = await svc.respond('我现在什么状态？');
      // 〔工具〕系统条目 + 正式回复
      expect(out, hasLength(2));
      expect(out[0].text, startsWith(ChatService.toolTag));
      expect(out[0].text, contains('get_status'));
      expect(out[0].text, contains('LV7')); // 真实读数进了回执
      expect(out[1].text, '查完了。一单没交，问什么。');
      expect(out[1].emotion, 'cold');
      // 第一次请求带 tools 数组；第二次带回系统回执
      expect(bodies, hasLength(2));
      expect(bodies[0], contains('"tools"'));
      expect(bodies[0], contains('get_status'));
      expect(bodies[1], contains('〔系统回执'));
      expect(bodies[1], contains('LV7'));
    });

    test('换任务：swap_quest 执行后队列真被换掉（候选单顶上）', () async {
      final List<String> bodies = <String>[];
      final LlmClient client = LlmClient(
        config: const LlmConfig(apiKey: 'sk-test'),
        httpClient: scripted(bodies, <(String, int)>[
          (toolCall('swap_quest', <String, dynamic>{'note': '腿疼'}), 200),
          (says('[smug]换好了。跑起来。'), 200),
        ]),
      );
      final MockAgentContext ctx = MockAgentContext(
        host: HostState.demo,
        goal: Goal.demo(),
        queue: <Quest>[daily()],
        nextCandidate: () => Quest(
          serial: 88,
          kind: 'daily',
          ring: 0,
          ringTotal: 0,
          name: '拉伸 15 分钟',
          reason: '',
          proof: '照片',
          minutes: 15,
          rank: 'E',
          attrs: const <String, int>{'敏': 2},
        ),
      );
      final ChatService svc = ChatService(
        client: client,
        tools: defaultAgentTools(context: ctx, memory: MemoryStore()),
      );
      final List<ChatMessage> out = await svc.respond('这单换一个');
      expect(ctx.queue.first.serial, 88); // 队首真被换了
      expect(ctx.queue.first.name, '拉伸 15 分钟');
      expect(out[0].text, contains('换好了'));
      expect(out[0].text, contains('拉伸 15 分钟'));
      expect(out[1].text, '换好了。跑起来。');
    });

    test('调整计划：adjust_plan 的 minutes 走钳制（300 → 180）', () async {
      final List<String> bodies = <String>[];
      final LlmClient client = LlmClient(
        config: const LlmConfig(apiKey: 'sk-test'),
        httpClient: scripted(bodies, <(String, int)>[
          (toolCall('adjust_plan', <String, dynamic>{'minutes': 300}), 200),
          (says('[pleased]180 分钟，做得到吧。'), 200),
        ]),
      );
      final MockAgentContext ctx = MockAgentContext(
        host: HostState.demo,
        goal: Goal.demo(),
        queue: <Quest>[daily()],
      );
      final ChatService svc = ChatService(
        client: client,
        tools: defaultAgentTools(context: ctx, memory: MemoryStore()),
      );
      final List<ChatMessage> out = await svc.respond('这单太重了');
      expect(ctx.queue.first.minutes, 180); // 钳制不回归
      expect(out[0].text, contains('180 分钟'));
      expect(out[1].text, '180 分钟，做得到吧。');
    });

    test('回填形态：她的上一条 + 系统回执以用户消息回注（端点兼容）', () async {
      final List<String> bodies = <String>[];
      final LlmClient client = LlmClient(
        config: const LlmConfig(apiKey: 'sk-test'),
        httpClient: scripted(bodies, <(String, int)>[
          (toolCall('get_status'), 200),
          (says('[neutral]知道了。'), 200),
        ]),
      );
      final ChatService svc = ChatService(
        client: client,
        tools: defaultAgentTools(
          context: MockAgentContext(queue: <Quest>[daily()]),
          memory: MemoryStore(),
        ),
      );
      await svc.respond('查一下');
      expect(bodies[1], contains('正在翻你的档案')); // 她的上一条（占位正文）
      expect(bodies[1], contains('〔系统回执 · 刚才的工具调用结果，供你作答〕'));
    });

    test('工具轮次用尽（模型一直要工具）→ 兜底收口，不吊着用户', () async {
      final List<String> bodies = <String>[];
      final LlmClient client = LlmClient(
        config: const LlmConfig(apiKey: 'sk-test'),
        httpClient: scripted(bodies, <(String, int)>[
          (toolCall('get_status'), 200),
          (toolCall('get_status'), 200),
          (toolCall('get_status'), 200),
          (toolCall('get_status'), 200), // 第 4 次不该发生
        ]),
      );
      final ChatService svc = ChatService(
        client: client,
        tools: defaultAgentTools(
          context: MockAgentContext(queue: <Quest>[daily()]),
          memory: MemoryStore(),
        ),
      );
      final List<ChatMessage> out = await svc.respond('在吗');
      expect(out, hasLength(ChatService.maxToolRounds + 1)); // 3 回执 + 兜底
      expect(ChatService.fallbackLines, contains(out.last.text));
    });

    test('第二跳 LLM 失败（HTTP 500）→ 已执行的工具回执保留 + 兜底收口', () async {
      final List<String> bodies = <String>[];
      final LlmClient client = LlmClient(
        config: const LlmConfig(apiKey: 'sk-test'),
        httpClient: scripted(bodies, <(String, int)>[
          (toolCall('get_status'), 200),
          ('{"error":"boom"}', 500),
        ]),
      );
      final ChatService svc = ChatService(
        client: client,
        tools: defaultAgentTools(
          context: MockAgentContext(queue: <Quest>[daily()]),
          memory: MemoryStore(),
        ),
      );
      final List<ChatMessage> out = await svc.respond('查一下');
      expect(out[0].text, startsWith(ChatService.toolTag)); // 工具真执行了
      expect(ChatService.fallbackLines, contains(out.last.text));
    });

    test('无 Key / 没接客户端 → respond 退化为单条兜底（快捷 chip 场景的本地可用性）', () async {
      final AgentToolRegistry reg = defaultAgentTools(
        context: MockAgentContext(queue: <Quest>[daily()]),
        memory: MemoryStore(),
      );
      // 没接 client
      final List<ChatMessage> a = await ChatService(tools: reg).respond('在吗');
      expect(a, hasLength(1));
      expect(ChatService.fallbackLines, contains(a.first.text));
      // client 没配 Key
      final ChatService b = ChatService(
        client: LlmClient(config: const LlmConfig(apiKey: '')),
        tools: reg,
      );
      final List<ChatMessage> out = await b.respond('在吗');
      expect(out, hasLength(1));
      expect(ChatService.fallbackLines, contains(out.first.text));
    });
  });

  group('A3 · 快捷工具 chip 行与〔工具〕系统条目（ChatPanel）', () {
    Future<void> mount(
      WidgetTester tester, {
      required List<ChatMessage> messages,
      bool thinking = false,
      ValueChanged<String>? onQuickTool,
    }) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                ChatPanel(
                  visible: true,
                  messages: messages,
                  thinking: thinking,
                  onQuickTool: onQuickTool,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('三枚 chip 在（查状态/换任务/调整计划），点按回调工具名', (
      WidgetTester tester,
    ) async {
      final List<String> tapped = <String>[];
      await mount(tester, messages: <ChatMessage>[], onQuickTool: tapped.add);
      expect(find.byKey(const Key('chat.tools')), findsOneWidget);
      expect(find.text('查状态'), findsOneWidget);
      expect(find.text('换任务'), findsOneWidget);
      expect(find.text('调整计划'), findsOneWidget);
      await tester.tap(find.byKey(const Key('chat.tool.get_status')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('chat.tool.adjust_plan')));
      await tester.pump();
      expect(tapped, <String>['get_status', 'adjust_plan']);
    });

    testWidgets('thinking 中 chip 置灰不可点（不重复触发执行）', (WidgetTester tester) async {
      final List<String> tapped = <String>[];
      await mount(
        tester,
        messages: <ChatMessage>[],
        thinking: true,
        onQuickTool: tapped.add,
      );
      await tester.tap(find.byKey(const Key('chat.tool.get_status')), warnIfMissed: false);
      await tester.pump();
      expect(tapped, isEmpty);
    });

    testWidgets('onQuickTool 未接线：chip 不可点（渲染但无回调）', (WidgetTester tester) async {
      await mount(tester, messages: <ChatMessage>[]);
      expect(find.byKey(const Key('chat.tool.swap_quest')), findsOneWidget);
      await tester.tap(find.byKey(const Key('chat.tool.swap_quest')), warnIfMissed: false);
      await tester.pump();
      // 没有 onQuickTool，点了也不炸（回调本身就是 null）
    });

    testWidgets('〔工具〕系统条目：等宽渲染 + 不打字机；她的正式回复照常打字', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      Widget panel(List<ChatMessage> messages) => MaterialApp(
            home: Scaffold(
              body: Stack(
                children: <Widget>[
                  ChatPanel(visible: true, messages: messages),
                ],
              ),
            ),
          );
      // 先只挂宿主那条（历史=已读），随后逐条到货：工具回执 → 她的回复
      // （面板把批量到货当历史，逐条到货才打字——与 main.dart 的逐条 append 一致）
      await tester.pumpWidget(panel(<ChatMessage>[ChatMessage.host('a', '查一下')]));
      await tester.pumpAndSettle();
      await tester.pumpWidget(panel(<ChatMessage>[
        ChatMessage.host('a', '查一下'),
        ChatMessage.sys('t1', '${ChatService.toolTag}get_status：LV7 · ◈340'),
      ]));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat.toolentry.1')), findsOneWidget);
      expect(find.text('${ChatService.toolTag}get_status：LV7 · ◈340'), findsOneWidget);
      expect(find.byType(TypeText), findsNothing); // 系统条目不打字机
      await tester.pumpWidget(panel(<ChatMessage>[
        ChatMessage.host('a', '查一下'),
        ChatMessage.sys('t1', '${ChatService.toolTag}get_status：LV7 · ◈340'),
        ChatMessage.sys('b', '查完了。一单没交。', emotion: 'cold'),
      ]));
      await tester.pump();
      // 打字机只给她的正式回复
      expect(find.byType(TypeText), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(TypeText), findsNothing);
    });
  });

  // ═══════════ TODO-07 · 聊天网关热更（docs/20 遗留观察①）═══════════
  //
  // 验收口径：设置页改 Key/BaseURL/模型名后，**不重启**直接对话即用新值。
  // 手段：SettingsStore 增类级广播（listener/版本号），聊天装配按变更
  // 重建 LlmClient / LlmGateway / ChatService。这里用同一套装配逻辑
  // （守卫、关旧、重建三步照抄 main._applyAgentSettings）+ 假传输层做
  // 机制化测试，防「又改回一次性装配」复发。

  group('TODO-07 · 设置变更 → 网关/客户端重建（免重启）', () {
    /// main._applyAgentSettings 的最小复刻：装配 + 广播订阅 +
    /// 「LLM 三要素没变就不折腾」守卫 + 重建时关旧客户端。
    /// ⚠️ svc/client 必须挂在 [._AgentWiring] **字段**上读——record 解构
    /// 会把重建前的引用拷进局部量，之后就看不见重建了（生产代码读的是
    /// State 字段，没有这个坑）。
    _AgentWiring wire() {
      final _AgentWiring w = _AgentWiring();

      void apply(AgentSettings s) {
        final _RecordingClient t = _RecordingClient(w.reqs.add);
        w.transports.add(t);
        w.client = LlmClient(
          config: LlmConfig(baseUrl: s.baseUrl, apiKey: s.apiKey, model: s.model),
          httpClient: t,
        );
        w.svc = ChatService(
          gateway: LlmGateway(w.client),
          client: w.client,
          memory: MemoryStore(),
        );
      }

      void onSettings(AgentSettings s) {
        final LlmClient old = w.client;
        if (old.config.baseUrl == s.baseUrl &&
            old.config.apiKey == s.apiKey &&
            old.config.model == s.model) {
          return;
        }
        old.close();
        apply(s);
      }

      SettingsStore.addListener(onSettings);
      addTearDown(() => SettingsStore.removeListener(onSettings));
      apply(const AgentSettings(apiKey: 'sk-old'));
      return w;
    }

    test('改 Key/BaseURL/模型名 → 广播 → 客户端/服务重建，旧客户端被关，新对话逐字用新值', () async {
      final _AgentWiring w = wire();
      final ChatService svcBefore = w.svc;
      final LlmClient clientBefore = w.client;

      // 旧配置下的对话：旧 Key、默认端点、默认模型（别名归一）
      await w.svc.reply('在吗');

      // 设置页 save() → SettingsStore 类级广播 → 装配层重建
      final int v0 = SettingsStore.version;
      await SettingsStore().save(const AgentSettings(
        apiKey: 'sk-new',
        baseUrl: 'https://api.example.org/v1',
        model: 'm2',
      ));
      expect(SettingsStore.version, v0 + 1); // 广播确实发出去了
      expect(w.svc, isNot(same(svcBefore))); // 聊天服务重建
      expect(w.client, isNot(same(clientBefore))); // 客户端重建
      expect(w.transports.first.closed, isTrue); // 旧客户端被关（连接池不泄漏）

      // 不重启直接再聊：真回了话（不是兜底），新 Key / 新端点 / 新模型逐字上线
      final ChatMessage r2 = await w.svc.reply('还在吗');
      expect(r2.text, '嗯。');
      expect(w.reqs, hasLength(2));
      expect(w.reqs[0].headers['Authorization'], 'Bearer sk-old');
      expect(w.reqs[0].url.toString(), 'https://api.deepseek.com/chat/completions');
      expect((jsonDecode(w.reqs[0].body) as Map<String, dynamic>)['model'], 'deepseek-flash');
      expect(w.reqs[1].headers['Authorization'], 'Bearer sk-new');
      expect(w.reqs[1].url.toString(), 'https://api.example.org/v1/chat/completions');
      expect((jsonDecode(w.reqs[1].body) as Map<String, dynamic>)['model'], 'm2');
    });

    test('非 LLM 字段变更（音效开关）→ 守卫拦下：客户端与服务原地不动', () async {
      final _AgentWiring w = wire();
      final ChatService svcBefore = w.svc;
      final LlmClient clientBefore = w.client;

      await SettingsStore().save(const AgentSettings(apiKey: 'sk-old', sound: false));

      expect(w.svc, same(svcBefore)); // 没重建
      expect(w.client, same(clientBefore));
      expect(w.transports.single.closed, isFalse);
      expect(w.reqs, isEmpty); // 也没发任何请求
    });

    test('广播机制本体：版本号随 save 自增；监听者抛异常只吞自己；退订后不再收', () async {
      final List<String> got = <String>[];
      void boom(AgentSettings s) => throw StateError('监听者自己炸了');
      void ok(AgentSettings s) => got.add(s.apiKey);
      SettingsStore.addListener(boom);
      SettingsStore.addListener(ok);
      addTearDown(() {
        SettingsStore.removeListener(boom);
        SettingsStore.removeListener(ok);
      });

      final int v0 = SettingsStore.version;
      await SettingsStore().save(const AgentSettings(apiKey: 'sk-x'));
      expect(got, <String>['sk-x']); // ok 照收
      expect(SettingsStore.version, v0 + 1); // 版本照涨

      SettingsStore.removeListener(ok);
      await SettingsStore().save(const AgentSettings(apiKey: 'sk-y'));
      expect(got, <String>['sk-x']); // 退订后不再收
    });

    test('热更与落盘一致：save 后另一个实例 load 得到新值', () async {
      await SettingsStore().save(const AgentSettings(apiKey: 'sk-disk'));
      expect((await SettingsStore().load()).apiKey, 'sk-disk');
    });
  });
}

/// 假网关：回固定文案（含标签）
class _FakeGateway implements CopyLlmGateway {
  _FakeGateway(this.reply);

  final String reply;

  @override
  bool get configured => true;

  @override
  Future<String?> complete({
    required List<Map<String, dynamic>> messages,
    double? temperature,
    int? maxTokens,
    Duration? timeout,
  }) async => reply;
}

/// 永远失败（null）的网关
class _NullGateway implements CopyLlmGateway {
  const _NullGateway();

  @override
  bool get configured => true;

  @override
  Future<String?> complete({
    required List<Map<String, dynamic>> messages,
    double? temperature,
    int? maxTokens,
    Duration? timeout,
  }) async => null;
}

/// 录下发出去的 messages（人设/记忆/历史装配断言用）
class _RecordingGateway implements CopyLlmGateway {
  const _RecordingGateway(this.reply, {this.onMessages});

  final String reply;
  final void Function(String raw)? onMessages;

  @override
  bool get configured => true;

  @override
  Future<String?> complete({
    required List<Map<String, dynamic>> messages,
    double? temperature,
    int? maxTokens,
    Duration? timeout,
  }) async {
    onMessages?.call(messages.toString());
    return reply;
  }
}

/// 假传输层（TODO-07 网关热更测试用）：录下每个请求（Auth 头/URL/body 供
/// 「新值上线」断言），并标记 [closed]——重建时旧客户端必须被关。
/// ⚠️ 响应必须带 utf-8 charset：http 包对无 charset 的响应按 latin1 解码，
/// 中文响应体会炸「Contains invalid characters」（真端点都带 utf-8 头）。
class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.onRequest);

  final void Function(http.Request request) onRequest;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest base) async {
    final http.Request request = base as http.Request;
    onRequest(request);
    final List<int> bytes = utf8.encode(jsonEncode(<String, dynamic>{
      'choices': <Map<String, dynamic>>[
        <String, dynamic>{
          'message': <String, dynamic>{'content': '[neutral]嗯。'},
        },
      ],
    }));
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      200,
      contentLength: bytes.length,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );
  }

  @override
  void close() => closed = true;
}

/// TODO-07 热更测试的装配 holder：`svc`/`client` 是**字段**——广播触发的
/// 重建会当场换指向，测试从同一个 holder 上读到的永远是「当前那份」；
/// `reqs`/`transports` 跨重建累计（证明旧值在线上、新值接棒）。
class _AgentWiring {
  late ChatService svc;
  late LlmClient client;
  final List<http.Request> reqs = <http.Request>[];
  final List<_RecordingClient> transports = <_RecordingClient>[];
}
