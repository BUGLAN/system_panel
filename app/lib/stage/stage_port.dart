import 'live2d_stage.dart';
import 'perf_presets.dart';

/// ═══════════════════════════════════════════════════════════
///  舞台端口（T3/T7）—— main.dart 只认这个抽象，不认具体实现。
///
///  ⚠️ 2026-10-12：**只剩原生一条实现**（`NativeStagePort`）。原 WebView 降级
///     路线（`Live2DWeb` / `WebStagePort`）已按宿主拍板删除 —— 它在 App 里
///     触摸是断的（WebView 包在 IgnorePointer 里、stage.js 也不转发指针），
///     而当初保留它的"MuMu 与插件不兼容"归因已被推翻（真因是 shader 资产没打进
///     APK，见 `main.dart` 的舞台注释与 `app/STAGE-OPTIONS.md`）。
///
///  桥接表真源 = prototype/opus-v2-dir/js/stage.js：
///   · 情绪（12）→ 表情文件（EMO_EXP，L73-77）
///   · 动词（19）→ 动作组（MOVE 的 mtn 名映射到 sakiko.model3.json 的 17 个组）
///   · 心情待机池（IDLE_POOL，L67-71：cold / pleased / neutral）
/// ═══════════════════════════════════════════════════════════

/// 舞台端口抽象。
abstract class StagePort {
  /// 切情绪（12 种，见 [StageBridges.emoExp]）——原型 `Stage.emote(name)`
  void mood(String name);

  /// 演一个动作动词（19 种，见 [StageBridges.verbGroup]）——原型 `Stage.motion(verb)`
  void act(String verb);

  /// 切待机池心情（cold / pleased / neutral）——原型 `Stage.idleMood`
  void idleMood(String mood);

  /// 开机睡姿（闭眼低头 + 动作停住）——docs/22 R5「Mac 轮验收项」。
  /// 原生走 `exp_sys_sleep` 合成表情（param() 单帧失效，见 STAGE-OPTIONS
  /// 「表演补完」节）；默认 no-op，WebView 降级路线不实现（留档）。
  Future<void> sleep() async {}

  /// 唤醒睁眼编排（闭眼抬头 450ms → 眼皮 .35 停 140ms → .05 停 120ms →
  /// 睁眼，原型 flows.js `wake()` L77-84 逐拍照抄）。返回的 Future 走完
  /// 整个编排，调用方 `.then` 里接欢迎手势。默认 no-op。
  Future<void> wakeEyes() async {}

  /// 直给一条表演（docs/24 §4：不经过动词表，动作组 + 表情一次下发）。
  /// 用于发布任务/升级/收官这些**没有现成动词**的时刻。默认 no-op（WebView
  /// 降级路线没有组名直通，保留原行为）。
  void perf(String group, String exp, {int priority = 2}) {}

  /// 按**预设**播放（`PerfPreset` = 命名好的"动作 × 表情"组合）。
  /// 默认退回 [perf]。
  void preset(PerfPreset p) => perf(p.group, p.exp, priority: p.priority);

  /// 只换表情（按名字）——调试台"表情"页签用：不动动作、不借还。
  /// 默认 no-op（WebView 路线用 [mood]）。
  void face(String exp) {}

  /// 情绪 + 兜底动作一起演（docs/24 §4「情绪→动作」）：情绪强烈的
  /// （annoyed/cold/sad/joy/surprised/tsun）多演一个动作，其余只换脸。
  /// 默认退回纯 [mood]。
  void react(String mood) => this.mood(mood);

  /// 打瞌睡（docs/24 #15：真机侧补整链）。默认退回 [sleep]。
  Future<void> doze() async => sleep();

  /// 从瞌睡里被戳醒（惊一下 → 回当前情绪）。默认 no-op。
  Future<void> undoze() async {}
}

/// 一条表演：动作组 + 该拍要带的表情（docs/24 §2「动作与表情绑在一起」）。
/// [priority] 遵循 Cubism 约定：0=none · 1=idle · 2=normal · 3=force；
/// 待机 1 / 指令 2 / 强制（暴击、升级、收官）3。
class Perf {
  const Perf(this.group, this.exp, {this.priority = 2});

  /// 动作组名（必须在 `sakiko.model3.json` 的 `Motions` 里）
  final String group;

  /// 表情文件名（必须在 `Expressions` 里；`''` = 这一拍不动表情）
  final String exp;

  final int priority;
}

/// 桥接表 + 查询。全部 static const，`stage_port_test.dart` 会逐条核对
/// （12 情绪全在 28 表情表里、动词组全在 model3.json 的 17 个组里）。
abstract class StageBridges {
  const StageBridges._();

  /// 情绪 → 表情文件名（stage.js `EMO_EXP` L73-77，原值照抄）
  static const Map<String, String> emoExp = <String, String>{
    'neutral': 'exp_idle01',
    'smug': 'exp_bsmile01',
    'cold': 'exp_serious01',
    'annoyed': 'exp_angry02',
    'pleased': 'exp_smile01',
    'tsun': 'exp_shy01',
    'joy': 'exp_bsmile02',
    'proud': 'exp_smile02',
    'surprised': 'exp_surprised02',
    'sad': 'exp_sad02',
    'focus': 'exp_serious02',
    'sleep': 'exp_idle04',
  };

  /// 动词 → 动作组（stage.js `MOVE` L45-65 的 mtn 名 → sakiko.model3.json
  /// 的 17 个组；docs/18 §1.5.4 的映射表）。组名清单见
  /// [Live2DStage.motionGroups]。
  static const Map<String, String> verbGroup = <String, String>{
    'present': 'kime',
    'cheer': 'kime',
    'nod': 'nod',
    'nod2': 'nod',
    'surprise': 'surprised',
    'fluster': 'denial',
    'deny': 'denial',
    'down': 'sad',
    'think': 'thinking',
    'happy': 'smile',
    'poke': 'check',
    'lookAway': 'look',
    'ask': 'question',
    'bye': 'bye',
    'check': 'check',
    'serious': 'serious',
    'angry': 'angry',
    'cry': 'cry',
    'maskoff': 'maskoff',
  };

  /// 动词 → 该拍要带的表情（docs/24 §4「动作与表情绑在一起」：**19 个动词全覆盖**，
  /// `act()` 一次下发表情+动作；表情是"借"的，3s 后还给当前情绪，见
  /// [Live2DStageHandle] 的归还定时器）。
  static const Map<String, String> verbFace = <String, String>{
    'present': 'exp_kime01', // 亮相/收官定格
    'cheer': 'exp_kime01',
    'nod': 'exp_serious02', // 接单/落库的正色点头
    'nod2': 'exp_serious02',
    'surprise': 'exp_surprised01', // 暴击
    'fluster': 'exp_surprised01', // 戳她第 4 下：又惊又躲
    'deny': 'exp_shy01', // 嘴硬
    'down': 'exp_sad01', // 认输
    'think': 'exp_serious02', // 追问/换目标
    'happy': 'exp_smile01', // 得意
    'poke': 'exp_shy01', // 原型 MOVE 里唯一带 exp 的，原值保留
    'lookAway': 'exp_idle02', // 回来看一眼
    'ask': 'exp_serious02', // 歪头疑问
    'bye': 'exp_idle01',
    'check': 'exp_serious01', // 打量/快照确认
    'serious': 'exp_serious01',
    'angry': 'exp_angry02', // 毒舌
    'cry': 'exp_cry02', // 连败（清单 C：6 个哭脸只用 2~3 个）
    'maskoff': 'exp_shadow01', // 翻脸黑脸（把闲置的 shadow 用起来）
  };

  /// 一条待机表演：动作组 + 该拍表情（docs/24 §3 清单 A）。
  /// 待机一律 priority 1（不许盖过正在演的指令）。
  static const List<Perf> _idleNeutral = <Perf>[
    Perf('look', 'exp_idle01'),
    Perf('check', 'exp_idle02'),
    Perf('thinking', 'exp_idle03'),
    Perf('smile', 'exp_smile01'),
    Perf('nod', 'exp_idle01'),
    Perf('idle', 'exp_idle01'),
  ];
  static const List<Perf> _idleCold = <Perf>[
    Perf('serious', 'exp_serious01'),
    Perf('look', 'exp_idle02'),
    Perf('nod', 'exp_serious02'),
    Perf('check', 'exp_serious01'),
  ];
  static const List<Perf> _idlePleased = <Perf>[
    Perf('smile', 'exp_smile02'),
    Perf('kime', 'exp_kime01'),
    Perf('nod', 'exp_smile01'),
    Perf('look', 'exp_smile01'),
    Perf('idle', 'exp_bsmile01'),
  ];

  /// 心情 → 待机表演池（docs/24 §3；原来只有动作组名、不带表情）
  static const Map<String, List<Perf>> idlePool = <String, List<Perf>>{
    'cold': _idleCold,
    'pleased': _idlePleased,
    'neutral': _idleNeutral,
  };

  /// 情绪 → 默认动作**动词**（docs/24 §4 的"情绪→动作"兜底，给 [StagePort.react] 用）。
  /// 只给**情绪强烈**的配动作（惊讶/生气/难过/得意/嘴硬），其余只换脸不动作 ——
  /// 表演预算（docs/14）：一拍只演一件事，别句句都动。
  /// ⚠️ 值必须是 [verbGroup] 的键（动词），不是动作组名。
  static const Map<String, String> emotionAct = <String, String>{
    'annoyed': 'angry',
    'cold': 'serious',
    'sad': 'down',
    'joy': 'cheer',
    'surprised': 'surprise',
    'tsun': 'deny',
  };

  /// 认得的情绪？
  static bool isMood(String name) => emoExp.containsKey(name);

  /// 认得的动词？
  static bool isVerb(String verb) => verbGroup.containsKey(verb);

  /// 合法心情（未知回落 neutral）
  static String poolOf(String mood) =>
      idlePool.containsKey(mood) ? mood : 'neutral';

  /// 情绪 → 表情下标（通过 [Live2DStage.expressionIndex]；找不到 -1）
  static int moodIndex(String name) {
    final String? exp = emoExp[name];
    if (exp == null) return -1;
    return Live2DStage.expressionIndex(exp);
  }

  /// 动词 → 动作组（未知动词回落 nod，绝不静默丢弃）
  static String groupOf(String verb) => verbGroup[verb] ?? 'nod';

  /// 动词自带的表情（无则 ''；再经 [Live2DStage.expressionIndex] 得下标，
  /// '' → -1 = 这一拍不动表情）
  static String faceOf(String verb) => verbFace[verb] ?? '';

  /// 动词自带表情的下标（无则 -1）
  static int verbFaceIndex(String verb) =>
      Live2DStage.expressionIndex(faceOf(verb));

  /// 情绪 → 兜底动作的**动词**（无则 ''，只换脸不动作）
  static String actOf(String mood) => emotionAct[mood] ?? '';
}

/// 原生实现：包住 `Live2DStageHandle`，查表后走插件 API。
class NativeStagePort implements StagePort {
  NativeStagePort(this._handle);

  final Live2DStageHandle _handle;

  @override
  void mood(String name) => _handle.emote(name);

  @override
  void act(String verb) => _handle.act(verb);

  @override
  void idleMood(String mood) => _handle.setIdleMood(mood);

  @override
  void perf(String group, String exp, {int priority = 2}) =>
      _handle.perf(group, exp, priority: priority);

  @override
  void preset(PerfPreset p) =>
      _handle.perf(p.group, p.exp, priority: p.priority);

  @override
  void face(String exp) => _handle.face(exp);

  @override
  void react(String mood) {
    _handle.emote(mood);
    // 情绪强烈的才加动作（表演预算：不是每句台词都动）
    final String verb = StageBridges.actOf(mood);
    if (verb.isNotEmpty) _handle.act(verb);
  }

  @override
  Future<void> sleep() => _handle.sleep();

  @override
  Future<void> wakeEyes() => _handle.wakeEyes();

  @override
  Future<void> doze() => _handle.sleep();

  @override
  Future<void> undoze() => _handle.undoze();
}
