import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/host_state.dart';
import 'package:system_panel/state/quest.dart';
import 'package:system_panel/state/quest_flow.dart';
import 'package:system_panel/state/result.dart';
import 'package:system_panel/state/save_file.dart';

/// QuestFlow —— 业务唯一真源（store.js 移植）。
///
/// 这里钉住「提交任务卡死」修复后的**数值契约**（docs/18 §2.3 + 第四章 T2）：
///  · E 级单 EXP +1、金币 +5；暴击 ×2、双倍卡 ×2、可叠 ×4；补救 ×0.5
///  · 升级走 need = 12 + lv×6
///  · 主线环点亮 + 队首补下一环；队列空 → empty（结算页弹【收工。】）
///  · 认输：主线回队首、生成补救单；接补救 = 插回队首
void main() {
  // 一张确定的 E 级日常单（serial 自拟，不与 41 撞）
  const Quest eQuest = Quest(
    serial: 900,
    kind: 'daily',
    ring: -1,
    ringTotal: 0,
    name: '出门走 3000 步',
    reason: '',
    proof: '步数截图',
    minutes: 30,
    rank: 'E',
    attrs: <String, int>{'体': 1},
  );

  /// 一张确定的 D 级补救单（半价口径用）
  const Quest dRemedy = Quest(
    serial: 901,
    kind: 'remedy',
    ring: -1,
    ringTotal: 0,
    name: '做一半',
    reason: '',
    proof: '',
    minutes: 20,
    rank: 'D',
    attrs: <String, int>{'体': 1},
  );

  /// 干净宿主（lv1 exp0、三件执行道具各 1），时间钉死，随机源钉死
  QuestFlow freshFlow({HostState? host, Goal? goal, List<Quest>? queue}) {
    final QuestFlow f = QuestFlow(
      host:
          host ??
          HostState.empty.copyWith(
            items: <String, int>{'dbl': 1, 'crit': 1, 'shield': 1, 'swap': 0},
          ),
      goal: goal ?? Goal.demo(),
      queue: queue,
      serial: 1000,
      rnd: math.Random(7),
    );
    return f;
  }

  /// 接一张单并结算（默认不暴击）；返回结算结果
  QuestResult? settleOf(
    QuestFlow f,
    Quest q, {
    DateTime? start,
    DateTime? end,
    bool? crit,
  }) {
    f.accept(q, now: start ?? DateTime(2026, 1, 1, 10));
    return f.settle(
      now: end ?? DateTime(2026, 1, 1, 10, 30),
      forceCrit: crit ?? false,
    );
  }

  group('数值表（docs/18 §2.3）', () {
    test('E~S 经验 / 金币，F 兼容档', () {
      expect(QuestFlow.expOf('F'), 0);
      expect(QuestFlow.expOf('E'), 1);
      expect(QuestFlow.expOf('D'), 2);
      expect(QuestFlow.expOf('C'), 4);
      expect(QuestFlow.expOf('B'), 6);
      expect(QuestFlow.expOf('A'), 8);
      expect(QuestFlow.expOf('S'), 10);
      expect(QuestFlow.coinOf('F'), 3);
      expect(QuestFlow.coinOf('E'), 5);
      expect(QuestFlow.coinOf('C'), 5);
      expect(QuestFlow.coinOf('A'), 10);
      expect(QuestFlow.coinOf('S'), 20);
    });

    test('升级曲线 need = 12 + lv×6', () {
      expect(QuestFlow.needFor(1), 18);
      expect(QuestFlow.needFor(5), 42);
      expect(QuestFlow.needFor(10), 72);
    });
  });

  group('演示开局与种子', () {
    test('demo()：队首就是 Quest.demo，共 4 单（主线 + 3 日常），单号不重号', () {
      final QuestFlow f = QuestFlow.demo();
      expect(f.head?.serial, Quest.demo.serial);
      expect(f.head?.rank, 'C');
      expect(f.queue.length, 4);
      expect(f.host.queue, 4); // HUD 的 queue 读数跟真实队列
      expect(f.queue.skip(1).every((Quest q) => q.kind == 'daily'), isTrue);
      // ⚠️ 回归：单号重号会让 accept 的 removeWhere 一次删掉两张
      expect(f.queue.map((Quest q) => q.serial).toSet().length, f.queue.length);
    });

    test('fromSave：老档没队列 → 按现状补种子（合并式迁移）', () {
      final QuestFlow f = QuestFlow.fromSave(
        host: HostState.demo,
        goal: Goal.demo(),
      );
      expect(f.queue, isNotEmpty);
      expect(f.head?.kind, 'main');
    });

    test('fromSave：存档里的队列原样回来（不清档）', () {
      final QuestFlow f = QuestFlow.fromSave(
        host: HostState.demo,
        goal: Goal.demo(),
        queue: <Quest>[eQuest],
      );
      expect(f.queue.length, 1);
      expect(f.head?.serial, eQuest.serial);
    });
  });

  group('接单与道具', () {
    test('accept：队首出队、active 记 startAt（D12）', () {
      final QuestFlow f = QuestFlow.demo();
      final Quest head = f.head!;
      f.accept(head, now: DateTime(2026, 1, 1, 10));
      expect(f.queue.length, 3);
      expect(f.host.queue, 3);
      expect(f.active?.task.serial, head.serial);
      expect(f.active?.startAt, DateTime(2026, 1, 1, 10));
    });

    test('useItem：扣库存、挂标记；重复用/没库存/没接单都 false', () {
      final QuestFlow f = QuestFlow.demo();
      f.accept(f.head!);
      expect(f.useItem('dbl'), isTrue);
      expect(f.host.items['dbl'], 0); // demo 档 dbl ×1
      expect(f.active?.dbl, isTrue);
      expect(f.useItem('dbl'), isFalse); // 本单已挂
      expect(f.useItem('crit'), isTrue);
      expect(f.active?.crit, isTrue);
      expect(f.useItem('swap'), isFalse); // 不是执行类
      final QuestFlow idle = QuestFlow.demo();
      expect(idle.useItem('dbl'), isFalse); // 没接单
    });

    test('critChance：底 6% + 连击 1%/天；暴击芯片 +25%（写死 .12 的修复）', () {
      final QuestFlow f = QuestFlow.demo(); // streak 6
      expect(f.critChance(), 0); // 没接单
      f.accept(f.head!);
      expect(f.critChance(), closeTo(.12, 1e-9)); // .06 + 6×.01
      f.useItem('crit');
      expect(f.critChance(), closeTo(.37, 1e-9));
      f.active!.photos = 3;
      expect(f.critChance(), closeTo(.55, 1e-9)); // .37 + 3×.06
    });
  });

  group('结算：数字来自真实计算', () {
    test('没接单时 settle 返回 null', () {
      expect(freshFlow().settle(), isNull);
    });

    test('E 级单：EXP +1、金币 +5、六维 +、连击起 1（验收：E→1/5）', () {
      final QuestFlow f = freshFlow();
      final QuestResult? r = settleOf(f, eQuest);
      expect(r, isNotNull);
      expect(r!.baseExp, 1);
      expect(r.exp, 1);
      expect(r.coin, 5);
      expect(r.crit, isFalse);
      expect(r.dbl, isFalse);
      expect(r.ups, isEmpty);
      expect(r.streak, 1);
      expect(r.streakUp, isTrue);
      expect(r.empty, isTrue); // 队列空了 → 结算页该弹【收工。】
      expect(r.lvAfter, 1);
      expect(r.finalNeed, 18);
      expect(r.expAfterSettle, 1);
      // 落账
      expect(f.host.exp, 1);
      expect(f.host.coins, 5);
      expect(f.host.streak, 1);
      expect(f.host.bestStreak, 1);
      expect(f.host.doneCount, 1);
      expect(f.host.attrs['体'], 1);
      expect(f.active, isNull);
    });

    test('暴击 ×2：经验与金币都翻倍，critCount 记账', () {
      final QuestFlow f = freshFlow();
      final QuestResult? r = settleOf(f, eQuest, crit: true);
      expect(r!.exp, 2);
      expect(r.coin, 10);
      expect(r.crit, isTrue);
      expect(f.host.critCount, 1);
      expect(f.host.coins, 10);
    });

    test('双倍卡 ×2；与暴击可叠成 ×4（道具效果不再只是摆设）', () {
      final QuestFlow f = freshFlow();
      f.accept(eQuest);
      f.useItem('dbl');
      QuestResult? r = f.settle(forceCrit: false);
      expect(r!.exp, 2, reason: 'E 1 × 双倍卡 2');
      expect(r.dbl, isTrue);
      expect(f.host.items['dbl'], 0, reason: '库存真扣了');

      final QuestFlow g = freshFlow();
      g.accept(eQuest);
      g.useItem('dbl');
      g.useItem('crit'); // 暴击芯片只加暴击率，forceCrit 钉死结果
      r = g.settle(forceCrit: true);
      expect(r!.exp, 4, reason: 'E 1 × 暴击 2 × 双倍卡 2');
      expect(g.host.items['dbl'], 0);
      expect(g.host.items['crit'], 0);
      expect(g.host.coins, 5 * 2, reason: '金币吃暴击不吃双倍');
    });

    test('补救单半价：EXP 1、金币 3，redeemed 置位', () {
      final QuestFlow f = freshFlow();
      final QuestResult? r = settleOf(f, dRemedy);
      expect(r!.baseExp, 1); // D 2 × .5
      expect(r.exp, 1);
      expect(r.coin, 3); // D 5 × .5 = 2.5 → 3
      expect(r.redeemed, isTrue);
    });

    test('升级：need=12+lv×6，溢出滚入下一档，afterNeed 换分母', () {
      final HostState lv1near = HostState.empty.copyWith(
        exp: 17, // 差 1 升级
        items: <String, int>{'dbl': 1, 'crit': 1, 'shield': 1, 'swap': 0},
      );
      final QuestFlow f = freshFlow(host: lv1near);
      f.accept(
        const Quest(
          serial: 902,
          kind: 'daily',
          ring: -1,
          ringTotal: 0,
          name: 's',
          reason: '',
          proof: '',
          minutes: 10,
          rank: 'S',
          attrs: <String, int>{'力': 2},
        ),
      );
      f.useItem('dbl'); // S 10 ×2 = 20
      final QuestResult? r = f.settle(forceCrit: false);
      expect(r!.ups, <int>[2]); // 17+20=37 → 溢出 19，lv2
      expect(r.lvAfter, 2);
      expect(r.expAfterSettle, 19);
      expect(r.finalNeed, 24); // 12 + 2×6
      expect(f.host.lv, 2);
      expect(f.host.exp, 19);
    });

    test('连升两级：ups 依次记录', () {
      final QuestFlow f = freshFlow(
        host: HostState.empty.copyWith(
          exp: 17,
          items: <String, int>{'dbl': 1, 'crit': 1, 'shield': 1, 'swap': 0},
        ),
      );
      f.accept(
        const Quest(
          serial: 903,
          kind: 'daily',
          ring: -1,
          ringTotal: 0,
          name: 's2',
          reason: '',
          proof: '',
          minutes: 10,
          rank: 'S',
          attrs: <String, int>{},
        ),
      );
      f.useItem('dbl');
      final QuestResult? r = f.settle(forceCrit: true); // 10 ×2 ×2 = 40
      // 17+40=57 → -18=39(lv2) → -24=15(lv3)，15 < 30 停
      expect(r!.ups, <int>[2, 3]);
      expect(f.host.lv, 3);
      expect(f.host.exp, 15);
    });

    test('60 秒内交单 → tooFast（她会拆穿）', () {
      final QuestFlow f = freshFlow();
      final QuestResult? r = settleOf(
        f,
        eQuest,
        start: DateTime(2026, 1, 1, 10),
        end: DateTime(2026, 1, 1, 10, 0, 30),
      );
      expect(r!.tooFast, isTrue);
      expect(r.held, const Duration(seconds: 30));
    });

    test('称号：首单解锁 first，暴击解锁 crit（落入 ownedTitles）', () {
      final QuestFlow f = freshFlow();
      settleOf(f, eQuest, crit: true);
      expect(f.host.ownedTitles, containsAll(<String>['first', 'crit']));
      expect(f.host.title, 'crit');
    });
  });

  group('主线环（提交后点亮 + 队首补下一环）', () {
    test('清一环：state=done、held/doneAt 落档、下一环 cur 且补单', () {
      final QuestFlow f = QuestFlow.demo();
      final Quest head = f.head!;
      expect(head.ring, 4);
      f.accept(head, now: DateTime(2026, 1, 1, 10));
      final QuestResult? r = f.settle(
        now: DateTime(2026, 1, 1, 10, 45),
        forceCrit: false,
      );
      expect(r!.ringClear, 4);
      expect(r.finale, isFalse);
      final List<GoalRing> rings = f.goal.rings;
      expect(rings[4].state, RingState.done);
      expect(rings[4].held, const Duration(minutes: 45));
      expect(rings[4].doneAt, DateTime(2026, 1, 1, 10, 45));
      expect(rings[5].state, RingState.cur);
      // 队首是新的第 6 环（0 基 5）
      expect(f.head?.kind, 'main');
      expect(f.head?.ring, 5);
      expect(f.queueEmpty, isFalse);
      expect(r.empty, isFalse);
    });

    test('收官：最后一环清掉 → finale，没有下一环补单', () {
      final Goal oneRing = Goal(
        text: '测试目标',
        short: '测试',
        at: DateTime(2026, 1, 1),
        rings: const <GoalRing>[
          GoalRing(
            short: '一环',
            title: '唯一的一环',
            proof: '截图',
            minutes: 15,
            rank: 'E',
            state: RingState.cur,
          ),
        ],
      );
      final QuestFlow f = freshFlow(goal: oneRing);
      f.accept(
        const Quest(
          serial: 905,
          kind: 'main',
          ring: 0,
          ringTotal: 1,
          name: '唯一的一环',
          reason: '',
          proof: '截图',
          minutes: 15,
          rank: 'E',
          attrs: <String, int>{'体': 1},
        ),
      );
      final QuestResult? r = f.settle(forceCrit: false);
      expect(r!.ringClear, 0);
      expect(r.finale, isTrue);
      expect(f.queueEmpty, isTrue);
      expect(f.goal.rings.single.state, RingState.done);
      expect(r.titles, contains('finale'));
    });
  });

  group('认输与补救（失败页不再是死局）', () {
    test('fail：failCount 记账、主线回队首、生成补救单（降两档/做一半/24h）', () {
      final QuestFlow f = QuestFlow.demo();
      final Quest head = f.head!;
      f.accept(head, now: DateTime(2026, 1, 1, 10));
      final FailOutcome? fo = f.fail(
        now: DateTime(2026, 1, 1, 10, 10),
        how: 'quit',
      );
      expect(fo, isNotNull);
      expect(fo!.held, const Duration(minutes: 10));
      expect(f.host.failCount, HostState.demo.failCount + 1); // demo 档本身 4 次
      expect(f.active, isNull);
      // 主线不判死：回队首
      expect(f.head?.serial, head.serial);
      // 补救单：C 降两档 = E；时限 = max(5, ⌈45/2⌉)
      expect(fo.remedy?.rank, 'E');
      expect(fo.remedy?.minutes, 23);
      expect(fo.remedy?.name, contains('（做一半）'));
      expect(fo.remedy?.reason, contains('补救')); // 附言是补救台词，不是日常的
      expect(
        fo.remedyDeadline?.difference(DateTime(2026, 1, 1, 10, 10)),
        const Duration(hours: 24),
      );
      expect(f.remedyOffer?.serial, fo.remedy?.serial);
    });

    test('takeRemedy(now:true)：插回队首并清掉 offer（失败页【……接。】）', () {
      final QuestFlow f = QuestFlow.demo();
      f.accept(f.head!);
      final FailOutcome? fo = f.fail();
      final Quest? taken = f.takeRemedy(now: true);
      expect(taken?.serial, fo!.remedy?.serial);
      expect(f.head?.serial, taken?.serial);
      expect(f.remedyOffer, isNull);
      expect(f.host.queue, f.queue.length);
    });

    test('takeRemedy：没 offer 时返回 null；超时判负 also 走 fail', () {
      final QuestFlow f = QuestFlow.demo();
      expect(f.takeRemedy(), isNull);
      f.accept(f.head!);
      final FailOutcome? fo = f.fail(how: 'timeout');
      expect(fo?.how, 'timeout');
      expect(f.failStreak, 1);
    });

    test('免死金牌：失败不计连败口径（shield 置位不涨 failStreak）', () {
      final QuestFlow f = QuestFlow.demo();
      f.accept(f.head!);
      f.useItem('shield');
      f.fail();
      expect(f.failStreak, 0);
    });
  });

  group('队列持久化（结算后杀进程，队列还在）', () {
    test('SaveData 往返带上队列', () {
      final QuestFlow f = QuestFlow.demo();
      f.accept(f.head!);
      final SaveData d = SaveData(host: f.host, goal: f.goal, queue: f.queue);
      final SaveData back = SaveData.fromJson(d.toJson(), fallback: SaveData.fresh());
      expect(back.queue.length, f.queue.length);
      expect(back.queue.first.serial, f.queue.first.serial);
      expect(back.queue.first.kind, f.queue.first.kind);
      expect(back.queue.first.rank, f.queue.first.rank);
    });

    test('SaveData 往返：Quest 字段原样回来（序列化归存档层）', () {
      const Quest source = Quest.demo;
      final SaveData d = SaveData(
        host: HostState.demo,
        goal: Goal.demo(),
        queue: <Quest>[source],
      );
      final Quest back = SaveData.fromJson(
        d.toJson(),
        fallback: SaveData.fresh(),
      ).queue.single;
      expect(back.serial, source.serial);
      expect(back.kind, source.kind);
      expect(back.ring, source.ring);
      expect(back.ringTotal, source.ringTotal);
      expect(back.name, source.name);
      expect(back.reason, source.reason);
      expect(back.proof, source.proof);
      expect(back.minutes, source.minutes);
      expect(back.rank, source.rank);
      expect(back.attrs, source.attrs);
    });

    test('单据字段缺失/类型不对 → 走默认值，不抛（老档兼容口径）', () {
      final SaveData d = SaveData.fromJson(
        <String, dynamic>{
          'host': HostState.demo.toJson(),
          'goal': Goal.demo().toJson(),
          'queue': <dynamic>[<String, dynamic>{}],
        },
        fallback: SaveData.fresh(),
      );
      final Quest back = d.queue.single;
      expect(back.serial, 0);
      expect(back.kind, 'daily');
      expect(back.rank, 'F');
      expect(back.attrs, isEmpty);
      expect(back.hinted, isFalse);
    });

    test('老档 json 没有 queue → 空表走默认（不崩、不清档）', () {
      final SaveData back = SaveData.fromJson(
        jsonDecode('{"host":{"name":"老档"},"goal":null}') as Map<String, dynamic>,
        fallback: SaveData(host: HostState.demo, goal: Goal.demo()),
      );
      expect(back.queue, isEmpty);
      expect(back.host.name, '老档');
    });

    test('连做 3 单（提交 → 再来一单循环）全程有单可接、不卡死', () {
      final QuestFlow f = QuestFlow.demo();
      for (int i = 0; i < 3; i++) {
        final Quest? head = f.head;
        expect(head, isNotNull, reason: '第 ${i + 1} 单必须有单可接');
        f.accept(head!, now: DateTime(2026, 1, 1, 10 + i));
        final QuestResult? r = f.settle(
          now: DateTime(2026, 1, 1, 10 + i, 30),
          forceCrit: false,
        );
        expect(r, isNotNull);
        // 结算页出口：还有单 → 再来一单；没单 → 收工（不再停留）
        if (f.queueEmpty) {
          expect(r!.empty, isTrue);
        } else {
          expect(r!.empty, isFalse);
        }
      }
      expect(f.host.doneCount, HostState.demo.doneCount + 3); // demo 档本身 31 单
    });
  });
}
