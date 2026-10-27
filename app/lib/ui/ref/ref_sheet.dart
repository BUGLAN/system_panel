import 'package:flutter/material.dart';

import '../../design/ref.dart';
import 'ref_inputs.dart';

/// ═══════════════════════════════════════════════════════════
///  系统设置抽屉 —— 参考稿 \`#sheet\`（CSS L481-491，DOM L837-843）
///
///  · 遮罩 rgba(4,3,10,.6) + blur 12（L481）
///  · 面板 28/28/0/0 圆角、#1a1630 → #0d0b17、顶部 1px 白 12%（L482）
///  · 44×5 抓条（L483）、900 20 标题（L484）
///  · 行：15/500 + 12/400 副标题、底部 1px line、padding 15/4（L485-486）
///  · 危险行 #ff8fb3（L487）；开关 52×30（L488-490）
///
///  参考稿没有覆盖、但 APP 已有的入口（对话 / LLM 连接）按同一行样式补在
///  「隐藏彩蛋」之后、「重置存档」之前 —— 只加行，不改版式。
/// ═══════════════════════════════════════════════════════════
class RefSheet extends StatefulWidget {
  const RefSheet({
    super.key,
    required this.visible,
    required this.sound,
    required this.onSound,
    required this.onClose,
    this.onHint,
    this.onChat,
    this.onLlm,
    this.onReset,
  });

  final bool visible;
  final bool sound;
  final ValueChanged<bool> onSound;
  final VoidCallback onClose;

  /// 隐藏彩蛋提示（JS L1655）
  final VoidCallback? onHint;

  /// APP 已有：和她聊聊
  final VoidCallback? onChat;

  /// APP 已有：LLM 连接设置
  final VoidCallback? onLlm;

  /// 重置存档（JS L1656）
  final VoidCallback? onReset;

  @override
  State<RefSheet> createState() => _RefSheetState();
}

class _RefSheetState extends State<RefSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 440),
  );

  @override
  void initState() {
    super.initState();
    if (widget.visible) _in.value = 1;
  }

  @override
  void didUpdateWidget(RefSheet old) {
    super.didUpdateWidget(old);
    if (widget.visible && !old.visible) {
      _in.forward(from: 0);
    } else if (!widget.visible && old.visible) {
      _in.reverse();
    }
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible && _in.isDismissed) return const SizedBox.shrink();
    final double t = Ref.ease.transform(_in.value);
    return Stack(
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
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
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
                  Text(
                    '系统设置',
                    style: refText(
                      family: Ref.fc,
                      size: 20,
                      wght: 900,
                      color: Ref.txt,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _row(
                    title: '音效',
                    sub: '点击、切换、暴击、升级……全部合成音',
                    trailing: RefSwitch(
                      on: widget.sound,
                      onChanged: widget.onSound,
                    ),
                    onTap: () => widget.onSound(!widget.sound),
                  ),
                  _row(
                    title: '秘籍',
                    sub: '老玩家都懂（桌面端键盘输入）',
                    trailing: Text(
                      '↑↑↓↓←→←→BA',
                      style: refText(
                        family: Ref.fm,
                        size: 13,
                        wght: 700,
                        ls: 2,
                        color: Ref.acid,
                      ),
                    ),
                  ),
                  _row(
                    title: '隐藏彩蛋提示',
                    sub: '戳她 · 长按她 · 连点计时器',
                    trailing: _arrow(),
                    onTap: widget.onHint,
                  ),
                  if (widget.onChat != null)
                    _row(
                      title: '和她聊聊',
                      sub: '她不负责安慰你，只负责说实话',
                      trailing: _arrow(),
                      onTap: widget.onChat,
                    ),
                  if (widget.onLlm != null)
                    _row(
                      title: 'LLM 连接',
                      sub: '端点 · 模型 · 温度 · 流式',
                      trailing: _arrow(),
                      onTap: widget.onLlm,
                    ),
                  _row(
                    title: '重置存档',
                    sub: '一切从「开机成功」重新开始',
                    trailing: _arrow(),
                    danger: true,
                    onTap: widget.onReset,
                    last: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _arrow() => Text(
    '›',
    style: refText(
      family: Ref.fd,
      size: 22,
      wght: 500,
      color: Ref.dim,
      height: 1,
    ),
  );

  Widget _row({
    required String title,
    required String sub,
    required Widget trailing,
    VoidCallback? onTap,
    bool danger = false,
    bool last = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 15),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: Ref.line)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: refText(
                      family: Ref.fc,
                      size: 15,
                      wght: 500,
                      color: danger ? const Color(0xFFFF8FB3) : Ref.txt,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: refText(
                      family: Ref.fc,
                      size: 12,
                      wght: 400,
                      color: Ref.dim,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing,
          ],
        ),
      ),
    );
  }
}
