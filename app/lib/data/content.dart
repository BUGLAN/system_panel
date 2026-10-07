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

  // ── 她主动开口（content.js L306-356，flows.js L693-706 调度）──

  /// 大厅待机碎碎念；`{ring}` 是当前环号
  static const List<String> idle = <String>[
    '盯着我看能变强吗？不能。',
    '第 [[{ring}]] 环还亮着。它不会自己灭。',
    '我手里的单不会过期——你的耐心会。',
    '系统在待机。宿主也在待机。这不对吧。',
    '手指别在我身上画圈。我看得见。',
    '你知道吗，我每天都在等这个按钮被按下。',
  ];

  /// 深夜（23:00~05:00）与清晨（<10:00，40% 概率）的专属碎碎念
  static const String idleNight = '这个点还醒着？那就做点有用的，或者去睡。';
  static const String idleMorning = '早。今天给我争气点。';

  /// 执行中她隔一阵子冒一句
  static const List<String> exec = <String>[
    '还在？好。',
    '计时没停。你也别停。',
    '别看我，看任务。',
    '快照拍了吗？证据越多，暴击率越高。',
    '我不催。……算了，我催。',
  ];

  /// 剩不到 3 分钟时改成报剩余（`{t}` 由 fmtDur 填）
  static const String execNear = '还剩 [[{t}]]。';

  /// 走神时那一句
  static const String doze = '……（待机）';

  /// 无存档时的 host 占位（flows.js L52）
  static const String hostUnknown = '未找到 · 新宿主';
}
