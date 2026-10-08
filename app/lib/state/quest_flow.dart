import 'dart:math' as math;

import '../data/attrs.dart';
import '../data/format.dart';
import '../data/rarity.dart';
import 'goal.dart';
import 'host_state.dart';
import 'quest.dart';
import 'result.dart';

/// ═══════════════════════════════════════════════════════════
///  业务唯一真源（T2）—— 移植 prototype/opus-v2-dir/js/store.js 的
///  队列 / 接单 / 道具 / 暴击率 / 结算 / 认输 / 补救。
///
///  「提交任务卡死」的修复点：main.dart 的 onSubmit 之前只会切页面，
///  不做任何结算（docs/18 §1.2 根因①②）——现在全部经这里产出真实
///  QuestResult 并落到档案 / 主线 / 队列，再由 main.dart 持久化。
///
///  ⚠️ 界面层只读公开 API；数值**只能经结算**进档案（Agent 工具的钳制同样如此）。
///
///  数值表：docs/18-Agent系统升级方案.md §2.3（E~S 奖励 + need=12+lv×6）。
///  T6 落地 lib/data/rewards.dart 后由其接管数值，此处只留结算规则。
/// ═══════════════════════════════════════════════════════════

/// 正在执行的那一单（原型 `S.active = { task, startAt, photos, dbl, crit, shield }`）
class ActiveQuest {
  ActiveQuest({required this.task, required this.startAt});

  final Quest task;

  /// 接单时刻 —— 计时由它推导（`Clock.now() - A.startAt`），不是累加
  final DateTime startAt;

  /// 本单已挂上生效的道具（原型 `A.dbl / A.crit / A.shield`）
  bool dbl = false;
  bool crit = false;
  bool shield = false;

  /// 已交的证据份数（拍照接线在 T4，结算口径先占位）
  int photos = 0;
}

/// 认输 / 超时的产出（原型 `Store.fail()` 的返回值，T2 消费补救单与时长）
class FailOutcome {
  const FailOutcome({
    required this.task,
    required this.held,
    required this.how,
    this.remedy,
    this.remedyDeadline,
  });

  final Quest task;
  final Duration held;
  final String how;

  /// 生成的补救单（原型同款：做一半 · 降两档 · 24 小时有效）
  final Quest? remedy;
  final DateTime? remedyDeadline;
}

/// 一张日常模板（原型 `DAILY_COMMON`，content.js L224-239）。
/// 只服务本文件的日常池，字段全部 final。
class DailyTpl {
  const DailyTpl(this.t, this.p, this.m, this.a, this.r);
  final String t;
  final String p;
  final int m;
  final Map<String, int> a;
  final String r;
}

class QuestFlow {
  QuestFlow({
    required this.host,
    required this.goal,
    List<Quest>? queue,
    int? serial,
    math.Random? rnd,
  }) : queue = queue ?? <Quest>[],
       _serial = serial ?? kFirstSerial,
       _rnd = rnd ?? math.Random();

  /// 单号从 41 起算 —— 与演示档 Quest.demo 的 № 0041 接上
  static const int kFirstSerial = 41;

  /// 宿主档案（结算/认输的唯一入账口）
  HostState host;

  /// 主线（结算时点亮环、推进 cur）
  Goal goal;

  /// 她手里的单（队首 = head）。可变的、有顺序的 —— 结算/接单都要改它
  final List<Quest> queue;

  ActiveQuest? _active;
  Quest? _remedyOffer;
  DateTime? _remedyDeadline;
  int _serial;
  final math.Random _rnd;

  /// 连击判定的运行时态（store.js `S.lastDoneDay`；随存档迁移在 T6 补字段）
  DateTime? _lastDoneDay;
  int _failStreak = 0;

  ActiveQuest? get active => _active;
  Quest? get remedyOffer => _remedyOffer;
  DateTime? get remedyDeadline => _remedyDeadline;
  int get failStreak => _failStreak;

  /// 队首（原型 `Store.head()`；T2 不做演示开关，直接给第一张）
  Quest? get head => queue.isEmpty ? null : queue.first;

  bool get queueEmpty => queue.isEmpty;

  // ── 数值表（docs/18 §2.3；T6 的 rewards.dart 是它最终的家）──────────

  /// 升级曲线：`need(lv) = 12 + lv × 6`（lv1=18 … lv5=42 … lv10=72）
  static int needFor(int lv) => 12 + lv * 6;

  /// E~S 经验表（F 是兼容档：仅老存档/补救残单结算用）
  static const Map<String, int> kExpByRank = <String, int>{
    'F': 0, 'E': 1, 'D': 2, 'C': 4, 'B': 6, 'A': 8, 'S': 10,
  };

  /// E~S 金币表
  static const Map<String, int> kCoinByRank = <String, int>{
    'F': 3, 'E': 5, 'D': 5, 'C': 5, 'B': 7, 'A': 10, 'S': 20,
  };

  static int expOf(String rank) => kExpByRank[rank] ?? 0;
  static int coinOf(String rank) => kCoinByRank[rank] ?? 3;

  /// 降/升档（store.js `rankShift`，钉在 F~S 之间）
  static String rankShift(String r, int d) =>
      Rarity.ranks[(Rarity.of(r).i + d).clamp(0, Rarity.ranks.length - 1)];

  /// 通用日常池（DAILY_COMMON 全量照搬 —— 任何主线都混进来补短板）
  static const List<DailyTpl> kDailyPool = <DailyTpl>[
    DailyTpl('整理桌面，只留今天要用的东西', '桌面照片', 10, <String, int>{'知': 1}, 'F'),
    DailyTpl('出门走 3000 步', '步数截图', 30, <String, int>{'体': 1, '敏': 1}, 'E'),
    DailyTpl('读 20 页书', '页码照片', 30, <String, int>{'智': 1, '知': 1}, 'E'),
    DailyTpl('发呆 10 分钟，不碰手机', '计时截图', 12, <String, int>{'知': 2}, 'F'),
    DailyTpl('给一个很久没联系的人发条消息', '对话截图（可打码）', 8, <String, int>{'魅': 2}, 'E'),
    DailyTpl('20 个深蹲', '自拍或计数截图', 6, <String, int>{'力': 1, '体': 1}, 'F'),
    DailyTpl('把一件拖了一周的小事做完', '完成截图', 25, <String, int>{'知': 1, '智': 1}, 'D'),
    DailyTpl('拉伸 10 分钟', '拉伸照片', 12, <String, int>{'敏': 2}, 'F'),
    DailyTpl('平板支撑累计 3 分钟', '计时截图', 10, <String, int>{'力': 1, '体': 1}, 'E'),
    DailyTpl('写 300 字，写什么都行', '文字截图', 25, <String, int>{'智': 1, '魅': 1}, 'E'),
    DailyTpl('收拾房间的一个角落', '前后对比照片', 15, <String, int>{'知': 1, '体': 1}, 'F'),
    DailyTpl('跳绳 500 下', '计数截图', 12, <String, int>{'敏': 1, '体': 1}, 'E'),
    DailyTpl('学一个新技巧，今天用三次', '截图', 15, <String, int>{'智': 1, '敏': 1}, 'F'),
    DailyTpl('做一顿饭', '饭菜照片', 40, <String, int>{'体': 1, '知': 1}, 'D'),
  ];

  // ── 构造 ──────────────────────────────────────────────────

  /// 演示开局：与 HostState.demo / Goal.demo() 配套的队列
  /// （队首就是 Quest.demo 那张 C 级主线，后跟三张日常 ——
  ///   原型 `veteran()` 的 queue 语义；首个界面与历史截图逐字节一致）
  /// ⚠️ 单号要从 42 起发 —— 41 已经是队首那一张的，重号会撞掉 accept 的 removeWhere
  static QuestFlow demo() {
    final QuestFlow f = QuestFlow(
      host: HostState.demo,
      goal: Goal.demo(),
      serial: kFirstSerial + 1,
    );
    f.queue.add(Quest.demo);
    f._seedDailies(3);
    return f;
  }

  /// 从读出来的存档装填；队列空（老档升级首启/新绑定）按现状补种子
  /// （原型 `rollDay` 的「主线单重钉 + 每日补发」最小版；幂等化在 T6）
  static QuestFlow fromSave({
    required HostState host,
    required Goal goal,
    List<Quest>? queue,
  }) {
    // 新单号接在存档里最大单号之后，绝不与存档里的单撞号
    int next = kFirstSerial;
    if (queue != null) {
      for (final Quest q in queue) {
        next = math.max(next, q.serial + 1);
      }
    }
    final QuestFlow f = QuestFlow(
      host: host,
      goal: goal,
      queue: queue,
      serial: next,
    );
    if (f.queue.isEmpty) f.seedForCurrentGoal();
    return f;
  }

  /// 当前主线脚下那一环补回队首 + 三张日常
  void seedForCurrentGoal() {
    final int ci = goal.currentIndex;
    if (ci >= 0) queue.add(ringTask(ci));
    _seedDailies(3);
  }

  void _seedDailies(int n) {
    queue.addAll(genDaily(n));
    _syncQueueCount();
  }

  void _syncQueueCount() => host = host.copyWith(queue: queue.length);

  // ── 造单 ──────────────────────────────────────────────────

  Quest _mk({
    required String kind,
    int ring = -1,
    int ringTotal = 0,
    required String name,
    required String proof,
    required int minutes,
    required String rank,
    required Map<String, int> attrs,
    String reason = '',
    bool hinted = false,
  }) => Quest(
    serial: _serial++,
    kind: kind,
    ring: ring,
    ringTotal: ringTotal,
    name: name,
    reason: reason,
    proof: proof,
    minutes: minutes,
    rank: rank,
    attrs: attrs,
    hinted: hinted,
  );

  /// 六维点数分配（store.js `splitAttrs`：按基准权重分，余数补给第一维）
  static Map<String, int> splitAttrs(Map<String, int> base, int pts) {
    final List<String> ks = base.keys.toList()
      ..sort((String x, String y) => base[y]!.compareTo(base[x]!));
    if (ks.isEmpty) return const <String, int>{};
    final int sum = base.values.fold(0, (int s, int v) => s + v);
    final Map<String, int> out = <String, int>{};
    int left = pts;
    for (int i = 0; i < ks.length; i++) {
      final int v = i == ks.length - 1
          ? left
          : math.min(
              left,
              math.max(
                i == 0 ? 1 : 0,
                (pts * base[ks[i]]! / (sum <= 0 ? 1 : sum)).round(),
              ),
            );
      if (v > 0) {
        out[ks[i]] = v;
        left -= v;
      }
    }
    if (left > 0) out[ks.first] = (out[ks.first] ?? 0) + left;
    return out;
  }

  /// 主线第 i 环 → 一张单（store.js `ringTask`）。
  /// ⚠️ GoalRing 暂无基准维（Flutter 侧模型没有 `a` 字段），先全押「体」；
  ///    T6 给 goal.dart 补 plan 元数据时一并迁移。
  Quest ringTask(int i) {
    final GoalRing g = goal.rings[i];
    return _mk(
      kind: 'main',
      ring: i,
      ringTotal: goal.rings.length,
      name: g.title,
      proof: g.proof,
      minutes: g.minutes,
      rank: g.rank,
      attrs: splitAttrs(const <String, int>{'体': 1}, Rarity.of(g.rank).pt),
      reason: reasonForMain(i),
    );
  }

  /// 日常生成（store.js `genDaily` 的 T2 版）：短板单优先，lv4/lv8 概率提档，
  /// 封顶 lv<8 到 D、lv≥8 到 C
  List<Quest> genDaily(int n) {
    final String weak = host.weakest.key;
    final List<Quest> out = <Quest>[];
    final Set<String> used = <String>{};
    bool take(bool Function(DailyTpl) pred) {
      final List<DailyTpl> cand = kDailyPool
          .where((DailyTpl d) => !used.contains(d.t) && pred(d))
          .toList();
      if (cand.isEmpty) return false;
      final DailyTpl d = cand[_rnd.nextInt(cand.length)];
      used.add(d.t);
      String rank = d.r;
      if (host.lv >= 4 && _rnd.nextDouble() < .3) rank = rankShift(rank, 1);
      if (host.lv >= 8 && _rnd.nextDouble() < .2) rank = rankShift(rank, 1);
      final int cap = host.lv >= 8 ? 3 : 2;
      rank = Rarity.ranks[math.min(Rarity.of(rank).i, cap)];
      out.add(
        _mk(
          kind: 'daily',
          name: d.t,
          proof: d.p,
          minutes: d.m,
          rank: rank,
          attrs: splitAttrs(d.a, Rarity.of(rank).pt),
        ),
      );
      return true;
    }

    // 一单专治短板，其余随缘（store.js L108 的 plan；贴主线由 ringTask 承担）
    for (int i = 0; i < n; i++) {
      if (!(take((DailyTpl d) => (d.a[weak] ?? 0) > 0) || take((_) => true))) {
        break;
      }
    }
    return out;
  }

  // ── 派单前的上下文：给单子写一句"为什么是你"（store.js `reasonFor`）──

  String reasonForMain(int i) {
    if (i > 0 && i < goal.rings.length) {
      final Duration? held = goal.rings[i - 1].held;
      if (held != null) {
        return '上一环你用了 ${fmtDur(held)}。这一环，我加了点码。';
      }
    }
    return '你说要「${goal.text}」。那就从这一步开始。';
  }

  String reasonFor(Quest t) {
    if (t.kind == 'main') return reasonForMain(t.ring);
    if (t.kind == 'remedy') return reasonForRemedy();
    if (t.hinted) return '昨天说好的那张。我替你留着呢。';
    final MapEntry<String, int> w = host.weakest;
    if ((t.attrs[w.key] ?? 0) > 0) {
      return '你的${Attr.nameOf(w.key)}只有 ${w.value}。这一单，专门治它。';
    }
    if (host.streak >= 2) return '连击 ${host.streak} 天。别断在这一单上。';
    return '今天的。我挑过了。';
  }

  /// 补救单的附言（store.js `reasonFor` 的 remedy 分支）
  String reasonForRemedy() => '补救。做完一半，就当那一笔没输。';

  // ── 宿主的回应 ────────────────────────────────────────────

  /// 接单：出队 + 记 startAt（store.js `accept`；D12 的"计时起点"）
  void accept(Quest t, {DateTime? now}) {
    queue.removeWhere((Quest q) => q.serial == t.serial);
    _active = ActiveQuest(task: t, startAt: now ?? DateTime.now());
    _syncQueueCount();
  }

  /// 用执行类道具：扣库存 + 挂到本单（store.js `useItem`）
  bool useItem(String id, {DateTime? now}) {
    final ActiveQuest? a = _active;
    if (a == null) return false;
    if (id != 'dbl' && id != 'crit' && id != 'shield') return false;
    final bool already = id == 'dbl'
        ? a.dbl
        : id == 'crit'
        ? a.crit
        : a.shield;
    if (already) return false;
    final int n = host.items[id] ?? 0;
    if (n <= 0) return false;
    host = host.copyWith(items: <String, int>{...host.items, id: n - 1});
    if (id == 'dbl') {
      a.dbl = true;
    } else if (id == 'crit') {
      a.crit = true;
    } else {
      a.shield = true;
    }
    return true;
  }

  /// 暴击率（store.js `critChance`）：底 6% + 每份证据 6%（≤3）+ 连击 1%/天（≤10）
  /// + 暴击芯片 25%，封顶 85%。
  /// ⚠️ 演示档（streak 6、0 证据、无芯片）= .12 —— 与原写死值一致，实测不回归。
  double critChance({int? photos}) {
    final ActiveQuest? a = _active;
    if (a == null) return 0;
    final int p = photos ?? a.photos;
    return math.min(
      .85,
      .06 + .06 * math.min(3, p) + math.min(10, host.streak) * .01 + (a.crit ? .25 : 0),
    );
  }

  // ── 结算（store.js `settle`；提交任务的真正语义）────────────────

  /// 无执行中单据时返回 null（调用方自行兜底）。
  /// [forceCrit] 只给测试用（demo 也可钉死非暴击：传 false）。
  QuestResult? settle({DateTime? now, math.Random? rnd, bool? forceCrit}) {
    final ActiveQuest? a = _active;
    if (a == null) return null;
    final DateTime t0 = now ?? DateTime.now();
    final Quest task = a.task;
    final Duration held = t0.difference(a.startAt);

    final double chance = critChance();
    final double roll = (rnd ?? _rnd).nextDouble();
    final bool crit = forceCrit ?? roll < chance;
    // 差一点就中：原型 `near`（差不到 8% 才给值）
    final int near = !crit && (roll - chance) < .08
        ? math.max(1, ((roll - chance) * 100).round())
        : 0;

    // 补救单半价（store.js L281-283：暴击×2、双倍×2、可叠×4）
    final double k = task.kind == 'remedy' ? .5 : 1.0;
    final int baseExp = (expOf(task.rank) * k).round();
    final int exp = baseExp * (crit ? 2 : 1) * (a.dbl ? 2 : 1);
    final int coin = (coinOf(task.rank) * k).round() * (crit ? 2 : 1);

    final int beforeLv = host.lv;
    final int beforeExp = host.exp;
    final int beforeNeed = needFor(beforeLv);

    // 经验入账 + 升级循环（新曲线 need=12+lv×6）
    int lv = beforeLv;
    int curExp = beforeExp + exp;
    final List<int> ups = <int>[];
    while (curExp >= needFor(lv)) {
      curExp -= needFor(lv);
      lv++;
      ups.add(lv);
    }
    host = host.copyWith(lv: lv, exp: curExp, coins: host.coins + coin);

    // 六维加成
    final Map<String, int> grown = <String, int>{...host.attrs};
    for (final MapEntry<String, int> e in task.attrs.entries) {
      grown[e.key] = (grown[e.key] ?? 0) + e.value;
    }
    host = host.copyWith(attrs: grown);

    // 连击：今天第一单才 +1（store.js L290-294）
    final DateTime today = DateTime(t0.year, t0.month, t0.day);
    bool streakUp = false;
    if (_lastDoneDay == null || !_isSameDay(_lastDoneDay!, today)) {
      final bool consecutive =
          _lastDoneDay != null && today.difference(_lastDoneDay!).inDays == 1;
      final int streak = consecutive ? host.streak + 1 : 1;
      host = host.copyWith(
        streak: streak,
        bestStreak: math.max(host.bestStreak, streak),
      );
      streakUp = true;
    }
    _lastDoneDay = today;

    host = host.copyWith(
      doneCount: host.doneCount + 1,
      critCount: host.critCount + (crit ? 1 : 0),
    );

    // 主线：这一环点亮，下一环补单（store.js L297-303）
    int ringClear = -1;
    bool finale = false;
    if (task.kind == 'main' &&
        task.ring >= 0 &&
        task.ring < goal.rings.length) {
      final List<GoalRing> rings = <GoalRing>[...goal.rings];
      final GoalRing g = rings[task.ring];
      rings[task.ring] = GoalRing(
        short: g.short,
        title: g.title,
        proof: g.proof,
        minutes: g.minutes,
        rank: g.rank,
        state: RingState.done,
        finalRing: g.finalRing,
        held: held,
        doneAt: t0,
      );
      final int nx = task.ring + 1;
      if (nx < rings.length) {
        final GoalRing n = rings[nx];
        rings[nx] = GoalRing(
          short: n.short,
          title: n.title,
          proof: n.proof,
          minutes: n.minutes,
          rank: n.rank,
          state: RingState.cur,
          finalRing: n.finalRing,
        );
        queue.insert(0, ringTask(nx));
      } else {
        finale = true;
      }
      goal = goal.copyWith(rings: rings);
      ringClear = task.ring;
    }

    // 补救单抵消失败（history 的 redeemed 标记随 T5 的 history 落库）
    final bool redeemed = task.kind == 'remedy';

    _syncQueueCount();
    final bool empty = queue.isEmpty;

    // 称号（store.js `checkTitles`）
    final List<String> titles = _checkTitles(
      crit: crit,
      rank: task.rank,
      redeemed: redeemed,
      finale: finale,
    );
    if (titles.isNotEmpty) {
      host = host.copyWith(
        ownedTitles: <String>{...host.ownedTitles, ...titles}.toList(),
        title: host.title == 'mouth' ? host.title : titles.last,
      );
    }

    _active = null;

    return QuestResult(
      quest: task,
      beforeLv: beforeLv,
      beforeExp: beforeExp,
      beforeNeed: beforeNeed,
      exp: exp,
      coin: coin,
      attrs: Map<String, int>.of(task.attrs),
      streak: host.streak,
      streakUp: streakUp,
      crit: crit,
      dbl: a.dbl,
      photos: a.photos,
      chance: chance,
      near: near,
      ups: ups,
      titles: titles,
      ringClear: ringClear,
      finale: finale,
      redeemed: redeemed,
      empty: empty,
      tooFast: held.inMilliseconds < 60000,
      held: held,
      afterLv: lv,
      afterNeed: needFor(lv),
      endExp: curExp,
    );
  }

  List<String> _checkTitles({
    required bool crit,
    required String rank,
    required bool redeemed,
    required bool finale,
  }) {
    final List<String> got = <String>[];
    void add(String id) {
      if (!host.ownedTitles.contains(id)) got.add(id);
    }

    if (host.doneCount >= 1) add('first');
    if (crit) add('crit');
    if (host.doneCount >= 5) add('done5');
    if (redeemed) add('redeem');
    if (host.streak >= 3) add('streak3');
    if (rank == 'A') add('rankA');
    if (host.doneCount >= 15) add('done15');
    if (host.streak >= 7) add('streak7');
    if (rank == 'S') add('rankS');
    if (finale) add('finale');
    return got;
  }

  // ── 认输 / 超时（store.js `fail`）────────────────────────────

  FailOutcome? fail({DateTime? now, String how = 'quit'}) {
    final ActiveQuest? a = _active;
    if (a == null) return null;
    final DateTime t0 = now ?? DateTime.now();
    final Quest task = a.task;
    final Duration held = t0.difference(a.startAt);
    if (!a.shield) _failStreak++;
    host = host.copyWith(failCount: host.failCount + 1);

    // 主线不判死：这一环回到队首（store.js L359）
    if (task.kind == 'main') queue.insert(0, task);

    Quest? remedy;
    DateTime? deadline;
    if (task.kind != 'remedy') {
      final String rr = rankShift(task.rank, -2);
      remedy = _mk(
        kind: 'remedy',
        name: '${task.name}（做一半）',
        proof: task.proof,
        minutes: math.max(5, (task.minutes / 2).ceil()),
        rank: rr,
        // 用原单的分配结果当权重再分一次（原单基准维没落库，见 ringTask 注）
        attrs: splitAttrs(task.attrs, Rarity.of(rr).pt),
        reason: reasonForRemedy(),
      );
      deadline = t0.add(const Duration(hours: 24));
      _remedyOffer = remedy;
      _remedyDeadline = deadline;
    }
    _active = null;
    _syncQueueCount();
    return FailOutcome(
      task: task,
      held: held,
      how: how,
      remedy: remedy,
      remedyDeadline: deadline,
    );
  }

  /// 领补救单：接 = 插回队首，算了 = 排队尾（store.js `takeRemedy`）
  Quest? takeRemedy({bool now = true}) {
    final Quest? r = _remedyOffer;
    if (r == null) return null;
    _remedyOffer = null;
    _remedyDeadline = null;
    if (now) {
      queue.insert(0, r);
    } else {
      queue.add(r);
    }
    _syncQueueCount();
    return r;
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
