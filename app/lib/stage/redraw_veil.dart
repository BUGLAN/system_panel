import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// 「重绘」过场 —— 吃掉**换族那一帧**的平台视图错位（docs/37 §3.5）
///
/// 病根：`Live2DStage.kViewFamilies = [1.05, 1.70]`，而只有派单的 `talk` 用
/// 1.70 族（`camera.dart` 的 `Cam.all`）。于是每次进出委托板，**平台视图的
/// 布局矩形真的改尺寸**（1.70 族 = 780×2870，1.05 族 = 780×1772，`kSize=1.0`）。
/// `矩形 × Transform.scale` 在几何上完全等价，所以画面本该无缝；但 Android
/// 平台视图是真 View/GL surface，**缩小那一帧** Flutter 已按新矩形合成、原生侧
/// 还按旧 surface 出图 → 单帧错位（实测：她头顶 275px → 1088px，同帧纯 Flutter
/// 的 HUD 纹丝不动）。放大方向不闪。
///
/// 宿主 2026-10-13 拍板：「增加动画，不出现这种闪的画面」。于是不去动几何（单族
/// 会把常驻 surface 从 1772px 高撑到 2870px），而是在**换族那一帧**起播一次
/// 一帧不透明、随后 ~110ms 退净的「重绘」过场：
///   · t=0（就是换族那一帧，AnimatedBuilder 同帧读到 controller=0）→ 遮罩满不透明
///   · 一道电光青扫线自下而上掠过（`easeOutCubic`，占前 70%）
///   · 遮罩 90ms 内退净
/// 60fps 下一帧 = 16ms，肉眼本就看不见；这一层把「错位帧」整帧换成一次系统感
/// 的刷新，观感是过场而不是闪。
///
/// 层级纪律：挂在她与环场**之上**、HUD **之下**（main.dart 的 Stack 顺序）——
/// 只盖舞台那两层，台词/底栏/派单板这些本来就正确的 UI 不许跟着闪。
///
/// reduced-motion：不播扫线，只保留 2 帧静态遮罩（不是动效，是切换）。
class StageRedrawVeil extends StatefulWidget {
  const StageRedrawVeil({super.key, required this.family});

  /// 当前帧的族尺寸（`Live2DStage.viewFamilyS(cam.s)`）——由调用方逐帧喂
  final double family;

  @override
  State<StageRedrawVeil> createState() => _StageRedrawVeilState();
}

class _StageRedrawVeilState extends State<StageRedrawVeil>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );

  /// 上一帧的族；首帧只记账不播（挂载那一下不是换族）
  double? _family;
  bool _on = false;

  @override
  void didUpdateWidget(StageRedrawVeil old) {
    super.didUpdateWidget(old);
    if (_family == null) {
      _family = widget.family;
      return;
    }
    if (widget.family != _family) {
      _family = widget.family;
      _on = true;
      // ⚠️ 只能在这里 `forward(from: 0)`：本帧的 builder 随后会读到 value=0
      //    （= 遮罩满不透明），所以**换族的同一帧**就被盖住了。放到 setState /
      //    下一帧再开会晚一帧，那一帧的错位就露出来了。
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_on) return const Positioned.fill(child: SizedBox.shrink());
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _c.duration = reduce
        ? const Duration(milliseconds: 80)
        : const Duration(milliseconds: 240);
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (BuildContext _, Widget? _) {
            final double t = _c.value;
            final double o; // 遮罩不透明度
            final double sweep; // 扫线进度；<0 = 不画
            if (reduce) {
              // 不做动效：只留 3 帧静态切换（80ms 控制器 → 约 3 帧），
              // 一帧都不能少 —— 少的那几帧就是"小号她"露出来的那几帧。
              o = t < .45 ? 1 : 0;
              sweep = -1;
            } else {
              // ⚠️ t=0 就是换族那一帧；**必须满不透明约 3 帧**（实测平台视图
              //    要 2~3 帧才换上新 surface，第 2/3 帧她还被渲染成"小号"）。
              //    3 帧 = 50ms 后开始软退（100ms 内退净）—— 这 50ms 只压她与
              //    天幕，环场/进度带/HUD/台词/底栏都在遮罩**之上**，所以观感是
              //    "她重绘一拍"而不是整屏黑。
              o = 1 - Curves.easeOutCubic.transform(((t - .15) / .40).clamp(0.0, 1.0));
              sweep = t <= .75 ? Curves.easeOutCubic.transform(t / .75) : -1;
            }
            if (o <= 0 && sweep < 0) return const SizedBox.shrink();
            return CustomPaint(painter: _VeilPainter(o: o, sweep: sweep));
          },
        ),
      ),
    );
  }
}

class _VeilPainter extends CustomPainter {
  const _VeilPainter({required this.o, required this.sweep});

  final double o;
  final double sweep;

  @override
  void paint(Canvas canvas, Size size) {
    if (o > 0) {
      canvas.drawRect(
        Offset.zero & size,
        // 深渊蓝而不是纯黑：读作「重绘」而不是黑屏 blink
        Paint()..color = C.abyss.withAlpha((o * 255).round().clamp(0, 255)),
      );
    }
    if (sweep >= 0) {
      final double y = size.height * (1 - sweep); // 自下而上
      final Rect band = Rect.fromLTWH(0, y - 30, size.width, 60);
      canvas.drawRect(
        band,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0x0038E1FF), Color(0x5538E1FF), Color(0x0038E1FF)],
          ).createShader(band),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, y - 1, size.width, 2),
        Paint()..color = C.blue.withAlpha(230),
      );
    }
  }

  @override
  bool shouldRepaint(_VeilPainter old) => old.o != o || old.sweep != sweep;
}
