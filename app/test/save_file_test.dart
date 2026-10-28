import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/host_state.dart';
import 'package:system_panel/state/quest_flow.dart';
import 'package:system_panel/state/save_file.dart';

/// 存档（`store.js` L4 / L34-52）。
///
/// 三条要钉住的：
///  1. **在默认值上合并** —— 缺字段走默认，这是老存档的迁移方式
///  2. 读坏了要能兜住，不能把 App 带崩
///  3. `wipe()` 之后要**冻结**，否则"重置"当场被覆盖
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 每个用例一块干净的内存存储（SharedPreferencesAsync 走的是新平台接口，
  /// SharedPreferences.setMockInitialValues 只对旧的 legacy API 生效）
  void resetStore([Map<String, Object> seed = const <String, Object>{}]) {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(Map<String, Object>.from(seed));
  }

  setUp(resetStore);

  SaveData sample() => SaveData(
    host: HostState.demo.copyWith(name: '测试宿主', coins: 999, lv: 9),
    goal: Goal.demo().copyWith(text: '一个月早睡早起', short: '早睡早起'),
  );

  group('存取往返', () {
    test('存进去再读出来，逐字段一致', () async {
      final SaveFile f = SaveFile();
      await f.save(sample());
      final SaveData back = await SaveFile().load();

      expect(back.host.name, '测试宿主');
      expect(back.host.coins, 999);
      expect(back.host.lv, 9);
      expect(back.host.attrs, HostState.demo.attrs);
      expect(back.host.items, HostState.demo.items);
      expect(back.host.ownedTitles, HostState.demo.ownedTitles);
      expect(back.goal.text, '一个月早睡早起');
      expect(back.goal.short, '早睡早起');
      expect(back.goal.plan.length, 8);
      expect(back.goal.firstOpenIndex, 4);
    });

    test('计划单的状态与用时都能回来', () async {
      await SaveFile().save(sample());
      final SaveData back = await SaveFile().load();
      final List<PlanTask> r = back.goal.plan;
      expect(r[0].state, PlanState.done);
      expect(r[0].held, const Duration(minutes: 11, seconds: 56));
      expect(r[4].state, PlanState.active);
      expect(r[7].state, PlanState.todo);
      expect(r[7].finalTask, isTrue);
    });

    test('没有档就给默认（首次启动）', () async {
      final SaveData d = await SaveFile().load(
        fallback: SaveData(host: HostState.demo, goal: Goal.demo()),
      );
      expect(d.host.name, HostState.demo.name);
      expect(d.goal.plan.length, 8);
    });
  });

  group('迁移：在默认值上合并', () {
    test('存档里缺的字段走默认值（老档新增字段不会崩）', () async {
      // 只写了名字和一个金币数，其余全缺 —— 模拟旧版本存档
      resetStore(<String, Object>{
        SaveFile.key: jsonEncode(<String, dynamic>{
          'host': <String, dynamic>{'name': '老档', 'coins': 7},
          'goal': Goal.demo().toJson(),
        }),
      });
      final SaveData d = await SaveFile().load(
        fallback: SaveData(host: HostState.demo, goal: Goal.demo()),
      );
      expect(d.host.name, '老档');
      expect(d.host.coins, 7);
      expect(d.host.lv, HostState.demo.lv); // 缺 → 默认
      expect(d.host.attrs, HostState.demo.attrs);
      expect(d.host.items, HostState.demo.items);
    });

    test('类型不对的字段也走默认（不抛）', () async {
      resetStore(<String, Object>{
        SaveFile.key: jsonEncode(<String, dynamic>{
          'host': <String, dynamic>{'lv': '这不是数字', 'coins': 3},
        }),
      });
      final SaveData d = await SaveFile().load(
        fallback: SaveData(host: HostState.demo, goal: Goal.demo()),
      );
      expect(d.host.lv, HostState.demo.lv);
      expect(d.host.coins, 3);
    });

    test('整个档读坏了也不崩', () async {
      resetStore(<String, Object>{SaveFile.key: '{这不是合法 JSON'});
      final SaveData d = await SaveFile().load(
        fallback: SaveData(host: HostState.demo, goal: Goal.demo()),
      );
      expect(d.host.name, HostState.demo.name);
    });

    test('存的是数组不是对象，也兜住', () async {
      resetStore(<String, Object>{SaveFile.key: '[1,2,3]'});
      final SaveData d = await SaveFile().load(
        fallback: SaveData(host: HostState.empty, goal: Goal.empty()),
      );
      expect(d.host.name, HostState.empty.name);
    });
  });

  group('重置', () {
    test('wipe 清掉档并冻结 —— 之后 save 不会再写回去', () async {
      final SaveFile f = SaveFile();
      await f.save(sample());
      expect(f.frozen, isFalse);

      final SaveData d = await f.wipe(fallback: SaveData.fresh());
      expect(f.frozen, isTrue);
      expect(d.host.name, HostState.empty.name);

      await f.save(sample()); // 冻结后这次写入应被忽略
      final SaveData back = await SaveFile().load();
      expect(back.host.name, HostState.empty.name);
    });

    test('未绑定 = 没有目标也没有计划单', () {
      final SaveData d = SaveData.fresh();
      expect(d.host.lv, 1);
      expect(d.goal.isEmpty, isTrue);
      expect(d.goal.plan, isEmpty);
    });
  });

  group('宿主档案本身', () {
    test('升到下一级要的经验 = Rewards 曲线（旧 60+lv*40 已废，t24）', () {
      expect(HostState.need(1), 18);
      expect(HostState.need(7), 54);
      // 演示档余额 38 < need(7)=54（旧值 214 会让第一单连升三级）
      expect(HostState.demo.expRatio, closeTo(38 / 54, 1e-9));
    });

    test('最弱的一维是最小的那个', () {
      expect(HostState.demo.weakest.key, '魅');
      expect(HostState.demo.weakest.value, 4);
    });

    test('copyWith 不动没传的字段', () {
      final HostState h = HostState.demo.copyWith(coins: 1);
      expect(h.coins, 1);
      expect(h.name, HostState.demo.name);
      expect(h.attrs, HostState.demo.attrs);
    });
  });
  group('冻结与解冻', () {
    test('重置后解冻，新的一次绑定能存进去（原型靠 reload 解冻）', () async {
      final SaveFile f = SaveFile();
      await f.save(sample());
      await f.wipe(fallback: SaveData.fresh());
      expect(f.frozen, isTrue);

      await f.save(sample()); // 冻结中，应被跳过
      expect((await f.load()).goal.text, '');

      f.unfreeze(); // 绑定那一刻解冻
      await f.save(sample().copyWith(goal: Goal.demo().copyWith(text: '考研上岸')));
      expect((await f.load()).goal.text, '考研上岸');
    });
  });
  group('lastSeen（回来时算"你走了多久"用）', () {
    test('存盘时自动盖上时间戳，读回来还在', () async {
      final SaveFile f = SaveFile();
      final DateTime before = DateTime.now().subtract(
        const Duration(seconds: 2),
      );
      await f.save(sample());
      final SaveData back = await f.load();
      expect(back.lastSeen, isNotNull);
      expect(back.lastSeen!.isAfter(before), isTrue);
      // 存档里没写 lastSeen 时不能崩
      resetStore(<String, Object>{SaveFile.key: '{"host":{"name":"没时间戳"}}'});
      final SaveData two = await SaveFile().load();
      expect(two.lastSeen, isNull);
      expect(two.host.name, '没时间戳');
    });

    test('时间戳格式不对也兜住', () async {
      resetStore(<String, Object>{SaveFile.key: '{"lastSeen":"不是时间"}'});
      final SaveData d = await SaveFile().load();
      expect(d.lastSeen, isNull);
    });
  });

  group('HistoryLog（opus-v2/history/v1 · A6）', () {
    HistoryEntry entry(
      DateTime at, {
      String result = 'clear',
      String rank = 'E',
      Map<String, int> attrs = const <String, int>{'体': 1},
      int exp = 1,
      int coin = 5,
      int streak = 1,
    }) => HistoryEntry(
      at: at,
      name: '测试单',
      rank: rank,
      kind: 'daily',
      exp: exp,
      coin: coin,
      streak: streak,
      result: result,
      attrs: attrs,
    );

    test('append → entries 往返，坏档回空表', () async {
      final HistoryLog log = HistoryLog();
      await log.append(entry(DateTime(2026, 3, 1, 9)));
      await log.append(
        entry(DateTime(2026, 3, 2, 9), result: 'quit', exp: 0, coin: 0),
      );
      final HistoryLog back = HistoryLog();
      final List<HistoryEntry> all = await back.entries();
      expect(all, hasLength(2));
      expect(all[0].result, 'clear');
      expect(all[1].result, 'quit');
      // 坏档
      resetStore(<String, Object>{HistoryLog.key: '{oops'});
      expect(await HistoryLog().entries(), isEmpty);
    });

    test('滚动上限 400：满了删最旧', () async {
      final HistoryLog log = HistoryLog();
      for (int i = 0; i < HistoryLog.maxEntries + 6; i++) {
        await log.append(entry(DateTime(2026, 1, 1).add(Duration(minutes: i))));
      }
      final List<HistoryEntry> all = await log.entries();
      expect(all.length, HistoryLog.maxEntries);
    });

    test('summarize：7 日窗口 / 完成数 / 出账 / 连击峰 / 六维日增量', () {
      final DateTime now = DateTime(2026, 3, 8, 12);
      final List<HistoryEntry> all = <HistoryEntry>[
        // 窗口外（8 天前）：不进任何聚合
        entry(now.subtract(const Duration(days: 8)), streak: 9),
        // 窗口内
        entry(
          now.subtract(const Duration(days: 1)),
          exp: 2,
          coin: 5,
          streak: 2,
          attrs: const <String, int>{'体': 2},
        ),
        entry(
          now.subtract(const Duration(days: 1)),
          result: 'quit',
          exp: 0,
          coin: 0,
          streak: 2,
          attrs: const <String, int>{}, // 认输不出账也不出属性
        ),
        entry(
          now,
          exp: 4,
          coin: 5,
          streak: 3,
          attrs: const <String, int>{'知': 1},
        ),
      ];
      final WeekSummary s = HistoryLog.summarize(all, now);
      expect(s.doneCount, 2); // quit 不算完成
      expect(s.totalExp, 6);
      expect(s.totalCoin, 10);
      expect(s.bestStreak, 3);
      expect(s.dayDone[6], 1); // 今天 1 单
      expect(s.dayDone[5], 1); // 昨天 1 单
      expect(s.dayAttrs['体'], 2);
      expect(s.dayAttrs['知'], 1);
      // 逐日列：昨天体+2（只有那一列有），今天知+1
      expect(s.dayAttrsByDay[5]['体'], 2);
      expect(s.dayAttrsByDay[5]['知'], isNull);
      expect(s.dayAttrsByDay[6]['知'], 1);
      expect(s.dayAttrsByDay[6]['体'], isNull);
      expect(s.dayAttrsByDay[0], isEmpty); // 6 天前无记录
      // recent = 全部记录的最近 ≤8 条（不限 7 日窗口），新 → 旧
      expect(s.recent.length, 4);
      expect(s.recent.first.at.day, 8); // 最新 = 今天那条
      expect(s.recent.last.at.day, 28); // 最旧 = 8 天前那条
    });

    test('summarize：空表全零（首日不裸奔）', () {
      final WeekSummary s = HistoryLog.summarize(
        const <HistoryEntry>[],
        DateTime(2026, 3, 8, 12),
      );
      expect(s.doneCount, 0);
      expect(s.totalExp, 0);
      expect(s.totalCoin, 0);
      expect(s.bestStreak, 0);
      expect(s.dayDone.every((int v) => v == 0), isTrue);
      expect(s.recent, isEmpty);
    });
  });
}
