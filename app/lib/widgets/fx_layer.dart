import 'dart:math' as math;

import 'package:flutter/material.dart';

/// ═══════════════════════════════════════════════════════════
///  FX 层（app.css L89-91 + js/fx.js L47-61）
///  `#flash` = 全屏亮帧，`#shake` = 震屏。两者都 `inset:0`、都不吃点击。
///
///  亮帧的参数是定死的：**白 · 16% · 180ms ease-out**，
///  结算/发布那一帧踩的就是它（`docs/08` 逐帧编排里写作「亮帧」）。
/// ═══════════════════════════════════════════════════════════

/// `#flash` —— 一帧打亮整屏，然后 180ms 淡出。
/// `#flash { opacity: 0; mix-blend-mode: screen }`，JS 设 `background` 与 `opacity`
/// 后下一帧开始 `transition: opacity Nms ease-out` 收到 0。
class FlashLayer extends StatelessWidget {
  const FlashLayer({
    super.key,
    this.alpha = 0,
    this.color = Colors.white,
    this.reduceMotion = false,
  });

  /// 当前这一帧的不透明度（0 = 没在闪）
  final double alpha;

  final Color color;

  /// `prefers-reduced-motion` → 原型把强度砍半
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final double a = reduceMotion ? alpha * .5 : alpha;
    return Positioned.fill(
      child: IgnorePointer(
        child: a <= 0
            ? const SizedBox.shrink()
            // `mix-blend-mode: screen` —— 用 saveLayer 把这层按 screen 合成，
            // 不能直接画半透明白（在亮的地方会比原型暗）
            : CustomPaint(
                painter: FlashPainter(color.withAlpha((a * 255).round())),
              ),
      ),
    );
  }
}

class FlashPainter extends CustomPainter {
  const FlashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = Offset.zero & size;
    canvas.saveLayer(r, Paint()..blendMode = BlendMode.screen);
    canvas.drawRect(r, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant FlashPainter old) => old.color != color;
}

/// `#shake` —— 整屏抖，幅度随时间线性衰减到 0。
/// `k = (1-p) × px`，每帧 `translate(rand(-k,k), rand(-k,k))`；
/// `reduceMotion` 下原型直接不抖。
class ShakeLayer extends StatefulWidget {
  const ShakeLayer({
    super.key,
    required this.child,
    this.token = 0,
    this.px = 4,
    this.ms = 240,
    this.reduceMotion = false,
  });

  final Widget child;

  /// 每加一次就抖一次（原型是命令式调用 `FX.shake()`）
  final int token;

  /// 起始幅度（px）
  final double px;

  final int ms;
  final bool reduceMotion;

  @override
  State<ShakeLayer> createState() => _ShakeLayerState();
}

class _ShakeLayerState extends State<ShakeLayer>
    with SingleTickerProviderStateMixin {
  final math.Random _rnd = math.Random();

  /// ⚠️ **把整棵子树用 GlobalKey 钉住** —— 抖/不抖之间切换 `Transform`
  /// 分支时，子树是「搬过去」（全部 State 原样保留）而不是「重挂」。
  ///
  /// **不钉的代价就是「提交任务卡死」的真正元凶**：结算砸印必抖
  /// （`onImpact` 最小 shakePx=4）→ 抖动切换 `Transform` 分支 → 整个
  /// Stack 连 Plate / 结算面板 / Live2D WebView 一起重挂 → 结算演出从头
  /// 重播 → 820ms 后又砸印又抖 → **死循环**，演出永远走不到结算卡。
  /// 实测症状：结算页卡在稀有度大字 + 粒子越积越多、WebView 反复重载、
  /// 派单板的骰子也永远在滚（`onRankFx` 的 A/S 抖同理）。
  final GlobalKey _subtreeKey = GlobalKey();

  /// ⚠️ 必须用 AnimationController，不能用 `Future.delayed` + `DateTime.now()`——
  /// 那样跑的是真实时钟，widget test 的假时钟推不动它（踩过：测试里抖完不归位）。
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.ms),
  )..addListener(_tick);

  double _dx = 0;
  double _dy = 0;
  int _seen = 0;

  @override
  void initState() {
    super.initState();
    _seen = widget.token;
    if (_seen > 0 && !widget.reduceMotion) _c.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant ShakeLayer old) {
    super.didUpdateWidget(old);
    if (widget.token != _seen) {
      _seen = widget.token;
      if (!widget.reduceMotion) {
        _c.duration = Duration(milliseconds: widget.ms);
        _c.forward(from: 0);
      }
    }
  }

  /// `k = (1-p) × px`，每帧 `translate(rand(-k,k), rand(-k,k))`
  void _tick() {
    final double p = _c.value;
    if (p >= 1) {
      setState(() => _dx = _dy = 0); // 原型 `s.style.transform = ''`
      return;
    }
    final double k = (1 - p) * widget.px;
    setState(() {
      _dx = (_rnd.nextDouble() * 2 - 1) * k;
      _dy = (_rnd.nextDouble() * 2 - 1) * k;
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ **不抖的时候绝不套 `Transform`。**
    //
    // 这层包住了整个 App（含 Live2D 平台视图）。平台视图**无法应用任意变换** ——
    // 只要祖先链上有一个 `Transform`，Flutter 的合成器就干脆**不合成它**，
    // 于是"模型加载成功、渲染循环在跑、视图也在层级里，但屏幕上什么都没有"。
    // 这个坑很贵：我为它排查了两轮（换标准模型 Hiyori 做对照才排除掉模型数据的问题）。
    //
    // 代价：真抖的那 240ms 里她不会跟着抖（平台视图跟不上）。
    // 目前接受 —— 先把"她出得来"这件事做对，抖不抖是后面的事。
    //
    // ⚠️ 两个分支的**共同子层**必须带同一个 GlobalKey（见 _subtreeKey 注）：
    // 分支切换 = 「搬子树」而不是「重建子树」。
    final Widget child = KeyedSubtree(key: _subtreeKey, child: widget.child);
    if (_dx == 0 && _dy == 0) return child;
    return Transform.translate(offset: Offset(_dx, _dy), child: child);
  }
}
