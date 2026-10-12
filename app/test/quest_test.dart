import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/data/rewards.dart';
import 'package:system_panel/state/quest.dart';

/// `Quest` 的派生文案（原型 `ui.js` L186-208 的模板）。
///
/// 单独立这个是因为 **`kindLabel` 少了一档**：原型是四档（main / remedy /
/// hinted / 日常委托），我原先只有三档 —— `T.hinted ? '日常 · 她替你留的'`
/// 那一支从来没写过。这种"少一个分支"的错，截图比对基本看不出来
/// （只有她替你留单的那天才显示），只能靠对源码。
void main() {
  Quest q({
    String kind = 'daily',
    bool hinted = false,
    int planIndex = 4,
    int planTotal = 8,
    Map<String, int> attrs = const <String, int>{'体': 1, '力': 1},
  }) => Quest(
    serial: 41,
    kind: kind,
    planIndex: planIndex,
    planTotal: planTotal,
    name: '跑完 5 公里',
    reason: '上一单你用了 38 分 46 秒。',
    proof: '跑步 App 截图',
    minutes: 45,
    rank: 'C',
    attrs: attrs,
    hinted: hinted,
  );

  group('kindLabel 四档（ui.js L196）', () {
    test('主线：`主线 · 第 N 单 / M`（序号 1 基）', () {
      expect(q(kind: 'main').kindLabel, '主线 · 第 5 单 / 8');
    });

    test('补救：`补救 · 24 小时内有效`', () {
      expect(q(kind: 'remedy').kindLabel, '补救 · 24 小时内有效');
    });

    test('⚠️ 她替你留的：`日常 · 她替你留的`', () {
      expect(q(hinted: true).kindLabel, '日常 · 她替你留的');
    });

    test('普通日常：`日常委托`', () {
      expect(q().kindLabel, '日常委托');
    });

    test('hinted 只影响日常那一档，不会盖掉主线/补救', () {
      expect(q(kind: 'main', hinted: true).kindLabel, '主线 · 第 5 单 / 8');
      expect(q(kind: 'remedy', hinted: true).kindLabel, '补救 · 24 小时内有效');
    });
  });

  group('单号与报酬', () {
    test('单号补零到 4 位', () {
      expect(q().serialText, '№ 0041');
    });

    test('报酬：`EXP n · ◈ m 体+1 力+1`（t15：结算经济口径，与结算同表）', () {
      // C 级 4 exp / 5 金币（docs/18 §2.3 Rewards）
      expect(q().lootText, 'EXP 4 · ◈ 5体+1 力+1');
    });

    test('⚠️ 补救单的报酬**减半**（原型 k = remedy ? .5 : 1）', () {
      expect(q(kind: 'remedy').lootText, 'EXP 2 · ◈ 3体+1 力+1');
    });

    test('rewardText = 原型旧表遗留（t15 后无生产读者，仅 rewards_test 交叉钉存档）', () {
      expect(q().rewardText, 'EXP 50 · ◈ 24体+1 力+1');
      expect(q(kind: 'remedy').rewardText, 'EXP 25 · ◈ 12体+1 力+1');
    });
  });

  group('lootText = 结算经济口径（docs/18 §2.3 Rewards，t8）', () {
    test('C 级：EXP 4 · ◈ 5 —— 与 QuestFlow.settle 同表（rewardText 是旧表）', () {
      expect(q().lootText, 'EXP 4 · ◈ 5体+1 力+1');
      expect(q().lootText, isNot(q().rewardText));
    });

    test('补救单减半：C 级 EXP 2 · ◈ 3（金币 2.5 → 3）', () {
      expect(q(kind: 'remedy').lootText, 'EXP 2 · ◈ 3体+1 力+1');
    });

    test('逐档与 Rewards 表对齐（E~S 全档）', () {
      for (final String rank in Rewards.kExpByRank.keys) {
        final Quest byRank = Quest(
          serial: 41,
          kind: 'daily',
          planIndex: -1,
          planTotal: 0,
          name: 'x',
          reason: '',
          proof: 'y',
          minutes: 10,
          rank: rank,
          attrs: const <String, int>{},
        );
        expect(
          byRank.lootText,
          'EXP ${Rewards.expOf(rank)} · ◈ ${Rewards.coinOf(rank)}',
          reason: '档位 $rank',
        );
      }
    });

    // t24 · 机制化约束（与 plate_test 的同名组互为双保险）：
    // 「显示 ≠ 结算」已复发两次，这里把**全档位 × 补救 × 暴击 × 双倍**的
    // 文案一次遍历钉死 —— lootTextOf 的输出只允许来自 Rewards.payout。
    test('全档位 × 补救/暴击/双倍：文案 == Rewards.payout（防第三次复发）', () {
      for (final String rank in Rewards.kExpByRank.keys) {
        for (final bool remedy in <bool>[false, true]) {
          for (final bool crit in <bool>[false, true]) {
            for (final bool dbl in <bool>[false, true]) {
              final Payout p = Rewards.payout(
                rank: rank,
                crit: crit,
                dbl: dbl,
                remedy: remedy,
              );
              expect(
                Quest.lootTextOf(
                  rank: rank,
                  remedy: remedy,
                  crit: crit,
                  dbl: dbl,
                ),
                'EXP ${p.exp} · ◈ ${p.coin}',
                reason: '$rank remedy=$remedy crit=$crit dbl=$dbl',
              );
            }
          }
        }
      }
    });

    test('六维后缀跟在金币后面（板面那一行的完整形状）', () {
      expect(
        Quest.lootTextOf(
          rank: 'C',
          attrs: const <String, int>{'体': 1, '力': 1},
        ),
        'EXP 4 · ◈ 5体+1 力+1',
      );
      expect(Quest.lootTextOf(rank: 'C'), 'EXP 4 · ◈ 5');
      expect(Quest.lootTextOf(rank: 'C', remedy: true), 'EXP 2 · ◈ 3');
      expect(
        Quest.lootTextOf(rank: 'S', crit: true, dbl: true),
        'EXP 40 · ◈ 40', // 暴击×2 金币、双倍只吃经验：10×2×2 / 20×2
      );
    });
  });
}
