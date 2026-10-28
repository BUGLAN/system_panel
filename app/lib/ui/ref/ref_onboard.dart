import 'package:flutter/material.dart';

import '../../design/ref.dart';
import '../../state/goal_gen.dart';
import 'ref_core.dart';
import 'ref_kit.dart';
import 'ref_inputs.dart';
import 'ref_text.dart';

/// ═══════════════════════════════════════════════════════════
///  绑定仪式（设计稿未覆盖，但 APP 必需）—— 按参考稿的视觉语言补：
///
///  第 0 幕：eyebrow + h1 + 核心/气泡 + 目标输入 + 预设词 + 主键
///  第 1 幕：访谈卡（3~5 张，逐张问，选项即答）
///
///  没有 HUD（参考稿 .scene.nohud 的 30 上边距），天幕由外层提供。
///
///  [loading] 非空 = 正在等 LLM（匹配类别 / 拆解清单）：输入区与访谈卡整块
///  换成加载卡，按钮全部不可点（docs/49 D1：原来这段几十秒毫无反馈）。
/// ═══════════════════════════════════════════════════════════
class RefOnboard extends StatefulWidget {
  const RefOnboard({
    super.key,
    required this.controller,
    required this.probe,
    required this.presets,
    required this.onSubmit,
    this.probeToken = 0,
    this.cards,
    this.onDone,
    this.onSkip,
    this.planError,
    this.loading,
  });

  final TextEditingController controller;

  /// 她正在说的那句（Typewriter，带 [高亮]）
  final String probe;
  final int probeToken;

  final List<String> presets;
  final VoidCallback onSubmit;

  /// 非空 = 第 1 幕访谈卡
  final List<InterviewCard>? cards;
  final ValueChanged<Map<String, String>>? onDone;

  final VoidCallback? onSkip;
  final String? planError;

  /// 非空 = 忙（外层给好的加载卡，见 RefPlanLoading）
  final Widget? loading;

  @override
  State<RefOnboard> createState() => _RefOnboardState();
}

class _RefOnboardState extends State<RefOnboard> {
  int _cardIx = 0;
  bool _custom = false;
  final Map<String, String> _answers = <String, String>{};
  final TextEditingController _customCtrl = TextEditingController();
  final FocusNode _customFocus = FocusNode();

  @override
  void didUpdateWidget(RefOnboard old) {
    super.didUpdateWidget(old);
    if (old.cards != widget.cards) {
      _cardIx = 0;
      _custom = false;
      _answers.clear();
      _customCtrl.clear();
    }
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    _customFocus.dispose();
    super.dispose();
  }

  void _answer(String v) {
    final List<InterviewCard> cards = widget.cards ?? const <InterviewCard>[];
    if (widget.loading != null) return; // 拆解中：不收新答案
    if (cards.isEmpty || v.trim().isEmpty) return;
    refPressSound('choose');
    _answers[cards[_cardIx].id] = v.trim();
    if (_cardIx >= cards.length - 1) {
      widget.onDone?.call(Map<String, String>.unmodifiable(_answers));
      return;
    }
    setState(() {
      _cardIx += 1;
      _custom = false;
      _customCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final bool interview = widget.cards != null && widget.cards!.isNotEmpty;
    final bool busy = widget.loading != null;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        Ref.gutter,
        safe.top + 30,
        Ref.gutter,
        safe.bottom + 30 + keyboard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              RefEyebrow(text: interview ? 'INTERVIEW · 访谈' : 'BINDING · 绑定仪式'),
              const Spacer(),
              if (widget.onSkip != null && !busy)
                GestureDetector(
                  onTap: () {
                    refPressSound('ui.tap');
                    widget.onSkip!();
                  },
                  child: Text(
                    '暂时跳过 ›',
                    style: refText(
                      family: Ref.fc,
                      size: 13,
                      wght: 500,
                      color: Ref.dim,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(interview ? '答完这几张，我给你排三天。' : '宿主，说出你的目标。', style: RefType.h1),
          const SizedBox(height: 18),
          Center(
            child: RefCore(
              size: 116,
              mood: CoreMood.neutral,
              accent: Ref.cyan,
              animate: !(MediaQuery.maybeDisableAnimationsOf(context) ?? false),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 330),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0x12FFFFFF), Color(0x05FFFFFF)],
                  ),
                  borderRadius: Ref.bubble,
                  border: Border.all(color: Ref.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'SYSTEM · 她说',
                      style: refText(
                        family: Ref.fm,
                        size: 10,
                        wght: 700,
                        ls: 3,
                        color: Ref.cyan,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 24),
                      child: RefTypewriter(
                        text: widget.probe,
                        skipToken: widget.probeToken,
                        style: refText(
                          family: Ref.fc,
                          size: 15,
                          wght: 500,
                          height: 1.6,
                          color: Ref.txt,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 360),
            switchInCurve: Ref.ease,
            switchOutCurve: Ref.snap,
            transitionBuilder: _rise,
            layoutBuilder: _topStack,
            child: busy
                ? KeyedSubtree(
                    key: const ValueKey<String>('busy'),
                    child: widget.loading!,
                  )
                : KeyedSubtree(
                    key: ValueKey<String>(interview ? 'interview' : 'ask'),
                    child: _form(interview),
                  ),
          ),
        ],
      ),
    );
  }

  /// 换块：淡入 + 上浮 16（与 RefReveal 同一曲线）
  static Widget _rise(Widget child, Animation<double> a) => FadeTransition(
    opacity: a,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, .04),
        end: Offset.zero,
      ).animate(a),
      child: child,
    ),
  );

  static Widget _topStack(Widget? current, List<Widget> previous) => Stack(
    alignment: Alignment.topCenter,
    children: <Widget>[...previous, ?current],
  );

  Widget _form(bool interview) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!interview) ...<Widget>[
          _fieldLabel('目标 ›'),
          const SizedBox(height: 8),
          RefTextField(
            controller: widget.controller,
            hint: '比如：三个月跑完半马',
            accent: Ref.acid,
            textSize: 15,
            height: 52,
            onChanged: (String _) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final String p in widget.presets)
                _chip(p, () {
                  widget.controller.text = p;
                  widget.controller.selection = TextSelection.collapsed(
                    offset: p.length,
                  );
                  setState(() {});
                }),
            ],
          ),
          const SizedBox(height: 22),
          RefButton(
            key: const Key('ref.onboard.submit'),
            label: '确立目标',
            trailingTriangle: true,
            onTap: widget.controller.text.trim().isEmpty
                ? null
                : widget.onSubmit,
          ),
          if (widget.planError != null) ...<Widget>[
            const SizedBox(height: 14),
            Text(
              widget.planError!,
              textAlign: TextAlign.center,
              style: refText(
                family: Ref.fc,
                size: 12,
                wght: 500,
                height: 1.5,
                color: Ref.hot,
              ),
            ),
          ],
        ] else
          _interview(),
      ],
    );
  }

  Widget _fieldLabel(String t) => Text(
    t,
    style: refText(
      family: Ref.fc,
      size: 13,
      wght: 500,
      color: Ref.dim,
      height: 1.2,
    ),
  );

  Widget _interview() {
    final List<InterviewCard> cards = widget.cards!;
    final InterviewCard card = cards[_cardIx];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            for (int i = 0; i < cards.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= _cardIx ? Ref.acid : const Color(0x14FFFFFF),
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: i == _cardIx
                        ? <BoxShadow>[
                            BoxShadow(
                              color: Ref.a(Ref.acid, .6),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 10),
            Text(
              '${_cardIx + 1}/${cards.length}',
              style: refText(
                family: Ref.fm,
                size: 11,
                wght: 500,
                color: Ref.dim,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Ref.ease,
          switchOutCurve: Ref.snap,
          layoutBuilder: _topStack,
          // 下一张从右侧 18px 滑入（与卡轮播「往右翻」同方向），上一张原地淡出
          transitionBuilder: (Widget c, Animation<double> a) {
            final bool incoming = c.key == ValueKey<int>(_cardIx);
            return FadeTransition(
              opacity: a,
              child: incoming
                  ? SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(.05, 0),
                        end: Offset.zero,
                      ).animate(a),
                      child: c,
                    )
                  : c,
            );
          },
          child: Column(
            key: ValueKey<int>(_cardIx),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                card.question,
                style: refText(
                  family: Ref.fc,
                  size: 22,
                  wght: 900,
                  height: 1.35,
                  color: Ref.txt,
                ),
              ),
              const SizedBox(height: 16),
              for (final String o in card.options) ...<Widget>[
                _option(o),
                const SizedBox(height: 10),
              ],
              if (!_custom)
                GestureDetector(
                  onTap: () {
                    refPressSound('ui.tap');
                    setState(() => _custom = true);
                    _customFocus.requestFocus();
                  },
                  child: Text(
                    '自己写 ›',
                    style: refText(
                      family: Ref.fc,
                      size: 13,
                      wght: 500,
                      color: Ref.dim,
                    ),
                  ),
                )
              else ...<Widget>[
                const SizedBox(height: 4),
                RefTextField(
                  controller: _customCtrl,
                  hint: '用一句话回答',
                  accent: Ref.acid,
                  textSize: 15,
                  height: 50,
                ),
                const SizedBox(height: 10),
                RefButton(
                  label: '回答',
                  small: true,
                  onTap: () => _answer(_customCtrl.text),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _option(String text) {
    return GestureDetector(
      onTap: () => _answer(text),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0x08FFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Ref.line),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                text,
                style: refText(
                  family: Ref.fc,
                  size: 15,
                  wght: 500,
                  height: 1.4,
                  color: Ref.txt,
                ),
              ),
            ),
            Text(
              '›',
              style: refText(
                family: Ref.fd,
                size: 20,
                wght: 500,
                color: Ref.dim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        refPressSound('ui.tap');
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Ref.line),
          color: const Color(0x05FFFFFF),
        ),
        child: Text(
          label,
          style: refText(family: Ref.fc, size: 13, wght: 500, color: Ref.dim),
        ),
      ),
    );
  }
}
