import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:system_panel/data/attrs.dart';
import 'package:system_panel/data/rarity.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/goal_gen.dart';
import 'package:system_panel/state/plan_failure.dart';
import 'package:system_panel/agent/mainline_tool.dart';
import 'package:system_panel/state/host_state.dart';
import 'package:system_panel/state/save_file.dart';

/// ═══════════════════════════════════════════════════════════
///  目标生成（goal_gen.dart）—— 类型识别 · 访谈卡组 · 首目标 3 天 3 张
///  · 答案三用 · 老存档兼容（docs/18 第 2.1 节 / §2.8，T6-1）
///  · docs/33：环（Ring）已废除 —— `rings`→`plan`、`GoalRing`→`PlanTask`、
///    环数→期限天数（`goalDaysFor`）、`currentIndex`→`firstOpenIndex`
/// ═══════════════════════════════════════════════════════════
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 批二（TODO-03 模板半批）**新增**的题面 —— 这些必须逐条落在池子里
  /// （老池里的 51 条是原型真源，不在这张表内）。
  const List<String> kNewPoolTitles = <String>[
    // 通用池新增 16 条
    '早起后喝一杯水，再做 10 个开合跳',
    '把手机放到够不着的地方，专注 25 分钟',
    '走楼梯不坐电梯，上下各两趟',
    '写三行今天想说的话，写完就合上',
    '洗一次碗，顺便把台面擦干净',
    '靠墙静蹲 3 组，每组 45 秒',
    '把明天的三件事写下来，只写三件',
    '念一段 3 分钟的文字，念出声',
    '整理一次手机相册，删掉 30 张废片',
    '靠墙站直 10 分钟，别塌肩',
    '喝水 6 杯，拿杯子凑数不算',
    '把昨天没做完的那件事补完',
    '快走 20 分钟，不许边刷手机边走',
    '手写一页字，慢一点，写整齐',
    '今天不喝含糖饮料，一杯都不',
    '睡前 10 分钟回顾今天，想清楚一件做对的事',
    // 各类专属池新增（抽查）
    '跑前热身 8 分钟，一个动作都别省',
    '匀速跑 3 公里，配速别忽快忽慢',
    '深蹲 3 组 × 20，练腿不练腿跑不远',
    '走满 6000 步，就当放松跑',
    '晚饭后站 15 分钟，别一吃完就坐下',
    '把今天吃的东西拍下来，一顿都别漏',
    '睡前不吃东西，渴了只喝水',
    '深蹲 3 组 × 15，膝盖别内扣',
    '平板支撑 3 组 × 45 秒',
    '练完拉伸 10 分钟，明天才起得来',
    '背 15 个新词，晚上再过一遍',
    '听一段 3 分钟音频，听不懂也听完',
    '大声朗读一段短文，读顺为止',
    '清空书桌，只留下今天要用的那本书',
    '把最近 5 道错题重做一遍',
    '限时 25 分钟专注，手机扣在桌上',
    '手机放到够不着的地方充电，一晚上别碰',
    '午睡不超过 30 分钟',
    '临摹一张你喜欢的图，10 分钟就够',
    '写 200 字，写完不回头改',
    '读 20 分钟官方文档，读不懂也读完一节',
    '重构一个函数，只改一处也行',
    '抬头挺胸走 10 分钟，别低头看手机',
    '对着镜子练 3 分钟的开场白',
    '为今天定一个 15 分钟的小目标，做完就算赢',
    '丢掉一件早该丢的东西',
    '出门走 20 分钟，不带耳机',
    '写下一件今天做得还行的事，一句就够',
  ];

  /// 全池题面（通用 + 十类专属）—— 新题必须在里面
  final Set<String> seenPools = <String>{
    for (final DailyTemplate d in kDailyCommon) d.title,
    for (final GoalCategory c in kGoalCatOrder)
      for (final DailyTemplate d in c.daily) d.title,
  };

  /// 每个用例一块干净的内存存储（同 save_file_test 的做法）
  void resetStore([Map<String, Object> seed = const <String, Object>{}]) {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(Map<String, Object>.from(seed));
  }

  setUp(resetStore);

  // ═══════════════════════════════════════════════════════════
  //  2026-10-23：类别识别（detectCategory / 关键词正则表）与天幕短字
  //  （shortOfGoal / 剥前缀规则）**已删除** —— 它们改由 Agent 调
  //  `set_goal_category` 决定（见 plan_agent_test.dart 的匹配用例）。
  //  这里只留**规则**侧：空泛判定（输入侧前置校验）与访谈卡组。
  // ═══════════════════════════════════════════════════════════

  group('类别表（十类，供 Agent 选择；不再自带关键词/模板）', () {
    test('十类 id 齐全且顺序固定（schema 的 enum 就取这个顺序）', () {
      expect(
        <String>[for (final GoalCategory c in kGoalCatOrder) c.id],
        <String>[
          'run', 'slim', 'fit', 'lang', 'exam',
          'sleep', 'make', 'code', 'bold', 'gen',
        ],
      );
      expect(goalCats.length, 10);
      expect(goalCategoryIds, <String>[
        for (final GoalCategory c in kGoalCatOrder) c.id,
      ]);
    });

    test('每类都有六维倾向与 3 张专属访谈卡（拆解要靠它们定位内容）', () {
      for (final GoalCategory cat in kGoalCatOrder) {
        expect(cat.tilt, isNotEmpty, reason: cat.id);
        expect(cat.cards.length, 3, reason: cat.id);
        expect(cat.label.trim(), isNotEmpty, reason: cat.id);
      }
    });
  });

  group('空泛判定（原型 VAGUE，追问到具体为止）', () {
    test('黑名单整句命中', () {
      expect(isVagueGoal('变优秀'), isTrue);
      expect(isVagueGoal('变强'), isTrue);
      expect(isVagueGoal('加油！'), isTrue); // 标点剥掉后 = 加油
      expect(isVagueGoal('好好学习'), isTrue);
    });

    test('剥标点后不足 2 字也算空泛', () {
      expect(isVagueGoal('学'), isTrue);
    });

    test('具体目标不拦（含本次事故的骑行目标）', () {
      expect(isVagueGoal('三个月跑完半马'), isFalse);
      expect(isVagueGoal('一个月早睡早起'), isFalse);
      expect(isVagueGoal('两周内骑自行车10次'), isFalse);
    });
  });

  group('访谈卡组 3~5 张（依据等级设定合适内容）', () {
    test('新宿主 lv1 = 类别 3 张（docs/18 第 2.1 节 示例形态）', () {
      final List<InterviewCard> cards = interviewCardsFor(
        goalCats['sleep']!,
      );
      expect(cards.length, 3);
      expect(cards.map((InterviewCard c) => c.id), <String>[
        'sleep.schedule',
        'sleep.recent',
        'sleep.persist',
      ]);
      expect(cards[0].question, '现在几点起、几点睡？');
      expect(cards[0].options, contains('1-2 点睡 9 点后起'));
    });

    test('lv2~3 追加投入时段，lv4+ 再追加复盘卡', () {
      expect(interviewCardsFor(goalCats['sleep']!, level: 3).length, 4);
      final List<InterviewCard> five = interviewCardsFor(
        goalCats['sleep']!,
        level: 5,
      );
      expect(five.length, 5);
      expect(five.last.id, 'common.history');
      expect(five[3].id, 'common.slot');
    });

    test('全表逐类：卡数 3、每卡 3~4 个选项、id 唯一', () {
      for (final GoalCategory cat in kGoalCatOrder) {
        expect(cat.cards.length, 3, reason: '${cat.id} 应有 3 张专属卡');
        final Set<String> ids = <String>{};
        for (final InterviewCard c in interviewCardsFor(cat, level: 9)) {
          expect(c.options.length, inInclusiveRange(3, 4), reason: c.id);
          ids.add(c.id);
        }
        expect(ids.length, 5, reason: '${cat.id} 的卡 id 应唯一');
      }
    });
  });
  // ═══════════════════════════════════════════════════════════
  //  2026-10-23 重写：类别模板 / 关键词识别全部删除
  //
  //  旧的这几组（首目标模板、shortOfGoal、goalDaysFor、completionDayBoost、
  //  「十类 × 3 种时长词穷举」）测的都是**已删除的兜底路径**：
  //    · 类别/短字/期限 → GoalMatchAgent 调 set_goal_category（LLM）
  //    · 拆解内容       → PlanAgent 调 set_plan（LLM）
  //  本文件现在只测**留下来的规则**：条数、档位、时限、校验、六维、存档。
  // ═══════════════════════════════════════════════════════════

  /// 造一批合规任务（首目标：3 张 E/D/C）
  List<TaskSpec> firstTasks() => const <TaskSpec>[
    TaskSpec(short: '定闹钟', title: '定好明早的闹钟', proof: '闹钟截图', minutes: 5, rank: 'E'),
    TaskSpec(short: '23:30', title: '今晚 23:30 前上床', proof: '屏幕使用时间截图', minutes: 20, rank: 'D'),
    TaskSpec(short: '不赖床', title: '闹钟响后 5 分钟内起床', proof: '起床时间截图', minutes: 10, rank: 'C'),
  ];

  /// 造一批合规任务（长计划：n 张，低开高走，末张 S 级兑现单）
  List<TaskSpec> longTasks(int n) => <TaskSpec>[
    for (int i = 0; i < n; i++)
      TaskSpec(
        short: '第${i + 1}张',
        title: '第 ${i + 1} 张的具体动作',
        proof: '截图',
        minutes: i == n - 1 ? 120 : 20,
        rank: i == n - 1
            ? 'S'
            : kFirstGoalRanks[(i * 3 ~/ (n - 1)).clamp(0, 2)],
      ),
  ];

  group('计划规则 · 条数 = 次数配额 或 期限天数（docs/34 第 3 节）', () {
    test('planTaskCountFor 夹在 [kPlanMinTasks, kPlanMaxTasks]', () {
      expect(planTaskCountFor(14), 14);
      expect(planTaskCountFor(180), 180);
      expect(planTaskCountFor(1), kPlanMinTasks);
      expect(planTaskCountFor(10000), kPlanMaxTasks);
    });

    test('⚠️ 真机事故回归：次数配额压过期限天数', () {
      // 「两周内骑自行车 10 次」= 14 天 + 10 次 → 清单 10 张，不是 14 张。
      // 旧口径（条数 = 天数）铸出 14 张「第 N 次骑行」，末张还写
      // 「第14次骑满120分钟并交全部10次轨迹」—— 自相矛盾。
      expect(planTaskCountFor(14, quota: 10), 10);
      expect(planTaskCountFor(14, quota: 0), 14, reason: '没写次数就按天数');
      expect(planTaskCountFor(180, quota: 3), 3);
      expect(planTaskCountFor(7, quota: 10000), kPlanMaxTasks);
    });

    test('validatePlan 也按配额算条数', () {
      expect(
        () => validatePlan(days: 14, quota: 10, tasks: longTasks(10)),
        returnsNormally,
      );
      // 14 张对「14 天 + 10 次」反而**不合规**（多出来的 4 张会让题面重复）
      expect(
        () => validatePlan(days: 14, quota: 10, tasks: longTasks(14)),
        throwsA(isA<PlanRuleError>()),
      );
      expect(
        () => validatePlan(days: 14, tasks: longTasks(14)),
        returnsNormally,
        reason: '不给配额时仍旧按天数',
      );
    });

    test('档位时限上限单调递增（F~S 全表覆盖）', () {
      int prev = 0;
      for (final String r in Rarity.ranks) {
        final int cap = rankCapMinutes(r);
        expect(cap, greaterThanOrEqualTo(prev), reason: r);
        prev = cap;
      }
      expect(rankCapMinutes('S'), 180);
      expect(rankCapMinutes('E'), 30);
    });
  });

  group('计划规则 · validatePlan **fail fast**', () {
    test('合规清单通过（首目标 / 长计划两条路）', () {
      validatePlan(days: 3, tasks: firstTasks(), firstGoal: true);
      expect(() => validatePlan(days: 14, tasks: longTasks(14)), returnsNormally);
    });

    test('条数不对 → PlanRuleError（不补齐、不截断）', () {
      expect(
        () => validatePlan(days: 14, tasks: longTasks(13)),
        throwsA(isA<PlanRuleError>()),
      );
      expect(
        () => validatePlan(days: 3, tasks: longTasks(4), firstGoal: true),
        throwsA(isA<PlanRuleError>()),
      );
    });

    test('字段空 / 档位非法 / 时限越界 → PlanRuleError', () {
      final List<TaskSpec> blank = <TaskSpec>[...firstTasks()];
      blank[1] = const TaskSpec(
        short: 'x',
        title: '   ',
        proof: '截图',
        minutes: 20,
        rank: 'D',
      );
      expect(
        () => validatePlan(days: 3, tasks: blank, firstGoal: true),
        throwsA(isA<PlanRuleError>()),
      );

      final List<TaskSpec> badRank = <TaskSpec>[...firstTasks()];
      badRank[2] = const TaskSpec(
        short: 'x',
        title: 'y',
        proof: 'z',
        minutes: 10,
        rank: 'Z',
      );
      expect(
        () => validatePlan(days: 3, tasks: badRank, firstGoal: true),
        throwsA(isA<PlanRuleError>()),
      );

      // E 档上限 30 分钟，给 31 就不行
      final List<TaskSpec> tooLong = <TaskSpec>[...firstTasks()];
      tooLong[0] = const TaskSpec(
        short: 'x',
        title: 'y',
        proof: 'z',
        minutes: 31,
        rank: 'E',
      );
      expect(
        () => validatePlan(days: 3, tasks: tooLong, firstGoal: true),
        throwsA(isA<PlanRuleError>()),
      );
    });

    test('档位倒退 → PlanRuleError（低开高走是全链约束）', () {
      // E → E → C 不算倒退
      final List<TaskSpec> flat = <TaskSpec>[
        const TaskSpec(short: 'a', title: 'b', proof: 'c', minutes: 20, rank: 'E'),
        const TaskSpec(short: 'a', title: 'b', proof: 'c', minutes: 20, rank: 'E'),
        const TaskSpec(short: 'a', title: 'b', proof: 'c', minutes: 20, rank: 'C'),
      ];
      expect(
        () => validatePlan(days: 3, tasks: flat, firstGoal: true),
        returnsNormally,
      );
      // D → E 是倒退
      final List<TaskSpec> back = <TaskSpec>[
        const TaskSpec(short: 'a', title: 'b', proof: 'c', minutes: 20, rank: 'D'),
        const TaskSpec(short: 'a', title: 'b', proof: 'c', minutes: 20, rank: 'E'),
        const TaskSpec(short: 'a', title: 'b', proof: 'c', minutes: 20, rank: 'C'),
      ];
      expect(
        () => validatePlan(days: 3, tasks: back, firstGoal: true),
        throwsA(isA<PlanRuleError>()),
      );
    });

    test('首目标只许 E/D/C、期限必须是 3 天', () {
      final List<TaskSpec> tooHard = <TaskSpec>[...firstTasks()];
      tooHard[2] = const TaskSpec(
        short: 'x',
        title: 'y',
        proof: 'z',
        minutes: 10,
        rank: 'B',
      );
      expect(
        () => validatePlan(days: 3, tasks: tooHard, firstGoal: true),
        throwsA(isA<PlanRuleError>()),
      );
      expect(
        () => validatePlan(days: 14, tasks: longTasks(14), firstGoal: true),
        throwsA(isA<PlanRuleError>()),
      );
    });

    test('非首目标的末张必须是 S 级兑现单', () {
      final List<TaskSpec> weakTail = longTasks(5);
      weakTail[4] = const TaskSpec(
        short: 'x',
        title: 'y',
        proof: 'z',
        minutes: 30,
        rank: 'C',
      );
      expect(
        () => validatePlan(days: 5, tasks: weakTail),
        throwsA(isA<PlanRuleError>()),
      );
    });

    test('⚠️ 真机事故回归：兑现单**不限**最低 120 分钟，只限 S 档上限', () {
      // 「两周骑 10 次」的收尾是「交全部 10 次轨迹」——一次轻验证。
      // 旧规则硬要求 ≥120 分钟，把它判成不合规 → 整个目标建不出来。
      final List<TaskSpec> lightTail = longTasks(5);
      lightTail[4] = const TaskSpec(
        short: '交轨迹',
        title: '交全部 10 次骑行轨迹',
        proof: '10次轨迹汇总图',
        minutes: 10,
        rank: 'S',
      );
      expect(
        () => validatePlan(days: 5, tasks: lightTail),
        returnsNormally,
        reason: '轻量的兑现动作是合法的',
      );
      // 但超 S 档上限（180）仍然要抛
      final List<TaskSpec> hugeTail = longTasks(5);
      hugeTail[4] = const TaskSpec(
        short: 'x',
        title: 'y',
        proof: 'z',
        minutes: 200,
        rank: 'S',
      );
      expect(
        () => validatePlan(days: 5, tasks: hugeTail),
        throwsA(isA<PlanRuleError>()),
      );
    });
  });

  group('铸计划 buildGoalFromPlan（唯一入口，不兜底）', () {
    test('首目标：3 天 3 张 E/D/C，末张不算兑现门', () {
      final Goal g = buildGoalFromPlan(
        text: '一个月早睡早起',
        short: '早起',
        cat: goalCats['sleep']!,
        days: 3,
        tasks: firstTasks(),
        answers: const <String, String>{'sleep.schedule': '0-1 点睡 8 点起'},
        firstGoal: true,
        at: DateTime(2026, 1, 1),
      );
      expect(g.days, 3);
      expect(g.cat, 'sleep');
      expect(g.short, '早起');
      expect(g.plan.length, 3);
      expect(g.plan.map((PlanTask t) => t.rank).toList(), <String>['E', 'D', 'C']);
      expect(g.plan.every((PlanTask t) => t.finalTask), isFalse);
      expect(g.firstOpenIndex, 0);
      expect(g.interview['sleep.schedule'], '0-1 点睡 8 点起');
    });

    test('长计划：条数 = 期限、末张 finalTask、六维按类别倾向分', () {
      final Goal g = buildGoalFromPlan(
        text: '两周内骑自行车10次',
        short: '骑自行车',
        cat: goalCats['gen']!,
        days: 14,
        tasks: longTasks(14),
        at: DateTime(2026, 1, 1),
      );
      expect(g.plan.length, 14);
      expect(g.plan.last.finalTask, isTrue);
      expect(g.plan.take(13).every((PlanTask t) => !t.finalTask), isTrue);
      expect(g.plan.last.rank, 'S');
      for (final PlanTask t in g.plan) {
        expect(t.attrs, isNotEmpty, reason: t.short);
        expect(
          t.attrs.keys.every((String k) => Attr.names.containsKey(k)),
          isTrue,
          reason: '${t.short} 出现非六维 key',
        );
        expect(
          t.attrs.values.fold<int>(0, (int s, int v) => s + v),
          Rarity.of(t.rank).pt,
          reason: '${t.short} 六维点数不等于 ${t.rank} 档点数',
        );
      }
    });

    test('空目标文本 → 抛（不铸空计划）', () {
      expect(
        () => buildGoalFromPlan(
          text: '   ',
          short: 'x',
          cat: goalCats['gen']!,
          days: 3,
          tasks: firstTasks(),
          firstGoal: true,
        ),
        throwsA(isA<PlanRuleError>()),
      );
    });

    test('⚠️ 模板已删除：类别不再自带 firstTasks/lightTask', () {
      for (final GoalCategory cat in kGoalCatOrder) {
        expect(cat.daily, isNotEmpty, reason: '${cat.id} 的日常池不该为空');
        expect(cat.cards.length, 3, reason: cat.id);
      }
    });
  });

  group('答案三用 · ② 日常池（与目标拆解无关的产品内容）', () {
    test('目标类型专属池在前、通用池补位', () {
      final List<DailyTemplate> pool = dailyPoolFor('sleep');
      expect(pool.length, goalCats['sleep']!.daily.length + kDailyCommon.length);
      expect(pool.first.title, '睡前 30 分钟不碰手机');
      expect(pool[goalCats['sleep']!.daily.length].title, kDailyCommon.first.title);
    });

    test('gen 池 = 兜底专属池 + 通用池；未知类型兜底到 gen', () {
      expect(
        dailyPoolFor('gen').length,
        goalCats['gen']!.daily.length + kDailyCommon.length,
      );
      expect(dailyPoolFor('gen').length, greaterThanOrEqualTo(38));
      expect(dailyPoolFor('不存在的类型'), dailyPoolFor('gen'));
    });
  });

  group('内容池扩充（TODO-03 模板半批：重样期后移）', () {
    test('通用池 ≥30 条（原型 14 条 → 批二 30 条）', () {
      expect(kDailyCommon.length, greaterThanOrEqualTo(30));
    });

    test('十类专属池各自 ≥8 条', () {
      for (final GoalCategory cat in kGoalCatOrder) {
        expect(
          cat.daily.length,
          greaterThanOrEqualTo(8),
          reason: '${cat.id} 专属池只有 ${cat.daily.length} 条',
        );
      }
    });

    test('新增池内容合规：题面非空不重样、时限 5~180、档位在 F~S', () {
      for (final String t in kNewPoolTitles) {
        expect(seenPools, contains(t), reason: '批二新题不在任何池子里：$t');
      }
      expect(
        kNewPoolTitles.toSet().length,
        kNewPoolTitles.length,
        reason: '批二新题自己重样了',
      );
      for (final DailyTemplate d in <DailyTemplate>[
        ...kDailyCommon,
        for (final GoalCategory c in kGoalCatOrder) ...c.daily,
      ]) {
        expect(d.title.trim(), isNotEmpty);
        expect(d.proof.trim(), isNotEmpty, reason: d.title);
        expect(d.minutes, inInclusiveRange(5, 180), reason: d.title);
        expect(Rarity.ranks, contains(d.rank), reason: d.title);
        expect(d.attrs, isNotEmpty, reason: d.title);
        expect(
          d.attrs.keys.every((String k) => Attr.names.containsKey(k)),
          isTrue,
          reason: '${d.title} 出现非六维 key',
        );
      }
    });

    test('14 天无全同日（连续 14 个换日不出现「一整天完全相同」）', () {
      final math.Random rnd = math.Random(20261009);
      final List<List<String>> days = <List<String>>[];
      for (int day = 0; day < 14; day++) {
        final List<DailyTemplate> picks = pickDailies(
          candidates: genDailyCandidates(catId: 'gen', rnd: rnd),
          attrs: const <String, int>{'体': 1, '智': 2, '知': 1},
          goalCatId: 'gen',
          n: 2,
          rnd: rnd,
        );
        expect(picks, isNotEmpty, reason: '第 $day 天没挑出单子');
        days.add(picks.map((DailyTemplate d) => d.title).toList());
      }
      for (int i = 1; i < days.length; i++) {
        expect(days[i], isNot(equals(days[i - 1])), reason: '第 $i 天与前一天重样');
      }
      for (int i = 0; i < days.length; i++) {
        for (int j = i + 1; j < days.length; j++) {
          expect(
            <String>[...days[i]]..sort(),
            isNot(equals(<String>[...days[j]]..sort())),
            reason: '第 $i 天与第 $j 天整套重样',
          );
        }
      }
      final Set<String> used = <String>{for (final List<String> d in days) ...d};
      expect(used.length, greaterThanOrEqualTo(20));
    });
  });

  group('答案三用 · ③ 记忆导出（T5 的第一批条目）', () {
    test('目标一句 + 逐卡问答，跳过未答的卡', () {
      final List<String> mem = memoriesFromInterview(
        cat: goalCats['sleep']!,
        answers: const <String, String>{
          'sleep.schedule': '1-2 点睡 9 点后起',
          'sleep.recent': '天天熬夜',
          // sleep.persist 未答 → 跳过
        },
        goalText: '一个月早睡早起',
      );
      expect(mem.length, 3);
      expect(mem.first, contains('一个月早睡早起'));
      expect(mem.first, contains('3 天'));
      expect(mem[1], contains('现在几点起、几点睡？'));
      expect(mem[1], contains('1-2 点睡 9 点后起'));
      expect(mem[2], contains('天天熬夜'));
    });

    test('期限可传（长计划的记忆不该写「首期 3 天」）', () {
      final List<String> mem = memoriesFromInterview(
        cat: goalCats['run']!,
        answers: const <String, String>{},
        goalText: '半年跑完半马',
        days: 180,
      );
      expect(mem.single, contains('180 天'));
    });
  });

  group('触发判定与老存档兼容（docs/18 第 2.8 节 合并式加法）', () {
    test('没有主线才要绑', () {
      expect(shouldOnboard(Goal.empty()), isTrue);
      expect(shouldOnboard(Goal.demo()), isFalse); // 老存档已有主线
      expect(
        shouldOnboard(
          buildGoalFromPlan(
            text: '考研上岸',
            short: '上岸',
            cat: goalCats['exam']!,
            days: 3,
            tasks: firstTasks(),
            firstGoal: true,
          ),
        ),
        isFalse,
      );
    });

    test('老档缺新字段 → 合并出默认值，不触发绑定流', () {
      final Map<String, dynamic> raw =
          jsonDecode(
                '''
        {"text":"三个月跑完半马","short":"半马","at":"2026-10-01T08:00:00.000",
         "rings":[{"short":"穿上跑鞋","title":"换上跑鞋，出门快走 15 分钟","proof":"运动 App 记录或出门自拍","minutes":20,"rank":"F","state":"done"}]}
      ''',
              )
              as Map<String, dynamic>;
      final Goal g = Goal.fromJson(raw, fallback: Goal.empty());
      expect(g.cat, '');
      expect(g.days, 1);
      expect(g.interview, isEmpty);
      expect(g.text, '三个月跑完半马');
      expect(g.plan, isNotEmpty);
      expect(g.plan.first.state, PlanState.done);
      expect(shouldOnboard(g), isFalse);
    });

    test('goal 元数据 toJson/fromJson 往返一致', () {
      final Goal g = buildGoalFromPlan(
        text: '一个月早睡早起',
        short: '早起',
        cat: goalCats['sleep']!,
        days: 3,
        tasks: firstTasks(),
        answers: const <String, String>{'sleep.recent': '偶尔熬夜'},
        firstGoal: true,
      );
      final Goal back = Goal.fromJson(g.toJson(), fallback: Goal.empty());
      expect(back.cat, 'sleep');
      expect(back.days, 3);
      expect(back.interview['sleep.recent'], '偶尔熬夜');
      expect(back.plan.length, 3);
      expect(back.plan.first.state, PlanState.todo);
      expect(back.plan.map((PlanTask r) => r.index).toList(), <int>[0, 1, 2]);
    });

    test('存档整链：访谈答案持久化，重启（重新 load）仍在', () async {
      final Goal goal = buildGoalFromPlan(
        text: '一个月早睡早起',
        short: '早起',
        cat: goalCats['sleep']!,
        days: 3,
        tasks: firstTasks(),
        answers: const <String, String>{
          'sleep.schedule': '0 点前睡 7 点前起',
          'sleep.recent': '偶尔熬夜',
          'sleep.persist': '睡前不碰手机',
        },
        firstGoal: true,
      );
      await SaveFile().save(
        SaveData(host: HostState.empty.copyWith(name: '新宿主'), goal: goal),
      );
      final SaveData back = await SaveFile().load();
      expect(back.goal.days, 3);
      expect(back.goal.cat, 'sleep');
      expect(back.goal.interview.length, 3);
      expect(back.goal.interview['sleep.persist'], '睡前不碰手机');
      expect(back.goal.plan, isNotEmpty);
      expect(back.goal.plan.map((PlanTask r) => r.rank).toList(), <String>[
        'E',
        'D',
        'C',
      ]);
      expect(shouldOnboard(back.goal), isFalse);
    });
  });

  group('见面礼（原型 bind 的双倍卡语义保留）', () {
    test('空表送 1 张；已有则叠加；不改动传入表', () {
      expect(kBindGiftDbl, 1);
      expect(kBindGiftItemKey, 'dbl');
      expect(kBindGiftKicker, '见面礼');
      expect(kBindGiftText, '双倍卡 ×1');

      expect(applyBindGift(const <String, int>{}), <String, int>{'dbl': 1});

      final Map<String, int> src = <String, int>{'dbl': 1, 'crit': 2};
      final Map<String, int> out = applyBindGift(src);
      expect(out['dbl'], 2);
      expect(out['crit'], 2);
      expect(src['dbl'], 1);
    });
  });
}
