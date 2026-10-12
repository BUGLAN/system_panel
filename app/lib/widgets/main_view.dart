import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/format.dart';
import '../data/rarity.dart';
import '../data/rewards.dart';
import '../design/tokens.dart';
import '../state/goal.dart';
import 'card_skins.dart';

/// ═══════════════════════════════════════════════════════════
///  主线页（docs/33 §3）—— 卡片式新视图
///
///  旧形态（抬头 + 8 条环挂签 + 一张环详情卡）已随「环」一起废除：
///  宿主原话「点击主线时需要类似卡片式的新卡片，需要新的设计」。
///
///  现在这一页 = 抬头（目标一句 + 期限内进度）+ **委托轨**（第 4 套皮肤
///  [CardSkin.duty] 的横条铭牌，一屏 5~6 张、可滑）+ 底排两颗。
///    · 点一条 → 展开 L 大牌（审视态，九区）
///    · 按住一条 → 接单（沿用「拔单=开始执行」的手感）
///    · 待发布 / 可接 / 执行中 / 已完成 / 已放弃 —— 五态用**状态线**表达
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

  /// 展开的那一张（审视态）
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

  /// 轨上同时显示几张（一屏 5~6 条）
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
    if (activeIndex == i || t.state == PlanState.active) return DutyState.active;
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
    );
  }

  static List<String> lootOf(PlanTask t) {
    final Payout p = Rewards.payout(rank: t.rank, crit: false, dbl: false);
    return <String>[
      'EXP ${p.exp}',
      '◈ ${p.coin}',
      for (final MapEntry<String, int> e in t.attrs.entries) '${e.key}+${e.value}',
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
          child: Stack(
            children: <Widget>[
              _top(),
              if (goal.plan.isEmpty)
                _empty()
              else if (selected != null && goal.taskAt(selected!) != null)
                _detail(selected!)
              else
                _rail(),
              _low(),
            ],
          ),
        ),
      ),
    );
  }

  /// 抬头：目标一句 + 期限内进度
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
              width: 38,
              height: 38,
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

  /// 委托轨：横条铭牌一叠（可滑）
  Widget _rail() {
    final List<int> idx = railIndices();
    return Positioned(
      left: 20,
      right: 20,
      top: 150,
      bottom: 110,
      child: ListView.separated(
        key: const Key('main.rail'),
        padding: EdgeInsets.zero,
        physics: const BouncingScrollPhysics(),
        itemCount: idx.length,
        separatorBuilder: (BuildContext _, int _) => const SizedBox(height: 10),
        itemBuilder: (BuildContext _, int k) {
          final int i = idx[k];
          final DutyState st = stateOf(i);
          return GestureDetector(
            key: Key('main.card.$i'),
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect?.call(i),
            onLongPress: st == DutyState.open ? () => onAccept?.call(i) : null,
            child: Align(
              alignment: Alignment.centerLeft,
              child: CardFace(
                skin: CardSkin.duty,
                card: cardOf(i, lead: st == DutyState.open),
                size: CardTableSize.m,
                lead: st == DutyState.open,
              ),
            ),
          );
        },
      ),
    );
  }

  /// L 大牌（审视态）：翻开来看来龙去脉
  Widget _detail(int i) {
    final PlanTask t = goal.plan[i];
    final DutyState st = stateOf(i);
    return Positioned(
      left: 0,
      right: 0,
      top: 130,
      child: Column(
        children: <Widget>[
          CardFace(
            key: const Key('main.detail'),
            skin: CardSkin.duty,
            card: cardOf(i, lead: true),
            size: CardTableSize.l,
            lead: true,
          ),
          const SizedBox(height: 14),
          if (st == DutyState.open)
            GestureDetector(
              key: const Key('main.take'),
              onTap: () => onAccept?.call(i),
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 46,
                width: 190,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: C.blue,
                  borderRadius: BorderRadius.circular(23),
                  boxShadow: <BoxShadow>[
                    BoxShadow(color: C.blue.withAlpha(102), blurRadius: 24),
                  ],
                ),
                child: Text(
                  '接这张',
                  style: fs(
                    family: F.cn,
                    size: 15,
                    wght: 600,
                    ls: .9,
                    height: 1,
                    color: C.deep,
                  ),
                ),
              ),
            )
          else
            Text(
              t.statusText(),
              style: fs(
                family: F.cn,
                size: 12.5,
                wght: 500,
                height: 1.4,
                color: C.mist,
              ),
            ),
          const SizedBox(height: 10),
          GestureDetector(
            key: const Key('main.back'),
            onTap: () => onSelect?.call(-1),
            behavior: HitTestBehavior.opaque,
            child: Text(
              '收起',
              style: fs(
                family: F.cn,
                size: 12.5,
                wght: 500,
                height: 1,
                color: C.mist,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Positioned(
      left: 20,
      right: 20,
      top: 200,
      child: Text(
        '还没有计划。说一句你想变成什么样。',
        style: fs(family: F.cn, size: 13, wght: 400, height: 1.6, color: C.mist),
      ),
    );
  }

  /// 底排：拇指区（下 40%）
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
    return GestureDetector(
      onTap: onDispatch,
      behavior: HitTestBehavior.opaque,
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
    return GestureDetector(
      onTap: onNewGoal,
      behavior: HitTestBehavior.opaque,
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
