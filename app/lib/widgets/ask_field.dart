import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'card_table.dart';
import 'rail_base.dart';

import '../design/tokens.dart';
import '../state/sfx.dart';

/// ═══════════════════════════════════════════════════════════
///  终端式输入（app.css L197-207 `#ask`）
///  + **换目标预设 = XS 微牌横滑牌列**（2026-10-12 · §4.B）
///
///  绑定仪式里她问「你叫什么」「你想变成什么样」，宿主就在这儿敲；
///  「换目标」的预设从**圆角胶囊**改成 **XS 微牌（100×72）横滑牌列** ——
///  与补给 / 档案 / 主线同一套牌语（斜切、状态线、领位抬起、档位咬合），
///  只是档位换成 XS。
///
///  ── 牌列（§4.B.1 ~ §4.B.3）──────────────────────────────────
///   · 一张预设 = 一张 `CardSkin.duty` 的 XS 微牌：① 角标（`预设 · 01`）
///     + ④ 单行名称 + ⑨ 状态线。XS 档**塞不下九区**，塞规则行必然裁字
///     （§10 已知坑 4）。
///   · 左右滑动 / 档位咬合（`rung` + 轻震）/ 吸附 / 领位抬起 —— 全在
///     `CardTable` 里（`rail_base.dart` 的 `RailShell`），这里一个字都不加。
///   · 点**领位** = 填入输入框（`onPreset`）；点**侧牌** = 送位（`CardTable`
///     自己处理：`kCardSideTapCommits = false`）。
///   · 牌列**末尾**可挂一张**非目标牌**：入口牌「先问小祥」（`onEntry`；
///     线框状态线 = 与目标牌区分）。它走 `onPick` 给的**下标**分派。
///
///  ── docs/39 M-24（2026-10-17 真机走查 · P1）──────────────────
///  取消牌「算了，不换」**已从牌列移除**：真机上它是牌列最右一张，被 430 屏宽
///  裁掉一半；而键盘一弹整条牌列连布局都不占（见下面纪律 2），取消就彻底没了
///  退路（走查图 04/08）。现在取消 = **输入幕左上那颗常驻 44 圆**（挂在
///  `main.dart`，只有主线的「换目标」有；绑定仪式本来就不该有取消），键盘弹起
///  也一直在。牌列只负责「预设」与「先问小祥」。
///
///  ── 三条布局纪律（第一优先级：不许挡住她的脸，§1）──────────
///   1. 她的脸在屏高 **20%~42%**，UI 只许落在 **45%~86%** 的安全带，整块贴底 34。
///   2. **键盘弹起 = 牌列退场**（§4.B.5）：`bottomInset > 0` 时整块被顶到
///      `844 − 336 − 34 = 474`，166 高的牌列再往上就摸到 **242 ≈ 28.7%** ——
///      正好压在她脸上。所以键盘可见时牌列**连布局都不占**，只留输入条 +
///      一枚「已选值」小标签。
///      ⚠️ 退场因此是**硬切**、没有 180ms 淡出：淡出期间它仍在布局里、仍会被
///      顶进禁区 —— 那不是「更顺滑」，那是挡脸。
///   3. `resizeToAvoidBottomInset` 仍归调用方（main.dart 必须 false：整屏随
///      键盘缩 → 舞台矩形变 → 插件重建 FBO + 她与环场错位）；本组件只吃
///      `bottomInset`，绝不自己动整屏。
///
///  盒模型（390×844，无键盘）：
///    ask [20,578,350,232]（bottom 34）= 牌列 166 + 12 + 输入条 54
///    牌列 166 = 牌高 72 + topPad 26 + dy2 38 + 尾隙 30（`CardTable._tableH`）
/// ═══════════════════════════════════════════════════════════

/// 输入条左上 / 右下那两道斜切（§4.B.4：与 TerminalButton 同一套斜切语言）
const double _kBevel = 9;

/// 【确定】键的斜切 —— 内层元素用更小的**同向**斜切（§3.1）
const double _kSubmitBevel = 6;

/// 「已选值」小标签的斜切（同上，再小一档）
const double _kTagBevel = 5;

/// 「已选值」小标签的估高（给安全带守卫用；宁可估大一点，早一点不显示）
const double _kTagH = 20;

class AskField extends StatefulWidget {
  const AskField({
    super.key,
    required this.prompt,
    this.placeholder = '',
    this.presets = const <String>[],
    this.controller,
    this.focusNode,
    this.visible = true,
    this.bottomInset = 0,
    this.onSubmit,
    this.onPreset,
    this.onEntry,
  });

  /// 左边那个提示词（`目标 ›`）
  final String prompt;

  final String placeholder;

  /// 现成答案（点领位那张牌 → 填进输入框）
  final List<String> presets;

  final TextEditingController? controller;

  /// 外部持有的焦点（弹/收键盘由外部控制；null = 组件内部自理）
  final FocusNode? focusNode;
  final bool visible;

  /// 键盘高度（`MediaQuery.viewInsetsOf(context).bottom`）。
  /// 主 Scaffold 用 `resizeToAvoidBottomInset: false`（**不能**让整屏随键盘缩，
  /// 否则舞台矩形跟着变 → 插件重建 FBO + 她整条位移；见 main.dart 的注释），
  /// 所以输入框得自己抬到键盘上面。
  ///
  /// ⚠️ 它同时是**牌列要不要退场**的唯一判据：`> 0` = 键盘可见 = 牌列不渲染。
  final double bottomInset;

  final VoidCallback? onSubmit;

  /// 点牌列领位那张**目标牌**：把预设词填进输入框
  final ValueChanged<String>? onPreset;

  /// 入口牌「先问小祥」（§4.B.2）：带场合上下文开对话，**不填输入框**。
  /// 传了它牌列末尾才会多出那一张。
  final VoidCallback? onEntry;

  // docs/39 M-24：原来这里还有 `onCancel`（牌列末尾的「算了，不换」）。
  // 取消已经搬去输入幕左上那颗**常驻 44 圆**（挂载在 main.dart），
  // 本组件不再承载取消 —— 牌列里也不再有 CANCEL，绑定仪式依旧没有取消。

  @override
  State<AskField> createState() => _AskFieldState();
}

class _AskFieldState extends State<AskField> {
  /// 自己造的 controller / focusNode（外部没给时才造，也要自己 dispose）
  TextEditingController? _ownCtrl;
  FocusNode? _ownFocus;
  late TextEditingController _ctrl;
  late FocusNode _focus;

  /// 最近一次从牌列里选中的预设（键盘态下用它回显「已选值」）
  String? _picked;

  /// 空输入点确定时的**内联**提示（§4.B.4：不许弹窗）
  String? _error;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    _ownCtrl = widget.controller == null ? TextEditingController() : null;
    _ownFocus = widget.focusNode == null ? FocusNode() : null;
    _ctrl = widget.controller ?? _ownCtrl!;
    _focus = widget.focusNode ?? _ownFocus!;
    _ctrl.addListener(_onText);
    _focus.addListener(_onFocus);
  }

  void _unbind() {
    _ctrl.removeListener(_onText);
    _focus.removeListener(_onFocus);
    _ownCtrl?.dispose();
    _ownFocus?.dispose();
    _ownCtrl = null;
    _ownFocus = null;
  }

  @override
  void didUpdateWidget(covariant AskField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller ||
        old.focusNode != widget.focusNode) {
      _unbind();
      _bind();
    }
    // 整块收起来（换目标关了 / 绑定仪式走了）：选中值与报错都归零，
    // 下次打开是一张干净的脸。
    if (old.visible && !widget.visible) {
      _picked = null;
      _error = null;
    }
  }

  @override
  void dispose() {
    _unbind();
    super.dispose();
  }

  void _onText() {
    // 一开始打字就撤掉内联提示 —— 它只在「空输入点确定」那一下有意义
    if (_error != null && _ctrl.text.trim().isNotEmpty) {
      setState(() => _error = null);
    }
  }

  void _onFocus() {
    if (mounted) setState(() {}); // 描边：聚焦转 C.blue（§4.B.4）
  }

  /// 键盘是否可见 —— **唯一判据是调用方给的 `bottomInset`**
  bool get _keyboardUp => widget.bottomInset > 0;

  /// docs/39 H-17 · 输入条距底的安全下限（原来是写死的 34）。
  ///
  /// 只取 `MediaQuery.padding` 的**下限**（math.max），不与 34 叠加 ——
  /// iPhone 的 Home Indicator 就是 34 → max(34, 34) = 34，真机位置不变；
  /// MuMu / 无手势条的机器 padding.bottom = 0 → 仍是 34，观感也不变。
  /// 以后出现更大的底部安全区（例如带 dock 的平板）它才真的抬起来。
  double _safeBottom(BuildContext context) =>
      math.max(34, MediaQuery.paddingOf(context).bottom);

  /// 键盘态下这枚标签会不会把整块顶进 `y < 45%` 的禁区（§1.2）。
  ///
  /// 屏幕矮 / 键盘高的机型上，输入条自己就已经贴到 45% 上下 —— 这时标签宁可
  /// 不显示：她的脸是第一位，而选中值在输入框里本来就看得见。
  bool _tagFits(BuildContext context) {
    final double h = MediaQuery.sizeOf(context).height;
    final double barTop = h - _safeBottom(context) - widget.bottomInset - 54;
    return barTop - 8 - _kTagH > h * .45;
  }

  /// 确定：空输入 → 内联提示（不弹窗、不落库）；有内容 → 交给调用方
  void _submit() {
    if (_ctrl.text.trim().isEmpty) {
      setState(() => _error = '空的她拆不动');
      return;
    }
    if (_error != null) setState(() => _error = null);
    // docs/39 M-24 / §5.4：确认 = `choose`（取消那颗圆是 `tap`，两者语义分开）。
    // 放这里而不是调用方：绑定仪式与换目标两条路都要这一声。
    Sfx.play('choose');
    widget.onSubmit?.call();
  }

  /// 牌列：预设牌 → 入口牌（§4.B.1 / §4.B.2）—— docs/39 M-24：取消牌已删
  List<TableCard> _cards() {
    final List<TableCard> out = <TableCard>[];
    for (int i = 0; i < widget.presets.length; i++) {
      out.add(
        TableCard(
          id: 'preset.$i',
          // ① 角标：`预设 · 01`（与货架/牌屉的编号同一套，从 01 起）
          kicker: '预设 · ${(i + 1).toString().padLeft(2, '0')}',
          // ④ 单行名称（XS 档只有这一行是正文）
          title: widget.presets[i],
          // ⑨ 亮青实线 = 可接（目标牌）
          dutyState: DutyState.open,
        ),
      );
    }
    if (widget.onEntry != null) {
      // 入口牌**不是目标牌**：sealed = 虚线状态线（线框），与目标牌区分开
      out.add(
        const TableCard(
          id: 'preset.entry',
          kicker: 'ENTRY · 小祥',
          title: '先问小祥',
          dutyState: DutyState.sealed,
        ),
      );
    }
    return out;
  }

  /// 牌列落定：`onPick` 给的是**下标**，按下标分派（§4.B.1 / §4.B.2 / §4.B.3）。
  ///
  /// ⚠️ 点侧牌只送位、不落定（`kCardSideTapCommits = false`），所以这里只在
  ///    「点领位」那一下被调到 —— 左右滑动、档位咬合、吸附全由 `CardTable` 负责。
  void _onPick(int i) {
    final List<TableCard> cards = _cards();
    if (i < 0 || i >= cards.length) return;
    final TableCard c = cards[i];
    if (c.id == 'preset.entry') {
      widget.onEntry?.call();
      return;
    }
    setState(() {
      _picked = c.title;
      _error = null;
    });
    widget.onPreset?.call(c.title); // 点领位 = 填入输入框
  }

  @override
  Widget build(BuildContext context) {
    final bool reduce = railReduceMotion(context);
    final List<TableCard> cards = _cards();
    // 键盘一弹，整块被 bottomInset 顶上去；牌列再跟着上就是压她的脸 ——
    // 所以键盘态**连布局都不占**（§4.B.5 / §1.3 硬约束 4）。
    final bool railOn = cards.isNotEmpty && !_keyboardUp;

    return Positioned(
      left: 20,
      right: 20,
      // docs/39 H-17：底边 34 是**安全区下限**（不是写死值），见 [_safeBottom]
      bottom: _safeBottom(context) + widget.bottomInset,
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: AnimatedOpacity(
          opacity: widget.visible ? 1 : 0,
          // 减弱动态：只剩一次短淡入（§3.2：更少更轻，不是全无）
          duration: Duration(milliseconds: reduce ? 160 : 300),
          child: AnimatedSlide(
            offset: (widget.visible || reduce)
                ? Offset.zero
                : const Offset(0, .3), // translateY(16px)
            duration: Duration(milliseconds: reduce ? 160 : 500),
            curve: kOut,
            child: Column(
              key: const Key('ask'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (railOn) _rail(cards),
                // 键盘态：牌列退场，已选值改由一枚小标签回显（§4.B.5）
                if (_keyboardUp && _picked != null && _tagFits(context))
                  _pickedTag(),
                _field(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// XS 微牌横滑牌列（§4.B.1）—— 机械全在 `CardTable`，这里只给牌面与档位。
  Widget _rail(List<TableCard> cards) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CardTable(
        // 牌列容器（`ask.presets` 挂在整条轨上）
        key: const Key('ask.presets'),
        cards: cards,
        skin: CardSkin.duty,
        size: CardTableSize.s, // XS 微牌 100×72
        onPick: _onPick,
      ),
    );
  }

  /// 键盘态下的「已选值」小标签（§4.B.5）。
  ///
  /// 牌列退场后选中的那一个不能就这么消失，用一枚小标签回显。
  /// ⚠️ 贴在**输入条上方**而不是塞进 Row：键盘态下宽度最紧张，塞进去会直接
  ///    吃掉正在打字的宽度（输入框只剩 ~90px）。
  Widget _pickedTag() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: const ShapeDecoration(
            color: C.abyss,
            shape: BeveledRectangleBorder(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(_kTagBevel),
                bottomRight: Radius.circular(_kTagBevel),
              ),
              side: BorderSide(color: C.line),
            ),
          ),
          child: Text(
            '已选 · ${_picked!}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: fs(
              family: F.mono,
              size: 10,
              wght: 600,
              ls: .6, // 小字标正字距（§15）
              height: 1.1,
              color: C.blue,
            ),
          ),
        ),
      ),
    );
  }

  /// 输入条（§4.B.4：单行输入 + 右侧【确定】，只优化材质与斜切，不改结构）
  Widget _field() {
    final bool focused = _focus.hasFocus;
    return Container(
      height: 54,
      // CSS 18/6，Border 占 1
      padding: const EdgeInsets.fromLTRB(17, 0, 5, 0),
      // 牌语统一：近实底 `C.abyss` + 细边 `C.line`，聚焦时描边转 `C.blue`；
      // 斜切 = 左上 + 右下 9px。
      //
      // ⚠️ 形状必须走 **ShapeDecoration**：`BoxDecoration` 的背景是按**矩形**铺的
      //    （`_paintBackgroundColor` 只认 `borderRadius`，不认 `OutlinedBorder` 的
      //    路径），配 `BeveledRectangleBorder` 会留下一块方角 + 一条斜线，等于没切。
      decoration: ShapeDecoration(
        color: C.abyss,
        shape: BeveledRectangleBorder(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(_kBevel),
            bottomRight: Radius.circular(_kBevel),
          ),
          side: BorderSide(color: focused ? C.blue : C.line),
        ),
        shadows: <BoxShadow>[
          if (focused)
            BoxShadow(
              color: C.blue.withAlpha(51),
              blurRadius: 24,
            ) // 0 0 24px 20%
          else
            const BoxShadow(
              color: Color(0x99000000),
              offset: Offset(0, 6),
              blurRadius: 16,
            ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Text(
            widget.prompt,
            key: const Key('ask.prompt'),
            style: fs(
              family: F.mono,
              size: 12,
              wght: 600,
              ls: .72,
              height: 1,
              color: C.blue,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const Key('ask.input'),
              controller: _ctrl,
              focusNode: _focus,
              onSubmitted: (_) => _submit(),
              cursorColor: C.blue,
              style: fs(family: F.cn, size: 16, wght: 500, color: C.ice),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.placeholder,
                hintStyle: fs(
                  family: F.cn,
                  size: 16,
                  wght: 500,
                  color: const Color(0xFF50627E),
                ),
                // 空输入点确定 → **内联**一行小字，不弹窗（§4.B.4）。
                // 它长在输入框自己的装饰里，所以输入条高度不变（54 装得下）。
                errorText: _error,
                errorMaxLines: 1,
                errorStyle: fs(
                  family: F.cn,
                  size: 11,
                  wght: 500,
                  height: 1.1,
                  color: C.rS,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _submit,
            behavior: HitTestBehavior.opaque,
            child: Container(
              key: const Key('ask.submit'),
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: const ShapeDecoration(
                color: C.blue,
                // 内层元素用更小的**同向**斜切（§3.1）
                shape: BeveledRectangleBorder(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(_kSubmitBevel),
                    bottomRight: Radius.circular(_kSubmitBevel),
                  ),
                ),
              ),
              child: Text(
                '确定',
                style: fs(family: F.cn, size: 14, wght: 700, color: C.deep),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
