import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/host_state.dart';
import 'package:system_panel/state/save_file.dart';

/// G1.1 坏档保护：原来读坏 = 静默空白档，读档后第一次自动存档就把坏档覆盖。
///
/// 要钉住的：
///  1. 坏主档 → 原串先另存 `.corrupt`，再退回 `.bak`；bak 也不行才空白档
///  2. 每次存盘前把上一份**好档**滚进 bak（坏档绝不进 bak）
///  3. 从 bak 恢复后，下一次存盘把好数据写回主档
///  4. wipe 把 bak / corrupt 一并删，重置后的档不会从 bak 复活
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void resetStore([Map<String, Object> seed = const <String, Object>{}]) {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(Map<String, Object>.from(seed));
  }

  setUp(resetStore);

  Future<String?> raw(String k) => SharedPreferencesAsync().getString(k);

  SaveData named(String name) => SaveData(
    host: HostState.empty.copyWith(name: name, coins: 7),
    goal: Goal.demo().copyWith(text: '$name 的主线'),
  );

  /// 原串里的宿主名（bak / corrupt 只存串，按 JSON 读一下）
  String? hostNameOf(String? s) {
    if (s == null) return null;
    final Object? j = jsonDecode(s);
    return ((j as Map<String, dynamic>)['host'] as Map<String, dynamic>)['name']
        as String?;
  }

  const String broken = '{"host":{"name":"写了一半';

  test('正常存两次 → bak 是第一次的内容，主档是第二次', () async {
    final SaveFile f = SaveFile();
    await f.save(named('第一次'));
    expect(await raw(SaveFile.bakKey), isNull, reason: '第一次存盘前没有好档可滚');
    await f.save(named('第二次'));
    expect(hostNameOf(await raw(SaveFile.bakKey)), '第一次');
    expect(hostNameOf(await raw(SaveFile.key)), '第二次');

    final SaveLoad back = await SaveFile().loadDetailed();
    expect(back.source, SaveSource.primary);
    expect(back.data.host.name, '第二次');
  });

  test('跨启动：读到的好档在本次第一次存盘时滚进 bak', () async {
    await SaveFile().save(named('上次启动'));
    final SaveFile f = SaveFile(); // 新实例 = 新一次启动
    expect((await f.loadDetailed()).source, SaveSource.primary);
    await f.save(named('这次启动'));
    expect(hostNameOf(await raw(SaveFile.bakKey)), '上次启动');
  });

  test('坏主档 → 从 bak 恢复；原串另存 corrupt；下次存盘把好数据写回主档', () async {
    final SaveFile w = SaveFile();
    await w.save(named('好档 A'));
    await w.save(named('好档 B')); // bak = A
    // 模拟主档被写坏（写一半 / 存储损坏）
    await SharedPreferencesAsync().setString(SaveFile.key, broken);

    final SaveFile f = SaveFile();
    final SaveLoad got = await f.loadDetailed(fallback: SaveData.fresh());
    expect(got.source, SaveSource.backup);
    expect(got.data.host.name, '好档 A');
    expect(got.data.goal.text, '好档 A 的主线');
    expect(await raw(SaveFile.corruptKey), broken, reason: '原串在任何覆盖之前留底');

    // 恢复后的第一次存盘：主档写回好数据；bak 里已是好档 A，不重滚
    await f.save(got.data.copyWith(host: got.data.host.copyWith(coins: 99)));
    final SaveLoad again = await SaveFile().loadDetailed();
    expect(again.source, SaveSource.primary);
    expect(again.data.host.name, '好档 A');
    expect(again.data.host.coins, 99);
    expect(hostNameOf(await raw(SaveFile.bakKey)), '好档 A');
    // 坏档绝不进 bak
    expect(await raw(SaveFile.bakKey), isNot(broken));
  });

  test('坏主档且无 bak → 空白档、source=corrupt，corrupt 存了原串', () async {
    resetStore(<String, Object>{SaveFile.key: broken});
    final SaveFile f = SaveFile();
    final SaveLoad got = await f.loadDetailed(fallback: SaveData.fresh());
    expect(got.source, SaveSource.corrupt);
    expect(got.data.host.name, HostState.empty.name);
    expect(got.data.goal.isEmpty, isTrue);
    expect(await raw(SaveFile.corruptKey), broken);

    // 之后的自动存档覆盖主档：坏串不会被滚进 bak，corrupt 里的原串还在
    await f.save(named('新绑定'));
    expect(await raw(SaveFile.bakKey), isNull);
    expect(await raw(SaveFile.corruptKey), broken);
    expect((await SaveFile().load()).host.name, '新绑定');
  });

  test('不是对象 / fromJson 抛异常也算坏档（走 bak）', () async {
    final SaveFile w = SaveFile();
    await w.save(named('好档'));
    await w.save(named('最新'));
    for (final String bad in <String>['[1,2,3]', 'null', '"字符串"']) {
      await SharedPreferencesAsync().setString(SaveFile.key, bad);
      final SaveLoad got = await SaveFile().loadDetailed();
      expect(got.source, SaveSource.backup, reason: bad);
      expect(got.data.host.name, '好档', reason: bad);
      expect(await raw(SaveFile.corruptKey), bad);
    }
  });

  test('主档是空串（截断）→ 走 bak；空串不另存 corrupt', () async {
    final SaveFile w = SaveFile();
    await w.save(named('好档'));
    await w.save(named('最新'));
    await SharedPreferencesAsync().setString(SaveFile.key, '');
    final SaveLoad got = await SaveFile().loadDetailed();
    expect(got.source, SaveSource.backup);
    expect(got.data.host.name, '好档');
    expect(await raw(SaveFile.corruptKey), isNull);
  });

  test('bak 也坏 → 空白档、source=corrupt', () async {
    resetStore(<String, Object>{SaveFile.key: broken, SaveFile.bakKey: '{也坏了'});
    final SaveLoad got = await SaveFile().loadDetailed(
      fallback: SaveData.fresh(),
    );
    expect(got.source, SaveSource.corrupt);
    expect(got.data.goal.isEmpty, isTrue);
  });

  test('没有主档 = 没有档，不去翻 bak（不复活旧档）', () async {
    resetStore(<String, Object>{
      SaveFile.bakKey: jsonEncode(named('旧档').toJson()),
    });
    final SaveLoad got = await SaveFile().loadDetailed(
      fallback: SaveData.fresh(),
    );
    expect(got.source, SaveSource.none);
    expect(got.data.host.name, HostState.empty.name);
  });

  test('load() 照旧只给数据（坏档同样退回 bak）', () async {
    final SaveFile w = SaveFile();
    await w.save(named('好档'));
    await w.save(named('最新'));
    await SharedPreferencesAsync().setString(SaveFile.key, broken);
    expect((await SaveFile().load()).host.name, '好档');
  });

  test('wipe 后 bak / corrupt 也没了；重新绑定后的第一次存盘不把旧档滚进 bak', () async {
    final SaveFile f = SaveFile();
    await f.save(named('旧档 A'));
    await f.save(named('旧档 B'));
    await SharedPreferencesAsync().setString(SaveFile.corruptKey, broken);
    expect(await raw(SaveFile.bakKey), isNotNull);

    await f.wipe(fallback: SaveData.fresh());
    expect(f.frozen, isTrue);
    expect(await raw(SaveFile.key), isNull);
    expect(await raw(SaveFile.bakKey), isNull);
    expect(await raw(SaveFile.corruptKey), isNull);
    expect((await SaveFile().loadDetailed()).source, SaveSource.none);

    // 冻结语义不变：解冻前的存盘被跳过
    await f.save(named('冻结中'));
    expect(await raw(SaveFile.key), isNull);

    f.unfreeze();
    await f.save(named('新宿主'));
    expect(await raw(SaveFile.bakKey), isNull, reason: '旧档 B 不能借内存记录复活进 bak');
    expect((await SaveFile().load()).host.name, '新宿主');
  });
}
