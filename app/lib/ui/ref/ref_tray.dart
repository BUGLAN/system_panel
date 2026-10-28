import 'package:flutter/material.dart';

import '../../data/items.dart';
import '../../design/ref.dart';
import 'ref_kit.dart' show refPressSound;
import 'ref_motion.dart';
import 'ref_svg.dart';

/// ═══════════════════════════════════════════════════════════
///  道具托盘 —— 参考稿 .tray / .icard（CSS L312-329 + L515，JS renderTray L1445-1456）
///
///  执行页动作区之上的 270 高托盘：背后一层自下而上的暗幕，左上
///  「LOADOUT · 选择装载道具」，三张 132×196 小卡扇形排开：
///    tx = (i−1)·118，rot = (i−1)·9°，ty = |i−1|·16；
///    收起时 translate(tx, 460) 且透明；已装载那张抬 24 并转正。
///  过渡 .55s ease（opacity .3s）。只放执行类道具（补签券不进托盘）。
/// ═══════════════════════════════════════════════════════════
class RefItemTray extends StatefulWidget {
  const RefItemTray({
    super.key,
    required this.items,
    required this.owned,
    required this.open,
    this.equipped = const <String>{},
    this.onPick,
    this.onClose,
    this.onEmpty,
    this.bottomInset = 150,
    this.embedded = false,
  });

  /// 嵌在执行页正文区底部（底边贴动作区、左右出血 22）
  final bool embedded;

  final List<Item> items;
  final Map<String, int> owned;
  final bool open;

  /// 本单已装载的道具 id
  final Set<String> equipped;
  final ValueChanged<String>? onPick;

  /// 点暗幕收起（JS `.tback` onclick）
  final VoidCallback? onClose;

  /// 点了持有 ×0 的卡（JS：error + 抖 + toast）
  final ValueChanged<Item>? onEmpty;
  final double bottomInset;

  @override
  State<RefItemTray> createState() => _RefItemTrayState();
}

class _RefItemTrayState extends State<RefItemTray> {
  final Map<String, int> _shake = <String, int>{};

  @override
  Widget build(BuildContext context) {
    final List<Item> show = <Item>[
      for (final Item it in widget.items)
        if (it.use == 'exec') it,
    ];
    final bool open = widget.open;
    final double bottom = widget.embedded
        ? 0
        : MediaQuery.paddingOf(context).bottom + widget.bottomInset;
    return Positioned(
      left: widget.embedded ? -Ref.gutter : 0,
      right: widget.embedded ? -Ref.gutter : 0,
      bottom: bottom,
      height: 270,
      child: IgnorePointer(
        ignoring: !open,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            // .tback：inset -400 0 -200，transparent → rgba(6,5,12,.92) 45%
            Positioned(
              left: 0,
              right: 0,
              top: -400,
              bottom: -200,
              child: GestureDetector(
                onTap: () {
                  refPressSound('ui.close');
                  widget.onClose?.call();
                },
                child: AnimatedOpacity(
                  opacity: open ? 1 : 0,
                  duration: const Duration(milliseconds: 350),
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
                opacity: open ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                child: Text(
                  'LOADOUT · 选择装载道具',
                  style: refText(
                    family: Ref.fm,
                    size: 11,
                    wght: 700,
                    ls: 4,
                    height: 1.2,
                    color: Ref.hot,
                  ),
                ),
              ),
            ),
            for (int i = 0; i < show.length; i++) _card(show[i], i, open),
          ],
        ),
      ),
    );
  }

  Widget _card(Item it, int i, bool open) {
    final int d = i - 1;
    final bool eq = widget.equipped.contains(it.id);
    final int own = widget.owned[it.id] ?? 0;
    final Color gc = Color(it.color);
    final double tx = d * 118.0;
    final double rot = eq ? 0 : d * 9.0;
    final double ty = open ? (d.abs() * 16.0 - (eq ? 24 : 0)) : 460;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Center(
        child: AnimatedOpacity(
          opacity: open ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: TweenAnimationBuilder<Offset>(
            tween: Tween<Offset>(end: Offset(tx, ty)),
            duration: const Duration(milliseconds: 550),
            curve: Ref.ease,
            builder: (BuildContext _, Offset o, Widget? c) =>
                Transform.translate(offset: o, child: c),
            child: AnimatedRotation(
              turns: rot / 360,
              duration: const Duration(milliseconds: 550),
              curve: Ref.ease,
              child: RefShakeX(
                token: _shake[it.id] ?? 0,
                child: GestureDetector(
                  onTap: () {
                    if (eq) return;
                    if (own <= 0) {
                      setState(() => _shake[it.id] = (_shake[it.id] ?? 0) + 1);
                      widget.onEmpty?.call(it);
                      return;
                    }
                    widget.onPick?.call(it.id);
                  },
                  child: _face(it, gc, eq, own),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// .icard：132×196 / r18 / p12 / 160° #241d3c→#0e0c19 / 1.5 gc45%
  Widget _face(Item it, Color gc, bool eq, int own) {
    final String first = '${it.desc.split('。').first}。';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 132,
      height: 196,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment(-.36, -1),
          end: Alignment(.36, 1),
          colors: <Color>[Color(0xFF241D3C), Color(0xFF0E0C19)],
        ),
        border: Border.all(color: eq ? Ref.acid : Ref.a(gc, .45), width: 1.5),
        boxShadow: <BoxShadow>[
          if (eq) BoxShadow(color: Ref.a(Ref.acid, .45), blurRadius: 30),
          const BoxShadow(
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
                it.code,
                style: refText(
                  family: Ref.fm,
                  size: 9,
                  wght: 700,
                  ls: 2,
                  height: 1.2,
                  color: gc,
                ),
              ),
              const Spacer(),
              Text(
                '×$own',
                style: refText(
                  family: Ref.fm,
                  size: 9,
                  wght: 700,
                  ls: 2,
                  height: 1.2,
                  color: Ref.dim,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Center(
            child: Container(
              width: 52,
              height: 52,
              margin: const EdgeInsets.only(top: 8, bottom: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: gc, width: 2),
                boxShadow: <BoxShadow>[
                  BoxShadow(color: Ref.a(gc, .5), blurRadius: 16),
                ],
                color: const Color(0xFF17132A),
              ),
              alignment: Alignment.center,
              child: RefSvgIcon(paths: RefIcons.of(it.id), color: gc, size: 24),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            it.name,
            textAlign: TextAlign.center,
            style: refText(size: 15, wght: 900, height: 1.3, color: Ref.txt),
          ),
          const SizedBox(height: 6),
          Text(
            first,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: refText(size: 11, wght: 400, height: 1.4, color: Ref.dim),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: eq ? Ref.acid : const Color(0x0FFFFFFF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              eq ? '✓ 已装载' : (own > 0 ? '点击装载' : '持有 ×0'),
              textAlign: TextAlign.center,
              style: refText(
                size: 11,
                wght: 700,
                height: 1.3,
                color: eq ? Ref.onAccent : Ref.dim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
