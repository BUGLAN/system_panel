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
}

/// 一句话目标 → 5~8 环主线链（真源 `makeGoal`）
class Goal {
  const Goal({
    required this.text,
    required this.short,
    required this.at,
    required this.rings,
  });

  final String text;

  /// 天幕上那个大字（`goal.short`）
  final String short;

  /// 立目标的时间 —— 原型是 `Clock.now()`，所以显示的是「今天」
  final DateTime at;

  final List<GoalRing> rings;

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
}
