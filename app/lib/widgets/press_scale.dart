import 'package:flutter/material.dart';

/// ═══════════════════════════════════════════════════════════
///  CSS 的 `:active` 反馈（原型里散在七处）
///
/// ```css
/// .btn:active            { transform: scale(.96); }              /* 所有按钮 */
/// .cta:active .cta-core  { transform: scale(.92); }              /* 大蓝键的芯 */
/// .dk:active .ic         { transform: scale(.9); box-shadow: … } /* 底栏键的图标 */
/// #ask .presets button:active { background: rgba(56,225,255,.2); }
/// #plateAlt button:active { color: var(--ice); box-shadow: inset …; }
/// #choices .ch:active::after { transform: scaleX(1); }           /* 从左扫入 */
/// ```
///
/// ⚠️ 这些是**按下瞬间**的反馈，CSS 里**没有 transition**（除了 `.ch::after` 那条
///    `.35s --out`）—— 所以这里默认**不加时长**：一按下就到、一松手就回。
///    加 `AnimatedScale` 会变成"慢半拍"，跟原型的干脆手感不一样。
///
/// 两个组件：
/// - [PressScale]：按下时把 `child` 缩一下（`.btn` / `.cta-core` / `.dk .ic`）
/// - [PressBuilder]：把"按下中?"交给调用方，自己画（换底色 / 换描边 / 扫光）
/// ═══════════════════════════════════════════════════════════

/// 按下时缩放 [child]
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

  /// 按下时缩到多少（原型各处不同，默认取 `.btn` 的 .96）
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

/// 把「按下中?」交给调用方自己画（换底色、换描边、扫光都走它）
class PressBuilder extends StatefulWidget {
  const PressBuilder({
    super.key,
    required this.builder,
    this.onTap,
    this.behavior = HitTestBehavior.opaque,
  });

  /// `(context, 按下中?) → 界面`
  final Widget Function(BuildContext, bool) builder;

  final VoidCallback? onTap;
  final HitTestBehavior behavior;

  @override
  State<PressBuilder> createState() => _PressBuilderState();
}

class _PressBuilderState extends State<PressBuilder> {
  bool _down = false;

  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapUp: widget.onTap == null ? null : (_) => _set(false),
      onTapCancel: widget.onTap == null ? null : () => _set(false),
      onTap: widget.onTap,
      child: widget.builder(context, _down),
    );
  }
}
