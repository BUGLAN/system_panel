/// 宿主档案 —— 对应原型 `Store.S` 里被界面读到的那部分。
///
/// 行为逻辑（存盘、发单、结算、连击规则）尚未由宿主约束，所以这里**只是数据**，
/// 先放一份与原型「老宿主 · 第 23 天」逐字段一致的演示档，
/// 好让界面能与原型做同状态比对。
library;

import '../data/rewards.dart';

class HostState {
  const HostState({
    required this.name,
    required this.lv,
    required this.exp,
    required this.coins,
    required this.streak,
    required this.title,
    required this.queue,
    required this.doneIndex,
    required this.planTotal,
    required this.attrs,
    required this.doneCount,
    required this.critCount,
    required this.failCount,
    required this.bestStreak,
    required this.ownedTitles,
    required this.items,
    this.totalExp = 0,
  });

  final String name;
  final int lv;
  final int exp;
  final int coins;
  final int streak;

  /// 已挂上的称号 id（原型的 `Store.title`）
  final String title;

  /// 她手里还有几单
  final int queue;

  /// 主线：脚下第几环（0 基）与总环数
  /// 已完成单数（老档的 `ringIndex` —— 「第几环」那一套已废除）
  final int doneIndex;
  final int planTotal;

  /// 六维，键是单字（力/敏/体/智/知/魅）
  final Map<String, int> attrs;

  /// stats.done / stats.crit / stats.fail
  final int doneCount;
  final int critCount;
  final int failCount;

  final int bestStreak;

  /// 已解锁的称号 id
  final List<String> ownedTitles;

  /// 道具持有数（key → 数量）
  final Map<String, int> items;

  /// 累计 EXP（G3.1：只增不减；档案页「累计 EXP」读它）。
  ///
  /// 为什么要单独存：之前档案页拿执行历史流水求和，可流水只留最近
  /// `HistoryLog.maxEntries` 条，满了再结算最旧的被挤掉 —— 累计值**倒退**。
  /// 入账口只有 `QuestFlow.settle` 一处（工具/聊天路径不给写 exp）。
  ///
  /// [kTotalExpUnknown] = 老档缺这个字段、还没迁移：读档后由
  /// `QuestFlow.backfillTotalExp` 用流水补一次并落盘。
  final int totalExp;

  /// 老档还没迁移的占位（任何负数都按它算 —— 见 [totalExpKnown]）
  static const int kTotalExpUnknown = -1;

  bool get totalExpKnown => totalExp >= 0;

  /// 「升到当前等级至少花掉的 EXP + 手上余额」—— 累计 EXP 的下界。
  ///
  /// 等级/余额只由结算改（从 LV1·0 起步），按现行曲线这就是全部入账；
  /// 老档迁移时与流水求和取大：流水被 400 条上限截过时，靠它兜住不倒退。
  static int expFloor(int lv, int exp) {
    int s = exp < 0 ? 0 : exp;
    for (int l = 1; l < lv; l++) {
      s += need(l);
    }
    return s;
  }

  /// 升到下一级要的经验 —— **唯一真源是 `Rewards.needFor`**（`12 + lv × 6`）。
  ///
  /// ⚠️ t24 之前这里自己写了一条旧曲线 `60 + lv * 40`（store.js L5 遗留），
  /// 与结算/升级用的 `rewards.dart:36` **双口径并存**：LV7 真实 need = 54，
  /// 档案页经验环却按 /340 画（常年在用户眼里几乎空着），agent 查状态报的
  /// 经验上限也是旧值（TODO-15）。现在整条链只有一条曲线，
  /// 这里只剩一个转发，改数值只改 `rewards.dart` 一处。
  static int need(int lv) => Rewards.needFor(lv);

  /// 经验环的进度（HUD 里 `clamp(exp / need(lv), 0, 1)`）—— 与升级判定同源
  double get expRatio => (exp / need(lv)).clamp(0.0, 1.0);

  /// 最弱的一维（`Store.weakest()`）—— 档案雷达里那一轴会变灰
  MapEntry<String, int> get weakest => attrs.entries.reduce(
    (MapEntry<String, int> a, MapEntry<String, int> b) =>
        b.value < a.value ? b : a,
  );

  /// 原型 `Store.veteran()` 建出来的那一档（「老宿主 · 第 23 天」）——
  /// **每次比对前都要在原型里先调一次 `Store.veteran()`**，否则拿到的是被玩脏的存档
  /// （这一坑踩过：items 少一个键，界面上会印出「持有 ×undefined」，
  ///   一度被我误判成原型的数据 bug）。
  static const HostState demo = HostState(
    name: '林深',
    lv: 7,
    // need(7) = 12 + 7×6 = 54：余额必须小于它，否则第一单就连升三级
    exp: 38,
    coins: 340,
    streak: 6,
    title: 'done15',
    queue: 4, // veteran() 的 S.queue.length
    doneIndex: 4,
    planTotal: 8,
    attrs: <String, int>{'力': 9, '敏': 12, '体': 17, '智': 6, '知': 8, '魅': 4},
    doneCount: 31,
    critCount: 6,
    failCount: 4,
    bestStreak: 6,
    ownedTitles: <String>[
      'bind',
      'first',
      'crit',
      'done5',
      'redeem',
      'streak3',
      'done15',
    ],
    items: <String, int>{'dbl': 1, 'crit': 1, 'shield': 1, 'patch': 1},
    // = expFloor(7, 38)：LV1→7 花掉 18+24+30+36+42+48 = 198，加余额 38
    totalExp: 236,
  );

  static const HostState empty = HostState(
    name: '宿主',
    lv: 1,
    exp: 0,
    coins: 0,
    streak: 0,
    title: 'bind',
    queue: 0,
    doneIndex: -1,
    planTotal: 0,
    attrs: <String, int>{'力': 0, '敏': 0, '体': 0, '智': 0, '知': 0, '魅': 0},
    doneCount: 0,
    critCount: 0,
    failCount: 0,
    bestStreak: 0,
    ownedTitles: <String>['bind'],
    items: <String, int>{'dbl': 0, 'crit': 0, 'shield': 0, 'patch': 0},
    totalExp: 0, // 新宿主 / 重置后从 0 记起（已知值，不走迁移）
  );

  // ── 存档（store.js L34-52）────────────────────────────────

  /// **在 `fallback` 上合并** —— 缺的字段走默认值，这就是老存档的迁移方式。
  /// 原型是 `Object.assign(this.fresh(), JSON.parse(raw))`。
  factory HostState.fromJson(
    Map<String, dynamic>? json, {
    required HostState fallback,
  }) {
    if (json == null) return fallback;
    T pick<T>(String k, T def) => json[k] is T ? json[k] as T : def;
    Map<String, int> attrsOf(String k, Map<String, int> def) {
      final Object? raw = json[k];
      if (raw is! Map) return def;
      return <String, int>{
        for (final MapEntry<Object?, Object?> e in raw.entries)
          if (e.key is String && e.value is int)
            e.key! as String: e.value! as int,
      };
    }

    return HostState(
      name: pick<String>('name', fallback.name),
      lv: pick<int>('lv', fallback.lv),
      exp: pick<int>('exp', fallback.exp),
      coins: pick<int>('coins', fallback.coins),
      streak: pick<int>('streak', fallback.streak),
      title: pick<String>('title', fallback.title),
      queue: pick<int>('queue', fallback.queue),
      doneIndex: pick<int>(
        'doneIndex',
        pick<int>('ringIndex', fallback.doneIndex),
      ),
      planTotal: pick<int>('planTotal', fallback.planTotal),
      attrs: attrsOf('attrs', fallback.attrs),
      doneCount: pick<int>('doneCount', fallback.doneCount),
      critCount: pick<int>('critCount', fallback.critCount),
      failCount: pick<int>('failCount', fallback.failCount),
      bestStreak: pick<int>('bestStreak', fallback.bestStreak),
      ownedTitles: json['ownedTitles'] is List
          ? <String>[
              for (final Object? t in json['ownedTitles'] as List)
                if (t is String) t,
            ]
          : fallback.ownedTitles,
      items: attrsOf('items', fallback.items),
      // ⚠️ 唯一**不**在 fallback 上合并的字段：缺了不能当 0（老档会显示累计 0），
      // 也不能取 fallback（演示档的值会冒名顶替）—— 标成「未知」，读档后用流水补
      totalExp: json['totalExp'] is int && (json['totalExp'] as int) >= 0
          ? json['totalExp'] as int
          : kTotalExpUnknown,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'lv': lv,
    'exp': exp,
    'coins': coins,
    'streak': streak,
    'title': title,
    'queue': queue,
    'doneIndex': doneIndex,
    'planTotal': planTotal,
    'attrs': attrs,
    'doneCount': doneCount,
    'critCount': critCount,
    'failCount': failCount,
    'bestStreak': bestStreak,
    'ownedTitles': ownedTitles,
    'items': items,
    // 未知（还没迁移）就不写：下次读档仍是「缺字段」，迁移还会再补
    if (totalExpKnown) 'totalExp': totalExp,
  };

  HostState copyWith({
    String? name,
    int? lv,
    int? exp,
    int? coins,
    int? streak,
    String? title,
    int? queue,
    int? doneIndex,
    int? planTotal,
    Map<String, int>? attrs,
    int? doneCount,
    int? critCount,
    int? failCount,
    int? bestStreak,
    List<String>? ownedTitles,
    Map<String, int>? items,
    int? totalExp,
  }) => HostState(
    name: name ?? this.name,
    lv: lv ?? this.lv,
    exp: exp ?? this.exp,
    coins: coins ?? this.coins,
    streak: streak ?? this.streak,
    title: title ?? this.title,
    queue: queue ?? this.queue,
    doneIndex: doneIndex ?? this.doneIndex,
    planTotal: planTotal ?? this.planTotal,
    attrs: attrs ?? this.attrs,
    doneCount: doneCount ?? this.doneCount,
    critCount: critCount ?? this.critCount,
    failCount: failCount ?? this.failCount,
    bestStreak: bestStreak ?? this.bestStreak,
    ownedTitles: ownedTitles ?? this.ownedTitles,
    items: items ?? this.items,
    totalExp: totalExp ?? this.totalExp,
  );
}
