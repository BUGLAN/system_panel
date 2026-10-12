import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:system_panel/data/attrs.dart';
import 'package:system_panel/data/rarity.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/goal_gen.dart';
import 'package:system_panel/state/host_state.dart';
import 'package:system_panel/state/save_file.dart';

/// ═══════════════════════════════════════════════════════════
///  目标生成（goal_gen.dart）—— 类型识别 · 访谈卡组 · 首目标 3 天 3 张
///  · 答案三用 · 老存档兼容（docs/18 §2.1 / §2.8，T6-1）
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

  group('类型识别（CAT_ORDER 顺序短路，gen 兜底）', () {
    test('十类各认各的', () {
      expect(detectCategory('三个月跑完半马').id, 'run');
      expect(detectCategory('半年减重 10 斤').id, 'slim');
      expect(detectCategory('练出腹肌').id, 'fit');
      expect(detectCategory('每天背 50 个单词').id, 'lang');
      expect(detectCategory('考研上岸').id, 'exam');
      expect(detectCategory('一个月早睡早起').id, 'sleep');
      expect(detectCategory('学会画画').id, 'make');
      expect(detectCategory('做一个 App 上线').id, 'code');
      expect(detectCategory('提升自信敢当众说话').id, 'bold');
      expect(detectCategory('变优秀').id, 'gen');
    });

    test('大小写不敏感与顺序敏感', () {
      expect(detectCategory('5K 计划').id, 'run'); // km|5k 走 /i
      expect(detectCategory('刷题').id, 'exam'); // exam 排在 code 之前
      expect(detectCategory('N1 过线').id, 'lang');
    });

    test('谁都不中落 gen', () {
      expect(detectCategory('提高球技').id, 'gen');
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

    test('具体目标不拦', () {
      expect(isVagueGoal('三个月跑完半马'), isFalse);
      expect(isVagueGoal('一个月早睡早起'), isFalse);
    });
  });

  group('天幕短字 shortOfGoal（store.js 同表）', () {
    test('关键词表命中', () {
      final GoalCategory sleep = goalCats['sleep']!;
      expect(shortOfGoal('三个月跑完半马', sleep), '半马');
      expect(shortOfGoal('半年减重 10 斤', sleep), '−10斤');
      // 原型规则表 早起 在 早睡 之前 → 「一个月早睡早起」取「早起」（store.js 同序）
      expect(shortOfGoal('一个月早睡早起', sleep), '早起');
      expect(shortOfGoal('六级冲刺', sleep), '六级');
      expect(shortOfGoal('5公里跑进 25 分', sleep), '5K');
    });

    test('没命中走类别兜底 / gen 剥前缀取 4 字', () {
      expect(shortOfGoal('提高球技', goalCats['run']!), '奔跑');
      expect(shortOfGoal('变得靠谱一点', goalCats['gen']!), '变得靠谱');
      expect(shortOfGoal('我要变靠谱', goalCats['gen']!), '变靠谱');
      expect(shortOfGoal('。。。', goalCats['gen']!), '变强'); // 剥完为空兜底
    });
  });

  group('访谈卡组 3~5 张（依据等级设定合适内容）', () {
    test('新宿主 lv1 = 类别 3 张（docs/18 §2.1 示例形态）', () {
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

  group('首目标：3 天 3 张（E/D/C）', () {
    final GoalCategory sleep = goalCats['sleep']!;
    final Goal goal = buildFirstGoal(text: '一个月早睡早起', cat: sleep);

    test('周期与元数据', () {
      expect(goal.days, 3);
      expect(goal.cat, 'sleep');
      expect(goal.text, '一个月早睡早起');
      expect(goal.short, '早起'); // 原型 shortOf：早起 规则在 早睡 之前
      expect(goal.plan.length, 3);
      expect(kFirstGoalDays, 3);
    });

    test('档位 E/D/C、计划内序号与状态（顺序锁已废除，全部待开工）', () {
      expect(goal.plan.map((PlanTask r) => r.rank).toList(), <String>[
        'E',
        'D',
        'C',
      ]);
      // docs/33：没有 cur/lock 的「顺序锁」了 —— 清单里每张都从 todo 起步，
      // 「第几张在脚下」由 firstOpenIndex 推导。
      expect(
        goal.plan.map((PlanTask r) => r.state).toList(),
        <PlanState>[PlanState.todo, PlanState.todo, PlanState.todo],
      );
      expect(goal.firstOpenIndex, 0);
      expect(goal.doneCount, 0);
      expect(goal.plan.map((PlanTask r) => r.index).toList(), <int>[0, 1, 2]);
      expect(goal.plan[2].finalTask, isTrue);
      expect(goal.plan.first.finalTask, isFalse);
    });

    test('时限落在 docs/18 §2.3 建议档内（E≤15 / D≤20 / C≤30，下限 5）', () {
      expect(goal.plan[0].minutes, lessThanOrEqualTo(15));
      expect(goal.plan[1].minutes, lessThanOrEqualTo(20));
      expect(goal.plan[2].minutes, lessThanOrEqualTo(30));
      for (final PlanTask r in goal.plan) {
        expect(r.minutes, greaterThanOrEqualTo(5));
      }
    });

    test('答案随 Goal 入档，且不被外部改写波及', () {
      final Map<String, String> answers = <String, String>{
        'sleep.schedule': '0-1 点睡 8 点起',
      };
      final Goal g = buildFirstGoal(
        text: '一个月早睡早起',
        cat: sleep,
        answers: answers,
      );
      expect(g.interview['sleep.schedule'], '0-1 点睡 8 点起');
      answers['sleep.schedule'] = '被改掉了';
      expect(g.interview['sleep.schedule'], '0-1 点睡 8 点起');
    });

    test('负担重 → 第 1 张换「比昨天早睡 15 分钟」（docs/18 §2.1 示例）', () {
      final Goal heavy = buildFirstGoal(
        text: '一个月早睡早起',
        cat: sleep,
        answers: const <String, String>{
          'sleep.schedule': '1-2 点睡 9 点后起',
          'sleep.recent': '天天熬夜',
        },
      );
      expect(heavy.plan.first.title, '比昨天早睡 15 分钟');
      expect(heavy.plan.first.rank, 'E');
      // 其余张不受影响
      expect(heavy.plan[1].title, '今晚 23:30 前放下手机上床');

      final Goal unset = buildFirstGoal(
        text: '一个月早睡早起',
        cat: sleep,
        answers: const <String, String>{'sleep.schedule': '没有固定'},
      );
      expect(unset.plan.first.title, '比昨天早睡 15 分钟');

      final Goal light = buildFirstGoal(
        text: '一个月早睡早起',
        cat: sleep,
        answers: const <String, String>{'sleep.recent': '基本规律'},
      );
      expect(light.plan.first.title, '定好明早的闹钟，手机放到够不着的地方');
    });

    test('没有轻档张的类别不受「负担重」影响', () {
      final Goal g = buildFirstGoal(
        text: '三个月跑完半马',
        cat: goalCats['run']!,
        answers: const <String, String>{'run.now': '没跑过，天天熬夜'},
      );
      expect(g.plan.first.title, '换上跑鞋，出门快走 15 分钟');
      expect(g.days, 3);
    });

    test('十类都能铸出合规首目标', () {
      for (final GoalCategory cat in kGoalCatOrder) {
        final Goal g = buildFirstGoal(text: '随便一个${cat.label}目标', cat: cat);
        expect(g.plan.length, 3, reason: cat.id);
        expect(g.plan.map((PlanTask r) => r.rank), <String>['E', 'D', 'C']);
        expect(g.days, 3, reason: cat.id);
        expect(g.plan.last.finalTask, isTrue, reason: cat.id);
      }
    });
  });

  group('答案三用 · ② 日常池', () {
    test('目标类型专属池在前、通用池补位', () {
      final List<DailyTemplate> pool = dailyPoolFor('sleep');
      expect(pool.length, goalCats['sleep']!.daily.length + kDailyCommon.length);
      expect(pool.first.title, '睡前 30 分钟不碰手机');
      // 专属池与通用池边界：第 N 条之后就是通用池第一条
      expect(pool[goalCats['sleep']!.daily.length].title, kDailyCommon.first.title);
    });

    test('gen 池 = 兜底专属池 + 通用池；未知类型兜底到 gen', () {
      // gen 类自己也有专属池（批二起 ≥8 条：谁都不中的目标不能只靠通用池）
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
      // 只对**批二新增**的条目做「不重样」断言 —— 老池里
      // 「拉伸 10 分钟」（fit 专属 + 通用）本来就有跨池重复，
      // 那属于原型遗留，不是这批引入的问题（同日内仍由生成侧去重）。
      for (final String t in kNewPoolTitles) {
        expect(seenPools, contains(t), reason: '批二新题不在任何池子里：$t');
      }
      expect(
        kNewPoolTitles.toSet().length,
        kNewPoolTitles.length,
        reason: '批二新题自己重样了',
      );
      final Set<String> seen = <String>{};
      for (final String t in kNewPoolTitles) {
        expect(seen.add(t), isTrue, reason: '批二新题重复：$t');
      }
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

    test('新增的通用池条目确实在池子里（抽查几条批二新题）', () {
      final List<String> titles =
          kDailyCommon.map((DailyTemplate d) => d.title).toList();
      expect(titles, contains('早起后喝一杯水，再做 10 个开合跳'));
      expect(titles, contains('靠墙静蹲 3 组，每组 45 秒'));
      expect(titles, contains('睡前 10 分钟回顾今天，想清楚一件做对的事'));
    });

    test('14 天无全同日（连续 14 个换日不出现「一整天完全相同」）', () {
      // 每天走一遍「候选 4~6 → 挑 1~2」（docs/18 §2.2 的真实链路），
      // 随机源固定 → 这是可复现的简单校验，不是概率断言。
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
      // ① 相邻两天不得整套相同
      for (int i = 1; i < days.length; i++) {
        expect(days[i], isNot(equals(days[i - 1])), reason: '第 $i 天与前一天重样');
      }
      // ② 整个 14 天里不得出现「整套完全相同的两天」
      for (int i = 0; i < days.length; i++) {
        for (int j = i + 1; j < days.length; j++) {
          expect(
            <String>[...days[i]]..sort(),
            isNot(equals(<String>[...days[j]]..sort())),
            reason: '第 $i 天与第 $j 天整套重样',
          );
        }
      }
      // ③ 14 天里出现过的题面覆盖 ≥ 20 条（池子够深才有这个数）
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
  });

  group('触发判定与老存档兼容（docs/18 §2.8 合并式加法）', () {
    test('没有主线才要绑', () {
      expect(shouldOnboard(Goal.empty()), isTrue);
      expect(shouldOnboard(Goal.demo()), isFalse); // 老存档已有主线
      expect(shouldOnboard(buildFirstGoal(text: '考研上岸', cat: goalCats['exam']!)), isFalse);
    });

    test('老档缺新字段 → 合并出默认值，不触发绑定流', () {
      // 模拟旧版本存档的 goal：有环（已有主线），但没有 cat/days/interview 键
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
      // docs/33 迁移：老档的 `days` 存的是环数（5~8），当期限用是错的 ——
      // 缺 `days` 时按**清单条数**兜底（这条老档只有 1 张）。
      expect(g.days, 1);
      expect(g.interview, isEmpty);
      expect(g.text, '三个月跑完半马'); // 老字段照常读回
      expect(g.plan, isNotEmpty);
      expect(g.plan.first.state, PlanState.done); // 老 state 'done' 照常读回
      expect(shouldOnboard(g), isFalse); // 清单非空 = 已有主线 = 不触发
    });

    test('goal 元数据 toJson/fromJson 往返一致', () {
      final Goal g = buildFirstGoal(
        text: '一个月早睡早起',
        cat: goalCats['sleep']!,
        answers: const <String, String>{'sleep.recent': '偶尔熬夜'},
      );
      final Goal back = Goal.fromJson(g.toJson(), fallback: Goal.empty());
      expect(back.cat, 'sleep');
      expect(back.days, 3);
      expect(back.interview['sleep.recent'], '偶尔熬夜');
      expect(back.plan.length, 3);
      // 首目标刚铸出来还没开工 → 三张都是 todo，序号原样读回
      expect(back.plan.first.state, PlanState.todo);
      expect(back.plan.map((PlanTask r) => r.index).toList(), <int>[0, 1, 2]);
    });

    test('存档整链：访谈答案持久化，重启（重新 load）仍在', () async {
      final Goal goal = buildFirstGoal(
        text: '一个月早睡早起',
        cat: goalCats['sleep']!,
        answers: const <String, String>{
          'sleep.schedule': '0 点前睡 7 点前起',
          'sleep.recent': '偶尔熬夜',
          'sleep.persist': '睡前不碰手机',
        },
      );
      await SaveFile().save(
        SaveData(host: HostState.empty.copyWith(name: '新宿主'), goal: goal),
      );
      // 「重启」= 新的 SaveFile 实例重新读档
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

  group('第二目标闭环（TODO-01 + TODO-06 模板半）：finale → 下一条主线', () {
    /// 上一目标（走完 3 张的 sleep 首目标）
    Goal finishedFirst() {
      final Goal g = buildFirstGoal(
        text: '一个月早睡早起',
        cat: goalCats['sleep']!,
        answers: const <String, String>{'sleep.schedule': '0 点前睡 7 点前起'},
      );
      return g.copyWith(
        plan: <PlanTask>[
          for (final PlanTask r in g.plan)
            PlanTask(
              index: r.index,
              short: r.short,
              title: r.title,
              proof: r.proof,
              minutes: r.minutes,
              rank: r.rank,
              attrs: r.attrs,
              state: PlanState.done,
              finalTask: r.finalTask,
              held: const Duration(minutes: 12),
              doneAt: DateTime(2026, 1, 3),
            ),
        ],
      );
    }

    Goal next(Goal prev, {int? cleared, int? total, int level = 1, String? text}) =>
        buildNextGoal(
          prev: prev,
          cleared: cleared ?? prev.plan.length,
          total: total ?? prev.plan.length,
          level: level,
          text: text,
          // 镜像生产调用（main.dart 两处都传 `at: prev.at`，O-2 裁决）
          at: prev.at,
        );

    test('时长词 → 期限天数（+ 计划条数 == 天数）', () {
      // docs/33：`goalDaysFor` 返回的是**期限天数**，不再是环数。
      //   一年 365 / 半年 180 / N 个月 N×30 / 百天 100 / 八周 56
      //   / 一个月 30 / 两周 14 / 十天 10 / 一周 7 / 没命中 21
      // 计划条数 = 期限天数（夹在 [kPlanMinTasks, kPlanMaxTasks] 内）。
      const Map<String, int> cases = <String, int>{
        '三个月跑完半马': 90,
        '一个月早睡早起': 30,
        '半年减重 10 斤': 180,
        '一年读完 50 本书': 365,
        '100 天打卡': 100,
        '两个月练出腹肌': 60,
        '二个月冲一次': 60,
        '60 天早起': 21, // 没命中任何时长词 → 默认 21 天
        '八周跑完 10K': 56,
        '一周读完一本书': 7,
        '7 天早睡': 7,
        '两周背完 500 词': 14,
        '随便一个目标': 21,
      };
      cases.forEach((String text, int days) {
        expect(goalDaysFor(text), days, reason: text);
        expect(planTaskCountFor(days), days, reason: text);
      });
      // 条数两头封口（防呆；正常时长词够不到上限）
      expect(planTaskCountFor(1), kPlanMinTasks);
      expect(planTaskCountFor(10000), kPlanMaxTasks);
    });

    test('计划条数 == 期限天数，且末张是「兑现它」的 S 级兑现单', () {
      for (final GoalCategory cat in kGoalCatOrder) {
        final Goal g = next(
          buildFirstGoal(text: '随便一个${cat.label}目标', cat: cat),
          text: '半年${cat.label}进阶',
        );
        expect(g.days, 180, reason: cat.id); // 「半年」→ 180 天
        expect(g.plan.length, g.days, reason: cat.id);
        expect(
          g.plan.length,
          inInclusiveRange(kPlanMinTasks, kPlanMaxTasks),
          reason: cat.id,
        );
        // 新铸出来的清单还没开工：全部 todo，第一张就是脚下那张
        expect(
          g.plan.every((PlanTask r) => r.state == PlanState.todo),
          isTrue,
          reason: cat.id,
        );
        expect(g.firstOpenIndex, 0, reason: cat.id);
        expect(g.plan.last.finalTask, isTrue, reason: cat.id);
        expect(g.plan.last.rank, 'S', reason: cat.id);
        expect(g.plan.last.title, endsWith('——兑现它'), reason: cat.id);
        // 兑现单时限由规则收口：不低于 kPlanFinalMinutes、不超过 S 档上限
        expect(
          g.plan.last.minutes,
          greaterThanOrEqualTo(kPlanFinalMinutes),
          reason: cat.id,
        );
        expect(
          g.plan.last.minutes,
          lessThanOrEqualTo(rankCapMinutes('S')),
          reason: cat.id,
        );
        // 只有末张带 finalTask；中间张不越界
        expect(
          g.plan.where((PlanTask r) => r.finalTask).length,
          1,
          reason: cat.id,
        );
      }
    });

    test('档位低开高走：首张 E、含 S、末张 S，全部是合法档位', () {
      final Goal g = next(finishedFirst(), text: '半年减重 10 斤');
      expect(g.plan.first.rank, 'E');
      expect(g.plan.map((PlanTask r) => r.rank), contains('S'));
      expect(g.plan.last.rank, 'S');
      for (final PlanTask r in g.plan) {
        expect(Rarity.ranks, contains(r.rank));
      }
    });

    test('完成度提档：满额 + lv≥4 多 7 天；没满额不提档；条数封顶 400', () {
      final Goal prev = finishedFirst();
      expect(completionDayBoost(cleared: 3, total: 3, level: 3), 0);
      expect(completionDayBoost(cleared: 3, total: 3, level: 4), 7);
      expect(completionDayBoost(cleared: 2, total: 3, level: 9), 0);
      expect(completionDayBoost(cleared: 0, total: 0, level: 9), 0);

      // 上一句「一个月早睡早起」→ 30 天；提档只加天数（清单条数跟着走）
      final Goal low = next(prev, level: 3); // 30 天（lv<4 不提档）
      final Goal high = next(prev, level: 5); // 30 + 7 = 37 天
      expect(low.days, 30);
      expect(low.plan.length, 30);
      expect(high.days, 37);
      expect(high.plan.length, 37);
      // 换一句更长的：「一年」365 + 提档 7 = 372 天（仍在上限 400 之内）
      final Goal year = next(prev, level: 5, text: '一年读完 50 本书');
      expect(year.days, 372);
      expect(year.plan.length, 372);
    });

    test('沿用上一目标的文本/类型/访谈答案/立目标时刻（O-2 裁决：沿用）', () {
      final Goal prev = finishedFirst();
      final Goal g = next(prev);
      expect(g.text, prev.text);
      expect(g.cat, 'sleep');
      expect(g.short, prev.short);
      // O-2（宿主 2026-10-10 裁决）：立目标时刻**沿用**上一目标。
      // 生产 `main.dart` 两处调用（_wireFlow 收官钩子 / _onGoalChangeSubmitted
      // 主动换目标）都传 `at: prev.at`；本测试的 next() 镜像同一调用。
      // 历史：2026-10-10 之前两处都没传 at，这条断言于是只在两次
      // `DateTime.now()` 落在同一毫秒时才绿（验收人实测 ≈99% 绿 / ≈1% 红）。
      expect(g.at, prev.at);
      expect(g.interview['sleep.schedule'], '0 点前睡 7 点前起');
    });

    test('换了那句话：类型跟着新那句话走，访谈答案仍是宿主的', () {
      final Goal prev = finishedFirst();
      final Goal g = next(prev, text: '半年减重 10 斤');
      expect(g.text, '半年减重 10 斤');
      expect(g.cat, 'slim');
      expect(g.short, '−10斤');
      expect(g.days, 180);
      expect(g.plan.length, 180);
      expect(g.interview['sleep.schedule'], '0 点前睡 7 点前起');
    });

    test('加码段：时限落在档位上限内、题面不空、第一条加码比起步段更重', () {
      final Goal g = next(finishedFirst(), text: '半年减重 10 斤');
      final GoalCategory slim = goalCats['slim']!;
      final List<PlanTask> mids = g.plan.sublist(0, g.plan.length - 1);
      expect(mids.length, 179);
      // 前 3 张是类别自带的起步模板，第 4 张起才是按 1.35^k 加码的生成段
      final int firstBoost = slim.firstTasks.length;
      for (int i = firstBoost; i < mids.length; i++) {
        expect(mids[i].title.trim(), isNotEmpty);
        expect(mids[i].proof.trim(), isNotEmpty);
        expect(mids[i].minutes, inInclusiveRange(5, 180));
      }
      final int baseMax = mids
          .sublist(0, firstBoost)
          .map((PlanTask r) => r.minutes)
          .reduce((int a, int b) => a > b ? a : b);
      // ⚠️ 第一张加码任务可能**刚好等于**起步段最长那张：新档位上限表里
      //    E 档就是 30 分钟（`rankCapMinutes`），而起步段最长的模板正好 30，
      //    所以阶梯还没抬档之前 `到此为止最重 + 5` 会被上限压回去。
      //    真正要钉的是「加码段确实比起步段重」——整段的最大值必须超过它。
      final int boostMax = mids
          .sublist(firstBoost)
          .map((PlanTask r) => r.minutes)
          .reduce((int a, int b) => a > b ? a : b);
      expect(boostMax, greaterThan(baseMax));
    });

    test('⚠️ 整条链单调不减：档位与时长都不许倒退（2026-10-12 宿主存档回归）', () {
      // 真机存档实测到的坏链：… 加码3 = S · 41 分钟 → 加码4 = **E · 7 分钟**
      // → 兑现 = S · 120 分钟。档位与时长一起绕回，长链最后一段比开头还轻。
      // 根因：档位取 `i % kPlanRankSeq.length`、时长取 `seed × 1.35` 单级
      //（不参考上一张），8 环时正好绕回 'E'。
      //
      // 口径（docs/33 不变）：**档位**约束全链（起步张 E/D/C 本来就是升的）；
      //   **时长**只约束生成段（起步张是人工编排的模板，可以「核心」比
      //   「三组成型」短 —— 难度轴是档位，不是分钟数）。
      for (final GoalCategory cat in kGoalCatOrder) {
        final Goal prev = buildFirstGoal(text: '起步', cat: cat);
        for (final String t in <String>['一周试试', '两个月加码', '半年冲一次']) {
          final Goal g = next(prev, text: '${cat.label}·$t');
          final List<PlanTask> plan = g.plan;
          final int firstBoost = cat.firstTasks.length;

          // ① 档位全链不倒退
          for (int i = 1; i < plan.length; i++) {
            expect(
              Rarity.ranks.indexOf(plan[i].rank),
              greaterThanOrEqualTo(Rarity.ranks.indexOf(plan[i - 1].rank)),
              reason: '${cat.id}/$t 第 ${i + 1} 张档位倒退了：'
                  '${plan[i - 1].rank} → ${plan[i].rank}',
            );
          }

          // ② 生成段起，时长不倒退（这里才是绕回 bug 的现场）
          for (int i = firstBoost + 1; i < plan.length; i++) {
            expect(
              plan[i].minutes,
              greaterThanOrEqualTo(plan[i - 1].minutes),
              reason: '${cat.id}/$t 第 ${i + 1} 张时长倒退了：'
                  '${plan[i - 1].minutes} → ${plan[i].minutes} 分钟',
            );
          }

          // ③ 加码段确实比起步张重（第一张可能被档位上限压平，见上一条用例），
          //    且兑现单不轻于任何一张
          final int baseMax = plan
              .sublist(0, firstBoost)
              .map((PlanTask r) => r.minutes)
              .reduce((int a, int b) => a > b ? a : b);
          final int boostMax = plan
              .sublist(firstBoost, plan.length - 1)
              .map((PlanTask r) => r.minutes)
              .reduce((int a, int b) => a > b ? a : b);
          expect(
            boostMax,
            greaterThan(baseMax),
            reason: '${cat.id}/$t 加码段没比起步张更重',
          );
          final int midMax = plan
              .sublist(0, plan.length - 1)
              .map((PlanTask r) => r.minutes)
              .reduce((int a, int b) => a > b ? a : b);
          expect(
            plan.last.minutes,
            greaterThanOrEqualTo(midMax),
            reason: '${cat.id}/$t 兑现单比前面的任务还轻',
          );
          expect(plan.last.finalTask, isTrue, reason: '${cat.id}/$t 末张不是兑现单');
        }
      }
    });

    test('十类 × 3 种时长词 × 任意等级：条数/档位/时限/状态全合规（穷举）', () {
      // 三种时长词的期限天数（`goalDaysFor` 真值，不含提档）
      const Map<String, int> baseDays = <String, int>{
        '一周试试': 7,
        '两个月加码': 60,
        '半年冲一次': 180,
      };
      for (final GoalCategory cat in kGoalCatOrder) {
        final Goal prev = buildFirstGoal(text: '随便一个${cat.label}目标', cat: cat);
        baseDays.forEach((String t, int days) {
          for (final int lv in <int>[1, 4, 9]) {
            final Goal g = next(prev, level: lv, text: '${cat.label}·$t');
            // 满额完成（上一目标 3/3）+ lv≥4 → 提档 +7 天
            final int want = days + (lv >= 4 ? 7 : 0);
            expect(g.days, want, reason: '${cat.id}/$t/$lv');
            expect(g.plan.length, g.days, reason: '${cat.id}/$t/$lv');
            expect(
              g.plan.length,
              inInclusiveRange(kPlanMinTasks, kPlanMaxTasks),
              reason: '${cat.id}/$t/$lv',
            );
            // 新铸的清单一张都还没开工（顺序锁已废除，不做 cur/lock 区分）
            expect(
              g.plan.every((PlanTask r) => r.state == PlanState.todo),
              isTrue,
              reason: '${cat.id}/$t/$lv',
            );
            expect(g.doneCount, 0, reason: '${cat.id}/$t/$lv');
            expect(g.firstOpenIndex, 0, reason: '${cat.id}/$t/$lv');
            for (final PlanTask r in g.plan) {
              expect(r.minutes, greaterThanOrEqualTo(5), reason: '${cat.id}/$t/$lv');
              expect(Rarity.ranks, contains(r.rank));
            }
          }
        });
      }
    });

    test('新主线可整链存档往返（days/条数/兑现标记都不丢）', () {
      final Goal g = next(finishedFirst(), text: '半年减重 10 斤');
      final Goal back = Goal.fromJson(g.toJson(), fallback: Goal.empty());
      expect(back.plan.length, g.plan.length);
      expect(back.days, g.days);
      expect(back.cat, 'slim');
      expect(back.plan.last.finalTask, isTrue);
      expect(back.plan.first.state, PlanState.todo);
      expect(back.interview['sleep.schedule'], '0 点前睡 7 点前起');
    });
  });

  group('见面礼（原型 bind 的双倍卡语义保留）', () {
    test('空表送 1 张；已有则叠加；不改动传入表', () {
      expect(kBindGiftDbl, 1);
      expect(kBindGiftItemKey, 'dbl'); // 道具表 items.dart 的双倍卡 key
      expect(kBindGiftKicker, '见面礼');
      expect(kBindGiftText, '双倍卡 ×1');

      expect(applyBindGift(const <String, int>{}), <String, int>{'dbl': 1});

      final Map<String, int> src = <String, int>{'dbl': 1, 'crit': 2};
      final Map<String, int> out = applyBindGift(src);
      expect(out['dbl'], 2);
      expect(out['crit'], 2);
      expect(src['dbl'], 1); // 原表不被改写
    });
  });
}
