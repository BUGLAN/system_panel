import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../state/sfx.dart';
import '../state/voice.dart';
import 'rail_base.dart';
import 'voice_bars.dart';

import 'type_text.dart';

import '../design/tokens.dart';

/// ═══════════════════════════════════════════════════════════
///  她的台词（app.css L152-178 `.line`）
///  不是聊天气泡，是**字幕**：一条横贯屏幕的玻璃带，左边一道青光。
///  实测盒模型（390×844，lobby）：line [20,506,350,71]
///  · who [38,518,316,12] · txt [38,536,316,27]
///
///  打字机 / 电子音节 / 口型包络属于行为，尚未由宿主约束 ——
///  这里只渲染「一句话已经说完」的静态样子。
///
///  ── docs/39 H-12（2026-10-17 真机走查 · P1）───────────────────
///  真机问题是**没有上限**：LLM 拆出来的长句会把玻璃带一路撑到聊天钮和
///  主线挂签上（走查 §2.1 / §0：17pt 正文、行高 1.58、无 maxLines）。
///  这一版把四条一起收口：
///   1. **maxLines 3 + ellipsis**（打字机照旧逐字铺，行数由整句决定）；
///   2. 超过 3 行时 17 → **16.5pt**（长句略收，省一行高度）；
///   3. 上边线 α .20 → **.26**（玻璃带在深底上更"有边"）；
///   4. 进 **240ms** / 出 **360ms**：淡 + 8px 下移（原来 300/450 且只有位移比例）。
///  玻璃 blur 3.5、左侧 2px 光条、34ms 打字机、跳字全部保留（走查明确不动）。
/// ═══════════════════════════════════════════════════════════

/// docs/39 H-12：字幕进场 240ms / 出场 360ms。
/// （§5.1 的「退场 = 进场的 60%」是 144ms，但方案表给的是 360 —— 字幕是长句，
///  退太快像被掐断；以方案表为准。）
const int kLineInMs = 240;
const int kLineOutMs = 360;

/// docs/39 H-12：字幕最多 3 行（超出省略号）。
const int kLineMaxLines = 3;

/// 估算用：每行约 19 个中文字。
///
/// 依据：字幕带内宽 ≈ 350（满宽 20 边距）− 左右内边距 34 = 316；正文 17pt 的中文
/// 字宽 ≈ 1em → 316 / 17 ≈ 18.6 字/行。取 19。
/// ⚠️ 只是**估算**：单测里用占位字体（每字形 1em 宽）会更接近这个值，真机字体
///    略窄一点 —— 所以阈值宁可比真机略早触发（长句早一点降到 16.5 不会难看，
///    晚一点才会真的挤出第 4 行）。
const int kLineCharsPerLine = 19;

/// 超过这个长度（19 × 3 ≈ 57 字）就把正文从 17 降到 16.5。
///
/// ⚠️ 判据必须是**整句全长**，不能是"当前显形了几个字"：打字机是逐字铺开的，
///    若按显形字数判，字号会在打字过程中从 17 跳到 16.5（一次会跳的排版事故）。
///    `[[…]]` 是高亮标记、不上屏，计长度时要剔掉。
const int kLineLongChars = kLineCharsPerLine * kLineMaxLines;

class LineLayer extends StatefulWidget {
  const LineLayer({
    super.key,
    required this.text,
    this.mood = '',
    required this.y,
    this.soft = false,
    this.visible = true,
    this.waveScale = .15,
    this.fail = false,
    this.skipToken = 0,
    this.voice,
    this.onChar,
    this.emotion,
    this.paceMs,
    this.bottomFloor = 0,
  });

  final String text;

  /// 右上角那个情绪词（MOOD_LABEL）
  final String mood;

  /// 字幕带顶边（原型的 --ly，由 mode 决定）
  final double y;

  /// 低声说话时的降调样式
  final bool soft;

  final bool visible;

  /// 波形条的静态高度（原型由声音驱动，范围 .12~1）
  final double waveScale;

  /// 认输态：`#app.fail .line::after` 会把左边那道青光换成灰色、去掉辉光
  final bool fail;

  /// 每 +1 就跳过打字机，整句立刻铺完（原型 `Tap.next()`）
  final int skipToken;

  /// 口型包络 —— 给了它，SYSTEM 后面那排条就变成活的（`ui.js` L70-73）。
  /// 没给就退回静态的 `waveScale`，行为与之前完全一致。
  final VoiceEnvelope? voice;

  /// 逐字回调（调用方转给 `VoiceEnvelope.syllable`）
  final ValueChanged<String>? onChar;

  /// 这句台词的**情绪**（`persona.dart` 的 12 情绪表之一）—— 逐字电子音节按它变调。
  /// 没给就按 [mood] 反查 `MOOD_LABEL`（`content.js:421`）；反查不到的（例如
  /// main.dart 自造的「专注」）退回 `neutral`，宁可平一点也不瞎猜。
  final String? emotion;

  /// 对白节奏（docs/22 §R4）：每字显形毫秒数，透传给 [TypeText] 的 `speed`。
  /// 没给 = 保持 [TypeText] 的既有默认（soft 42 / 普通 34）；给了就以档位为准。
  final int? paceMs;

  /// docs/39 H-17：字幕带**底边不许越过**的那条线距屏底多少 pt。
  ///
  /// 0 = 不设下限（默认，老调用点行为逐字节不变）。
  /// main.dart 传「底部安全区，或主线上让开底部两键的 34 + 56 + 12」——
  /// 这样 3 行字幕在主线页会**被顶上去**而不是压住【接任务/继续执行】。
  /// 只做**下限**（`min(y, 上限)`），不做叠加：现有布局里它一次都不会动
  /// （见 main.dart 调用点的注释），加它是给以后的版式兜底。
  final double bottomFloor;

  /// `MOOD_LABEL` 的逆映射：中文标签 → 情绪（`content.js` L421-424）
  static String _emotionOfMood(String mood) => const <String, String>{
    '待机': 'neutral',
    '嫌弃': 'smug',
    '冷淡': 'cold',
    '不爽': 'annoyed',
    '尚可': 'pleased',
    '别扭': 'tsun',
    '……开心': 'joy',
    '意外': 'surprised',
    '失望': 'sad',
    '监视': 'focus',
    '休眠': 'sleep',
    '认可': 'proud',
  }[mood] ?? 'neutral';

  /// `[[…]]` 是语法标记、不上屏 —— 计长度与行数时剔掉
  static String _plain(String s) => s.replaceAll('[[', '').replaceAll(']]', '');

  /// 整句的**估算**行数（1~3）—— 只用于「降字号」与「底边下限」的高度预算
  static int linesOf(String text) {
    final int n = _plain(text).runes.length;
    return (n / kLineCharsPerLine).ceil().clamp(1, kLineMaxLines);
  }

  @override
  State<LineLayer> createState() => _LineLayerState();
}

class _LineLayerState extends State<LineLayer>
    with SingleTickerProviderStateMixin {
  /// 进出场进度：0 = 收起（透明 + 偏 8px），1 = 完全展开。
  /// 首帧按 [LineLayer.visible] 直接落位（不补播首屏入场 —— 与 Hud/Dock 同纪律）。
  late final AnimationController _c = AnimationController(
    vsync: this,
    value: widget.visible ? 1 : 0,
  );

  /// 这一程是进场还是出场 —— 决定那 8px 往哪边挪（进：-8 → 0；出：0 → +8）
  bool _intro = true;

  @override
  void didUpdateWidget(covariant LineLayer old) {
    super.didUpdateWidget(old);
    if (old.visible == widget.visible) return;
    // 减弱动态效果：直接落终态（§5.5「reduceMotion 要落终态」，不是不动画面）
    if (railReduceMotion(context)) {
      _c.value = widget.visible ? 1 : 0;
      return;
    }
    if (widget.visible) {
      _intro = true;
      _c.duration = const Duration(milliseconds: kLineInMs);
      _c.forward(from: 0);
    } else {
      _intro = false;
      _c.duration = const Duration(milliseconds: kLineOutMs);
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 整句是否算「长句」（> 3 行估算）—— 决定 17 还是 16.5
  bool get _long => LineLayer._plain(widget.text).runes.length > kLineLongChars;

  @override
  Widget build(BuildContext context) {
    // 打字机逐字铺开时字号不能跳：判据是**整句全长**（见 kLineLongChars 注释）
    final double size = _long ? 16.5 : 17;
    final Color ink = widget.soft
        ? const Color(0xFFB8C7DC)
        : const Color(0xFFEEFCFF);
    // 打字机逐字音节（`ui.js:96`）：原型在**同一个逐字回调**里发
    // `Voice.syllable(ch, emo, o.soft)`，这里接在既有的口型钩子后面。
    // 跳过整句时 `TypeText` 不逐字回调 → 也就不会逐字发音（原型同）。
    final String sylEmotion =
        widget.emotion ?? LineLayer._emotionOfMood(widget.mood);
    final Color bar = widget.fail
        ? const Color(0xFF6C7A92)
        : widget.soft
        ? const Color(0xFF7C8AA3)
        : C.blue;
    final Color whoColor = widget.soft ? const Color(0xFF8A9AB4) : C.blue;

    return AnimatedBuilder(
      animation: _c,
      // ⚠️ 只有字幕带这一小块做 Opacity（不是整屏、不是牌屉那种整张玻璃卡）。
      //    H-12 的方案表明确要求"淡"，这里照做；saveLayer 的范围 = 一条 71~125
      //    高的带子，不是 §5.5 点名的整屏/整卡。
      builder: (BuildContext _, Widget? child) {
        // 与全库同一套收口曲线：kOut（§5.1「退场 = 进场的 60%」，曲线同源）
        final double k = kOut.transform(_c.value).clamp(0.0, 1.0);
        // 进：从 -8 落到 0；出：从 0 沉到 +8（都是"下移 8px"）
        final double dy = (_intro ? -8 : 8) * (1 - k);
        return Positioned(
          // ⚠️ `line` 这个 Key 必须留在**带子本身**（Positioned 这层），
          //    不能下沉到 Padding 里面 —— 单测按它量 [20, y, 350, ~71] 的盒模型。
          key: const Key('line'),
          left: 20,
          right: 20,
          top: _topOf(context),
          child: IgnorePointer(
            // 收起途中也别吃"点背景跳打字机"的那一下
            ignoring: k < .999,
            child: Opacity(
              opacity: k,
              child: Transform.translate(
                offset: Offset(0, dy),
                child: child,
              ),
            ),
          ),
        );
      },
      child: _band(ink, bar, whoColor, size, sylEmotion),
    );
  }

  /// 字幕带的顶边：默认就是 [LineLayer.y]；只有调用方给了 [LineLayer.bottomFloor]
  /// 才做「底边不许越过」的下限夹取（按估算高度，够用 —— 这一层不能为了量高度
  /// 把自己变成需要二次布局的件）。
  double _topOf(BuildContext context) {
    if (widget.bottomFloor <= 0) return widget.y;
    final double h = MediaQuery.sizeOf(context).height;
    final double size = _long ? 16.5 : 17;
    // 盒高 = 上内边距 12 + who 行 12 + 间隙 6 + 行数×行高 + 下内边距 14
    final double estH =
        12 + 12 + 6 + LineLayer.linesOf(widget.text) * size * 1.58 + 14;
    final double maxTop = h - widget.bottomFloor - estH;
    return math.min(widget.y, math.max(0, maxTop));
  }

  /// 玻璃带本体（除进出场外的一切）
  Widget _band(
    Color ink,
    Color bar,
    Color whoColor,
    double size,
    String sylEmotion,
  ) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        // .line::before —— 从屏幕左右两侧淡出的玻璃带
        // （视觉真源：原型 `backdrop-filter: blur(7px)`，Flutter 端 3.5。
        //   虽然这是常驻合成里最贵的一笔，但视觉不许动 —— 原样保留。）
        Positioned(
          left: -20,
          right: -20,
          top: 0,
          bottom: 0,
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[
                      Color(0x80030814), // rgba(3,8,20,.5)
                      Color(0xD6030916), // rgba(3,9,22,.84)
                      Color(0xD6030916),
                      Color(0x80030814),
                    ],
                    stops: <double>[0, .16, .84, 1],
                  ),
                  border: Border(
                    // docs/39 H-12：上边线 α .20 → .26（51 → 66）
                    top: BorderSide(color: C.blue.withAlpha(66), width: 1),
                    bottom: BorderSide(color: C.blue.withAlpha(18), width: 1),
                  ),
                ),
              ),
            ),
          ),
        ),
        // .line::after —— 左边那道青光（H-12：2px 保留）
        Positioned(
          left: 0,
          top: 14,
          bottom: 16,
          width: 2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bar,
              borderRadius: BorderRadius.circular(1),
              boxShadow: (widget.soft || widget.fail)
                  ? null
                  : <BoxShadow>[BoxShadow(color: C.blue, blurRadius: 10)],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _who(whoColor, bar),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: 26.86,
                ), // 1.58em
                child: DefaultTextStyle(
                  // ⚠️ 打字机（type_text.dart）自己不给 `Text.rich` 传 maxLines，
                  //    Text.build 的规则是 `maxLines ?? defaultTextStyle.maxLines`、
                  //    `overflow ?? … ?? defaultTextStyle.overflow` —— 所以用
                  //    DefaultTextStyle 下发「3 行 + 省略号」，既把 3 行钉死、
                  //    又不碰打字机逐字铺开的实现。
                  maxLines: kLineMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: fs(family: F.cn, size: size, wght: 500, height: 1.58),
                  child: TypeText(
                    text: widget.text,
                    soft: widget.soft,
                    skipToken: widget.skipToken,
                    // 对白节奏三档（docs/22 §R4）：设置页选的值从这里下来；
                    // 没接线时传 null，退回 type_text.dart 的默认（34）。
                    speed: widget.paceMs,
                    // 口型包络照旧先走（`VoiceEnvelope.syllable`），后面这一发
                    // 才是**电子音节**（`soft` = 旁白降调、音量减半）。
                    // 跳过整句时这里一次都不会被回调 —— `type_text.dart` 的 skip
                    // 分支先把 `_shown` 推到句尾，不会再逐字回调（原型同）。
                    onChar: (String ch) {
                      widget.onChar?.call(ch);
                      Sfx.syllable(sylEmotion, soft: widget.soft);
                    },
                    style: fs(
                      family: F.cn,
                      size: size, // H-12：默认 17；超过 3 行估算 → 16.5
                      wght: widget.soft ? 400 : 500,
                      ls: .34,
                      height: 1.58,
                      color: ink,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Color(0xCC000000),
                          blurRadius: 12,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _who(Color whoColor, Color bar) {
    return Row(
      children: <Widget>[
        Text(
          'SYSTEM',
          style: fs(
            family: F.num,
            size: 11,
            wght: 800,
            ls: 2.64,
            height: 1,
            color: whoColor,
          ),
        ),
        const SizedBox(width: 8),
        // .wave —— 五根随声音起伏的竖条
        // 给了口型包络就用活的那套（原型 `ui.js` L70-73 由 `Voice.mouth` 驱动）
        //
        // docs/39 §5.5：减弱动态 → 退回**静态高度**（`.15`，CSS 的原始值），
        // 不跑波形循环。默认路径（没开 reduce）一个像素都不变。
        if (widget.voice != null)
          VoiceBars(
            voice: widget.voice!,
            color: bar,
            enabled: !railReduceMotion(context),
          )
        else
          SizedBox(
            height: 12,
            child: Row(
              children: List<Widget>.generate(5, (int i) {
                return Padding(
                  padding: EdgeInsets.only(right: i == 4 ? 0 : 2),
                  child: Container(
                    width: 2,
                    height: 12 * widget.waveScale,
                    decoration: BoxDecoration(
                      color: bar,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                );
              }),
            ),
          ),
        const SizedBox(width: 8),
        if (widget.mood.isNotEmpty)
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: '· ',
                  style: fs(
                    family: F.mono,
                    size: 9.5,
                    wght: 500,
                    ls: 1.14,
                    height: 1,
                    color: C.mist,
                  ),
                ),
                TextSpan(
                  text: widget.mood,
                  style: fs(
                    family: F.mono,
                    size: 9.5,
                    wght: 500,
                    ls: 1.14,
                    height: 1,
                    color: C.mist,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
