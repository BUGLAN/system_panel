import 'package:flutter/material.dart';

import 'press_scale.dart';

import '../design/tokens.dart';

/// ═══════════════════════════════════════════════════════════
///  终端式输入（app.css L197-207 `#ask`）
///  绑定仪式里她问「你叫什么」「你想变成什么样」，宿主就在这儿敲。
///  可以先给几个现成答案（`.presets`）。
///
///  实测盒模型（390×844，目标那一步）：
///    ask [20,653,350,157]（bottom 34）
///    presets [20,653,350,91]（两行 42 + 间隔 7）
///    label [20,756,350,54] · ps [38,775,41,16] · input [89,756,201,54]
/// ═══════════════════════════════════════════════════════════
class AskField extends StatelessWidget {
  const AskField({
    super.key,
    required this.prompt,
    this.placeholder = '',
    this.presets = const <String>[],
    this.controller,
    this.focusNode,
    this.visible = true,
    this.onSubmit,
    this.onPreset,
  });

  /// 左边那个提示词（`目标 ›`）
  final String prompt;

  final String placeholder;

  /// 现成答案（点一下填进输入框）
  final List<String> presets;

  final TextEditingController? controller;

  /// 外部持有的焦点（弹/收键盘由外部控制；null = 组件内部自理）
  final FocusNode? focusNode;
  final bool visible;
  final VoidCallback? onSubmit;
  final ValueChanged<String>? onPreset;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 20,
      right: 20,
      bottom: 34,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: AnimatedSlide(
            offset: visible
                ? Offset.zero
                : const Offset(0, .3), // translateY(16px)
            duration: const Duration(milliseconds: 500),
            curve: kOut,
            child: Column(
              key: const Key('ask'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (presets.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Wrap(
                      key: const Key('ask.presets'),
                      spacing: 7,
                      runSpacing: 7,
                      children: <Widget>[
                        for (final String p in presets) _preset(p),
                      ],
                    ),
                  ),
                _field(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// `.presets button` —— 注意它继承了 `#ask button` 的 `height:42` 与 `font-weight:700`
  /// 按下：`#ask .presets button:active { background: rgba(56,225,255,.2) }`（瞬变，无过渡）
  Widget _preset(String text) {
    return PressBuilder(
      onTap: onPreset == null ? null : () => onPreset!(text),
      builder: (BuildContext _, bool down) => Container(
        height: 42,
        // Border 占布局、CSS 的 inset 阴影不占 → padding 各减 1px
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: down
              ? const Color(0x3338E1FF) // rgba(56,225,255,.2)
              : const Color(0xD1040C1C), // rgba(4,12,28,.82)
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: C.line, width: 1),
        ),
        // ⚠️ 不能给 Container 加 alignment —— 那会让它吃掉最大宽度，
        // 在 Wrap 里就变成一颗一行了（踩过）
        child: Center(
          widthFactor: 1,
          child: Text(
            text,
            style: fs(family: F.cn, size: 12.5, wght: 700, color: C.ice),
          ),
        ),
      ),
    );
  }

  Widget _field() {
    return Container(
      height: 54,
      padding: const EdgeInsets.fromLTRB(17, 0, 5, 0), // CSS 18/6，Border 占 1
      decoration: BoxDecoration(
        color: const Color(0xDB040C1C), // rgba(4,12,28,.86)
        borderRadius: BorderRadius.circular(27),
        border: Border.all(color: C.blue, width: 1),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: C.blue.withAlpha(51),
            blurRadius: 24,
          ), // 0 0 24px 20%
        ],
      ),
      child: Row(
        children: <Widget>[
          Text(
            prompt,
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
              controller: controller,
              focusNode: focusNode,
              onSubmitted: (_) => onSubmit?.call(),
              cursorColor: C.blue,
              style: fs(family: F.cn, size: 16, wght: 500, color: C.ice),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: placeholder,
                hintStyle: fs(
                  family: F.cn,
                  size: 16,
                  wght: 500,
                  color: const Color(0xFF50627E),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onSubmit,
            behavior: HitTestBehavior.opaque,
            child: Container(
              key: const Key('ask.submit'),
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: C.blue,
                borderRadius: BorderRadius.circular(21),
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
