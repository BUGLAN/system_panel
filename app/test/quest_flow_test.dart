import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/agent/vision.dart';
import 'package:system_panel/data/rarity.dart';
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

  /// D 级日常（retreat 降一档用：D → E，同 serial 重刻）
  const Quest dQuest = Quest(
    serial: 911,
    kind: 'daily',
    ring: -1,
    ringTotal: 0,
    name: '把一件拖了一周的小事做完',
    reason: '',
    proof: '完成截图',
    minutes: 25,
    rank: 'D',
    attrs: <String, int>{'知': 1, '智': 1},
  );

  /// C 级日常（三连退触发「口头巨人」用：C→D→E→F 换单）
  const Quest cQuest = Quest(
    serial: 912,
    kind: 'daily',
    ring: -1,
    ringTotal: 0,
    name: '做一顿饭',
    reason: '',
    proof: '饭菜照片',
    minutes: 40,
    rank: 'C',
    attrs: <String, int>{'体': 1, '知': 1},
  );

  /// F 级日常（F 还退＝换另一张 F 用）
  const Quest fQuest = Quest(
    serial: 913,
    kind: 'daily',
    ring: -1,
    ringTotal: 0,
    name: '发呆 10 分钟，不碰手机',
    reason: '',
    proof: '计时截图',
    minutes: 12,
    rank: 'F',
    attrs: <String, int>{'知': 1},
  );

  /// 一张带校验状态的证据（t14：暴击口径分已校验/未校验）
  EvidenceShot shot(String id, EvidenceStatus status) => EvidenceShot(
    id: id,
    path: 'evidence/q900/$id.jpg',
    status: status,
    takenAt: DateTime(2026, 1, 1, 10),
  );

  int attrSum(Quest q) =>
      q.attrs.values.fold<int>(0, (int s, int v) => s + v);

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

    test('⚠️ 回归 t16/B1：无档 fallback 的 queue 是 const []，种子化不得抛且队列可变', () {
      // 复刻真机崩溃链：SaveData 默认 queue = const []（**不可变**）→
      // 首装/无档时 load() 原样返回 fallback → fromSave(queue: fallback.queue)
      // → seedForCurrentGoal() 的 queue.add() 抛
      // 「Cannot add to an unmodifiable list」→ 冷启/wipe 直接崩、绑定流不可达。
      final SaveData fallback = SaveData(
        host: HostState.demo,
        goal: Goal.demo(),
      );
      expect(fallback.queue, isEmpty);
      // 先证明 fallback 的队列确实不可变（防线若被移除，这条先红）
      expect(
        () => fallback.queue.add(eQuest),
        throwsUnsupportedError,
        reason: 'SaveData 默认 queue 必须保持 const []——本测试依赖它复现 B1',
      );

      final QuestFlow f = QuestFlow.fromSave(
        host: fallback.host,
        goal: fallback.goal,
        queue: fallback.queue, // ← 不可变表原样传入（真实崩溃参数）
      );
      expect(() => f.seedForCurrentGoal(), returnsNormally);
      expect(f.queue, isNotEmpty);
      expect(f.head?.kind, 'main');
      // 队列必须可变：accept 的 removeWhere、补救单 insert 都要改它
      f.queue.add(eQuest);
      expect(f.queue.last.serial, eQuest.serial);
      f.queue.removeLast();
      expect(f.queue.contains(eQuest), isFalse);
    });

    test('⚠️ 回归 t16/B1 连锁：wipe 的 fallback 队列同样可种子化（frozen 语义不变）', () async {
      final SaveFile f = SaveFile();
      await f.wipe(fallback: SaveData(host: HostState.demo, goal: Goal.demo()));
      // wipe 后 frozen=true —— 存盘被静默跳过是**既有语义**，本测试不回退它；
      // 这里只锁「wipe 返回的 fallback 队列能安全喂给 QuestFlow」。
      final SaveData d = await f.wipe(fallback: SaveData(host: HostState.demo, goal: Goal.demo()));
      final QuestFlow flow = QuestFlow.fromSave(
        host: d.host,
        goal: d.goal,
        queue: d.queue,
      );
      expect(() => flow.seedForCurrentGoal(), returnsNormally);
      expect(flow.queue, isNotEmpty);
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
      expect(f.critChance(), closeTo(.12, 1e-9)); // .06 + 6×.01，0 证据不回归
      f.useItem('crit');
      expect(f.critChance(), closeTo(.37, 1e-9));
      for (int i = 0; i < 3; i++) {
        expect(f.addEvidence(shot('v$i', EvidenceStatus.verified)), isTrue);
      }
      expect(f.critChance(), closeTo(.58, 1e-9)); // .37 + 3×.07（已校验 7%/张）
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

  group('证据状态进结算（t14：已校验 7% / 未校验 4%，封顶 .85）', () {
    test('口径分档：1 已校验 + 1 未校验 = .06+.07+.04，不与底值双重计', () {
      final QuestFlow f = freshFlow(); // streak 0
      f.accept(eQuest);
      expect(f.addEvidence(shot('a', EvidenceStatus.verified)), isTrue);
      expect(f.addEvidence(shot('b', EvidenceStatus.unverified)), isTrue);
      expect(f.active!.verifiedCount, 1);
      expect(f.active!.unverifiedCount, 1);
      expect(f.critChance(), closeTo(.06 + .07 + .04, 1e-9));
      // 存疑按未校验计（exec_panel 同口径）
      expect(f.addEvidence(shot('c', EvidenceStatus.suspect)), isTrue);
      expect(f.critChance(), closeTo(.06 + .07 + .04 + .04, 1e-9));
    });

    test('settle 用的 chance 就是证据联动口径（进 QuestResult.chance）', () {
      final QuestFlow f = freshFlow();
      f.accept(eQuest);
      f.addEvidence(shot('a', EvidenceStatus.verified));
      f.addEvidence(shot('b', EvidenceStatus.unverified));
      final QuestResult? r = f.settle(forceCrit: false);
      expect(r!.photos, 2);
      expect(r.chance, closeTo(.17, 1e-9));
    });

    test('封顶 .85：证据计数喂爆也不会超（口径唯一真源 vision.critChance）', () {
      final QuestFlow f = freshFlow();
      f.accept(eQuest);
      expect(f.critChance(verified: 99, unverified: 99), .85);
    });

    test('addEvidence：最多 3 张（flows.js snap 的 >=3 拦截）；remove 按 id', () {
      final QuestFlow f = freshFlow();
      expect(f.addEvidence(shot('x', EvidenceStatus.unverified)), isFalse);
      f.accept(eQuest);
      for (int i = 0; i < QuestFlow.kMaxEvidence; i++) {
        expect(f.addEvidence(shot('s$i', EvidenceStatus.verified)), isTrue);
      }
      expect(f.addEvidence(shot('s9', EvidenceStatus.verified)), isFalse);
      expect(f.active!.photos, 3);
      expect(f.removeEvidence('s1'), isTrue);
      expect(f.active!.photos, 2);
      expect(f.removeEvidence('没有这张'), isFalse);
    });
  });

  group('换一个 retreat（store.js L235-250 全语义）', () {
    test('非 F 级：同一张单降一档重刻（serial 不变），六维按新档点数重分', () {
      final QuestFlow f = freshFlow(queue: <Quest>[dQuest]);
      final RetreatOutcome? o = f.retreat(dQuest, now: DateTime(2026, 1, 1, 9));
      expect(o, isNotNull);
      expect(o!.task.rank, 'D', reason: '旧档位留在 outcome.task');
      expect(o.replacement, isNotNull);
      expect(o.replacement!.rank, 'E', reason: 'rankShift(-1)：D → E');
      expect(
        o.replacement!.serial,
        dQuest.serial,
        reason: '同一张单重刻，不是换新单',
      );
      expect(o.replacement!.name, dQuest.name);
      expect(o.replacement!.minutes, dQuest.minutes);
      expect(
        attrSum(o.replacement!),
        Rarity.of('E').pt,
        reason: '六维按新档点数（E=1）重分',
      );
      expect(f.head?.rank, 'E');
      expect(f.queue.length, 1);
      expect(f.retreatedTimes(dQuest.serial), 1);
      expect(f.retreatToday, 1);
      expect(f.retreatTotal, 1);
    });

    test('F 级还退：换另一张 F 日常顶位（新 serial、F 档、1 点六维）', () {
      final QuestFlow f = freshFlow(queue: <Quest>[fQuest]);
      final RetreatOutcome? o = f.retreat(fQuest, now: DateTime(2026, 1, 1, 9));
      expect(o, isNotNull);
      final Quest? nt = o!.replacement;
      expect(nt, isNotNull, reason: '日常池不会空');
      expect(nt!.serial, isNot(fQuest.serial), reason: '换上来的是另一张单');
      expect(nt.rank, 'F', reason: 'F 还退不降档，换一张别的 F');
      expect(nt.kind, 'daily');
      expect(attrSum(nt), Rarity.of('F').pt);
      expect(nt.reason, isNotEmpty, reason: '换上的单要重新配一句附言');
      expect(f.head?.serial, nt.serial);
      expect(f.queue.length, 1);
      expect(f.retreatedTimes(fQuest.serial), 0, reason: '换单不算这张单的退缩次数');
    });

    test('跨日：retreatToday 归零重计，retreatTotal 继续累计', () {
      final QuestFlow f = freshFlow(queue: <Quest>[dQuest]);
      f.retreat(dQuest, now: DateTime(2026, 1, 1, 9)); // D→E（原地重刻）
      f.retreat(f.head!, now: DateTime(2026, 1, 1, 20)); // E→F（原地重刻）
      expect(f.retreatToday, 2);
      expect(f.retreatTotal, 2);
      f.retreat(f.head!, now: DateTime(2026, 1, 2, 9)); // 跨天：已是 F → 换一张
      expect(f.retreatToday, 1, reason: '当日计数跨天归零');
      expect(f.retreatTotal, 3, reason: '累计跨天继续涨');
    });

    test('不在她手里的单 → null，计数不动', () {
      final QuestFlow f = freshFlow(queue: <Quest>[dQuest]);
      expect(f.retreat(eQuest), isNull);
      expect(f.retreatToday, 0);
      expect(f.retreatTotal, 0);
    });

    test('累计退缩 ≥3 → 强制佩戴「口头巨人」（只触发一次）', () {
      final QuestFlow f = freshFlow(queue: <Quest>[cQuest]);
      final DateTime t = DateTime(2026, 1, 1, 9);
      expect(f.retreat(cQuest, now: t)!.shame, isFalse); // C→D
      expect(f.retreat(f.head!, now: t)!.shame, isFalse); // D→E
      final RetreatOutcome? third = f.retreat(f.head!, now: t); // E→F（原地）
      expect(third!.shame, isTrue);
      expect(third.count, 3);
      expect(f.host.ownedTitles, contains('mouth'));
      expect(f.host.title, 'mouth');
      expect(f.titleBeforeShame, 'bind');
      // 第 4 次：已经是 F → 换一张别的 F；已解锁过，不再触发
      final int before = f.head!.serial;
      final RetreatOutcome? fourth = f.retreat(f.head!, now: t);
      expect(fourth!.shame, isFalse);
      expect(fourth.replacement!.serial, isNot(before), reason: 'F 还退换成新单');
      expect(f.retreatTotal, 4);
      expect(f.host.ownedTitles.where((String t2) => t2 == 'mouth').length, 1);
    });
  });

  group('称号佩戴 equip（store.js L385）', () {
    test('未解锁 → false 忽略；已解锁 → 换挂 + 存档通知', () {
      final QuestFlow f = QuestFlow.demo(); // veteran 档：title = done15
      int saved = 0;
      f.onChanged = () => saved++;
      expect(f.equip('rankS'), isFalse, reason: '没解锁过的称号不认');
      expect(f.host.title, 'done15');
      expect(saved, 0, reason: '失败不发存档通知');
      expect(f.equip('first'), isTrue);
      expect(f.host.title, 'first');
      expect(saved, 1);
      expect(f.equip('done15'), isTrue, reason: '重复/换回也是成功（原型同款）');
      expect(f.host.title, 'done15');
      expect(saved, 2);
    });

    test('「口头巨人」生效中禁换挂（摘不掉，完成一单再说）', () {
      final QuestFlow f = freshFlow(queue: <Quest>[cQuest]);
      final DateTime t = DateTime(2026, 1, 1, 9);
      for (int i = 0; i < 3; i++) {
        f.retreat(f.head!, now: t);
      }
      expect(f.host.title, 'mouth');
      expect(f.equip('bind'), isFalse);
      expect(f.host.title, 'mouth', reason: '强制期里换挂一律拒绝');
    });

    test('强制期在交成一单后结束：换回称号，新称号照常解锁（store.js L311）', () {
      final QuestFlow f = freshFlow(queue: <Quest>[cQuest]);
      final DateTime t = DateTime(2026, 1, 1, 9);
      for (int i = 0; i < 3; i++) {
        f.retreat(f.head!, now: t);
      }
      expect(f.host.title, 'mouth');
      f.accept(f.head!, now: DateTime(2026, 1, 1, 10));
      final QuestResult? r = f.settle(
        now: DateTime(2026, 1, 1, 10, 30),
        forceCrit: false,
      );
      expect(r, isNotNull);
      expect(f.host.title, 'first', reason: '强制期结束换回，再戴上本次解锁的 first');
      expect(f.titleBeforeShame, isNull);
      expect(f.host.ownedTitles, containsAll(<String>['mouth', 'first']));
    });
  });

  group('补给 buy（store.js L380-384）', () {
    test('买得起：扣金币 + 道具 +1 + 存档通知；买不起：false 且分文不动', () {
      final QuestFlow f = freshFlow(host: HostState.empty.copyWith(coins: 100));
      int saved = 0;
      f.onChanged = () => saved++;
      expect(f.buy('dbl'), isTrue); // 双倍卡 60
      expect(f.host.coins, 40);
      expect(f.host.items['dbl'], 1);
      expect(saved, 1);
      expect(f.buy('crit'), isFalse, reason: '暴击芯片 45 > 40 买不起');
      expect(f.host.coins, 40);
      expect(f.host.items['crit'], 0);
      expect(saved, 1, reason: '失败不发存档通知');
      expect(f.buy('不存在的道具'), isFalse);
    });

    test('金币原样不够就false：边界正好等于价格 → 买得起', () {
      final QuestFlow f = freshFlow(host: HostState.empty.copyWith(coins: 30));
      expect(f.buy('swap'), isTrue, reason: '换单券 30 = 30');
      expect(f.host.coins, 0);
      expect(f.host.items['swap'], 1);
    });
  });

  group('接口与 t10 装配对齐', () {
    test('sheet/plate 的回调形状能直接接上（ValueChanged<String> / retreat）', () {
      final QuestFlow f = QuestFlow.demo();
      // Sheet.onEquipTitle / onBuyItem 都是 ValueChanged<String>
      final void Function(String) onEquip = f.equip;
      final void Function(String) onBuy = f.buy;
      onEquip('crit'); // demo 档已解锁 crit → 换挂
      expect(f.host.title, 'crit');
      onBuy('shield'); // 340 ≥ 90 → 真买
      expect(f.host.items['shield'], HostState.demo.items['shield']! + 1);
      // PlateAlt.onPick 是 ValueChanged<int>：main.dart 侧 idx==0 → retreat(head)
      final RetreatOutcome? o = f.retreat(f.head!);
      expect(o, isNotNull);
      expect(o!.replacement?.rank, 'D', reason: 'demo 队首 C → 降一档 D');
    });
  });

  group('执行中单据持久化（t16/B3：接单后杀进程，任务/计时起点/证据保持）', () {
    test('activeToSaveJson / restoreActiveFromJson：任务/起点/道具/证据全保持', () {
      final QuestFlow f = freshFlow();
      f.accept(eQuest, now: DateTime(2026, 1, 1, 10));
      expect(f.useItem('dbl'), isTrue);
      f.active!.evidence.add(shot('ev1', EvidenceStatus.verified));

      final Map<String, dynamic>? json = f.activeToSaveJson();
      expect(json, isNotNull);
      expect(json!['startAt'], '2026-01-01T10:00:00.000');
      expect(json['dbl'], true);

      final QuestFlow g = freshFlow();
      g.restoreActiveFromJson(json);
      expect(g.active, isNotNull);
      expect(g.active!.task.serial, eQuest.serial);
      expect(g.active!.startAt, DateTime(2026, 1, 1, 10));
      expect(g.active!.dbl, isTrue);
      expect(g.active!.crit, isFalse);
      expect(g.active!.verifiedCount, 1);
      expect(g.active!.photos, 1);
    });

    test('SaveData 往返带上 active（datastore 形态）', () {
      final QuestFlow f = freshFlow();
      f.accept(eQuest, now: DateTime(2026, 1, 1, 10));
      f.active!.evidence.add(shot('ev2', EvidenceStatus.unverified));
      final SaveData d = SaveData(
        host: f.host,
        goal: f.goal,
        queue: f.queue,
        activeJson: f.activeToSaveJson(),
      );
      final SaveData back = SaveData.fromJson(d.toJson(), fallback: SaveData.fresh());
      expect(back.activeJson, isNotNull);
      final QuestFlow g = freshFlow();
      g.restoreActiveFromJson(back.activeJson);
      expect(g.active?.task.serial, eQuest.serial);
      expect(g.active!.photos, 1);
    });

    test('restore 后计时按 startAt 推导：杀进程重启计时不归零', () {
      final QuestFlow f = freshFlow();
      f.accept(eQuest, now: DateTime(2026, 1, 1, 10));
      final Map<String, dynamic>? json = f.activeToSaveJson();
      final QuestFlow g = freshFlow();
      g.restoreActiveFromJson(json);
      final QuestResult? r = g.settle(
        now: DateTime(2026, 1, 1, 10, 30),
        forceCrit: false,
      );
      expect(r!.held, const Duration(minutes: 30), reason: '计时起点随档恢复');
    });

    test('restoreActiveFromJson(null/坏形状) 静默忽略（合并式迁移口径）', () {
      final QuestFlow f = freshFlow();
      f.restoreActiveFromJson(null);
      expect(f.active, isNull);
      f.restoreActiveFromJson(<String, dynamic>{'task': '不是 map'});
      expect(f.active, isNull);
      f.restoreActiveFromJson(<String, dynamic>{});
      expect(f.active, isNull);
    });
  });

  group('暴击率单一真源（t16/B4：显示口径不得双计证据加成）', () {
    test('critBase 不含证据加成；critChance = critBase + evidenceCritBonus', () {
      final QuestFlow f = freshFlow(); // streak 0，底值 6%
      f.accept(eQuest);
      f.active!.evidence.add(shot('v1', EvidenceStatus.verified));
      f.active!.evidence.add(shot('u1', EvidenceStatus.unverified));

      final double base = f.critBase();
      expect(base, closeTo(.06, 1e-9), reason: '底值不含证据/连击以外的任何项');
      final double full = f.critChance();
      expect(full, closeTo(.06 + .07 + .04, 1e-9));
      expect(
        full,
        closeTo(base + evidenceCritBonus(verified: 1, unverified: 1), 1e-9),
        reason: '显示口径 = 底值 + 证据加成，只能加一次',
      );
    });

    test('暴击芯片在底值里；封顶 85% 由公式兜住', () {
      final QuestFlow f = freshFlow();
      f.accept(eQuest);
      f.useItem('crit');
      expect(f.critBase(), closeTo(.31, 1e-9)); // .06 + .25
      f.active!.evidence
        ..add(shot('a', EvidenceStatus.verified))
        ..add(shot('b', EvidenceStatus.verified))
        ..add(shot('c', EvidenceStatus.verified));
      // .31 + 3×.07 = .52（未到封顶；封顶 .85 由 vision.critChance 的 min 兜住，
      // 这里验证的是「底值+证据加成 = 全量」这一口径不被双计突破）
      expect(f.critChance(), closeTo(.52, 1e-9));
      expect(
        f.critChance(),
        closeTo(f.critBase() + evidenceCritBonus(verified: 3, unverified: 0), 1e-9),
      );
    });
  });
}
