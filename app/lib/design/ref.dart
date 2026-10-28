import 'package:flutter/material.dart';

/// ═══════════════════════════════════════════════════════════
///  参考稿令牌 —— 唯一基准：`宿主养成系统_重设计.html` 的 `:root`（L12-20）
///
///  这一层是 **v3 表现层的唯一真源**。旧的 `tokens.dart`（C / F / Motion /
///  Pal）保留不动：它被 700+ 条历史测试与旧组件引用着，逐页迁移时会
///  一个一个换过来。新增的界面**只许**读这里。
///
///  从 CSS 到 Dart 的换算纪律：
///   · `rgba(255,255,255,.08)` → `Color(0x14FFFFFF)`（α×255 四舍五入）
///   · `font: 900 28px/1.2` → `RefText.of(size: 28, wght: 900, height: 1.2)`
///   · `letter-spacing: .5px` → `letterSpacing: .5`（参考稿里 px 就是逻辑像素）
/// ═══════════════════════════════════════════════════════════
class Ref {
  const Ref._();

  // ── 基底（L13）──────────────────────────────────────────────
  /// `--bg:#06050c` 页面底（紫黑，不是蓝黑）
  static const Color bg = Color(0xFF06050C);

  /// `--ink:#0d0b18` 卡底 / 输入底
  static const Color ink = Color(0xFF0D0B18);

  /// `--line:rgba(255,255,255,.08)` 全局分隔线 / 描边
  static const Color line = Color(0x14FFFFFF);

  // ── 强调色（L14）────────────────────────────────────────────
  /// `--acid:#d6ff3d` 主强调：主按钮 / 当前卡 / 等级环 / 选中态
  static const Color acid = Color(0xFFD6FF3D);

  /// `--hot:#ff3b7a` 失败 / 认输 / 暴击 / 警示
  static const Color hot = Color(0xFFFF3B7A);

  /// `--cyan:#3be8ff` 次要强调：主线 / 信息 / 金币
  static const Color cyan = Color(0xFF3BE8FF);

  /// `--violet:#8f6bff` 档案 / 名牒 / 进度条
  static const Color violet = Color(0xFF8F6BFF);

  /// `--gold:#ffcc4d` 稀有度 B / 金色压印 / tabs 滑块
  static const Color gold = Color(0xFFFFCC4D);

  /// `--mint:#3dffa8` 稀有度 E / 成功
  static const Color mint = Color(0xFF3DFFA8);

  // ── 文本（L15）──────────────────────────────────────────────
  /// `--txt:#f4f1ff` 标题 / 主文本（微紫白）
  static const Color txt = Color(0xFFF4F1FF);

  /// `--dim:#8c88aa` 正文次级
  static const Color dim = Color(0xFF8C88AA);

  /// `--dim2:#55516E` 三级 / 占位符 / 刻度
  static const Color dim2 = Color(0xFF55516E);

  /// 主按钮上的深色字（参考稿里是 `#0a0910`）
  static const Color onAccent = Color(0xFF0A0910);

  // ── 字体（L16-18）──────────────────────────────────────────
  /// `--fd: 'Chakra Petch'` 标题 / 拉丁大字 / 数字大字
  static const String fd = 'ChakraPetch';

  /// `--fc: 'Noto Sans SC'` 中文正文
  static const String fc = 'NotoSansSC';

  /// `--fm: 'JetBrains Mono'` 等宽读数 / 系统日志
  static const String fm = 'JetBrainsMono';

  // ── 曲线（L19）──────────────────────────────────────────────
  /// `--ease: cubic-bezier(.2,.9,.2,1)` 主过渡
  static const Cubic ease = Cubic(.2, .9, .2, 1);

  /// `--snap: cubic-bezier(.7,0,.2,1)` 收口 / 归位
  static const Cubic snap = Cubic(.7, 0, .2, 1);

  /// 弹入（L1120 toast / L1141 modal 用的 `.2,1.4,.4,1`）
  static const Cubic pop = Cubic(.2, 1.4, .4, 1);

  /// 页面 wipe（L1172 的 `.75,0,.25,1`）
  static const Cubic wipe = Cubic(.75, 0, .25, 1);

  /// 卡翻转（L525 的 `.3,1.3,.4,1`）
  static const Cubic flip = Cubic(.3, 1.3, .4, 1);

  /// 急停（L1346/L1391 的 `.6,0,.8,.4`：压印砸下）
  static const Cubic slam = Cubic(.6, 0, .8, .4);

  // ── 稀有度色谱（L1011 `GC`）─────────────────────────────────
  /// 参考稿的档位色：E 薄荷 / D 青 / C 紫 / B 金 / A 品红 / S 纯白。
  /// ⚠️ 与 `data/rarity.dart` 的旧色谱**不同**（旧版 S 是红）。
  ///    新界面一律读这里；旧表等逐页迁移完再合并。
  static const Map<String, Color> rank = <String, Color>{
    'F': Color(0xFF9AA3B2),
    'E': mint,
    'D': cyan,
    'C': violet,
    'B': gold,
    'A': hot,
    'S': Color(0xFFFFFFFF),
  };

  /// 档位 → 色（未知档退 `F` 灰）
  static Color rankOf(String r) => rank[r] ?? rank['F']!;

  /// 稀有度点数（L1291 `RARN`）：卡片右上那排小菱形亮几个
  static const Map<String, int> rankPips = <String, int>{
    'E': 1,
    'D': 2,
    'C': 3,
    'B': 4,
    'A': 5,
    'S': 5,
    'F': 1,
  };

  /// α 混合便捷（参考稿里 `color-mix(in srgb, c 22%, transparent)` 的等价物）
  static Color a(Color c, double alpha) =>
      c.withAlpha((alpha.clamp(0.0, 1.0) * 255).round());

  /// 两色混合（`color-mix(in srgb, a 15%, b)`）
  static Color mix(Color a, Color b, double t) =>
      Color.lerp(a, b, t.clamp(0.0, 1.0))!;

  // ── 布局常量（L57-59 / L71 / L174 / L191 …）─────────────────
  /// `.scene` 左右内边距 22（参考稿唯一的口径）
  static const double gutter = 22;

  /// `.scene` 顶部内容起点：`env(safe) + 94`（有 HUD）/ `+30`（`.nohud`）
  static const double sceneTop = 94;
  static const double sceneTopNoHud = 30;

  /// `.scene` 底部：`env(safe) + 20`
  static const double sceneBottom = 20;

  /// 手机壳最大尺寸（L38）：`min(100vw,430px)` × `min(100dvh,920px)`
  static const double deviceMaxW = 430;
  static const double deviceMaxH = 920;

  /// `.btn` 高 62 / `.btn.sm` 56 / 斜切 13
  static const double btnH = 62;
  static const double btnSmH = 56;
  static const double btnCut = 13;

  /// `.bubble` 圆角 `4 16 16 16`（她的话）
  static const BorderRadius bubble = BorderRadius.only(
    topLeft: Radius.circular(4),
    topRight: Radius.circular(16),
    bottomRight: Radius.circular(16),
    bottomLeft: Radius.circular(16),
  );
}

/// CSS `font:` 简写在 Dart 里的对应物（参考稿三套字体 + 真斜体）。
///
/// 与旧 `fs()` 的区别：**行高、字距一律显式给**（参考稿 CSS 的 `font:`
/// 简写把 `line-height` 写在小数点上，比如 `16px/1.35`）—— 不猜 normal。
TextStyle refText({
  String? family,
  required double size,
  double wght = 400,
  double? ls,
  double? height,
  Color? color,
  bool italic = false,
  List<Shadow>? shadows,
  Paint? foreground,
}) {
  // ⚠️ 参考稿的 `--fd / --fm` 声明里都带 `--fc` 作后备
  //    （L16-18 的 font-family 列表）。Flutter 不会自动跨 family 找字形，
  //    所以 Chakra Petch / JetBrains Mono 里的中文必须显式 fallback，
  //    否则就是截图里那种方框（「她说」「主线」全变豆腐块）。
  final String fam = family ?? Ref.fc;
  return TextStyle(
    fontFamily: fam,
    fontFamilyFallback: fam == Ref.fc
        ? const <String>['NotoSansSC']
        : const <String>['NotoSansSC', 'NotoSansSC', 'Noto Sans SC'],
    fontSize: size,
    height: height,
    letterSpacing: ls,
    color: foreground == null ? color : null,
    foreground: foreground,
    shadows: shadows,
    // Chakra Petch 是静态字重（500/700 各一份文件）：Flutter 按 fontWeight
    // 选文件，只给 fontVariations 会一律落到 Medium —— 粗体全丢。
    // 可变字体（NotoSansSC / JetBrainsMono）由 fontVariations 精确控制。
    fontWeight: _weightOf(wght),
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    fontVariations: <FontVariation>[FontVariation('wght', wght)],
  );
}

FontWeight _weightOf(double w) {
  final int i = ((w / 100).round() - 1).clamp(0, 8);
  return FontWeight.values[i];
}

/// 参考稿的高频文字组合（避免每处重复写 6 个参数）。
class RefType {
  const RefType._();

  /// `.eyebrow`（L60）：`500 11px` + `letter-spacing:4px` + 主强调色
  static TextStyle eyebrow(Color accent) => refText(
    family: Ref.fm,
    size: 11,
    wght: 500,
    ls: 4,
    height: 1.6,
    color: accent,
  );

  /// `.h1`（L62）：`900 28px/1.2` + `letter-spacing:.5px` + 硬投影
  static TextStyle h1 = refText(
    size: 28,
    wght: 900,
    ls: .5,
    height: 1.2,
    color: Ref.txt,
    shadows: const <Shadow>[
      Shadow(color: Color(0x66000000), offset: Offset(0, 2)),
    ],
  );

  /// `.meta`（L218）：`400 14px` + 次级灰
  static TextStyle meta = refText(size: 14, wght: 400, color: Ref.dim);

  /// `.meta b`（L219）：`700 16px` Chakra Petch + 主文本
  static TextStyle metaNum = refText(
    family: Ref.fd,
    size: 16,
    wght: 700,
    color: Ref.txt,
  );

  /// `.q-t`（L150）：`900 19px` 委托标题
  static TextStyle questTitle = refText(size: 19, wght: 900, color: Ref.txt);

  /// `.tk-t`（L255）：`700 16px/1.35` 票券标题
  static TextStyle ticketTitle = refText(
    size: 16,
    wght: 700,
    height: 1.35,
    color: Ref.txt,
  );

  /// `.tk-m`（L256）：`400 12px` 次级
  static TextStyle ticketMeta = refText(size: 12, wght: 400, color: Ref.dim);

  /// `.gc-t`（L201）：`900 20px/1.35` 大牌标题
  static TextStyle cardTitle = refText(
    size: 20,
    wght: 900,
    height: 1.35,
    color: Ref.txt,
  );

  /// `.gc-m`（L202）：`400 13px` 大牌附注
  static TextStyle cardMeta = refText(size: 13, wght: 400, color: Ref.dim);

  /// `.vline`（L440）：`500 15px/1.6` 她的话（居中）
  static TextStyle verdictLine = refText(
    size: 15,
    wght: 500,
    height: 1.6,
    color: Color(0xFFE7E3FF),
  );

  /// `.srow`（L485）：`500 15px` 设置行
  static TextStyle srow = refText(size: 15, wght: 500, color: Ref.txt);

  /// `.srow small`（L486）：`400 12px` 设置行副标题
  static TextStyle srowSub = refText(size: 12, wght: 400, color: Ref.dim);

  /// `.lu-t`（L453）：`700 italic 52px`
  static TextStyle levelUp = refText(
    family: Ref.fd,
    size: 52,
    wght: 700,
    ls: 2,
    height: 1,
    color: Ref.acid,
    italic: true,
    shadows: const <Shadow>[
      Shadow(color: Ref.acid, blurRadius: 30),
      Shadow(color: Ref.hot, offset: Offset(4, 4)),
    ],
  );
}
