import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/attrs.dart';
import '../data/rarity.dart';
import '../design/tokens.dart';
import '../state/quest_flow.dart';

/// ═══════════════════════════════════════════════════════════
///  A6 数据回顾（docs/19 §A6 · t21）
///
///  嵌在档案页里的「本周回顾」段（sheet.dart 的 _ArchiveSwitch 切换）：
///   ① 本周概览：完成数 / 总 EXP / 总金币 / 连击峰值 —— 四格读数，
///      沿用档案页「战绩」格语言（青 5% 底 + Tektur 数字）
///   ② 六维 · 7 日：每维一行 7 根日增量条（0 增量压成暗线）+ 现值
///   ③ 最近战绩：≤8 条，稀有度色标 + 出账 + 结果（CLEAR 青 / 认输 红 /
///      超时 金）+ 日期
///
///  数据来自 [HistoryLog]（opus-v2/history/v1，QuestFlow.settle/认输追加）；
///  空态不裸奔：概览照显（全 0）、条全暗、列表给一句她的开场。
///  入场动效：三段错峰（0/90/180ms 起，320ms kOut fade+上移 8px）——
///  AGENTS.md 惯例的 280~450ms 档。
/// ═══════════════════════════════════════════════════════════
class StatsPane extends StatefulWidget {
  const StatsPane({super.key, this.log, this.attrs});

  /// null = 默认实例（同 key，读同一份数据；测试注入内存实现）
  final HistoryLog? log;

  /// 六维现值（Sheet.host.attrs；行尾的「现值」读数）
  final Map<String, int>? attrs;

  @override
  State<StatsPane> createState() => _StatsPaneState();
}

class _StatsPaneState extends State<StatsPane> {
  List<HistoryEntry> _entries = <HistoryEntry>[];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<HistoryEntry> all = await (widget.log ?? HistoryLog()).entries();
    if (!mounted) return;
    setState(() {
      _entries = all;
      _loaded = true;
    });
  }

  /// 错峰入场（delay ms 起步；320ms kOut fade + 上移 8px）
  Widget _rise(double delayMs, Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: (320 + delayMs).round()),
      curve: kOut,
      builder: (BuildContext _, double k, Widget? child) => Opacity(
        opacity: k,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - k)),
          child: child,
        ),
      ),
      child: child,
    );
  }

  /// `.sec` 同款：kicker + 细线（与档案页段落同一视觉）
  Widget _kicker(String text) {
    return Row(
      children: <Widget>[
        Text(
          text,
          style: fs(
            family: F.mono,
            size: 10,
            wght: 400,
            ls: 1.6,
            height: 1,
            color: C.mist,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: C.line2)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final WeekSummary s = HistoryLog.summarize(_entries, DateTime.now());
    return Column(
      key: const Key('stats.pane'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _rise(0, _kicker('本周概览 · LAST 7 DAYS')),
        const SizedBox(height: 10),
        _rise(0, _overview(s)),
        const SizedBox(height: 18),
        _rise(90, _kicker('六维 · 7 日增量')),
        const SizedBox(height: 10),
        _rise(90, _attrBars(s)),
        const SizedBox(height: 18),
        _rise(180, _kicker('最近战绩 · LOG')),
        const SizedBox(height: 10),
        _rise(180, _recent(s)),
        if (!_loaded) const SizedBox(height: 4),
      ],
    );
  }

  // ── ① 本周概览：四格读数（档案「战绩」同款格语言）──────────────
  Widget _overview(WeekSummary s) {
    final List<List<String>> cells = <List<String>>[
      <String>['${s.doneCount}', '完成'],
      <String>['${s.totalExp}', '总 EXP'],
      <String>['${s.totalCoin}', '总金币'],
      <String>['${s.bestStreak}', '连击峰值'],
    ];
    return Row(
      key: const Key('stats.overview'),
      children: <Widget>[
        for (int i = 0; i < cells.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              key: Key('stats.cell.$i'),
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
              decoration: BoxDecoration(
                color: C.blue.withAlpha(13), // rgba(56,225,255,.05)
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: <Widget>[
                  Text(
                    cells[i][0],
                    style: fs(
                      family: F.num,
                      size: 20,
                      wght: 800,
                      height: 1,
                      color: C.ice,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cells[i][1],
                    style: fs(
                      family: F.cn,
                      size: 10,
                      wght: 400,
                      color: C.mist,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── ② 六维 · 7 日增量：每维一行 7 根小条 + 现值 ─────────────────
  Widget _attrBars(WeekSummary s) {
    final Map<String, int> current = widget.attrs ?? const <String, int>{};
    final int maxDelta = s.dayAttrsByDay.fold(0, (int acc, Map<String, int> day) {
      final int dayMax = day.values.fold(0, (int a, int b) => math.max(a, b));
      return math.max(acc, dayMax);
    });
    return Column(
      key: const Key('stats.attrs'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final Attr a in Attr.all)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 16,
                  child: Text(
                    a.k,
                    style: fs(
                      family: F.cn,
                      size: 12,
                      wght: 400,
                      height: 1,
                      color: C.ice,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      for (int i = 0; i < 7; i++) _bar(a.k, s, i, maxDelta),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 26,
                  child: Text(
                    '${current[a.k] ?? 0}',
                    textAlign: TextAlign.right,
                    style: fs(
                      family: F.num,
                      size: 13,
                      wght: 700,
                      height: 1,
                      color: C.blue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // 空态提示只在「一条记录都没有」时出现，不单独占段
        if (_entries.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '还没战绩。第一单就从今天开始。',
              key: const Key('stats.empty'),
              style: fs(
                family: F.cn,
                size: 11.5,
                wght: 400,
                height: 1.6,
                color: C.dim,
              ),
            ),
          ),
      ],
    );
  }

  /// 第 i 天（0=6 天前 … 6=今天）那一根：只反映**这一维当天**的增量
  /// （读 dayAttrsByDay 的那一列；0 增量 = 暗的基线，不假装有变化）
  Widget _bar(String key, WeekSummary s, int i, int maxDelta) {
    final int delta = s.dayAttrsByDay[i][key] ?? 0;
    final bool lit = delta > 0;
    final double frac = maxDelta <= 0
        ? 0.0
        : (delta / maxDelta).clamp(0.0, 1.0);
    return Tooltip(
      message: 'D-${6 - i} · $key+${lit ? delta : 0}',
      child: Container(
        key: Key('stats.bar.$key.$i'),
        width: 14,
        height: 4 + 16 * frac,
        decoration: BoxDecoration(
          color: lit ? C.blue.withAlpha(230) : C.line2,
          borderRadius: BorderRadius.circular(2),
          boxShadow: lit
              ? <BoxShadow>[BoxShadow(color: C.blue.withAlpha(77), blurRadius: 6)]
              : null,
        ),
      ),
    );
  }

  // ── ③ 最近战绩：≤8 条，稀有度色标 + 出账 + 结果 ─────────────────
  Widget _recent(WeekSummary s) {
    if (s.recent.isEmpty) {
      return const SizedBox.shrink(); // 空态文案已在 ② 里给过，不重复
    }
    return Column(
      key: const Key('stats.recent'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final HistoryEntry e in s.recent)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
              decoration: BoxDecoration(
                color: C.blue.withAlpha(11), // rgba(56,225,255,.045)
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: <Widget>[
                  // 稀有度色标
                  Container(
                    width: 3,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Rarity.of(e.rank).color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          e.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: fs(
                            family: F.cn,
                            size: 12.5,
                            wght: 400,
                            height: 1.2,
                            color: C.ice,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${e.result == 'clear' ? 'CLEAR' : e.result == 'quit' ? '认输' : '超时'}'
                          ' · ${e.at.month}/${e.at.day}',
                          style: fs(
                            family: F.mono,
                            size: 9,
                            wght: 500,
                            ls: .8,
                            height: 1,
                            color: _resultColor(e.result),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 出账（认输/超时记 0——不亮）
                  Text(
                    e.exp > 0 || e.coin > 0
                        ? 'EXP ${e.exp} · ◈ ${e.coin}'
                        : '—',
                    style: fs(
                      family: F.num,
                      size: 11,
                      wght: 700,
                      height: 1,
                      color: e.exp > 0 || e.coin > 0 ? C.blue : C.dim,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // 「今天」参照（防止月份歧义）
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '截至 ${DateTime.now().month}/${DateTime.now().day}',
            style: fs(
              family: F.mono,
              size: 8.5,
              wght: 400,
              height: 1,
              color: C.dim,
            ),
          ),
        ),
      ],
    );
  }

  Color _resultColor(String result) => switch (result) {
    'clear' => C.blue,
    'quit' => const Color(0xFFFF8F99), // 认输：红系（失败页同款）
    _ => const Color(0xFFFBBF24), // 超时：金（B 级色）
  };
}
