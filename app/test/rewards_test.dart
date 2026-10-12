import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/data/rarity.dart';
import 'package:system_panel/data/rewards.dart';
import 'package:system_panel/state/goal_gen.dart';
import 'package:system_panel/state/quest.dart';
import 'package:system_panel/state/quest_flow.dart';

/// T6-2 的数值契约（docs/18 §2.2/§2.3 + 第四章 T6 验收单）：
///  · E~S 奖励表逐档断言（F 兼容档）、升级曲线 need=12+lv×6
///  · 结算乘区：暴击 ×2、双倍卡 ×2 可叠 ×4、补救单 ×0.5（金币不吃双倍）
///  · 周期生成：候选池 4~6 → 最弱维/贴主线挑 1~2；换日队列手术
///    （隔夜作废/主线重钉/补救单留未过期）；日上限 6；主线不占配额
void main() {
  group('奖励表逐档（docs/18 §2.3）', () {
    test('经验：F0 / E1 / D2 / C4 / B6 / A8 / S10', () {
      expect(Rewards.expOf('F'), 0);
      expect(Rewards.expOf('E'), 1);
      expect(Rewards.expOf('D'), 2);
      expect(Rewards.expOf('C'), 4);
      expect(Rewards.expOf('B'), 6);
      expect(Rewards.expOf('A'), 8);
      expect(Rewards.expOf('S'), 10);
    });

    test('金币：F3 / E5 / D5 / C5 / B7 / A10 / S20', () {
      expect(Rewards.coinOf('F'), 3);
      expect(Rewards.coinOf('E'), 5);
      expect(Rewards.coinOf('D'), 5);
      expect(Rewards.coinOf('C'), 5);
      expect(Rewards.coinOf('B'), 7);
      expect(Rewards.coinOf('A'), 10);
      expect(Rewards.coinOf('S'), 20);
    });

    test('与 QuestFlow.settle 现行数值逐档一致（迁移前的防漂移钉）', () {
      for (final String r in <String>['F', 'E', 'D', 'C', 'B', 'A', 'S']) {
        expect(Rewards.expOf(r), QuestFlow.expOf(r), reason: 'EXP $r');
        expect(Rewards.coinOf(r), QuestFlow.coinOf(r), reason: '金币 $r');
      }
    });

    test('升级曲线 need(lv) = 12 + lv×6（lv1=18 … lv5=42 … lv10=72）', () {
      expect(Rewards.needFor(1), 18);
      expect(Rewards.needFor(2), 24);
      expect(Rewards.needFor(5), 42);
      expect(Rewards.needFor(10), 72);
      expect(Rewards.needFor(1), QuestFlow.needFor(1));
      expect(Rewards.needFor(7), QuestFlow.needFor(7));
      // 节奏校验（§2.3）：首目标 3 天 1+2+4=7 EXP + 日常 2~8 → 3~5 天升 LV2
      expect(7 + 8, lessThan(Rewards.needFor(1)));
      expect(7 + 8 + Rewards.needFor(1), greaterThan(Rewards.needFor(1)));
    });
  });

  group('结算乘区（store.js:281-283）', () {
    test('普通单 = 表值：E → EXP 1 / 金币 5', () {
      expect(Rewards.payout(rank: 'E', crit: false, dbl: false), const Payout(baseExp: 1, exp: 1, coin: 5));
    });

    test('暴击 ×2：经验与金币都翻倍', () {
      expect(Rewards.payout(rank: 'E', crit: true, dbl: false), const Payout(baseExp: 1, exp: 2, coin: 10));
      expect(Rewards.payout(rank: 'S', crit: true, dbl: false), const Payout(baseExp: 10, exp: 20, coin: 40));
    });

    test('双倍卡 ×2 只吃经验；与暴击可叠 ×4', () {
      expect(Rewards.payout(rank: 'E', crit: false, dbl: true), const Payout(baseExp: 1, exp: 2, coin: 5));
      expect(Rewards.payout(rank: 'E', crit: true, dbl: true), const Payout(baseExp: 1, exp: 4, coin: 10));
    });

    test('补救单 ×0.5（D：EXP 2→1、金币 5→2.5→3），暴击在其上再翻', () {
      expect(
        Rewards.payout(rank: 'D', crit: false, dbl: false, remedy: true),
        const Payout(baseExp: 1, exp: 1, coin: 3),
      );
      expect(
        Rewards.payout(rank: 'D', crit: true, dbl: false, remedy: true),
        const Payout(baseExp: 1, exp: 2, coin: 6),
      );
    });

    test('F 兼容档：经验 0（金币照给 3）—— 仅老存档/补救残单结算用', () {
      expect(Rewards.payout(rank: 'F', crit: false, dbl: false), const Payout(baseExp: 0, exp: 0, coin: 3));
    });
  });

  group('单据读数（quest.dart 接 Rewards）', () {
    test('lootText = 结算经济口径：C 级 EXP 4 · ◈ 5（与 settle 同表）', () {
      expect(Quest.demo.lootText, 'EXP 4 · ◈ 5体+1 力+1');
    });

    test('lootText 补救单减半：D 级 EXP 1 · ◈ 3（金币 2.5 → 3）', () {
      const Quest remedy = Quest(
        serial: 1,
        kind: 'remedy',
        planIndex: -1,
        planTotal: 0,
        name: '做一半',
        reason: '',
        proof: '',
        minutes: 10,
        rank: 'D',
        attrs: <String, int>{'体': 2},
      );
      expect(remedy.lootText, 'EXP 1 · ◈ 3体+2');
    });

    test('rewardText 保持原型板面旧表（plate 像素真值，返工卡再迁）', () {
      expect(Quest.demo.rewardText, 'EXP 50 · ◈ 24体+1 力+1');
    });
  });

  // ═══ 周期任务生成（docs/18 §2.2 · T6-2）══════════════════════

  group('每日单数与候选池', () {
    test('dailyCountFor：lv≥5 或连击≥3 为 2，否则 1', () {
      expect(dailyCountFor(level: 1, streak: 0), 1);
      expect(dailyCountFor(level: 4, streak: 2), 1);
      expect(dailyCountFor(level: 5, streak: 0), 2);
      expect(dailyCountFor(level: 9, streak: 0), 2);
      expect(dailyCountFor(level: 1, streak: 3), 2);
      expect(dailyCountFor(level: 4, streak: 7), 2);
    });

    test('候选池 4~6 个、互不重复；gen 类（专属池空）落通用池照样够', () {
      final math.Random rnd = math.Random(7);
      for (final String cat in <String>['run', 'sleep', 'gen']) {
        final List<DailyTemplate> cands = genDailyCandidates(catId: cat, rnd: rnd);
        expect(cands.length, inInclusiveRange(kDailyCandidateMin, kDailyCandidateMax),
            reason: cat);
        expect(cands.map((DailyTemplate d) => d.title).toSet().length, cands.length,
            reason: '$cat 去重');
      }
    });

    test('挑单：第一单专治最弱维，第二单贴主线（类别六维倾向命中）', () {
      const List<DailyTemplate> candidates = <DailyTemplate>[
        DailyTemplate(
          title: '慢跑 1.5 公里',
          proof: '跑步 App 截图',
          minutes: 20,
          attrs: <String, int>{'体': 1, '敏': 1},
          rank: 'E',
        ),
        DailyTemplate(
          title: '读 20 页书',
          proof: '页码照片',
          minutes: 30,
          attrs: <String, int>{'智': 1, '知': 1},
          rank: 'E',
        ),
        DailyTemplate(
          title: '平板支撑累计 3 分钟',
          proof: '计时截图',
          minutes: 10,
          attrs: <String, int>{'力': 1, '体': 1},
          rank: 'E',
        ),
        DailyTemplate(
          title: '拉伸 10 分钟',
          proof: '拉伸照片',
          minutes: 12,
          attrs: <String, int>{'敏': 2},
          rank: 'F',
        ),
      ];
      final List<DailyTemplate> picks = pickDailies(
        candidates: candidates,
        // 最弱维 = 敏（2）
        attrs: const <String, int>{'力': 9, '敏': 2, '体': 17, '智': 6, '知': 8, '魅': 4},
        goalCatId: 'run', // tilt = 体2/敏1/力1
        n: 2,
        rnd: math.Random(11),
      );
      expect(picks.length, 2);
      expect(picks[0].attrs['敏'] ?? 0, greaterThan(0), reason: '一单专治最弱维');
      expect(
        picks[1].attrs.keys.any((String k) => const <String>['体', '敏', '力'].contains(k)),
        isTrue,
        reason: '一单贴主线（run 的倾向维）',
      );
      expect(picks[0].title, isNot(picks[1].title), reason: '不重复挑同一张');
    });

    test('候选里没有短板单时随缘兜底，绝不满手空回', () {
      final math.Random rnd = math.Random(3);
      final List<DailyTemplate> picks = pickDailies(
        candidates: const <DailyTemplate>[
          DailyTemplate(
            title: '写 300 字',
            proof: '文字截图',
            minutes: 25,
            attrs: <String, int>{'智': 1},
            rank: 'E',
          ),
        ],
        attrs: const <String, int>{'力': 9, '敏': 2, '体': 17, '智': 6, '知': 8, '魅': 4},
        goalCatId: 'fit', // tilt 力/体 —— 候选里一个都没有
        n: 1,
        rnd: rnd,
      );
      expect(picks.length, 1, reason: '随缘兜底接住');
    });
  });

  group('日常档位与模板落单', () {
    test('lv<4 不提档：F 钉回 E（新生成不再出 F）、C 封到 D', () {
      final math.Random rnd = math.Random(99);
      expect(dailyRankFor('F', level: 1, rnd: rnd), 'E');
      expect(dailyRankFor('E', level: 2, rnd: rnd), 'E');
      expect(dailyRankFor('D', level: 3, rnd: rnd), 'D');
      expect(dailyRankFor('C', level: 1, rnd: rnd), 'D', reason: '低级封顶 D');
      expect(dailyRankFor('S', level: 1, rnd: rnd), 'D');
    });

    test('lv≥8 封顶 C；lv≥4 的提档不出 [1..cap] 之外（多 seed 扫描）', () {
      for (int seed = 0; seed < 40; seed++) {
        final math.Random rnd = math.Random(seed);
        final String r4 = dailyRankFor('F', level: 4, rnd: rnd);
        expect(Rarity.of(r4).i, inInclusiveRange(1, 2), reason: 'lv4 seed=$seed');
        final String r8 = dailyRankFor('F', level: 8, rnd: rnd);
        expect(Rarity.of(r8).i, inInclusiveRange(1, 3), reason: 'lv8 seed=$seed');
      }
    });

    test('模板 → 单：kind/名称/证明/时限随模板，六维按档位点数重分', () {
      const DailyTemplate t = DailyTemplate(
        title: '慢跑 1.5 公里',
        proof: '跑步 App 截图',
        minutes: 20,
        attrs: <String, int>{'体': 1, '敏': 1},
        rank: 'F',
      );
      final Quest q = dailyQuestFrom(
        t,
        serial: 777,
        level: 1,
        rnd: math.Random(1),
      );
      expect(q.serial, 777);
      expect(q.kind, 'daily');
      expect(q.name, '慢跑 1.5 公里');
      expect(q.proof, '跑步 App 截图');
      expect(q.minutes, 20);
      expect(q.rank, 'E', reason: 'F 只出不练：新生成钉回 E');
      expect(
        q.attrs.values.fold<int>(0, (int s, int v) => s + v),
        Rarity.of('E').pt,
        reason: '六维按档位点数（E=1）重分',
      );
    });
  });

  group('换日队列手术（store.js rollDay L179-196）', () {
    const Quest overnightDaily = Quest(
      serial: 71,
      kind: 'daily',
      planIndex: -1,
      planTotal: 0,
      name: '昨天的单',
      reason: '',
      proof: '',
      minutes: 15,
      rank: 'E',
      attrs: <String, int>{'体': 1},
    );
    const Quest overnightMain = Quest(
      serial: 41,
      kind: 'main',
      planIndex: 4,
      planTotal: 8,
      name: '昨天被退缩降过档的主线',
      reason: '',
      proof: '',
      minutes: 45,
      rank: 'D',
      attrs: <String, int>{'体': 1},
    );
    const Quest remedy = Quest(
      serial: 81,
      kind: 'remedy',
      planIndex: -1,
      planTotal: 0,
      name: '补救单',
      reason: '',
      proof: '',
      minutes: 10,
      rank: 'F',
      attrs: <String, int>{'体': 1},
    );

    Quest freshDaily(int serial) => Quest(
      serial: serial,
      kind: 'daily',
      planIndex: -1,
      planTotal: 0,
      name: '今天的单 $serial',
      reason: '',
      proof: '',
      minutes: 15,
      rank: 'E',
      attrs: <String, int>{'体': 1},
    );

    final DateTime now = DateTime(2026, 3, 1, 7);

    test('隔夜日常与主线作废，主线单重钉（新单号新档位）顶到队首', () {
      final List<Quest> out = rollDayQueue(
        overnight: <Quest>[overnightMain, overnightDaily],
        fresh: <Quest>[freshDaily(90), freshDaily(91)],
        mainTask: () => const Quest(
          serial: 42,
          kind: 'main',
          planIndex: 4,
          planTotal: 8,
          name: '跑完 5 公里',
          reason: '',
          proof: '跑步 App 截图',
          minutes: 45,
          rank: 'C',
          attrs: <String, int>{'体': 1, '力': 1},
        ),
        now: now,
      );
      expect(out.map((Quest q) => q.kind), <String>['main', 'daily', 'daily']);
      expect(out.first.serial, 42, reason: '重钉的新主线单在队首');
      expect(out.first.rank, 'C', reason: '昨天退缩降的档，新的一天还原');
      expect(out.any((Quest q) => q.serial == overnightDaily.serial), isFalse,
          reason: '隔夜日常作废');
      expect(out.any((Quest q) => q.serial == overnightMain.serial), isFalse,
          reason: '旧主线单不作废保留');
    });

    test('补救单只留未过期的；主线没有脚下环（goal 空）时不重钉', () {
      final List<Quest> out = rollDayQueue(
        overnight: <Quest>[overnightDaily, remedy],
        fresh: const <Quest>[],
        remedyDeadline: now.add(const Duration(hours: 1)),
        now: now,
      );
      expect(out.map((Quest q) => q.serial), <int>[remedy.serial]);

      final List<Quest> expired = rollDayQueue(
        overnight: <Quest>[remedy],
        fresh: const <Quest>[],
        remedyDeadline: now.subtract(const Duration(minutes: 1)),
        now: now,
      );
      expect(expired, isEmpty, reason: '过期的补救单一并清走');
    });

    test('执行中的就是主线单时不重钉（原型 L189，防双主线）', () {
      final List<Quest> out = rollDayQueue(
        overnight: <Quest>[overnightDaily],
        fresh: const <Quest>[],
        mainTask: () => overnightMain,
        activeIsMain: true,
        now: now,
      );
      expect(out.any((Quest q) => q.kind == 'main'), isFalse);
    });

    test('日上限 6：补发超了就钳掉；主线/补救单不占配额', () {
      final List<Quest> fresh = <Quest>[
        for (int i = 0; i < 9; i++) freshDaily(100 + i),
      ];
      final List<Quest> out = rollDayQueue(
        overnight: <Quest>[remedy, overnightMain],
        fresh: fresh,
        mainTask: () => overnightMain,
        now: now,
      );
      expect(out.where((Quest q) => q.kind == 'daily').length, kDailyCap);
      expect(out.where((Quest q) => q.kind == 'remedy').length, 1);
      expect(out.where((Quest q) => q.kind == 'main').length, 1);
      expect(out.length, kDailyCap + 2, reason: '主线与补救不吃日常配额');
    });
  });

  group('绑定见面礼（原型 bind() 的 dbl+=1）', () {
    test('applyBindGift：双倍卡 +1，原表不动', () {
      final Map<String, int> before = <String, int>{
        'dbl': 0, 'crit': 1, 'shield': 0, 'swap': 2,
      };
      final Map<String, int> after = applyBindGift(before);
      expect(after['dbl'], 1);
      expect(after['crit'], 1);
      expect(after['swap'], 2);
      expect(before['dbl'], 0, reason: '不改传入表');
      expect(kBindGiftItemKey, 'dbl');
      expect(kBindGiftKicker, '见面礼');
      expect(kBindGiftText, '双倍卡 ×1');
    });
  });
}