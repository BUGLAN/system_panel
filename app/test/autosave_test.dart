import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:system_panel/agent/vision.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/host_state.dart';
import 'package:system_panel/state/quest.dart';
import 'package:system_panel/state/quest_flow.dart';

/// 自动存档契约：QuestFlow 每个改了存档字段（host / goal / queue / active /
/// pendingGoal）的公开方法，成功后都要发 [QuestFlow.onChanged]。
///
/// main.dart 把 onChanged 接到合并写盘，调用点不再手写 `_persist()` ——
/// 所以这里漏一处，就是 docs/50 E1.1 那类「杀进程丢单」。
void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  const Quest daily = Quest(
    serial: 900,
    kind: 'daily',
    planIndex: -1,
    planTotal: 0,
    name: '出门走 3000 步',
    reason: '',
    proof: '步数截图',
    minutes: 30,
    rank: 'D',
    attrs: <String, int>{'体': 1},
  );

  EvidenceShot shot(String id) => EvidenceShot(
    id: id,
    path: 'evidence/q900/$id.jpg',
    status: EvidenceStatus.unverified,
    takenAt: DateTime(2026, 1, 1, 10),
  );

  late int saves;
  QuestFlow flow({List<Quest> queue = const <Quest>[daily]}) {
    saves = 0;
    final QuestFlow f = QuestFlow(
      host: HostState.empty.copyWith(
        coins: 500,
        items: <String, int>{'dbl': 1, 'crit': 1, 'shield': 1, 'patch': 1},
      ),
      goal: Goal.demo(),
      queue: queue,
      serial: 1000,
      rnd: math.Random(7),
    );
    f.onChanged = () => saves++;
    return f;
  }

  test('接单就通知（E1.1：接单后杀进程不丢单）', () {
    final QuestFlow f = flow();
    f.accept(daily, now: DateTime(2026, 1, 1, 10));
    expect(saves, greaterThan(0));
  });

  test('用道具 / 加证据 / 落校验结论 / 撤证据都通知', () {
    final QuestFlow f = flow();
    f.accept(daily, now: DateTime(2026, 1, 1, 10));

    saves = 0;
    expect(f.useItem('dbl'), isTrue);
    expect(saves, greaterThan(0));

    saves = 0;
    expect(f.addEvidence(shot('a')), isTrue);
    expect(saves, greaterThan(0));

    saves = 0;
    f.applyVerdict('a', const VisionVerdict.verified(''));
    expect(saves, greaterThan(0));

    saves = 0;
    expect(f.removeEvidence('a'), isTrue);
    expect(saves, greaterThan(0));
  });

  test('失败的操作不通知', () {
    final QuestFlow f = flow();
    expect(f.useItem('dbl'), isFalse, reason: '没接单');
    expect(f.removeEvidence('nope'), isFalse);
    expect(f.addEvidence(shot('x')), isFalse);
    expect(saves, 0);
  });

  test('认输 + 领补救单都通知', () {
    final QuestFlow f = flow();
    f.accept(daily, now: DateTime(2026, 1, 1, 10));

    saves = 0;
    expect(f.fail(now: DateTime(2026, 1, 1, 10, 5)), isNotNull);
    expect(saves, greaterThan(0));

    saves = 0;
    expect(f.takeRemedy(), isNotNull);
    expect(saves, greaterThan(0));
  });

  test('结算走完才通知（不把中间态写进档）', () async {
    final QuestFlow f = flow();
    f.accept(daily, now: DateTime(2026, 1, 1, 10));
    saves = 0;
    await f.settle(now: DateTime(2026, 1, 1, 10, 30), forceCrit: false);
    expect(saves, greaterThan(0));
  });

  test('补发计划单 / touch 都通知', () {
    final QuestFlow f = flow(queue: const <Quest>[]);
    f.publishPlanTasks();
    expect(saves, greaterThan(0), reason: 'demo 目标有清单，补发了就要落盘');

    saves = 0;
    f.touch();
    expect(saves, 1);
  });
}
