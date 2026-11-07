import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:system_panel/agent/goal_match_agent.dart';
import 'package:system_panel/agent/guardrail.dart';
import 'package:system_panel/agent/llm_client.dart';
import 'package:system_panel/agent/mainline_tool.dart';
import 'package:system_panel/agent/plan_agent.dart';
import 'package:system_panel/agent/plan_brief.dart';
import 'package:system_panel/agent/tools.dart';
import 'package:system_panel/data/crisis_words.dart';
import 'package:system_panel/design/ref.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/goal_gen.dart';
import 'package:system_panel/state/plan_failure.dart';
import 'package:system_panel/state/sfx.dart';
import 'package:system_panel/ui/ref/ref_goal_swap.dart';
import 'package:system_panel/ui/ref/ref_inputs.dart';
import 'package:system_panel/ui/ref/ref_onboard.dart';
import 'package:system_panel/widgets/chat_bar.dart';

/// G2.2「目标与输入没有护栏」的回归网。钉三件事：
///  ① 本地闸门：自伤 / 自杀类关键词命中就拦（不发 LLM），口语和同形词不误伤；
///  ② 提示词护栏：匹配 / 拆解 / 续拆 / set_plan 工具定义里都带着健康与安全条款，
///     违法 / 伤害他人的目标她拒拆时按 badGoal 抛（不是笼统的 noPlan）；
///  ③ 输入上限：目标 50 / 聊天 200，按已上屏字数算 —— 组字中的拼音不截断。
void main() {
  setUp(() => Sfx.enabled = false); // 测试环境没有音频插件

  // ═══════════════════════════════════════════════════════
  group('① 本地闸门 isCrisisGoal', () {
    test('明确的自伤 / 自杀表达 → 命中', () {
      for (final String s in <String>[
        '我不想活了',
        '不想活下去',
        '想自杀',
        '自 杀', // 中间夹空格
        '割腕',
        '我想死',
        '好想死啊。',
        '想死，好累',
        '活着没意思',
        '活着没有意义',
        '结束自己的生命',
        '一个月内了结自己',
        '三个月不再自残', // 戒自残也拦：该转介专业帮助，不该拆成任务
        '从楼上跳楼',
        'I want to kill myself',
        'thinking about suicide',
        'stop self-harm',
        'I want to die',
      ]) {
        expect(isCrisisGoal(s), isTrue, reason: s);
      }
    });

    test('口语夸张、同形词、正常目标 → 不误伤', () {
      for (final String s in <String>[
        '杀时间',
        '学会亲自杀鱼做饭',
        '独自伤心也要跑完半马',
        '暗自伤神不如去跑步',
        '双十一跳楼价囤够猫粮',
        '敢坐一次跳楼机',
        '跳楼梯训练 20 组',
        '看轻生死，先把书读完',
        '过上轻生活',
        '减轻生理期的痛',
        '一个月学会上吊环',
        '我想死磕英语',
        '想死记硬背四级单词',
        '好想死你了，周末回家',
        '看完自杀小队',
        '别再自杀式减肥',
        '学会心理危机里的自杀干预',
        '不想活成别人眼里的样子',
        '累死了也要坚持跑步',
        '笑死，三天背完单词',
        '别让熬夜害了自己',
        'upskill myself in Python',
        'kill time less',
        '一个月减 30 斤',
        ...kOnboardPresets,
      ]) {
        expect(isCrisisGoal(s), isFalse, reason: s);
      }
    });

    test('她那句：认真、不写热线号码、短到 320 宽三行放得下', () {
      expect(kCrisisCareLine, contains('信任的人'));
      expect(kCrisisCareLine, contains('专业'));
      expect(RegExp(r'\d').hasMatch(kCrisisCareLine), isFalse);
      expect(kCrisisCareLine.contains('['), isFalse); // 不带高亮
      expect(kCrisisCareLine.characters.length, lessThanOrEqualTo(34));
    });

    test('G4.2 聊天那句：同口吻、不写热线号码、不带高亮、不邀请接着聊', () {
      expect(kCrisisChatLine, startsWith(kCrisisCareLine));
      expect(RegExp(r'\d').hasMatch(kCrisisChatLine), isFalse);
      expect(kCrisisChatLine.contains('['), isFalse);
      expect(kCrisisChatLine.contains('接着说'), isFalse);
    });

    testWidgets('换目标页台词框（maxLines 3）两档屏宽都不截掉她那句', (WidgetTester tester) async {
      for (final Size s in <Size>[const Size(390, 844), const Size(320, 640)]) {
        tester.view.physicalSize = Size(s.width * 3, s.height * 3);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);
        final TextEditingController c = TextEditingController();
        addTearDown(c.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              backgroundColor: Ref.bg,
              body: Builder(
                builder: (BuildContext ctx) => MediaQuery(
                  // 减弱动态：打字机一次显形，直接量整句
                  data: MediaQuery.of(ctx).copyWith(disableAnimations: true),
                  child: RefGoalSwap(
                    goal: Goal.demo(),
                    controller: c,
                    presets: const <String>[],
                    line: kCrisisCareLine,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 1400));
        expect(tester.takeException(), isNull);
        final RenderParagraph p = tester.renderObject<RenderParagraph>(
          find.textContaining('我认真听到了', findRichText: true),
        );
        expect(p.didExceedMaxLines, isFalse, reason: '$s');
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  // ═══════════════════════════════════════════════════════
  group('② 提示词护栏', () {
    String says(String text) =>
        '{"choices":[{"message":{"content":${jsonEncode(text)}}}]}';

    http.Client scripted(List<String> bodies, List<String> responses) =>
        MockClient((http.Request req) async {
          bodies.add(req.body);
          return http.Response(
            responses.isEmpty ? says('（没了）') : responses.removeAt(0),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        });

    LlmClient clientOf(http.Client h) => LlmClient(
      config: const LlmConfig(apiKey: 'sk-test'),
      httpClient: h,
    );

    /// 一次请求里发出去的全部消息正文
    String sentText(String body) {
      final List<dynamic> msgs =
          (jsonDecode(body) as Map<String, dynamic>)['messages']
              as List<dynamic>;
      return msgs.map((dynamic m) => '${(m as Map)['content']}').join('\n');
    }

    test('条款本身：减重节奏 / 禁区 / 不拆的目标都在', () {
      expect(kMatchGuard, contains('每周最多减约 1 公斤（2 斤）'));
      expect(kMatchGuard, contains('违法'));
      expect(kMatchGuard, contains('伤害他人'));
      expect(kMatchGuard, contains(kRefuseMark));
      for (final String k in <String>[
        '每周最多减约 1 公斤（2 斤）',
        '先按安全的速度走',
        '断食',
        '催吐',
        '脱水',
        '极端热量缺口',
        '带伤',
        '违法',
        '伤害他人',
        kRefuseMark,
      ]) {
        expect(kPlanGuard, contains(k), reason: k);
      }
    });

    test('匹配：真正发出去的请求里带着护栏', () async {
      final List<String> bodies = <String>[];
      final GoalMatchDraft draft = GoalMatchDraft();
      final StrictAgentToolRegistry reg = StrictAgentToolRegistry()
        ..register(setGoalCategoryTool(goalText: '一个月减 30 斤', draft: draft));
      final GoalMatchAgent agent = GoalMatchAgent(
        client: clientOf(
          scripted(bodies, <String>[
            '{"choices":[{"message":{"content":"","tool_calls":[{"id":"c1",'
                '"type":"function","function":{"name":"set_goal_category",'
                '"arguments":${jsonEncode(jsonEncode(<String, dynamic>{'id': 'slim', 'short': '减重', 'days': 30, 'quota': 0}))}}}]}}]}',
          ]),
        ),
      );
      await agent.match(goalText: '一个月减 30 斤', tools: reg, draft: draft);
      expect(bodies, hasLength(1));
      expect(sentText(bodies.single), contains(kMatchGuard));
      expect(GoalMatchAgent.promptFor('x'), contains(kMatchGuard));
      // 工具定义里的期限说明也带着减重节奏
      final Map<String, dynamic> days =
          (setGoalCategorySchema()['properties']
                  as Map<String, dynamic>)['days']
              as Map<String, dynamic>;
      expect(days['description'], contains('每周最多减约 1 公斤'));
    });

    test('拆解：首段 / 分段 / 续拆的正文都带护栏；set_plan 定义也钉了禁区', () {
      final PlanWindow first = planWindowFor(total: 30, firstGoal: true);
      final PlanBrief b0 = PlanBrief(
        goalText: '一个月减 30 斤',
        days: 30,
        taskCount: first.size,
        cat: goalCats['slim']!,
        firstGoal: true,
        window: first,
      );
      expect(b0.userText, contains(kPlanGuard));
      // 窗口 14 > 段长 12 会切段并行拆：每段的正文同样带着
      for (final PlanSegment seg in planSegmentsFor(b0.win)) {
        expect(b0.forSegment(seg).userText, contains(kPlanGuard));
      }
      // 续拆下一段（QuestFlow.nextWindowHook → PlanBrief + progress）
      final PlanWindow next = planWindowFor(total: 30, planned: 14);
      final PlanBrief b1 = PlanBrief(
        goalText: '一个月减 30 斤',
        days: 30,
        taskCount: next.size,
        cat: goalCats['slim']!,
        window: next,
        progress: '已拆 14/30 张，完成 14 张。',
      );
      expect(b1.userText, contains(kPlanGuard));
      expect(b1.userText, contains('已拆 14/30 张'));

      final Map<String, dynamic> tasks =
          (setPlanSchema(14)['properties'] as Map<String, dynamic>)['tasks']
              as Map<String, dynamic>;
      expect(tasks['description'], contains(kPlanSchemaGuard));
      expect(kPlanSchemaGuard, contains('断食'));
      expect(kPlanSchemaGuard, contains('带伤硬练'));
    });

    test('拒拆标记：只认句首（情绪标签之后）', () {
      expect(refusalOf('〔不拆〕这是在报复别人。'), '这是在报复别人。');
      expect(refusalOf('[cold]〔不拆〕跟踪别人不是目标。'), '跟踪别人不是目标。');
      expect(refusalOf('〔不拆〕'), isNotEmpty);
      expect(refusalOf('规则里写了〔不拆〕的情况'), isNull);
      expect(refusalOf('[smug]两周十次，第一张压到 20 分钟。'), isNull);
    });

    test('匹配时她拒接 → badGoal（不是 noPlan），只发一次请求', () async {
      final List<String> bodies = <String>[];
      final GoalMatchDraft draft = GoalMatchDraft();
      final StrictAgentToolRegistry reg = StrictAgentToolRegistry()
        ..register(setGoalCategoryTool(goalText: '报复前任', draft: draft));
      final GoalMatchAgent agent = GoalMatchAgent(
        client: clientOf(
          scripted(bodies, <String>[says('[cold]〔不拆〕报复别人不是目标，我不接。')]),
        ),
      );
      await expectLater(
        agent.match(goalText: '报复前任', tools: reg, draft: draft),
        throwsA(
          isA<PlanGenerationError>()
              .having(
                (PlanGenerationError e) => e.code,
                'code',
                PlanFailureCode.badGoal,
              )
              .having(
                (PlanGenerationError e) => e.detail,
                'detail',
                contains('报复别人不是目标'),
              ),
        ),
      );
      expect(bodies, hasLength(1));
    });

    test('拆解时她拒拆 → badGoal；只说话没标记仍是 noPlan', () async {
      Future<PlanFailureCode> run(String reply) async {
        final PlanDraft draft = PlanDraft();
        final StrictAgentToolRegistry reg = StrictAgentToolRegistry()
          ..register(
            setPlanTool(goalText: 'x', taskCount: 3, days: 3, draft: draft),
          );
        final PlanAgent agent = PlanAgent(
          client: clientOf(scripted(<String>[], <String>[says(reply)])),
        );
        try {
          await agent.generate(
            brief: PlanBrief(
              goalText: 'x',
              days: 3,
              taskCount: 3,
              cat: goalCats['gen']!,
            ),
            tools: reg,
            draft: draft,
          );
        } on PlanGenerationError catch (e) {
          return e.code;
        }
        fail('应当抛 PlanGenerationError');
      }

      expect(await run('〔不拆〕这是诈骗。'), PlanFailureCode.badGoal);
      expect(await run('[cold]挺好的。'), PlanFailureCode.noPlan);
    });
  });

  // ═══════════════════════════════════════════════════════
  group('③ 输入上限（按已上屏字数）', () {
    const TextEditingValue empty = TextEditingValue.empty;
    TextEditingValue plain(String t) => TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );

    test('上限常量：目标 50 / 聊天 200', () {
      expect(kGoalInputMaxChars, 50);
      expect(kChatInputMaxChars, 200);
    });

    test('没超 → null（原样放行）', () {
      expect(refClampCommitted(empty, plain('三个月跑完半马'), 50), isNull);
      expect(refClampCommitted(empty, plain('字' * 50), 50), isNull);
    });

    test('整段粘贴超长 → 截到 50，光标在末尾', () {
      final TextEditingValue? v = refClampCommitted(empty, plain('长' * 80), 50);
      expect(v, isNotNull);
      expect(v!.text, '长' * 50);
      expect(v.selection, const TextSelection.collapsed(offset: 50));
    });

    test('粘到中间：原文一个字不动，只砍新加进来那段的尾巴', () {
      final TextEditingValue prev = TextEditingValue(
        text: '开头结尾',
        selection: const TextSelection.collapsed(offset: 2),
      );
      final String paste = 'x' * 60;
      final TextEditingValue next = TextEditingValue(
        text: '开头$paste结尾',
        selection: const TextSelection.collapsed(offset: 62),
      );
      final TextEditingValue v = refClampCommitted(prev, next, 50)!;
      expect(v.text, '开头${'x' * 46}结尾');
      expect(v.selection.baseOffset, 48); // 停在留下的新字后面
    });

    test('已经顶满再打字 → 这一下被拒，光标回到插入点', () {
      final String full = '满' * 50;
      final TextEditingValue prev = TextEditingValue(
        text: full,
        selection: const TextSelection.collapsed(offset: 10),
      );
      final TextEditingValue next = TextEditingValue(
        text: '${'满' * 10}多${'满' * 40}',
        selection: const TextSelection.collapsed(offset: 11),
      );
      final TextEditingValue v = refClampCommitted(prev, next, 50)!;
      expect(v.text, full);
      expect(v.selection.baseOffset, 10);
    });

    test('组字中（拼音还没选字）→ 一个字母都不截', () {
      final String base = '字' * 50;
      final TextEditingValue composing = TextEditingValue(
        text: '${base}nihao',
        selection: const TextSelection.collapsed(offset: 55),
        composing: const TextRange(start: 50, end: 55),
      );
      expect(refClampCommitted(plain(base), composing, 50), isNull);
      // 选完字（组字结束）那一下才按上限截
      final TextEditingValue committed = refClampCommitted(
        composing,
        plain('$base你好'),
        50,
      )!;
      expect(committed.text, base);
    });

    test('组字结束时只超一点：留下能放下的那几个新字', () {
      final String base = '字' * 49;
      final TextEditingValue composing = TextEditingValue(
        text: '${base}nihao',
        composing: const TextRange(start: 49, end: 54),
        selection: const TextSelection.collapsed(offset: 54),
      );
      final TextEditingValue v = refClampCommitted(
        composing,
        plain('$base你好'),
        50,
      )!;
      expect(v.text, '$base你');
    });

    test('按字素簇数：emoji 算 1 个', () {
      expect(refClampCommitted(empty, plain('👍🏻' * 50), 50), isNull);
      final TextEditingValue v = refClampCommitted(
        empty,
        plain('👍🏻' * 51),
        50,
      )!;
      expect(v.text.characters.length, 50);
    });

    testWidgets('RefTextField：超长粘贴截断 + 轻提示，到点自己收', (WidgetTester tester) async {
      final TextEditingController c = TextEditingController();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Ref.bg,
            body: Center(
              child: RefTextField(controller: c, maxChars: kGoalInputMaxChars),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '长' * 80);
      await tester.pump();
      expect(c.text, '长' * 50);
      expect(find.byKey(const Key('ref.input.clipHint')), findsOneWidget);
      expect(find.text('已截到 50 字'), findsOneWidget);
      await tester.pump(kRefClipHintHold + const Duration(milliseconds: 50));
      expect(find.byKey(const Key('ref.input.clipHint')), findsNothing);
      // 没超就不提示
      await tester.enterText(find.byType(TextField), '三个月跑完半马');
      await tester.pump();
      expect(find.byKey(const Key('ref.input.clipHint')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('RefTextField 不给 maxChars：照旧不限（LLM 设置页的 Key / 地址）', (
      WidgetTester tester,
    ) async {
      final TextEditingController c = TextEditingController();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RefTextField(controller: c)),
        ),
      );
      await tester.enterText(find.byType(TextField), 'k' * 300);
      await tester.pump();
      expect(c.text.length, 300);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('绑定页：字数显示「N/50」，组字中的拼音不计、不截', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final TextEditingController c = TextEditingController();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Ref.bg,
            body: Builder(
              builder: (BuildContext ctx) => MediaQuery(
                // 键盘弹起：字数条吸在键盘上沿（B3）
                data: MediaQuery.of(ctx)
                    .copyWith(viewInsets: const EdgeInsets.only(bottom: 300)),
                child: RefOnboard(
                  controller: c,
                  probe: '说吧。',
                  presets: const <String>[],
                  onSubmit: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('0/50'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '三个月跑完半马');
      await tester.pump();
      expect(find.text('7/50'), findsOneWidget);
      expect(find.text('7 字'), findsNothing);

      // 顶满 50 个字后再打拼音：拼音留着（不截），字数仍是 50/50
      final String base = '字' * 50;
      await tester.enterText(find.byType(TextField), base);
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '${base}ni',
          selection: const TextSelection.collapsed(offset: 52),
          composing: const TextRange(start: 50, end: 52),
        ),
      );
      await tester.pump();
      expect(c.text, '${base}ni');
      expect(find.text('50/50'), findsOneWidget);
      // 选字上屏 → 超出的那个字被截掉
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '$base你',
          selection: const TextSelection.collapsed(offset: 51),
        ),
      );
      await tester.pump();
      expect(c.text, base);
      expect(find.byKey(const Key('ref.input.clipHint')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('换目标页：输入框同样 50 字封顶', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final TextEditingController c = TextEditingController();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Ref.bg,
            body: RefGoalSwap(
              goal: Goal.demo(),
              controller: c,
              presets: const <String>[],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1400));
      await tester.enterText(find.byKey(const Key('ref.swap.input')), '目' * 70);
      await tester.pump();
      expect(c.text, '目' * 50);
      expect(find.byKey(const Key('ref.input.clipHint')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('聊天输入：200 字封顶 + 轻提示；组字中不截拼音', (WidgetTester tester) async {
      final TextEditingController c = TextEditingController();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ChatBar(controller: c, onSend: (_) {}),
            ),
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('chat.input')), '聊' * 300);
      await tester.pump();
      expect(c.text, '聊' * 200);
      expect(find.byKey(const Key('chat.input.clipHint')), findsOneWidget);
      await tester.pump(kRefClipHintHold + const Duration(milliseconds: 50));
      expect(find.byKey(const Key('chat.input.clipHint')), findsNothing);

      final String base = 'a' * 199;
      await tester.enterText(find.byKey(const Key('chat.input')), base);
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '${base}nihao',
          selection: const TextSelection.collapsed(offset: 204),
          composing: const TextRange(start: 199, end: 204),
        ),
      );
      await tester.pump();
      expect(c.text, '${base}nihao'); // 组字中：拼音一个字母都不动
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '$base你好',
          selection: const TextSelection.collapsed(offset: 201),
        ),
      );
      await tester.pump();
      expect(c.text, '$base你'); // 上屏后按 200 截，留下放得下的那个字
      await tester.pumpWidget(const SizedBox());
    });
  });
}
