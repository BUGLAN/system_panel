import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/tokens.dart';
import '../state/goal_gen.dart';
import 'press_scale.dart';

/// ═══════════════════════════════════════════════════════════
///  卡片式访谈（docs/18 §2.1 · T6-1）
///
///  绑定流第二步：目标输入之后，她按目标类型抽出 3~5 张信息卡，
///  一次一张 —— 每张 = 一个问题 + 3~4 个选项 chip + 「自己写」自由输入。
///  视觉语言沿用原型：玻璃面板 + 青色 mono kicker + 42px 圆角 chip
///  （`#ask .presets` 同款）+ kOut 缓动。
///
///  自包含组件：只认 [InterviewCard] 与回调，装配（挂进 onboard 幕）归 T8。
///  答案以 `卡 id → 答案原文` 交给 [onDone]，由调用方喂给
///  `PlanBrief.interview`（喂拆解）/ `dailyPoolFor` / `memoriesFromInterview`。
/// ═══════════════════════════════════════════════════════════
class InterviewDeck extends StatefulWidget {
  const InterviewDeck({
    super.key,
    required this.cards,
    required this.onDone,
    this.onCardAnswered,
    this.kicker = 'INTERVIEW · 访谈',
  }) : assert(
         cards.length >= 3 && cards.length <= 5,
         '访谈卡组必须落在 3~5 张（docs/18 §2.1）',
       );

  final List<InterviewCard> cards;

  /// 全部答完（最后一张卡提交）时回调，参数 = 卡 id → 答案原文。
  final ValueChanged<Map<String, String>> onDone;

  /// 每答完一张卡回调一次（换目标迷你流等场景可用来逐卡写记忆）。
  final void Function(InterviewCard card, String answer)? onCardAnswered;

  final String kicker;

  @override
  State<InterviewDeck> createState() => _InterviewDeckState();
}

class _InterviewDeckState extends State<InterviewDeck> {
  int _ix = 0;
  bool _custom = false;
  final Map<String, String> _answers = <String, String>{};
  final TextEditingController _customCtrl = TextEditingController();

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  InterviewCard get _card => widget.cards[_ix];

  void _answer(String value) {
    if (value.trim().isEmpty) return;
    _answers[_card.id] = value.trim();
    widget.onCardAnswered?.call(_card, value.trim());
    if (_ix == widget.cards.length - 1) {
      widget.onDone(Map<String, String>.unmodifiable(_answers));
      return;
    }
    setState(() {
      _ix += 1;
      _custom = false;
      _customCtrl.clear();
    });
  }

  void _submitCustom() => _answer(_customCtrl.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        key: const Key('deck'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _header(),
          const SizedBox(height: 10),
          _track(),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: kOut,
            switchOutCurve: kOut.flipped,
            transitionBuilder: (Widget child, Animation<double> a) {
              final Animation<double> ease = CurvedAnimation(
                parent: a,
                curve: Curves.easeOut,
              );
              return FadeTransition(
                opacity: ease,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, .12),
                    end: Offset.zero,
                  ).animate(ease),
                  child: child,
                ),
              );
            },
            child: _CardPanel(
              key: ValueKey<int>(_ix),
              card: _card,
              custom: _custom,
              customCtrl: _customCtrl,
              picked: (String opt) => _answer(opt),
              onCustomToggle: () => setState(() => _custom = true),
              onCustomSubmit: _submitCustom,
            ),
          ),
        ],
      ),
    );
  }

  /// kicker 行：左「INTERVIEW · 访谈」，右「01 / 03」
  Widget _header() {
    final TextStyle mono = fs(
      family: F.mono,
      size: 10,
      wght: 600,
      ls: 1.8,
      height: 1,
      color: C.blue,
    );
    return Row(
      children: <Widget>[
        Text(widget.kicker, style: mono),
        const Spacer(),
        Text(
          '${(_ix + 1).toString().padLeft(2, '0')} / '
          '${widget.cards.length.toString().padLeft(2, '0')}',
          key: const Key('deck.progress'),
          style: mono,
        ),
      ],
    );
  }

  /// 2px 进度轨：走过 = 亮青，未走 = 暗槽
  Widget _track() {
    final double v = _ix / widget.cards.length;
    return Container(
      key: const Key('deck.track'),
      height: 2,
      decoration: BoxDecoration(
        color: C.line2,
        borderRadius: BorderRadius.circular(1),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: v.clamp(0, 1),
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: C.blue,
              borderRadius: BorderRadius.circular(1),
              boxShadow: <BoxShadow>[BoxShadow(color: C.blue, blurRadius: 8)],
            ),
          ),
        ),
      ),
    );
  }
}

/// 单张卡：玻璃面板（`#ask` 同族的深底 + 青描边）
class _CardPanel extends StatelessWidget {
  const _CardPanel({
    super.key,
    required this.card,
    required this.custom,
    required this.customCtrl,
    required this.picked,
    required this.onCustomToggle,
    required this.onCustomSubmit,
  });

  final InterviewCard card;
  final bool custom;
  final TextEditingController customCtrl;
  final ValueChanged<String> picked;
  final VoidCallback onCustomToggle;
  final VoidCallback onCustomSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xDB040C1C), // rgba(4,12,28,.86)
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            card.question,
            key: const Key('deck.question'),
            style: fs(family: F.hd, size: 17, wght: 400, color: C.ice),
          ),
          const SizedBox(height: 14),
          if (custom)
            _customField()
          else ...<Widget>[
            // 宿主 2026-10-11：绑定仪式这几张访谈卡的答案也做成卡片 ——
            // 但「样式不能完全一样」，所以这里**竖排**（预设那排是横排胶囊、
            // 货架是竖版厚卡、名牒带挂孔）：一张答案一张横版薄牌，
            // 左上斜切 14 + 左侧 2px 青竖条，右侧一枚指向箭头。
            Column(
              key: const Key('deck.options'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < card.options.length; i++)
                  _chip(
                    card.options[i],
                    key: Key('deck.opt.${card.id}.$i'),
                    onTap: () => picked(card.options[i]),
                  ),
                _chip(
                  '自己写',
                  key: const Key('deck.custom'),
                  ghost: true,
                  onTap: onCustomToggle,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 一张答案牌（宿主指定的「访谈卡也做成卡片」）。
  ///
  /// 与另外几套卡语言刻意不同：货架＝竖版厚卡＋斜切 22＋吊钩价签；
  /// 名牒＝竖版窄牌＋挂孔；预设＝横排胶囊；**这里＝竖排横版薄牌**
  /// （左上斜切 14 + 左侧 2px 青竖条 + 右侧箭头）。
  ///
  /// ⚠️ 形状是**真的裁**（ClipPath），斜切那一段也要有描边，所以描边沿同一条路径画。
  /// ⚠️ PressBuilder 不收 key，钥匙挂在外层 KeyedSubtree 上。
  Widget _chip(String text, {required VoidCallback onTap, Key? key, bool ghost = false}) {
    return KeyedSubtree(
      key: key,
      child: PressBuilder(
        onTap: onTap,
        builder: (BuildContext _, bool down) => Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: SizedBox(
            height: 52,
            child: ClipPath(
              clipper: const _ChipClipper(),
              child: Stack(
                children: <Widget>[
                  if (!ghost)
                    const Positioned.fill(
                      child: ColoredBox(color: Color(0xFF050A14)),
                    ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: down
                              ? const <Color>[Color(0xFF1B3358), Color(0xFF0A1424)]
                              : (ghost
                                    ? const <Color>[Color(0x00000000), Color(0x00000000)]
                                    : const <Color>[Color(0xFF122441), Color(0xFF070D18)]),
                        ),
                      ),
                    ),
                  ),
                  // 左侧那一道青竖条：跟「这一条能选」的语义走（幽灵项不画）
                  if (!ghost)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 2,
                      child: ColoredBox(
                        color: down ? C.blue : C.blue.withAlpha(120),
                      ),
                    ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ChipEdgePainter(
                        color: ghost ? C.line : (down ? C.blue : C.line2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: fs(
                              family: F.cn,
                              size: 13,
                              wght: ghost ? 400 : 650,
                              color: ghost ? C.mist : C.ice,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          ghost ? '＋' : '›',
                          style: fs(
                            family: F.mono,
                            size: 13,
                            wght: 500,
                            height: 1,
                            color: down ? C.blue : C.mist,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 答案牌的轮廓：左上斜切 14
  static Path chipPath(Size s, {double inset = 0}) {
    const double b = 14;
    final double w = s.width - inset, h = s.height - inset;
    return Path()
      ..moveTo(inset, b)
      ..lineTo(b, inset)
      ..lineTo(w, inset)
      ..lineTo(w, h)
      ..lineTo(inset, h)
      ..close();
  }


  /// 「自己写」的自由输入行
  Widget _customField() {
    return Container(
      key: const Key('deck.custom.field'),
      height: 46,
      padding: const EdgeInsets.fromLTRB(14, 0, 5, 0),
      decoration: BoxDecoration(
        color: const Color(0xDB040C1C),
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: C.blue),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              key: const Key('deck.custom.input'),
              controller: customCtrl,
              autofocus: true,
              inputFormatters: <TextInputFormatter>[
                LengthLimitingTextInputFormatter(40),
              ],
              onSubmitted: (_) => onCustomSubmit(),
              cursorColor: C.blue,
              style: fs(family: F.cn, size: 14, wght: 500, color: C.ice),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '一句话，具体点',
                hintStyle: fs(
                  family: F.cn,
                  size: 14,
                  wght: 500,
                  color: const Color(0xFF50627E),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            key: const Key('deck.custom.submit'),
            behavior: HitTestBehavior.opaque,
            onTap: onCustomSubmit,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: C.blue,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Text(
                '确定',
                style: fs(family: F.cn, size: 12.5, wght: 700, color: C.deep),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 沿答案牌的轮廓描 1px 线（斜切那一段也要有线 —— `Border.all` 画的是圆角矩形，
/// 斜切段会缺一条、圆角的弧会漏在斜切外面，实测过）。
class _ChipEdgePainter extends CustomPainter {
  const _ChipEdgePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawPath(
      _CardPanel.chipPath(s, inset: .5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_ChipEdgePainter old) => old.color != color;
}

/// 答案牌的轮廓（左上斜切 14）
class _ChipClipper extends CustomClipper<Path> {
  const _ChipClipper();

  @override
  Path getClip(Size s) => _CardPanel.chipPath(s);

  @override
  bool shouldReclip(_ChipClipper oldClipper) => false;
}
