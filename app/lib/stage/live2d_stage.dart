import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetManifest, ByteData, rootBundle;
import 'package:flutter_live2d/flutter_live2d.dart';
import 'package:path_provider/path_provider.dart';

import 'camera.dart';
import 'stage_port.dart';

/// ═══════════════════════════════════════════════════════════
///  她本人（`#stage`）—— Live2D 模型的原生渲染层
///
/// 原型里这个节点是 `document.createElement('ournotes-live2d')`，由自定义
/// 播放器挂 WebGL 画布（`stage.js` L120）。这里换成 `flutter_live2d`
/// （Cubism Native SDK + OpenGL ES 2）—— **渲染器换了，但模型数据是同一份**：
/// `tools/l2d/convert.py` 把原型那份 Unity prefab 转成了标准 Live2D 文件。
///
/// ## 几件必须记住的事
///
/// 1. **它必须放在 Flutter UI 的下面。** 插件用
///    `PlatformViewHitTestBehavior.opaque`，平台视图会吃掉触摸；放在下层时
///    Stack 里更靠上的 Flutter 组件先命中，字幕/按钮照样能点。
/// 2. **没有相机矩阵 API。** 插件只给参数/动作/表情，给不了变换。原型的相机是
///    世界空间里的仿射（缩放 + 平移，`stage.js` `_camMul`）—— 这里用
///    **布局矩形复刻**（docs/18 §1.5.3）：`Live2DView` 放进 `Positioned.fromRect`，
///    矩形由 `Cam` 算出（见 [Live2DStage.stageRect]）。⚠️ 平台视图外禁套
///    `Transform`/`Opacity` —— saveLayer 会把平台视图整个吞掉（实测踩过）。
/// 3. **加载失败要能降级。** 模型目录不入库（版权），新克隆没跑转换器时会
///    `LOAD_FAILED`；这时整层收掉，让舞台退回全息剪影（原型也有这个降级）。
/// ═══════════════════════════════════════════════════════════

/// 舞台对外的把手：给页面驱动"她现在什么表情、做什么动作"。
class Live2DStageHandle {
  Live2DStageHandle(this._ctrl, [this._onIdleMood, this._onSleepingChanged]);

  final Live2DViewController _ctrl;

  /// 待机池心情落回 state（原型 `Stage.idleMood = mood`）
  final void Function(String mood)? _onIdleMood;

  /// 睡眠态回写（`_Live2DStageState._sleeping`）：睡觉期间待机池暂停
  final ValueChanged<bool>? _onSleepingChanged;

  bool get isReady => _ctrl.value.isLoaded;

  /// 切待机池心情（cold / pleased / neutral）
  void setIdleMood(String mood) => _onIdleMood?.call(mood);

  /// 播一个动作（组名来自 `model3.json` 的 `Motions` 分组：
  /// `idle` / `smile` / `nod` / `cry` / `angry` / `look` …）
  Future<void> motion(String group, {int index = 0, int priority = 2}) =>
      _ctrl.startMotion(group: group, index: index, priority: priority);

  /// 切表情（`model3.json` 里 `Expressions` 的**下标**，插件只收下标不收名字）
  Future<void> expression(int index) => _ctrl.setExpression(index);

  /// 直接写参数（原型 `Stage.faceT` 那套表情参数的入口）
  Future<void> param(String id, double value) => _ctrl.setParameter(id, value);

  /// 0 = 停住动作（物理继续跑）
  void speed(double v) => _ctrl.setMotionSpeed(v);

  // ── 表情借还（docs/24 §6 红线 3：借的表情要归还）──────────────────
  // 动作/待机带的表情是"借"的：拍完 3s 自动回到**当前情绪**的脸。
  // （原来没有这个机制——戳她以外的表情会一直挂到下一次 mood()。）
  String _moodName = 'neutral';
  Timer? _expGiveBack;

  /// 当前基础情绪（[emote] 最后一次收下的名字）
  String get moodName => _moodName;

  /// 借出的表情多久归还（动作普遍 2~4s，取 3s 中位）
  static const Duration _kExpGiveBack = Duration(seconds: 3);

  void _scheduleGiveBack() {
    _expGiveBack?.cancel();
    _expGiveBack = Timer(_kExpGiveBack, () {
      final int i = StageBridges.moodIndex(_moodName);
      if (i >= 0) unawaited(expression(i));
    });
  }

  /// 释放定时器（`_Live2DStageState.dispose` 里调）
  void dispose() {
    _expGiveBack?.cancel();
    _expGiveBack = null;
  }

  /// 情绪入口（原型 `Stage.emote(name)`）：查 [StageBridges.emoExp]
  /// 下发表情；`sleep` 额外把动作停住（docs/18 §1.5.4：idle speed 0）。
  /// 这是**基础脸**：换情绪会立刻作废没还完的"借出表情"。
  Future<void> emote(String name) async {
    _moodName = StageBridges.isMood(name) ? name : 'neutral';
    _expGiveBack?.cancel();
    final int i = StageBridges.moodIndex(_moodName);
    if (i >= 0) await expression(i);
    speed(_moodName == 'sleep' ? 0 : 1);
  }

  /// 动作入口（原型 `Stage.motion(verb)`）：动词→动作组 + **该拍表情**
  /// （docs/24 §4：19 个动词全带脸，表情 3s 后还给当前情绪）。
  ///
  /// ⚠️ **组内随机取变体**：原型 `MOVE[verb].m` 是数组（C/L/R 三向），
  /// 固定 index 0 会让她每次都做同一个动作（宿主验收「待机动作太少」）。
  Future<void> act(String verb) async {
    final int xi = StageBridges.verbFaceIndex(verb);
    if (xi >= 0) {
      await expression(xi);
      _scheduleGiveBack();
    }
    final String group = StageBridges.groupOf(verb);
    await motion(
      group,
      index: _rnd.nextInt(Live2DStage.countOf(group)),
      priority: 2,
    );
  }

  /// 直给一条表演（docs/24 §4：没有现成动词的时刻——发布任务/升级/收官）。
  /// 表情同样是借的，3s 后回当前情绪。
  Future<void> perf(String group, String exp, {int priority = 2}) async {
    final int i = Live2DStage.expressionIndex(exp);
    if (i >= 0) {
      await expression(i);
      _scheduleGiveBack();
    }
    await motion(
      group,
      index: _rnd.nextInt(Live2DStage.countOf(group)),
      priority: priority,
    );
  }

  /// 只换表情（按名字）——调试台"表情"页签用：不借还、不动动作，纯看脸。
  Future<void> face(String exp) async {
    final int i = Live2DStage.expressionIndex(exp);
    if (i >= 0) await expression(i);
  }

  /// 待机池条目（docs/24 §3：待机动作**带表情**，priority 恒 1）
  Future<void> idlePerf(Perf p) async {
    final int i = Live2DStage.expressionIndex(p.exp);
    if (i >= 0) {
      await expression(i);
      _scheduleGiveBack();
    }
    await motion(
      p.group,
      index: _rnd.nextInt(Live2DStage.countOf(p.group)),
      priority: 1,
    );
  }

  /// 从瞌睡里被戳醒（docs/24 #15）：惊一下（exp_sys_wake）→ 回当前情绪。
  Future<void> undoze() async {
    final int wake = Live2DStage.expressionIndex('exp_sys_wake');
    if (wake >= 0) await expression(wake);
    speed(1);
    _onSleepingChanged?.call(false);
    // 350ms 后回到基础情绪的脸（惊那一拍要看得见）
    _expGiveBack?.cancel();
    _expGiveBack = Timer(const Duration(milliseconds: 350), () {
      final int i = StageBridges.moodIndex(_moodName);
      if (i >= 0) unawaited(expression(i));
    });
  }

  final math.Random _rnd = math.Random();

  // ── 开机睡姿与唤醒编排（docs/22 R5「Mac 轮验收项」· 2026-10-11 补完）──
  //
  // 为什么不走 `param()`：插件 wrapper 的 SetParam 单帧即被
  // `LoadParameters→motion→SaveParameters` 循环覆写（STAGE-OPTIONS
  // 「表演补完」节实测）；表情在管线里于 eyeblink 之后应用、
  // Blend=Overwrite 可持续覆写 —— 所以闭眼/抬眼皮全部走 `exp_sys_*` 合成表情。

  /// 开机睡姿（原型 flows.js L54-61：`emote('sleep') + look('down')`，
  /// FACES.sleep 原值 lid 0 / ay −16 / az 2 / cheek .1）：
  /// 闭眼 + 低头 + 眼球下移 + 动作停住（speed 0，物理照跑）。
  Future<void> sleep() async {
    _onSleepingChanged?.call(true);
    speed(0);
    final int i = Live2DStage.expressionIndex('exp_sys_sleep');
    debugPrint('[stage] 睡姿下发（exp_sys_sleep 下标 $i）');
    if (i >= 0) await expression(i);
  }

  /// 唤醒睁眼编排（原型 flows.js `wake()` L77-84 的拍子，逐拍照抄）：
  /// 闭眼抬头 450ms → 眼皮 .35 停 140ms → .05 停 120ms → neutral 睁眼
  /// （+ 动作恢复）。返回后由调用方接欢迎手势。
  Future<void> wakeEyes() async {
    final int up = Live2DStage.expressionIndex('exp_sys_wake');
    final int l35 = Live2DStage.expressionIndex('exp_sys_lid35');
    final int l05 = Live2DStage.expressionIndex('exp_sys_lid05');
    final int neutral = Live2DStage.expressionIndex('exp_idle01');
    final bool stepsOk = up >= 0 && l35 >= 0 && l05 >= 0 && neutral >= 0;
    debugPrint(
      '[stage] 睁眼编排开始：抬头 $up / lid35 $l35 / lid05 $l05 / neutral $neutral'
      '${stepsOk ? '' : " ⚠️ 有下标 -1 —— 模型数据版本可能没刷新"}',
    );
    // 抬头（仍闭眼）
    if (up >= 0) await expression(up);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    // 眼皮颤两下：.35 → .05
    if (l35 >= 0) await expression(l35);
    await Future<void>.delayed(const Duration(milliseconds: 140));
    if (l05 >= 0) await expression(l05);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    // 睁眼看向宿主（neutral = 原型 emote('neutral')；视线由 drag(0,0) 天然正对）
    if (neutral >= 0) await expression(neutral);
    speed(1);
    _onSleepingChanged?.call(false);
    debugPrint('[stage] 睁眼编排完成（450/140/120ms 三拍）');
  }
}

class Live2DStage extends StatefulWidget {
  const Live2DStage({
    super.key,
    this.visible = true,
    required this.cam,
    this.onReady,
    this.onFailed,
  });

  final bool visible;

  /// 相机（`camera.dart` 弹簧推出来的那一帧）—— **几何相机：布局矩形复刻**。
  /// 没有 camera matrix API（docs/18 §1.5.3），所以把 `Live2DView` 放进
  /// `Positioned.fromRect`：矩形 = 以 `Cam.screenCenter` 为中心、
  /// 边长 = 屏高 × `Cam.s`（她应占屏高的比例）× 标定系数。
  final Cam cam;

  /// 模型加载好了（把把手交出去）
  final ValueChanged<Live2DStageHandle>? onReady;

  /// 加载失败（拿不到模型就退回剪影/WebView）
  final VoidCallback? onFailed;

  /// ⚠️ **对照实验开关**：临时换成标准模型 Hiyori 来定位问题。
  ///
  /// **实验做完了，结论留在 `app/STAGE-OPTIONS.md`：**
  /// 换成标准模型 Hiyori 之后**照样什么都看不见**（而它 `loadModel` 第一次就返回
  /// true，sakiko 要两次）。所以 —— **问题不在我转换的模型，在插件/合成的这一层。**
  /// 想复现细节时把它改成 `true` 即可。
  static const bool useHiyoriControl = false;

  /// 本机转换出来的模型（`tools/l2d/convert.py`）
  static const String modelDir = useHiyoriControl
      ? 'assets/live2d/hiyori/'
      : 'assets/live2d/sakiko/';
  static const String modelFile = useHiyoriControl
      ? 'Hiyori.model3.json'
      : 'sakiko.model3.json';

  /// `sakiko.model3.json` 的 **17 个动作组**（2026-10-09 本机实测清单，
  /// `stage_port_test.dart` 会核对桥接表里每个动词组都在这里面）：
  /// idle/smile/nod/cry/angry/look/surprised/question/sad/serious/denial/
  /// check/bye/misc_tear/maskoff/kime/thinking
  static const List<String> motionGroups = <String>[
    'idle',
    'smile',
    'nod',
    'cry',
    'angry',
    'look',
    'surprised',
    'question',
    'sad',
    'serious',
    'denial',
    'check',
    'bye',
    'misc_tear',
    'maskoff',
    'kime',
    'thinking',
  ];

  /// 每个动作组的**变体数**（`sakiko.model3.json` 实测，2026-10-11）。
  ///
  /// 原型 `MOVE` 表里的 `m` 是**数组**（C 中 / L 左 / R 右 三向随机挑一个），
  /// 待机池同理 —— 固定播 `index: 0` 的话，池子里那 6 个组实际只出 6 个动作，
  /// 观感就是宿主验收的「待机动作太少」。按组内随机后可用变体 **27 个**。
  /// `stage_port_test.dart` 会拿转换产物逐项核对这张表。
  static const Map<String, int> motionCounts = <String, int>{
    'idle': 3,
    'smile': 6,
    'nod': 6,
    'cry': 3,
    'angry': 3,
    'look': 6,
    'surprised': 3,
    'question': 3,
    'sad': 6,
    'serious': 3,
    'denial': 6,
    'check': 3,
    'bye': 3,
    'misc_tear': 1,
    'maskoff': 3,
    'kime': 3,
    'thinking': 3,
    'Idle': 1, // 基底别名组（只有 mtn_idle01_C 一条）
  };

  /// 组内变体数（未知组按 1 处理，绝不越界 —— 越界插件会静默 no-op）
  static int countOf(String group) => motionCounts[group] ?? 1;

  /// `model3.json` 里 `Expressions` 的顺序。
  ///
  /// 插件只收**下标**不收名字，所以这里留一份名字表供调用方按名字查。
  /// ⚠️ 顺序由 `tools/l2d/convert.py` **按名字排序**写出（prefab 里的原序是随机的，
  ///    不可依赖），所以这张表就是字母序。**改了转换器就要同步这里** ——
  ///    `test/stage_port_test.dart` 核对桥接表、本表与产物的一致性。
  /// 尾部 4 个 `exp_sys_*` 是转换器生成的**系统合成表情**（2026-10-11 表演补完，
  ///    STAGE-OPTIONS「表演补完」节）：Blend=Overwrite 持续覆写眼部/头部参数，
  ///    服务开机睡姿与唤醒睁眼编排 —— 原型 `faceT` 脸层的原生等价物
  ///    （插件 `SetParam` 单帧即被 motion 管线覆写，所以走表情不走参数）。
  static const List<String> expressions = <String>[
    'exp_angry01',
    'exp_angry02',
    'exp_bsmile01',
    'exp_bsmile02',
    'exp_cry01',
    'exp_cry02',
    'exp_cry03',
    'exp_cry04',
    'exp_cry05',
    'exp_cry06',
    'exp_idle01',
    'exp_idle02',
    'exp_idle03',
    'exp_idle04',
    'exp_kime01',
    'exp_pale01',
    'exp_pale02',
    'exp_sad01',
    'exp_sad02',
    'exp_serious01',
    'exp_serious02',
    'exp_shadow01',
    'exp_shy01',
    'exp_smile01',
    'exp_smile02',
    'exp_surprised01',
    'exp_surprised02',
    'exp_surprised03',
    'exp_sys_lid05',
    'exp_sys_lid35',
    'exp_sys_sleep',
    'exp_sys_wake',
  ];

  /// 常驻基底动作组（转换器在 model3.json 里生成的 `"Idle"` 别名组，指向
  /// `mtn_idle01_C`）。插件的 iOS wrapper 对字面 `"Idle"` 组**循环播放**、
  /// 且在动作播完时**自动兜底回它** —— 这正是原型 stage.js L167
  /// `playMotion(defaultMotion, {loop:true})` 的常驻基底语义。
  /// ⚠️ 17 个语义组（[motionGroups]）是桥接表用的；基底是这一条，别混。
  static const String baseGroup = 'Idle';

  /// 模型数据版本戳（改一次数据升一次）：
  /// · v2 = 2026-10-11 表演补完（"Idle" 别名组 + 4 个 exp_sys_* 合成表情）
  /// · v3 = 2026-10-11 眼皮颤动改脆（exp_sys_* 淡出 .25→.05）
  ///
  /// ⚠️ **为什么自管解压目录（不交给插件的 asset 缓存）**：
  /// 插件的 `_extractAssetDirToCache`（asset_cache.dart L60-77）以「目录存在 +
  /// `.ready` 标记」短路，缓存键只有**目录名的 base64、没有内容指纹** ——
  /// 换数据后旧 model3.json 会被无限复用。2026-10-11 实测踩中：插件缓存里
  /// 还是 Oct 10 23:54 解压的旧数据（28 表情 / 无 Idle 组 / 无 exp_sys_*），
  /// 新数据 00:53 才生成，之后重装 App 三次都没刷新 → 表情下标 30 越界静默
  /// no-op、基底组找不到，她「一点没变」。
  /// ⚠️ 踩坑细节：`getTemporaryDirectory()`（path_provider）在 iOS 上返回的是
  ///    **`Library/Caches`**，而插件走的是 `NSTemporaryDirectory()` = **`tmp/`**
  ///    —— 两者不是同一个目录，所以「删插件缓存目录」那条路走不通（第一版
  ///    就是这么白写的）。改为自己解压到我们选定的目录、喂**绝对路径**。
  /// 取证手段（下次复用）：
  ///   xcrun devicectl device copy from --domain-type appDataContainer \
  ///     --domain-identifier com.systempanel.app \
  ///     --source Library/Caches/sys_l2d --destination /tmp/devextract
  ///   （要看插件自己那份旧缓存就把 source 换成 tmp/flutter_live2d_models）
  ///
  /// 插件的 `loadModel` 接受**绝对路径**（`_isAbsolutePath` → 原样返回），
  /// 所以这里按版本号解压到 `Library/Caches/sys_l2d/v<N>/` 再喂绝对路径 ——
  /// 刷新时机完全由我们掌控，未来重跑转换器只需把版本号 +1。
  /// · v2 = 表演补完（Idle 别名组 + 4 个 exp_sys_*）
  /// · v3 = 眼皮颤动改脆（exp_sys_* 淡出 .25→.05）
  /// · v4 = 贴图 2× Lanczos 上采样试过（2048²→4096²）—— **已退回**：
  ///        高频能量只 +3%（插件 mipmap 链会把有效细节归一化），宿主主观
  ///        验收「更糊」，GPU 显存还 4 倍 ⇒ 回到 v5 = 原版 2048² 贴图
  /// · v5 = 2026-10-11 几何修正（画布比例 2:3 的舞台矩形）+ 贴图回 2048²
  /// · v6 = **动作 Segments 布局修正**（转换器把类型标记写在了错误位置，
  ///        导致全部 64 个动作都过不了 Cubism 一致性校验、`LoadMotion` 全失败
  ///        → 她从来没播过任何动作，宿主验收「像死人一样」）
  /// · v7 = **JSON 格式修正**（Cubism 私有解析器只认 `\n`/`,` 作数字终止符、
  ///        且不吃科学计数法；转换器原来压单行 → 每个数组的最后一个数字紧跟
  ///        `]` → `IsValid=0` → 动作与物理全部加载失败）
  /// · v8 = 表情剥掉「眼睑 = 1.0 的 Overwrite 钉死」→ 恢复眨眼（待机三修①）
  /// · v9 = **表情 Blend 枚举映射修正**（2026-10-12，宿主：「默认的这个眼睛
  ///        好像弄错了」）。prefab 的 Blend 是 Unity 的
  ///        `0=Override/1=Additive/2=Multiply`，与 exp3.json 的
  ///        `0=Add/1=Multiply/2=Overwrite` **不同序**；旧转换器按"同序"搬，
  ///        于是 prefab 里 1962 条 `Additive 0`（= 加 0 = 什么都不做）被写成
  ///        `Multiply 0` ⇒ **把参数清零**：大厅待机那张 `exp_idle01` 里的
  ///        `ParamCheek`（腮红）、`ParamEyeLHighlight/RHighlight`（**瞳孔高光**）、
  ///        `ParameyelidL/R`、`ParamMouthForm` 等全被钉成 0 —— 默认这张脸因此
  ///        与原数据不一样。修正后 v8 那个"剥眼睑"补丁随之作废（同一条变成
  ///        `Multiply 1.0` = 空操作，眨眼天然不受影响）。
  static const int modelDataVersion = 9;

  /// 把声明的模型资产解压到版本化目录，返回**绝对路径**（带尾斜杠）。
  /// 版本一致就复用；不一致先把整棵树删掉（连旧版本目录）再重解。
  static Future<String> resolveModelDir() async {
    final Directory tmp = await getTemporaryDirectory();
    final Directory root = Directory('${tmp.path}/sys_l2d');
    final Directory dir = Directory('${root.path}/v$modelDataVersion');
    final File marker = File('${dir.path}/.complete');
    if (dir.existsSync() && marker.existsSync()) {
      debugPrint('[stage] 模型资产 v$modelDataVersion 已就位（复用）');
      return '${dir.path}/';
    }
    if (root.existsSync()) await root.delete(recursive: true);
    await dir.create(recursive: true);
    final AssetManifest manifest =
        await AssetManifest.loadFromAssetBundle(rootBundle);
    final List<String> keys = manifest
        .listAssets()
        .where((String k) => k.startsWith(modelDir))
        .toList();
    for (final String key in keys) {
      final String rel = key.substring(modelDir.length);
      final File out = File('${dir.path}/$rel');
      await out.parent.create(recursive: true);
      final ByteData data = await rootBundle.load(key);
      await out.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    await marker.writeAsString('ok', flush: true);
    debugPrint('[stage] 模型资产 v$modelDataVersion 解压完成（${keys.length} 件）→ ${dir.path}');
    return '${dir.path}/';
  }


  /// 按名字取表情下标（找不到给 -1）
  static int expressionIndex(String name) => expressions.indexOf(name);

  /// ── 相机矩形（docs/18 §1.5.3 布局矩形复刻相机）──────────────────
  ///
  /// 她**应占**的屏幕矩形：中心 = `Cam.screenCenter`，高 = 屏高 × `Cam.s`
  /// × [StageCalib.kSize]，宽按**模型画布比例**（见 [kCanvasAspect]）。
  ///
  /// ⚠️⚠️ **为什么必须保持画布比例（2026-10-11 iOS 真机轮踩的坑）**：
  /// 插件 iOS 侧把模型塞进视图的规则是（`Live2DWrapper.mm` L615 / L658）——
  /// ```objc
  /// if (w > h) _model->GetModelMatrix()->SetHeight(2.0f);
  /// else       _model->GetModelMatrix()->SetWidth(2.0f);   // 方形/竖视图走这里
  /// ```
  /// 即**非宽视图按「画布宽度」塞满视图宽度**。sakiko 的画布是 6000×9000
  /// （宽:高 = 2:3），于是画布高 = 3.0 个世界单位被塞进只有 2.0 单位高的
  /// **正方形**视图 → 她**恒定被上下各裁掉 25% 视图高**（宿主观感：头顶与脚
  /// 都被截断、她"太大"）。而且：**视图是正方形时，矩形调多大都没用** ——
  /// 可见的世界范围只由视图**宽高比**决定，不由尺寸决定。
  /// 所以舞台矩形必须保持画布比例（宽 = 高 × 2/3），此时可见范围正好等于
  /// 整张画布（高 3.0 单位），她完整可见；大小再交给 [StageCalib.kSize]。
  ///
  /// 旧的"正方形 + 当成 92% 屏高"那套是**循环论证**：方形视图裁掉的内容让
  /// 可见轮廓恰好填满矩形，`calib_alpha` 量到的"92.0%"其实是被裁后的范围
  /// （HANDOFF 警告过"别拿被裁的轮廓当信号"，这次是另一种同款：量到的是
  /// 裁剪框本身）。
  static Rect stageRect(Cam cam, Size size) {
    final Offset center = cam.screenCenter(size);
    final double h = size.height * cam.s * StageCalib.kSize;
    final double w = h * kCanvasAspect;
    return Rect.fromCenter(center: center, width: w, height: h)
        .translate(StageCalib.dx, StageCalib.dy);
  }

  /// ── 视图固定尺寸族（2026-10-11 根治「推镜头像硬切」）──────────────
  ///
  /// 病灶：平台视图的**布局尺寸**一变，插件 iOS 侧就在 `layoutSubviews()` 里
  /// `recreateFramebufferOnMainThread()` + `onSurfaceChanged()`（重建 FBO、
  /// 排空渲染队列）。相机按帧改矩形尺寸 = **每帧重建** —— 于是推镜头那段她
  /// 基本不渲染，落点看起来就是"直接切过去"（原来的应对只是拿亮帧盖住）。
  ///
  /// 现在：视图只在**族**之间换尺寸（罕见，且都有过场盖着），族内所有缩放
  /// 交给 `Transform` —— Flutter 官方文档明确 `UiKitView`（`_DarwinView`）
  /// **支持 transform / clip / opacity**，而 `Transform.scale` 绕矩形中心
  /// 缩放与"把矩形改成 cam.s 那么大"在几何上完全等价（宽高比不变、中心不变）。
  ///
  /// 族尺寸 ≥ 族内最大 `cam.s`，所以缩放系数恒 ≤ 1（只缩小、不放大 → 不糊）。
  /// 目前只有两族：小景别（boot/lobby/exec/result/full/panel/fail ≤ 1.05）
  /// 与大景别（talk 1.70 = 派单时推到她跟前）。
  ///
  /// ⚠️ **2026-10-24：小族从 1.05 提到 1.40 —— 这不是"几何回退"，是超采样（SSAA）**。
  /// 病根：贴图相对屏幕本来就是 1:1（虹膜 96×112 texel ↔ 屏上 34~41px，mip LOD 1.07~1.22），
  /// 所以「关 mipmap」换来的锐利全是混叠（发丝/腮红上的点状噪光，宿主 2026-10-24 判
  /// 「锯齿太多了」）。真正能"又清晰又干净"的只有**多渲染像素再缩回去**：
  /// 小族 1.40 ⇒ 平台视图按屏高 1.40 倍渲染（FBO 3914px 高），再由 Transform 缩到
  /// cam.s（大厅 0.92 → 1.52× 超采样），CoreAnimation 做降采样 ⇒ 中频 +50~53%、
  /// 高频仅 +74~162%（对照：关 mipmap 是 +900~2200%，肉眼点状噪光）。
  /// 代价：显存/填充 ×2.3；派单（1.70 族）不变。细节与量测见 docs/46 §3.9。
  static const List<double> kViewFamilies = <double>[1.40, 1.70];

  /// 这一帧该用哪一族（取第一个 ≥ cam.s 的族）
  static double viewFamilyS(double camS) {
    for (final double f in kViewFamilies) {
      if (camS <= f + 1e-6) return f;
    }
    return kViewFamilies.last;
  }

  /// 平台视图的**固定布局矩形**（族尺寸，中心仍是 `cam.screenCenter`）。
  /// 视觉上的大小/位置由 `Transform.scale(cam.s / 族尺寸)` 表达。
  static Rect viewRect(double familyS, Cam cam, Size size) {
    final Offset center = cam.screenCenter(size);
    final double h = size.height * familyS * StageCalib.kSize;
    final double w = h * kCanvasAspect;
    return Rect.fromCenter(center: center, width: w, height: h)
        .translate(StageCalib.dx, StageCalib.dy);
  }

  /// 模型画布的宽高比（宽 / 高）——`sakiko_orig/models/*.json` 的
  /// `model.canvas = {width: 6000, height: 9000}`。舞台矩形必须与它一致，
  /// 否则插件按宽度适配时会把她的头/脚裁掉（见 [stageRect] 注释）。
  static const double kCanvasAspect = 6000 / 9000;

  /// 「戳到她了吗」——原型 `Stage.hit(x, y)`（stage.js）的**宽度曲线**近似：
  /// 头窄 → 肩最宽 → 裙摆再宽一点。
  ///
  /// ```js
  /// const h = b.y - a.y, f = clamp((y - a.y) / h, 0, 1);   // 0 头顶 → 1 脚底
  /// const w = h * G.half * lerp(.42, 1, min(1, f/.24)) * (f > .5 ? lerp(1, 1.15, (f-.5)/.5) : 1);
  /// return Math.abs(x - a.x) < w;
  /// ```
  /// ⚠️ 原型的 `G.half`（0.30）在这里是**相对她身高**的比例，不是她的真实半宽
  /// （真实半宽约 0.15×身高）—— 即原型的命中框本来就**明显放大**，
  /// 为的是"随手一戳就中"。这里照抄同样的宽松度，**别"顺手修正"收紧**。
  ///
  /// [rect] 传 [stageRect]（= 整张画布 = 她的包围盒，顶≈头发、底≈脚）。
  static bool hitHer(Offset p, Rect rect) {
    if (rect.height <= 0) return false;
    final double f = (p.dy - rect.top) / rect.height;
    if (f < 0 || f > 1) return false;
    final double widen = f <= .24
        ? _lerp(.42, 1, f / .24)
        : (f > .5 ? _lerp(1, 1.15, (f - .5) / .5) : 1);
    final double halfW = rect.height * _kHitHalfRatio * widen;
    return (p.dx - rect.center.dx).abs() < halfW;
  }

  /// 原型的 `G.half` 原值（0.30；语义见 [hitHer] 注释）
  static const double _kHitHalfRatio = .30;

  static double _lerp(double a, double b, double t) =>
      a + (b - a) * t.clamp(0, 1);

  @override
  State<Live2DStage> createState() => _Live2DStageState();
}

/// 标定常数（阈值包围盒法回填；禁截图轮廓量测——HANDOFF 前车之鉴）。
///
/// ⚠️ 语义（2026-10-11 改）：`kSize` 现在是**矩形高 / (屏高 × cam.s)** 的系数，
/// 而矩形本身已经按画布比例（2:3）展开。因为插件按画布宽度适配，她的实际
/// 身高 = 矩形宽 × (她的画布高占比)，所以 kSize 要按实测反解，不再是"1.0
/// 就正好 92%"。
///
/// 标定流程（真机，iOS）：
///  1. 应用内把 [Live2DStage] 挂到画布比例的矩形上（已是默认路径）；
///  2. `xcrun devicectl device capture screenshot --device <UDID> --destination shot.png`
///  3. `python tools/ref/calib_alpha.py --png shot.png --logical 430x932`
///     （阈值包围盒 → 反解 kSize/dx/dy 建议值）
///  4. 回填这里，热重载复查（她完整可见后，量到的不再是裁剪框）。
class StageCalib {
  const StageCalib._();

  /// 矩形高 / (屏高 × cam.s)（见类注释；由真机实测反解）
  static const double kSize = 1.0;

  /// 中心平移（逻辑像素；alpha 包围盒中心与 `Cam.screenCenter` 的差）
  static const double dx = 0;
  static const double dy = 0;
}

class _Live2DStageState extends State<Live2DStage> {
  final Live2DViewController _ctrl = Live2DViewController();
  final math.Random _rnd = math.Random();

  /// 待机池心情（原型 `Stage.idleMood`：cold / pleased / neutral）
  String _idleMood = 'neutral';
  Timer? _idleTimer;

  /// 加载失败（不再尝试，把平台视图从树里摘掉，退回剪影）
  ///
  /// ⚠️ 只在**加载流程结束之后**才可能为真 —— 那时 surface 早就建好了，
  ///    所以这样收掉是安全的；换成一开始就 `Opacity(0)` 会死锁（见 build 的注释）。
  bool _failed = false;
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 待机池轮播（原型 `Stage.tick` L410-412：`idle.next = t + rand(7,15)`，
  /// 优先级 1 不抢主动作）。睡眠期间（开机闭眼）池子暂停 —— 原型的睡姿
  /// 由 boot 流程持有，不会被待机小动作打扰。
  void _startIdleLoop() {
    _idleTimer?.cancel();
    _idleTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted || _failed || _sleeping) return;
      final DateTime now = DateTime.now();
      if (now.isBefore(_nextIdleAt)) return;
      _nextIdleAt = now.add(Duration(seconds: 7 + _rnd.nextInt(9)));
      // docs/24 §3：待机条目 = 动作组 + 表情（原来只播动作不带脸）
      final List<Perf> pool =
          StageBridges.idlePool[StageBridges.poolOf(_idleMood)] ??
          StageBridges.idlePool['neutral']!;
      // 不连播同一个组（原来纯随机，可能连续两次同一个动作）
      int j = _rnd.nextInt(pool.length);
      if (pool.length > 1 && pool[j].group == _lastIdleGroup) {
        j = (j + 1) % pool.length;
      }
      final Perf p = pool[j];
      _lastIdleGroup = p.group;
      final int ix = _rnd.nextInt(Live2DStage.countOf(p.group));
      debugPrint(
        '[stage] 待机表演 → ${p.group}[$ix]+${p.exp}'
        '（心情 $_idleMood，下次 ${_nextIdleAt.second}s）',
      );
      unawaited(_handle?.idlePerf(p));
    });
  }

  /// 上一次待机播的动作组（避免连播；docs/24 §3「可选加强」）
  String? _lastIdleGroup;

  /// 舞台把手（待机池要走它的表情借还；加载完成后创建）
  Live2DStageHandle? _handle;

  /// 下一次待机小动作的时间（`rand(7,15)s`，原型 stage.js L411）
  DateTime _nextIdleAt = DateTime.now().add(const Duration(seconds: 4));

  /// 开机睡姿持有期间为真（[Live2DStageHandle.sleep] / [wakeEyes] 驱动）
  bool _sleeping = false;

  @override
  void reassemble() {
    super.reassemble();
    _startIdleLoop();
  }

  Future<void> _load() async {
    debugPrint('[stage] 开始加载 ${Live2DStage.modelDir}${Live2DStage.modelFile}');
    try {
      // ⚠️ 第一条命令必须等原生视图就绪，否则报 VIEW_NOT_ATTACHED
      await _ctrl.whenAttached;
      // ⚠️ **绝对路径**喂模型：绕开插件那份无内容指纹的 asset 缓存
      //    （见 [resolveModelDir] 注释）；解压失败退回资产目录由插件自理。
      String modelDirArg = Live2DStage.modelDir;
      try {
        modelDirArg = await Live2DStage.resolveModelDir();
      } on Object catch (e) {
        debugPrint('[stage] 自管解压失败（退回插件资产缓存）：$e');
      }
      debugPrint('[stage] 原生视图已就绪 → loadModel');
      // ⚠️ 原生侧 `nativeLoadModel` 有竞态：GL 上下文/surface 就绪的时机稍有不同
      //    就会返回 false（同一份数据时而 true 时而 false）。所以重试几次，
      //    每次之间让出一段时间，等渲染线程把 EGL surface 挂好。
      bool ok = false;
      for (int i = 0; i < 5 && !ok; i++) {
        if (i > 0) await Future<void>.delayed(Duration(milliseconds: 400 * i));
        ok = await _ctrl.loadModel(
          modelDir: modelDirArg,
          modelFileName: Live2DStage.modelFile,
        );
        debugPrint(
          '[stage] loadModel 第 ${i + 1} 次 → $ok '
          '(${_ctrl.value.lastError?.code ?? '-'} '
          '${_ctrl.value.lastError?.message ?? ''})',
        );
      }
      if (!mounted) return;
      if (ok) {
        // 常驻基底：`Idle` 别名组（mtn_idle01_C，插件对字面 "Idle" 循环播放、
        // 播完自动兜底回来 —— 2026-10-11 表演补完，STAGE-OPTIONS 有根因）。
        // 对照原型 stage.js L167 `playMotion(defaultMotion, {loop:true})`。
        unawaited(
          _ctrl.startMotion(
            group: Live2DStage.useHiyoriControl ? 'Idle' : Live2DStage.baseGroup,
            priority: 1,
          ),
        );
        final int ei = Live2DStage.expressionIndex('exp_idle01');
        if (ei >= 0) unawaited(_ctrl.setExpression(ei));
        _startIdleLoop();
        _handle = Live2DStageHandle(
          _ctrl,
          (String m) => _idleMood = m,
          (bool s) => _sleeping = s,
        );
        widget.onReady?.call(_handle!);
      } else {
        _fail();
      }
    } on Object catch (e) {
      debugPrint('[stage] 模型加载失败：$e');
      _fail();
    }
  }

  void _fail() {
    if (_reported) return;
    _reported = true;
    if (mounted) setState(() => _failed = true);
    widget.onFailed?.call();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _handle?.dispose(); // 表情借还的定时器
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    // 确认加载失败 → 把平台视图摘掉，让舞台露出下面的全息剪影。
    // ⚠️ 只有**加载流程结束**后才可能走到这里 —— 那时 surface 早建好了，
    //    所以摘掉是安全的；反过来"一开始就 opacity 0"会死锁（见下）。
    if (_failed) return const SizedBox.shrink();
    // ⚠️⚠️ **一开始就必须让它可见，绝不能 opacity: 0。**
    //
    //    踩过的坑（第二轮才定位到）：`flutter_live2d` 的原生侧把 loadModel
    //    排进渲染线程的队列，而那个队列**只对 EGL surface 已就绪的视图执行**：
    //
    //        if (target != null && target.eglSurface != EGL14.EGL_NO_SURFACE) action()
    //
    //    surface 来自 `TextureView.onSurfaceTextureAvailable` —— 也就是**必须真的
    //    参与绘制**才会有。而 Flutter 的 `Opacity(0)` 不会画子树，于是：
    //      opacity 0 → surface 不创建 → loadModel 永不执行 → `await` 永远不返回。
    //    症状是日志停在「原生视图已就绪 → loadModel」，之后一片安静。
    //
    //    可见性改成：**加载前/加载中都可见**（GL 清成透明，画出模型前本来就看不见，
    //    不会闪），只有**确认失败**才收掉，露出下面的全息剪影。
    //
    // ⚠️ **几何相机 = 固定布局矩形 + Transform（docs/18 §1.5.3 · 2026-10-11 改）**
    //    原来是"每帧把矩形改成 cam.s 那么大"——平台视图的布局尺寸一变，插件
    //    iOS 侧就重建 FBO（见 [Live2DStage.kViewFamilies] 的注释），推镜头那段
    //    她基本不渲染，落点像"直接切过去"（宿主验收原话）。
    //    现在矩形只按**族**定尺寸（罕见地换），缩放用 `Transform.scale` 表达：
    //    绕中心缩放与"把矩形改成 cam.s 那么大"几何等价，而 Flutter 的
    //    `UiKitView` 官方支持 transform/clip/opacity —— 于是推镜头是每帧连续的。
    //    ⚠️ 注意：这里说的"禁 Transform/Opacity"是旧结论（saveLayer 吞平台视图），
    //    对当前 iOS `UiKitView` 路线不成立；`Opacity` 仍然别套（会用 saveLayer），
    //    但 `Transform` 是安全的。
    return Positioned.fill(
      child: IgnorePointer(
        // ⚠️ 2026-10-11 改：**不吃触摸了**（原来是 true）。
        //
        // 原因：插件的平台视图自带"眼睛/头跟着手指"（`Live2DGLView.touches*`
        // → `wrapper.touchBegan/Moved` → DragManager → 每帧给头/身角度加偏移），
        // 这正是原型 `Stage.pointer(x,y)` + `look('pointer')` 那一拍。原来的
        // `ignoring: true` 把这条路整个掐断了 —— 宿主验收："主界面像死人一样，
        // 原型上戳它有反应的"。
        //
        // 为什么现在是安全的：
        //  · 所有可交互 UI（底栏/按钮/选项/输入框）都在她**之上**，它们的
        //    GestureDetector 先命中并吃下事件，不受影响；
        //  · 「戳她」的命中层用的是 translucent 的 `Listener`（main.dart）——
        //    `Listener` 不参与手势竞技场，所以它和平台视图**两边都能收到**事件：
        //    平台视图驱动跟随，Listener 负责 `Stage.hit` 命中判定 + 背景那套
        //    （记"宿主还在"、跳过打字机）。
        ignoring: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final Size size = Size(c.maxWidth, c.maxHeight);
            final double familyS = Live2DStage.viewFamilyS(widget.cam.s);
            final Rect rect = Live2DStage.viewRect(familyS, widget.cam, size);
            // 视觉缩放 = cam.s / 族尺寸（恒 ≤ 1）；中心不变 → 与改矩形等价
            final double k = widget.cam.s / familyS;
            return Stack(
              children: <Widget>[
                Positioned.fromRect(
                  rect: rect,
                  child: Transform.scale(
                    scale: k,
                    child: Live2DView(controller: _ctrl),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
