/// 道具（金币唯一去处）—— 真源：prototype/opus-v2-dir/js/content.js L261-266。
class Item {
  const Item({
    required this.id,
    required this.name,
    required this.glyph,
    required this.price,
    required this.desc,
    required this.use,
  });

  final String id;
  final String name;

  /// 那个字符字形（原型直接写在界面上的）
  final String glyph;
  final int price;
  final String desc;

  /// 在哪一步用：exec / dispatch
  final String use;

  static const List<Item> all = <Item>[
    Item(
      id: 'dbl',
      name: '双倍卡',
      glyph: '×2',
      price: 60,
      desc: '本单经验翻倍。和暴击叠，就是四倍。',
      use: 'exec',
    ),
    Item(
      id: 'crit',
      name: '暴击芯片',
      glyph: '✦',
      price: 45,
      desc: '本单暴击率 +25%。',
      use: 'exec',
    ),
    Item(
      id: 'shield',
      name: '免死金牌',
      glyph: '◆',
      price: 90,
      desc: '本单失败不计连败。嘴，她照骂。',
      use: 'exec',
    ),
    Item(
      id: 'swap',
      name: '换单券',
      glyph: '⇄',
      price: 30,
      desc: '派单时换一张同级的，不算退缩。',
      use: 'dispatch',
    ),
  ];

  static Item? byId(String id) {
    for (final Item it in all) {
      if (it.id == id) return it;
    }
    return null;
  }
}
