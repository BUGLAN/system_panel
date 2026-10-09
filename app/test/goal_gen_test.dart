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
///  目标生成（goal_gen.dart）—— 类型识别 · 访谈卡组 · 首目标 3 天 3 环
///  · 答案三用 · 老存档兼容（docs/18 §2.1 / §2.8，T6-1）
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

  group('首目标：3 天 3 环（E/D/C）', () {
    final GoalCategory sleep = goalCats['sleep']!;
    final Goal goal = buildFirstGoal(text: '一个月早睡早起', cat: sleep);

    test('周期与元数据', () {
      expect(goal.days, 3);
      expect(goal.cat, 'sleep');
      expect(goal.text, '一个月早睡早起');
      expect(goal.short, '早起'); // 原型 shortOf：早起 规则在 早睡 之前
      expect(goal.rings.length, 3);
      expect(kFirstGoalDays, 3);
    });

    test('档位 E/D/C、状态与头顶环', () {
      expect(goal.rings.map((GoalRing r) => r.rank).toList(), <String>[
        'E',
        'D',
        'C',
      ]);
      expect(goal.rings.first.state, RingState.cur);
      expect(goal.rings[1].state, RingState.lock);
      expect(goal.rings[2].state, RingState.lock);
      expect(goal.rings[2].finalRing, isTrue);
      expect(goal.rings.first.finalRing, isFalse);
    });

    test('时限落在 docs/18 §2.3 建议档内（E≤15 / D≤20 / C≤30，下限 5）', () {
      expect(goal.rings[0].minutes, lessThanOrEqualTo(15));
      expect(goal.rings[1].minutes, lessThanOrEqualTo(20));
      expect(goal.rings[2].minutes, lessThanOrEqualTo(30));
      for (final GoalRing r in goal.rings) {
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

    test('负担重 → 第 1 环换「比昨天早睡 15 分钟」（docs/18 §2.1 示例）', () {
      final Goal heavy = buildFirstGoal(
        text: '一个月早睡早起',
        cat: sleep,
        answers: const <String, String>{
          'sleep.schedule': '1-2 点睡 9 点后起',
          'sleep.recent': '天天熬夜',
        },
      );
      expect(heavy.rings.first.title, '比昨天早睡 15 分钟');
      expect(heavy.rings.first.rank, 'E');
      // 其余环不受影响
      expect(heavy.rings[1].title, '今晚 23:30 前放下手机上床');

      final Goal unset = buildFirstGoal(
        text: '一个月早睡早起',
        cat: sleep,
        answers: const <String, String>{'sleep.schedule': '没有固定'},
      );
      expect(unset.rings.first.title, '比昨天早睡 15 分钟');

      final Goal light = buildFirstGoal(
        text: '一个月早睡早起',
        cat: sleep,
        answers: const <String, String>{'sleep.recent': '基本规律'},
      );
      expect(light.rings.first.title, '定好明早的闹钟，手机放到够不着的地方');
    });

    test('没有轻档环的类别不受「负担重」影响', () {
      final Goal g = buildFirstGoal(
        text: '三个月跑完半马',
        cat: goalCats['run']!,
        answers: const <String, String>{'run.now': '没跑过，天天熬夜'},
      );
      expect(g.rings.first.title, '换上跑鞋，出门快走 15 分钟');
      expect(g.days, 3);
    });

    test('十类都能铸出合规首目标', () {
      for (final GoalCategory cat in kGoalCatOrder) {
        final Goal g = buildFirstGoal(text: '随便一个${cat.label}目标', cat: cat);
        expect(g.rings.length, 3, reason: cat.id);
        expect(g.rings.map((GoalRing r) => r.rank), <String>['E', 'D', 'C']);
        expect(g.days, 3, reason: cat.id);
        expect(g.rings.last.finalRing, isTrue, reason: cat.id);
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
      expect(g.days, 0);
      expect(g.interview, isEmpty);
      expect(g.text, '三个月跑完半马'); // 老字段照常读回
      expect(g.rings, isNotEmpty);
      expect(shouldOnboard(g), isFalse); // 环非空 = 已有主线 = 不触发
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
      expect(back.rings.length, 3);
      expect(back.rings.first.state, RingState.cur);
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
      expect(back.goal.rings.map((GoalRing r) => r.rank).toList(), <String>[
        'E',
        'D',
        'C',
      ]);
      expect(shouldOnboard(back.goal), isFalse);
    });
  });

  group('第二目标闭环（TODO-01 + TODO-06 模板半）：finale → 下一条主线', () {
    /// 上一目标（走完 3 环的 sleep 首目标）
    Goal finishedFirst() {
      final Goal g = buildFirstGoal(
        text: '一个月早睡早起',
        cat: goalCats['sleep']!,
        answers: const <String, String>{'sleep.schedule': '0 点前睡 7 点前起'},
      );
      return g.copyWith(
        rings: <GoalRing>[
          for (final GoalRing r in g.rings)
            GoalRing(
              short: r.short,
              title: r.title,
              proof: r.proof,
              minutes: r.minutes,
              rank: r.rank,
              state: RingState.done,
              finalRing: r.finalRing,
              held: const Duration(minutes: 12),
              doneAt: DateTime(2026, 1, 3),
            ),
        ],
      );
    }

    Goal next(Goal prev, {int? cleared, int? total, int level = 1, String? text}) =>
        buildNextGoal(
          prev: prev,
          cleared: cleared ?? prev.rings.length,
          total: total ?? prev.rings.length,
          level: level,
          text: text,
        );

    test('时长词 → 环数（原型 makeGoal L147-150 逐条）', () {
      // ⚠️ 「一个月」不在原型表里（落默认 6），但「三个月」命中 [三四五六七八九十]个月 → 8。
      //    这两条必须一起钉住，否则 `[两二]个月` 会把「一个月」也吞成 7。
      expect(goalRingCountFor('三个月跑完半马'), 8);
      expect(goalRingCountFor('一个月早睡早起'), 6);
      expect(goalRingCountFor('半年减重 10 斤'), 8);
      expect(goalRingCountFor('一年读完 50 本书'), 8);
      expect(goalRingCountFor('100 天打卡'), 8);
      expect(goalRingCountFor('两个月练出腹肌'), 7);
      expect(goalRingCountFor('二个月冲一次'), 7);
      expect(goalRingCountFor('60 天早起'), 7);
      expect(goalRingCountFor('八周跑完 10K'), 7);
      expect(goalRingCountFor('一周读完一本书'), 5);
      expect(goalRingCountFor('7 天早睡'), 5);
      expect(goalRingCountFor('两周背完 500 词'), 5);
      expect(goalRingCountFor('随便一个目标'), 6);
    });

    test('环数永远落在 5~8，且末环是「兑现它」的 S 环', () {
      for (final GoalCategory cat in kGoalCatOrder) {
        final Goal g = next(
          buildFirstGoal(text: '随便一个${cat.label}目标', cat: cat),
          text: '半年${cat.label}进阶',
        );
        expect(g.rings.length, inInclusiveRange(5, 8), reason: cat.id);
        expect(g.days, g.rings.length, reason: cat.id);
        expect(g.rings.first.state, RingState.cur, reason: cat.id);
        expect(g.rings.last.state, RingState.lock, reason: cat.id);
        expect(g.rings.last.finalRing, isTrue, reason: cat.id);
        expect(g.rings.last.rank, 'S', reason: cat.id);
        expect(g.rings.last.title, endsWith('——兑现它'), reason: cat.id);
        expect(g.rings.last.minutes, kNextGoalFinalMinutes, reason: cat.id);
        // 只有末环带 finalRing；中间环不越界
        expect(
          g.rings.where((GoalRing r) => r.finalRing).length,
          1,
          reason: cat.id,
        );
      }
    });

    test('档位低开高走：首环 E、含 S、末环 S，全部是合法档位', () {
      final Goal g = next(finishedFirst(), text: '半年减重 10 斤');
      expect(g.rings.first.rank, 'E');
      expect(g.rings.map((GoalRing r) => r.rank), contains('S'));
      expect(g.rings.last.rank, 'S');
      for (final GoalRing r in g.rings) {
        expect(Rarity.ranks, contains(r.rank));
      }
    });

    test('完成度提档：满环 + lv≥4 多一环；没满环不提档；封顶 8', () {
      final Goal prev = finishedFirst();
      expect(completionRingBoost(cleared: 3, total: 3, level: 3), 0);
      expect(completionRingBoost(cleared: 3, total: 3, level: 4), 1);
      expect(completionRingBoost(cleared: 2, total: 3, level: 9), 0);
      expect(completionRingBoost(cleared: 0, total: 0, level: 9), 0);

      final Goal low = next(prev, level: 3); // 默认 6 环
      final Goal high = next(prev, level: 5); // 6 + 1 = 7 环
      expect(low.rings.length, 6);
      expect(high.rings.length, 7);
      // 8 环目标 + 提档 → 还是 8（封顶）
      expect(next(prev, level: 5, text: '半年减重 10 斤').rings.length, 8);
    });

    test('沿用上一目标的文本/类型/访谈答案/立目标时刻', () {
      final Goal prev = finishedFirst();
      final Goal g = next(prev);
      expect(g.text, prev.text);
      expect(g.cat, 'sleep');
      expect(g.short, prev.short);
      expect(g.at, prev.at);
      expect(g.interview['sleep.schedule'], '0 点前睡 7 点前起');
    });

    test('换了那句话：类型跟着新那句话走，访谈答案仍是宿主的', () {
      final Goal prev = finishedFirst();
      final Goal g = next(prev, text: '半年减重 10 斤');
      expect(g.text, '半年减重 10 斤');
      expect(g.cat, 'slim');
      expect(g.short, '−10斤');
      expect(g.rings.length, 8);
      expect(g.interview['sleep.schedule'], '0 点前睡 7 点前起');
    });

    test('加码环：时限递增且落在档位上限内，题面不空', () {
      final Goal g = next(finishedFirst(), text: '半年减重 10 斤');
      final List<GoalRing> mids = g.rings.sublist(0, g.rings.length - 1);
      expect(mids.length, 7);
      for (int i = 3; i < mids.length; i++) {
        expect(mids[i].title.trim(), isNotEmpty);
        expect(mids[i].proof.trim(), isNotEmpty);
        expect(mids[i].minutes, inInclusiveRange(5, 180));
      }
      // 第 4 环（0 基 3，第一条加码环）比它的底样更长
      expect(mids[3].minutes, greaterThan(mids[0].minutes));
    });

    test('十类 × 5~8 环 × 任意等级：环数/档位/时限/状态全合规（穷举）', () {
      for (final GoalCategory cat in kGoalCatOrder) {
        final Goal prev = buildFirstGoal(text: '随便一个${cat.label}目标', cat: cat);
        for (final String t in <String>['一周试试', '两个月加码', '半年冲一次']) {
          for (final int lv in <int>[1, 4, 9]) {
            final Goal g = next(prev, level: lv, text: '${cat.label}·$t');
            expect(g.rings.length, inInclusiveRange(5, 8), reason: '${cat.id}/$t/$lv');
            expect(g.days, g.rings.length);
            expect(g.rings.first.state, RingState.cur);
            expect(
              g.rings.skip(1).every((GoalRing r) => r.state == RingState.lock),
              isTrue,
            );
            for (final GoalRing r in g.rings) {
              expect(r.minutes, greaterThanOrEqualTo(5), reason: '${cat.id}/$t/$lv');
              expect(Rarity.ranks, contains(r.rank));
            }
          }
        }
      }
    });

    test('新主线可整链存档往返（days/环数/末环标记都不丢）', () {
      final Goal g = next(finishedFirst(), text: '半年减重 10 斤');
      final Goal back = Goal.fromJson(g.toJson(), fallback: Goal.empty());
      expect(back.rings.length, g.rings.length);
      expect(back.days, g.days);
      expect(back.cat, 'slim');
      expect(back.rings.last.finalRing, isTrue);
      expect(back.rings.first.state, RingState.cur);
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
