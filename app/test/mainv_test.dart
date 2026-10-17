import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/widgets/card_skins.dart';
import 'package:system_panel/widgets/main_view.dart';

/// 主线页（docs/33 卡片式新视图）—— 数据读数 + 委托轨窗口 + 五态 + 手势。
///
/// ⚠️ 这一页按百分比/相机数学定位，必须用 `tester.view` 设尺寸
/// （`setSurfaceSize` 不改 MediaQuery，见 app/PORTING-NOTES.md 第 13 条）。
const Size kDesign = Size(390, 844);

Future<void> _mount(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = Size(kDesign.width * 3, kDesign.height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Stack(children: <Widget>[child])),
    ),
  );
  await tester.pump();
}

/// 一张「全待办」的 12 天清单（测轨窗口/状态用，绕开演示档的固定形态）
Goal _planOf({int days = 12, int done = 0}) => Goal(
  text: '半年内坚持健身',
  short: '健身',
  at: DateTime(2026, 10, 12),
  days: days,
  plan: <PlanTask>[
    for (int i = 0; i < days; i++)
      PlanTask(
        index: i,
        short: '第 ${i + 1} 张',
        title: '第 ${i + 1} 张的题面',
        proof: '截图',
        minutes: 20,
        rank: i == days - 1 ? 'S' : 'D',
        state: i < done ? PlanState.done : PlanState.todo,
        finalTask: i == days - 1,
      ),
  ],
);

void main() {
  group('计划数据（docs/33：目标 = 一句话 + 期限 + 任务清单）', () {
    test('演示档：8 张、第 5 张脚下、末张是兑现单', () {
      final Goal g = Goal.demo();
      expect(g.totalTasks, 8);
      expect(g.doneCount, 4);
      expect(g.firstOpenIndex, 4);
      expect(g.plan[4].short, '五公里');
      expect(g.plan[7].finalTask, isTrue);
      expect(g.plan[7].rank, 'S');
      expect(g.plan[0].statusText(), startsWith('已完成 · '));
      expect(g.plan[4].statusText(), '正在执行');
      expect(g.plan[5].statusText(), '待发布');
    });

    test('状态码兼容老档（cur/lock 都读得回来）', () {
      expect(PlanState.of('cur'), PlanState.active);
      expect(PlanState.of('done'), PlanState.done);
      expect(PlanState.of('lock'), PlanState.todo);
      expect(PlanState.of('nonsense'), PlanState.todo);
    });

    test('抬头读数：已过 N/M 天 · 完成 X 单', () {
      // 演示档那条主线是「三个月跑完半马」→ 期限 90 天（清单 8 张是环时代残留形态）
      final Goal g = Goal.demo();
      expect(g.days, 90);
      expect(g.progressText(g.at), '已过 1/90 天 · 完成 4 单');
      expect(g.remainingDays(g.at), 89);
    });

    test('空目标 = 没有清单（未绑定）', () {
      expect(Goal.empty().isEmpty, isTrue);
      expect(Goal.empty().totalTasks, 0);
      expect(Goal.empty().firstOpenIndex, -1);
    });
  });

  group('委托轨（第 4 套皮肤 duty）', () {
    test('尺寸：牌扇 148×220 / 牌屉 208×292 / XS 微牌 100×72（docs/39 M-05）', () {
      // docs/39 M-05：132×196 → 148×220（CardTable 高度 = 220+26+38+30 = 314）
      expect(dimsOf(CardSkin.duty, CardTableSize.m).w, 148);
      expect(dimsOf(CardSkin.duty, CardTableSize.m).h, 220);
      expect(dimsOf(CardSkin.duty, CardTableSize.l).w, 208);
      expect(dimsOf(CardSkin.duty, CardTableSize.l).h, 292);
      expect(dimsOf(CardSkin.duty, CardTableSize.s).w, 100);
      expect(dimsOf(CardSkin.duty, CardTableSize.s).h, 72);
    });

    test('窗口：从第一张没做完的往前带一张，往后最多 5 张（M-05 领位 ±2）', () {
      // 12 天全待办 → 第 0 张起（往前带不了）最多 5 张
      expect(MainView(goal: _planOf()).railIndices(), <int>[0, 1, 2, 3, 4]);
      // 做完 4 张 → 第一张没做完的是 4，往前带第 3 张 → 3..7
      expect(MainView(goal: _planOf(done: 4)).railIndices(), <int>[
        3,
        4,
        5,
        6,
        7,
      ]);
      // 全走完 → 停在最后两张（往前带一张的既有口径）
      expect(MainView(goal: _planOf(days: 12, done: 12)).railIndices(), <int>[
        10,
        11,
      ]);
    });

    test('五态：已完成 / 执行中 / 可接 / 待发布 / 已放弃', () {
      final Goal g = _planOf(days: 6, done: 1);
      final MainView v = MainView(goal: g, published: {2, 3}, activeIndex: 2);
      expect(v.stateOf(0), DutyState.done);
      expect(v.stateOf(2), DutyState.active);
      expect(v.stateOf(3), DutyState.open);
      expect(v.stateOf(5), DutyState.sealed);
      final Goal ab = g.copyWith(
        plan: <PlanTask>[
          g.plan[0],
          g.plan[1].copyWith(state: PlanState.abandoned),
          ...g.plan.sublist(2),
        ],
      );
      expect(MainView(goal: ab).stateOf(1), DutyState.abandoned);
    });

    test('牌面九区映射：角标 / 印位 / 规则行 / 报酬条', () {
      final Goal g = _planOf(days: 6, done: 1);
      final TableCard c = MainView(goal: g, published: {2}).cardOf(2);
      expect(c.kicker, 'MAIN · 03');
      expect(c.rank, g.plan[2].rank);
      expect(c.dutyMeta, contains('20 分钟'));
      expect(c.dutyMeta, contains('截图'));
      expect(c.loot.first, startsWith('EXP '));
      expect(c.dutyState, DutyState.open);
    });
  });

  group('主线页 · 交互（2026-10-12 重设计：竖牌扇 + 牌屉）', () {
    testWidgets('抬头 / 牌扇 / 刻度轨都在；点领位 → 展开牌屉', (WidgetTester tester) async {
      final Goal g = _planOf(days: 6, done: 1);
      int? picked;
      await _mount(
        tester,
        MainView(
          goal: g,
          // 领位（计划第 1 张）必须是**可接**的，否则落定不该触发（`enabled` 门控）
          published: const <int>{1, 2, 3},
          activeIndex: 2,
          onSelect: (int i) => picked = i,
        ),
      );
      expect(find.byKey(const Key('main.top')), findsOneWidget);
      expect(find.byKey(const Key('main.rail')), findsOneWidget);
      expect(find.byKey(const Key('main.scale')), findsOneWidget);
      expect(find.byKey(const Key('main.newGoal')), findsOneWidget);

      // 领位 = 第一张没做完的（计划第 1 张），它就在扇心
      await tester.tapAt(tester.getCenter(find.byKey(const Key('main.rail'))));
      expect(picked, 1);
    });

    testWidgets('牌扇整个落在安全带里（不越到她脸上）', (WidgetTester tester) async {
      await _mount(
        tester,
        MainView(goal: _planOf(days: 6, done: 1), published: const <int>{2, 3}),
      );
      final Rect fan = tester.getRect(find.byKey(const Key('main.rail')));
      expect(
        fan.top,
        greaterThanOrEqualTo(kDesign.height * MainView.kSafeTop - .5),
        reason: '牌扇顶边不得越过安全带（她的脸在 20%~42%）',
      );
      expect(
        fan.bottom,
        lessThanOrEqualTo(kDesign.height * MainView.kSafeBottom + .5),
      );
    });

    testWidgets('牌屉：可接那张给【接任务】；点「收起」回牌扇', (WidgetTester tester) async {
      final Goal g = _planOf(days: 6, done: 1);
      int? picked;
      int? taken;
      await _mount(
        tester,
        MainView(
          goal: g,
          published: const <int>{1, 2, 3},
          activeIndex: 2,
          selected: 1,
          onSelect: (int i) => picked = i,
          onAccept: (int i) => taken = i,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('main.detail')), findsOneWidget);
      expect(find.byKey(const Key('main.rail')), findsNothing);
      await tester.tap(find.byKey(const Key('main.take')));
      expect(taken, 1);
      // docs/39 M-18：收起先播 260ms 退场再回调 _pickedTask = null
      await tester.tap(find.byKey(const Key('main.back')));
      await tester.pumpAndSettle();
      expect(picked, -1);
    });

    testWidgets('待发布那张没有【接任务】（只读）', (WidgetTester tester) async {
      await _mount(
        tester,
        MainView(goal: _planOf(days: 6, done: 1), selected: 5),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('main.take')), findsNothing);
      expect(find.byKey(const Key('main.detail')), findsOneWidget);
    });

    // docs/39 M-10：原来只有「可接」的领位能开屉，其余四态点下去只出一声
    // —— 真机上宿主点「待发布」的牌什么都不发生。现在点领位 = 看详情，全五态都开。
    //
    // 领位 = 扇心那张（`_fan` 的 leadAt 口径 = firstOpenIndex；全完成停最后一张）。
    // 这里逐态把目标牌放到领位上，再点扇心 —— 等价于点领位那张。
    testWidgets('全态可点开：五态的领位牌点下去都开屉（enabled 不再挡看）', (
      WidgetTester tester,
    ) async {
      PlanTask t(int i, PlanState s) => PlanTask(
        index: i,
        short: '第 ${i + 1} 张',
        title: '第 ${i + 1} 张的题面',
        proof: '截图',
        minutes: 20,
        rank: 'D',
        state: s,
      );
      Goal g(List<PlanState> states) => Goal(
        text: '半年内坚持健身',
        short: '健身',
        at: DateTime(2026, 10, 12),
        days: states.length,
        plan: <PlanTask>[
          for (int i = 0; i < states.length; i++) t(i, states[i]),
        ],
      );
      // 名字 → (goal, published, activeIndex, 领位上那一态)
      final Map<String, (Goal, Set<int>, int?, DutyState)> cases =
          <String, (Goal, Set<int>, int?, DutyState)>{
            // 第 0 张 todo 且已派 → 可接
            '可接': (
              g(<PlanState>[PlanState.todo, PlanState.todo]),
              const <int>{0},
              null,
              DutyState.open,
            ),
            // 第 0 张 active → 执行中
            '执行中': (
              g(<PlanState>[PlanState.active, PlanState.todo]),
              const <int>{0},
              0,
              DutyState.active,
            ),
            // 第 0 张 todo 且没派 → 待发布
            '待发布': (
              g(<PlanState>[PlanState.todo, PlanState.done]),
              const <int>{},
              null,
              DutyState.sealed,
            ),
            // ⚠️ 「领位是已完成那张」这一档只在**全部走完**时出现（窗口停在最后
            //    一张），而全完成现在是 M-23 的完成态仪式（牌扇整层换成满环+金印，
            //    见文件末尾的 M-23 用例）—— 所以这里不再列它：牌扇上的「已完成」
            //    卡由上面 `cardOf` 的单测和五态映射覆盖。
          };
      for (final MapEntry<String, (Goal, Set<int>, int?, DutyState)> e
          in cases.entries) {
        final Goal gg = e.value.$1;
        final Set<int> pub = e.value.$2;
        final int? active = e.value.$3;
        final MainView probe = MainView(
          goal: gg,
          published: pub,
          activeIndex: active,
        );
        final List<int> idx = probe.railIndices();
        final int open = gg.firstOpenIndex;
        final int leadAt = open < 0
            ? idx.length - 1
            : idx.indexWhere((int i) => i == open);
        final int leadPlan = idx[math.max(0, leadAt)];
        expect(
          probe.stateOf(leadPlan),
          e.value.$4,
          reason: '${e.key} 用例的领位没坐到目标态上（用例本身错了）',
        );
        // 「可接」之外的四态都是 enabled: false —— 这正是老 bug 的入口
        expect(
          probe.cardOf(leadPlan).enabled,
          e.key == '可接',
          reason: '${e.key} 的 enabled 口径（只有可接才是 true）',
        );

        int? picked;
        await _mount(
          tester,
          // ⚠️ 每个用例一个独立 key：同一个 testWidgets 里连挂多棵 MainView，
          //    同 key 同类型会**复用 State**（CardTable 的领位存在 _rail 里，
          //    不会重新吃 initialLead）—— 这条坑让用例互相污染过。
          MainView(
            key: ValueKey<String>(e.key),
            goal: gg,
            published: pub,
            activeIndex: active,
            onSelect: (int i) => picked = i,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tapAt(
          tester.getCenter(find.byKey(const Key('main.rail'))),
        );
        await tester.pumpAndSettle();
        expect(picked, leadPlan, reason: '${e.key} 态点领位必须能开屉');
      }
    });

    // docs/39 M-15 / M-16 / M-17：牌屉是**三段式单卡**，证据带在卡里，
    // 并且同一屏只剩一颗主 CTA（页面底部两颗在抽屉打开时淡出）。
    testWidgets('牌屉：证据带有标签、只有一颗主 CTA、底部两颗已淡出', (WidgetTester tester) async {
      await _mount(
        tester,
        MainView(
          goal: _planOf(days: 6, done: 1),
          published: const <int>{1, 2, 3},
          selected: 1,
        ),
      );
      await tester.pumpAndSettle();
      // ② 证据带在卡里（不再是牌外托盘），且带 10pt 标签
      expect(find.byKey(const Key('duty.evidence')), findsOneWidget);
      expect(find.textContaining('证据 · 最多 5 张'), findsOneWidget);
      expect(find.text('接单后可传证据'), findsOneWidget);
      // 牌外那个旧托盘不再存在
      expect(find.byKey(const Key('main.tray')), findsNothing);
      // M-17：抽屉里只有一个主 CTA，页面底部两颗的容器已淡出（opacity 0）
      expect(find.byKey(const Key('main.take')), findsOneWidget);
      final AnimatedOpacity fade = tester.widget<AnimatedOpacity>(
        find.byKey(const Key('main.lowFade')),
      );
      expect(fade.opacity, 0, reason: '抽屉打开时页面底部两颗必须淡出');
    });

    // docs/39 M-20：底部主 CTA 是同一套状态机 —— 没有执行中 = 去委托板，
    // 执行中 = 继续执行；队列空 = 只留占位 + 一句「今日已清」。
    testWidgets('底部主 CTA 文案随状态变（去委托板 / 继续执行 / 今日已清）', (
      WidgetTester tester,
    ) async {
      // 无执行中、队列有单 → 去委托板
      await _mount(
        tester,
        MainView(
          key: const ValueKey<String>('a'),
          goal: _planOf(days: 6, done: 1),
          published: const <int>{1, 2, 3},
          canDispatch: true,
        ),
      );
      expect(find.text('去委托板'), findsOneWidget);
      // 执行中 → 继续执行
      await _mount(
        tester,
        MainView(
          key: const ValueKey<String>('b'),
          goal: _planOf(days: 6, done: 1),
          published: const <int>{1, 2, 3},
          activeIndex: 2,
          elapsed: '12:04',
        ),
      );
      expect(find.text('继续执行'), findsOneWidget);
      // 队列空 → 今日已清（主 CTA 只留占位，不动作）
      await _mount(
        tester,
        MainView(
          key: const ValueKey<String>('c'),
          goal: _planOf(days: 6, done: 1),
          published: const <int>{1, 2, 3},
        ),
      );
      expect(find.byKey(const Key('main.cleared')), findsOneWidget);
      // M-21：ghost 固定在右（不会因为主 CTA 消失而左跳）
      expect(find.byKey(const Key('main.newGoal')), findsOneWidget);
    });

    // docs/39 M-21（队列空）：【去执行】整颗消失时，【换目标】会从左端跳到右端
    // —— 走查里这是「图标位移」的一类硬伤。修法是**主 CTA 的位置永远在**：
    // 空态只用一颗同宽的占位（+ 一句「今日已清」），ghost 的 x 不动。
    testWidgets('队列空：主 CTA 变占位，ghost 的位置与有单时逐像素相同', (
      WidgetTester tester,
    ) async {
      // 先量「有单」的 ghost 左缘
      await _mount(
        tester,
        MainView(
          key: const ValueKey<String>('m21.a'),
          goal: _planOf(days: 6, done: 1),
          published: const <int>{1, 2, 3},
          canDispatch: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));
      final Rect withQueue = tester.getRect(
        find.byKey(const Key('main.newGoal')),
      );
      // 再量「队列空」的同一颗 ghost
      await _mount(
        tester,
        MainView(
          key: const ValueKey<String>('m21.b'),
          goal: _planOf(days: 6, done: 1),
          published: const <int>{1, 2, 3},
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));
      final Rect empty = tester.getRect(find.byKey(const Key('main.newGoal')));
      expect(
        empty.left,
        closeTo(withQueue.left, .5),
        reason: 'M-21：队列空时 ghost 不许左跳（主 CTA 位置只是换成占位）',
      );
    });

    // M-02：读数 12pt + 状态 chip（剩 N 天 / 已到期 / 执行中 12:04）
    testWidgets('读数行给状态 chip；执行中那条带计时', (WidgetTester tester) async {
      await _mount(
        tester,
        MainView(
          key: const ValueKey<String>('d'),
          goal: _planOf(days: 6, done: 1),
          published: const <int>{1, 2, 3},
          activeIndex: 2,
          elapsed: '12:04',
          now: DateTime(2026, 10, 12),
        ),
      );
      expect(find.byKey(const Key('main.chip.active')), findsOneWidget);
      expect(find.textContaining('执行中 12:04'), findsOneWidget);
    });

    // docs/39 M-13：刻度轨的「导航」与「检查」分离 ——
    // 拖动/轻点刻度轨**只移动牌扇领位**，绝不打开牌屉（老版本 onTapDown 立刻跳转，
    // 拖拽分支永远不可达，真机上「想擦洗一下结果开了一张牌」）。
    testWidgets('刻度轨拖动只移动领位、不开牌屉', (WidgetTester tester) async {
      final List<int> picked = <int>[];
      await _mount(
        tester,
        MainView(
          goal: _planOf(days: 8, done: 0),
          published: const <int>{0, 1, 2, 3, 4, 5, 6, 7},
          onSelect: (int i) => picked.add(i),
        ),
      );
      await tester.pumpAndSettle();
      final Finder scale = find.byKey(const Key('main.scale'));
      // 在刻度轨上往下拖（= 往前走几段）
      await tester.drag(scale, const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(picked, isEmpty, reason: '刻度轨拖动只该移动领位，不该触发 onSelect（开牌屉）');
      // 轻点也一样：只跳段，不打开
      await tester.tapAt(tester.getCenter(scale) + const Offset(0, 60));
      await tester.pumpAndSettle();
      expect(picked, isEmpty, reason: '刻度轨轻点只该跳段，不该触发 onSelect（开牌屉）');
    });

    // docs/39 M-05：领位牌 148×220 —— 牌桌高度 = 220+26+38+30 = 314，
    // 390 基准的安全带只有 346，所以牌桌**贴着安全带撑满**（`Positioned` 给的
    // 是紧约束），真正要钉的是牌本身 148×220 与「不越过 45%」。
    testWidgets('牌扇几何：领位牌 148×220、整个落在安全带里', (WidgetTester tester) async {
      await _mount(
        tester,
        MainView(goal: _planOf(days: 8), published: const <int>{0, 1, 2}),
      );
      await tester.pumpAndSettle();
      final List<CardFace> faces = tester
          .widgetList<CardFace>(find.byType(CardFace))
          .toList();
      expect(faces, isNotEmpty);
      final CardFace leadFace = faces.firstWhere((CardFace f) => f.lead);
      final Dims d = dimsOf(CardSkin.duty, CardTableSize.m);
      expect(d.w, 148);
      expect(d.h, 220);
      expect(leadFace.size, CardTableSize.m);
      // 整块牌扇仍然落在 45%~86% 里（她脸在 20%~42%）
      final Rect fan = tester.getRect(find.byKey(const Key('main.rail')));
      expect(fan.top, greaterThanOrEqualTo(844 * .45 - 1));
      expect(fan.bottom, lessThanOrEqualTo(844 * .86 + 1));
    });

    // docs/39 M-09：执行中那张牌有**两个编码** —— 光包在跑 + 牌角 11pt 计时。
    // 光包是 CustomPainter 里的一小段（不是整张卡 Opacity），这里验它真的被喂了相位。
    testWidgets('执行中：牌角有计时、光包相位在走', (WidgetTester tester) async {
      await _mount(
        tester,
        MainView(
          goal: _planOf(days: 6, done: 1),
          published: const <int>{1, 2, 3},
          activeIndex: 2,
          elapsed: '12:04',
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      // 执行中那张在牌扇窗口里 → 计时读数是牌面上「不动」的那一半编码
      expect(find.byKey(const Key('duty.timer')), findsWidgets);
      // 跑几拍确认 ticker 在推相位（相位变了才重绘），且不抛异常
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    });

    // docs/39 §5.2：进页编排 —— 抬头 40ms、牌扇 120ms、底部两键 320ms。
    // 这里钉「跑完整段之后一切就位且落在安全带里」。
    testWidgets('进页编排：跑完 ≤800ms 后一切就位', (WidgetTester tester) async {
      await _mount(
        tester,
        MainView(
          goal: _planOf(days: 6, done: 1),
          published: const <int>{1, 2, 3},
          canDispatch: true,
        ),
      );
      // 编排总长 760ms；800ms 之后应当全部落在终态
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('main.top')), findsOneWidget);
      expect(find.byKey(const Key('main.rail')), findsOneWidget);
      final Rect fan = tester.getRect(find.byKey(const Key('main.rail')));
      expect(fan.top, greaterThanOrEqualTo(844 * .45 - 1));
      // 底部两颗上浮 16px 已走完 → 正好落在 bottom:34 的终态（844-34=810）
      final Rect low = tester.getRect(find.byKey(const Key('main.low')));
      expect(low.bottom, closeTo(844 - 34, 2));
    });

    // 「已放弃」坐不到领位（firstOpenIndex 只认 todo/active，往前带一张也带不到
    // 它）—— 但它仍然必须**能开屉**：牌屉里那条只读的放弃态同样可看。
    // 这一条从 onSelect 入口直接验（牌屉的渲染本身由上面几条覆盖）。
    testWidgets('已放弃那张也能开屉（只读，无动作键）', (WidgetTester tester) async {
      final Goal g = _planOf(days: 6, done: 1).copyWith(
        plan: <PlanTask>[
          ..._planOf(days: 6, done: 1).plan.take(1),
          _planOf(
            days: 6,
            done: 1,
          ).plan[1].copyWith(state: PlanState.abandoned),
          ..._planOf(days: 6, done: 1).plan.skip(2),
        ],
      );
      await _mount(tester, MainView(goal: g, selected: 1));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('main.detail')), findsOneWidget);
      // 放弃态没有任何动作键（只有【收起】）
      expect(find.byKey(const Key('main.take')), findsNothing);
      expect(find.byKey(const Key('main.publish')), findsNothing);
      expect(find.byKey(const Key('main.back')), findsOneWidget);
    });
    // docs/39 M-23（全部完成）：原来没有任何「目标达成」状态。现在：
    //  · 进度带满环（主线页的页内环，600ms 长满）
    //  · 金色压印「兑现」
    //  · 她一句
    //  · 抬头 chip 写「已兑现」
    //  · 主 CTA 变【立新目标】
    testWidgets('全部完成：满环 + 金印「兑现」+ 她一句 + 抬头 chip + 【立新目标】', (
      WidgetTester tester,
    ) async {
      await _mount(tester, MainView(goal: _planOf(days: 3, done: 3)));
      await tester.pump(const Duration(milliseconds: 900)); // 600 满环 + 280 压印
      await tester.pumpAndSettle();

      // 牌扇/牌屉都不在：完成态是独立的一屏
      expect(find.byKey(const Key('main.rail')), findsNothing);
      expect(find.byKey(const Key('main.detail')), findsNothing);
      // 满环 + 金印 + 她一句
      expect(find.byKey(const Key('main.doneRing')), findsOneWidget);
      expect(find.byKey(const Key('main.doneSeal')), findsOneWidget);
      expect(find.text('兑现'), findsOneWidget);
      expect(find.byKey(const Key('main.doneLine')), findsOneWidget);
      // 目标状态写进抬头 chip（与剩 N 天 / 已到期同一套）
      expect(find.byKey(const Key('main.chip.done')), findsOneWidget);
      expect(find.text('已兑现'), findsOneWidget);
      // 主 CTA = 【立新目标】（不是「今日已清」、也不是「去委托板」）
      expect(find.text('立新目标'), findsOneWidget);
      expect(find.byKey(const Key('main.cleared')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    // M-23 的满环/压印是**一次演出的两个阶段**：600ms 走满之前金印还没落定。
    // （这条钉住「不是一上来就全亮」—— 否则 600ms 那条编排等于没做。）
    testWidgets('全部完成：仪式分两段（600ms 满环 → 280ms 压印）', (
      WidgetTester tester,
    ) async {
      await _mount(tester, MainView(goal: _planOf(days: 2, done: 2)));
      await tester.pump(const Duration(milliseconds: 100));
      final double early = tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.byKey(const Key('main.doneSeal')),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;
      await tester.pump(const Duration(milliseconds: 800));
      final double late = tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.byKey(const Key('main.doneSeal')),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;
      expect(early, lessThan(.5), reason: '600ms 满环走完之前，金印还没落定');
      expect(late, closeTo(1, .001), reason: '880ms 之后金印完全落定');
    });

    // §5.5：reduce 下满环/压印直接落终态，不跑 880ms 编排
    testWidgets('全部完成 · reduce：满环与压印直接落终态', (WidgetTester tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _mount(tester, MainView(goal: _planOf(days: 2, done: 2)));
      await tester.pump(); // 一帧就位
      expect(find.byKey(const Key('main.doneSeal')), findsOneWidget);
      final double op = tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.byKey(const Key('main.doneSeal')),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;
      expect(op, 1, reason: 'reduce 下不播 880ms 编排，直接落终态');
    });
  });
}
