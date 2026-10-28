/// 道具（金币唯一去处）—— 真源：prototype/opus-v2-dir/js/content.js L261-266。
class Item {
  const Item({
    required this.id,
    required this.name,
    required this.glyph,
    required this.price,
    required this.desc,
    required this.use,
    required this.code,
    required this.color,
    this.lv = 0,
  });

  final String id;
  final String name;

  final String glyph;
  final int price;
  final String desc;

  /// exec = 执行中装载；shop = 补给站里直接使用
  final String use;

  /// 牌面编号（参考稿 `ITEMS[].code`）
  final String code;

  /// 档位色（参考稿 `ITEMS[].gc`）
  final int color;

  /// 购买所需等级（0 = 不限；参考稿护盾 lv:2）
  final int lv;

  /// 参考稿 `ITEMS`（JS L1040-1045）：顺序、名字、文案、价格、颜色一字不改。
  static const List<Item> all = <Item>[
    Item(
      id: 'crit',
      name: '暴击芯片',
      glyph: '✦',
      price: 45,
      desc: '本单暴击率 +25%。暴击时奖励 ×1.5，属性额外 +1。',
      use: 'exec',
      code: 'CRIT',
      color: 0xFFFF3B7A,
    ),
    Item(
      id: 'dbl',
      name: '双倍卡',
      glyph: '×2',
      price: 60,
      desc: '本单 EXP 与晶核 ×2。贪心是第一生产力。',
      use: 'exec',
      code: 'DBL',
      color: 0xFFFFCC4D,
    ),
    Item(
      id: 'shield',
      name: '护盾',
      glyph: '◆',
      price: 90,
      desc: '认输时连胜不中断。失败，也要失败得体面。',
      use: 'exec',
      code: 'SHIELD',
      color: 0xFF3BE8FF,
      lv: 2,
    ),
    Item(
      id: 'patch',
      name: '补签券',
      glyph: '✓',
      price: 30,
      desc: '补回一天断签，连胜 +1。这叫补救，不叫作弊。',
      use: 'shop',
      code: 'PATCH',
      color: 0xFF3DFFA8,
    ),
  ];

  static Item? byId(String id) {
    for (final Item it in all) {
      if (it.id == id) return it;
    }
    return null;
  }

  /// 执行期可用的那三样，**顺序照原型写死**
  /// （`ui.js` L433 的 `['dbl','crit','shield']`，标签与抽屉都按它排）
  static const List<String> execIds = <String>['dbl', 'crit', 'shield'];

  /// 执行类道具的持有总数（原型 `Exec.slots()` 末尾的 `#exItemN`）
  ///
  /// ```js
  /// const n = Object.keys(ITEMS).filter(k => ITEMS[k].use === 'exec')
  ///   .reduce((s, k) => s + Store.S.items[k], 0);
  /// $('#exItemN').textContent = n || '';
  /// ```
  static int execCount(Map<String, int> items) {
    int n = 0;
    for (final Item it in all) {
      if (it.use == 'exec') n += items[it.id] ?? 0;
    }
    return n;
  }
}
