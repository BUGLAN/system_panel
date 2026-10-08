import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_live2d/flutter_live2d.dart';

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
  Live2DStageHandle(this._ctrl, [this._onIdleMood]);

  final Live2DViewController _ctrl;

  /// 待机池心情落回 state（原型 `Stage.idleMood = mood`）
  final void Function(String mood)? _onIdleMood;

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

  /// 情绪入口（原型 `Stage.emote(name)`）：查 [StageBridges.emoExp]
  /// 下发表情；`sleep` 额外把动作停住（docs/18 §1.5.4：idle speed 0）。
  Future<void> emote(String name) async {
    final int i = StageBridges.moodIndex(name);
    if (i >= 0) await expression(i);
    speed(name == 'sleep' ? 0 : 1);
  }

  /// 动作入口（原型 `Stage.motion(verb)`）：动词→动作组；自带表情覆盖的
  /// （poke → exp_shy01）先下发表情。
  Future<void> act(String verb) async {
    final int xi = StageBridges.verbExpIndex(verb);
    if (xi >= 0) await expression(xi);
    await motion(StageBridges.groupOf(verb), priority: 2);
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

  /// `model3.json` 里 `Expressions` 的顺序。
  ///
  /// 插件只收**下标**不收名字，所以这里留一份名字表供调用方按名字查。
  /// ⚠️ 顺序由 `tools/l2d/convert.py` **按名字排序**写出（prefab 里的原序是随机的，
  ///    不可依赖），所以这张表就是字母序。**改了转换器就要同步这里** ——
  ///    `test/live2d_stage_test.dart` 会拿实际生成的 `model3.json` 来核对。
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
  ];

  /// 按名字取表情下标（找不到给 -1）
  static int expressionIndex(String name) => expressions.indexOf(name);

  /// ── 相机矩形（docs/18 §1.5.3 布局矩形复刻相机）──────────────────
  ///
  /// 她**应占**的屏幕矩形：中心 = `Cam.screenCenter`，高 = 屏高 × `Cam.s`。
  /// 数学对照（大厅 s=.92、syF=.505）：top = .505H − .46H = 4.5%H、
  /// bottom = 96.5%H —— 与原型"大厅她占屏高 92%、顶 4.5% 底 96.5%"一致。
  ///
  /// 插件在视图内如何框住模型没有 API 可查，误差全部吸收进 [StageCalib]
  /// 这三个常数 —— 由 `tools/ref/calib_alpha.py`（alpha 包围盒法）实测回填。
  static Rect stageRect(Cam cam, Size size) {
    final Offset center = cam.screenCenter(size);
    final double side = size.height * cam.s * StageCalib.kSize;
    return Rect.fromCenter(center: center, width: side, height: side)
        .translate(StageCalib.dx, StageCalib.dy);
  }

  @override
  State<Live2DStage> createState() => _Live2DStageState();
}

/// 标定常数（alpha 包围盒法回填；禁截图轮廓量测——HANDOFF 前车之鉴）。
///
/// 标定流程（app/STAGE-OPTIONS.md「MuMu · 原生舞台标定」节）：
///  1. `flutter run -d 127.0.0.1:16512` 进大厅；
///  2. `python tools/ref/calib_alpha.py --device 127.0.0.1:16512`
///     （截图 → alpha/亮度阈值包围盒 → 反解常数建议值）；
///  3. 把建议值回填到这里，热重载复查。
class StageCalib {
  const StageCalib._();

  /// 视图边长 × 系数（1.0 = 矩形高恰好等于她应占屏高；模型在视图内不满铺就 >1）
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

  /// 待机池轮播（原型 `Stage.tick` L412 的 pools：优先级 1，不抢主动作）。
  /// 间隔照原型的"动作播完歇一下"节奏随机化，避免机械感。
  void _startIdleLoop() {
    _idleTimer?.cancel();
    _idleTimer = Timer.periodic(const Duration(milliseconds: 900), (Timer t) {
      if (!mounted || _failed) return;
      if (t.tick % 9 != _idleSlot) return; // ≈8s 上下随机一拍
      final List<String> pool =
          StageBridges.idlePool[StageBridges.poolOf(_idleMood)] ??
          StageBridges.idlePool['neutral']!;
      final String group = pool[_rnd.nextInt(pool.length)];
      unawaited(_ctrl.startMotion(group: group, priority: 1));
    });
  }

  /// 每次启动错开一拍，避免多实例同步轮播
  static final int _idleSlot = DateTime.now().second % 9;

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
      debugPrint('[stage] 原生视图已就绪 → loadModel');
      // ⚠️ 原生侧 `nativeLoadModel` 有竞态：GL 上下文/surface 就绪的时机稍有不同
      //    就会返回 false（同一份数据时而 true 时而 false）。所以重试几次，
      //    每次之间让出一段时间，等渲染线程把 EGL surface 挂好。
      bool ok = false;
      for (int i = 0; i < 5 && !ok; i++) {
        if (i > 0) await Future<void>.delayed(Duration(milliseconds: 400 * i));
        ok = await _ctrl.loadModel(
          modelDir: Live2DStage.modelDir,
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
        // 默认待机动作与表情（与游戏剧情里一致：`mtn_idle01_C` / `exp_idle01`）
        unawaited(
          _ctrl.startMotion(
            group: Live2DStage.useHiyoriControl ? 'Idle' : 'idle',
            priority: 1,
          ),
        );
        final int ei = Live2DStage.expressionIndex('exp_idle01');
        if (ei >= 0) unawaited(_ctrl.setExpression(ei));
        _startIdleLoop();
        widget.onReady?.call(
          Live2DStageHandle(_ctrl, (String m) => _idleMood = m),
        );
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
    // ⚠️ **几何相机 = 布局矩形复刻（docs/18 §1.5.3）**：平台视图外禁套
    //    Transform/Opacity（saveLayer 会吞掉平台视图），所以相机的缩放/平移
    //    全部落进 `Positioned.fromRect` 的布局矩形 —— 平台视图随布局尺寸变化
    //    是安全路径。矩形每帧由 `Cam`（弹簧推镜头）给出，随 build 刷新。
    return Positioned.fill(
      child: IgnorePointer(
        // 平台视图是 opaque 的，会吃掉触摸；这里不吃，交给上面那层 Flutter UI
        ignoring: true,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final Size size = Size(c.maxWidth, c.maxHeight);
            final Rect rect = Live2DStage.stageRect(widget.cam, size);
            return Stack(
              children: <Widget>[
                Positioned.fromRect(rect: rect, child: Live2DView(controller: _ctrl)),
              ],
            );
          },
        ),
      ),
    );
  }
}
