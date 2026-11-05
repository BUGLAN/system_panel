import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/chat/tool_card.dart';
import 'package:system_panel/design/ref.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/goal_gen.dart';
import 'package:system_panel/state/host_state.dart';
import 'package:system_panel/state/quest.dart';
import 'package:system_panel/ui/ref/ref_board.dart';
import 'package:system_panel/ui/ref/ref_home.dart';
import 'package:system_panel/ui/ref/ref_main.dart';
import 'package:system_panel/ui/ref/ref_onboard.dart';
import 'package:system_panel/ui/ref/ref_overlays.dart';
import 'package:system_panel/ui/ref/ref_panels.dart';

/// docs/50 B 类（B1–B8）新 UI 的行为网：只钉「该出现的出现、该点的能点、
/// 状态不丢」，不做像素断言（flutter test 用占位字体）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> mountAt(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(backgroundColor: Ref.bg, body: child),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
  }

  const Quest timedQ = Quest(
    serial: 7,
    kind: 'main',
    planIndex: 1,
    planTotal: 180,
    name: '量一次腰围，记下数字和日期',
    reason: '',
    proof: '卷尺读数照片',
    minutes: 8,
    rank: 'E',
    attrs: <String, int>{'力': 1},
  );
  const Quest checkinQ = Quest(
    serial: 8,
    kind: 'daily',
    name: '空腹上秤',
    reason: '',
    proof: '体重秤照片',
    minutes: 5,
    rank: 'E',
    attrs: <String, int>{'体': 1},
    timed: false,
  );

  const List<InterviewCard> cards = <InterviewCard>[
    InterviewCard(id: 'k.level', question: '现在什么水平？', options: <String>['零基础', '学过一点']),
    InterviewCard(id: 'k.freq', question: '一周能练几次？', options: <String>['1~2 次', '3~4 次']),
  ];

  group('B1 拆解失败错误态', () {
    testWidgets('主壳重建（新的卡组列表实例）不会把访谈打回第一张、清空答案', (
      WidgetTester tester,
    ) async {
      final TextEditingController ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      Map<String, String>? done;
      String? err;
      late StateSetter rebuild;
      await mountAt(
        tester,
        StatefulBuilder(
          builder: (BuildContext _, StateSetter set) {
            rebuild = set;
            return RefOnboard(
              controller: ctrl,
              probe: '凭第一反应选。',
              presets: const <String>[],
              onSubmit: () {},
              // 每次 build 都新建一份列表 —— 与主壳 interviewCardsFor(...) 同形
              cards: List<InterviewCard>.of(cards),
              goalText: '三个月学会弹吉他',
              planError: err,
              planErrorTitle: err == null ? null : '上游不可用',
              onDone: (Map<String, String> a) => done = a,
              onRephrase: () {},
              onSkip: err == null ? null : () {},
            );
          },
        ),
      );
      await tester.tap(find.text('零基础'));
      await tester.pump(const Duration(milliseconds: 500));
      rebuild(() {}); // 中途任意一次重建
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('一周能练几次？'), findsOneWidget);
      await tester.tap(find.text('3~4 次'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(done, <String, String>{'k.level': '零基础', 'k.freq': '3~4 次'});

      // 拆解失败：停在复核态（错误卡 + 已答卡），答案原样在
      rebuild(() => err = 'httpError · HTTP 503');
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('ref.onboard.review')), findsOneWidget);
      expect(find.byKey(const Key('ref.onboard.error')), findsOneWidget);
      expect(find.text('ERROR · 上游不可用'), findsOneWidget);
      expect(find.text('零基础'), findsOneWidget);
      expect(find.text('3~4 次'), findsOneWidget);
      expect(find.text('三个月学会弹吉他'), findsOneWidget);
      expect(find.byKey(const Key('ref.onboard.rephrase')), findsOneWidget);
      expect(find.byKey(const Key('ref.onboard.skip')), findsOneWidget);

      // 【重试拆解】= 用同一组答案再交一次
      done = null;
      await tester.tap(find.byKey(const Key('ref.onboard.retry')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(done, <String, String>{'k.level': '零基础', 'k.freq': '3~4 次'});

      // 「改答案」回到第一张，原答案描边保留
      await tester.tap(find.byKey(const Key('ref.onboard.editAnswers')));
      await tester.pump(const Duration(milliseconds: 600));
      for (int k = 0; k < 6; k++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.byKey(const Key('ref.onboard.review')), findsNothing);
      expect(find.text('现在什么水平？'), findsOneWidget);
      expect(find.byKey(const Key('ref.onboard.review')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('换个说法回第 0 幕再回来：同一组卡直接停在复核态（不重答）', (
      WidgetTester tester,
    ) async {
      final TextEditingController ctrl = TextEditingController(text: '学吉他');
      addTearDown(ctrl.dispose);
      bool showCards = true;
      late StateSetter rebuild;
      await mountAt(
        tester,
        StatefulBuilder(
          builder: (BuildContext _, StateSetter set) {
            rebuild = set;
            return RefOnboard(
              controller: ctrl,
              probe: '……',
              presets: const <String>[],
              onSubmit: () {},
              cards: showCards ? List<InterviewCard>.of(cards) : null,
              onDone: (_) {},
            );
          },
        ),
      );
      await tester.tap(find.text('零基础'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('1~2 次'));
      await tester.pump(const Duration(milliseconds: 500));
      rebuild(() => showCards = false);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('ref.onboard.submit')), findsOneWidget);
      rebuild(() => showCards = true);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('ref.onboard.review')), findsOneWidget);
      expect(find.text('开始拆解'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('B2 无目标空态', () {
    testWidgets('大厅：没主线、没记着的目标 → 「未立目标」卡 +【立目标】', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await mountAt(
        tester,
        RefHome(
          host: HostState.empty,
          goal: Goal.empty(),
          days: 0,
          onSetGoal: () => taps++,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('ref.home.noGoal')), findsOneWidget);
      expect(find.byKey(const Key('ref.home.pendingGoal')), findsNothing);
      await tester.tap(find.byKey(const Key('ref.home.setGoal')));
      await tester.pump();
      expect(taps, 1);
      // 记着目标时是 C5 的待拆卡，不出这张
      await mountAt(
        tester,
        RefHome(
          host: HostState.empty,
          goal: Goal.empty(),
          days: 0,
          pendingGoal: '三个月学会弹吉他',
          onSetGoal: () {},
        ),
      );
      expect(find.byKey(const Key('ref.home.noGoal')), findsNothing);
      expect(find.byKey(const Key('ref.home.pendingGoal')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('主线页：没有目标只剩一个【立目标】（没东西可换）', (WidgetTester tester) async {
      int taps = 0;
      await mountAt(
        tester,
        RefMain(goal: Goal.empty(), onSetGoal: () => taps++),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('ref.main.setGoal')), findsOneWidget);
      expect(find.byKey(const Key('ref.main.swapGoal')), findsNothing);
      expect(find.byKey(const Key('ref.main.toBoard')), findsNothing);
      await tester.tap(find.byKey(const Key('ref.main.setGoal')));
      await tester.pump();
      expect(taps, 1);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('B4 证据来源底板', () {
    testWidgets('拍照 / 相册 / 演示截图 / 取消 都能点', (WidgetTester tester) async {
      final List<String> hit = <String>[];
      await mountAt(
        tester,
        RefBottomPanel(
          visible: true,
          onClose: () => hit.add('scrim'),
          child: RefEvidenceSource(
            proof: '卷尺读数照片',
            slotsLeft: 3,
            onCamera: () => hit.add('camera'),
            onGallery: () => hit.add('gallery'),
            onDemo: () => hit.add('demo'),
            onCancel: () => hit.add('cancel'),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('上传快照记录'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ref.evidenceSource.camera')));
      await tester.tap(find.byKey(const Key('ref.evidenceSource.gallery')));
      await tester.tap(find.byKey(const Key('ref.evidenceSource.demo')));
      await tester.tap(find.byKey(const Key('ref.evidenceSource.cancel')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(hit, <String>['camera', 'gallery', 'demo', 'cancel']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('release 不给演示截图', (WidgetTester tester) async {
      await mountAt(
        tester,
        RefBottomPanel(
          visible: true,
          onClose: () {},
          child: RefEvidenceSource(
            proof: '照片',
            slotsLeft: 2,
            onCamera: () {},
            onGallery: () {},
            onCancel: () {},
          ),
        ),
      );
      expect(find.byKey(const Key('ref.evidenceSource.demo')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('B5 认输页补救票', () {
    testWidgets('有补救单：票 +【接下补救单】+「先放委托板」都在、能点', (
      WidgetTester tester,
    ) async {
      int take = 0, back = 0;
      const Quest remedy = Quest(
        serial: 9,
        kind: 'remedy',
        name: '量腰围，只记数字',
        reason: '',
        proof: '卷尺读数照片',
        minutes: 4,
        rank: 'D',
        attrs: <String, int>{'力': 1},
      );
      await mountAt(
        tester,
        RefFail(
          title: '任务失败',
          sub: 'MISSION FAILED',
          box: const SizedBox(height: 40),
          onBack: () => back++,
          remedy: RefTicketCard(
            quest: remedy,
            stampOnTap: false,
            onTap: () => take++,
          ),
          onTakeRemedy: () => take++,
          backLabel: '先放委托板，回大厅',
        ),
      );
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.takeException(), isNull);
      expect(find.text('REMEDY · 补救单已备好'), findsOneWidget);
      expect(find.text('量腰围，只记数字'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ref.fail.takeRemedy')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('先放委托板，回大厅'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(take, 1);
      expect(back, 1);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('B6 接单前简报', () {
    testWidgets('计时单：TIME TRIAL + 判负行 +【开始计时】', (WidgetTester tester) async {
      int start = 0, cancel = 0;
      await mountAt(
        tester,
        RefBottomPanel(
          visible: true,
          onClose: () => cancel++,
          child: RefBrief(
            quest: timedQ,
            onStart: () => start++,
            onCancel: () => cancel++,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('TIME TRIAL'), findsOneWidget);
      expect(find.text('MAIN 02 / 180'), findsOneWidget);
      expect(find.text('判负'), findsOneWidget);
      expect(find.text('8 分钟 · 点开始才计时'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ref.brief.start')));
      await tester.tap(find.byKey(const Key('ref.brief.cancel')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(start, 1);
      expect(cancel, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('打卡单：CHECK-IN、不计时、没有判负行', (WidgetTester tester) async {
      await mountAt(
        tester,
        RefBottomPanel(
          visible: true,
          onClose: () {},
          child: RefBrief(quest: checkinQ, onStart: () {}, onCancel: () {}),
        ),
      );
      expect(find.text('CHECK-IN'), findsOneWidget);
      expect(find.text('不计时 · 今天内交'), findsOneWidget);
      expect(find.text('判负'), findsNothing);
      expect(find.text('开始 · 不计时'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    test('奖励读数用六维显示名（力 → 体质），晶核不用符号', () {
      final String r = RefBrief.rewardOf(timedQ);
      expect(r, contains('体质 +1'));
      expect(r, contains('晶核'));
      expect(r, isNot(contains('◈')));
    });
  });

  group('B7 节点轨分段标识', () {
    testWidgets('整条主线超过一段才显示「第 k 段」', (WidgetTester tester) async {
      final Goal g = Goal.demo();
      await mountAt(tester, RefMain(goal: g.copyWith(planTotal: 180)));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('ref.main.segment')), findsOneWidget);
      expect(find.textContaining('第 1 段'), findsOneWidget);
      await mountAt(
        tester,
        RefMain(goal: g.copyWith(planTotal: g.plan.length)),
      );
      if (g.plan.length <= kPlanWindowSize) {
        expect(find.byKey(const Key('ref.main.segment')), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('B8 聊天工具回执卡', () {
    test('get_status 回执解析成状态快照（最弱维键 → 显示名）', () {
      const String t =
          'get_status：LV3 · EXP 12/40 · ◈56 · 连击 2（最好 5）\n'
          '主线：「半年减重 10 斤」完成 1/180 单\n'
          '手里 3 单 · 完成 7 · 战败 1 · 最弱维：体3';
      final ({String? tool, String body}) r = splitToolReceipt(t);
      expect(r.tool, 'get_status');
      final StatusSnapshot? s = StatusSnapshot.tryParse(r.body);
      expect(s, isNotNull);
      expect(s!.lv, 3);
      expect(s.exp, 12);
      expect(s.expNeed, 40);
      expect(s.coins, 56);
      expect(s.streak, 2);
      expect(s.bestStreak, 5);
      expect(s.goalLine, '「半年减重 10 斤」完成 1/180 单');
      expect(s.queue, 3);
      expect(s.done, 7);
      expect(s.failed, 1);
      expect(s.weakest, '意志 3');
    });

    test('认不出的回执 → null（走精简卡，不丢内容）', () {
      expect(StatusSnapshot.tryParse('换好了：慢跑 1.5 公里'), isNull);
      expect(splitToolReceipt('LV7 · ◈340').tool, isNull);
      expect(toolTitleOf('swap_quest'), '换任务');
    });

    testWidgets('状态卡与精简卡都能渲染', (WidgetTester tester) async {
      await mountAt(
        tester,
        const Column(
          children: <Widget>[
            ChatToolCard(
              text:
                  'LV3 · EXP 12/40 · ◈56 · 连击 2（最好 5）\n'
                  '主线：未立目标\n'
                  '手里 3 单 · 完成 7 · 战败 1 · 最弱维：智2',
            ),
            ChatToolCard(text: 'swap_quest：换好了'),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('chat.statusCard')), findsOneWidget);
      expect(find.text('TOOL · 状态快照'), findsOneWidget);
      expect(find.text('智识 2'), findsOneWidget);
      expect(find.text('TOOL · 换任务'), findsOneWidget);
      expect(find.text('换好了'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
