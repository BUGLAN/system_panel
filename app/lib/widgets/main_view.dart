import 'dart:math' as math;
import 'dart:ui' show BlurStyle, MaskFilter, PathMetric;

import 'package:flutter/material.dart';

import '../data/format.dart';
import '../data/rarity.dart';
import '../data/rewards.dart';
import '../design/tokens.dart';
import '../state/goal.dart';
import '../state/haptics.dart';
import '../state/sfx.dart';
import 'card_table.dart';
import 'press_scale.dart';
import 'rail_base.dart';

/// ═══════════════════════════════════════════════════════════
///  主线页（2026-10-12 重设计）—— 竖牌扇 + 牌屉
///
///  ⚠️ **第一优先级：不许挡住她的脸。**
///  她的头 / 脸落在屏高 **20%~42%**（`StageAnchors.eyes` = 27%），
///  所以整页 UI 只允许出现在 **45%~86% 的安全带**里：
///    · 抬头（目标名 / 进度读数）在她头顶之上 —— 安全，不动
///    · 牌扇 + 刻度轨在安全带里左右滑动
///    · 详情 = 从底部升起的**牌屉**（不是居中大牌 —— 那正是原来挡脸的元凶）
///
///  旧形态已退役：`CardSkin.duty` 横条牌 268×58（stride 66 / dx1 6px）本质是
///  列表项不是牌，而且三张一叠正压在她脸上（截图①落在 21%~42%）。
///
///  手感全部走既有真源：牌扇 = [CardTable]（拖拽跟手 / 动量投影 / 档位咬合
///  `rung` + 轻震 / 落定 `seal` + 压印），本页**不自己实现任何手势**。
/// ═══════════════════════════════════════════════════════════
class MainView extends StatelessWidget {
  const MainView({
    super.key,
    required this.goal,
    this.published = const <int>{},
    this.activeIndex,
    this.selected,
    this.elapsed,
    this.canDispatch = false,
    this.visible = true,
    this.now,
    this.onClose,
    this.onDispatch,
    this.onNewGoal,
    this.onSelect,
    this.onAccept,
  });

  final Goal goal;

  /// 队列里已经有单的计划序号（可接）；不在里面的未完成单 = 待发布
  final Set<int> published;

  /// 正在执行的那一张（null = 没有）
  final int? activeIndex;

  /// 展开的那一张（牌屉态）
  final int? selected;

  /// 执行中那张的计时读数（`12:04`），由 main 侧每秒推进
  final String? elapsed;

  /// 是否给「去执行」那颗主按钮
  final bool canDispatch;

  final bool visible;

  final DateTime? now;
  final VoidCallback? onClose;
  final VoidCallback? onDispatch;
  final VoidCallback? onNewGoal;
  final ValueChanged<int>? onSelect;
  final ValueChanged<int>? onAccept;

  // ── 安全带（屏高比例）────────────────────────────────────
  //
  // 这两个数是本页的**核心约束**，不是审美偏好：脸在 20%~42%，
  // 45% 起才允许放东西；86% 以下留给底部两颗键。
  static const double kSafeTop = .45;
  static const double kSafeBottom = .86;

  /// 刻度轨最多分几格（再长就分组 —— 单格只有几像素，靠擦洗而不是靠点准）
  static const int kScaleSlots = 40;

  /// 轨上同时显示几张
  static const int kRailMax = 6;

  /// 轨上显示的序号：从第一张没做完的往前带一张（给点上下文），
  /// 往后最多 [kRailMax] 张 —— 清单一长（半年 = 180 张）也不会铺满屏。
  List<int> railIndices() {
    final int n = goal.plan.length;
    if (n == 0) return const <int>[];
    final int open = goal.firstOpenIndex;
    final int first = open < 0 ? n - 1 : open;
    final int start = math.max(0, first - 1);
    final int end = math.min(n, start + kRailMax);
    return <int>[for (int i = start; i < end; i++) i];
  }

  DutyState stateOf(int i) {
    final PlanTask t = goal.plan[i];
    if (t.state == PlanState.done) return DutyState.done;
    if (t.state == PlanState.abandoned) return DutyState.abandoned;
    if (activeIndex == i || t.state == PlanState.active) {
      return DutyState.active;
    }
    return published.contains(i) ? DutyState.open : DutyState.sealed;
  }

  TableCard cardOf(int i, {bool lead = false}) {
    final PlanTask t = goal.plan[i];
    final DutyState st = stateOf(i);
    return TableCard(
      id: 'duty.$i',
      kicker: 'MAIN · ${(i + 1).toString().padLeft(2, '0')}',
      title: t.title,
      glyph: t.attrs.isEmpty ? null : t.attrs.keys.first,
      rank: t.rank,
      accent: Rarity.of(t.rank).color,
      loot: lootOf(t),
      dutyState: st,
      dutyMeta: '${fmtMin(t.minutes)} · ${t.proof}',
      elapsed: st == DutyState.active ? elapsed : null,
      sealWord: st == DutyState.done ? '已完成' : null,
      enabled: st == DutyState.open,
      locked: st == DutyState.sealed,
      index: i + 1,
      // ⑧ 批注：这一段原来没数据，`_dutyFull` 的 Spacer 于是留出一整片空
      //    （详情"空牌"的病根）。她的口吻，不是状态标签。
      note: _noteOf(st),
    );
  }

  /// ⑧ 她的批注（按五态给她的一句话 —— 不是状态文字）
  static String _noteOf(DutyState s) => switch (s) {
    DutyState.open => '接了就开计时。',
    DutyState.active => '计时中。别磨蹭。',
    DutyState.sealed => '还没派到你手上。',
    DutyState.done => '这单已经记在账上了。',
    DutyState.abandoned => '这单作废了。',
  };

  static List<String> lootOf(PlanTask t) {
    final Payout p = Rewards.payout(rank: t.rank, crit: false, dbl: false);
    return <String>[
      'EXP ${p.exp}',
      '◈ ${p.coin}',
      for (final MapEntry<String, int> e in t.attrs.entries)
        '${e.key}+${e.value}',
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 400),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              final double top = box.maxHeight * kSafeTop;
              final double band = box.maxHeight * (kSafeBottom - kSafeTop);
              final bool detail =
                  selected != null && goal.taskAt(selected!) != null;
              return Stack(
                children: <Widget>[
                  _top(),
                  if (goal.plan.isEmpty)
                    _empty(top, band)
                  else if (detail)
                    _drawer(selected!, top, band, box.maxWidth - 32)
                  else
                    _fan(top, band),
                  _low(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// 抬头：目标一句 + 期限内进度（在她头顶之上，安全区，形态不动）
  Widget _top() {
    final DateTime t0 = now ?? DateTime.now();
    return Positioned(
      left: 20,
      right: 20,
      top: 22,
      child: Row(
        key: const Key('main.top'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  height: 19.2,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      'MAINLINE · 主线',
                      key: const Key('main.kicker'),
                      style: fs(
                        family: F.mono,
                        size: 10,
                        wght: 400,
                        ls: 1.6,
                        color: C.blue,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Text(
                    goal.text,
                    key: const Key('main.title'),
                    style: fs(
                      family: F.hd,
                      size: 22,
                      wght: 400,
                      ls: .44,
                      height: 1.25,
                      color: C.ice,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // 读数口径：`已过 N/M 天 · 完成 X 单`（docs/33 §7.5）
                Text(
                  goal.days <= 0
                      ? '完成 ${goal.doneCount} 单'
                      : goal.progressText(t0),
                  key: const Key('main.progress'),
                  style: fs(
                    family: F.mono,
                    size: 11,
                    wght: 600,
                    ls: 1.1,
                    color: C.mist,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onClose,
            behavior: HitTestBehavior.opaque,
            child: Container(
              key: const Key('main.close'),
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x99040E20),
                border: Border.all(color: C.line, width: 1),
              ),
              child: Text(
                '×',
                style: fs(
                  family: F.cn,
                  size: 22,
                  wght: 400,
                  height: 1,
                  color: C.ice,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 牌扇 + **竖向刻度轨** —— 全部落在安全带（45%~86%）里
  Widget _fan(double top, double band) {
    final List<int> idx = railIndices();
    if (idx.isEmpty) return const SizedBox.shrink();
    // 领位落在「第一张没做完的」那一张上（和旧口径一致）
    final int open = goal.firstOpenIndex;
    final int leadAt = open < 0
        ? idx.length - 1
        : math.max(0, idx.indexOf(open));
    return Stack(
      children: <Widget>[
        // 牌扇：整条安全带都给它（原来被横轨切掉一截）
        Positioned(
          left: 0,
          right: 0,
          top: top,
          height: band,
          // 手感全在 CardTable 里：拖拽跟手、动量投影、档位咬合 `rung` + 轻震、
          // 落定 `seal` + 压印。本页一个手势都不自己实现。
          child: CardTable(
            key: const Key('main.rail'),
            cards: <TableCard>[for (final int i in idx) cardOf(i)],
            skin: CardSkin.duty,
            size: CardTableSize.m,
            initialLead: leadAt,
            onPick: (int k) => onSelect?.call(idx[k]),
          ),
        ),
        // 竖向刻度轨：贴左边缘，与牌扇同高（§4.A.3 的跳段手段）
        Positioned(
          left: 0,
          top: top,
          height: band,
          width: _MissionScrubber.hitWidth,
          child: _MissionScrubber(
            key: const Key('main.scale'),
            total: goal.plan.length,
            openIndex: goal.firstOpenIndex,
            onJump: (int i) => onSelect?.call(i),
          ),
        ),
      ],
    );
  }

  /// 详情 = 从底部升起的**牌屉**（§4.A.2）
  ///
  /// ⚠️ 不是居中大牌 —— 那正是原来把她的脸压在后面的元凶（19%~51%）。
  /// 牌屉只占安全带；九区在宽盒里重新配重（[CardSkin.duty] 的 `_dutyDrawer`），
  /// 5 个证据槽移出牌面、落到下方独立托盘。
  Widget _drawer(int i, double top, double band, double width) {
    final DutyState st = stateOf(i);
    const double trayH = 52;
    final double cardH = math.max(180, band - trayH - 12);
    return Positioned(
      left: 16,
      right: 16,
      top: top,
      height: band,
      child: _RiseDrawer(
        key: const Key('main.detail'),
        child: Column(
          children: <Widget>[
            SizedBox(
              height: cardH,
              child: CardFace(
                skin: CardSkin.duty,
                card: cardOf(i, lead: true),
                size: CardTableSize.l,
                lead: true,
                dims: Dims(width, cardH),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: trayH,
              child: Row(
                children: <Widget>[
                  Expanded(child: _tray()),
                  const SizedBox(width: 10),
                  // ⚠️ 没有动作键的态（待发布 / 已完成 / 已放弃）**不占**那个 104px：
                  //    否则 `收起` 会悬在中间、右边空一块（实机截图看出来的）。
                  if (_hasAction(st)) ...<Widget>[
                    _action(i, st),
                    const SizedBox(width: 8),
                  ],
                  _collapse(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 证据托盘：5 个虚线槽（移出牌面 —— 原来贴在牌下沿被裁掉）
  Widget _tray() {
    return Row(
      key: const Key('main.tray'),
      children: <Widget>[
        for (int k = 0; k < 5; k++) ...<Widget>[
          if (k > 0) const SizedBox(width: 6),
          const Expanded(
            child: CustomPaint(
              painter: _DashSlot(),
              child: SizedBox(height: 46),
            ),
          ),
        ],
      ],
    );
  }

  /// 收起牌屉（回牌扇）。留在托盘同一行 —— 动作区永远在拇指区，不往她脸上跑。
  Widget _collapse() {
    return PressScale(
      onTap: onSelect == null ? null : () => onSelect!(-1),
      child: Container(
        key: const Key('main.back'),
        width: 44,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xB3040E20),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
          border: Border.all(color: C.line),
        ),
        child: Text(
          '收起',
          style: fs(family: F.cn, size: 12, wght: 600, height: 1, color: C.ice),
        ),
      ),
    );
  }

  /// 这一态有没有动作键（可接 = 【接任务】；执行中 = 计时读数）
  bool _hasAction(DutyState st) =>
      st == DutyState.open || (st == DutyState.active && elapsed != null);

  /// 动作区：可接 = 一枚斜切 CTA【接任务】；其余四态只给读数（不给按钮）
  Widget _action(int i, DutyState st) {
    if (st == DutyState.open) {
      return PressScale(
        onTap: onAccept == null
            ? null
            : () {
                Sfx.play('seal');
                Haptics.buzz('seal');
                onAccept!(i);
              },
        child: Container(
          key: const Key('main.take'),
          width: 104,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: C.blue,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(color: C.blue.withAlpha(110), blurRadius: 24),
            ],
          ),
          child: Text(
            '接任务',
            style: fs(
              family: F.cn,
              size: 15,
              wght: 700,
              ls: .9,
              height: 1,
              color: C.deep,
            ),
          ),
        ),
      );
    }
    // 执行中给计时读数（数字，不是状态文字）；其余三态留空 ——
    // 牌面的印章与状态线已经把状态说完了。
    if (st == DutyState.active && elapsed != null) {
      return SizedBox(
        width: 104,
        height: 46,
        child: Center(
          child: Text(
            elapsed!,
            style: fs(
              family: F.num,
              size: 22,
              wght: 700,
              ls: .6,
              height: 1,
              color: C.blue,
            ),
          ),
        ),
      );
    }
    return const SizedBox(width: 104, height: 46);
  }

  Widget _empty(double top, double band) {
    return Positioned(
      left: 20,
      right: 20,
      top: top,
      height: band,
      child: Align(
        alignment: Alignment.topLeft,
        child: Text(
          '还没有计划。说一句你想变成什么样。',
          style: fs(
            family: F.cn,
            size: 13,
            wght: 400,
            height: 1.6,
            color: C.mist,
          ),
        ),
      ),
    );
  }

  /// 底排：拇指区（形态与位置不动）
  Widget _low() {
    return Positioned(
      left: 20,
      right: 20,
      bottom: 26,
      child: Row(
        key: const Key('main.low'),
        children: <Widget>[
          if (canDispatch) ...<Widget>[
            Expanded(child: _mainButton()),
            const SizedBox(width: 10),
          ],
          _ghostButton(),
        ],
      ),
    );
  }

  Widget _mainButton() {
    return PressScale(
      onTap: onDispatch,
      child: Container(
        key: const Key('main.dispatch'),
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: C.blue,
          borderRadius: BorderRadius.circular(27),
          boxShadow: <BoxShadow>[
            BoxShadow(color: C.blue.withAlpha(102), blurRadius: 28),
          ],
        ),
        child: Stack(
          children: <Widget>[
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.white.withAlpha(153)),
              ),
            ),
            Text(
              '去执行',
              style: fs(
                family: F.cn,
                size: 15,
                wght: 600,
                ls: .9,
                height: 1,
                color: C.deep,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ghostButton() {
    return PressScale(
      onTap: onNewGoal,
      child: Container(
        key: const Key('main.newGoal'),
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 19),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xB3040E20),
          borderRadius: BorderRadius.circular(27),
          border: Border.all(color: C.line, width: 1),
        ),
        child: Text(
          '换目标',
          style: fs(
            family: F.cn,
            size: 15,
            wght: 600,
            ls: .9,
            height: 1,
            color: C.ice,
          ),
        ),
      ),
    );
  }
}

/// 牌屉升起：弹簧式过冲（apple-design §4「抽屉 damping ≈.8 / response ≈.3」）。
///
/// ⚠️ 用**自持控制器**而不是 `TweenAnimationBuilder`：主线的计时读数会让
/// 上层每秒 rebuild，`TweenAnimationBuilder` 会被不断重置回起点（本仓库踩过）。
class _RiseDrawer extends StatefulWidget {
  const _RiseDrawer({super.key, required this.child});

  final Widget child;

  @override
  State<_RiseDrawer> createState() => _RiseDrawerState();
}

class _RiseDrawerState extends State<_RiseDrawer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 减弱动态：只留一段短淡入，不位移（apple-design §14）
    if (railReduceMotion(context)) {
      return AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (BuildContext _, Widget? child) => Opacity(
          opacity: kOut.transform(_c.value).clamp(0.0, 1.0),
          child: child,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (BuildContext _, Widget? child) {
        // 过冲到 ≈1.06 再回弹（§7 弹簧口径：过冲 ≤1.08）
        final double t = Curves.easeOutBack.transform(_c.value);
        return Opacity(
          opacity: _c.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 44),
            child: child,
          ),
        );
      },
    );
  }
}

/// 托盘里的一个虚线证据槽
class _DashSlot extends CustomPainter {
  const _DashSlot();

  @override
  void paint(Canvas canvas, Size s) {
    final Paint p = Paint()
      ..color = const Color(0x4D38E1FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const double dash = 5;
    const double gap = 4;
    final Path path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(.5, .5, s.width - 1, s.height - 1),
          const Radius.circular(6),
        ),
      );
    for (final PathMetric m in path.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        final double end = math.min(d + dash, m.length);
        canvas.drawPath(m.extractPath(d, end), p);
        d = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// 任务刻度轨（**竖向**，贴屏幕左边缘）
///
/// 2026-10-13 宿主：「刻度轨可以改成竖的，放在左边」——
/// 原来那条横穿她腰部，在她浅色裙摆那一段会糊掉；竖轨贴左边缘、落在安全带里。
///
/// 交互（单格只有几像素高，**不能拿格子本身当触控目标**）：
///  · 点一下 → 跳到那一段（开牌屉）
///  · 按住上下拖 → 连续擦洗，每过一格 `rung` + 轻震，松手跳到落点
/// 整条轨是一根通栏命中区（apple-design §2 直接操纵 / §13 因果同帧）。
class _MissionScrubber extends StatefulWidget {
  const _MissionScrubber({
    super.key,
    required this.total,
    required this.openIndex,
    required this.onJump,
  });

  /// 通栏命中区宽度（视觉刻度只占左边 ~4..22px，剩下的是手指余量）
  static const double hitWidth = 40;

  /// 清单总条数
  final int total;

  /// 脚下那一段（`goal.firstOpenIndex`，-1 = 全走完）
  final int openIndex;

  /// 跳到某个任务（开它的牌屉）
  final ValueChanged<int> onJump;

  @override
  State<_MissionScrubber> createState() => _MissionScrubberState();
}

class _MissionScrubberState extends State<_MissionScrubber> {
  /// 拖拽中落在哪一格（null = 没在拖）
  int? _dragSlot;

  int get _slots => math.min(widget.total, MainView.kScaleSlots);

  int get _per => _slots <= 0 ? 1 : (widget.total / _slots).ceil();

  /// 脚下那一段的下标（全走完 → 最后一段）
  int get _openSlot {
    if (_slots <= 0) return 0;
    if (widget.openIndex < 0) return _slots - 1;
    return (widget.openIndex ~/ _per).clamp(0, _slots - 1);
  }

  /// 这一格覆盖的第一个任务序号（跳段落点）
  int _indexOf(int slot) => math.min(widget.total - 1, slot * _per);

  int _slotAt(double dy, double h) {
    if (_slots <= 0 || h <= 0) return 0;
    return ((dy / h) * _slots).floor().clamp(0, _slots - 1);
  }

  /// 换格：响一声 + 轻震（同一帧）
  void _detent(int slot) {
    Sfx.play('rung', variant: slot % 5);
    Haptics.buzz('choose');
  }

  void _jump(int slot) {
    if (widget.total <= 0) return;
    _detent(slot);
    widget.onJump(_indexOf(slot));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double h = c.maxHeight;
        final int active = _dragSlot ?? _openSlot;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (TapDownDetails d) =>
              _jump(_slotAt(d.localPosition.dy, h)),
          onVerticalDragStart: (DragStartDetails d) {
            final int s = _slotAt(d.localPosition.dy, h);
            setState(() => _dragSlot = s);
            _detent(s);
          },
          onVerticalDragUpdate: (DragUpdateDetails d) {
            final int s = _slotAt(d.localPosition.dy, h);
            if (s == _dragSlot) return;
            setState(() => _dragSlot = s);
            _detent(s);
          },
          onVerticalDragEnd: (DragEndDetails d) {
            final int? s = _dragSlot;
            setState(() => _dragSlot = null);
            // 擦洗过程中每一格已经响过了，松手只落点（不重复响）
            if (s != null) widget.onJump(_indexOf(s));
          },
          onVerticalDragCancel: () => setState(() => _dragSlot = null),
          child: SizedBox.expand(
            child: CustomPaint(
              painter: _ScrubberPainter(
                slots: _slots,
                active: active,
                passed: _openSlot,
                dragging: _dragSlot != null,
                reduce: railReduceMotion(context),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 刻度轨画笔：走过 = 实心亮刻度 / 脚下 = 长刻度 + 光晕 / 未走 = 暗刻度
///
/// ⚠️ 状态一律用**样式**表达，禁止状态文字（docs/17 纪律）。
class _ScrubberPainter extends CustomPainter {
  const _ScrubberPainter({
    required this.slots,
    required this.active,
    required this.passed,
    required this.dragging,
    required this.reduce,
  });

  final int slots;

  /// 脚下（或拖拽落点）那一格
  final int active;

  /// 已经走过多少格
  final int passed;

  final bool dragging;
  final bool reduce;

  /// 刻度的中心 x —— 贴左边缘。牌扇最左那张牌的外缘从 ~11px 起，
  /// 视觉刻度只占 4..22px，重叠可以忽略（命中区仍是整条 40px）。
  static const double _cx = 13;

  @override
  void paint(Canvas canvas, Size s) {
    if (slots <= 0 || s.height <= 0) return;
    final double step = s.height / slots;
    for (int i = 0; i < slots; i++) {
      final double y = step * (i + .5);
      final bool here = i == active;
      final bool done = i < passed;
      final double w = here ? 20 : (done ? 14 : 9);
      if (here && !reduce) {
        canvas.drawLine(
          Offset(_cx - w / 2, y),
          Offset(_cx + w / 2, y),
          Paint()
            ..color = C.blue.withAlpha(dragging ? 120 : 70)
            ..strokeWidth = 9
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
      canvas.drawLine(
        Offset(_cx - w / 2, y),
        Offset(_cx + w / 2, y),
        Paint()
          ..color = here
              ? C.blue
              : (done ? C.blue.withAlpha(200) : C.blue.withAlpha(60))
          ..strokeWidth = here ? 3 : 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ScrubberPainter old) =>
      old.slots != slots ||
      old.active != active ||
      old.passed != passed ||
      old.dragging != dragging ||
      old.reduce != reduce;
}
