import 'package:flutter/material.dart';

import '../data/items.dart';
import '../design/tokens.dart';
import 'card_table.dart';

/// ═══════════════════════════════════════════════════════════
///  道具抽屉（`ui.js` L430-448 `Exec.drawer()`）
///
///  ⚠️ **宿主 2026-10-11 的最终裁决：不要自己重写一套，直接搬补给页那一桌。**
///  原话：「道具卡 样式和动效 都没有啊，你为什么不直接搬过来，反而重写？」
///
///  所以这里**不再有 ItemRail / 自绘卡面**：抽屉里放的就是
///  [CardTable]（`skin: shelf` + `size: l`）—— 与补给页（`TableOverlay`）
///  **同一个组件、同一套皮肤、同一套入场/领位/落定动效**，一个参数都不改。
///  唯一差别只有内容：补给那桌写价格、这桌写持有数；道具是拿来用的，不挂价签。
///
///  三张牌（双倍卡 / 暴击芯片 / 免死金牌）来自 [Item.execIds]，与执行面板那颗
///  「道具」标签共用同一份清单，免得两处各写一份。
///
///  ⚠️ 开合动画用 `AnimatedOpacity` / `AnimatedSlide`，**不能用 `TweenAnimationBuilder`**：
///  执行面板的计时器每帧 rebuild，后者会把动画不断重置回起点（踩过，卡在 15% 不透明度）。
/// ═══════════════════════════════════════════════════════════
class ItemDrawer extends StatelessWidget {
  const ItemDrawer({
    super.key,
    required this.open,
    required this.counts,
    required this.used,
    required this.coins,
    this.onUse,
    this.onShop,
  });

  final bool open;

  /// 持有数（`Store.S.items`）
  final Map<String, int> counts;

  /// 本单已经挂上生效的（原型 `A[k]`）
  final Set<String> used;

  final int coins;

  /// 用某个道具（真正的数值变化属于业务规则，这里只上报）
  final ValueChanged<String>? onUse;

  /// 「去补给」—— 当前没有 UI 触发它（那颗小键已按宿主指定删除），
  /// 回调与签名保留，`main.dart` 的调用点无需改动。
  final VoidCallback? onShop;

  /// 抽屉里只列执行期可用的那三样（原型写死 `['dbl','crit','shield']`）
  static const List<String> execIds = Item.execIds;

  @override
  Widget build(BuildContext context) {
    final List<Item> items = <Item>[
      for (final String id in execIds)
        if (Item.byId(id) != null) Item.byId(id)!,
    ];
    return Positioned(
      left: 0,
      right: 0,
      // 与补给页（TableOverlay）同一档高度：牌桌浮在舞台下三分之一
      bottom: 104,
      child: IgnorePointer(
        ignoring: !open,
        child: AnimatedOpacity(
          opacity: open ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          curve: kOut,
          child: AnimatedSlide(
            offset: open ? Offset.zero : const Offset(0, .06),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            child: CardTable(
              key: const Key('exec.drawer'),
              skin: CardSkin.shelf, // 与补给页同一套卡面语言
              size: CardTableSize.l, // 同一档尺寸（208×292）
              // 领位落在第一件「手上有货」的牌上：一进来就有一张能直接落定
              initialLead: _firstUsable(items),
              cards: <TableCard>[
                for (final Item it in items)
                  TableCard(
                    id: it.id,
                    kicker: 'ITEM · ${it.id.toUpperCase()}',
                    title: it.name,
                    glyph: it.glyph,
                    rule: it.desc,
                    badge: used.contains(it.id)
                        ? '已生效'
                        : '持有 ×${counts[it.id] ?? 0}',
                    // 无货且没生效 → 不可用（点了不落定，她会解释一句）
                    enabled: (counts[it.id] ?? 0) > 0 || used.contains(it.id),
                    sealWord: '用',
                  ),
              ],
              onPick: (int i) => onUse?.call(items[i].id),
            ),
          ),
        ),
      ),
    );
  }

  /// 第一件「手上有货或已生效」的牌的下标；都没有就退回中位
  int _firstUsable(List<Item> items) {
    final int i = items.indexWhere(
      (Item it) => (counts[it.id] ?? 0) > 0 || used.contains(it.id),
    );
    return i >= 0 ? i : (items.length - 1) ~/ 2;
  }
}
