import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../widgets/chat_bar.dart';
import '../widgets/press_scale.dart';
import '../widgets/type_text.dart';
import 'chat_history.dart';
import 'chat_service.dart';

/// ═══════════════════════════════════════════════════════════
///  对话层（docs/18 §2.6 + docs/19 §A3 快捷工具行）
///
///  从底部滑入、占屏高 72%；背景半透明压暗，她在后面仍可见
///  ——层序在 Live2D 之上、亮帧之下（main.dart 挂载点保证）。
///  结构：名牌（小祥 · 系统娘 · 在线）→ 可滚动历史（时间分组头
///  今天/昨天/M月D日）→ 思考中… → 快捷工具 chip 行 → 输入栏。
///
///  她的气泡用 [TypeText] 打字机（每条只打一次）；情绪标签已由
///  ChatService 剥掉，正文直接可念。〔工具〕前缀的消息渲染成
///  系统条目（等宽读数风，不打字机）。
///
///  快捷 chip = 无 LLM 也能直调工具（docs/19 §A3）：查状态/换任务/
///  调整计划。样式沿用 interview_deck 选项 chip 惯例（42px 圆角盒 +
///  PressBuilder 按下反馈），配色/字体走 design/tokens.dart。
/// ═══════════════════════════════════════════════════════════

/// 一个快捷工具 chip：[label] 给人看，[tool] 是注册表里的工具名。
class ChatQuickChip {
  const ChatQuickChip(this.label, this.tool);

  final String label;
  final String tool;
}

/// 首发三枚（无 LLM 也可直调，docs/19 §A3）
const List<ChatQuickChip> kChatQuickChips = <ChatQuickChip>[
  ChatQuickChip('查状态', 'get_status'),
  ChatQuickChip('换任务', 'swap_quest'),
  ChatQuickChip('调整计划', 'adjust_plan'),
];

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.messages,
    this.visible = true,
    this.thinking = false,
    this.name = '小祥',
    this.onSend,
    this.onClose,
    this.onVoiceTap,
    this.onQuickTool,
    this.enabled = true,
    this.quickChips = kChatQuickChips,
  });

  /// 旧 → 新
  final List<ChatMessage> messages;
  final bool visible;

  /// LLM 忙（「思考中…」占位 + 锁输入）
  final bool thinking;
  final String name;
  final ValueChanged<String>? onSend;
  final VoidCallback? onClose;
  final VoidCallback? onVoiceTap;

  /// 快捷 chip 直调工具（docs/19 §A3）；null = chips 置灰不可点
  final ValueChanged<String>? onQuickTool;

  /// chip 数据（测试可注入）
  final List<ChatQuickChip> quickChips;
  final bool enabled;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final ScrollController _scroll = ScrollController();

  /// 已经打过字的那条消息（每条只演一次打字机；重开面板不重打）
  final Set<String> _typed = <String>{};

  /// 已经"到货"的消息数 —— 一次只进一条她的回复 = 会话节奏，打字；
  /// 批量到货（首次读档等）= 历史，全部标记已读不打字
  int _seen = 0;

  @override
  void initState() {
    super.initState();
    // 挂载时就已在的历史都算"读过"——只有本次会话新到的才打字
    _typed.addAll(widget.messages.map((ChatMessage m) => m.id));
    _seen = widget.messages.length;
  }

  @override
  void didUpdateWidget(covariant ChatPanel old) {
    super.didUpdateWidget(old);
    final int n = widget.messages.length;
    final bool grew = n > _seen;
    if (grew) {
      if (n - _seen > 1 || widget.messages[n - 1].fromHost) {
        for (int i = _seen; i < n; i++) {
          _typed.add(widget.messages[i].id);
        }
      }
      _seen = n;
    } else if (n < _seen) {
      _seen = n;
    }
    if ((grew || (!old.visible && widget.visible)) && widget.visible) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double h = MediaQuery.sizeOf(context).height;
    return Positioned.fill(
      // 收起来时同时断掉命中，别替下面的东西挨点
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: AnimatedOpacity(
          opacity: widget.visible ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: Stack(
            children: <Widget>[
              // 背景半透明压暗——她在后面仍可见；点背景 = 关
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onClose,
                  child: const ColoredBox(color: Color(0x7302060E)),
                ),
              ),
              // 面板本体：占屏高 72%，从底部滑入
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: h * .72,
                child: AnimatedSlide(
                  offset: widget.visible
                      ? Offset.zero
                      : const Offset(0, 1.04),
                  duration: const Duration(milliseconds: 450),
                  curve: kOut,
                  child: DecoratedBox(
                    key: const Key('chat.panel'),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Color(0xF0061228),
                          Color(0xFA030812),
                        ],
                        stops: <double>[0, .3],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _head(),
                        Container(height: 1, color: C.line2),
                        Expanded(child: _history()),
                        if (widget.thinking) _thinking(),
                        _quickTools(),
                        SafeArea(
                          top: false,
                          child: ChatBar(
                            onSend: widget.onSend,
                            onVoiceTap: widget.onVoiceTap,
                            enabled: widget.enabled && !widget.thinking,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 名牌：小祥 + 状态点 + 「系统娘 · 在线」；右边 × 关闭
  Widget _head() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Row(
        children: <Widget>[
          // 状态点（呼吸感用静态辉光即可，docs 没给动效规格）
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: C.blue,
              boxShadow: <BoxShadow>[BoxShadow(color: C.blue, blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            widget.name,
            key: const Key('chat.name'),
            style: fs(family: F.hd, size: 17, wght: 400, ls: .68, color: C.ice),
          ),
          const SizedBox(width: 10),
          Text(
            '系统娘 · 在线',
            key: const Key('chat.status'),
            style: fs(family: F.mono, size: 9.5, wght: 500, ls: 1.1, color: C.mist),
          ),
          const Spacer(),
          GestureDetector(
            onTap: widget.onClose,
            behavior: HitTestBehavior.opaque,
            child: Container(
              key: const Key('chat.close'),
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: C.line, width: 1),
              ),
              child: Text(
                '×',
                style: fs(family: F.cn, size: 22, wght: 400, height: 1, color: C.ice),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 可滚动历史 + 时间分组头（今天/昨天/M月D日）
  Widget _history() {
    final List<ChatMessage> ms = widget.messages;
    if (ms.isEmpty) {
      return Center(
        child: Text(
          '有事说事。我听着。',
          key: const Key('chat.empty'),
          style: fs(family: F.cn, size: 12.5, wght: 400, color: C.dim),
        ),
      );
    }
    final List<Widget> children = <Widget>[];
    for (int i = 0; i < ms.length; i++) {
      final ChatMessage m = ms[i];
      final bool newDay =
          i == 0 || ChatHistory.dayLabel(ms[i - 1].at) != ChatHistory.dayLabel(m.at);
      if (newDay) {
        children.add(
          Padding(
            key: Key('chat.day.$i'),
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
            child: Row(
              children: <Widget>[
                Expanded(child: Container(height: 1, color: C.line2)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    ChatHistory.dayLabel(m.at),
                    style: fs(
                      family: F.mono,
                      size: 9,
                      wght: 500,
                      ls: 1.2,
                      color: C.dim,
                    ),
                  ),
                ),
                Expanded(child: Container(height: 1, color: C.line2)),
              ],
            ),
          ),
        );
      }
      children.add(_bubble(m, i));
    }
    return ListView(
      key: const Key('chat.list'),
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      children: children,
    );
  }

  Widget _bubble(ChatMessage m, int i) {
    final bool host = m.fromHost;
    // 〔工具〕系统条目：等宽读数风、不打字机、左侧细框
    if (!host && m.text.startsWith(ChatService.toolTag)) {
      return Align(
        key: Key('chat.msg.$i'),
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(top: 7),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(
            color: const Color(0x8C050E20),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: C.line2, width: 1),
          ),
          child: Text(
            m.text,
            key: Key('chat.toolentry.$i'),
            style: fs(family: F.mono, size: 11, wght: 500, height: 1.5, color: C.mist),
          ),
        ),
      );
    }
    // 她的最新一条 + 还没打过字 → 打字机；点一下立刻铺完
    final bool fresh =
        !host && !_typed.contains(m.id) && i == widget.messages.length - 1;
    final Widget body = fresh
        ? TypeText(
            key: ValueKey<String>('chat.bubble.type.${m.id}'),
            text: m.text,
            speed: 30,
            style: fs(family: F.cn, size: 13.5, wght: 400, height: 1.5, color: C.ice),
            onDone: () {
              if (mounted) setState(() => _typed.add(m.id));
            },
          )
        : Text(
            m.text,
            style: fs(family: F.cn, size: 13.5, wght: 400, height: 1.5, color: C.ice),
          );
    return Align(
      key: Key('chat.msg.$i'),
      alignment: host ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: fresh ? () => setState(() => _typed.add(m.id)) : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(top: 7),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          constraints: const BoxConstraints(maxWidth: 286),
          decoration: BoxDecoration(
            // 她 = 左 + 青框深底；宿主 = 右 + 青底深字（docs/18 §2.6）
            color: host ? C.blue : const Color(0xBD050E20),
            borderRadius: BorderRadius.circular(14),
            border: host ? null : Border.all(color: C.line, width: 1),
            boxShadow: host
                ? <BoxShadow>[BoxShadow(color: C.blue.withAlpha(89), blurRadius: 14)]
                : null,
          ),
          child: body,
        ),
      ),
    );
  }

  /// 「思考中…」占位（她=左侧小气泡样式）
  Widget _thinking() {
    return Padding(
      key: const Key('chat.thinking'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xBD050E20),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: C.line2, width: 1),
          ),
          child: Text(
            '思考中…',
            style: fs(family: F.cn, size: 12.5, wght: 400, height: 1.4, color: C.mist),
          ),
        ),
      ),
    );
  }

  /// 快捷工具 chip 行（docs/19 §A3）：无 LLM 也能直调工具。
  /// 样式=interview_deck 选项 chip 同款语言（42px 圆角盒 + PressBuilder
  /// 按下换底 `rgba(56,225,255,.2)`），thinking/未接线时置灰不可点。
  Widget _quickTools() {
    final bool live = widget.enabled && !widget.thinking && widget.onQuickTool != null;
    return Container(
      key: const Key('chat.tools'),
      height: 54,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: C.line2, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: <Widget>[
            for (int i = 0; i < widget.quickChips.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 7),
              _toolChip(widget.quickChips[i], live: live),
            ],
          ],
        ),
      ),
    );
  }

  /// interview_deck `_chip` 的同款盒模型（42px 圆角 + 按下反馈）
  Widget _toolChip(ChatQuickChip chip, {required bool live}) {
    return KeyedSubtree(
      key: Key('chat.tool.${chip.tool}'),
      child: PressBuilder(
        onTap: live ? () => widget.onQuickTool!(chip.tool) : null,
        builder: (BuildContext _, bool down) => Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: live
                ? (down ? const Color(0x3338E1FF) : const Color(0xD1040C1C))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.line2),
          ),
          child: Text(
            chip.label,
            key: Key('chat.tool.label.${chip.tool}'),
            style: fs(
              family: F.cn,
              size: 12.5,
              wght: 700,
              color: live ? C.ice : C.dim,
            ),
          ),
        ),
      ),
    );
  }
}
