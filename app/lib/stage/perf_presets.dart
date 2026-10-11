import 'live2d_stage.dart';

/// ═══════════════════════════════════════════════════════════
///  预设 = **动作 × 表情** 的一个命名组合（宿主 2026-10-11 定义）。
///
///  · 资源边界：动作组 18 个（`sakiko.model3.json` 的 `Motions`）、
///    表情 32 个（`Expressions`）——都不能新增文件，只能组合。
///  · 本文是**命名表**：给"值得用的组合"取中文名，供
///    ① 调试页（`widgets/perf_debug.dart`）逐条试；
///    ② 文档 `docs/25-表情·动作·预设总表.md` 与代码对齐；
///    ③ 以后接新时刻时直接引用预设 id，不再散写字面量。
///  · 表格真源仍是 `StageBridges`（`verbFace`/`idlePool`/`emotionAct`）；
///    本表是它们的"命名视图"，`stage_port_test.dart` 会核对
///    **每个预设的动作组与表情都真实存在**、id 不重复。
/// ═══════════════════════════════════════════════════════════

/// 预设族（调试页分组 + 文档分节）
enum PerfFamily {
  present('亮相', 'PRESENT'),
  daily('日常', 'DAILY'),
  idle('待机', 'IDLE'),
  emotion('情绪', 'EMOTION'),
  settle('结算', 'SETTLE'),
  fail('失败', 'FAIL'),
  sleep('睡醒', 'SLEEP'),
  extra('备用', 'EXTRA');

  const PerfFamily(this.cn, this.mono);

  /// 中文族名（文档/调试页标题）
  final String cn;

  /// mono kicker（调试页右上小字）
  final String mono;
}

/// 一条命名预设
class PerfPreset {
  const PerfPreset(
    this.id,
    this.name,
    this.family,
    this.group,
    this.exp,
    this.usage, {
    this.priority = 2,
  });

  /// mono 标识（代码/文档引用用；全表唯一）
  final String id;

  /// 中文名（宿主一眼认得的名字）
  final String name;

  final PerfFamily family;

  /// 动作组（必须在 `Live2DStage.motionGroups` 里）
  final String group;

  /// 表情（必须在 `Live2DStage.expressions` 里；`''` = 不动表情）
  final String exp;

  /// 现在用在哪（空 = 备用，还没接时刻）
  final String usage;

  /// Cubism 优先级：1 待机 / 2 指令 / 3 强制
  final int priority;
}

/// 预设总表（改动要同步 `docs/25-表情·动作·预设总表.md`）
abstract class PerfPresets {
  const PerfPresets._();

  static const List<PerfPreset> all = <PerfPreset>[
    // ── 亮相 ──────────────────────────────────────────────────
    PerfPreset('present', '亮相', PerfFamily.present, 'kime', 'exp_kime01',
        '唤醒·发布任务·升级·结算好单'),
    PerfPreset('cheer', '欢呼', PerfFamily.present, 'kime', 'exp_kime01',
        '情绪 joy 的兜底动作'),
    PerfPreset(
        'finale', '收官定格', PerfFamily.present, 'kime', 'exp_bsmile02', '主线达成', priority: 3),

    // ── 日常 ──────────────────────────────────────────────────
    PerfPreset('nod_serious', '正色颔首', PerfFamily.daily, 'nod',
        'exp_serious02', '接单·换目标落库'),
    PerfPreset('nod_smile', '满意点头', PerfFamily.daily, 'nod', 'exp_smile01',
        '提交任务·待机(得意)'),
    PerfPreset('check_serious', '打量', PerfFamily.daily, 'check',
        'exp_serious01', '快照记录·待机(冷淡)'),
    PerfPreset('check_shy', '害羞躲闪', PerfFamily.daily, 'check', 'exp_shy01',
        '戳她第 1~3 下'),
    PerfPreset('think_serious', '沉思', PerfFamily.daily, 'thinking',
        'exp_serious02', '换目标·追问'),
    PerfPreset('look_away', '转头一瞥', PerfFamily.daily, 'look', 'exp_idle02',
        '离开回来'),
    PerfPreset('bye', '挥手告别', PerfFamily.daily, 'bye', 'exp_idle01', '(备用)'),

    // ── 待机（每 7~15s 一条；priority 1）──────────────────────
    PerfPreset('idle_look', '张望', PerfFamily.idle, 'look', 'exp_idle01',
        '待机(默认池)', priority: 1),
    PerfPreset('idle_check', '倦怠打量', PerfFamily.idle, 'check',
        'exp_idle02', '待机(默认/冷淡池)', priority: 1),
    PerfPreset('idle_think', '出神', PerfFamily.idle, 'thinking', 'exp_idle03',
        '待机(默认池)', priority: 1),
    PerfPreset('idle_smile', '微笑', PerfFamily.idle, 'smile', 'exp_smile01',
        '待机(默认池)', priority: 1),
    PerfPreset('idle_nod', '轻点一下头', PerfFamily.idle, 'nod', 'exp_idle01',
        '待机(默认池)', priority: 1),
    PerfPreset('idle_breath', '站立呼吸', PerfFamily.idle, 'idle',
        'exp_idle01', '待机(默认池)', priority: 1),
    PerfPreset('idle_serious', '正色站定', PerfFamily.idle, 'serious',
        'exp_serious01', '待机(冷淡池)', priority: 1),
    PerfPreset('idle_grim', '正色点头', PerfFamily.idle, 'nod', 'exp_serious02',
        '待机(冷淡池)', priority: 1),
    PerfPreset('idle_grin', '得意笑', PerfFamily.idle, 'smile', 'exp_smile02',
        '待机(得意池)', priority: 1),
    PerfPreset('idle_pose', '得意定格', PerfFamily.idle, 'kime', 'exp_kime01',
        '待机(得意池)', priority: 1),
    PerfPreset('idle_content', '含笑侧目', PerfFamily.idle, 'look',
        'exp_smile01', '待机(得意池)', priority: 1),
    PerfPreset('idle_smug', '得意站定', PerfFamily.idle, 'idle', 'exp_bsmile01',
        '待机(得意池)', priority: 1),

    // ── 情绪 ──────────────────────────────────────────────────
    PerfPreset('smile_soft', '抿嘴笑', PerfFamily.emotion, 'smile',
        'exp_smile01', '动词 happy'),
    PerfPreset('smile_grin', '得意笑', PerfFamily.emotion, 'smile',
        'exp_bsmile01', '结算(小单档)'),
    PerfPreset('deny_shy', '嘴硬摆手', PerfFamily.emotion, 'denial',
        'exp_shy01', '情绪 tsun·结算(勉强档)'),
    PerfPreset('angry', '生气', PerfFamily.emotion, 'angry', 'exp_angry02',
        '情绪 annoyed·毒舌'),
    PerfPreset('serious', '正色', PerfFamily.emotion, 'serious',
        'exp_serious01', '情绪 cold'),
    PerfPreset('sad', '垂头', PerfFamily.emotion, 'sad', 'exp_sad01', '认输'),
    PerfPreset('cry', '哭', PerfFamily.emotion, 'cry', 'exp_cry02', '动词 cry'),
    PerfPreset('surprise', '吃惊', PerfFamily.emotion, 'surprised',
        'exp_surprised01', '暴击'),
    PerfPreset('panic', '惊慌摆手', PerfFamily.emotion, 'denial',
        'exp_surprised01', '戳她第 4 下'),
    PerfPreset('ask', '歪头疑问', PerfFamily.emotion, 'question',
        'exp_serious02', '追问·绑定问目标'),
    PerfPreset('maskoff', '翻脸', PerfFamily.emotion, 'maskoff',
        'exp_shadow01', '动词 maskoff'),

    // ── 结算 ──────────────────────────────────────────────────
    PerfPreset('settle_grade', '勉强收下', PerfFamily.settle, 'denial',
        'exp_shy01', '结算(勉强档)'),
    PerfPreset(
        'levelup', '升级定格', PerfFamily.settle, 'kime', 'exp_kime01', '升级', priority: 3),
    PerfPreset('crit', '暴击', PerfFamily.settle, 'surprised',
        'exp_surprised01', '暴击', priority: 3),

    // ── 失败 ──────────────────────────────────────────────────
    PerfPreset('fail_quit', '认输垂头', PerfFamily.fail, 'sad', 'exp_sad01',
        '认输(主动)'),
    PerfPreset('fail_timeout', '超时惨白', PerfFamily.fail, 'sad',
        'exp_pale02', '认输(超时)'),

    // ── 睡醒 ──────────────────────────────────────────────────
    PerfPreset('sleep', '睡着', PerfFamily.sleep, 'idle', 'exp_sys_sleep',
        '开机睡姿·打瞌睡', priority: 1),
    PerfPreset('wake', '惊醒', PerfFamily.sleep, 'surprised', 'exp_sys_wake',
        '瞌睡被戳醒'),

    // ── 备用（闲置表情的组合，等宿主点名）────────────────────
    PerfPreset('rage', '压着火', PerfFamily.extra, 'angry', 'exp_angry01',
        '毒舌加重(连败 2 次以上)'),
    PerfPreset('pale', '失血', PerfFamily.extra, 'check', 'exp_pale01',
        '暴击失手·S 级发布前'),
    PerfPreset('shock', '大惊', PerfFamily.extra, 'surprised',
        'exp_surprised03', 'S 级结算·突发钉单'),
    PerfPreset('stunned', '愕然', PerfFamily.extra, 'surprised',
        'exp_surprised02', '(备用)'),
    PerfPreset('gloomy', '低落', PerfFamily.extra, 'sad', 'exp_sad02', '(备用)'),
    PerfPreset('sob', '抽泣', PerfFamily.extra, 'cry', 'exp_cry01',
        '连败一档'),
    PerfPreset('breakdown', '崩溃', PerfFamily.extra, 'cry', 'exp_cry06',
        '连败三档'),
  ];

  /// 按族取（调试页与文档都按族分节；族内保持声明顺序）
  static List<PerfPreset> of(PerfFamily f) =>
      all.where((PerfPreset p) => p.family == f).toList(growable: false);

  static PerfPreset? byId(String id) {
    for (final PerfPreset p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 动作组总表（18 个 = 17 个语义组 + `Idle` 常驻基底别名）——调试页"动作"页签用
  static List<String> get groups =>
      <String>[...Live2DStage.motionGroups, Live2DStage.baseGroup];
}
