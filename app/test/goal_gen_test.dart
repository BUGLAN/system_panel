import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
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
      expect(pool.length, 4 + kDailyCommon.length);
      expect(pool.first.title, '睡前 30 分钟不碰手机');
    });

    test('gen 池只有通用池；未知类型兜底到 gen', () {
      expect(dailyPoolFor('gen').length, kDailyCommon.length);
      expect(dailyPoolFor('不存在的类型'), dailyPoolFor('gen'));
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
}
