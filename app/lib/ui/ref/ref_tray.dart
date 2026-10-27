import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/items.dart';
import '../../design/ref.dart';

/// ═══════════════════════════════════════════════════════════
///  道具托盘 —— 参考稿 .tray（CSS L312-329，DOM L760）
///
///  .tray：绝对定位在底部 safe + 150、高 270、z 6；
///  .tback 从 -400 到 -200 的暗场（45% 处 rgba(6,5,12,.92)）；
///  .tlabel 在 top -30 左侧 22，「LOADOUT · 选择装载道具」11px mono 字距 4 hot；
///  .icard：132×196、r18、160 度紫渐变、1.5px hot 边，
///  收起时 translate(tx, 300px) rotate(rot)，展开时到 ty；
///  .eq 再上浮 24 且边框转 acid。
/// ═══════════════════════════════════════════════════════════
class RefItemTray extends StatelessWidget {
  const RefItemTray({
    super.key,
    required this.items,
    required this.owned,
    required this.open,
    this.eqId,
    this.onPick,
    this.bottomInset = 150,
  });

  final List<Item> items;
  final Map<String, int> owned;
  final bool open;
  final String? eqId;
  final ValueChanged<String>? onPick;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final List<Item> show = <Item>[
      for (final Item it in items)
        if ((owned[it.id] ?? 0) > 0) it,
    ];
    if (show.isEmpty) return const SizedBox.shrink();
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: safe.bottom + bottomInset,
      height: 270,
      child: IgnorePointer(
        ignoring: !open,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              left: 0,
              right: 0,
              top: -400,
              bottom: -200,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 350),
                  opacity: open ? 1 : 0,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[Color(0x0006050C), Color(0xEB06050C)],
                        stops: <double>[0, .45],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 22,
              top: -30,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: open ? 1 : 0,
                child: Text(
                  'LOADOUT · 选择装载道具',
                  style: refText(
                    family: Ref.fm,
                    size: 11,
                    wght: 700,
                    ls: 4,
                    height: 1,
                    color: Ref.hot,
                  ),
                ),
              ),
            ),
            for (int i = 0; i < show.length; i++)
              _card(show[i], i, show.length),
          ],
        ),
      ),
    );
  }

  Widget _card(Item it, int i, int n) {
    final double t = n <= 1 ? 0 : (i / (n - 1)) - .5;
    final double tx = t * 200;
    final double rot = t * 16;
    final bool eq = eqId == it.id;
    final Widget card = Container(
      width: 132,
      height: 196,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF241D3C), Color(0xFF0E0C19)],
        ),
        border: Border.all(
          color: eq ? Ref.acid : Ref.a(Ref.hot, .45),
          width: 1.5,
        ),
        boxShadow: eq
            ? <BoxShadow>[
                BoxShadow(color: Ref.a(Ref.acid, .45), blurRadius: 30),
                const BoxShadow(
                  color: Color(0x99000000),
                  offset: Offset(0, 20),
                  blurRadius: 40,
                ),
              ]
            : const <BoxShadow>[
                BoxShadow(
                  color: Color(0x99000000),
                  offset: Offset(0, 20),
                  blurRadius: 40,
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'ITEM ${(i + 1).toString().padLeft(2, '0')}',
                style: refText(
                  family: Ref.fm,
                  size: 9,
                  wght: 700,
                  ls: 2,
                  height: 1,
                  color: Ref.hot,
                ),
              ),
              const Spacer(),
              Text(
                '×${owned[it.id] ?? 0}',
                style: refText(
                  family: Ref.fm,
                  size: 9,
                  wght: 700,
                  ls: 1,
                  height: 1,
                  color: Ref.dim,
                ),
              ),
            ],
          ),
          Container(
            width: 52,
            height: 52,
            margin: const EdgeInsets.only(top: 8, bottom: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Ref.hot, width: 2),
              boxShadow: <BoxShadow>[
                BoxShadow(color: Ref.a(Ref.hot, .5), blurRadius: 16),
              ],
            ),
            child: Text(
              it.glyph,
              style: refText(
                family: Ref.fc,
                size: 24,
                wght: 900,
                height: 1,
                color: Ref.hot,
              ),
            ),
          ),
          Text(
            it.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: refText(
              family: Ref.fc,
              size: 15,
              wght: 900,
              height: 1.2,
              color: Ref.txt,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            it.desc,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: refText(
              family: Ref.fc,
              size: 11,
              wght: 400,
              height: 1.4,
              color: Ref.dim,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: eq ? Ref.acid : const Color(0x0FFFFFFF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              eq ? '已装载' : '装载',
              style: refText(
                family: Ref.fc,
                size: 11,
                wght: 700,
                height: 1,
                color: eq ? Ref.onAccent : Ref.dim,
              ),
            ),
          ),
        ],
      ),
    );
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      // 参考稿 L515: .tray:not(.open) .icard{opacity:0; translateY(460px)}
      // 只挪 300 且不透明的话，卡片会从屏底露出小半张（真机截图确认）。
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        curve: Ref.ease,
        opacity: open ? 1 : 0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 550),
          curve: Ref.ease,
          transform: Matrix4.identity()
            ..translateByDouble(tx, open ? (eq ? -24.0 : 0.0) : 460.0, 0, 1)
            ..rotateZ((open ? rot : rot * 1.6) * math.pi / 180),
          child: GestureDetector(
            onTap: onPick == null ? null : () => onPick!(it.id),
            child: card,
          ),
        ),
      ),
    );
  }
}
