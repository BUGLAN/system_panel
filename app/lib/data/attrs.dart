/// 六维 —— 真源：prototype/opus-v2-dir/js/content.js L8-11（v4 换血后的力/敏/体/智/知/魅）。
class Attr {
  const Attr(this.k, this.name);

  /// 单字键（存档里的 key）
  final String k;

  /// 全名（界面上显示的那个）
  final String name;

  static const List<Attr> all = <Attr>[
    Attr('力', '力量'),
    Attr('敏', '敏捷'),
    Attr('体', '体质'),
    Attr('智', '智力'),
    Attr('知', '感知'),
    Attr('魅', '魅力'),
  ];

  /// k → 全名（`ATTR_NAME`）
  static final Map<String, String> names = <String, String>{
    for (final Attr a in all) a.k: a.name,
  };

  /// 把单字键翻成全名；认不出就原样返回
  static String nameOf(String k) => names[k] ?? k;
}
