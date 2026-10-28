import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../agent/vision.dart' as vision;
import '../data/attrs.dart';
import '../data/format.dart';
import '../data/items.dart';
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
///  返工卡（t14）增补：换一个 retreat（计数+口头巨人+降档/换单）、
///  补给 buy（扣币加道具）、挂称号 equip（mouth 强制期禁换挂）、
///  证据带校验状态进暴击率（vision.dart evidenceCritBonus 7%/4%，封顶 .85）。
///
///  ⚠️ 界面层只读公开 API；数值**只能经结算**进档案（Agent 工具的钳制同样如此）。
///
///  数值表：docs/18-Agent系统升级方案.md §2.3（E~S 奖励 + need=12+lv×6）。
///  T6 落地 lib/data/rewards.dart 后由其接管数值，此处只留结算规则。
/// ═══════════════════════════════════════════════════════════

/// 正在执行的那一单（原型 `S.active = { task, startAt, photos, dbl, crit, shield }`）
class ActiveQuest {
  ActiveQuest({
    required this.task,
    required this.startAt,
    List<vision.EvidenceShot>? evidence,
  }) : evidence = evidence ?? <vision.EvidenceShot>[];

  final Quest task;

  /// 接单时刻 —— 计时由它推导（`Clock.now() - A.startAt`），不是累加
  final DateTime startAt;

  /// 本单已挂上生效的道具（原型 `A.dbl / A.crit / A.shield`）
  bool dbl = false;
  bool crit = false;
  bool shield = false;

  /// 本单的证据（docs/18 §2.4：每张带校验状态 ✓/存疑/未校验）。
  /// 原型的 `A.photos` 是纯份数数组；这里升级为 vision.dart 的 EvidenceShot，
  /// 暴击口径按已校验/未校验分别计（`critChance`）。
  final List<vision.EvidenceShot> evidence;

  /// 已交证据份数（旧口径：结算页/战报还读这个数）
  int get photos => evidence.length;

  /// 已校验份数（LLM 判真）；存疑与未校验一律按未校验计（exec_panel 同口径）
  int get verifiedCount => evidence
      .where(
        (vision.EvidenceShot s) => s.status == vision.EvidenceStatus.verified,
      )
      .length;

  /// 未校验份数 = 总数 - 已校验
  int get unverifiedCount => evidence.length - verifiedCount;
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

/// 「换一个」的产出（原型 `Store.retreat()` 返回的 `{ n, shame }` 加上新单）。
class RetreatOutcome {
  const RetreatOutcome({
    required this.task,
    required this.count,
    required this.total,
    required this.shame,
    this.replacement,
  });

  /// 退掉的那一单（降档前的样子 —— 结算台词/界面重刻要读它的旧档位）
  final Quest task;

  /// 换上的那一单：非 F 级 = 同 serial 降一档重刻；F 级还退 = 另一张 F 日常。
  /// null = F 级但日常池枯了，原单原样留着（原型 `if (nt)` 的兜底）。
  final Quest? replacement;

  /// 今天第几次退缩（含本次；原型 `info.n`，台词 retreat1/2/3 按它分档）
  final int count;

  /// 累计退缩次数（跨日不清；原型 `S.retreatTotal`）
  final int total;

  /// 本次触发了「口头巨人」强制佩戴（累计 ≥3 且还没解锁过）
  final bool shame;
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

/// 主线收官（finale）的产出 —— TODO-01「第二目标闭环」。
///
/// [cleared] = **已走过的环数**（收官时必然 = [total]，所以提档条件成立）；
/// [total] = 刚走完的这条主线的总环数；[level] 是结算后的等级；
/// [goal] 非空表示新主线**已经落库**（`flow.goal` 已换成它、旧主线单已撤下、
/// 首环已钉队首）。
class FinaleOutcome {
  const FinaleOutcome({
    required this.cleared,
    required this.total,
    required this.level,
    required this.newGoalText,
    this.goal,
    this.insertedPlan,
  });

  /// 已走过的环数（不是环号 —— 环号是 0 基的 `planClear`）
  final int cleared;

  final int total;
  final int level;

  /// 新主线的一句话（沿用上一目标或宿主另立的那句）
  final String newGoalText;

  /// 新主线（null = 宿主没接续，叙事真的停在终点）
  final Goal? goal;

  /// 这次往队首钉进去的首环单（幂等：已经在队列里就是 null）
  final Quest? insertedPlan;
}

/// 收官时生成下一条主线的钩子。
/// 参数 = `(上一目标, 已走过的环数, 上一目标总环数, 结算后等级)`。
///
/// ⚠️ 2026-10-23：**不再允许返回 null**。旧签名用 null 表示「这次不续」，
/// 于是「拆不出下一份计划」和「故意停在终点」被混成同一件事，失败被吞掉。
/// 现在钩子要么返回一份计划，要么抛（拆解失败原样往上抛给调用方）。
/// 想真的停在终点，就别接这个钩子。
typedef NextGoalHook = Future<Goal> Function(
  Goal prev,
  int cleared,
  int total,
  int level,
);

class QuestFlow {
  QuestFlow({
    required this.host,
    required this.goal,
    List<Quest>? queue,
    int? serial,
    math.Random? rnd,
    HistoryLog? historyLog,
  }) : queue = List<Quest>.of(queue ?? const <Quest>[]),
       _serial = serial ?? kFirstSerial,
       _rnd = rnd ?? math.Random(),
       historyLog = historyLog ?? HistoryLog();

  /// A6：执行历史（settle/认输追加；独立 key，main.dart 的存档流不用动）
  final HistoryLog historyLog;

  /// 单号从 41 起算 —— 与演示档 Quest.demo 的 № 0041 接上
  static const int kFirstSerial = 41;

  /// 单子的存档形态（t16/B3：active 随档走，队列与执行中单据共用这一套；
  /// save_file.dart 的存档层委托到这里，Quest 模型保持纯数据）。
  static Map<String, dynamic> questToJson(Quest q) => <String, dynamic>{
    'serial': q.serial,
    'kind': q.kind,
    'planIndex': q.planIndex,
    'planTotal': q.planTotal,
    if (q.goalId.isNotEmpty) 'goalId': q.goalId,
    'name': q.name,
    'reason': q.reason,
    'proof': q.proof,
    'minutes': q.minutes,
    'rank': q.rank,
    'attrs': q.attrs,
    if (q.hinted) 'hinted': true,
  };

  /// **字段缺/类型不对全走默认** —— 与存档「在默认值上合并」同一口径
  static Quest questFromJson(Map<String, dynamic> j) => Quest(
    serial: j['serial'] is int ? j['serial'] as int : 0,
    kind: j['kind'] is String ? j['kind'] as String : 'daily',
    // 老档兼容：`rings` 时代的单存的是 'ring' / 'ringTotal'
    planIndex: j['planIndex'] is int
        ? j['planIndex'] as int
        : (j['ring'] is int ? j['ring'] as int : -1),
    planTotal: j['planTotal'] is int
        ? j['planTotal'] as int
        : (j['ringTotal'] is int ? j['ringTotal'] as int : 0),
    goalId: j['goalId'] is String ? j['goalId'] as String : '',
    name: j['name'] is String ? j['name'] as String : '',
    reason: j['reason'] is String ? j['reason'] as String : '',
    proof: j['proof'] is String ? j['proof'] as String : '',
    minutes: j['minutes'] is int ? j['minutes'] as int : 15,
    rank: j['rank'] is String ? j['rank'] as String : 'F',
    attrs: j['attrs'] is Map
        ? <String, int>{
            for (final MapEntry<Object?, Object?> e
                in (j['attrs'] as Map).entries)
              if (e.key is String && e.value is int)
                e.key! as String: e.value! as int,
          }
        : const <String, int>{},
    hinted: j['hinted'] == true,
  );

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

  /// 退缩计数（store.js `S.retreatDay / retreatToday / retreatTotal`；
  /// 随存档迁移在 T6 补字段 —— 与 lastDoneDay 同一批）
  DateTime? _retreatDay;
  int _retreatToday = 0;
  int _retreatTotal = 0;

  /// 「口头巨人」戴上之前的称号（store.js `S.prevTitle`）——
  /// 结算交成这一单就换回去（强制期结束，原型 ui.js L609「完成一单再说」）
  String? _titleBeforeShame;

  /// 每张单被退缩过几次（原型 `T.retreated`；key = serial）
  final Map<int, int> _retreated = <int, int>{};

  /// 执行页最多挂 3 张证据（原型 flows.js `snap()` 的 `>= 3` 拦截）
  static const int kMaxEvidence = 3;

  ActiveQuest? get active => _active;
  Quest? get remedyOffer => _remedyOffer;
  DateTime? get remedyDeadline => _remedyDeadline;
  int get failStreak => _failStreak;

  /// 今天退缩了几次 / 累计退缩几次（store.js `S.retreatToday / retreatTotal`）
  int get retreatToday => _retreatToday;
  int get retreatTotal => _retreatTotal;

  /// 「口头巨人」戴上之前的称号（null = 不是从强制期里来的）
  String? get titleBeforeShame => _titleBeforeShame;

  /// 某张单（按 serial）被退缩过几次（原型 `T.retreated`）
  int retreatedTimes(int serial) => _retreated[serial] ?? 0;

  /// 存档通知（原型每个宿主回应末尾的 `this.save()`）：equip/buy/retreat
  /// 改完状态后回调整 —— main.dart 把它接到 `_persist()` 即可（t10 装配）。
  void Function()? onChanged;
  void _notify() => onChanged?.call();

  /// 收官钩子（TODO-01）：最后一环 CLEAR 时铸下一条主线。
  /// 不接 = 叙事停在终点（队列真的会空）；接上 = 自动续主线。
  /// 钩子抛异常 = 拆解失败，**原样往上抛**（不吞、不降级）。
  NextGoalHook? nextGoalHook;

  /// 最近一次收官的结果（界面据此说「下一条主线已经钉好了」）。
  /// 读一次不清空 —— 结算面板可能重建多次。
  FinaleOutcome? get lastFinale => _finaleOutcome;
  FinaleOutcome? _finaleOutcome;

  /// 队首（原型 `Store.head()`；T2 不做演示开关，直接给第一张）
  Quest? get head => queue.isEmpty ? null : queue.first;

  bool get queueEmpty => queue.isEmpty;

  // ── 数值表（docs/18 §2.3；T6 的 rewards.dart 是它最终的家）──────────

  /// 升级曲线：`need(lv) = 12 + lv × 6`（lv1=18 … lv5=42 … lv10=72）
  static int needFor(int lv) => 12 + lv * 6;

  /// E~S 经验表（F 是兼容档：仅老存档/补救残单结算用）
  static const Map<String, int> kExpByRank = <String, int>{
    'F': 0,
    'E': 1,
    'D': 2,
    'C': 4,
    'B': 6,
    'A': 8,
    'S': 10,
  };

  /// E~S 金币表
  static const Map<String, int> kCoinByRank = <String, int>{
    'F': 3,
    'E': 5,
    'D': 5,
    'C': 5,
    'B': 7,
    'A': 10,
    'S': 20,
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
    // ── 批二扩充（TODO-03 模板半批）—— 通用池 14 → 30（与 goal_gen.kDailyCommon 同源同序）──
    DailyTpl('早起后喝一杯水，再做 10 个开合跳', '计时截图', 5, <String, int>{
      '体': 1,
      '力': 1,
    }, 'F'),
    DailyTpl('把手机放到够不着的地方，专注 25 分钟', '计时截图', 30, <String, int>{
      '智': 1,
      '知': 1,
    }, 'E'),
    DailyTpl('走楼梯不坐电梯，上下各两趟', '步数截图', 10, <String, int>{'体': 1, '敏': 1}, 'F'),
    DailyTpl('写三行今天想说的话，写完就合上', '文字截图', 10, <String, int>{'魅': 1, '知': 1}, 'F'),
    DailyTpl('洗一次碗，顺便把台面擦干净', '前后对比照片', 15, <String, int>{'知': 1, '体': 1}, 'F'),
    DailyTpl('靠墙静蹲 3 组，每组 45 秒', '计时截图', 8, <String, int>{'力': 1, '体': 1}, 'E'),
    DailyTpl('把明天的三件事写下来，只写三件', '清单照片', 10, <String, int>{'知': 1, '智': 1}, 'F'),
    DailyTpl('念一段 3 分钟的文字，念出声', '录音截图', 10, <String, int>{'魅': 1, '智': 1}, 'F'),
    DailyTpl('整理一次手机相册，删掉 30 张废片', '相册截图', 15, <String, int>{'知': 1}, 'F'),
    DailyTpl('靠墙站直 10 分钟，别塌肩', '计时截图', 10, <String, int>{'魅': 1, '体': 1}, 'F'),
    DailyTpl('喝水 6 杯，拿杯子凑数不算', '杯子照片', 5, <String, int>{'体': 1}, 'F'),
    DailyTpl('把昨天没做完的那件事补完', '完成截图', 30, <String, int>{'知': 1, '智': 1}, 'D'),
    DailyTpl('快走 20 分钟，不许边刷手机边走', '步数截图', 25, <String, int>{
      '体': 1,
      '敏': 1,
    }, 'E'),
    DailyTpl('手写一页字，慢一点，写整齐', '纸面照片', 15, <String, int>{'敏': 1, '知': 1}, 'F'),
    DailyTpl('今天不喝含糖饮料，一杯都不', '晚上拍一张今天喝过的东西', 5, <String, int>{
      '知': 1,
      '体': 1,
    }, 'F'),
    DailyTpl('睡前 10 分钟回顾今天，想清楚一件做对的事', '笔记照片', 12, <String, int>{
      '知': 1,
      '魅': 1,
    }, 'F'),
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

  /// 队列里同时挂几张**还没做完的计划单**（其余的在主线页上显示「待发布」）。
  /// 宿主原话：「任务却能做不同的」——所以不再一次只钉一张。
  static const int kPlanPublishWindow = 3;

  /// 计划单补发：把清单里还没发布的补到手上（保持 [kPlanPublishWindow] 张）。
  /// 幂等 —— 已经在队列里 / 正在执行的那张不会重复发。
  List<Quest> publishPlanTasks({int window = kPlanPublishWindow}) {
    // ⚠️ 只数**当前这份清单**的单：换过目标的老单不算在手（否则收官补发会少一张）
    final List<Quest> out = <Quest>[];
    int inHand = queue
        .where((Quest q) => q.kind == 'main' && q.goalId == goal.id)
        .length;
    final Quest? act = _active?.task;
    if (act != null && act.kind == 'main' && act.goalId == goal.id) inHand++;
    for (final PlanTask t in goal.plan) {
      if (inHand >= window) break;
      if (t.state != PlanState.todo) continue;
      if (queue.any(
        (Quest q) =>
            q.kind == 'main' && q.goalId == goal.id && q.planIndex == t.index,
      )) {
        continue;
      }
      final Quest q = planTask(t.index);
      queue.add(q);
      out.add(q);
      inHand++;
    }
    if (out.isNotEmpty) {
      // 主线单排到队首、且**按清单顺序**（`queue.add` 会把它们甩到日常后面，
      // 那 `head` 就成了日常 —— 派单板/「去执行」读的都是队首）。
      final List<Quest> mains =
          queue
              .where((Quest q) => q.kind == 'main' && q.goalId == goal.id)
              .toList()
            ..sort((Quest a, Quest b) => a.planIndex.compareTo(b.planIndex));
      queue.removeWhere((q) => q.kind == 'main' && q.goalId == goal.id);
      queue.insertAll(0, mains);
      _syncQueueCount();
    }
    return out;
  }

  /// 单独把清单第 i 张派出来（主线页按住「待发布」那条也能直接接）。
  /// 已经在队列里就返回那一张（不重发、不撞号）。
  Quest? publishPlanTask(int i) {
    final PlanTask? t = goal.taskAt(i);
    if (t == null || t.state != PlanState.todo) return null;
    for (final Quest q in queue) {
      if (q.kind == 'main' && q.goalId == goal.id && q.planIndex == i) return q;
    }
    final Quest q = planTask(i);
    queue.add(q);
    _syncQueueCount();
    return q;
  }

  /// 当前目标的计划补回手上 + 三张日常。
  /// ⚠️ t19/A1：**空目标（没有清单 = 未绑定）什么都不种**——真新档在绑定仪式
  /// 之前不该有主线单也不该有日常（绑定/访谈完成后再由 main 侧播种），
  /// 否则真新用户一进大厅就背三张"别人的"日常。
  void seedForCurrentGoal() {
    if (goal.plan.isEmpty) {
      _syncQueueCount();
      return;
    }
    publishPlanTasks();
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
    int planIndex = -1,
    int planTotal = 0,
    String goalId = '',
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
    planIndex: planIndex,
    planTotal: planTotal,
    goalId: goalId,
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

  /// 清单第 i 张 → 一张主线单（`ringTask` 的接任者）。
  /// 六维直接读清单里那张的分配（`goal_gen.buildPlanTasks` 已按类别倾向算好）。
  Quest planTask(int i) {
    final PlanTask t = goal.plan[i];
    return _mk(
      kind: 'main',
      planIndex: i,
      planTotal: goal.plan.length,
      goalId: goal.id,
      name: t.title,
      proof: t.proof,
      minutes: t.minutes,
      rank: t.rank,
      attrs: t.attrs.isEmpty
          ? splitAttrs(const <String, int>{'体': 1}, Rarity.of(t.rank).pt)
          : t.attrs,
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

    // 一单专治短板，其余随缘（store.js L108 的 plan；贴主线由 planTask 承担）
    for (int i = 0; i < n; i++) {
      if (!(take((DailyTpl d) => (d.a[weak] ?? 0) > 0) || take((_) => true))) {
        break;
      }
    }
    return out;
  }

  // ── 派单前的上下文：给单子写一句"为什么是你"（store.js `reasonFor`）──

  String reasonForMain(int i) {
    if (i > 0 && i < goal.plan.length) {
      final Duration? held = goal.plan[i - 1].held;
      if (held != null) {
        return '上一张你用了 ${fmtDur(held)}。这一张，我加了点码。';
      }
    }
    return '你说要「${goal.text}」。那就从这一步开始。';
  }

  String reasonFor(Quest t) {
    if (t.kind == 'main') return reasonForMain(t.planIndex);
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

  /// 暴击率（store.js `critChance` 的证据联动升级版，docs/18 §2.4）：
  /// 底 6% + **已校验 7%/张 + 未校验 4%/张**（vision.dart `evidenceCritBonus`）
  /// + 连击 1%/天（≤10）+ 暴击芯片 25%，封顶 85%。
  ///
  /// 口径唯一真源 = vision.dart 的 `critChance`（内部已含底值/连击/芯片，
  /// 这里只喂证据计数 —— 基础值与证据加成**不二次叠加**）。
  /// ⚠️ 演示档（streak 6、0 证据、无芯片）= .12 —— 与原写死值一致，实测不回归。
  ///
  /// [verified]/[unverified] 只给测试与预览用（缺省读执行中那单的真实证据）。
  double critChance({int? verified, int? unverified}) {
    final ActiveQuest? a = _active;
    if (a == null) return 0;
    return vision.critChance(
      verified: verified ?? a.verifiedCount,
      unverified: unverified ?? a.unverifiedCount,
      streak: host.streak,
      critItem: a.crit,
    );
  }

  /// 暴击率**底值**（不含证据加成）——t16/B4 显示口径单一真源的另一半：
  /// 执行页手里已经拿着证据列表，它自己加 `evidenceCritBonus`；
  /// 这里若再给全量 [critChance]，证据加成就会被算两遍（gate 实测双计）。
  /// 底值/连击/芯片仍走 vision.critChance 单一公式，只是证据计数归零。
  double critBase() {
    final ActiveQuest? a = _active;
    if (a == null) return 0;
    return vision.critChance(
      verified: 0,
      unverified: 0,
      streak: host.streak,
      critItem: a.crit,
    );
  }

  // ── 执行中单据的持久化（docs/18 §2.8：active 随档走，t16/B3）──────

  /// 执行中单据的快照（任务/计时起点/道具标记/证据）。
  /// 证据只带存档字段（相对路径+状态；absPath 是会话内渲染用的，不进档）。
  Map<String, dynamic>? activeToSaveJson() {
    final ActiveQuest? a = _active;
    if (a == null) return null;
    return <String, dynamic>{
      'task': questToJson(a.task),
      'startAt': a.startAt.toIso8601String(),
      if (a.dbl) 'dbl': true,
      if (a.crit) 'crit': true,
      if (a.shield) 'shield': true,
      'evidence': <Map<String, dynamic>>[
        for (final vision.EvidenceShot s in a.evidence) s.toJson(),
      ],
    };
  }

  /// 从存档恢复执行中单据（杀进程重启后任务/计时起点/证据保持）。
  /// [json] 为 null 或形状不对 = 无执行中单据，静默忽略（合并式迁移口径）。
  void restoreActiveFromJson(Map<String, dynamic>? json) {
    if (json == null) return;
    final Object? taskJson = json['task'];
    if (taskJson is! Map) return;
    final Quest task = questFromJson(Map<String, dynamic>.from(taskJson));
    final DateTime startAt =
        DateTime.tryParse('${json['startAt'] ?? ''}') ?? DateTime.now();
    final ActiveQuest a = ActiveQuest(
      task: task,
      startAt: startAt,
      evidence: <vision.EvidenceShot>[
        if (json['evidence'] is List)
          for (final Object? e in json['evidence'] as List)
            if (e is Map)
              vision.EvidenceShot.fromJson(Map<String, dynamic>.from(e)),
      ],
    );
    if (json['dbl'] == true) a.dbl = true;
    if (json['crit'] == true) a.crit = true;
    if (json['shield'] == true) a.shield = true;
    _active = a;
  }

  // ── 结算（store.js `settle`；提交任务的真正语义）────────────────

  /// 没有执行中的单 → **抛** [StateError]（旧版返回 null，调用方 `?? _result`
  /// 把「没结算」伪装成「结算成功」，正是静默降级）。
  ///
  /// 收官（最后一单）时会 await [nextGoalHook] 去铸下一份计划 —— 那是一次真
  /// LLM 调用，失败会**原样抛**给调用方，不会退化成模板。
  ///
  /// [forceCrit] 只给测试用（demo 也可钉死非暴击：传 false）。
  Future<QuestResult> settle({
    DateTime? now,
    math.Random? rnd,
    bool? forceCrit,
  }) async {
    final ActiveQuest? a = _active;
    if (a == null) {
      throw StateError('settle：没有正在执行的单，没有可结算的东西');
    }
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

    // 计划：把交掉的这张在清单上划掉（顺序锁早已不存在 —— 交哪张都行），
    // 然后补下一张到手上。兑现单交掉 = 这个目标完成（里程碑结算）。
    int planClear = -1;
    bool finale = false;
    if (task.kind == 'main' &&
        task.planIndex >= 0 &&
        task.goalId == goal.id &&
        goal.taskAt(task.planIndex) != null) {
      final List<PlanTask> plan = <PlanTask>[...goal.plan];
      final PlanTask g = plan[task.planIndex];
      if (g.state != PlanState.done) {
        plan[task.planIndex] = g.copyWith(
          state: PlanState.done,
          held: held,
          doneAt: t0,
        );
        goal = goal.copyWith(plan: plan);
        planClear = task.planIndex;
        finale =
            plan[task.planIndex].finalTask ||
            plan.every((PlanTask x) => x.state == PlanState.done);
      }
    }

    // 收官 → 第二目标闭环（TODO-01）：铸下一条主线、撤旧主线单、首环钉队首。
    // 结算**当场落库**（不是等界面点一下）——否则结算页读到的 `empty` 是错的，
    // 宿主会看到【收工。】而其实新主线已经在手上。
    if (finale) {
      // 提档读的是「走过了几张 / 一共几张」——兑现单交掉时就是全部。
      // ⚠️ 拆解失败会从这里抛出去：结算已经落账，但**下一份计划拿不出来**
      //    这件事必须让调用方看见（旧版是静默停在终点）。
      await _applyFinale(
        cleared: goal.doneCount,
        total: goal.plan.length,
        level: host.lv,
      );
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
    // 「口头巨人」强制期结束：这一单交成了 → 换回退缩前的称号
    // （store.js L311 的 unshamed；原型 ui.js L609「完成一单再说」）
    final String? prev = _titleBeforeShame;
    if (host.title == 'mouth' && prev != null) {
      host = host.copyWith(title: prev);
      _titleBeforeShame = null;
    }
    if (titles.isNotEmpty) {
      host = host.copyWith(
        ownedTitles: <String>{...host.ownedTitles, ...titles}.toList(),
        title: host.title == 'mouth' ? host.title : titles.last,
      );
    }

    _active = null;

    // 交掉一张就补一张（保持在手窗口）。⚠️ 必须放在 `_active = null` **之后**：
    // 窗口把"正在执行的那张"也算在内，早一步补发就会每交一张少一格。
    if (!finale && task.kind == 'main') publishPlanTasks();

    // A6：写入执行历史（fire-and-forget——写盘失败不阻塞结算演出）
    historyLog.append(
      HistoryEntry(
        at: t0,
        name: task.name,
        rank: task.rank,
        kind: task.kind,
        exp: exp,
        coin: coin,
        streak: host.streak,
        result: 'clear',
        attrs: Map<String, int>.of(task.attrs),
      ),
    );

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
      planClear: planClear,
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

  // ── 第二目标闭环（TODO-01：finale → 自动续主线 / 换目标落库）────────

  /// 收官：铸下一条主线并**当场落库**。
  ///
  /// 语义 = 原型 `Store.newGoal(plan)`（store.js L170-176）：
  ///   · 旧主线的单全部撤下（`queue.filter(t => t.kind !== 'main')`）
  ///   · 新主线首环**钉在队首**（`queue.unshift(planTask(0))`）
  ///   · 档案里的 `goal` 换成新主线
  ///
  /// 与原型唯一的不同：**日常单保留**（原型 `newGoal` 也保留）。
  /// 没接 [nextGoalHook] 时返回一个 `goal == null` 的结果 —— 叙事真的停在终点
  /// （那是**故意**不接，不是失败）。接了钩子就一定会 await 到一份计划，
  /// 钩子抛什么就往上抛什么。
  Future<FinaleOutcome> _applyFinale({
    required int cleared,
    required int total,
    required int level,
  }) async {
    final Goal prev = goal;
    final NextGoalHook? hook = nextGoalHook;
    if (hook == null) {
      final FinaleOutcome stop = FinaleOutcome(
        cleared: cleared,
        total: total,
        level: level,
        newGoalText: '',
      );
      _finaleOutcome = stop;
      return stop;
    }
    final Goal next = await hook(prev, cleared, total, level);
    if (next.plan.isEmpty) {
      throw StateError('收官钩子交回的目标「${next.text}」没有任务清单');
    }
    queue.removeWhere((Quest q) => q.kind == 'main');
    goal = next;
    final List<Quest> pub = publishPlanTasks();
    _syncQueueCount();
    final FinaleOutcome out = FinaleOutcome(
      cleared: cleared,
      total: total,
      level: level,
      newGoalText: next.text,
      goal: next,
      insertedPlan: pub.isEmpty ? null : pub.first,
    );
    _finaleOutcome = out;
    return out;
  }

  /// 幂等补投：把最近一次收官铸好的新主线首环**再确认一次**钉在队首。
  ///
  /// 结算时已经投过一次（[_applyFinale]），这里只兜两种边角：
  ///   ① 老存档（收官发生在本功能之前）读档后首环不在队列里；
  ///   ② 调用方重复调用（点了两次「下一条主线」）。
  /// 返回这次是否真的动了队列。
  Future<bool> applyFinaleOutcome() async {
    // ① 上一轮收官铸好的新主线，首环没钉上（老档读回 / 上次落盘发生在钉环之前）
    final FinaleOutcome? o = _finaleOutcome;
    final Goal? g = o?.goal;
    if (o != null && g != null && g.plan.isNotEmpty) {
      // 幂等口径：settle 里钉的那张首环单还在队列里 → 什么都不用做。
      // ⚠️ 按 **serial** 认，不按题面 —— `planTask` 每次都发新单号，
      //    按名字判会以为「没有」然后钉进第二张重号单。
      final int? pinned = o.insertedPlan?.serial;
      if (pinned != null &&
          queue.any((Quest q) => q.serial == pinned && q.kind == 'main')) {
        return false;
      }
      queue.removeWhere((Quest q) => q.kind == 'main');
      final List<Quest> pub = publishPlanTasks();
      _finaleOutcome = FinaleOutcome(
        cleared: o.cleared,
        total: o.total,
        level: o.level,
        newGoalText: o.newGoalText,
        goal: g,
        insertedPlan: pub.isEmpty ? null : pub.first,
      );
      return true;
    }
    // ② 读档时这条主线**已经走完了**（收官发生在本功能之前的老存档）——
    //    叙事不该停在终点，补一次「铸下一条 + 钉队首」。
    //    ⚠️ 空目标（未绑定）不在此列：`Goal.empty()` 没有环，不进这个分支。
    if (nextGoalHook != null &&
        goal.plan.isNotEmpty &&
        goal.firstOpenIndex < 0) {
      await _applyFinale(
        cleared: goal.doneCount,
        total: goal.plan.length,
        level: host.lv,
      );
      return _finaleOutcome?.goal != null;
    }
    return false;
  }

  /// 换目标（原型 `Store.newGoal` 的落库语义；TODO-01 的「换目标」入口）：
  /// **旧主线单移除、新主线钉队首**。传进来的 [next] 由调用方铸
  /// （`_buildGoalWithAgent` 拆出来的），这里只负责队列手术与档案替换。
  ///
  /// 返回被钉上队首的那张首单。[next] 没有清单 → **抛** [StateError]
  /// （旧版返回 null，调用方 `if (first == null) return;` 把「新目标没排出来」
  /// 这件事悄悄咽掉：界面看着像换了目标，其实什么都没发生）。
  Quest newGoal(Goal next) {
    if (next.plan.isEmpty) {
      throw StateError('newGoal：目标「${next.text}」没有任务清单，不能落库');
    }
    queue.removeWhere((Quest q) => q.kind == 'main');
    goal = next;
    final List<Quest> pub = publishPlanTasks();
    _syncQueueCount();
    _notify();
    if (pub.isEmpty) {
      throw StateError('newGoal：目标「${next.text}」落库后没有任何一张单被派出来');
    }
    return pub.first;
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
        // 用原单的分配结果当权重再分一次（原单基准维没落库，见 planTask 注）
        attrs: splitAttrs(task.attrs, Rarity.of(rr).pt),
        reason: reasonForRemedy(),
      );
      deadline = t0.add(const Duration(hours: 24));
      _remedyOffer = remedy;
      _remedyDeadline = deadline;
    }
    _active = null;
    _syncQueueCount();
    // A6：认输/超时也入档（exp/coin 记 0——判负不出账），result 区分两者
    historyLog.append(
      HistoryEntry(
        at: t0,
        name: task.name,
        rank: task.rank,
        kind: task.kind,
        exp: 0,
        coin: 0,
        streak: host.streak,
        result: how == 'timeout' ? 'timeout' : 'quit',
      ),
    );
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

  // ── 换一个 / 补给 / 挂称号（store.js retreat / buy / equip）──────────

  /// 挂证据：接到执行中那单上（拍照接线归 t4）。最多 [kMaxEvidence] 张
  /// （原型 flows.js `snap()` 拦在 3）；没接单/已满 → false。
  bool addEvidence(vision.EvidenceShot shot) {
    final ActiveQuest? a = _active;
    if (a == null) return false;
    if (a.evidence.length >= kMaxEvidence) return false;
    a.evidence.add(shot);
    return true;
  }

  /// 撤一张证据（执行页长按删除，按 [id] 找）。没找到/没接单 → false。
  bool removeEvidence(String id) {
    final ActiveQuest? a = _active;
    if (a == null) return false;
    final int n = a.evidence.length;
    a.evidence.removeWhere((vision.EvidenceShot s) => s.id == id);
    return a.evidence.length != n;
  }

  /// 「换一个」（store.js `retreat` L235-250 的全语义）：
  ///  · 当日计数重置（跨天归零）→ retreatToday/Total 各 +1；
  ///  · 累计 ≥3 且还没解锁过 → 强制佩戴「口头巨人」（耻辱称号，禁摘）；
  ///  · 非 F 级：**同一张单**降一档重刻（`rankShift(-1)`，六维按新档点数重分，
  ///    serial 不变 —— 她只是把这张单刻薄了一点）；
  ///  · F 级还退：换**另一张** F 日常顶到这个位置（池子枯了就原样留着）。
  ///
  /// [t] 不在她手里 → null（调用方自行兜底）。
  RetreatOutcome? retreat(Quest t, {DateTime? now}) {
    final int idx = queue.indexWhere((Quest q) => q.serial == t.serial);
    if (idx < 0) return null;
    final DateTime t0 = now ?? DateTime.now();
    final DateTime today = DateTime(t0.year, t0.month, t0.day);
    if (_retreatDay == null || !_isSameDay(_retreatDay!, today)) {
      _retreatDay = today;
      _retreatToday = 0;
    }
    _retreatToday++;
    _retreatTotal++;
    bool shame = false;
    if (_retreatTotal >= 3 && !host.ownedTitles.contains('mouth')) {
      _titleBeforeShame = host.title;
      host = host.copyWith(
        ownedTitles: <String>{...host.ownedTitles, 'mouth'}.toList(),
        title: 'mouth',
      );
      shame = true;
    }

    Quest? replacement;
    if (t.rank == 'F') {
      // F 还退：换一张别的 F（原型 `genDaily(1)[0]` → 钉回 F 档）
      final List<Quest> gen = genDaily(1);
      if (gen.isNotEmpty) {
        final Quest nt = _reRank(gen.first, 'F', reason: reasonFor(gen.first));
        queue[idx] = nt;
        replacement = nt;
      }
    } else {
      final String nr = rankShift(t.rank, -1);
      final Quest nt = _reRank(t, nr);
      queue[idx] = nt;
      replacement = nt;
      _retreated[t.serial] = (_retreated[t.serial] ?? 0) + 1;
    }

    _syncQueueCount();
    _notify();
    return RetreatOutcome(
      task: t,
      replacement: replacement,
      count: _retreatToday,
      total: _retreatTotal,
      shame: shame,
    );
  }

  /// 购买（store.js `buy` L380-384）：买不起/没这个道具 → false；
  /// 成功 = 扣金币 + 道具 +1 + 存档通知。
  bool buy(String id) {
    final Item? it = Item.byId(id);
    if (it == null) return false;
    if (it.lv > 0 && host.lv < it.lv) return false;
    if (host.coins < it.price) return false;
    host = host.copyWith(
      coins: host.coins - it.price,
      items: <String, int>{...host.items, id: (host.items[id] ?? 0) + 1},
    );
    _notify();
    return true;
  }

  /// 补签券（参考稿 useBtn L1633）：持有 −1、连胜 +1。没有 → false。
  bool usePatch() {
    final int n = host.items['patch'] ?? 0;
    if (n <= 0) return false;
    host = host.copyWith(
      items: <String, int>{...host.items, 'patch': n - 1},
      streak: host.streak + 1,
    );
    _notify();
    return true;
  }

  /// 称号佩戴（store.js `equip` L385）：未解锁 → false（忽略）；
  /// 「口头巨人」生效中禁换挂 → false（摘不掉，完成一单再说）；
  /// 成功 = 换挂 + 存档通知 + true（重复点当前称号也成功，原型同款）。
  bool equip(String id) {
    if (!host.ownedTitles.contains(id)) return false;
    if (host.title == 'mouth') return false;
    host = host.copyWith(title: id);
    _notify();
    return true;
  }

  /// 同一张单换个档重刻：六维按新档点数重分。
  /// ⚠️ 本侧没有基准维 baseA，用现分配当权重 —— fail() 的补救单同口径。
  Quest _reRank(Quest q, String rank, {String? reason}) => Quest(
    serial: q.serial,
    kind: q.kind,
    planIndex: q.planIndex,
    planTotal: q.planTotal,
    goalId: q.goalId,
    name: q.name,
    reason: reason ?? q.reason,
    proof: q.proof,
    minutes: q.minutes,
    rank: rank,
    attrs: splitAttrs(q.attrs, Rarity.of(rank).pt),
    hinted: q.hinted,
  );

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// ═══════════════════════════════════════════════════════════
///  A6 数据回顾（t21）：事件级执行历史
///
///  key = `opus-v2/history/v1` —— **独立 key**（与 memory/chat/settings
///  同一惯例）：settle/认输由 [QuestFlow] 追加，回顾面板（stats_pane）读，
///  不经 SaveData（主存档结构不动；新 key 缺省 = 空表，合并迁移天然成立）。
///  滚动上限 400 条；坏档/读失败 → 空表，永不崩。
/// ═══════════════════════════════════════════════════════════

/// 一条战绩。result：clear（结算通过）/ quit（认输）/ timeout（超时判负）。
class HistoryEntry {
  const HistoryEntry({
    required this.at,
    required this.name,
    required this.rank,
    required this.kind,
    required this.exp,
    required this.coin,
    required this.streak,
    required this.result,
    this.attrs = const <String, int>{},
  });

  final DateTime at;
  final String name;
  final String rank;
  final String kind;

  /// 结算出账（认输/超时为 0）
  final int exp;
  final int coin;

  /// 记账后的连击值
  final int streak;
  final String result;
  final Map<String, int> attrs;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'at': at.toIso8601String(),
    'name': name,
    'rank': rank,
    'kind': kind,
    'exp': exp,
    'coin': coin,
    'streak': streak,
    'result': result,
    if (attrs.isNotEmpty) 'attrs': attrs,
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
    at: DateTime.tryParse('${j['at'] ?? ''}') ?? DateTime.now(),
    name: '${j['name'] ?? ''}',
    rank: '${j['rank'] ?? 'F'}',
    kind: '${j['kind'] ?? 'daily'}',
    exp: (j['exp'] as num?)?.toInt() ?? 0,
    coin: (j['coin'] as num?)?.toInt() ?? 0,
    streak: (j['streak'] as num?)?.toInt() ?? 0,
    result: '${j['result'] ?? 'clear'}',
    attrs: j['attrs'] is Map
        ? <String, int>{
            for (final MapEntry<Object?, Object?> e
                in (j['attrs'] as Map).entries)
              if (e.value is int) '${e.key}': e.value! as int,
          }
        : const <String, int>{},
  );
}

class HistoryLog {
  HistoryLog({SharedPreferencesAsync? prefs}) : _injected = prefs;

  /// 独立 key（docs/18 §2.8 惯例）
  static const String key = 'opus-v2/history/v1';

  /// 滚动上限（满了删最旧）
  static const int maxEntries = 400;

  final SharedPreferencesAsync? _injected;
  SharedPreferencesAsync? _prefs;

  SharedPreferencesAsync get _p =>
      _prefs ??= _injected ?? SharedPreferencesAsync();

  /// 旧 → 新；坏档回空表
  Future<List<HistoryEntry>> entries() async {
    try {
      final String? raw = await _p.getString(key);
      if (raw == null || raw.isEmpty) return <HistoryEntry>[];
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return <HistoryEntry>[];
      final List<HistoryEntry> out = <HistoryEntry>[
        for (final Object? e in decoded)
          if (e is Map) HistoryEntry.fromJson(Map<String, dynamic>.from(e)),
      ];
      out.sort((HistoryEntry a, HistoryEntry b) => a.at.compareTo(b.at));
      return out;
    } catch (_) {
      return <HistoryEntry>[];
    }
  }

  /// 追加一条 + 滚动 + 落盘。失败不抛（下次写再试）。
  ///
  /// 内部**串行队列**：read-modify-write 竞态会让并发 append 互相覆盖
  /// （连做两单时第二条吞掉第一条），所以同实例的追加排一条 Future 链。
  Future<void> _tail = Future<void>.value();

  Future<void> append(HistoryEntry e) {
    final Future<void> next = _tail.then((_) async {
      final List<HistoryEntry> all = await entries();
      all.add(e);
      if (all.length > maxEntries) {
        all.removeRange(0, all.length - maxEntries);
      }
      try {
        await _p.setString(
          key,
          jsonEncode(<Map<String, dynamic>>[
            for (final HistoryEntry h in all) h.toJson(),
          ]),
        );
      } catch (_) {}
    });
    _tail = next.catchError((Object _) {});
    return next;
  }

  /// 概览聚合（纯函数，UI 与测试共用）。[now] 决定「最近 7 天」窗口。
  static WeekSummary summarize(List<HistoryEntry> all, DateTime now) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    final List<HistoryEntry> week = all
        .where(
          (HistoryEntry e) => !DateTime(
            e.at.year,
            e.at.month,
            e.at.day,
          ).isBefore(today.subtract(const Duration(days: 6))),
        )
        .toList();
    final Map<String, int> dayAttrs = <String, int>{
      for (final String k in Attr.names.keys) k: 0,
    };
    final List<Map<String, int>> dayAttrsByDay =
        List<Map<String, int>>.generate(7, (_) => <String, int>{});
    final List<int> dayDone = List<int>.filled(7, 0);
    int totalExp = 0, totalCoin = 0, bestStreak = 0;
    for (final HistoryEntry e in week) {
      totalExp += e.exp;
      totalCoin += e.coin;
      bestStreak = math.max(bestStreak, e.streak);
      final int idx =
          6 -
          today.difference(DateTime(e.at.year, e.at.month, e.at.day)).inDays;
      if (idx >= 0 && idx < 7) {
        if (e.result == 'clear') dayDone[idx] += 1;
        for (final MapEntry<String, int> a in e.attrs.entries) {
          dayAttrs[a.key] = (dayAttrs[a.key] ?? 0) + a.value;
          dayAttrsByDay[idx][a.key] =
              (dayAttrsByDay[idx][a.key] ?? 0) + a.value;
        }
      }
    }
    final List<HistoryEntry> recent = all.length <= 8
        ? all.reversed.toList()
        : all.sublist(all.length - 8).reversed.toList();
    return WeekSummary(
      doneCount: week.where((HistoryEntry e) => e.result == 'clear').length,
      totalExp: totalExp,
      totalCoin: totalCoin,
      bestStreak: bestStreak,
      dayDone: dayDone,
      dayAttrs: dayAttrs,
      dayAttrsByDay: dayAttrsByDay,
      recent: recent,
    );
  }
}

/// 回顾面板的聚合结果（最近 7 天窗口）
class WeekSummary {
  const WeekSummary({
    required this.doneCount,
    required this.totalExp,
    required this.totalCoin,
    required this.bestStreak,
    required this.dayDone,
    required this.dayAttrs,
    required this.dayAttrsByDay,
    required this.recent,
  });

  final int doneCount;
  final int totalExp;
  final int totalCoin;
  final int bestStreak;

  /// 7 列完成数（0=6 天前 … 6=今天）
  final List<int> dayDone;

  /// 7 天窗口内各维增量（总量）
  final Map<String, int> dayAttrs;

  /// **逐日**各维增量（0=6 天前 … 6=今天；列内 维→增量）——
  /// 回顾面板的 7 根条每根读自己那一列，别再共用总量
  final List<Map<String, int>> dayAttrsByDay;

  /// 最近 ≤8 条（新 → 旧）
  final List<HistoryEntry> recent;
}
