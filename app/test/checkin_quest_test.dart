import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:system_panel/agent/mainline_tool.dart';
import 'package:system_panel/agent/plan_brief.dart';
import 'package:system_panel/agent/tools.dart';
import 'package:system_panel/agent/vision.dart';
import 'package:system_panel/design/ref.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/goal_gen.dart';
import 'package:system_panel/state/host_state.dart';
import 'package:system_panel/state/quest.dart';
import 'package:system_panel/state/quest_flow.dart';
import 'package:system_panel/state/result.dart';
import 'package:system_panel/ui/ref/ref_board.dart';
import 'package:system_panel/ui/ref/ref_exec.dart';
import 'package:system_panel/ui/ref/ref_inputs.dart';

/// docs/50 C3（2026-11-05 定案）：「打卡」类任务 —— 不计时、随时传证据提交，
/// 拆解时由 LLM 在 set_plan 里标 `mode`（timed | checkin）。
///
/// 钉住：打卡单不会超时、能正常结算（评级看证据）、老存档读入后是计时单、
/// set_plan 能解析 mode、执行面板 / 委托板不显示计时读数。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  const Quest weigh = Quest(
    serial: 950,
    kind: 'daily',
    name: '空腹上秤',
    reason: '',
    proof: '体重秤照片',
    minutes: 5,
    rank: 'E',
    attrs: <String, int>{'体': 1},
    timed: false,
  );

  EvidenceShot shot(String id, EvidenceStatus status) => EvidenceShot(
    id: id,
    path: 'evidence/q950/$id.jpg',
    status: status,
    takenAt: DateTime(2026, 1, 1, 10),
  );

  QuestFlow flowOf({List<Quest>? queue, Goal? goal}) => QuestFlow(
    host: HostState.empty,
    goal: goal ?? Goal.demo(),
    queue: queue,
    serial: 1000,
    rnd: math.Random(7),
  );

  group('Quest：计时 / 打卡字段', () {
    test('默认是计时单；打卡单的时长读数是「打卡」', () {
      expect(Quest.demo.timed, isTrue);
      expect(Quest.demo.timeLabel, '45 分钟');
      expect(weigh.checkin, isTrue);
      expect(weigh.timeLabel, '打卡');
    });

    test('copyWith 保留 timed，也能改', () {
      expect(weigh.copyWith(rank: 'D').timed, isFalse);
      expect(weigh.copyWith(timed: true).timed, isTrue);
    });
  });

  group('存档兼容', () {
    test('老存档（无 mode 键）读入后是计时单', () {
      final Map<String, dynamic> old = QuestFlow.questToJson(Quest.demo)
        ..remove('mode');
      expect(old.containsKey('mode'), isFalse, reason: '计时单不写 mode');
      expect(QuestFlow.questFromJson(old).timed, isTrue);
    });

    test('打卡单往返不丢；非法 mode 值按计时单', () {
      final Map<String, dynamic> j = QuestFlow.questToJson(weigh);
      expect(j['mode'], 'checkin');
      expect(QuestFlow.questFromJson(j).timed, isFalse);
      expect(
        QuestFlow.questFromJson(<String, dynamic>{...j, 'mode': 'weird'}).timed,
        isTrue,
      );
    });

    test('PlanTask：老存档 → 计时单；打卡单往返不丢', () {
      const PlanTask t = PlanTask(
        index: 0,
        short: '上秤',
        title: '空腹上秤',
        proof: '体重秤照片',
        minutes: 5,
        rank: 'E',
        timed: false,
      );
      final Map<String, dynamic> j = t.toJson();
      expect(j['mode'], 'checkin');
      expect(PlanTask.fromJson(j).timed, isFalse);
      expect(
        PlanTask.fromJson(<String, dynamic>{...j}..remove('mode')).timed,
        isTrue,
      );
      expect(t.copyWith(state: PlanState.done).timed, isFalse);
    });

    test('执行中的打卡单随档走（杀进程重启后仍是打卡单）', () {
      final QuestFlow f = flowOf(queue: <Quest>[weigh]);
      f.accept(weigh, now: DateTime(2026, 1, 1, 8));
      final Map<String, dynamic>? saved = f.activeToSaveJson();
      final QuestFlow g = flowOf();
      g.restoreActiveFromJson(saved);
      expect(g.active!.task.timed, isFalse);
    });
  });

  group('set_plan 解析 mode', () {
    AgentTool tool(PlanDraft draft) => setPlanTool(
      goalText: '一个月减 3 斤',
      taskCount: 3,
      days: 3,
      draft: draft,
      validate: false,
    );

    Map<String, dynamic> task(int i, Object? mode) => <String, dynamic>{
      'short': '任务$i',
      'title': '第 $i 步',
      'proof': '照片',
      'minutes': 10,
      'rank': 'E',
      'mode': ?mode,
    };

    test('checkin → 打卡单；缺省 / 非法值 → 计时单', () async {
      final PlanDraft draft = PlanDraft();
      final ToolOutcome oc = await tool(draft).run(<String, dynamic>{
        'tasks': <Map<String, dynamic>>[
          task(1, 'checkin'),
          task(2, null),
          task(3, 'stopwatch'),
        ],
      });
      expect(oc.ok, isTrue);
      expect(draft.tasks!.map((TaskSpec t) => t.timed).toList(), <bool>[
        false,
        true,
        true,
      ]);
      final List<dynamic> echoed = oc.data!['tasks'] as List<dynamic>;
      expect((echoed.first as Map<String, dynamic>)['mode'], 'checkin');
    });

    test('parseTaskMode：大小写与空白都容忍', () {
      expect(parseTaskMode(' CheckIn '), isFalse);
      expect(parseTaskMode('timed'), isTrue);
      expect(parseTaskMode(42), isTrue);
    });

    test('拆解提示词写明 checkin 规则', () {
      final PlanBrief b = PlanBrief(
        goalText: '一个月减 3 斤',
        days: 30,
        taskCount: 30,
        cat: goalCats['slim']!,
      );
      expect(b.userText, contains('checkin'));
      expect(b.userText, contains('称重'));
    });

    test('TaskSpec.timed 一路带进 PlanTask 与派出的 Quest', () {
      final List<PlanTask> plan = buildPlanTasks(
        cat: goalCats['slim']!,
        tasks: const <TaskSpec>[
          TaskSpec(
            short: '上秤',
            title: '空腹上秤',
            proof: '体重秤照片',
            minutes: 5,
            rank: 'E',
            timed: false,
          ),
          TaskSpec(
            short: '快走',
            title: '快走 30 分钟',
            proof: '步数',
            minutes: 30,
            rank: 'E',
          ),
        ],
        firstGoal: true,
      );
      expect(plan.map((PlanTask t) => t.timed).toList(), <bool>[false, true]);
      final QuestFlow f = flowOf(
        goal: Goal(
          text: '一个月减 3 斤',
          short: '减重',
          at: DateTime(2030, 1, 1),
          plan: plan,
        ),
      );
      expect(f.planTask(0).timed, isFalse);
      expect(f.planTask(1).timed, isTrue);
    });
  });

  group('QuestFlow：打卡单不超时、照常结算', () {
    test('超时判负对打卡单无效（单子仍在执行中），认输照常', () {
      final QuestFlow f = flowOf(queue: <Quest>[weigh]);
      f.accept(weigh, now: DateTime(2026, 1, 1, 8));
      final FailOutcome? fo = f.fail(
        now: DateTime(2026, 1, 1, 23),
        how: 'timeout',
      );
      expect(fo, isNull);
      expect(f.active, isNotNull, reason: '打卡单不计时，不会被超时踢出');
      final FailOutcome? quit = f.fail(now: DateTime(2026, 1, 1, 23));
      expect(quit, isNotNull);
      expect(quit!.remedy!.timed, isFalse, reason: '打卡单的补救单也是打卡单');
    });

    test('计时单的超时判负不受影响', () {
      final Quest timed = weigh.copyWith(serial: 951, timed: true);
      final QuestFlow f = flowOf(queue: <Quest>[timed]);
      f.accept(timed, now: DateTime(2026, 1, 1, 8));
      expect(f.fail(now: DateTime(2026, 1, 1, 9), how: 'timeout'), isNotNull);
    });

    test('隔了一整天交也能结算；瞬间交不算「太快」；评级看证据', () async {
      final QuestFlow f = flowOf(queue: <Quest>[weigh]);
      f.accept(weigh, now: DateTime(2026, 1, 1, 8));
      f.active!.evidence.add(shot('a', EvidenceStatus.verified));
      final QuestResult r = await f.settle(
        now: DateTime(2026, 1, 1, 8, 0, 20),
        forceCrit: false,
      );
      expect(r.exp, greaterThan(0));
      expect(r.tooFast, isFalse);
      expect(r.verified, 1);
      expect(r.grade, 'A', reason: '有判真证据 = 齐全');

      final Quest w2 = weigh.copyWith(serial: 952);
      f.queue.add(w2);
      f.accept(w2, now: DateTime(2026, 1, 1, 8));
      f.active!.evidence.add(shot('b', EvidenceStatus.unverified));
      final QuestResult r2 = await f.settle(
        now: DateTime(2026, 1, 2, 7),
        forceCrit: false,
      );
      expect(r2.grade, 'B', reason: '只有未校验证据');
    });

    test('grade：计时单仍按时长比；暴击 A → S', () {
      QuestResult res(
        Quest q,
        Duration held, {
        int photos = 1,
        int verified = 0,
        bool crit = false,
      }) => QuestResult(
        quest: q,
        beforeLv: 1,
        beforeExp: 0,
        beforeNeed: 18,
        exp: 1,
        coin: 5,
        attrs: const <String, int>{},
        streak: 1,
        streakUp: true,
        crit: crit,
        dbl: false,
        photos: photos,
        verified: verified,
        chance: .1,
        held: held,
      );
      final Quest timed = weigh.copyWith(timed: true, minutes: 10);
      expect(res(timed, const Duration(minutes: 10)).grade, 'A');
      expect(res(timed, const Duration(minutes: 6)).grade, 'B');
      expect(res(timed, const Duration(minutes: 1)).grade, 'C');
      expect(res(weigh, Duration.zero, verified: 1, crit: true).grade, 'S');
      expect(res(weigh, Duration.zero, photos: 0).grade, 'C');
    });
  });

  group('界面：打卡单不显示计时', () {
    Future<void> mount(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(backgroundColor: Ref.bg, body: child),
        ),
      );
      await tester.pump();
    }

    testWidgets('执行面板：打卡单无倒计时 / 进度条，有「做完随时交」', (WidgetTester tester) async {
      await mount(
        tester,
        const RefExec(quest: weigh, elapsed: Duration(minutes: 40)),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('ref.exec.checkin')), findsOneWidget);
      expect(find.byType(RefProgressBar), findsNothing);
      expect(find.textContaining('做完随时交'), findsOneWidget);
      expect(find.byKey(const Key('ref.exec.submit')), findsOneWidget);

      await mount(
        tester,
        RefExec(quest: Quest.demo, elapsed: const Duration(minutes: 3)),
      );
      expect(find.byKey(const Key('ref.exec.checkin')), findsNothing);
      expect(find.byType(RefProgressBar), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('委托板：打卡单显示「打卡」而不是「N 分钟」', (WidgetTester tester) async {
      await mount(
        tester,
        RefBoard(
          quests: const <Quest>[weigh],
          filter: 'all',
          onFilter: (String _) {},
          onTap: (Quest _) {},
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('· 打卡 ·'), findsOneWidget);
      expect(find.textContaining('5 分钟'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
