import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../stage/live2d_stage.dart';
import '../stage/perf_presets.dart';
import '../stage/stage_port.dart';

/// ═══════════════════════════════════════════════════════════
///  表演调试台（宿主 2026-10-11：「新增一个调试页面，在这里我能调试表情、
///  动作以及预设」）。
///
///  入口：设置页（投影面板「系统」）→「表演调试台」。
///  形态：贴底的半屏面板（**留上面一半让她可见**，点了就能看她怎么演）。
///  三个页签：
///   · 预设 —— `PerfPreset`（动作 × 表情的命名组合），点一下整条演；
///   · 动作 —— 18 个动作组（组内随机取变体），**不动表情**，看纯动作；
///   · 表情 —— 32 个表情逐个试（只换脸），下面标出它现在被谁用。
///  另外一排快捷键：睡着 / 惊醒 / 回情绪 / 随机待机。
///
///  ⚠️ 这是**调试设施**，不是产品界面：不进底栏、不写存档、不用排版对齐
///  原型；但要守项目的视觉语言（电光青 + 玻璃 + mono 读数）。
/// ═══════════════════════════════════════════════════════════
class PerfDebugPanel extends StatefulWidget {
  const PerfDebugPanel({
    super.key,
    required this.visible,
    this.port,
    this.onClose,
  });

  final bool visible;

  /// 舞台把手（`_stagePort`）；null = 舞台没好，面板只读
  final StagePort? port;

  final VoidCallback? onClose;

  @override
  State<PerfDebugPanel> createState() => _PerfDebugPanelState();
}

class _PerfDebugPanelState extends State<PerfDebugPanel> {
  int _tab = 0;
  String _last = '还没点过 · 点一条试试';

  void _playPreset(PerfPreset p) {
    widget.port?.preset(p);
    setState(() => _last = '预设「${p.name}」= ${p.group} + ${p.exp}');
  }

  void _playGroup(String group) {
    // 表情传 '' = 这一拍不动表情（纯看动作）
    widget.port?.perf(group, '');
    final int n = Live2DStage.countOf(group);
    setState(() => _last = '动作 $group（$n 个变体里随机一个）');
  }

  void _playFace(String exp) {
    widget.port?.face(exp);
    setState(() => _last = '表情 $exp（下标 ${Live2DStage.expressionIndex(exp)}）');
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: const Duration(milliseconds: 260),
        child: Stack(
          children: <Widget>[
            // 幕布：点一下就关（上半屏留给她）
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onClose,
                child: Container(color: const Color(0x59000000)),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                key: const Key('perfDebug.panel'),
                width: size.width,
                height: size.height * .58,
                decoration: const BoxDecoration(
                  color: Color(0xF2040C1C),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                  border: Border(top: BorderSide(color: C.line)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _head(),
                    _tabs(),
                    _quick(),
                    const Divider(height: 1, color: C.line2),
                    Expanded(child: _body()),
                    _foot(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 抬头 ───────────────────────────────────────────────────
  Widget _head() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'PERF LAB · 表演调试台',
                  style: fs(
                    family: F.mono,
                    size: 10,
                    wght: 500,
                    ls: 1.6,
                    color: C.blue,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '预设 ${PerfPresets.all.length} · 动作 ${PerfPresets.groups.length}'
                  ' · 表情 ${Live2DStage.expressions.length}',
                  style: fs(family: F.cn, size: 11.5, wght: 500, color: C.mist),
                ),
              ],
            ),
          ),
          GestureDetector(
            key: const Key('perfDebug.close'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClose,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: C.line),
              ),
              child: Text(
                '收起',
                style: fs(family: F.cn, size: 12, wght: 700, color: C.ice),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 三个页签 ───────────────────────────────────────────────
  Widget _tabs() {
    const List<String> names = <String>['预设', '动作', '表情'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < names.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 8),
            GestureDetector(
              key: Key('perfDebug.tab$i'),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _tab = i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  color: _tab == i ? C.blue : const Color(0x1A38E1FF),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: _tab == i
                      ? const <BoxShadow>[
                          BoxShadow(color: Color(0x5938E1FF), blurRadius: 16),
                        ]
                      : null,
                ),
                child: Text(
                  names[i],
                  style: fs(
                    family: F.cn,
                    size: 12.5,
                    wght: 700,
                    color: _tab == i ? C.deep : C.ice,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 快捷键（睡/醒/回情绪/随机待机）─────────────────────────
  Widget _quick() {
    final List<(String, VoidCallback)> q = <(String, VoidCallback)>[
      ('睡着', () => widget.port?.doze()),
      ('惊醒', () => widget.port?.undoze()),
      ('回情绪', () => widget.port?.mood('neutral')),
      (
        '随机待机',
        () {
          final List<Perf> pool = StageBridges.idlePool['neutral']!;
          final Perf p = pool[DateTime.now().millisecond % pool.length];
          widget.port?.perf(p.group, p.exp, priority: 1);
          setState(() => _last = '待机「${p.group} + ${p.exp}」');
        },
      ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Row(
        children: <Widget>[
          for (final (String label, VoidCallback fn) in q) ...<Widget>[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: fn,
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: C.line2),
                ),
                child: Text(
                  label,
                  style: fs(family: F.cn, size: 11.5, wght: 600, color: C.mist),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _body() => switch (_tab) {
    0 => _presetList(),
    1 => _groupList(),
    _ => _faceList(),
  };

  // ── 页签 1：预设（按族分组）────────────────────────────────
  Widget _presetList() {
    final List<Widget> out = <Widget>[];
    for (final PerfFamily f in PerfFamily.values) {
      final List<PerfPreset> list = PerfPresets.of(f);
      if (list.isEmpty) continue;
      out.add(_section('${f.cn} · ${f.mono}'));
      for (final PerfPreset p in list) {
        out.add(_cell(
          key: Key('perfDebug.preset.${p.id}'),
          title: p.name,
          mono: p.id,
          sub: '${p.group} + ${p.exp}'
              '${p.priority != 2 ? '  ·P${p.priority}' : ''}'
              '${p.usage.isEmpty ? '' : '  · ${p.usage}'}',
          onTap: () => _playPreset(p),
        ));
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      children: out,
    );
  }

  // ── 页签 2：动作组（不动表情，纯看动作）───────────────────
  Widget _groupList() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      children: <Widget>[
        _section('动作组 · 18（点一下随机播一个变体，不动表情）'),
        for (final String g in PerfPresets.groups)
          _cell(
            key: Key('perfDebug.group.$g'),
            title: g,
            mono: '${Live2DStage.countOf(g)} 变体',
            sub: g == Live2DStage.baseGroup ? '常驻基底（循环播放）' : '',
            onTap: () => _playGroup(g),
          ),
      ],
    );
  }

  // ── 页签 3：表情（只换脸，标出当前谁在用）─────────────────
  Widget _faceList() {
    final List<String> expr = Live2DStage.expressions;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      children: <Widget>[
        _section('表情 · ${expr.length}（只换脸，不动动作）'),
        for (int i = 0; i < expr.length; i++)
          _cell(
            key: Key('perfDebug.face.$i'),
            title: expr[i],
            mono: '#$i',
            sub: _expUsage(expr[i]),
            onTap: () => _playFace(expr[i]),
          ),
      ],
    );
  }

  /// 这个表情现在被谁用（从桥接表**活读**，跟代码永远一致）
  String _expUsage(String exp) {
    final List<String> u = <String>[];
    StageBridges.emoExp.forEach((String k, String v) {
      if (v == exp) u.add('情绪 $k');
    });
    StageBridges.verbFace.forEach((String k, String v) {
      if (v == exp) u.add('动词 $k');
    });
    for (final MapEntry<String, List<Perf>> e
        in StageBridges.idlePool.entries) {
      for (final Perf p in e.value) {
        if (p.exp == exp) u.add('待机 ${p.group}');
      }
    }
    for (final PerfPreset p in PerfPresets.all) {
      if (p.exp == exp && p.usage.isNotEmpty) u.add(p.name);
    }
    // 去重（顺序保持）
    final List<String> seen = <String>[];
    for (final String s in u) {
      if (!seen.contains(s)) seen.add(s);
    }
    return seen.isEmpty ? '（闲置：还没接时刻）' : seen.join(' · ');
  }

  // ── 零件 ───────────────────────────────────────────────────
  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 6),
    child: Text(
      text,
      style: fs(family: F.mono, size: 10, wght: 500, ls: 1.2, color: C.blue),
    ),
  );

  Widget _cell({
    required Key key,
    required String title,
    required String mono,
    required String sub,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0x14050E20),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: C.line2),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: fs(family: F.cn, size: 12.5, wght: 700, color: C.ice),
                  ),
                  if (sub.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: fs(
                        family: F.cn,
                        size: 10.5,
                        wght: 500,
                        color: C.mist,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              mono,
              style: fs(family: F.mono, size: 10, wght: 500, color: C.dim),
            ),
          ],
        ),
      ),
    );
  }

  Widget _foot() => Container(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: C.line2)),
    ),
    child: Text(
      _last,
      style: fs(family: F.mono, size: 10.5, wght: 500, color: C.blue),
    ),
  );
}
