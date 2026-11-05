import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:system_panel/chat/chat_history.dart';
import 'package:system_panel/design/ref.dart';
import 'package:system_panel/state/quest.dart';
import 'package:system_panel/state/quest_flow.dart';
import 'package:system_panel/ui/ref/ref_board.dart';

/// docs/50 第二轮走查 E1 缺陷的回归网（E1.4 的规则用例在 quest_flow_test）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  group('E1.2 / E1.5 重置存档要清掉的旁路存储', () {
    test('ChatHistory.clear：内存与落盘一起清，重新读档是空的', () async {
      final ChatHistory h = ChatHistory();
      await h.append(ChatMessage.host('m1', '查状态'));
      await h.clear();
      expect(h.messages, isEmpty);
      final ChatHistory again = ChatHistory();
      await again.load();
      expect(again.messages, isEmpty);
    });

    test('HistoryLog.clear：排在在途追加之后（档案「累计 EXP」不再带上旧档）', () async {
      final HistoryLog log = HistoryLog();
      final HistoryEntry e = HistoryEntry(
        at: DateTime(2026, 11, 5),
        name: '旧档那一单',
        rank: 'E',
        kind: 'main',
        exp: 1,
        coin: 5,
        streak: 1,
        result: 'clear',
      );
      // 不 await：模拟结算刚写、紧接着就重置
      log.append(e);
      await log.clear();
      expect(await log.entries(), isEmpty);
      expect(await HistoryLog().entries(), isEmpty);
    });
  });

  group('E1.3 委托板主线按顺序', () {
    testWidgets('锁住的主线单写「锁定」、不盖「已接单」章；能接的照常', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      Quest main(int serial, int i) => Quest(
        serial: serial,
        kind: 'main',
        planIndex: i,
        planTotal: 60,
        goalId: 'g',
        name: '第 ${i + 1} 单',
        reason: '',
        proof: '截图',
        minutes: 20,
        rank: 'E',
        attrs: const <String, int>{'智': 1},
      );
      final List<Quest> tapped = <Quest>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Ref.bg,
            body: RefBoard(
              quests: <Quest>[main(1, 0), main(2, 1)],
              filter: 'all',
              onFilter: (_) {},
              onTap: tapped.add,
              isLocked: (Quest q) => q.planIndex > 0,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));
      expect(tester.takeException(), isNull);
      // 第 1 张「接单」、第 2 张「锁定」（竖排逐字）
      expect(find.text('锁'), findsOneWidget);
      expect(find.text('定'), findsOneWidget);
      expect(find.text('接'), findsOneWidget);
      await tester.tap(find.text('第 2 单'));
      await tester.pump(const Duration(milliseconds: 100));
      // 锁住的单不盖章、直接交给调用方拦（由主壳说明原因）
      expect(tapped.map((Quest q) => q.serial), <int>[2]);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
