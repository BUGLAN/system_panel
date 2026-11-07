import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../design/ref.dart';
import 'ref_inputs.dart';
import 'ref_kit.dart' show refPressSound;

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
///
///  进出：常驻挂载、由 [visible] 驱动 —— 挂上即 440ms 从底部滑上，
///  关掉时反向滑下、滑完才摘树。原来首帧直接落终态、build 也不订阅控制器，
///  抽屉是「啪」一下出现、「啪」一下消失的。开 `ui.open` / 关 `ui.close`。
/// ═══════════════════════════════════════════════════════════
class RefSheet extends StatefulWidget {
  const RefSheet({
    super.key,
    required this.visible,
    required this.sound,
    required this.onSound,
    required this.onClose,
    this.vision = true,
    this.onVision,
    this.onHint,
    this.onChat,
    this.onLlm,
    this.onReset,
    this.onAgreement,
    this.onPrivacy,
    this.onRevoke,
  });

  final bool visible;
  final bool sound;
  final ValueChanged<bool> onSound;
  final VoidCallback onClose;

  /// 证据视觉校验开关（= `AgentSettings.visionEnabled`，宿主定案 G2.3：从只在
  /// debug 可达的 LLM 设置页挪到这里，所有构建都露）。[onVision] 为 null 不显示这行
  final bool vision;
  final ValueChanged<bool>? onVision;

  /// 隐藏彩蛋提示（JS L1655）
  final VoidCallback? onHint;

  /// APP 已有：和她聊聊
  final VoidCallback? onChat;

  /// APP 已有：LLM 连接设置
  final VoidCallback? onLlm;

  /// 重置存档（JS L1656）
  final VoidCallback? onReset;

  /// G2.1：查看《用户协议》/《隐私政策》、撤回同意（所有构建都显示）
  final VoidCallback? onAgreement;
  final VoidCallback? onPrivacy;
  final VoidCallback? onRevoke;

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
    // 首帧就可见（直接挂一张打开的抽屉）：只演入场、不出声 —— 声音只跟「开/关」
    // 这个状态切换走（主壳里抽屉常驻挂载，开抽屉一定经过 didUpdateWidget）
    if (widget.visible) _open(sound: false);
  }

  @override
  void didUpdateWidget(RefSheet old) {
    super.didUpdateWidget(old);
    if (widget.visible && !old.visible) {
      _open();
    } else if (!widget.visible && old.visible) {
      refPressSound('ui.close');
      _in.reverse();
    }
  }

  void _open({bool sound = true}) {
    if (sound) refPressSound('ui.open');
    final bool reduce = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    if (reduce) {
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
    return AnimatedBuilder(
      animation: _in,
      builder: (BuildContext context, Widget? _) {
        if (!widget.visible && _in.isDismissed) return const SizedBox.shrink();
        // 关闭途中不再接手势（防止滑下去的那半秒里又点中一行）
        return IgnorePointer(ignoring: !widget.visible, child: _sheet(context));
      },
    );
  }

  Widget _sheet(BuildContext context) {
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
                    sub: '点击、切换、暴击、升级……8-bit 音效包', // A10（docs/50）
                    trailing: RefSwitch(
                      on: widget.sound,
                      onChanged: widget.onSound,
                    ),
                    onTap: () => widget.onSound(!widget.sound),
                  ),
                  // G2.3（宿主定案）：LLM 设置页只在 debug 可达，视觉校验开关不跟着
                  // 藏起来 —— 挪到这一行，所有构建都露（写的仍是 visionEnabled）
                  if (widget.onVision case final ValueChanged<bool> onVision)
                    _row(
                      title: '证据视觉校验',
                      sub: '证据图发给 AI 核对，不符的拒收；关掉 = 照收，一律按「未校验」计',
                      trailing: RefSwitch(
                        on: widget.vision,
                        onChanged: onVision,
                      ),
                      onTap: () => onVision(!widget.vision),
                    ),
                  // A17（docs/50）：秘籍 / 彩蛋提示 / LLM 连接是开发向入口，
                  // release 不露（G2.3 起长按 HUD 菜单键的隐藏入口也只在 debug 接线）
                  if (kDebugMode)
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
                  if (kDebugMode)
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
                  if (widget.onLlm != null && kDebugMode)
                    _row(
                      title: 'LLM 连接',
                      sub: '端点 · 模型 · 温度 · 上下文',
                      trailing: _arrow(),
                      onTap: widget.onLlm,
                    ),
                  // G2.1 隐私与协议：上架必需，**不**像秘籍 / LLM 连接那样只在 debug 露。
                  // 三个入口压进一行（三颗小签）：抽屉不可滚，再加三整行，
                  // debug 构建在 320×640 上会把标题顶出屏幕。
                  if (widget.onAgreement != null ||
                      widget.onPrivacy != null ||
                      widget.onRevoke != null)
                    _legalRow(),
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

  /// 「隐私与协议」行：标题 + 三颗小签（撤回同意用危险色）
  Widget _legalRow() {
    return Container(
      key: const Key('ref.sheet.legal'),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 15),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Ref.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 不配副标题、签上不带书名号：这一行要在 320 宽里一行排下三颗签
          // （折成两行时整张抽屉高出 ~60，debug 构建的标题会被顶出屏幕）
          Text(
            '隐私与协议',
            style: refText(family: Ref.fc, size: 15, wght: 500, color: Ref.txt),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (widget.onAgreement != null)
                _legalPill('ref.sheet.agreement', '用户协议', widget.onAgreement!),
              if (widget.onPrivacy != null)
                _legalPill('ref.sheet.privacy', '隐私政策', widget.onPrivacy!),
              if (widget.onRevoke != null)
                _legalPill(
                  'ref.sheet.revoke',
                  '撤回同意',
                  widget.onRevoke!,
                  danger: true,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legalPill(
    String key,
    String label,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    final Color c = danger ? const Color(0xFFFF8FB3) : Ref.txt;
    return GestureDetector(
      key: Key(key),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        refPressSound('ui.tap');
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: danger ? Ref.a(c, .45) : const Color(0x26FFFFFF),
          ),
        ),
        child: Text(
          label,
          style: refText(family: Ref.fc, size: 13, wght: 500, color: c),
        ),
      ),
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
      onTap: onTap == null
          ? null
          : () {
              refPressSound('ui.tap');
              onTap();
            },
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
