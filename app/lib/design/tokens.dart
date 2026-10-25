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

/// ═══════════════════════════════════════════════════════════
///  设计系统 v2「舞台 HUD」—— 2026-10-25 UI 重设计（docs/48）
///
///  一句话：**她是舞台，界面是 HUD**。所有 v2 令牌都围绕这条展开：
///   · 颜色分三层 —— 舞台光（只属于她：青辉/暖边光）、HUD 墨层（界面底）、
///     奖励色（金 / 暴击品红，只在「得到」那一拍出现）
///   · 卡片是唯一允许有「材质」的东西（全息箔 + 镜面高光 + 边缘光）
///   · 动效四档沿用 [Motion]；v2 只补**曲线**和**弹簧预设**的名字
///   · 音效有**触发规则**（[SoundRule]）：哪些动作出声、多响、多密
///
///  ⚠️ 旧令牌（[C] / [F] / [Motion]）一个不删、数值不改：测试与历史文档
///     都锚在它们上面。v2 只**新增**，组件逐个迁移。
/// ═══════════════════════════════════════════════════════════

/// v2 调色板（在 [C] 之上的语义层）
class Pal {
  const Pal._();

  // ── HUD 墨层：由深到浅 4 级（界面底，永远比她暗）─────────────
  static const Color ink0 = Color(0xFF02050C); // 最底（屏幕边缘/暗角）
  static const Color ink1 = Color(0xFF060C1A); // 卡底 · 远
  static const Color ink2 = Color(0xFF0B1528); // 卡底 · 近
  static const Color ink3 = Color(0xFF13213B); // 抬起面（领位卡顶部）

  // ── 舞台光：只属于她 ─────────────────────────────────────
  /// 主辉光（背光）—— 与 [C.blue] 同族但更冷更柔
  static const Color halo = Color(0xFF5BE6FF);

  /// 暖边光（右上方的 key light，给她一圈「被照亮」的轮廓）
  static const Color rim = Color(0xFFFFD3A1);

  /// 地台光
  static const Color dais = Color(0xFF38E1FF);

  // ── 奖励色：只在「得到」那一拍 ────────────────────────────
  static const Color gold = Color(0xFFFBBF24); // = 稀有度 B 金（不新增主题色）
  static const Color goldDeep = Color(0xFFB7791F);
  static const Color crit = Color(0xFFFF4FA3);
  static const Color violet = Color(0xFF9B7BFF);

  // ── 文本层级（压在墨层上）──────────────────────────────────
  static const Color text1 = Color(0xFFF2FBFF); // 标题
  static const Color text2 = Color(0xFFB9CCE4); // 正文
  static const Color text3 = Color(0xFF7489A8); // 注释
  static const Color text4 = Color(0xFF475A78); // 禁用

  /// 全息箔的彩虹三段（青 → 紫 → 金），只给卡面箔层用
  static const List<Color> foil = <Color>[
    Color(0xFF38E1FF),
    Color(0xFF9B7BFF),
    Color(0xFFFF7AC8),
    Color(0xFFFFC857),
    Color(0xFF38E1FF),
  ];

  /// 舞台情绪色：按当前时刻给她的背光换色（[StageMood]）
  static Color moodHalo(StageMood m) => switch (m) {
    StageMood.calm => halo,
    StageMood.focus => const Color(0xFF3FD0FF),
    StageMood.talk => const Color(0xFF7FE9FF),
    StageMood.reward => gold,
    StageMood.fail => const Color(0xFFB84A5E),
    StageMood.sleep => const Color(0xFF3A5D8F),
  };
}

/// 舞台情绪（驱动背光色 / 呼吸速度 / 地台亮度）
enum StageMood { calm, focus, talk, reward, fail, sleep }

/// 间距 4 点栅格
class Space {
  const Space._();
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;

  /// 屏幕左右安全边距（HUD / CTA 统一用它）
  static const double gutter = 20;
}

/// 圆角
class Radii {
  const Radii._();
  static const double chip = 8;
  static const double card = 14;
  static const double panel = 22;
  static const double pill = 999;

  /// HUD 斜切角（cut-corner）—— 游戏按钮的身份
  static const double cut = 12;
}

/// 落影 / 辉光预设（全部是**单层**阴影：多层大半径阴影是 GPU 大户）
class Elev {
  const Elev._();

  /// 贴地：侧位卡、底栏按键
  static const List<BoxShadow> low = <BoxShadow>[
    BoxShadow(color: Color(0x80000000), offset: Offset(0, 6), blurRadius: 14),
  ];

  /// 抬起：领位卡、弹层
  static const List<BoxShadow> high = <BoxShadow>[
    BoxShadow(
      color: Color(0xB3020510),
      offset: Offset(0, 18),
      blurRadius: 34,
      spreadRadius: -6,
    ),
  ];

  /// 彩色辉光（领位卡底下那团「悬浮光」/ 主按钮外辉）
  static List<BoxShadow> glow(Color c, {double a = .45, double r = 26}) =>
      <BoxShadow>[
        BoxShadow(
          color: c.withAlpha((a * 255).round()),
          blurRadius: r,
          spreadRadius: -r * .35,
        ),
      ];
}

/// 曲线（与 [Motion] 的时长档配对使用）
class Ease {
  const Ease._();

  /// 进场：快出慢停（= [kOut]）
  static const Curve enter = kOut;

  /// 退场：慢起快走
  static const Curve exit = Cubic(.7, 0, .84, 0);

  /// 强调：带一点点过冲（≤1.08，见 [Motion.maxOvershoot]）
  static const Curve pop = Cubic(.34, 1.36, .64, 1);

  /// 舞台慢推（= [kInOut]）
  static const Curve glide = kInOut;

  /// 呼吸（正弦感，用于循环）
  static const Curve breathe = Cubic(.45, .05, .55, .95);
}

/// 弹簧预设（名字 → 刚度/阻尼比），组件里不许再写裸 k/ζ
class SpringSpec {
  const SpringSpec(this.k, this.zeta);
  final double k;
  final double zeta;

  /// 按压回弹：脆、带一点过冲
  static const SpringSpec press = SpringSpec(420, .62);

  /// 卡牌倾斜跟手：软、不过冲
  static const SpringSpec tilt = SpringSpec(180, .9);

  /// 牌桌（= Motion.cardTableK/Zeta）
  static const SpringSpec table = SpringSpec(Motion.cardTableK, Motion.cardTableZeta);

  /// 相机（= Motion.cameraK/Zeta）
  static const SpringSpec camera = SpringSpec(Motion.cameraK, Motion.cameraZeta);
}

/// 音效触发规则 —— **什么动作出声、多响、多密**（Sfx.cue 读它）。
///
///  铁律：
///   1. 只有**落定**（提交 / 钤印 / 结算 / 升级）用满音量；过程音（按下、
///      档位、翻面）一律 soft，且同一 key 有最小间隔，连点不会变成机关枪
///   2. 按下**不出声**只震动；抬手（真的触发了）才出声 —— 防误触噪音
///   3. 静音总开关 / 音量档由设置页控制（Sfx.enabled / Sfx.userGain）
class SoundRule {
  const SoundRule(this.key, {this.gain = 1, this.minGapMs = 0});

  /// sfx.dart 的事件 key
  final String key;

  /// 相对音量 0~1（再乘总音量）
  final double gain;

  /// 同一 cue 两发之间的最小间隔
  final int minGapMs;

  static const Map<String, SoundRule> cues = <String, SoundRule>{
    // 过程音（soft + 节流）
    'ui.tap': SoundRule('tap', gain: .55, minGapMs: 60),
    'ui.open': SoundRule('choose', gain: .45, minGapMs: 120),
    'ui.close': SoundRule('detent', gain: .35, minGapMs: 120),
    'card.focus': SoundRule('detent', gain: .5, minGapMs: 45),
    'card.lift': SoundRule('deal', gain: .4, minGapMs: 90),
    'card.deny': SoundRule('detent', gain: .6, minGapMs: 160),
    'stage.touch': SoundRule('poke', gain: .8, minGapMs: 180),
    // 落定音（满音量）
    'card.commit': SoundRule('stamp'),
    'reward.seal': SoundRule('seal'),
    'reward.levelup': SoundRule('levelup'),
  };
}
