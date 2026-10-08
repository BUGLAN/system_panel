import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/host_state.dart';
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
      expect(back.goal.rings.length, 8);
      expect(back.goal.currentIndex, 4);
    });

    test('环的三种状态与用时都能回来', () async {
      await SaveFile().save(sample());
      final SaveData back = await SaveFile().load();
      final List<GoalRing> r = back.goal.rings;
      expect(r[0].state, RingState.done);
      expect(r[0].held, const Duration(minutes: 11, seconds: 56));
      expect(r[4].state, RingState.cur);
      expect(r[7].state, RingState.lock);
      expect(r[7].finalRing, isTrue);
    });

    test('没有档就给默认（首次启动）', () async {
      final SaveData d = await SaveFile().load(
        fallback: SaveData(host: HostState.demo, goal: Goal.demo()),
      );
      expect(d.host.name, HostState.demo.name);
      expect(d.goal.rings.length, 8);
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

    test('未绑定 = 没有目标也没有环', () {
      final SaveData d = SaveData.fresh();
      expect(d.host.lv, 1);
      expect(d.goal.isEmpty, isTrue);
      expect(d.goal.rings, isEmpty);
    });
  });

  group('宿主档案本身', () {
    test('升到下一级要的经验（store.js L5）', () {
      expect(HostState.need(1), 100);
      expect(HostState.need(7), 340);
      expect(HostState.demo.expRatio, closeTo(214 / 340, 1e-9));
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
}
