import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_live2d/flutter_live2d.dart';

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
///    世界空间里的仿射（缩放 + 平移，`stage.js` `_camMul`），所以这里用
///    **`Transform` 包住视图**来复刻 —— 对纯缩放+平移来说两者等价。
/// 3. **加载失败要能降级。** 模型目录不入库（版权），新克隆没跑转换器时会
///    `LOAD_FAILED`；这时整层收掉，让舞台退回全息剪影（原型也有这个降级）。
/// ═══════════════════════════════════════════════════════════

/// 舞台对外的把手：给页面驱动"她现在什么表情、做什么动作"。
class Live2DStageHandle {
  Live2DStageHandle(this._ctrl);

  final Live2DViewController _ctrl;

  bool get isReady => _ctrl.value.isLoaded;

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
}

class Live2DStage extends StatefulWidget {
  const Live2DStage({
    super.key,
    this.visible = true,
    this.scale = 1,
    this.offset = Offset.zero,
    this.onReady,
    this.onFailed,
  });

  final bool visible;

  /// 相机给的缩放 / 平移（`camera.dart` 算出来的那一套）
  final double scale;
  final Offset offset;

  /// 模型加载好了（把把手交出去）
  final ValueChanged<Live2DStageHandle>? onReady;

  /// 加载失败（拿不到模型就退回剪影）
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

  @override
  State<Live2DStage> createState() => _Live2DStageState();
}

class _Live2DStageState extends State<Live2DStage> {
  final Live2DViewController _ctrl = Live2DViewController();

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
        widget.onReady?.call(Live2DStageHandle(_ctrl));
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
    return Positioned.fill(
      child: IgnorePointer(
        // 平台视图是 opaque 的，会吃掉触摸；这里不吃，交给上面那层 Flutter UI
        ignoring: true,
        // ⚠️ **平台视图外面不要套 `AnimatedOpacity` / `Transform`。**
        //    hybrid composition 下这些会走 saveLayer，平台视图可能整个不画
        //    （实测：模型加载成功但屏幕上什么都没有）。
        //    相机的缩放/平移得另想办法，见文件末尾的 TODO。
        child: Live2DView(controller: _ctrl),
      ),
    );
  }
}
