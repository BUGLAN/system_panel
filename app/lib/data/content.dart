/// ═══════════════════════════════════════════════════════════
///  文案真源：prototype/opus-v2-dir/js/content.js
///  只放"系统说的话"和固定读数文案；游戏数值/规则另开文件。
/// ═══════════════════════════════════════════════════════════
class LINES {
  const LINES._();

  /// 开机 TIPS（content.js L403）
  static const List<String> tips = <String>[
    '系统不会等你。但会记得你让她等了多久。',
    '证据越多，暴击率越高。她信你，暴击不信。',
    '认输不丢人。丢人的是不敢接。',
    '退缩三次会解锁一个称号。你不会想要的。',
    '连击断了也没关系。她会从 1 重新数。',
    '她的单不会过期。只会在她手里越攥越紧。',
  ];

  /// 开机日志（content.js L411）；[3] 是模板，host 由存档决定
  static const List<String> bootLog = <String>[
    '挂载人格模块 …… 毒舌 ✓',
    '挂载人格模块 …… 靠谱 ✓',
    '校准良心 …… 未找到，跳过',
    '链接宿主档案 …… {host}',
    '唤醒序列就绪',
  ];

  /// 开机屏品牌字
  static const String bootTopLeft = 'SYS//BOOT · v2';
  static const String bootSub = '宿 主 · 系 统';
  static const String bootGo = '触碰屏幕 · 唤醒系统';

  /// 无存档时的 host 占位（flows.js L52）
  static const String hostUnknown = '未找到 · 新宿主';
}
