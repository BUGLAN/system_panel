import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:system_panel/agent/copy.dart';
import 'package:system_panel/agent/memory.dart';
import 'package:system_panel/chat/chat_history.dart';
import 'package:system_panel/chat/chat_panel.dart';
import 'package:system_panel/chat/chat_service.dart';
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
      expect(find.text('思考中…'), findsOneWidget);
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
