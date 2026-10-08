import 'package:flutter/material.dart';

/// ═══════════════════════════════════════════════════════════
///  CSS 的 `:active` 缩放（原型里散在七处）
///
/// ```css
/// .btn:active       { transform: scale(.96); }                 /* 所有按钮 */
/// .cta:active .cta-core { transform: scale(.92); }             /* 大蓝键的芯 */
/// .dk:active .ic    { transform: scale(.9); box-shadow: … }    /* 底栏三个键的图标 */
/// ```
///
/// ⚠️ 这些是**按下瞬间**的反馈，不是动画 —— CSS 里没有 transition，
///    所以这里也**不加时长**（一按下就到、一松手就回）。
///    加上 `AnimatedScale` 反而会变成"慢半拍"，与原型的干脆手感不同。
///
/// 用法：把要缩放的那一层包起来（**只包该缩的那层** —— 比如 CTA 只缩芯，
/// 外圈的呼吸光环不缩）。
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.scale = .96,
    this.onTap,
    this.pressedGlow,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;

  /// 按下时缩到多少（原型各处的值不同，默认取 `.btn` 的 .96）
  final double scale;

  final VoidCallback? onTap;

  /// 按下时额外加的一层外发光（`.dk:active .ic` 有，别的没有）
  final List<BoxShadow>? pressedGlow;

  final HitTestBehavior behavior;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    Widget child = widget.child;
    if (_down && widget.pressedGlow != null) {
      child = DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: widget.pressedGlow,
        ),
        child: child,
      );
    }
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapUp: widget.onTap == null ? null : (_) => _set(false),
      onTapCancel: widget.onTap == null ? null : () => _set(false),
      onTap: widget.onTap,
      child: Transform.scale(scale: _down ? widget.scale : 1, child: child),
    );
  }
}
