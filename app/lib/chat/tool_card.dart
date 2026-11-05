import 'package:flutter/material.dart';

import '../data/attrs.dart';
import '../design/ref.dart';

/// ═══════════════════════════════════════════════════════════
///  B8（docs/50）：〔工具〕回执 → 可读的卡片
///
///  原来「查状态」直接把 `get_status` 的原始回执文本（等宽、一长串 ·）贴进
///  对话。现在：
///   · `get_status` → [StatusSnapshot] 结构化状态卡（等级 + EXP 条 /
///     连胜 · 晶核 · 手里 / 主线进度 / 完成 · 战败 · 最弱维）
///   · 其它工具 → 同款外壳的精简卡（TOOL · 工具名 + 回执正文）
///
///  回执文本是 `agent/tools.dart` 自己拼的固定格式；解析失败一律走精简卡，
///  永远不会因为格式变了而丢内容。
/// ═══════════════════════════════════════════════════════════

/// `get_status` 回执的结构化读数
class StatusSnapshot {
  const StatusSnapshot({
    required this.lv,
    required this.exp,
    required this.expNeed,
    required this.coins,
    required this.streak,
    required this.bestStreak,
    required this.goalLine,
    required this.queue,
    required this.done,
    required this.failed,
    required this.weakest,
  });

  final int lv;
  final int exp;
  final int expNeed;
  final int coins;
  final int streak;
  final int bestStreak;

  /// 「「半年减重 10 斤」完成 1/180 单」或「未立目标」
  final String goalLine;
  final int queue;
  final int done;
  final int failed;

  /// 最弱维（显示名 + 数值，例如「意志 3」）
  final String weakest;

  static final RegExp _re = RegExp(
    r'LV(\d+) · EXP (\d+)/(\d+) · ◈(\d+) · 连击 (\d+)（最好 (\d+)）\s*'
    r'主线：(.*?)\s*'
    r'手里 (\d+) 单 · 完成 (\d+) · 战败 (\d+) · 最弱维：(\S*)',
    dotAll: true,
  );

  /// 认不出 → null（调用方退回精简卡）
  static StatusSnapshot? tryParse(String text) {
    final RegExpMatch? m = _re.firstMatch(text);
    if (m == null) return null;
    int n(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
    final String w = m.group(11) ?? '';
    // 「体3」→「意志 3」（存档键 → 显示名，data/attrs.dart）
    final String weakest = w.isEmpty
        ? '—'
        : '${Attr.nameOf(w.substring(0, 1))} ${w.substring(1)}'.trim();
    return StatusSnapshot(
      lv: n(1),
      exp: n(2),
      expNeed: n(3),
      coins: n(4),
      streak: n(5),
      bestStreak: n(6),
      goalLine: (m.group(7) ?? '').trim(),
      queue: n(8),
      done: n(9),
      failed: n(10),
      weakest: weakest,
    );
  }
}

/// 拆出回执里的工具名（LLM 路径是 `get_status：…`，快捷 chip 路径没有前缀）
({String? tool, String body}) splitToolReceipt(String text) {
  final RegExpMatch? m = RegExp(r'^([a-z_]+)：').firstMatch(text);
  if (m == null) return (tool: null, body: text);
  return (tool: m.group(1), body: text.substring(m.end));
}

/// 工具名 → 卡头的中文名
String toolTitleOf(String? tool) => switch (tool) {
  'get_status' => '状态快照',
  'swap_quest' => '换任务',
  'adjust_plan' => '调整计划',
  'remember' => '记下了',
  null => '系统回执',
  _ => tool,
};

/// 一条〔工具〕回执的卡片（[text] 已去掉〔工具〕前缀）
class ChatToolCard extends StatelessWidget {
  const ChatToolCard({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ({String? tool, String body}) r = splitToolReceipt(text.trim());
    final StatusSnapshot? s = StatusSnapshot.tryParse(r.body);
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final Widget card = Container(
      margin: const EdgeInsets.only(top: 7),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Ref.a(Ref.cyan, .35)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Ref.a(Ref.cyan, .08), Ref.a(Ref.ink, .9)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'TOOL · ${toolTitleOf(s != null ? 'get_status' : r.tool)}',
            style: refText(
              family: Ref.fm,
              size: 10,
              wght: 700,
              ls: 3,
              color: Ref.cyan,
            ),
          ),
          const SizedBox(height: 10),
          if (s != null) _status(s) else _plain(r.body),
        ],
      ),
    );
    // 入场：320ms 淡入 + 上移 8（Motion.Scene · Ref.ease），与页面卡片同口径
    return Align(
      alignment: Alignment.centerLeft,
      child: reduce
          ? card
          : TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 320),
              curve: Ref.ease,
              builder: (BuildContext _, double t, Widget? child) => Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, 8 * (1 - t)),
                  child: child,
                ),
              ),
              child: card,
            ),
    );
  }

  Widget _plain(String body) => Text(
    body,
    style: refText(
      family: Ref.fc,
      size: 13,
      wght: 500,
      height: 1.55,
      color: Ref.txt,
    ),
  );

  Widget _status(StatusSnapshot s) {
    final double pf = s.expNeed <= 0
        ? 0
        : (s.exp / s.expNeed).clamp(0.0, 1.0);
    return Column(
      key: const Key('chat.statusCard'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x17FFFFFF), width: 3),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'LV',
                    style: refText(
                      family: Ref.fm,
                      size: 8,
                      wght: 700,
                      ls: 2,
                      height: 1,
                      color: Ref.dim,
                    ),
                  ),
                  Text(
                    '${s.lv}',
                    style: refText(
                      family: Ref.fd,
                      size: 19,
                      wght: 700,
                      height: 1.1,
                      color: Ref.txt,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text('EXP', style: _mono),
                      const Spacer(),
                      Text('${s.exp} / ${s.expNeed}', style: _mono),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 8,
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          const ColoredBox(color: Color(0x14FFFFFF)),
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: pf,
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: <Color>[Ref.violet, Ref.acid],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(child: _tile('连胜', '${s.streak}', const Color(0xFFFFB35C))),
            const SizedBox(width: 8),
            Expanded(child: _tile('晶核', '${s.coins}', Ref.cyan)),
            const SizedBox(width: 8),
            Expanded(child: _tile('手里', '${s.queue} 单', Ref.txt)),
          ],
        ),
        const SizedBox(height: 12),
        _kv('主线', s.goalLine.isEmpty ? '未立目标' : s.goalLine),
        const SizedBox(height: 6),
        _kv('战绩', '完成 ${s.done} · 战败 ${s.failed} · 最好连胜 ${s.bestStreak}'),
        const SizedBox(height: 6),
        _kv('最弱维', s.weakest),
      ],
    );
  }

  static final TextStyle _mono = refText(
    family: Ref.fm,
    size: 11,
    wght: 500,
    color: Ref.dim,
  );

  Widget _tile(String k, String v, Color c) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0x0AFFFFFF),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      children: <Widget>[
        Text(k, style: refText(family: Ref.fm, size: 10, wght: 500, color: Ref.dim)),
        const SizedBox(height: 2),
        Text(
          v,
          style: refText(family: Ref.fd, size: 18, wght: 700, height: 1.1, color: c),
        ),
      ],
    ),
  );

  Widget _kv(String k, String v) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      SizedBox(
        width: 48,
        child: Text(
          k,
          style: refText(family: Ref.fc, size: 13, wght: 500, height: 1.45, color: Ref.dim),
        ),
      ),
      Expanded(
        child: Text(
          v,
          style: refText(family: Ref.fc, size: 13, wght: 500, height: 1.45, color: Ref.txt),
        ),
      ),
    ],
  );
}
