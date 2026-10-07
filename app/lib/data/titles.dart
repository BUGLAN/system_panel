/// 称号 —— 真源：prototype/opus-v2-dir/js/content.js L244-257。
class HostTitle {
  const HostTitle(this.id, this.name, this.hint, {this.shame = false});

  final String id;
  final String name;

  /// 还没拿到时显示的提示：`？？？ · <hint>`
  final String hint;

  /// 耻辱称号（「不想要也得要」）—— 边框是红的，且摘不掉
  final bool shame;

  static const List<HostTitle> all = <HostTitle>[
    HostTitle('bind', '新绑定的', '绑定系统'),
    HostTitle('first', '第一滴汗', '完成第一单'),
    HostTitle('crit', '被暴击眷顾', '触发一次暴击'),
    HostTitle('done5', '不算太废', '累计完成 5 单'),
    HostTitle('redeem', '回头是岸', '完成一次补救'),
    HostTitle('streak3', '三日不断', '连击 3 天'),
    HostTitle('rankA', 'A 级经手人', '完成一张 A 级'),
    HostTitle('done15', '惯犯', '累计完成 15 单'),
    HostTitle('streak7', '七日不断', '连击 7 天'),
    HostTitle('rankS', 'S 级幸存者', '完成一张 S 级'),
    HostTitle('mouth', '口头巨人', '退缩 3 次（不想要也得要）', shame: true),
    HostTitle('finale', '主线终结者', '走完一整条主线'),
  ];

  static final Map<String, HostTitle> byId = <String, HostTitle>{
    for (final HostTitle t in all) t.id: t,
  };

  static String nameOf(String id) => byId[id]?.name ?? id;
}
