import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:system_panel/data/rewards.dart';
import 'package:system_panel/design/ref.dart';
import 'package:system_panel/state/quest.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/quest_flow.dart';
import 'package:system_panel/ui/ref/ref_exec.dart';
import 'package:system_panel/ui/ref/ref_inputs.dart';

/// docs/50 第二轮走查 E2 的回归网（E2.2 评级口径的分档用例在 checkin_quest_test）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  testWidgets('E2.1：拒收原因留在槽下（直到下一张入槽 / 换一单）', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    Widget exec(String? note) => MaterialApp(
      home: Scaffold(
        backgroundColor: Ref.bg,
        body: RefExec(
          quest: Quest.demo,
          elapsed: const Duration(minutes: 2),
          rejectNote: note,
        ),
      ),
    );
    await tester.pumpWidget(exec('画面里是一片花，没有卷尺读数'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('ref.exec.rejectNote')), findsOneWidget);
    expect(find.text('上一张被拒：画面里是一片花，没有卷尺读数'), findsOneWidget);
    await tester.pumpWidget(exec(null));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('ref.exec.rejectNote')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test('E2.4：F 级补救单经验保底 1（原来减半后是 0）；非补救不受影响', () {
    final Payout r = Rewards.payout(
      rank: 'F',
      crit: false,
      dbl: false,
      remedy: true,
    );
    expect(r.exp, greaterThanOrEqualTo(1));
    expect(r.baseExp, greaterThanOrEqualTo(1));
    final Payout plain = Rewards.payout(rank: 'F', crit: false, dbl: false);
    expect(plain.exp, Rewards.expOf('F'));
  });

  group('E2.6 拼音组字', () {
    test('组字中：已上屏文本去掉拼音，判定为组字', () {
      const TextEditingValue v = TextEditingValue(
        text: '两月liang yue',
        composing: TextRange(start: 2, end: 11),
      );
      expect(refIsComposing(v), isTrue);
      expect(refCommittedText(v), '两月');
    });

    test('没有组字：原样返回', () {
      const TextEditingValue v = TextEditingValue(text: '两月背完四级词汇');
      expect(refIsComposing(v), isFalse);
      expect(refCommittedText(v), '两月背完四级词汇');
    });
  });

  group('E2.2 战报评级落库', () {
    test('PlanTask.grade 存档往返；老存档没有 = null', () {
      const PlanTask t = PlanTask(
        index: 0,
        short: '测词',
        title: '测 30 词摸底',
        proof: '截图',
        minutes: 20,
        rank: 'E',
        state: PlanState.done,
        grade: 'A',
      );
      expect(PlanTask.fromJson(t.toJson()).grade, 'A');
      final Map<String, dynamic> old = t.toJson()..remove('grade');
      expect(PlanTask.fromJson(old).grade, isNull);
    });

    test('结算把评级写进清单那一格（主线卡战报读它）', () async {
      final QuestFlow f = QuestFlow.demo();
      final int i = f.head!.planIndex;
      f.accept(f.head!);
      await f.settle(forceCrit: false);
      expect(f.goal.plan[i].grade, isNotNull);
    });
  });
}
