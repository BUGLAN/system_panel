import 'live2d_stage.dart';
import 'live2d_web.dart';

/// ═══════════════════════════════════════════════════════════
///  舞台端口（T3/T7）—— main.dart 只认这个抽象，不认具体实现。
///
///  双实现等价（docs/18 §1.5.4）：
///   · 原生 `Live2DStage`：表情/动作走插件 API，桥接表在 Dart 侧查
///   · WebView `Live2DWeb`：转发给原型播放器自己的 `Stage.emote/motion`
///     （stage.js L27-77 本来就有 FACES/MOVE/EMO_EXP 表）
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

  /// 动词自带的表情覆盖（stage.js MOVE 里的 `exp:` 字段——目前只有 poke）
  static const Map<String, String> verbExp = <String, String>{
    'poke': 'exp_shy01',
  };

  /// 心情 → 待机动作组池（stage.js `IDLE_POOL` L67-71 的 mtn 名 → 组名）
  static const Map<String, List<String>> idlePool = <String, List<String>>{
    'cold': <String>['serious', 'look', 'nod'],
    'pleased': <String>['smile', 'kime', 'nod'],
    'neutral': <String>['look', 'check', 'nod', 'smile', 'thinking', 'idle'],
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

  /// 动词自带的表情覆盖（无则 -1）
  static int verbExpIndex(String verb) {
    final String? exp = verbExp[verb];
    if (exp == null) return -1;
    return Live2DStage.expressionIndex(exp);
  }
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
}

/// WebView 实现：转发给原型播放器的 `Stage.emote/motion`（stage.js 自带同名表）。
class WebStagePort implements StagePort {
  WebStagePort(this._state);

  final Live2DWebState _state;

  @override
  void mood(String name) => _state.emote(name);

  @override
  void act(String verb) => _state.motion(verb);

  @override
  void idleMood(String mood) {
    // 播放器内部本来就有 IDLE_POOL 待机调度，无需外部喂
  }
}
