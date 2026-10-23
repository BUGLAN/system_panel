import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/data/rarity.dart';
import 'package:system_panel/data/rewards.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/host_state.dart';
import 'package:system_panel/state/quest.dart';
import 'package:system_panel/state/quest_flow.dart';
import 'package:system_panel/state/result.dart';
import 'package:system_panel/widgets/plate.dart';

/// 派单板（玻璃板 + 等级骰子 + 指纹 + alt 按钮）。
/// 坐标断言来自运行中原型的实测值（C 级主线第 5 环）。
///
/// ⚠️ 同 lobby_test：`flutter test` 用占位字体（每字形 1em 宽），
/// 凡"宽度由文字撑出来"的盒子在单测里量不准，只断言与文字宽度无关的部分。
const Size kDesign = Size(390, 844);

Future<void> _mount(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(kDesign);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Stack(children: <Widget>[child])),
    ),
  );
  await tester.pump();
}

void main() {
  group('稀有度阶梯 = content.js L14-23', () {
    test('七级颜色与奖励逐个对齐', () {
      expect(Rarity.ranks, <String>['F', 'E', 'D', 'C', 'B', 'A', 'S']);
      expect(Rarity.of('F').color.toARGB32(), 0xFF9AA3B2);
      expect(Rarity.of('C').color.toARGB32(), 0xFFA78BFA);
      expect(Rarity.of('S').color.toARGB32(), 0xFFFF4D5E);
      expect(Rarity.of('C').exp, 50);
      expect(Rarity.of('C').coin, 24);
      expect(Rarity.of('C').i, 3);
      expect(Rarity.of('S').i, 6);
      expect(Rarity.of('S').exp, 200);
    });
  });

  group('委托数据', () {
    test('单号 / 计划序号 / 时限 / 报酬文案（ui.js + util.js）', () {
      const Quest q = Quest.demo;
      expect(q.serialText, '№ 0041');
      expect(q.kindLabel, '主线 · 第 5 单 / 8');
      expect(q.minutesText, '45 分钟');
      // t15：loot 面板切结算经济口径（Rewards 表，与 QuestFlow.settle 同源）
      expect(q.lootText, 'EXP 4 · ◈ 5体+1 力+1');
    });

    test('时限跨小时的说法（fmtMin）', () {
      const Quest base = Quest.demo;
      expect(
        Quest(
          serial: 1,
          kind: 'daily',
          planIndex: 0,
          planTotal: 1,
          name: 'x',
          reason: '',
          proof: 'y',
          minutes: 60,
          rank: 'F',
          attrs: <String, int>{},
        ).minutesText,
        '1 小时',
      );
      expect(
        Quest(
          serial: 1,
          kind: 'daily',
          planIndex: 0,
          planTotal: 1,
          name: 'x',
          reason: '',
          proof: 'y',
          minutes: 90,
          rank: 'F',
          attrs: <String, int>{},
        ).minutesText,
        '1 小时 30 分',
      );
      expect(base.minutes, 45);
    });
  });

  group('玻璃板', () {
    testWidgets('文案齐全：单号 / 计划序号 / 标题 / 附言 / 规格 / 按住', (
      WidgetTester tester,
    ) async {
      await _mount(
        tester,
        const Plate(
          quest: Quest.demo,
          host: HostState.demo,
          animateLand: false,
        ),
      );
      expect(find.text('№ 0041'), findsOneWidget);
      expect(find.text('主线 · 第 5 单 / 8'), findsOneWidget);
      expect(find.text('跑完 5 公里'), findsOneWidget);
      expect(find.text('附言'), findsOneWidget);
      expect(find.text('证明'), findsOneWidget);
      expect(find.text('跑步 App 截图'), findsOneWidget);
      expect(find.text('时限'), findsOneWidget);
      expect(find.text('45 分钟'), findsOneWidget);
      expect(find.text('报酬'), findsOneWidget);
      expect(find.text('按住 · 接下'), findsOneWidget);
      expect(find.text('HOLD TO ACCEPT'), findsOneWidget);
      expect(find.text('C'), findsOneWidget); // 骰子上的等级字
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('玻璃板 / 骰子 / 环 / 指纹 / 底缘光落在实测坐标上', (WidgetTester tester) async {
      await _mount(
        tester,
        const Plate(
          quest: Quest.demo,
          host: HostState.demo,
          animateLand: false,
        ),
      );
      expect(
        tester.getRect(find.byKey(const Key('plate'))),
        const Rect.fromLTWH(16, 396, 358, 384),
      );
      expect(
        tester.getRect(find.byKey(const Key('plate.rank'))),
        const Rect.fromLTWH(272, 430, 86, 104),
      );
      expect(
        tester.getRect(find.byKey(const Key('plate.ring'))),
        const Rect.fromLTWH(276, 430, 78, 78),
      );
      expect(
        tester.getRect(find.byKey(const Key('plate.print'))),
        const Rect.fromLTWH(36, 672, 318, 108),
      );
      // .pl-print 是「居中一行」：指纹的 x 由右边文案宽度撑出来，单测里量不准，
      // 只钉住它自己的尺寸与竖直位置（原型实测 top 692）
      final Rect fp = tester.getRect(find.byKey(const Key('plate.fp')));
      expect(fp.width, 62);
      expect(fp.height, 70);
      expect(fp.top, closeTo(691, 1.5));
      // .pl-edge { left:10%; right:10%; bottom:0; height:2 } —— 358 的 10% = 35.8
      final Rect edge = tester.getRect(find.byKey(const Key('plate.edge')));
      expect(edge.left, closeTo(51.8, .1));
      expect(edge.width, closeTo(286.4, .1));
      expect(edge.bottom, closeTo(780, .1));
      expect(edge.height, 2);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('不可见时不占位', (WidgetTester tester) async {
      await _mount(
        tester,
        const Plate(
          quest: Quest.demo,
          host: HostState.demo,
          visible: false,
          animateLand: false,
        ),
      );
      expect(find.byKey(const Key('plate')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('板下的两个按钮', () {
    testWidgets('渲染「宿主 · 」前缀与文案，并在实测坐标', (WidgetTester tester) async {
      await _mount(tester, const PlateAlt(labels: <String>['换一个', '等会儿']));
      expect(find.text('换一个'), findsOneWidget);
      expect(find.text('等会儿'), findsOneWidget);
      expect(find.text('宿主 · '), findsNWidgets(2));
      final Rect row = tester.getRect(find.byType(Row).first);
      expect(row.left, 16);
      expect(row.right, 374);
      expect(row.bottom, closeTo(826, .5)); // bottom:18 + 高 36
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('D4：点「换一个 / 等会儿」回调 onPick(0/1)', (WidgetTester tester) async {
      // 数据源 mock：业务（QuestFlow.retreat / later）在 QuestFlow，装配归 main.dart（t10）。
      // 这里按 docs/18 §1.3-D4 的接口契约用闭包记录回调，钉住索引语义：
      // 0 = retreat（换一个：降一档 / F 级换同档他单 / 当日 3 次戴「口头巨人」）
      // 1 = later（等会儿：单子留在队列、回大厅）
      final List<int> picked = <int>[];
      await _mount(
        tester,
        PlateAlt(
          labels: const <String>['换一个', '等会儿'],
          onPick: picked.add,
        ),
      );
      await tester.tap(find.byKey(const Key('plate.alt.0')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('plate.alt.1')));
      await tester.pump();
      expect(picked, <int>[0, 1]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('D4：没接线（onPick 缺省）时按下只有 :active 变色、不抛异常', (
      WidgetTester tester,
    ) async {
      await _mount(tester, const PlateAlt(labels: <String>['换一个', '等会儿']));
      await tester.tap(find.byKey(const Key('plate.alt.0')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('D4：收起时断掉命中（点不到）', (WidgetTester tester) async {
      int? picked;
      await _mount(
        tester,
        PlateAlt(
          labels: const <String>['换一个', '等会儿'],
          visible: false,
          onPick: (int i) => picked = i,
        ),
      );
      // IgnorePointer 生效时 tap 落空（warnIfMissed 关掉警告，断言确实没触发）
      await tester.tap(find.byKey(const Key('plate.alt.0')), warnIfMissed: false);
      await tester.pump();
      expect(picked, isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
  // ── 显示 = 结算（t24 · 机制化约束）──────────────────────────
  //
  // 「显示 ≠ 结算」已经复发两次：t15 把 loot 面板从原型旧表切到 Rewards 表，
  // 却在补救单场景漏了 ×0.5；t24 之前 plate.dart 又自己拼数字，同 E 级补救单
  // 两块板显示 `EXP 1 · ◈ 5` / `EXP 0 · ◈ 3`，都不是真源 `1/3`。
  // 两次都不是「没测试」，而是**没有一条「显示必须从真源派生」的约束**。
  // 下面这组就是那条约束：全档位遍历 + 真渲染出来的文案 + 真结算出账，
  // 三方对齐；谁再自己拼一个数就红。
  group('显示 = 结算（全档位 · 防第三次复发）', () {
    const List<String> kAllRanks = <String>['F', 'E', 'D', 'C', 'B', 'A', 'S'];

    Quest questOf(
      String rank, {
      String kind = 'daily',
      Map<String, int> attrs = const <String, int>{'体': 1, '力': 1},
    }) => Quest(
      serial: 41,
      kind: kind,
      planIndex: -1,
      planTotal: 0,
      name: 'x',
      reason: '',
      proof: 'y',
      minutes: 10,
      rank: rank,
      attrs: attrs,
    );

    /// 渲染真板子，把「报酬」行那条文案原样读回来（不是读 Quest 的 getter，
    /// 是读 widget 树里真正印出去的那个字符串）
    Future<String> plateLootText(WidgetTester tester, Quest q) async {
      await _mount(
        tester,
        Plate(quest: q, host: HostState.demo, animateLand: false),
      );
      final String text = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => t.data)
          .whereType<String>()
          .firstWhere((String s) => s.startsWith('EXP '), orElse: () => '');
      await tester.pumpWidget(const SizedBox());
      return text;
    }

    test('全档位（F~S）：板面文案 == Rewards.payout 派生（普通 / 补救 / 暴击 / 双倍 / 叠乘）', () {
      for (final String rank in kAllRanks) {
        for (final bool remedy in <bool>[false, true]) {
          for (final bool crit in <bool>[false, true]) {
            for (final bool dbl in <bool>[false, true]) {
              final Payout p = Rewards.payout(
                rank: rank,
                crit: crit,
                dbl: dbl,
                remedy: remedy,
              );
              final String where =
                  '$rank remedy=$remedy crit=$crit dbl=$dbl';
              // 真源派生（板面显示就是这一句）
              expect(
                Quest.lootTextOf(
                  rank: rank,
                  remedy: remedy,
                  crit: crit,
                  dbl: dbl,
                  attrs: const <String, int>{},
                ),
                'EXP ${p.exp} · ◈ ${p.coin}',
                reason: where,
              );
              // 结算真源：quest_flow.settle 的同一条公式（补救 ×0.5 → 暴击 ×2
              // → 双倍 ×2 只吃经验），两边逐档同值
              final double k = remedy ? .5 : 1;
              final int base = (Rewards.expOf(rank) * k).round();
              expect(base * (crit ? 2 : 1) * (dbl ? 2 : 1), p.exp, reason: where);
              expect(
                (Rewards.coinOf(rank) * k).round() * (crit ? 2 : 1),
                p.coin,
                reason: where,
              );
            }
          }
        }
      }
    });

    test('补救单口径回归：E 级补救 = EXP 1 · ◈ 3（旧写法会印出 1 / 5）', () {
      final Quest remedyE = questOf('E', kind: 'remedy');
      expect(remedyE.lootText, 'EXP 1 · ◈ 3体+1 力+1');
      // 这正是 docs/20 §2.2-1 记录的那次回归：漏 ×0.5 时 = 表值
      expect(Rewards.expOf('E'), 1);
      expect(Rewards.coinOf('E'), 5); // 5 × .5 = 2.5 → 3
    });

    test('补救单真结算 == 板面文案（走 QuestFlow.settle 全链路）', () async {
      for (final String rank in kAllRanks) {
        final Quest remedy = questOf(rank, kind: 'remedy');
        final QuestFlow f = QuestFlow(
          host: HostState.empty,
          goal: Goal.demo(),
        )..accept(remedy);
        final QuestResult r = await f.settle(forceCrit: false);
        // 板面那一行必须**逐字**含真结算的两个数（不是各自算一遍再比）
        expect(
          remedy.lootText,
          startsWith('EXP ${r.exp} · ◈ ${r.coin}'),
          reason: '$rank 补救单：结算出账 vs 板面文案',
        );
        // 结算数字本身 = Rewards 表（补救 ×0.5 → 暴击 ×2 → 双倍只吃经验）
        final Payout p = Rewards.payout(
          rank: rank,
          crit: r.crit,
          dbl: r.dbl,
          remedy: true,
        );
        expect(r.exp, p.exp, reason: '$rank 补救单 EXP');
        expect(r.coin, p.coin, reason: '$rank 补救单金币');
      }
    });

    testWidgets('派单板真渲染：普通单与补救单印出的都是 lootText（含 ×0.5）', (
      WidgetTester tester,
    ) async {
      // 普通 C 级主线（demo 单）：EXP 4 · ◈ 5 体+1 力+1
      expect(
        await plateLootText(tester, Quest.demo),
        Quest.demo.lootText,
      );
      expect(await plateLootText(tester, Quest.demo), 'EXP 4 · ◈ 5体+1 力+1');

      // 补救单：F 级（金币 3 × .5 = 1.5 → 2）与 E 级（EXP 1 / 金币 3）
      final Quest remedyF = questOf('F', kind: 'remedy', attrs: const <String, int>{'知': 2});
      final Quest remedyE = questOf('E', kind: 'remedy', attrs: const <String, int>{'知': 2});
      expect(await plateLootText(tester, remedyF), remedyF.lootText);
      expect(await plateLootText(tester, remedyF), 'EXP 0 · ◈ 2知+2');
      expect(await plateLootText(tester, remedyE), remedyE.lootText);
      expect(await plateLootText(tester, remedyE), 'EXP 1 · ◈ 3知+2');
    });

    test('升级曲线单一真源：HostState.need == Rewards.needFor == QuestFlow.needFor', () {
      for (int lv = 1; lv <= 30; lv++) {
        expect(HostState.need(lv), Rewards.needFor(lv), reason: 'LV$lv');
        expect(QuestFlow.needFor(lv), Rewards.needFor(lv), reason: 'LV$lv');
      }
      expect(HostState.need(1), 18);
      expect(HostState.need(7), 54); // 旧曲线 60+7×40 = 340（已废）
      expect(HostState.demo.expRatio, 1.0); // 214 / 54 → clamp 到满环
    });
  });

  // ── 数据契约 ──────────────────────────────────────────────
  // 演示档的每个字段都必须与原型 `Store.veteran()` 的 `Store.head()` 一致。
  // 改这里的数之前，先在原型里跑一次 `Store.veteran(); console.log(Store.head())`。
  // 踩过：serial 我按印象写了 80（实为 41）、reason 漏了「46 秒」——
  // 这种小字差异在区域均值里几乎看不出来，是换成干净存档后才核对出来的。
  group('演示档数据契约', () {
    test('与 Store.veteran() 的 head 任务逐字段一致', () {
      const Quest q = Quest.demo;
      expect(q.serial, 41);
      expect(q.kind, 'main');
      expect(q.planIndex, 4);
      expect(q.name, '跑完 5 公里');
      expect(q.reason, '上一张你用了 38 分 46 秒。这一张，我加了点码。');
      expect(q.proof, '跑步 App 截图');
      expect(q.minutes, 45);
      expect(q.rank, 'C');
      expect(q.attrs, <String, int>{'体': 1, '力': 1});
    });
  });

  // ── reRank 换档演出（t26/TODO-12）─────────────────────────
  //
  // 原型 `ui.js Plate.reRank(T, from)`：退缩时字母往下掉一档、报酬重刻。
  // Flutter 侧原先只在 serial 变化时重播仪式 —— 同一张单降档是**静态跳变**，
  // 玩家感知不到「她把这张单刻薄了」（MOTION-ANALYSIS P1-3）。
  // 下行滚档每档 90ms（三档 = 270ms，即验收口径「换单 270ms 下行滚档」），
  // 滚完复用 rankLock（换 token 重挂重播）+ onRankFx 收尾，再单独重刻报酬行。
  group('reRank 换档演出（t26/TODO-12）', () {
    Quest mk(String rank, {int serial = 41}) => Quest(
      serial: serial,
      kind: 'daily',
      planIndex: -1,
      planTotal: 0,
      name: 'x',
      reason: '',
      proof: 'y',
      minutes: 10,
      rank: rank,
      attrs: const <String, int>{'体': 1, '力': 1},
    );

    Widget host(Quest q, {void Function(int)? onRankFx}) => MaterialApp(
      home: Scaffold(
        body: Stack(
          children: <Widget>[Plate(quest: q, host: HostState.demo, onRankFx: onRankFx)],
        ),
      ),
    );

    /// 把开局仪式播完，落到终态。
    ///
    /// ⚠️ 滚档完成以 [rankFxSeen]（onRankFx 是否已开火）为准：
    /// `Future.delayed` 链在 FakeAsync 下起滚时刻有漂移，固定拍会截停在
    /// 仪式中途，把「换一个」的下行滚档跟残局搅在一起（实测踩过）。
    Future<void> playCeremony(WidgetTester tester, bool Function() rankFxSeen) async {
      await tester.pump(const Duration(milliseconds: 560)); // 落板
      await tester.pump(const Duration(milliseconds: 590)); // land 后的 resolve 停顿
      for (int i = 0; i < 60 && !rankFxSeen(); i++) {
        await tester.pump(const Duration(milliseconds: 50)); // 等滚档落定
      }
      await tester.pump(const Duration(milliseconds: 3200)); // 刻字播完
      await tester.pump();
    }

    testWidgets('同单降档：下行滚档替代静态跳变（90ms/档 + rankLock 重播）', (
      WidgetTester tester,
    ) async {
      int? fx;
      await _mount(tester, host(mk('C'), onRankFx: (int i) => fx = i));
      await playCeremony(tester, () => fx != null);
      expect(find.text('C'), findsOneWidget);
      expect(fx, 3); // 开局仪式照常收尾
      expect(find.textContaining('EXP 4 · ◈ 5'), findsOneWidget);

      // 「换一个」：C → D（同 serial，降一档）
      await _mount(tester, host(mk('D'), onRankFx: (int i) => fx = i));
      await tester.pump(); // t=0：下行起点 = 旧档
      expect(find.text('C'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 40)); // 90ms 内还挂在 C
      expect(find.text('C'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 60)); // t=100 ≥ 90
      expect(find.text('D'), findsOneWidget); // 落到新档
      expect(fx, 2); // onRankFx 照常收尾（原型 rankRoll 的尾巴对 down 同样生效）
      expect(find.byKey(const Key('plate.lock.1')), findsOneWidget); // 锁重播
      expect(find.byKey(const Key('plate.lock.0')), findsNothing);

      // 报酬行重刻：激光照走一遍 + 600ms 白闪收敛，最后落在新档文案上
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byKey(const Key('plate.laser')), findsOneWidget); // 重刻中
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byKey(const Key('plate.laser')), findsNothing);
      // D 档战利品（Rewards：D = EXP 2 / ◈ 5）
      expect(find.textContaining('EXP 2 · ◈ 5'), findsOneWidget);
    });

    testWidgets('三档下行恰好 270ms：C→F 逐档可见（验收口径的钉子）', (
      WidgetTester tester,
    ) async {
      int? fx;
      await _mount(tester, host(mk('C'), onRankFx: (int i) => fx = i));
      await playCeremony(tester, () => fx != null);
      fx = null; // 清掉开局那发，只看降档这一发
      await _mount(tester, host(mk('F'), onRankFx: (int i) => fx = i));
      await tester.pump(const Duration(milliseconds: 45)); // [0,90) C
      expect(find.text('C'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 50)); // [90,180) D
      expect(find.text('D'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 85)); // [180,270) E
      expect(find.text('E'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 90)); // t=270 落 F
      expect(find.text('F'), findsOneWidget);
      // 恰好压线完成的 onFinish 随下一帧落地（零拍 pump 冲不动它，实测踩过）
      await tester.pump(const Duration(milliseconds: 16));
      expect(fx, 0);
      expect(find.byKey(const Key('plate.lock.1')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.textContaining('EXP 0 · ◈ 3'), findsOneWidget); // F 档战利品
    });

    testWidgets('静态比对（animateLand:false）降档：直接落终态，不播仪式', (
      WidgetTester tester,
    ) async {
      Widget staticHost(Quest q) => MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[Plate(quest: q, host: HostState.demo, animateLand: false)],
          ),
        ),
      );
      await _mount(tester, staticHost(mk('C')));
      expect(find.text('C'), findsOneWidget);
      await _mount(tester, staticHost(mk('F')));
      await tester.pump();
      expect(find.text('F'), findsOneWidget); // 立即终态
      expect(find.byKey(const Key('plate.lock.1')), findsOneWidget);
      expect(find.textContaining('EXP 0 · ◈ 3'), findsOneWidget);
    });

    testWidgets('F 级「换一个」是换一张（serial 变）→ 原样重刻一块，无锁', (
      WidgetTester tester,
    ) async {
      Widget staticHost(Quest q) => MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[Plate(quest: q, host: HostState.demo, animateLand: false)],
          ),
        ),
      );
      await _mount(tester, staticHost(mk('C')));
      await _mount(tester, staticHost(mk('E', serial: 42)));
      await tester.pump();
      expect(find.text('E'), findsOneWidget);
      expect(find.text('№ 0042'), findsOneWidget); // 新单号
      expect(find.textContaining('EXP 1 · ◈ 5'), findsOneWidget);
      // 换单走 _start（静态不挂锁），只有 reRank 才有 rankLock 重播
      expect(find.byKey(const Key('plate.lock.1')), findsNothing);
    });
  });

}
