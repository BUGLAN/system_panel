import 'dart:ui' as ui;

import 'package:flutter/material.dart';

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
/// ═══════════════════════════════════════════════════════════
class LineLayer extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final Color ink = soft ? const Color(0xFFB8C7DC) : const Color(0xFFEEFCFF);
    final Color bar = fail
        ? const Color(0xFF6C7A92)
        : soft
        ? const Color(0xFF7C8AA3)
        : C.blue;
    final Color whoColor = soft ? const Color(0xFF8A9AB4) : C.blue;

    return Positioned(
      left: 20,
      right: 20,
      top: y,
      child: AnimatedOpacity(
        key: const Key('line'),
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 300),
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, .12),
          duration: const Duration(milliseconds: 450),
          curve: kOut,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              // .line::before —— 从屏幕左右两侧淡出的玻璃带
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
                          top: BorderSide(
                            color: C.blue.withAlpha(51),
                            width: 1,
                          ),
                          bottom: BorderSide(
                            color: C.blue.withAlpha(18),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // .line::after —— 左边那道青光
              Positioned(
                left: 0,
                top: 14,
                bottom: 16,
                width: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: bar,
                    borderRadius: BorderRadius.circular(1),
                    boxShadow: (soft || fail)
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
                      child: TypeText(
                        text: text,
                        soft: soft,
                        skipToken: skipToken,
                        style: fs(
                          family: F.cn,
                          size: 17,
                          wght: soft ? 400 : 500,
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
        SizedBox(
          height: 12,
          child: Row(
            children: List<Widget>.generate(5, (int i) {
              return Padding(
                padding: EdgeInsets.only(right: i == 4 ? 0 : 2),
                child: Container(
                  width: 2,
                  height: 12 * waveScale,
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
        if (mood.isNotEmpty)
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
                  text: mood,
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
