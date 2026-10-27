import '../data/format.dart';

/// ═══════════════════════════════════════════════════════════
///  目标 = 一句话 + 期限 + 一张**任务清单**（docs/33 废除「环」）
///
///  旧模型 `PlanTask` 被删掉了：那一个「环」同时兼三个身份
///  （数据结构 / 工作单元 / 视觉），于是任何目标都被迫切成 5~8 格、
///  每格必须是"一次做完"——「半年内坚持健身」两条都不满足。
///
///  现在：
///    · [PlanTask] = 计划里的一张**任务**（唯一工作单元，单次可执行）
///    · [Goal.plan] = 期限内的任务清单（条数由期限算，不是固定 5~8）
///    · 顺序锁消失：清单里任意一张未完成的都能直接接（`accept()` 从不判环）
///    · 视觉上的「8 条等宽虚线」→ 一条进度带（见 `stage/progress_band.dart`）
/// ═══════════════════════════════════════════════════════════

/// 计划里一张单的状态。
///
///  · [todo]      还没派 / 已派在队列里等接（界面按队列区分「待发布 / 可接」）
///  · [active]    正在执行（全局同时只有一张）
///  · [done]      已完成（记了用时与完成时刻）
///  · [abandoned] 宿主放弃主线时一起废掉的（灰、只读）
enum PlanState {
  todo,
  active,
  done,
  abandoned;

  static PlanState of(String s) => switch (s) {
    'active' || 'cur' => PlanState.active,
    'done' => PlanState.done,
    'abandoned' => PlanState.abandoned,
    _ => PlanState.todo,
  };
}

/// 计划里的一张单 —— 「任务」就是它，没有别的身份。
class PlanTask {
  const PlanTask({
    required this.index,
    required this.short,
    required this.title,
    required this.proof,
    required this.minutes,
    required this.rank,
    this.attrs = const <String, int>{},
    this.state = PlanState.todo,
    this.finalTask = false,
    this.held,
    this.doneAt,
  });

  /// 计划内序号（0 基）—— 只用于显示「第几张」，不是执行顺序
  final int index;

  /// 短名（挂在进度带上 / 大牌角标）
  final String short;

  /// 牌面题面
  final String title;

  /// 怎么证明
  final String proof;

  /// 时限（分钟）
  final int minutes;

  final String rank;

  /// 六维加成（生成时就定死，结算只读它）
  final Map<String, int> attrs;

  final PlanState state;

  /// 兑现单：它完成 = 这个目标完成（里程碑结算）
  final bool finalTask;

  /// 已完成：用了多久 / 什么时候完成
  final Duration? held;
  final DateTime? doneAt;

  bool get done => state == PlanState.done;
  bool get open => state == PlanState.todo || state == PlanState.active;

  /// 详情面板里那一句状态描述
  String statusText() {
    switch (state) {
      case PlanState.done:
        final String when = doneAt == null
            ? '—'
            : '${doneAt!.month}/${doneAt!.day}';
        final String dur = held == null ? '—' : fmtDur(held!);
        return '已完成 · $when · 用时 $dur';
      case PlanState.active:
        return '正在执行';
      case PlanState.abandoned:
        return '已放弃';
      case PlanState.todo:
        return '待发布';
    }
  }

  PlanTask copyWith({
    int? index,
    String? short,
    String? title,
    String? proof,
    int? minutes,
    String? rank,
    Map<String, int>? attrs,
    PlanState? state,
    bool? finalTask,
    Duration? held,
    DateTime? doneAt,
  }) => PlanTask(
    index: index ?? this.index,
    short: short ?? this.short,
    title: title ?? this.title,
    proof: proof ?? this.proof,
    minutes: minutes ?? this.minutes,
    rank: rank ?? this.rank,
    attrs: attrs ?? this.attrs,
    state: state ?? this.state,
    finalTask: finalTask ?? this.finalTask,
    held: held ?? this.held,
    doneAt: doneAt ?? this.doneAt,
  );

  // ── 存档 ──────────────────────────────────────────────────

  factory PlanTask.fromJson(Map<String, dynamic> j, {int index = 0}) =>
      PlanTask(
        index: j['index'] is int ? j['index'] as int : index,
        short: j['short'] is String ? j['short'] as String : '',
        title: j['title'] is String ? j['title'] as String : '',
        proof: j['proof'] is String ? j['proof'] as String : '',
        minutes: j['minutes'] is int ? j['minutes'] as int : 0,
        rank: j['rank'] is String ? j['rank'] as String : 'F',
        attrs: j['attrs'] is Map
            ? <String, int>{
                for (final MapEntry<Object?, Object?> e
                    in (j['attrs'] as Map).entries)
                  if (e.key is String && e.value is int)
                    e.key! as String: e.value! as int,
              }
            : const <String, int>{},
        state: PlanState.of(j['state'] is String ? j['state'] as String : ''),
        finalTask: j['final'] == true,
        held: j['heldMs'] is int
            ? Duration(milliseconds: j['heldMs'] as int)
            : null,
        doneAt: j['doneAt'] is String
            ? DateTime.tryParse(j['doneAt'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'index': index,
    'short': short,
    'title': title,
    'proof': proof,
    'minutes': minutes,
    'rank': rank,
    if (attrs.isNotEmpty) 'attrs': attrs,
    'state': state.name,
    'final': finalTask,
    if (held != null) 'heldMs': held!.inMilliseconds,
    if (doneAt != null) 'doneAt': doneAt!.toIso8601String(),
  };
}

/// 一句话目标 → 期限 + 任务清单（真源 `goal_gen.buildPlan`）。
///
/// plan 元数据（docs/18 §2.1 / §3.1-T6）：[cat] 目标类型、[days] 期限天数、
/// [interview] 访谈答案（卡 id → 答案）。三者也随存档持久化，供任务生成
/// 与小祥记忆读取；老存档缺这些字段时在 fallback 上合并出默认值。
class Goal {
  const Goal({
    required this.text,
    required this.short,
    required this.at,
    required this.plan,
    this.cat = '',
    this.days = 0,
    this.interview = const <String, String>{},
    this.uid = '',
  });

  final String text;

  /// 天幕上那个大字（`goal.short`）
  final String short;

  /// 立目标的时间（显示「起于 X 月 X 日」）
  final DateTime at;

  /// 期限内的任务清单 —— 计划里几张单就是它
  final List<PlanTask> plan;

  /// 目标类型 id（`run/slim/fit/lang/exam/sleep/make/code/bold/gen`）
  final String cat;

  /// 期限（天）。任务数由它算（`goal_gen.planTaskCountFor`）。
  final int days;

  /// 访谈答案（卡 id → 答案原文）—— 访谈即第一批记忆，也供任务生成读取。
  final Map<String, String> interview;

  /// 显式身份（演示档等）；一般留空，由 [id] 按立目标时刻推。
  final String uid;

  /// 目标身份 —— 任务单靠它认领「我是这份清单里的第几张」。
  /// 换目标时会撤掉旧主线单，所以立目标时刻足以区分（`at` 沿用是刻意的）。
  String get id => uid.isNotEmpty ? uid : 'g${at.millisecondsSinceEpoch}';

  int get doneCount =>
      plan.where((PlanTask t) => t.state == PlanState.done).length;

  /// 清单总条数（进度带的分母）
  int get totalTasks => plan.length;

  /// 清单里第一张还没做完的（null = 全部走完）
  int get firstOpenIndex {
    for (int i = 0; i < plan.length; i++) {
      if (plan[i].state == PlanState.todo ||
          plan[i].state == PlanState.active) {
        return i;
      }
    }
    return -1;
  }

  PlanTask? taskAt(int i) => (i >= 0 && i < plan.length) ? plan[i] : null;

  String get startedText => '${at.month} 月 ${at.day} 日';

  /// 已过天数（第 1 天 = 立目标当天）
  int passedDays(DateTime now) {
    final int d =
        DateTime(
          now.year,
          now.month,
          now.day,
        ).difference(DateTime(at.year, at.month, at.day)).inDays +
        1;
    return d < 1 ? 1 : d;
  }

  /// 剩余天数（可以为负 = 已超期）
  int remainingDays(DateTime now) => days - passedDays(now);

  /// 抬头那一行读数：`已过 N/M 天 · 完成 X 单`
  String progressText(DateTime now) =>
      '已过 ${passedDays(now)}/$days 天 · 完成 $doneCount 单';

  /// 演示档（原型 `Store.veteran()` 那条主线）：8 张单，前 4 张已完成。
  static const List<PlanTask> _demoPlan = <PlanTask>[
    PlanTask(
      index: 0,
      short: '穿上跑鞋',
      title: '换上跑鞋，出门快走 15 分钟',
      proof: '运动 App 记录或出门自拍',
      minutes: 20,
      rank: 'F',
      state: PlanState.done,
      held: Duration(minutes: 11, seconds: 56),
    ),
    PlanTask(
      index: 1,
      short: '第一公里',
      title: '慢跑 1 公里。可以慢，不许停',
      proof: '跑步 App 截图',
      minutes: 20,
      rank: 'E',
      state: PlanState.done,
      held: Duration(minutes: 19, seconds: 36),
    ),
    PlanTask(
      index: 2,
      short: '两公里不停',
      title: '慢跑 2 公里，中途不走路',
      proof: '跑步 App 截图',
      minutes: 25,
      rank: 'D',
      state: PlanState.done,
      held: Duration(minutes: 23, seconds: 25),
    ),
    PlanTask(
      index: 3,
      short: '三公里',
      title: '跑完 3 公里，配速随你',
      proof: '跑步 App 截图',
      minutes: 35,
      rank: 'D',
      state: PlanState.done,
      held: Duration(minutes: 38, seconds: 34),
    ),
    PlanTask(
      index: 4,
      short: '五公里',
      title: '跑完 5 公里',
      proof: '跑步 App 截图',
      minutes: 45,
      rank: 'C',
      state: PlanState.active,
    ),
    PlanTask(
      index: 5,
      short: '八公里',
      title: '跑完 8 公里，跑后拉伸 10 分钟',
      proof: '跑步 App 截图 + 拉伸照片',
      minutes: 70,
      rank: 'B',
    ),
    PlanTask(
      index: 6,
      short: '十公里',
      title: '跑完 10 公里',
      proof: '跑步 App 截图',
      minutes: 80,
      rank: 'A',
    ),
    PlanTask(
      index: 7,
      short: '半马',
      title: '三个月跑完半马——兑现它',
      proof: '能证明你做到了的截图',
      minutes: 120,
      rank: 'S',
      finalTask: true,
    ),
  ];

  /// 与原型 `Store.veteran()` 一致的那条主线。
  /// `at` 用「今天」——原型就是 `Clock.now()`，所以「起于 X 月 X 日」每天都变。
  static Goal demo() => Goal(
    text: '三个月跑完半马',
    short: '半马',
    at: DateTime.now(),
    plan: _demoPlan,
    cat: 'run',
    // 演示档那条主线的期限就是「三个月」（清单只有 8 张 = 环时代的残留形态，
    // 期限仍按 90 天念，否则抬头会写「已过 1/8 天」）
    days: 90,
    uid: 'demo',
  );

  /// 未绑定：没有目标也没有任务
  factory Goal.empty() =>
      Goal(text: '', short: '', at: DateTime.now(), plan: const <PlanTask>[]);

  bool get isEmpty => plan.isEmpty;

  // ── 存档（「在默认值上合并」）─────────────────────────────

  factory Goal.fromJson(Map<String, dynamic>? json, {required Goal fallback}) {
    if (json == null) return fallback;
    final Object? rawPlan = json['plan'] ?? json['rings'];
    if (rawPlan is! List) return fallback;
    final List<PlanTask> plan = <PlanTask>[
      for (int i = 0; i < rawPlan.length; i++)
        if (rawPlan[i] is Map)
          PlanTask.fromJson(
            Map<String, dynamic>.from(rawPlan[i] as Map),
            index: i,
          ),
    ];
    if (plan.isEmpty) return fallback;
    // ⚠️ 老存档迁移：`rings` 时代没有 `plan`，`days` 存的是环数（5~8）——
    //    期限按**清单条数**兜底，别把"8 环"当成"8 天"。
    final bool migrated = json['plan'] is! List;
    final int days = json['days'] is int
        ? (migrated ? plan.length : json['days'] as int)
        : fallback.days;
    return Goal(
      text: json['text'] is String ? json['text'] as String : fallback.text,
      short: json['short'] is String ? json['short'] as String : fallback.short,
      at: json['at'] is String
          ? (DateTime.tryParse(json['at'] as String) ?? fallback.at)
          : fallback.at,
      cat: json['cat'] is String ? json['cat'] as String : fallback.cat,
      days: days < 1 ? plan.length : days,
      interview: json['interview'] is Map
          ? <String, String>{
              for (final MapEntry<Object?, Object?> e
                  in (json['interview'] as Map).entries)
                if (e.key is String && e.value is String)
                  e.key! as String: e.value! as String,
            }
          : fallback.interview,
      plan: plan,
      uid: json['uid'] is String ? json['uid'] as String : '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'text': text,
    'short': short,
    'at': at.toIso8601String(),
    'cat': cat,
    'days': days,
    'interview': interview,
    if (uid.isNotEmpty) 'uid': uid,
    'plan': <Map<String, dynamic>>[for (final PlanTask t in plan) t.toJson()],
  };

  Goal copyWith({
    String? text,
    String? short,
    DateTime? at,
    List<PlanTask>? plan,
    String? cat,
    int? days,
    Map<String, String>? interview,
    String? uid,
  }) => Goal(
    text: text ?? this.text,
    short: short ?? this.short,
    at: at ?? this.at,
    plan: plan ?? this.plan,
    cat: cat ?? this.cat,
    days: days ?? this.days,
    interview: interview ?? this.interview,
    uid: uid ?? this.uid,
  );
}
