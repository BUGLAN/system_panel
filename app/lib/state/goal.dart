import '../data/format.dart';

/// 一环的状态（原型里是字符串 `done` / `cur` / `lock`）
enum RingState {
  done,
  cur,
  lock;

  static RingState of(String s) => switch (s) {
    'done' => RingState.done,
    'cur' => RingState.cur,
    _ => RingState.lock,
  };
}

/// 主线的一环 —— 真源 prototype/opus-v2-dir/js/store.js `makeGoal()`。
class GoalRing {
  const GoalRing({
    required this.short,
    required this.title,
    required this.proof,
    required this.minutes,
    required this.rank,
    required this.state,
    this.finalRing = false,
    this.held,
    this.doneAt,
  });

  /// 挂在环上的短名（`g.n`）
  final String short;

  /// 详情卡里的标题（`g.t`）
  final String title;

  /// 怎么证明（`g.p`）
  final String proof;

  /// 时限（分钟，`g.m`）
  final int minutes;

  final String rank;
  final RingState state;

  /// 「她头顶那一环」
  final bool finalRing;

  /// 已完成：用了多久 / 什么时候完成
  final Duration? held;
  final DateTime? doneAt;

  /// `MainV.detail()` 里那一句状态描述
  String statusText() {
    switch (state) {
      case RingState.done:
        final bool hasDate = doneAt != null;
        final String when = hasDate ? '${doneAt!.month}/${doneAt!.day}' : '—';
        final String dur = held == null ? '—' : fmtDur(held!);
        return '已完成 · $when · 用时 $dur';
      case RingState.cur:
        return '你在这一环';
      case RingState.lock:
        return '未解锁';
    }
  }

  // ── 存档 ──────────────────────────────────────────────────

  factory GoalRing.fromJson(Map<String, dynamic> j) => GoalRing(
    short: j['short'] is String ? j['short'] as String : '',
    title: j['title'] is String ? j['title'] as String : '',
    proof: j['proof'] is String ? j['proof'] as String : '',
    minutes: j['minutes'] is int ? j['minutes'] as int : 0,
    rank: j['rank'] is String ? j['rank'] as String : 'F',
    state: RingState.of(j['state'] is String ? j['state'] as String : 'lock'),
    finalRing: j['final'] == true,
    held: j['heldMs'] is int
        ? Duration(milliseconds: j['heldMs'] as int)
        : null,
    doneAt: j['doneAt'] is String
        ? DateTime.tryParse(j['doneAt'] as String)
        : null,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'short': short,
    'title': title,
    'proof': proof,
    'minutes': minutes,
    'rank': rank,
    'state': state.name,
    'final': finalRing,
    if (held != null) 'heldMs': held!.inMilliseconds,
    if (doneAt != null) 'doneAt': doneAt!.toIso8601String(),
  };
}

/// 一句话目标 → 主线链（真源 `makeGoal`；老链 5~8 环，首次新目标 3 天 3 环）。
///
/// plan 元数据（docs/18 §2.1 / §3.1-T6）：[cat] 目标类型、[days] 周期天数、
/// [interview] 访谈答案（卡 id → 答案）。三者也随存档持久化，供周期任务
/// 生成与小祥记忆读取；老存档缺这些字段时在 fallback 上合并出默认值。
class Goal {
  const Goal({
    required this.text,
    required this.short,
    required this.at,
    required this.rings,
    this.cat = '',
    this.days = 0,
    this.interview = const <String, String>{},
  });

  final String text;

  /// 天幕上那个大字（`goal.short`）
  final String short;

  /// 立目标的时间 —— 原型是 `Clock.now()`，所以显示的是「今天」
  final DateTime at;

  final List<GoalRing> rings;

  /// 目标类型 id（`run/slim/fit/lang/exam/sleep/make/code/bold/gen`，
  /// 原型 `CATS` 十类）—— 空串表示老存档/未识别（`goal_gen.dart`）。
  final String cat;

  /// 周期天数：首次新目标 = 3（每天一环，docs/18 §2.1）；0 = 未按天规划（老链/演示档）。
  final int days;

  /// 访谈答案（卡 id → 答案原文）—— 访谈即第一批记忆，也供周期任务生成读取。
  final Map<String, String> interview;

  int get doneCount =>
      rings.where((GoalRing r) => r.state == RingState.done).length;

  int get currentIndex =>
      rings.indexWhere((GoalRing r) => r.state == RingState.cur);

  String get startedText => '${at.month} 月 ${at.day} 日';

  static const List<GoalRing> _demoRings = <GoalRing>[
    GoalRing(
      short: '穿上跑鞋',
      title: '换上跑鞋，出门快走 15 分钟',
      proof: '运动 App 记录或出门自拍',
      minutes: 20,
      rank: 'F',
      state: RingState.done,
      held: Duration(minutes: 11, seconds: 56),
    ),
    GoalRing(
      short: '第一公里',
      title: '慢跑 1 公里。可以慢，不许停',
      proof: '跑步 App 截图',
      minutes: 20,
      rank: 'E',
      state: RingState.done,
      held: Duration(minutes: 19, seconds: 36),
    ),
    GoalRing(
      short: '两公里不停',
      title: '慢跑 2 公里，中途不走路',
      proof: '跑步 App 截图',
      minutes: 25,
      rank: 'D',
      state: RingState.done,
      held: Duration(minutes: 23, seconds: 25),
    ),
    GoalRing(
      short: '三公里',
      title: '跑完 3 公里，配速随你',
      proof: '跑步 App 截图',
      minutes: 35,
      rank: 'D',
      state: RingState.done,
      held: Duration(minutes: 38, seconds: 34),
    ),
    GoalRing(
      short: '五公里',
      title: '跑完 5 公里',
      proof: '跑步 App 截图',
      minutes: 45,
      rank: 'C',
      state: RingState.cur,
    ),
    GoalRing(
      short: '八公里',
      title: '跑完 8 公里，跑后拉伸 10 分钟',
      proof: '跑步 App 截图 + 拉伸照片',
      minutes: 70,
      rank: 'B',
      state: RingState.lock,
    ),
    GoalRing(
      short: '十公里',
      title: '跑完 10 公里',
      proof: '跑步 App 截图',
      minutes: 80,
      rank: 'A',
      state: RingState.lock,
    ),
    GoalRing(
      short: '半马',
      title: '三个月跑完半马——兑现它',
      proof: '能证明你做到了的截图',
      minutes: 120,
      rank: 'S',
      state: RingState.lock,
      finalRing: true,
    ),
  ];

  /// 与原型 `Store.veteran()` 一致的那条主线。
  /// `at` 用「今天」——原型就是 `Clock.now()`，所以「起于 X 月 X 日」每天都变。
  static Goal demo() =>
      Goal(text: '三个月跑完半马', short: '半马', at: DateTime.now(), rings: _demoRings);

  /// 未绑定：没有目标也没有环
  factory Goal.empty() =>
      Goal(text: '', short: '', at: DateTime.now(), rings: const <GoalRing>[]);

  bool get isEmpty => rings.isEmpty;

  // ── 存档（store.js L34-52 的"在默认值上合并"）──────────────

  factory Goal.fromJson(Map<String, dynamic>? json, {required Goal fallback}) {
    if (json == null || json['rings'] is! List) return fallback;
    final List<GoalRing> rings = <GoalRing>[
      for (final Object? r in json['rings'] as List)
        if (r is Map) GoalRing.fromJson(Map<String, dynamic>.from(r)),
    ];
    if (rings.isEmpty) return fallback;
    return Goal(
      text: json['text'] is String ? json['text'] as String : fallback.text,
      short: json['short'] is String ? json['short'] as String : fallback.short,
      at: json['at'] is String
          ? (DateTime.tryParse(json['at'] as String) ?? fallback.at)
          : fallback.at,
      cat: json['cat'] is String ? json['cat'] as String : fallback.cat,
      days: json['days'] is int ? json['days'] as int : fallback.days,
      interview: json['interview'] is Map
          ? <String, String>{
              for (final MapEntry<Object?, Object?> e
                  in (json['interview'] as Map).entries)
                if (e.key is String && e.value is String)
                  e.key! as String: e.value! as String,
            }
          : fallback.interview,
      rings: rings,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'text': text,
    'short': short,
    'at': at.toIso8601String(),
    'cat': cat,
    'days': days,
    'interview': interview,
    'rings': <Map<String, dynamic>>[for (final GoalRing r in rings) r.toJson()],
  };

  Goal copyWith({
    String? text,
    String? short,
    DateTime? at,
    List<GoalRing>? rings,
    String? cat,
    int? days,
    Map<String, String>? interview,
  }) => Goal(
    text: text ?? this.text,
    short: short ?? this.short,
    at: at ?? this.at,
    rings: rings ?? this.rings,
    cat: cat ?? this.cat,
    days: days ?? this.days,
    interview: interview ?? this.interview,
  );
}
