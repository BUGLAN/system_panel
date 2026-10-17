import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/stage/camera.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/host_state.dart';
import 'package:system_panel/widgets/chat_bar.dart';
import 'package:system_panel/widgets/dock.dart';
import 'package:system_panel/widgets/exec_pill.dart';
import 'package:system_panel/widgets/hud.dart';
import 'package:system_panel/widgets/line_layer.dart';
import 'package:system_panel/widgets/plan_tag.dart';
import 'package:system_panel/widgets/type_text.dart';

/// 大厅页（HUD / 字幕 / 底栏）。
///
/// 这里的坐标断言全部来自**运行中的原型实测值**（getBoundingClientRect 换算到
/// #app 的逻辑坐标，390×844）。原型一改，这里必须跟着改 —— 这就是回归网。
///
/// ⚠️ `flutter test` 用的是占位字体：**每个字形都按 1em 宽**渲染，真实字体资产
/// 不参与排版。所以凡是"宽度由文字撑出来"的坐标（金币芯片的左缘、.cta-n 的宽度…）
/// 在单测里量不准，这里只断言与文字宽度无关的部分；真实字体的观感与坐标由
/// 真机截图 + 原型比对负责（见 .verify/step2-compare.png）。
const Size kDesign = Size(390, 844);

/// ⚠️ 必须用 `tester.view` 设尺寸（不是 `setSurfaceSize`）：
/// 后者只改 surface、**不改 MediaQuery**，于是组件里 `MediaQuery.sizeOf` 读到的
/// 还是 800×600 —— 大厅那批按百分比/相机数学定位的断言就全错位
/// （app/PORTING-NOTES.md 第 13 条；docs/39 H-08 的 clamp 上界也被它坑过）。
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

void main() {
  // ⚠️ 回归网：`Hud` / `Dock` 的 build 顶层是 `Positioned`（ParentDataWidget），
  //    唤醒过场的淡入**必须**在它们**内部**套 Opacity。2026-10-11 我在 main.dart
  //    外面包了一层带 RenderObject 的包装件，真机直接抛
  //    `Incorrect use of ParentDataWidget`（HUD 与底栏各一次）—— 这条用例就是
  //    防它回归：挂在 Stack 里跑一遍淡入，异常会被 flutter_test 记为失败。
  testWidgets('Hud/Dock 淡入：Opacity 在内部，不抛 ParentDataWidget', (WidgetTester tester) async {
    final AnimationController c = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 900),
    );
    addTearDown(c.dispose);
    await _mount(
      tester,
      Stack(
        children: <Widget>[
          Hud(state: HostState.demo, fade: c),
          Dock(state: HostState.demo, fade: c),
        ],
      ),
    );
    c.forward(from: 0);
    await tester.pump(); // 先让 ticker 起跑一帧（不然第一次 pump 的 elapsed 还是 0）
    await tester.pump(const Duration(milliseconds: 300));
    final List<double> ops = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((Opacity o) => o.opacity)
        .toList();
    expect(ops.any((double o) => o > 0 && o < 1), isTrue,
        reason: '淡入途中应出现中间不透明度（说明 Opacity 真的接上了动画）');
    expect(tester.takeException(), isNull, reason: '不许有框架异常');
    // ⚠️ 不能用 pumpAndSettle：Hud/Dock 里有常驻呼吸/脉冲动画，永远 settle 不了。
    //    有界推进到淡入结束即可。
    await tester.pump(const Duration(milliseconds: 1200));
    final List<double> done = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((Opacity o) => o.opacity)
        .toList();
    expect(done.every((double o) => o > .99 || o == 0), isTrue,
        reason: '淡入结束后应回到 1（或本来就该隐的 0）');
    expect(tester.takeException(), isNull);
  });

  group('宿主档案', () {
    test('升级所需经验 = Rewards 曲线 12 + lv×6（旧 60+lv*40 已废）', () {
      expect(HostState.need(1), 18);
      expect(HostState.need(7), 54);
    });

    test('演示档与原型「老宿主 · 第 23 天」一致', () {
      const HostState s = HostState.demo;
      expect(s.name, '林深');
      expect(s.lv, 7);
      expect(s.exp, 214);
      expect(s.coins, 340);
      expect(s.streak, 6);
      expect(s.title, 'done15');
      expect(s.queue, 4);
      // t24：分母改结算曲线 12+7×6=54（214/54 越界 → clamp 满环）
      expect(s.expRatio, 1.0);
    });
  });

  group('HUD', () {
    testWidgets('名字 / 称号 / 金币 / 等级都渲染', (WidgetTester tester) async {
      await _mount(tester, const Hud(state: HostState.demo));
      expect(find.text('林深'), findsOneWidget);
      expect(find.text('「惯犯」'), findsOneWidget);
      expect(find.text('340'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('LV'), findsOneWidget);
      // ⚠️ 「连击」已**摘出** `.hud-who`，成了独立的 [StreakPill]（宿主 2026-10-11
      //    「给它换个位置」；main.dart 里以 `visible:false` 挂载）——它不再属于
      //    `Hud`，所以断言搬到了下面那条 StreakPill 用例里，这里不要它。
      expect(tester.takeException(), isNull);
    });

    testWidgets('连击药丸（已摘出 Hud）：读数照旧，visible 只管透明度不管存在', (
      WidgetTester tester,
    ) async {
      await _mount(tester, const StreakPill(streak: 12));
      // ⚠️ 读数走 `Text.rich`（数字要单独换字体），所以断言必须开 findRichText ——
      //    `find.text` 只认 `Text.data`，span 里的字它看不见。
      expect(find.textContaining('连击', findRichText: true), findsOneWidget);
      expect(find.textContaining('12', findRichText: true), findsOneWidget);

      // 0 连击 → 破折号，不冒数字
      await _mount(tester, const StreakPill(streak: 0));
      expect(find.textContaining('连击 —', findRichText: true), findsOneWidget);

      // visible:false 是「淡出」不是「移除」（main.dart 现在就是这个状态）——
      // 文字仍在树里，靠 AnimatedOpacity 压到 0
      await _mount(tester, const StreakPill(streak: 5, visible: false));
      expect(find.textContaining('连击', findRichText: true), findsOneWidget);
    });

    testWidgets('各件落在 docs/39 §3.1 的新规格坐标上', (WidgetTester tester) async {
      await _mount(tester, const Hud(state: HostState.demo));
      // docs/39 H-02：左右边距 20（原 16）→ lv [20,22,48,48]（H-03：46 → 48）
      expect(
        tester.getRect(find.byKey(const Key('hud.lv'))),
        const Rect.fromLTWH(20, 22, 48, 48),
      );
      // H-06：**视觉盒仍是 34×34**（命中盒 44 在外面那层，不影响这里的坐标）；
      // 右缘 = 390 - 20（H-02 的右边距），所以左上 = 336
      expect(
        tester.getRect(find.byKey(const Key('hud.menu'))),
        const Rect.fromLTWH(336, 29, 34, 34),
      );
      final Rect coin = tester.getRect(find.byKey(const Key('hud.coin')));
      // 右缘由「菜单固定 34 + 间距 10 + 右边距 20」定死，与文字宽度无关
      expect(coin.right, closeTo(326, .5));
      expect(coin.top, 30); // H-05：高 30 → 32，竖向居中在 74 的 HUD 里
      expect(coin.height, 32);
    });

    testWidgets('H-01 顶部压暗：高 116、压在她之上（HUD 之内）、不改 HUD 盒高', (
      WidgetTester tester,
    ) async {
      await _mount(tester, const Hud(state: HostState.demo));
      final Rect scrim = tester.getRect(find.byKey(const Key('hud.scrim')));
      expect(scrim.top, 0);
      expect(scrim.height, 116);
      expect(scrim.width, 390); // 满宽
      // HUD 盒仍是 74（H-02「高 74 不变」），承托允许画到盒外
      expect(tester.getSize(find.byType(Hud)).height, 74);
    });

    testWidgets('H-06 菜单：视觉 34 但命中 44×44，点边缘也能开', (
      WidgetTester tester,
    ) async {
      int opened = 0;
      await _mount(
        tester,
        Hud(state: HostState.demo, onMenu: () => opened++),
      );
      final Rect visual = tester.getRect(find.byKey(const Key('hud.menu')));
      // 命中盒 = 视觉盒外扩 5：在视觉盒左缘往左 4px 处点，仍应命中
      await tester.tapAt(visual.centerLeft + const Offset(-4, 0));
      await tester.pump();
      expect(opened, 1, reason: 'H-06：透明命中必须扩到 44×44');
      expect(tester.takeException(), isNull);
    });
  });

  group('底栏', () {
    testWidgets('三颗侧键 + 委托环 + 底注都在', (WidgetTester tester) async {
      await _mount(tester, const Dock(state: HostState.demo));
      expect(find.text('主线'), findsOneWidget);
      expect(find.text('档案'), findsOneWidget);
      expect(find.text('补给'), findsOneWidget);
      expect(find.text('委托'), findsOneWidget);
      expect(find.text('TASK'), findsOneWidget);
      expect(find.text('4'), findsOneWidget); // .cta-n 上的单数
      expect(find.text('她手里有 4 单'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('各件落在 docs/39 §3.3 的新规格坐标上', (WidgetTester tester) async {
      await _mount(tester, const Dock(state: HostState.demo));
      // cta [268,712,104,104] · core [276,720,88,88] 是**原型实测**；
      // docs/39 H-17 把底栏内边距 26 抬到 34（安全区下限），整块内容因此上移 8，
      // 所以新规格 = 原型值 − 8，x 与尺寸一律不变。
      expect(
        tester.getRect(find.byKey(const Key('dock.cta'))),
        const Rect.fromLTWH(268, 704, 104, 104),
      );
      expect(
        tester.getRect(find.byKey(const Key('dock.cta.core'))),
        const Rect.fromLTWH(276, 712, 88, 88),
      );
      // .cta-n 是 min-width:24 的胶囊：右/上/高与文字无关，宽度至少 24
      final Rect n = tester.getRect(find.byKey(const Key('dock.cta.n')));
      expect(n.right, closeTo(370, .5));
      expect(n.top, 706); // H-17：整块 −8
      expect(n.height, 24);
      expect(n.width, greaterThanOrEqualTo(24));
      // H-15：底注 10pt / bottom 8 → 11pt / bottom 14（844 - 14 = 830）
      final Rect cap = tester.getRect(find.byKey(const Key('dock.cap')));
      expect(cap.left, 268);
      expect(cap.width, 104);
      expect(cap.bottom, closeTo(830, .5));
      final Rect k1 = tester.getRect(find.byKey(const Key('dock.key.main')));
      expect(k1.left, 18);
      expect(k1.top, closeTo(741, 1)); // H-17：749 − 8
      expect(k1.width, 58);
      // H-14：间距 6 → 8 → 18 + (58+8) + (58+8) = 150
      final Rect k3 = tester.getRect(find.byKey(const Key('dock.key.supply')));
      expect(k3.left, 150);
      await tester.pumpWidget(const SizedBox());
    });

    // docs/39 H-15 · 主 CTA 三态（P0）：原先 running 是写死的 false，
    // 「执行中」分支根本不可达 —— 这三条用例就是钉住那个状态机。
    group('H-15 主 CTA 三态', () {
      testWidgets('待接：青球 + 委托/TASK + 徽标 N + 队列读数', (WidgetTester tester) async {
        await _mount(tester, const Dock(state: HostState.demo));
        expect(find.text('委托'), findsOneWidget);
        expect(find.text('TASK'), findsOneWidget);
        expect(find.byKey(const Key('dock.cta.n')), findsOneWidget);
        expect(find.text('她手里有 4 单'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('执行中：计时 + 执行中 9pt + 徽标隐藏 + 底注「点开 · 继续」', (
        WidgetTester tester,
      ) async {
        await _mount(
          tester,
          const Dock(
            state: HostState.demo,
            running: true,
            elapsed: Duration(minutes: 12, seconds: 4),
          ),
        );
        expect(find.text('12:04'), findsOneWidget); // Tektur 22 的计时
        expect(find.text('执行中'), findsOneWidget);
        expect(find.text('委托'), findsNothing);
        expect(find.byKey(const Key('dock.cta.n')), findsNothing);
        expect(find.text('点开 · 继续'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('今日已清：队列 0 → 今日已清、无徽标、底注是真实换日倒计时', (
        WidgetTester tester,
      ) async {
        await _mount(
          tester,
          Dock(state: HostState.demo.copyWith(queue: 0)),
        );
        expect(find.text('今日已清'), findsOneWidget);
        expect(find.byKey(const Key('dock.cta.n')), findsNothing);
        // H-15：不再是写死的「换日还有 0 小时」
        expect(find.text('换日还有 0 小时'), findsNothing);
        final Text cap = tester.widget<Text>(find.byKey(const Key('dock.cap')));
        expect(cap.data, startsWith('换日还有 '));
        await tester.pumpWidget(const SizedBox());
      });

      test('换日倒计时是真实读数（纯函数）', () {
        // 22:00 → 还有 2 小时；23:30 → 还有 30 分钟
        expect(dockRollCap(DateTime(2026, 10, 17, 22)), '换日还有 2 小时');
        expect(dockRollCap(DateTime(2026, 10, 17, 23, 30)), '换日还有 30 分钟');
        // 跨月也按第二天 0 点算
        expect(dockRollCap(DateTime(2026, 10, 31, 20)), '换日还有 4 小时');
        // 23:59:40 → 不足 1 分钟也得给个读数（不出现「0 小时」）
        expect(dockRollCap(DateTime(2026, 10, 17, 23, 59, 40)), contains('1 分钟'));
      });
    });

    testWidgets('隐藏态整条底栏沉到屏幕外（app.css L211）', (WidgetTester tester) async {
      await _mount(tester, const Dock(state: HostState.demo, visible: false));
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        tester.getRect(find.byKey(const Key('dock.cta'))).top,
        greaterThan(844),
      );
      await tester.pumpWidget(const SizedBox());
    });
  });

  // docs/39 H-08（P0）· 主线挂签重做：恒 .18 + 右边缘越界被裁 + 不跟推镜。
  // 这三条钉住新规格里最容易再退化的三点：三档不透明度、夹取、跟 camObj。
  group('主线挂签（H-08）', () {
    final Goal goal = Goal.demo(); // 0/8，短字「半马」

    testWidgets('112×48 两行挂签：主线 / 4/8 / 短字 + 2px 进度条', (
      WidgetTester tester,
    ) async {
      await _mount(tester, PlanTag(goal: goal));
      final Rect tag = tester.getRect(find.byKey(const Key('planTag')));
      expect(tag.width, closeTo(112, .01));
      expect(tag.height, closeTo(48, .01));
      expect(find.text('主线'), findsOneWidget);
      // Goal.demo() 的 8 张里已完成 4 张 → 挂签读数是 4/8（不是 0/8）
      expect(find.textContaining('4/8', findRichText: true), findsOneWidget);
      expect(find.text('半马'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('三档不透明度：常态 .78 / 说话 .55 / 失败 .35（不再是 .18）', (
      WidgetTester tester,
    ) async {
      // 淡入层是 planTag **外面**那圈 AnimatedOpacity（Positioned > IgnorePointer >
      // AnimatedOpacity > GestureDetector > planTag），所以用 descendant 找。
      // 这里读的是契约值（组件 API 传进来的那一档），真实渲染交给 FadeTransition。
      Future<double> opacityOf(PlanTagTone tone) async {
        await _mount(tester, PlanTag(goal: goal, tone: tone));
        final double v = tester
            .widget<AnimatedOpacity>(find.byKey(const Key('planTag.fade')))
            .opacity;
        expect(v, isNot(closeTo(.18, .01)), reason: '不再是环时代那个恒定的 .18');
        await tester.pumpWidget(const SizedBox());
        return v;
      }

      expect(await opacityOf(PlanTagTone.normal), closeTo(.78, .01));
      expect(await opacityOf(PlanTagTone.speaking), closeTo(.55, .01));
      expect(await opacityOf(PlanTagTone.failed), closeTo(.35, .01));
    });

    testWidgets('左缘夹在 [16, W-16-112]：锚点在屏外也不会越界被裁', (
      WidgetTester tester,
    ) async {
      // 大厅相机下挂签本来就该在屏内；换一个把锚点推到右缘外的相机
      await _mount(
        tester,
        PlanTag(goal: goal, cam: 'lobby', camObj: const Cam(2.6, 0, -.535, .5, .5)),
      );
      // 屏宽从本 widget 的 MediaQuery 取（_mount 的 surface 与 MediaQuery 未必同源）
      final Size screen = MediaQuery.sizeOf(tester.element(find.byType(PlanTag)));
      final Rect tag = tester.getRect(find.byKey(const Key('planTag')));
      expect(tag.left, greaterThanOrEqualTo(16));
      expect(tag.right, lessThanOrEqualTo(screen.width - 16 + .01));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('跟 camObj 逐帧走：换一帧相机，挂签跟着挪', (
      WidgetTester tester,
    ) async {
      await _mount(tester, PlanTag(goal: goal, camObj: Cam.byName('lobby')));
      final double atLobby = tester.getRect(find.byKey(const Key('planTag'))).top;
      await _mount(tester, PlanTag(goal: goal, camObj: Cam.byName('boot')));
      final double atBoot = tester.getRect(find.byKey(const Key('planTag'))).top;
      expect(atBoot, isNot(closeTo(atLobby, 1)),
          reason: 'camObj 变了挂签必须跟着环走（只吃字符串时这里是钉死的）');
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('字幕', () {
    testWidgets('渲染文本 / SYSTEM / 情绪词，且落在实测坐标', (WidgetTester tester) async {
      await _mount(
        tester,
        const LineLayer(text: '我手里有 5 单。都是给你的。', mood: '尚可', y: 506.4),
      );
      expect(find.text('我手里有 5 单。都是给你的。'), findsOneWidget);
      expect(find.text('SYSTEM'), findsOneWidget);
      expect(find.textContaining('尚可'), findsWidgets);

      // 原型实测：line [20,506,350,71]
      final Rect line = tester.getRect(find.byKey(const Key('line')));
      expect(line.left, 20);
      expect(line.right, 370);
      expect(line.top, closeTo(506.4, .5));
      expect(line.height, closeTo(71, 1.5));

      // docs/22 §R4 对白节奏三档：没给 paceMs → TypeText 用自己的默认（34）；
      // main.dart 接线后给 24/34/42 → 原样透传到打字机的 speed
      expect(tester.widget<TypeText>(find.byType(TypeText)).speed, isNull);
      await tester.pumpWidget(const SizedBox());
      await _mount(
        tester,
        const LineLayer(
          text: '我手里有 5 单。都是给你的。',
          mood: '尚可',
          y: 506.4,
          paceMs: 24, // 快档
        ),
      );
      expect(tester.widget<TypeText>(find.byType(TypeText)).speed, 24);
      await tester.pumpWidget(const SizedBox());
    });

    // docs/39 H-12（P1）· 字幕上限：真机上 LLM 长句会把玻璃带一路撑到聊天钮
    // 与主线挂签上（走查 §2.1）。这里钉住四条：
    //   ① maxLines 3 + ellipsis 真的**下发到了 Text.rich**（打字机自己不给参数，
    //      要靠 DefaultTextStyle —— 这一条就是钉那个下发链路）；
    //   ② 超过 3 行估算（> 57 字）才是 16.5，否则 17；
    //   ③ 判据是**整句全长**：只显形了几个字时字号不许跳；
    //   ④ 上边线 α .20 → .26（51 → 66）。
    group('H-12 字幕 maxLines / 长句降字号', () {
      TextStyle textStyleOf(WidgetTester tester) =>
          tester.widget<TypeText>(find.byType(TypeText)).style!;

      testWidgets('短句：3 行上限 + 省略号下发，字号 17', (WidgetTester tester) async {
        await _mount(
          tester,
          const LineLayer(text: '我手里有 5 单。都是给你的。', mood: '尚可', y: 506.4),
        );
        // ① 下发链路：DefaultTextStyle(3 行 + ellipsis) → Text.rich
        final DefaultTextStyle dts = tester
            .widgetList<DefaultTextStyle>(find.byType(DefaultTextStyle))
            .firstWhere((DefaultTextStyle d) => d.maxLines != null);
        expect(dts.maxLines, 3);
        expect(dts.overflow, TextOverflow.ellipsis);
        final RichText rt = tester
            .widgetList<RichText>(find.byType(RichText))
            .firstWhere((RichText r) => r.text.toPlainText().contains('我手里'));
        expect(rt.maxLines, 3, reason: 'Text.rich 必须真的吃到 3 行上限');
        expect(rt.overflow, TextOverflow.ellipsis);
        // ② 短句 → 17（原来的字号）
        expect(textStyleOf(tester).fontSize, 17);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('长句（> 57 字）：字号降到 16.5，仍是 3 行上限', (
        WidgetTester tester,
      ) async {
        // 19 字/行 × 3 行 = 57：这里给 60 个中文字（越过阈值）
        // 60 个中文字（19×3 = 57 是阈值，这里刻意越过）——
        // ⚠️ 别用 53 字那种"看着很长其实没到"的句子，否则测的是短句分支。
        const String long =
            '你打算用一句空话把半年拆成八环吗，别想了，先把今天这一单做完再说，'
            '剩下的我替你盯着，做不到就等着被笑话吧，反正丢人的不是我。';
        expect(long.runes.length, greaterThan(57), reason: '测试数据本身要越过阈值');
        await _mount(tester, const LineLayer(text: long, y: 506.4));
        expect(textStyleOf(tester).fontSize, 16.5);
        final RichText rt = tester
            .widgetList<RichText>(find.byType(RichText))
            .firstWhere((RichText r) => r.text.toPlainText().contains('半年拆成'));
        expect(rt.maxLines, 3);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('打字途中字号不跳：按整句全长判，不按已显形字数', (
        WidgetTester tester,
      ) async {
        const String long =
            '你打算用一句空话把半年拆成八环吗，别想了，先把今天这一单做完再说，'
            '剩下的我替你盯着，做不到就等着被笑话吧，反正丢人的不是我。';
        await _mount(tester, const LineLayer(text: long, y: 506.4));
        // 刚挂上只显形几个字（打字机才起步）—— 字号必须已经是 16.5
        expect(textStyleOf(tester).fontSize, 16.5);
        await tester.pump(const Duration(milliseconds: 200));
        expect(textStyleOf(tester).fontSize, 16.5);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('上边线 α .26（原来 .20）', (WidgetTester tester) async {
        await _mount(tester, const LineLayer(text: '一句短的。', y: 506.4));
        // 玻璃带 ::before 的装饰：找带 top BorderSide 的那个 DecoratedBox
        final Iterable<DecoratedBox> boxes = tester.widgetList<DecoratedBox>(
          find.byType(DecoratedBox),
        );
        final BoxDecoration band = boxes
            .map((DecoratedBox b) => b.decoration)
            .whereType<BoxDecoration>()
            .firstWhere((BoxDecoration d) => d.gradient != null);
        expect(
          band.border!.top.color.a,
          closeTo(.26, .01),
          reason: 'H-12：字幕带上边线不透明度 .20 → .26',
        );
        expect(band.border!.top.width, 1);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('H-17 底边下限：给了 bottomFloor 就把字幕顶上去', (
        WidgetTester tester,
      ) async {
        // 844 高、底边下限 100：字幕带底边不许低于 744
        await _mount(
          tester,
          const LineLayer(text: '一句短的。', y: 780, bottomFloor: 100),
        );
        final Rect line = tester.getRect(find.byKey(const Key('line')));
        expect(line.bottom, lessThanOrEqualTo(844 - 100 + .5));
        await tester.pumpWidget(const SizedBox());
      });
    });

    // docs/39 H-16（P1）· 执行药丸：原来 `TweenAnimationBuilder` 的 begin 与 end
    // 是同一个表达式（`visible ? 1 : 0` 两边一样）→ 400ms 入场是**死代码**，
    // 一帧都不播。这里把「真的会经过 0<opacity<1」钉死：这类"参数写错但能编译"的
    // 退化只有靠中间帧断言才抓得住。
    group('H-16 执行药丸进出场', () {
      Future<void> mount(WidgetTester tester, bool visible) async {
        await _mount(
          tester,
          ExecPill(
            visible: visible,
            elapsed: const Duration(minutes: 1),
          ),
        );
      }

      double pillOpacity(WidgetTester tester) => tester
          .widgetList<Opacity>(find.byType(Opacity))
          .map((Opacity o) => o.opacity)
          .fold<double>(1, (double a, double b) => a * b);

      testWidgets('入场：200ms 途中出现 0<opacity<1，终态为 1', (
        WidgetTester tester,
      ) async {
        await mount(tester, true); // 首帧就按 visible 落位 = 1（不补播首屏）
        expect(pillOpacity(tester), closeTo(1, .001));
        // 翻成不可见 → 160ms 淡出
        await _mount(
          tester,
          const ExecPill(visible: false, elapsed: Duration.zero),
        );
        await tester.pump(const Duration(milliseconds: 80));
        final double half = pillOpacity(tester);
        expect(
          half,
          greaterThan(0),
          reason: '淡出途中不许一帧跳到 0（那又变成硬切）',
        );
        expect(half, lessThan(1));
        await tester.pump(const Duration(milliseconds: 200));
        expect(pillOpacity(tester), closeTo(0, .001));
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('入场路径真的走：从 0 到 1 的中间帧（死代码回归）', (
        WidgetTester tester,
      ) async {
        // 先用 visible:false 挂上 → 药丸在但 opacity 0
        await mount(tester, false);
        expect(pillOpacity(tester), closeTo(0, .001));
        // 再翻成 true（同一个 State，走了 didUpdateWidget 的进场分支）
        await mount(tester, true);
        await tester.pump(const Duration(milliseconds: 100));
        final double mid = pillOpacity(tester);
        expect(
          mid,
          allOf(greaterThan(0), lessThan(1)),
          reason: 'H-16：入场必须真的播（原来 begin==end，这里永远到不了 1 以外的值）',
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(pillOpacity(tester), closeTo(1, .001));
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('闪烁周期 2.4s（与 Motion.heartMs 同步）', (
        WidgetTester tester,
      ) async {
        await mount(tester, true);
        // 点/灯是 7px 的圆：读它的 color alpha 在两个半周期之间变
        Color dot(WidgetTester t) {
          final Iterable<Container> cs = t.widgetList<Container>(
            find.byType(Container),
          );
          final Container c = cs.firstWhere((Container c) {
            final Decoration? d = c.decoration;
            return d is BoxDecoration && d.shape == BoxShape.circle;
          });
          return (c.decoration! as BoxDecoration).color!;
        }

        await tester.pump(); // 起跑
        final double a0 = dot(tester).a;
        // 1.2s 后刚好走过半个周期（亮 → 暗）
        await tester.pump(const Duration(milliseconds: 1200));
        final double a1 = dot(tester).a;
        expect(a0, isNot(closeTo(a1, .01)), reason: '2.4s 周期在 1.2s 处该翻面');
        // 再走 1.2s 回到原相位
        await tester.pump(const Duration(milliseconds: 1200));
        expect(dot(tester).a, closeTo(a0, .02));
        await tester.pumpWidget(const SizedBox());
      });
    });
  });

  group('对话入口（docs/18 §2.6，t10）', () {
    testWidgets('大厅左上 34×34 玻璃圆钮：HUD 行下方、可点开聊', (WidgetTester tester) async {
      // main.dart 的装配位：left 16 / top 78（HUD 行 74 之下）
      final List<int> opens = <int>[];
      await _mount(
        tester,
        Positioned(
          left: 16,
          top: 78,
          child: ChatEntryButton(onTap: () => opens.add(1)),
        ),
      );
      final Rect r = tester.getRect(find.byKey(const Key('chat.entry')));
      expect(r, const Rect.fromLTWH(16, 78, 34, 34));
      expect(opens, isEmpty);
      await tester.tap(find.byKey(const Key('chat.entry')));
      await tester.pump();
      expect(opens, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });
  });
}
