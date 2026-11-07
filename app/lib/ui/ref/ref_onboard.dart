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
///  换成加载卡，按钮全部不可点（原来这段几十秒毫无反馈）。
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
    this.planErrorTitle,
    this.goalText = '',
    this.onRephrase,
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

  /// 失败详情（一行，`code · detail`）；非空 = 显示错误卡（B1）
  final String? planError;

  /// 错误卡标题（按失败类型：上游不可用 / 没配 Key / 断网 / 超时…）
  final String? planErrorTitle;

  /// 访谈对应的那句目标（复核态「已答卡」第一行）
  final String goalText;

  /// B1【换个说法】：回第 0 幕改目标（原文预填），答案先留着
  final VoidCallback? onRephrase;

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

  /// B1：点了「改答案」—— 回到逐张作答（复核态让位），答完最后一张再回来
  bool _editing = false;

  /// 键盘是否盖着第 0 幕（B3：CTA 吸到键盘上沿）
  bool _kb = false;

  static String _idsOf(List<InterviewCard>? cs) =>
      cs == null ? '' : cs.map((InterviewCard c) => c.id).join('|');

  /// 复核态：访谈卡全答过、且不在「改答案」中 —— 拆解失败 / 换说法回来都停在这
  bool get _review {
    final List<InterviewCard>? cs = widget.cards;
    if (cs == null || cs.isEmpty || _editing) return false;
    return cs.every((InterviewCard c) => _answers.containsKey(c.id));
  }

  @override
  void didUpdateWidget(RefOnboard old) {
    super.didUpdateWidget(old);
    // B1（docs/50）：卡组按 **id** 比较。原来按列表身份比 —— 主壳每次 build
    // 都 `interviewCardsFor(...)` 新建一份，于是任何一次重建（拆解失败那一下
    // setState 就是）都把访谈打回 1/3、答案清空。
    // 卡组变成 null（换个说法回第 0 幕）也不清：同一组卡回来时答案还在。
    final List<InterviewCard>? now = widget.cards;
    if (now == null || _idsOf(old.cards) == _idsOf(now)) return;
    final bool same = now.every((InterviewCard c) => _answers.containsKey(c.id));
    _cardIx = 0;
    _custom = false;
    _editing = false;
    _customCtrl.clear();
    if (!same) _answers.clear();
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
      setState(() => _editing = false);
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
    final bool review = interview && !busy && _review;
    final bool failed = widget.planError != null;
    // B3（docs/50）：第 0 幕键盘弹起 → 「确立目标」吸到键盘上沿（原来被整块盖住）
    _kb = keyboard > 0 && !interview && !busy;
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final Duration scene = reduce
        ? Duration.zero
        : const Duration(milliseconds: 320); // Motion.Scene

    final String title = review
        ? (failed ? '拆到一半，线断了。' : '答案都在，确认一下。')
        // E2.7（docs/50）：手动断行 —— 自动折行在 390 宽下剩一个「段。」孤字
        : (interview ? '答完这几张，\n我给你排第一段。' : '宿主，说出你的目标。');

    final Widget page = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        Ref.gutter,
        safe.top + 30,
        Ref.gutter,
        safe.bottom + 30 + keyboard + (_kb ? 96 : 0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Flexible(
                child: RefEyebrow(
                  text: review && failed
                      ? 'PLAN · 拆解失败'
                      : (interview ? 'INTERVIEW · 访谈' : 'BINDING · 绑定仪式'),
                  accent: review && failed ? Ref.hot : null,
                ),
              ),
              const Spacer(),
              if (review)
                Text(
                  '访谈 ${widget.cards!.length}/${widget.cards!.length} ✓',
                  style: refText(
                    family: Ref.fm,
                    size: 11,
                    wght: 500,
                    color: Ref.dim,
                  ),
                )
              else if (widget.onSkip != null && !busy)
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
          Text(title, style: _kb ? RefType.h1.copyWith(fontSize: 22) : RefType.h1),
          SizedBox(height: _kb ? 12 : 18),
          // B3：键盘上来时眼睛缩到 40、与气泡并排，给输入框和 CTA 让位
          AnimatedSize(
            duration: scene,
            curve: Ref.ease,
            alignment: Alignment.topCenter,
            child: _kb || review
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      RefCore(
                        size: _kb ? 40 : 62,
                        mood: review && failed ? CoreMood.angry : CoreMood.neutral,
                        accent: review && failed ? Ref.hot : Ref.cyan,
                        animate: !reduce,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: _bubble(compact: _kb)),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Center(
                        child: RefCore(
                          size: 116,
                          mood: CoreMood.neutral,
                          accent: Ref.cyan,
                          animate: !reduce,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 330),
                          child: _bubble(),
                        ),
                      ),
                    ],
                  ),
          ),
          SizedBox(height: _kb ? 16 : 22),
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
                    key: ValueKey<String>(
                      review ? 'review' : (interview ? 'interview' : 'ask'),
                    ),
                    child: review ? _reviewView() : _form(interview),
                  ),
          ),
        ],
      ),
    );

    return Stack(
      children: <Widget>[
        Positioned.fill(child: page),
        // B3：吸附在键盘上沿的 CTA 条（渐隐底 + 字数）
        if (_kb)
          Positioned(
            left: 0,
            right: 0,
            bottom: keyboard,
            child: Container(
              padding: const EdgeInsets.fromLTRB(Ref.gutter, 14, Ref.gutter, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Ref.a(Ref.bg, 0), Ref.a(Ref.bg, .96)],
                  stops: const <double>[0, .3],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _counter(),
                  const SizedBox(height: 8),
                  _submitButton(),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 她的气泡（[compact] = 键盘上来时：一行省略、字号 14）
  Widget _bubble({bool compact = false}) {
    return Container(
      padding: compact
          ? const EdgeInsets.fromLTRB(14, 9, 14, 9)
          : const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
          if (!compact) ...<Widget>[
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
          ],
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: compact ? 0 : 24),
            child: RefTypewriter(
              text: widget.probe,
              skipToken: widget.probeToken,
              maxLines: compact ? 1 : null,
              overflow: compact ? TextOverflow.ellipsis : TextOverflow.clip,
              style: refText(
                family: Ref.fc,
                size: compact ? 14 : 15,
                wght: 500,
                height: compact ? 1.5 : 1.6,
                color: Ref.txt,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 键盘上沿那条的字数：G2.2 改成「N/50」—— 上限看得见，顶到了转 hot。
  /// 只数已上屏的字（E2.6：组字中的拼音不算）
  Widget _counter() {
    final int n = refCommittedText(widget.controller.value)
        .trim()
        .characters
        .length;
    return Text(
      '$n/$kGoalInputMaxChars',
      key: const Key('ref.onboard.count'),
      style: refText(
        family: Ref.fm,
        size: 11,
        wght: 500,
        ls: 1,
        color: n >= kGoalInputMaxChars ? Ref.hot : Ref.dim,
      ),
    );
  }

  Widget _submitButton() => RefButton(
    key: const Key('ref.onboard.submit'),
    label: '确立目标',
    trailingTriangle: true,
    // E2.6：拼音还在组字时不给点（选字前点下去会把一串拼音交成目标）
    onTap:
        refIsComposing(widget.controller.value) ||
            refCommittedText(widget.controller.value).trim().isEmpty
        ? null
        : widget.onSubmit,
  );

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
          // B1：匹配类别就失败（访谈前）—— 同一张错误卡，摆在输入框上面
          if (widget.planError != null) ...<Widget>[
            _errorCard(),
            const SizedBox(height: 16),
          ],
          _fieldLabel('目标'), // A9（docs/50）：不可点的标签不带 ›
          const SizedBox(height: 8),
          RefTextField(
            controller: widget.controller,
            hint: '比如：三个月跑完半马',
            accent: Ref.acid,
            textSize: 15,
            height: 52,
            maxChars: kGoalInputMaxChars, // G2.2：一句话目标，长文粘进来截断
            onChanged: (String _) => setState(() {}),
            // A4（docs/50）：键盘上的 ✓ 直接提交（空输入不提交）
            onSubmitted: (String v) {
              if (v.trim().isNotEmpty) widget.onSubmit();
            },
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
          // B3：键盘上来时 CTA 在键盘上沿那条里（见 build），这里不重复摆
          if (!_kb) ...<Widget>[
            const SizedBox(height: 22),
            _submitButton(),
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
                  // G2.2：访谈答案原样进拆解提示词，同一个口子，同一个上限
                  maxChars: kGoalInputMaxChars,
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

  /// B1 错误卡：hot 描边 + 失败类型 + 一句详情（上游原因原样给，别糊弄）
  Widget _errorCard() {
    return Container(
      key: const Key('ref.onboard.error'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Ref.a(Ref.hot, .07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Ref.a(Ref.hot, .4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Ref.hot,
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(color: Ref.hot, blurRadius: 8),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ERROR · ${widget.planErrorTitle ?? '拆解失败'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: refText(
                    family: Ref.fm,
                    size: 11,
                    wght: 700,
                    ls: 3,
                    color: Ref.hot,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.planError ?? '',
            style: refText(
              family: Ref.fc,
              size: 14,
              wght: 500,
              height: 1.6,
              color: const Color(0xFFE9DBE3),
            ),
          ),
        ],
      ),
    );
  }

  /// B1 复核态：错误卡（若有）+ 已答卡 + 【重试拆解 / 开始拆解】【换个说法】+ 先跳过
  Widget _reviewView() {
    final List<InterviewCard> cs = widget.cards!;
    final bool failed = widget.planError != null;
    Widget row(String k, String v, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              k,
              style: refText(
                family: Ref.fc,
                size: 14,
                wght: 500,
                height: 1.4,
                color: Ref.dim,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: refText(
                family: Ref.fc,
                size: 14,
                wght: strong ? 700 : 500,
                height: 1.4,
                color: Ref.txt,
              ),
            ),
          ),
        ],
      ),
    );
    return Column(
      key: const Key('ref.onboard.review'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (failed) ...<Widget>[_errorCard(), const SizedBox(height: 12)],
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          decoration: BoxDecoration(
            color: const Color(0x08FFFFFF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Ref.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'KEPT · 已答，不用重答',
                      style: refText(
                        family: Ref.fm,
                        size: 11,
                        wght: 700,
                        ls: 3,
                        color: Ref.mint,
                      ),
                    ),
                  ),
                  GestureDetector(
                    key: const Key('ref.onboard.editAnswers'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      refPressSound('ui.tap');
                      setState(() {
                        _editing = true;
                        _cardIx = 0;
                        _custom = false;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        '改答案 ›',
                        style: refText(
                          family: Ref.fc,
                          size: 12,
                          wght: 500,
                          color: Ref.dim,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (widget.goalText.isNotEmpty) ...<Widget>[
                row('目标', widget.goalText, strong: true),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 5),
                  child: SizedBox(
                    height: 1,
                    child: ColoredBox(color: Ref.line),
                  ),
                ),
              ],
              for (final InterviewCard c in cs)
                row(c.question, _answers[c.id] ?? '—'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        RefButton(
          key: const Key('ref.onboard.retry'),
          label: failed ? '重试拆解' : '开始拆解',
          trailingTriangle: !failed,
          onTap: () =>
              widget.onDone?.call(Map<String, String>.unmodifiable(_answers)),
        ),
        if (widget.onRephrase != null) ...<Widget>[
          const SizedBox(height: 12),
          RefButton(
            key: const Key('ref.onboard.rephrase'),
            label: '换个说法',
            primary: false,
            small: true,
            animateSheen: false,
            onTap: widget.onRephrase,
          ),
        ],
        if (widget.onSkip != null) ...<Widget>[
          const SizedBox(height: 6),
          Center(
            child: GestureDetector(
              key: const Key('ref.onboard.skip'),
              behavior: HitTestBehavior.opaque,
              onTap: () {
                refPressSound('ui.tap');
                widget.onSkip!();
              },
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  '先跳过，今天先做日常 ›',
                  style: refText(
                    family: Ref.fc,
                    size: 13,
                    wght: 500,
                    color: Ref.dim,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _option(String text) {
    // B1「改答案」：上次选的那项描 acid 边，一眼看出原答案
    final List<InterviewCard> cs = widget.cards ?? const <InterviewCard>[];
    final bool was =
        _cardIx < cs.length && _answers[cs[_cardIx].id] == text;
    return GestureDetector(
      onTap: () => _answer(text),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: was ? Ref.a(Ref.acid, .08) : const Color(0x08FFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: was ? Ref.a(Ref.acid, .6) : Ref.line),
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
