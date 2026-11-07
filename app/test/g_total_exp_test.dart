import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/host_state.dart';
import 'package:system_panel/state/quest.dart';
import 'package:system_panel/state/quest_flow.dart';
import 'package:system_panel/state/result.dart';
import 'package:system_panel/state/save_file.dart';

/// G3.1 档案「累计 EXP」不倒退。
///
/// 原来档案页拿执行历史流水求和，流水只留最近 [HistoryLog.maxEntries] 条，
/// 满了再结算最旧的被挤掉 —— 累计值变小。现在 [HostState.totalExp] 单独存、
/// 只在结算处累加；老档缺字段 → 读档后用流水补一次（与等级下界取大）并落盘。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  int serial = 5000;
  Quest daily(String rank) => Quest(
    serial: serial++,
    kind: 'daily',
    planIndex: -1,
    planTotal: 0,
    name: '出门走 3000 步',
    reason: '',
    proof: '步数截图',
    minutes: 30,
    rank: rank,
    attrs: const <String, int>{'体': 1},
  );

  HistoryEntry clear(int exp, DateTime at) => HistoryEntry(
    at: at,
    name: '老单',
    rank: 'C',
    kind: 'daily',
    exp: exp,
    coin: 5,
    streak: 1,
    result: 'clear',
  );

  /// 接一张单、钉死不暴击地结算掉
  Future<QuestResult> settleOne(QuestFlow f, Quest q, DateTime t0) {
    f.accept(q, now: t0);
    return f.settle(now: t0.add(const Duration(minutes: 31)), forceCrit: false);
  }

  group('HostState 字段与迁移标记', () {
    test('新宿主 / 重置后从 0 记起（已知值，不走迁移）', () {
      expect(HostState.empty.totalExp, 0);
      expect(HostState.empty.totalExpKnown, isTrue);
      expect(SaveData.fresh().host.totalExp, 0);
    });

    test('演示档的累计 = 等级下界（LV7 余额 38 → 236）', () {
      expect(HostState.demo.totalExp, HostState.expFloor(7, 38));
      expect(HostState.expFloor(7, 38), 236);
      expect(HostState.expFloor(1, 0), 0);
      expect(HostState.expFloor(3, 2), 18 + 24 + 2);
    });

    test('老档缺字段 → 未知（不当 0、也不取 fallback 冒名）', () {
      final HostState h = HostState.fromJson(<String, dynamic>{
        'name': '老档',
        'lv': 3,
      }, fallback: HostState.demo);
      expect(h.totalExpKnown, isFalse);
      expect(h.totalExp, HostState.kTotalExpUnknown);
      // 未知不写进档：下次读档仍是「缺字段」，迁移还会补
      expect(h.toJson().containsKey('totalExp'), isFalse);
    });

    test('有值就读值；负数 / 类型不对按未知', () {
      HostState of(Object v) => HostState.fromJson(<String, dynamic>{
        'totalExp': v,
      }, fallback: HostState.empty);
      expect(of(321).totalExp, 321);
      expect(of(-5).totalExpKnown, isFalse);
      expect(of('12').totalExpKnown, isFalse);
    });

    test('存档往返保留累计 EXP', () async {
      final SaveFile f = SaveFile();
      await f.save(
        SaveData(
          host: HostState.empty.copyWith(totalExp: 777),
          goal: Goal.empty(),
        ),
      );
      expect((await SaveFile().load()).host.totalExp, 777);
    });
  });

  group('结算入账', () {
    test('每单累加最终入账（含暴击/双倍）；升级扣余额、累计不扣', () async {
      final QuestFlow f = QuestFlow(
        host: HostState.empty,
        goal: Goal.empty(),
        serial: 9000,
        rnd: math.Random(3),
      );
      int sum = 0;
      final DateTime t0 = DateTime(2026, 3, 1, 9);
      for (int i = 0; i < 6; i++) {
        final QuestResult r = await settleOne(
          f,
          daily('S'),
          t0.add(Duration(hours: i)),
        );
        sum += r.exp;
        expect(f.host.totalExp, sum);
      }
      expect(f.host.lv, greaterThan(1), reason: '6 张 S 单（60 EXP）至少升过一级');
      expect(f.host.exp, lessThan(sum), reason: '余额被升级扣过');
      expect(f.host.totalExp, HostState.expFloor(f.host.lv, f.host.exp));

      // 暴击 ×2 也照最终入账累加
      f.accept(daily('A'), now: t0.add(const Duration(days: 1)));
      final QuestResult crit = await f.settle(
        now: t0.add(const Duration(days: 1, minutes: 40)),
        forceCrit: true,
      );
      expect(crit.exp, 16);
      expect(f.host.totalExp, sum + 16);
    });

    test('认输不出账、累计不变', () {
      final QuestFlow f = QuestFlow(
        host: HostState.empty.copyWith(totalExp: 40),
        goal: Goal.empty(),
        serial: 9100,
      );
      f.accept(daily('C'), now: DateTime(2026, 3, 1, 9));
      f.fail(now: DateTime(2026, 3, 1, 10));
      expect(f.host.totalExp, 40);
    });

    test('超过 400 条流水后累计也不倒退（流水求和会倒退）', () async {
      final HistoryLog log = HistoryLog();
      final QuestFlow f = QuestFlow(
        host: HostState.empty,
        goal: Goal.empty(),
        serial: 10000,
        rnd: math.Random(5),
        historyLog: log,
      );
      final int n = HistoryLog.maxEntries + 12;
      int sum = 0;
      int prev = 0;
      final DateTime t0 = DateTime(2026, 1, 1, 8);
      for (int i = 0; i < n; i++) {
        // 头 12 单是高价 S 单：它们会先被挤出流水，求和口径一定倒退
        final QuestResult r = await settleOne(
          f,
          daily(i < 12 ? 'S' : 'E'),
          t0.add(Duration(hours: i)),
        );
        sum += r.exp;
        expect(f.host.totalExp, greaterThanOrEqualTo(prev));
        prev = f.host.totalExp;
      }
      expect(f.host.totalExp, sum);

      final List<HistoryEntry> kept = await log.entriesSettled();
      expect(kept, hasLength(HistoryLog.maxEntries));
      final int histSum = kept.fold<int>(
        0,
        (int s, HistoryEntry e) => s + e.exp,
      );
      expect(histSum, lessThan(sum), reason: '旧口径（流水求和）在这里已经倒退了');
    });
  });

  group('老档迁移（读档后补一次并落盘）', () {
    /// 一份不带 totalExp 的老档 + 已有的执行流水
    Future<QuestFlow> oldSave({
      required int lv,
      required int exp,
      required List<int> history,
    }) async {
      final HistoryLog log = HistoryLog();
      for (int i = 0; i < history.length; i++) {
        await log.append(clear(history[i], DateTime(2026, 2, 1, 9 + i)));
      }
      final SaveData d = SaveData.fromJson(
        jsonDecode(
          jsonEncode(<String, dynamic>{
            'host': <String, dynamic>{'name': '老档', 'lv': lv, 'exp': exp},
          }),
        ) as Map<String, dynamic>,
        fallback: SaveData.fresh(),
      );
      expect(d.host.totalExpKnown, isFalse);
      return QuestFlow(
        host: d.host,
        goal: d.goal,
        serial: 20000,
        historyLog: log,
      );
    }

    test('流水求和补上，并通知存档；再调一次不动', () async {
      final QuestFlow f = await oldSave(
        lv: 1,
        exp: 5,
        history: <int>[4, 6, 10],
      );
      int saves = 0;
      f.onChanged = () => saves++;

      expect(await f.backfillTotalExp(), isTrue);
      expect(f.host.totalExp, 20); // max(4+6+10, 下界 5)
      expect(saves, 1, reason: '补上就要落盘（autosave 契约）');
      expect(f.host.toJson()['totalExp'], 20);

      saves = 0;
      expect(await f.backfillTotalExp(), isFalse);
      expect(f.host.totalExp, 20);
      expect(saves, 0);
    });

    test('流水被截过 / 清过：取等级下界，不比「升到这级花掉的」少', () async {
      final QuestFlow f = await oldSave(lv: 3, exp: 2, history: <int>[1]);
      await f.backfillTotalExp();
      expect(f.host.totalExp, 18 + 24 + 2);
    });

    test('迁移前就结算了一单：这单先不记，求和时从流水带上', () async {
      final QuestFlow f = await oldSave(lv: 1, exp: 0, history: <int>[3]);
      final QuestResult r = await settleOne(
        f,
        daily('B'),
        DateTime(2026, 2, 2, 9),
      );
      expect(f.host.totalExpKnown, isFalse);
      await f.backfillTotalExp();
      expect(f.host.totalExp, 3 + r.exp);
    });

    test('补完存档往返：下次读档不再迁移', () async {
      final QuestFlow f = await oldSave(lv: 2, exp: 1, history: <int>[9, 9, 9]);
      await f.backfillTotalExp();
      final SaveFile file = SaveFile();
      await file.save(SaveData(host: f.host, goal: f.goal));
      final SaveData back = await SaveFile().load();
      expect(back.host.totalExpKnown, isTrue);
      expect(back.host.totalExp, 27);
    });
  });
}
