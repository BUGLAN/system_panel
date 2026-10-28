import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/ref.dart';
import 'ref_kit.dart' show cutCornerPath, refPressSound;

/// .tabs（L238-241）：容器 r14 / padding 4 / rgba(255,255,255,.04) / 1px line；
/// 按钮高 36 / 14px 700；滑块发 --gold + 0 0 18px 50%，
/// transform .4s + width .4s 都是 var(--ease)。
class RefTabs extends StatelessWidget {
  const RefTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.accent,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final Color gold = accent ?? Ref.gold;
    return Container(
      height: 44, // 36 + padding 4x2
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Ref.line),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final double seg = c.maxWidth / math.max(1, labels.length);
          return Stack(
            children: <Widget>[
              AnimatedPositioned(
                duration: const Duration(milliseconds: 400),
                curve: Ref.ease,
                left: seg * index,
                top: 0,
                bottom: 0,
                width: seg,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: gold,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: <BoxShadow>[
                      BoxShadow(color: Ref.a(gold, .5), blurRadius: 18),
                    ],
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  for (int i = 0; i < labels.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          // 参考稿 tabs：按下 click + 换页 soft（L1386）
                          refPressSound('ui.tap');
                          if (i != index) refPressSound('ui.soft');
                          onChanged(i);
                        },
                        child: Center(
                          child: Text(
                            labels[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: refText(
                              family: Ref.fc,
                              size: 14,
                              wght: 700,
                              height: 1,
                              color: i == index ? Ref.onAccent : Ref.dim,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// .tbar（L278-283）：高 8 / r4 / 轨道 rgba(255,255,255,.07)；
/// 填充 linear-gradient(90deg, hot, gold, acid) + 14px 辉光；
/// 右端一枚 12x12 白点（0 0 12px #fff, 0 0 24px acid）；
/// .ticks 是 5 根 2x14 的白 .18 竖线，上探 3px。
class RefProgressBar extends StatelessWidget {
  const RefProgressBar({
    super.key,
    required this.value,
    this.ticks = 5,
    this.showKnob = true,
    this.height = 8,
    this.accent,
  });

  final double value;
  final int ticks;
  final bool showKnob;
  final double height;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final double v = value.clamp(0.0, 1.0);
    final Color a = accent ?? Ref.acid;
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final double w = c.maxWidth;
          final double filled = math.max(height, w * v);
          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0x12FFFFFF),
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
              ),
              if (v > 0)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.linear, // 参考稿 .fill 是 .3s linear
                  width: filled,
                  height: height,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: <Color>[Ref.hot, Ref.gold, Ref.acid],
                    ),
                    borderRadius: BorderRadius.circular(height / 2),
                    boxShadow: <BoxShadow>[
                      BoxShadow(color: Ref.a(a, .7), blurRadius: 14),
                    ],
                  ),
                ),
              if (showKnob && v > 0)
                Positioned(
                  left: filled - 6,
                  top: -(12 - height) / 2,
                  child: IgnorePointer(
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: <BoxShadow>[
                          const BoxShadow(color: Colors.white, blurRadius: 12),
                          BoxShadow(color: a, blurRadius: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              if (ticks > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        for (int i = 0; i < ticks; i++)
                          Container(
                            width: 2,
                            height: 14,
                            transform: Matrix4.translationValues(0, -3, 0),
                            color: const Color(0x2EFFFFFF),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// .evi-slot（L293-301）：82x82 / r14 / 蚂蚁线四边（12px 实 2px）；
/// .has 时 0 0 0 2px acid + 一条 3px 激光上下扫描（1.6s ease-in-out）。
class RefEvidenceSlot extends StatefulWidget {
  const RefEvidenceSlot({
    super.key,
    this.onTap,
    this.image,
    this.badge,
    this.size = 82,
    this.placeholder,
  });

  final VoidCallback? onTap;
  final Widget? image;
  final Widget? badge;
  final double size;

  /// 空槽里的内容（默认是 +）
  final Widget? placeholder;

  @override
  State<RefEvidenceSlot> createState() => _RefEvidenceSlotState();
}

class _RefEvidenceSlotState extends State<RefEvidenceSlot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLaser();
  }

  /// ⚠️ 也要在 didUpdateWidget 里同步：槽位是「先空后有图」的，只在
  ///    didChangeDependencies 里起播的话，放进图之后激光扫描根本不会动。
  @override
  void didUpdateWidget(RefEvidenceSlot old) {
    super.didUpdateWidget(old);
    if ((old.image != null) != (widget.image != null)) _syncLaser();
  }

  void _syncLaser() {
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final bool has = widget.image != null;
    if (has && !reduce) {
      if (!_c.isAnimating) _c.repeat();
    } else if (_c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool has = widget.image != null;
    final double s = widget.size;
    return Semantics(
      button: widget.onTap != null,
      label: has ? '证据已上传' : '上传证据',
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: s,
          height: s,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: has ? Colors.black : const Color(0x0D3BE8FF),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: has
                        ? <BoxShadow>[
                            BoxShadow(
                              color: Ref.a(Ref.acid, .4),
                              blurRadius: 20,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
              if (!has)
                Positioned.fill(child: CustomPaint(painter: _AntsPainter())),
              if (has)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: widget.image,
                  ),
                ),
              if (!has)
                Center(
                  child:
                      widget.placeholder ??
                      Text(
                        '+',
                        style: refText(
                          family: Ref.fd,
                          size: 34,
                          wght: 300,
                          height: 1,
                          color: Ref.cyan,
                        ),
                      ),
                ),
              if (has)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedBuilder(
                      animation: _c,
                      builder: (BuildContext _, Widget? _) {
                        // @keyframes laser { 0%,100% { top:0 } 50% { top:100% - 3px } }
                        final double t = _c.value;
                        final double k = t < .5 ? t * 2 : (1 - t) * 2;
                        return Align(
                          alignment: Alignment(0, k * 2 - 1),
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: Ref.acid,
                              boxShadow: <BoxShadow>[
                                BoxShadow(color: Ref.acid, blurRadius: 12),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              if (has)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Ref.acid, width: 2),
                      ),
                    ),
                  ),
                ),
              if (widget.badge != null)
                Positioned(right: 4, bottom: 4, child: widget.badge!),
            ],
          ),
        ),
      ),
    );
  }
}

/// 蚂蚁线：四边 2px 青框（参考稿用四组 repeating-linear-gradient 实现 12/12 虚线）
class _AntsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final RRect r = RRect.fromRectAndRadius(
      Offset.zero & s,
      const Radius.circular(14),
    ).deflate(1);
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Ref.cyan;
    const double dash = 12;
    // 四边各画 12 实 12 空
    for (final (Offset a, Offset b) in <(Offset, Offset)>[
      (Offset(r.left, r.top), Offset(r.right, r.top)),
      (Offset(r.left, r.bottom), Offset(r.right, r.bottom)),
      (Offset(r.left, r.top), Offset(r.left, r.bottom)),
      (Offset(r.right, r.top), Offset(r.right, r.bottom)),
    ]) {
      final double len = (b - a).distance;
      final Offset dir = (b - a) / len;
      for (double t = 0; t < len; t += dash * 2) {
        final double end = math.min(len, t + dash);
        canvas.drawLine(a + dir * t, a + dir * end, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// .sw（L488-490）：52x30 / r15 / rgba(255,255,255,.12)；
/// 开 = acid 底 + 滑铲右移 22；滑铲 24 圆，background .25s / transform .3s
class RefSwitch extends StatelessWidget {
  const RefSwitch({
    super.key,
    required this.on,
    this.onChanged,
    this.enabled = true,
  });

  final bool on;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: on,
      child: GestureDetector(
        onTap: enabled && onChanged != null
            ? () {
                refPressSound('ui.tap');
                onChanged!(!on);
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 52,
          height: 30,
          decoration: BoxDecoration(
            color: on ? Ref.acid : const Color(0x1FFFFFFF),
            borderRadius: BorderRadius.circular(15),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 300),
            curve: Ref.ease,
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? Ref.onAccent : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 参考稿没有输入控件；按它的语言补一枚：--ink 底 + 1px line、
/// 聚焦转 accent、圆角 10、高 46。
class RefTextField extends StatefulWidget {
  const RefTextField({
    super.key,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.accent,
    this.onChanged,
    this.keyboardType,
    this.height = 46,
    this.textSize = 14,
    this.mono = false,
    this.focusNode,
    this.onSubmitted,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final Color? accent;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final double height;
  final double textSize;
  final bool mono;

  /// 外部焦点（调用方要主动弹键盘时给；不给就自建一颗）
  final FocusNode? focusNode;

  /// 键盘「完成」键（给了就把回车键标成 done）
  final ValueChanged<String>? onSubmitted;

  /// false = 只读（加载中锁输入，边框压暗）
  final bool enabled;

  @override
  State<RefTextField> createState() => _RefTextFieldState();
}

class _RefTextFieldState extends State<RefTextField> {
  FocusNode? _own;
  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode());
  bool _hidden = true;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(RefTextField old) {
    super.didUpdateWidget(old);
    final FocusNode prev = old.focusNode ?? _own!;
    if (prev != _focus) {
      prev.removeListener(_onFocus);
      _focus.addListener(_onFocus);
    }
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = widget.accent ?? Ref.acid;
    return Container(
      height: widget.height,
      padding: EdgeInsets.only(left: 12, right: widget.obscure ? 4 : 12),
      decoration: BoxDecoration(
        color: Ref.ink,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _focus.hasFocus && widget.enabled ? accent : Ref.line,
        ),
        boxShadow: _focus.hasFocus
            ? <BoxShadow>[BoxShadow(color: Ref.a(accent, .22), blurRadius: 14)]
            : null,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              obscureText: widget.obscure && _hidden,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              textInputAction: widget.onSubmitted == null
                  ? null
                  : TextInputAction.done,
              enabled: widget.enabled,
              keyboardType: widget.keyboardType,
              cursorColor: accent,
              cursorWidth: 2,
              style: refText(
                family: widget.mono ? Ref.fm : Ref.fc,
                size: widget.textSize,
                wght: widget.mono ? 500 : 400,
                height: 1.2,
                color: Ref.txt,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: refText(
                  family: widget.mono ? Ref.fm : Ref.fc,
                  size: widget.textSize,
                  wght: 400,
                  height: 1.2,
                  color: Ref.dim2,
                ),
              ),
            ),
          ),
          if (widget.obscure)
            GestureDetector(
              onTap: () => setState(() => _hidden = !_hidden),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 34,
                height: 34,
                child: CustomPaint(
                  painter: _EyePainter(open: !_hidden, color: accent),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EyePainter extends CustomPainter {
  const _EyePainter({required this.open, required this.color});
  final bool open;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final Offset c = Offset(s.width / 2, s.height / 2);
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Ref.mix(color, Ref.dim, open ? 0 : .55);
    final Path eye = Path()
      ..moveTo(c.dx - 9, c.dy)
      ..quadraticBezierTo(c.dx, c.dy - 7, c.dx + 9, c.dy)
      ..quadraticBezierTo(c.dx, c.dy + 7, c.dx - 9, c.dy);
    canvas.drawPath(eye, p);
    canvas.drawCircle(c, 2.6, Paint()..color = p.color);
    if (!open) {
      canvas.drawLine(
        Offset(c.dx - 9, c.dy + 6),
        Offset(c.dx + 9, c.dy - 6),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_EyePainter o) => o.open != open || o.color != color;
}

/// .sec-h（L343-345）：500 14px + 后方拉满的细线 + 右侧读数
class RefSectionHeader extends StatelessWidget {
  const RefSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.accent,
    this.padding,
  });

  final String title;
  final String? trailing;
  final Color? accent;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.only(top: 22, bottom: 12),
      // ⚠️ 标题必须可收缩：参考稿是 Chakra/Noto 下的定宽文本，但字体没
      //    加载时（离屏出图 / 裸 test）回退到更宽的字体，实测把「名牒册 ·
      //    点击佩戴」挤出 98px。分隔线反而应该让位，所以标题用 Flexible。
      child: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: refText(
                family: Ref.fc,
                size: 14,
                wght: 500,
                height: 1,
                color: Ref.dim,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Divider(height: 1, thickness: 1, color: Ref.line),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 10),
            Text(
              trailing!,
              style: refText(
                family: Ref.fd,
                size: 14,
                wght: 700,
                height: 1,
                color: accent ?? Ref.violet,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// .eyebrow（L60-61）：500 11px / 字距 4 / 前置 14x2 横线 + 8px 辉光
class RefEyebrow extends StatelessWidget {
  const RefEyebrow({super.key, required this.text, this.accent});

  final String text;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final Color a = accent ?? Ref.acid;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 14,
          height: 2,
          decoration: BoxDecoration(
            color: a,
            boxShadow: <BoxShadow>[BoxShadow(color: a, blurRadius: 8)],
          ),
        ),
        const SizedBox(width: 8),
        // ⚠️ 必须可收缩：11px + 字距 4 的英文眉在真字体下放得下，但**字体没
        //    加载时**（离屏出图 / 裸 test）会回退到更宽的系统字体，实测
        //    「ARCHIVE · 宿主档案」挤出 98px。眉文本允许省略，横线不动。
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: refText(
              family: Ref.fm,
              size: 11,
              wght: 500,
              ls: 4,
              height: 1,
              color: a,
            ),
          ),
        ),
      ],
    );
  }
}

/// 斜切卡壳（参考稿 .quest r20 / .ticket 左圆角 / 面板 r22 都靠圆角，
/// 只有按钮用斜切）—— 这里提供一枚「斜切 + 圆角」组合路径，给徽记类用。
Path tagPath(Rect r, double cut) => cutCornerPath(r, cut);
