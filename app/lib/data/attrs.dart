/// 六维 —— **显示名与顺序**按设计稿 `宿主养成系统_重设计.html` L1009：
/// 体质 / 意志 / 智识 / 感知 / 魅力 / 灵巧（雷达图与档案页的六维条都读它）。
///
/// ⚠️ **存档 key 一个字都不改**（力/敏/体/智/知/魅）：它们已经写进老存档、
/// 结算的六维加成表与历史测试。这里只改 name 与 all 的**排列顺序**，
/// 于是「界面读起来是设计稿的六维、存档仍是原来那六个键」。
class Attr {
  const Attr(this.k, this.name);

  /// 单字键（存档里的 key）—— **不要改**
  final String k;

  /// 全名（界面上显示的那个）
  final String name;

  /// 设计稿顺序：体质 → 意志 → 智识 → 感知 → 魅力 → 灵巧
  static const List<Attr> all = <Attr>[
    Attr('力', '体质'),
    Attr('体', '意志'),
    Attr('智', '智识'),
    Attr('知', '感知'),
    Attr('魅', '魅力'),
    Attr('敏', '灵巧'),
  ];

  /// k → 全名（`ATTR_NAME`）
  static final Map<String, String> names = <String, String>{
    for (final Attr a in all) a.k: a.name,
  };

  /// 把单字键翻成全名；认不出就原样返回
  static String nameOf(String k) => names[k] ?? k;
}
