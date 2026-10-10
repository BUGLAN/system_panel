import 'package:flutter/material.dart';

import '../data/items.dart';
import '../design/tokens.dart';
import '../state/haptics.dart';
import '../state/sfx.dart';

/// ═══════════════════════════════════════════════════════════
///  道具抽屉（`ui.js` L430-448 `Exec.drawer()`）
///
///  ```js
///  d.innerHTML = ['dbl','crit','shield'].map(k => {
///    const it = ITEMS[k], used = A[k], n = S.items[k];
///    return `<button class="it${used ? ' used' : ''}" ${!n && !used ? 'disabled' : ''}>
///      <span class="glyph">${it.glyph}</span>
///      <span><b>${it.name}</b><small>${used ? '已生效' : '持有 ×' + n}</small></span></button>`;
///  }).join('') + `<button class="it" data-k="shop"><span class="glyph">◈</span>
///      <span><b>去补给</b><small>金币 ${S.coins}</small></span></button>`;
///  ```
///  再点一次「道具」就收起（`if (d.classList.contains('on')) { remove; return }`）。
///
///  `.drawer`: 两列网格 · `opacity .25s` + `transform .4s --spring`（上移 14px、缩到 .97）
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

  /// 「去补给」
  final VoidCallback? onShop;

  /// 抽屉里只列执行期可用的那三样（原型写死 `['dbl','crit','shield']`）
  /// 抽屉里只列执行期可用的那三样（原型写死 `['dbl','crit','shield']`）
  /// —— 与执行面板的标签共用 `Item.execIds`，免得两处各写一份
  static const List<String> execIds = Item.execIds;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[
      for (final String id in execIds) _row(id),
      _shopRow(),
    ];
    return Positioned(
      left: 14,
      right: 14,
      bottom: 148,
      child: IgnorePointer(
        ignoring: !open,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: open ? 1 : 0, end: open ? 1 : 0),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutBack, // 近似那条 --spring（有 1.12 的过冲）
          builder: (BuildContext _, double k, Widget? child) => Opacity(
            opacity: k.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, 14 * (1 - k)),
              child: Transform.scale(scale: .97 + .03 * k, child: child),
            ),
          ),
          child: Container(
            key: const Key('exec.drawer'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xF0040C1C), // rgba(4,12,28,.94)
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: C.line, width: 1),
              boxShadow: <BoxShadow>[
                const BoxShadow(
                  color: Color(0x99000000),
                  offset: Offset(0, 20),
                  blurRadius: 50,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < rows.length; i += 2) ...<Widget>[
                  if (i > 0) const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(child: rows[i]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: i + 1 < rows.length
                            ? rows[i + 1]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 一个道具格
  Widget _row(String id) {
    final Item? it = Item.byId(id);
    if (it == null) return const SizedBox.shrink();
    final int n = counts[id] ?? 0;
    final bool on = used.contains(id);
    final bool disabled = n <= 0 && !on;
    return _tile(
      key: Key('exec.drawer.$id'),
      glyph: it.glyph,
      title: it.name,
      sub: on ? '已生效' : '持有 ×$n',
      disabled: disabled,
      used: on,
      // 使用道具（`ui.js:444`）：原型只有"真的用上了"那一拍才响
      // —— `if (A[k]) return; if (Store.useItem(k)) { Sound.play('seal'); FX.flash(…); }`
      // 所以这里两个前置条件对齐原型：**本单没生效过**（`!A[k]`）且**手上有货**
      // （原型那颗 button 就是在 `!n && !used` 时 disabled）。「已生效」的格子点了
      // 依旧走原回调（行为一字不动），只是不再补响那一声。
      onTap: disabled
          ? null
          : () {
              if (!on && n > 0) {
                Sfx.play('seal');
                Haptics.buzz('seal');
              }
              onUse?.call(id);
            },
    );
  }

  /// 「去补给」
  Widget _shopRow() => _tile(
    key: const Key('exec.drawer.shop'),
    glyph: '◈',
    title: '去补给',
    sub: '金币 $coins',
    disabled: false,
    used: false,
    onTap: onShop,
  );

  Widget _tile({
    required Key key,
    required String glyph,
    required String title,
    required String sub,
    required bool disabled,
    required bool used,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Opacity(
        opacity: disabled ? .35 : 1, // `.it[disabled] { opacity: .35 }`
        child: Container(
          height: 56,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: used
                ? const Color(0x2438E1FF) // rgba(56,225,255,.14)
                : const Color(0x0D38E1FF), // rgba(56,225,255,.05)
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: used ? C.blue : C.line2, width: 1),
          ),
          child: Row(
            children: <Widget>[
              _glyph(glyph),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: fs(
                        family: F.cn,
                        size: 13,
                        wght: 400,
                        height: 1,
                        color: C.ice,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: fs(
                        family: F.mono,
                        size: 10,
                        wght: 500,
                        height: 1,
                        color: C.mist,
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

  /// `.glyph` —— 36px 圆环 + 内圈径向辉光 + 外发光
  Widget _glyph(String s) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: C.blue, width: 1.5),
        // CSS 是 radial-gradient(circle, rgba(...,.18), transparent 70%)：
        // 半径按 70% 收，所以用 0 → .18 → 0（stops .7）来贴合
        gradient: RadialGradient(
          colors: <Color>[C.blue.withAlpha(46), C.blue.withAlpha(0)],
          stops: const <double>[0, .7],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(color: C.blue.withAlpha(64), blurRadius: 12),
        ],
      ),
      child: Text(
        s,
        style: fs(family: F.num, size: 14, wght: 800, height: 1, color: C.blue),
      ),
    );
  }
}
