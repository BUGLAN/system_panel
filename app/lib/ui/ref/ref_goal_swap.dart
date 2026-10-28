import 'package:flutter/material.dart';

import '../../design/ref.dart';
import '../../state/goal.dart';
import 'ref_core.dart';
import 'ref_inputs.dart';
import 'ref_kit.dart';
import 'ref_motion.dart';
import 'ref_orb.dart' show RefLink;
import 'ref_text.dart';

/// ═══════════════════════════════════════════════════════════
///  换目标 —— v3 独立场景（docs/49 C，重写）
///
///  旧版是上一代视觉（`AskField` 底部输入条 + 左上 ← 圆）浮在主线页上，
///  与 ref 体系不是一套语言，提交后也只有一句台词、几十秒毫无反馈。
///  现在与主线页 / 绑定仪式同一套版式：
///
///   .sh      eyebrow `REWRITE · 换目标` + h1 + ×（金色：参考稿「立新目标」用 gold）
///   .meta    「旧清单撤下 · 等级/晶核/六维保留」
///   .cur     当前主线卡（原文 + 完成 N/M + 已过天数 + 进度条 + 「将撤下」压印）
///   .sysbox  46 核心 + SYSTEM + 她的台词（打字机）
///   .form    新目标输入 + 预设词 + 「先问小祥」—— 忙时整块换成 [loading]
///   .actions 【算了】ghost + 【确认换线】gold
///
///  进出由外层走 `_go('swap')` 斜切转场；元素按 RefReveal 逐层显影。
///  没有 HUD（.nohud 30 上边距）；键盘由本页自己让位（主 Scaffold 不缩）。
/// ═══════════════════════════════════════════════════════════
class RefGoalSwap extends StatefulWidget {
  const RefGoalSwap({
    super.key,
    required this.goal,
    required this.controller,
    required this.presets,
    this.focusNode,
    this.line,
    this.lineToken = 0,
    this.error,
    this.loading,
    this.onBack,
    this.onSubmit,
    this.onAskXiang,
  });

  /// 当前（将被撤下的）主线
  final Goal goal;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final List<String> presets;

  /// 她的台词（外层插话）；[lineToken] 变化时重播打字机
  final String? line;
  final int lineToken;

  /// 上一次拆解失败的原因（null = 没失败）
  final String? error;

  /// 非空 = 正在拆解（外层给好的 RefPlanLoading）
  final Widget? loading;

  final VoidCallback? onBack;
  final VoidCallback? onSubmit;

  /// 「先问小祥」：带场合开对话，不落库
  final VoidCallback? onAskXiang;

  @override
  State<RefGoalSwap> createState() => _RefGoalSwapState();
}

class _RefGoalSwapState extends State<RefGoalSwap> {
  static const Color _acc = Ref.gold;

  bool get _busy => widget.loading != null;

  bool get _ready => widget.controller.text.trim().isNotEmpty && !_busy;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(RefGoalSwap old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  /// 主键的可点态跟着输入走（空 = 灰）
  void _onText() {
    if (mounted) setState(() {});
  }

  void _submit() {
    if (!_ready) return;
    widget.onSubmit?.call();
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      key: const Key('ref.swap'),
      padding: EdgeInsets.fromLTRB(
        Ref.gutter,
        safe.top + Ref.sceneTopNoHud,
        Ref.gutter,
        safe.bottom + Ref.sceneBottom + keyboard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          RefReveal(index: 0, child: _head()),
          RefReveal(index: 1, child: _meta()),
          RefReveal(index: 2, child: _current()),
          RefReveal(index: 3, child: _sysbox()),
          RefReveal(
            index: 4,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 360),
              switchInCurve: Ref.ease,
              switchOutCurve: Ref.snap,
              layoutBuilder: (Widget? cur, List<Widget> prev) => Stack(
                alignment: Alignment.topCenter,
                children: <Widget>[...prev, ?cur],
              ),
              transitionBuilder: (Widget c, Animation<double> a) =>
                  FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, .04),
                        end: Offset.zero,
                      ).animate(a),
                      child: c,
                    ),
                  ),
              child: _busy
                  ? KeyedSubtree(
                      key: const ValueKey<String>('busy'),
                      child: widget.loading!,
                    )
                  : KeyedSubtree(
                      key: const ValueKey<String>('form'),
                      child: _form(),
                    ),
            ),
          ),
          const SizedBox(height: 22),
          RefReveal(index: 5, child: _actions()),
        ],
      ),
    );
  }

  Widget _head() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const RefEyebrow(text: 'REWRITE · 换目标', accent: _acc),
              const SizedBox(height: 8),
              Text('换一条主线', style: RefType.h1),
            ],
          ),
        ),
        const SizedBox(width: 12),
        RefXButton(
          key: const Key('ref.swap.back'),
          onTap: _busy ? null : widget.onBack,
          accent: _acc,
        ),
      ],
    );
  }

  Widget _meta() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(text: '确认后旧清单', style: RefType.meta),
            TextSpan(
              text: ' 整条撤下 ',
              style: refText(size: 14, wght: 700, color: Ref.hot),
            ),
            TextSpan(text: '· 等级 / 晶核 / 六维保留', style: RefType.meta),
          ],
        ),
      ),
    );
  }

  /// 当前主线卡：原文 + 进度。卡右上一枚「将撤下」虚框压印。
  Widget _current() {
    final Goal g = widget.goal;
    final int total = g.plan.length;
    final int done = g.doneCount;
    final int days = g.days <= 0 ? 14 : g.days;
    final int passed = g.passedDays(DateTime.now()).clamp(1, days);
    final double pf = total <= 0 ? 0 : (done / total).clamp(0.0, 1.0);
    return Container(
      key: const Key('ref.swap.current'),
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment(-.94, -.34),
          end: Alignment(.94, .34),
          colors: <Color>[Color(0xFF1F1A3A), Color(0xFF0E0C19)],
        ),
        border: Border.all(color: Ref.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'CURRENT · 当前主线',
                style: refText(
                  family: Ref.fm,
                  size: 10,
                  wght: 700,
                  ls: 3,
                  height: 1.2,
                  color: Ref.cyan,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Ref.a(Ref.hot, .6)),
                  color: Ref.a(Ref.hot, .08),
                ),
                child: Text(
                  '将撤下',
                  style: refText(
                    size: 11,
                    wght: 700,
                    ls: 1,
                    height: 1.2,
                    color: Ref.hot,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            g.text.isEmpty ? '（还没有目标）' : g.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: RefType.cardTitle.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 12),
          // ⚠️ Stack 必须 expand：非定位子节点拿到的是松约束，
          //    FractionallySizedBox 的高度会塌成 0（进度条看着永远是空的）
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  const ColoredBox(color: Color(0x12FFFFFF)),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: pf,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[Ref.cyan, Ref.acid],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: <Widget>[
              Text('完成', style: RefType.meta.copyWith(fontSize: 13)),
              Text('$done/$total', style: RefType.metaNum),
              Text('单 · 已过', style: RefType.meta.copyWith(fontSize: 13)),
              Text('$passed/$days', style: RefType.metaNum),
              Text('天', style: RefType.meta.copyWith(fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  /// .sysbox（与主线页同款，左边金线）
  Widget _sysbox() {
    final String line = (widget.line ?? '').trim().isEmpty
        ? '要换？那就说清楚换成什么。[旧的那条]，说换就换。'
        : widget.line!;
    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 18),
      padding: const EdgeInsets.fromLTRB(14, 12, 0, 12),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: _acc, width: 3)),
        gradient: LinearGradient(
          colors: <Color>[Color(0x14FFCC4D), Color(0x00FFCC4D)],
          stops: <double>[0, .7],
        ),
      ),
      child: Row(
        children: <Widget>[
          RefCore(
            size: 46,
            mood: widget.error != null ? CoreMood.angry : CoreMood.neutral,
            accent: _acc,
            animate: !(MediaQuery.maybeDisableAnimationsOf(context) ?? false),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'SYSTEM',
                  style: refText(
                    family: Ref.fm,
                    size: 13,
                    wght: 700,
                    ls: 4,
                    height: 1,
                    color: _acc,
                  ),
                ),
                const SizedBox(height: 5),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 26),
                  child: RefTypewriter(
                    key: ValueKey<String>('${widget.lineToken}·$line'),
                    text: line,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: refText(
                      size: 16,
                      wght: 500,
                      height: 1.5,
                      color: Ref.txt,
                    ),
                    highlightStyle: refText(
                      family: Ref.fd,
                      size: 16 * 1.15,
                      wght: 700,
                      height: 1.3,
                      color: _acc,
                      shadows: const <Shadow>[
                        Shadow(color: _acc, blurRadius: 12),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              '新目标 ›',
              style: refText(size: 13, wght: 500, height: 1.2, color: Ref.dim),
            ),
            const Spacer(),
            RefLink(
              key: const Key('ref.swap.askXiang'),
              label: '先问小祥 ›',
              accent: Ref.cyan,
              onTap: widget.onAskXiang,
            ),
          ],
        ),
        const SizedBox(height: 8),
        RefTextField(
          key: const Key('ref.swap.input'),
          controller: widget.controller,
          focusNode: widget.focusNode,
          hint: '比如：半年减重 10 斤',
          accent: _acc,
          textSize: 15,
          height: 52,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[for (final String p in widget.presets) _chip(p)],
        ),
        if (widget.error != null) ...<Widget>[
          const SizedBox(height: 14),
          Container(
            key: const Key('ref.swap.error'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Ref.a(Ref.hot, .08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Ref.a(Ref.hot, .4)),
            ),
            child: Text(
              '拆解失败 · ${widget.error!}\n旧主线没动。改一改再试，或者先问小祥。',
              style: refText(
                size: 12.5,
                wght: 500,
                height: 1.5,
                color: Ref.txt,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _chip(String label) {
    final bool on = widget.controller.text.trim() == label;
    return GestureDetector(
      onTap: () {
        refPressSound('ui.tap');
        widget.controller.text = label;
        widget.controller.selection = TextSelection.collapsed(
          offset: label.length,
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Ref.ease,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? _acc : Ref.line),
          color: on ? Ref.a(_acc, .12) : const Color(0x05FFFFFF),
        ),
        child: Text(
          label,
          style: refText(size: 13, wght: 500, color: on ? _acc : Ref.dim),
        ),
      ),
    );
  }

  Widget _actions() {
    return Row(
      children: <Widget>[
        RefButton(
          key: const Key('ref.swap.cancel'),
          label: '算了',
          primary: false,
          animateSheen: false,
          sound: 'ui.close',
          onTap: _busy ? null : widget.onBack,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: RefButton(
            key: const Key('ref.swap.submit'),
            label: _busy ? '拆解中…' : '确认换线',
            accent: _acc,
            trailingTriangle: !_busy,
            onTap: _ready ? _submit : null,
          ),
        ),
      ],
    );
  }
}
