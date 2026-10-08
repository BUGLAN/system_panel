import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// 一个可选回答（原型 `choose([{t, v, main}])`）
class Choice {
  const Choice(this.label, {this.main = false});

  final String label;

  /// 主选项＝青色实心那颗
  final bool main;
}

/// ═══════════════════════════════════════════════════════════
///  回应（app.css L181-193 `#choices`）
///  她说一句，宿主从下面挑一个——不做聊天界面，只做按钮。
///  实测盒模型（390×844）：choices [20,701,350,109] · 两颗各 [20,701,350,50] / [20,760,350,50]
/// ═══════════════════════════════════════════════════════════
class Choices extends StatelessWidget {
  const Choices({
    super.key,
    required this.items,
    this.visible = true,
    this.onPick,
  });

  final List<Choice> items;
  final bool visible;
  final ValueChanged<int>? onPick;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 20,
      right: 20,
      bottom: 34,
      // 收起来时必须同时断掉命中：否则一颗看不见的按钮会替下面的东西挨点
      // （本仓库真踩过：派单板的指纹被隐形的回应按钮吃掉）
      child: IgnorePointer(
        ignoring: !visible,
        child: Column(
          key: const Key('choices'),
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < items.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: 9), // #choices gap
              _Ch(
                key: Key('choices.$i'),
                choice: items[i],
                visible: visible,
                onTap: onPick == null ? null : () => onPick!(i),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// `#choices .ch`
class _Ch extends StatefulWidget {
  const _Ch({
    super.key,
    required this.choice,
    required this.visible,
    this.onTap,
  });

  final Choice choice;
  final bool visible;
  final VoidCallback? onTap;

  @override
  State<_Ch> createState() => _ChState();
}

class _ChState extends State<_Ch> {
  /// `#choices .ch:active::after { transform: scaleX(1) }`
  /// —— 按下时那层渐变**从左扫过来**（`.35s var(--out)`），松手扫回去
  bool _down = false;

  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final Choice choice = widget.choice;
    final bool visible = widget.visible;
    final VoidCallback? onTap = widget.onTap;
    final bool main = choice.main;
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 300),
      child: AnimatedSlide(
        offset: visible
            ? Offset.zero
            : const Offset(0, .28), // translateY(14px)
        duration: const Duration(milliseconds: 500),
        curve: kOut,
        child: GestureDetector(
          onTap: onTap,
          onTapDown: onTap == null ? null : (_) => _set(true),
          onTapUp: onTap == null ? null : (_) => _set(false),
          onTapCancel: onTap == null ? null : () => _set(false),
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: <Widget>[
              // `.ch::after` —— `linear-gradient(90deg, rgba(56,225,255,.25), rgba(56,225,255,.05))`
              // 原型里它盖住「宿主」小牌、但被 `.ch span`（z-index:1）压住；
              // 这里放在内容之下，差别只在按下那一瞬间，可以接受。
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: _down ? 1 : 0),
                  duration: const Duration(milliseconds: 350),
                  curve: kOut,
                  builder: (BuildContext _, double k, Widget? _) => Transform(
                    alignment: Alignment.centerLeft,
                    transform: Matrix4.diagonal3Values(k, 1, 1),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        gradient: const LinearGradient(
                          colors: <Color>[Color(0x4038E1FF), Color(0x0D38E1FF)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                constraints: const BoxConstraints(minHeight: 50),
                // Border 占布局、CSS 的 inset 阴影不占 → padding 各减 1px
                padding: const EdgeInsets.symmetric(
                  horizontal: 17,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: main
                      ? C.blue
                      : const Color(0xBD050E20), // rgba(5,14,32,.74)
                  borderRadius: BorderRadius.circular(26),
                  border: main
                      ? null
                      : Border.all(
                          color: const Color(0x4D38E1FF),
                          width: 1,
                        ), // rgba(56,225,255,.3)
                  boxShadow: main
                      ? <BoxShadow>[
                          BoxShadow(
                            color: C.blue.withAlpha(89),
                            blurRadius: 26,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: <Widget>[
                    // .ch::before —— 「宿主」小牌
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: main
                            ? const Color(0x24021022)
                            : C.blue.withAlpha(20),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '宿主',
                        style: fs(
                          family: F.mono,
                          size: 9,
                          wght: 600,
                          ls: 1.26,
                          height: 1,
                          color: main ? const Color(0x99021022) : C.mist,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        choice.label,
                        style: fs(
                          family: F.cn,
                          size: 15.5,
                          wght: main ? 650 : 400,
                          ls: .31,
                          color: main ? C.deep : C.ice,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
