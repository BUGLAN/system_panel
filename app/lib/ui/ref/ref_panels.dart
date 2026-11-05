import 'package:flutter/material.dart';

import '../../data/attrs.dart';
import '../../design/ref.dart';
import '../../state/quest.dart';
import '../../widgets/press_scale.dart';
import 'ref_kit.dart';
import 'ref_svg.dart';

/// ═══════════════════════════════════════════════════════════
///  底板（bottom panel）—— 参考稿 `#sheet` 的同一套外壳，抽出来给
///  「证据来源」（B4）与「接单前简报」（B6）复用。
///
///  · 遮罩 rgba(bg,.6) 跟着进度淡入，点遮罩 = [onClose]
///  · 面板 28/28/0/0 圆角、#1a1630 → #0d0b17、顶部 1px 白 12%、44×5 抓条
///  · 进出 440ms `Ref.ease` 从底部滑上 / 滑下，滑完才摘树（与 [RefSheet] 同口径）
///  · 开 `ui.open` / 关 `ui.close`；减弱动态直接落终态
/// ═══════════════════════════════════════════════════════════
class RefBottomPanel extends StatefulWidget {
  const RefBottomPanel({
    super.key,
    required this.visible,
    required this.onClose,
    required this.child,
  });

  final bool visible;
  final VoidCallback onClose;
  final Widget child;

  @override
  State<RefBottomPanel> createState() => _RefBottomPanelState();
}

class _RefBottomPanelState extends State<RefBottomPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 440),
  );

  /// 关闭滑下那半秒里还要画旧内容（调用方此时可能已经把内容清空）
  Widget? _last;

  @override
  void initState() {
    super.initState();
    if (widget.visible) _open(sound: false);
  }

  @override
  void didUpdateWidget(RefBottomPanel old) {
    super.didUpdateWidget(old);
    if (widget.visible && !old.visible) {
      _open();
    } else if (!widget.visible && old.visible) {
      refPressSound('ui.close');
      _in.reverse();
    }
  }

  bool get _reduce => WidgetsBinding
      .instance
      .platformDispatcher
      .accessibilityFeatures
      .disableAnimations;

  void _open({bool sound = true}) {
    if (sound) refPressSound('ui.open');
    if (_reduce) {
      _in.value = 1;
    } else {
      _in.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.visible) _last = widget.child;
    return AnimatedBuilder(
      animation: _in,
      builder: (BuildContext context, Widget? _) {
        if (!widget.visible && _in.isDismissed) return const SizedBox.shrink();
        final double t = Ref.ease.transform(_in.value);
        return IgnorePointer(
          ignoring: !widget.visible,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onClose,
                  child: ColoredBox(color: Ref.a(Ref.bg, .60 * _in.value)),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * MediaQuery.sizeOf(context).height),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[Color(0xFF1A1630), Color(0xFF0D0B17)],
                      ),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                      border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Color(0x99000000),
                          blurRadius: 60,
                          offset: Offset(0, -30),
                        ),
                      ],
                    ),
                    padding: EdgeInsets.fromLTRB(
                      22,
                      12,
                      22,
                      MediaQuery.paddingOf(context).bottom + 26,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Center(
                          child: Container(
                            width: 44,
                            height: 5,
                            decoration: BoxDecoration(
                              color: const Color(0x33FFFFFF),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _last ?? const SizedBox.shrink(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 底板标题（`.sheet h3`：900 20）
Widget _panelTitle(String t) => Text(
  t,
  style: refText(family: Ref.fc, size: 20, wght: 900, color: Ref.txt),
);

// ───────────────────────────────────────────────────────────
//  B4 · 证据来源：拍照 / 相册（+ debug 的演示截图）
// ───────────────────────────────────────────────────────────

/// 点证据槽「+」先弹这张：【拍照】（推荐，现场拍最像真的）/【相册】。
/// 演示截图只在 [onDemo] 非空时露出（主壳只在 debug 包给）。
class RefEvidenceSource extends StatelessWidget {
  const RefEvidenceSource({
    super.key,
    required this.proof,
    required this.slotsLeft,
    required this.onCamera,
    required this.onGallery,
    required this.onCancel,
    this.onDemo,
  });

  /// 这一单的证据要求（Quest.proof）
  final String proof;

  /// 还能放几张
  final int slotsLeft;

  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onCancel;
  final VoidCallback? onDemo;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('ref.evidenceSource'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _panelTitle('上传快照记录'),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            style: refText(family: Ref.fc, size: 13, wght: 500, color: Ref.dim),
            children: <InlineSpan>[
              const TextSpan(text: '要求：'),
              TextSpan(
                text: proof,
                style: refText(
                  family: Ref.fc,
                  size: 13,
                  wght: 700,
                  color: Ref.txt,
                ),
              ),
              TextSpan(text: ' · 还能放 $slotsLeft 张'),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: <Widget>[
            Expanded(
              child: _SourceTile(
                key: const Key('ref.evidenceSource.camera'),
                icon: RefIcons.camera,
                title: '拍照',
                sub: '现场拍，最像真的',
                accent: Ref.acid,
                recommended: true,
                onTap: onCamera,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SourceTile(
                key: const Key('ref.evidenceSource.gallery'),
                icon: RefIcons.gallery,
                title: '相册',
                sub: '照片或 App 截图',
                accent: Ref.cyan,
                onTap: onGallery,
              ),
            ),
          ],
        ),
        if (onDemo != null) ...<Widget>[
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              key: const Key('ref.evidenceSource.demo'),
              behavior: HitTestBehavior.opaque,
              onTap: () {
                refPressSound('ui.tap');
                onDemo!();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '⚡ 用演示截图（仅调试包）›',
                  style: refText(
                    family: Ref.fc,
                    size: 13,
                    wght: 500,
                    color: Ref.cyan,
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        RefButton(
          key: const Key('ref.evidenceSource.cancel'),
          label: '取消',
          primary: false,
          small: true,
          animateSheen: false,
          sound: 'ui.close',
          onTap: onCancel,
        ),
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    super.key,
    required this.icon,
    required this.title,
    required this.sub,
    required this.accent,
    required this.onTap,
    this.recommended = false,
  });

  final String icon;
  final String title;
  final String sub;
  final Color accent;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title：$sub',
      child: PressScale(
        scale: .95,
        onTap: () {
          refPressSound('ui.tap');
          onTap();
        },
        child: Container(
          height: 148,
          decoration: BoxDecoration(
            gradient: recommended
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Ref.a(accent, .14), Ref.a(accent, .03)],
                  )
                : null,
            color: recommended ? null : const Color(0x0AFFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: recommended ? accent : const Color(0x29FFFFFF),
              width: recommended ? 1.5 : 1,
            ),
            boxShadow: recommended
                ? <BoxShadow>[
                    BoxShadow(color: Ref.a(accent, .18), blurRadius: 24),
                  ]
                : null,
          ),
          child: Stack(
            children: <Widget>[
              if (recommended)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '推荐',
                      style: refText(
                        family: Ref.fm,
                        size: 9,
                        wght: 700,
                        ls: 2,
                        color: Ref.onAccent,
                      ),
                    ),
                  ),
                ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    RefSvgIcon(
                      paths: <String>[icon],
                      color: accent,
                      size: 34,
                      glow: recommended ? 8 : 0,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      style: refText(
                        family: Ref.fc,
                        size: 17,
                        wght: 900,
                        color: Ref.txt,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      sub,
                      style: refText(
                        family: Ref.fc,
                        size: 12,
                        wght: 500,
                        color: Ref.dim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────
//  B6 · 接单前简报
// ───────────────────────────────────────────────────────────

/// 点「接取」先弹这张：时长 / 证据 / 奖励 / 判负 + 她一句，
/// 点【开始计时】才进执行面板、才开始计时；【再想想】收起、单子不动。
/// 打卡单（C3）：标签 CHECK-IN、时长行「不计时 · 今天内交」、无判负行、
/// 主键「开始 · 不计时」。
class RefBrief extends StatelessWidget {
  const RefBrief({
    super.key,
    required this.quest,
    required this.onStart,
    required this.onCancel,
  });

  final Quest quest;
  final VoidCallback onStart;
  final VoidCallback onCancel;

  /// 简报里的奖励读数：结算口径 EXP / 晶核 + 六维显示名（键 → 体质 / 意志…）
  static String rewardOf(Quest q) {
    final String base = Quest.lootTextOf(
      rank: q.rank,
      remedy: q.kind == 'remedy',
    ).replaceAll('◈', '晶核');
    final String at = q.attrs.entries
        .map((MapEntry<String, int> e) => '${Attr.nameOf(e.key)} +${e.value}')
        .join(' · ');
    return at.isEmpty ? base : '$base · $at';
  }

  /// 编号行：主线 `MAIN 02 / 180`，补救 / 日常各自的英文眉
  static String codeOf(Quest q) => switch (q.kind) {
    'main' =>
      'MAIN ${(q.planIndex + 1).toString().padLeft(2, '0')} / ${q.planTotal}',
    // E1.4：顶替主线某一环的补救单写明是第几单
    'remedy' when q.planIndex >= 0 =>
      'REMEDY · 主线 ${(q.planIndex + 1).toString().padLeft(2, '0')}',
    'remedy' => 'REMEDY · 补救',
    _ => 'DAILY · 日常',
  };

  /// 她的一句（按单子类型）
  static String lineOf(Quest q) {
    if (q.checkin) return '打卡单不计时。做完拍下来，今天之内交就行。';
    if (q.kind == 'remedy' && q.planIndex >= 0) {
      return '这张顶替刚才那一环：做一半就算数，交了这一环就算过关。';
    }
    if (q.kind == 'remedy') return '补救单，做一半就算数。别再半路跑了。';
    return '看清楚再接。东西先备好，计时从你点「开始」那一刻算。';
  }

  @override
  Widget build(BuildContext context) {
    final Quest q = quest;
    final Color gc = Ref.rankOf(q.rank);
    return Column(
      key: const Key('ref.brief'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: gc, width: 2),
                boxShadow: <BoxShadow>[
                  BoxShadow(color: Ref.a(gc, .7), blurRadius: 12),
                ],
              ),
              child: Text(
                q.rank,
                style: refText(
                  family: Ref.fd,
                  size: 18,
                  wght: 700,
                  italic: true,
                  height: 1,
                  color: gc,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'BRIEF · 接单前简报',
                    style: refText(
                      family: Ref.fm,
                      size: 11,
                      wght: 500,
                      ls: 2,
                      color: Ref.dim,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    codeOf(q),
                    style: refText(
                      family: Ref.fm,
                      size: 11,
                      wght: 500,
                      ls: 2,
                      color: Ref.cyan,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: q.checkin ? Ref.a(Ref.mint, .6) : const Color(0x33FFFFFF),
                ),
              ),
              child: Text(
                q.checkin ? 'CHECK-IN' : 'TIME TRIAL',
                style: refText(
                  family: Ref.fm,
                  size: 10,
                  wght: 700,
                  ls: 2,
                  color: q.checkin ? Ref.mint : Ref.txt,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          q.name,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: refText(
            family: Ref.fc,
            size: 21,
            wght: 900,
            height: 1.35,
            color: Ref.txt,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: const Color(0x08FFFFFF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Ref.line),
          ),
          child: Column(
            children: <Widget>[
              _kv(
                '时长',
                q.checkin ? '不计时 · 今天内交' : '${q.minutesText} · 点开始才计时',
                accent: Ref.acid,
              ),
              _sep(),
              _kv('证据', '${q.proof} · 1–3 张'),
              _sep(),
              _kv('奖励', rewardOf(q)),
              if (q.timed) ...<Widget>[
                _sep(),
                _kv('判负', '超过 ${q.minutesText} 没交 / 认输', accent: Ref.hot),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0x12FFFFFF), Color(0x05FFFFFF)],
            ),
            borderRadius: Ref.bubble,
            border: Border.all(color: Ref.line),
          ),
          child: Text(
            lineOf(q),
            style: refText(
              family: Ref.fc,
              size: 14,
              wght: 500,
              height: 1.55,
              color: Ref.txt,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            RefButton(
              key: const Key('ref.brief.cancel'),
              label: '再想想',
              primary: false,
              small: true,
              animateSheen: false,
              sound: 'ui.close',
              onTap: onCancel,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: RefButton(
                key: const Key('ref.brief.start'),
                label: q.checkin ? '开始 · 不计时' : '开始计时',
                small: true,
                trailingTriangle: true,
                onTap: onStart,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static Widget _sep() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 10),
    child: SizedBox(height: 1, child: ColoredBox(color: Ref.line)),
  );

  static Widget _kv(String k, String v, {Color? accent}) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      SizedBox(
        width: 44,
        child: Text(
          k,
          style: refText(family: Ref.fc, size: 14, wght: 500, color: Ref.dim),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          v,
          textAlign: TextAlign.right,
          style: refText(
            family: Ref.fc,
            size: 14,
            wght: 500,
            height: 1.45,
            color: accent ?? Ref.txt,
          ),
        ),
      ),
    ],
  );
}

