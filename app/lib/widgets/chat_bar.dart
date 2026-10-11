import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../design/tokens.dart';
import 'press_scale.dart';
import 'sys_icons.dart';

/// ═══════════════════════════════════════════════════════════
///  对话层的两件 UI（docs/18 §2.6）
///
///  · [ChatEntryButton]：对话入口。原先钉在大厅左上（HUD 下方）的 34×34 小圆钮；
///    宿主 2026-10-11 指定搬到**右下、委托板正上方**，并放大到 56（贴右手拇指）。
///  · [ChatBar]：对话层底部的输入栏——【文本输入+发送】【🎤语音】双入口。
///    **语音是明确的预留态**：置灰 + 「即将支持」角标，点了弹插话不假装可用。
/// ═══════════════════════════════════════════════════════════

/// 大厅的对话入口（原型无此物，样式对齐 `#sheet ×`/`.dk` 的玻璃圆钮）
class ChatEntryButton extends StatelessWidget {
  const ChatEntryButton({super.key, this.onTap, this.size = 34});

  final VoidCallback? onTap;

  /// 直径。默认 34（原型那颗）；搬到委托上方后宿主指定 56。
  final double size;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      pressedGlow: const <BoxShadow>[
        BoxShadow(color: Color(0x5938E1FF), blurRadius: 16),
      ],
      child: Container(
        key: const Key('chat.entry'),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xB3040E20), // rgba(4,14,32,.7)
          border: Border.all(color: C.line, width: 1),
        ),
        child: Center(
          child: SvgPicture.string(kIconChat, width: size * .47, height: size * .47),
        ),
      ),
    );
  }
}

/// 输入栏：`TextField + 发送 + 🎤语音（预留）`
class ChatBar extends StatefulWidget {
  const ChatBar({
    super.key,
    this.controller,
    this.onSend,
    this.onVoiceTap,
    this.enabled = true,
    this.hint = '说点什么…',
  });

  /// 外部可注入（测试/受控）；不给就自己管
  final TextEditingController? controller;
  final ValueChanged<String>? onSend;

  /// 点置灰的语音钮（上层弹她的插话）
  final VoidCallback? onVoiceTap;

  /// LLM 忙时锁输入（防连发）
  final bool enabled;
  final String hint;

  @override
  State<ChatBar> createState() => _ChatBarState();
}

class _ChatBarState extends State<ChatBar> {
  TextEditingController? _own;

  TextEditingController get _c => widget.controller ?? (_own ??= TextEditingController());

  void _fire() {
    final String text = _c.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    if (widget.controller == null) _c.clear(); // 受控时由宿主清
    widget.onSend?.call(text);
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool canSend = widget.enabled;
    return Container(
      key: const Key('chat.bar'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: C.line2, width: 1)),
      ),
      child: Row(
        children: <Widget>[
          // 文本输入（docs/18 §2.6：回车 / 发送都提交）
          Expanded(
            child: Container(
              key: const Key('chat.input.wrap'),
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: C.blue.withAlpha(13), // rgba(56,225,255,.05)
                borderRadius: BorderRadius.circular(19),
                border: Border.all(color: C.line2, width: 1),
              ),
              alignment: Alignment.center,
              child: TextField(
                key: const Key('chat.input'),
                controller: _c,
                enabled: canSend,
                style: fs(family: F.cn, size: 13.5, wght: 400, color: C.ice),
                cursorColor: C.blue,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: widget.hint,
                  hintStyle: fs(
                    family: F.cn,
                    size: 13,
                    wght: 400,
                    color: C.dim,
                  ),
                ),
                onSubmitted: (String _) => _fire(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 发送
          PressScale(
            onTap: canSend ? _fire : null,
            child: Container(
              key: const Key('chat.send'),
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: canSend ? C.blue : C.blue.withAlpha(26),
              ),
              child: Text(
                '↑',
                style: fs(
                  family: F.num,
                  size: 18,
                  wght: 800,
                  height: 1,
                  color: canSend ? C.deep : C.dim,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 🎤 语音 —— 预留态：置灰 + 「即将支持」角标（验收口径）
          PressScale(
            onTap: widget.onVoiceTap,
            child: SizedBox(
              key: const Key('chat.voice'),
              width: 44,
              height: 38,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: C.blue.withAlpha(13),
                      border: Border.all(color: C.line2, width: 1),
                    ),
                    child: Text(
                      '🎤',
                      style: fs(
                        family: F.cn,
                        size: 14,
                        wght: 400,
                        height: 1,
                        color: C.dim,
                      ),
                    ),
                  ),
                  // 「即将支持」角标
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      key: const Key('chat.voice.badge'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xEE04122A),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: C.line2, width: 1),
                      ),
                      child: Text(
                        '即将支持',
                        style: fs(
                          family: F.cn,
                          size: 7.5,
                          wght: 400,
                          height: 1.2,
                          color: C.mist,
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
    );
  }
}
