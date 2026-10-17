import 'package:flutter/material.dart';

/// ═══════════════════════════════════════════════════════════
///  视觉令牌 —— 唯一真源：prototype/opus-v2-dir/css/app.css 的 :root
///  改这里之前先去改原型，两边不许各说各话。
/// ═══════════════════════════════════════════════════════════

/// 颜色（app.css L11-15）
class C {
  const C._();

  // 基底
  static const voidBg = Color(0xFF03060E); // --void
  static const abyss = Color(0xFF060F20); // --abyss
  static const navy = Color(0xFF0B1A36); // --navy
  static const deep = Color(0xFF021022); // --deep

  // 唯一主色 + 冰
  static const blue = Color(0xFF38E1FF); // --blue  电光青
  static const blue2 = Color(0xFF1F8BFF); // --blue2
  static const ice = Color(0xFFE9FBFF); // --ice
  static const mist = Color(0xFF8FA6C4); // --mist
  static const dim = Color(0xFF4B5E7C); // --dim

  // 描边（rgba(56,225,255,α)）
  static const line = Color(0x4238E1FF); // .26
  static const line2 = Color(0x1F38E1FF); // .12

  // 稀有度色谱：只出现在稀有度本身上，不做氛围
  static const rF = Color(0xFF9AA3B2);
  static const rE = Color(0xFF4ADE80);
  static const rD = Color(0xFF38BDF8);
  static const rC = Color(0xFFA78BFA);
  static const rB = Color(0xFFFBBF24);
  static const rA = Color(0xFFFB923C);
  static const rS = Color(0xFFFF4D5E);

  /// 开机屏专用（app.css L527/531/536）
  static const bootTop = Color(0xFF4F6584);
  static const bootLog = Color(0xFF6F86A6);
}

/// 字体族（app.css L16-19 / L6-9）
/// 四个都是可变字体，字重必须在代码里用 fontVariations 指定，
/// 光写 fontWeight 不生效 —— FangYuan 的默认实例是 wght 700。
class F {
  const F._();
  static const cn = 'FangYuan'; // 正文 / 她的话（阿里妈妈方圆体，wght 200-700）
  static const hd = 'ShuHei'; // 标题（阿里妈妈数黑体）
  static const num = 'Tektur'; // 数字（wdth 75-100 / wght 400-900）
  static const mono = 'KodeMono'; // 系统读数（wght 400-700）
}

/// 各字体的 normal 行高 = (hhea.ascent − hhea.descent + hhea.lineGap) / unitsPerEm。
///
/// CSS 里没写 `line-height` 的地方用的就是它。Flutter 的坑：`TextStyle.height` 留空
/// 会**继承 Material 主题的 1.43**，于是每个文字行框都偏高（底栏标签能差 3px）。
/// 所以这里按字体把行高钉死，并且用 [TextLeadingDistribution.even] 复刻 CSS 的
/// 半行距模型（多余空间上下各一半），保证基线位置也一致。
const Map<String, double> kNormalLineHeight = <String, double>{
  F.cn: 1.20, // FangYuan  850/150/200
  F.hd: 1.40, // ShuHei   1050/150/200
  F.num: 1.30, // Tektur  1000/300/0
  F.mono: 1.28, // KodeMono 980/300/0
};

/// CSS `font:` 简写的 Dart 对应物。
/// [ls] 是 letter-spacing 的**像素**值；em 值请用 [em] 换算。
/// [height] 不传就按字体取 normal 行高（见 [kNormalLineHeight]）。
TextStyle fs({
  required String family,
  required double size,
  double wght = 400,
  double? wdth,
  double? ls,
  double? height,
  Color? color,
  Paint? foreground,
  List<Shadow>? shadows,
}) {
  return TextStyle(
    fontFamily: family,
    fontSize: size,
    height: height ?? kNormalLineHeight[family] ?? 1.2,
    leadingDistribution: TextLeadingDistribution.even,
    letterSpacing: ls,
    color: foreground == null ? color : null,
    foreground: foreground,
    shadows: shadows,
    fontVariations: <FontVariation>[
      FontVariation('wght', wght),
      if (wdth != null) FontVariation('wdth', wdth),
    ],
  );
}

/// CSS 的 em → 像素
double em(double size, double emValue) => size * emValue;

/// 缓动（app.css L22）
const kOut = Cubic(0.16, 1, 0.3, 1);

/// easeInOutCubic（util.js L85 `ease.inOutCubic` 的 Flutter 等价物）
const kInOut = Cubic(0.65, 0, 0.35, 1);

/// ═══════════════════════════════════════════════════════════
///  动效令牌（docs/39 §5.1「令牌先加进 design/tokens.dart，再改组件」）
///
///  四层：Touch / Respond / Scene / Payoff。改动画前先在这里找档位，
///  **不许在组件里再写字面量时长** —— 同一个动作两处不同时长就是「不统一」。
/// ═══════════════════════════════════════════════════════════
class Motion {
  const Motion._();

  // ── Touch：按下 0ms 到、抬起 120ms 回 ──────────────────────
  static const int touchMs = 0;
  static const int releaseMs = 120;

  // ── Respond：状态切换、小反馈 120–160ms ────────────────────
  static const int respondMs = 140;

  // ── Scene：内容 320ms / 相机 + chrome 520ms ───────────────
  static const int sceneContentMs = 320;
  static const int sceneChromeMs = 520;

  // ── Payoff：接单 / 结算 / 升级 / 进度收割 ─────────────────
  static const int harvestMs = 600; // 进度收割（弧增长）
  static const int stampMs = 280; // 接单压印
  static const int levelUpMs = 780; // 跨级编排（360 + 180 + 420）

  // ── 系统心跳：只驱动 CTA 呼吸 / 进度带弧头 / 挂签光点 ────────
  static const int heartMs = 2400;

  // ── 牌屉开 / 关 / 压暗 ───────────────────────────────────
  static const int drawerOpenMs = 420;
  static const int drawerCloseMs = 260;
  static const int scrimMs = 200;

  // ── 物理弹簧（docs/39 §5.1）───
  static const double cardTableK = 120;
  static const double cardTableZeta = .9;
  static const double cameraK = 70;
  static const double cameraZeta = .95;

  /// 过冲上限（§5.1「过冲 ≤1.08」）
  static const double maxOvershoot = 1.08;

  /// 退场 = 进场的 60%（§5.1「退场 = 进场的 60%」）
  static const double exitRatio = .6;

  /// 同屏最多几个可感知循环（她 + 心跳 = 2，其余 ≥18s 归环境层）
  static const int maxLooping = 2;
}

/// 舞台锚点。
///
/// 原型里这些值由 Live2D 模型实测比例 + 镜头矩阵算出（`Stage.toScreen`），
/// 模型还没移植，所以这里固定为**运行中原型量出来的 boot 镜头值**：
///   Stage.W×H = 390×844，eyes=(195, 227.93)，chest=(195, 375.67)，bodyH=540.16
/// 模型落地后这一层要改成由舞台实时提供。
class StageAnchors {
  const StageAnchors._();

  /// 设计基准尺寸（原型 #phone 的逻辑尺寸）
  static const double w = 390;
  static const double h = 844;

  static const Offset eyes = Offset(195, 227.93);
  static const Offset chest = Offset(195, 375.67);

  /// 按实际屏幕高换算后的比例（锚点的 y 跟着镜头走，x 永远居中）
  static const double eyesFracY = 227.93 / 844;
  static const double chestFracY = 375.67 / 844;
}

/// 背景大字的参数（flows.js `setWord`）
/// 字号与缩放跟屏幕无关，是设计常量；位置跟着舞台的 chest 锚点走。
class WordSpec {
  const WordSpec._();

  /// 拉丁判定：显式传了 latin，或整串都是大写字母数字
  static bool isLatin(String text, {bool latin = false}) =>
      latin || RegExp(r'^[A-Z0-9\-−]+$').hasMatch(text);

  /// latin:  Math.round(Math.min(120, 560 / len))
  /// 中文:   Math.round(Math.min(175, 360 / len))
  static double fontSize(String text, {bool latin = true}) {
    final int len = text.isEmpty ? 1 : text.runes.length;
    final double cap = latin ? 120 : 175;
    final double span = latin ? 560 : 360;
    return (span / len).clamp(0, cap).roundToDouble();
  }

  static const double scale = 0.910;
}
