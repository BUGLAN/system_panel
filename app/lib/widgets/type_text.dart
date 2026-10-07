import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// ═══════════════════════════════════════════════════════════
///  打字机（ui.js L77-112 `Line.say`）—— 一字一字往外蹦，标点处多停一拍。
///
///  参数全部照抄原型，别凭感觉改：
///   · 每字 **34ms**（`soft` 台词 **42ms**）
///   · 标点追加：`，、：` +120ms · `。！？` +240ms · `…` +70ms · `—` +40ms
///   · 每个字自己淡入 **120ms**（`.line .txt .c { opacity:0 } .c.on { transition: opacity .12s }`）
///   · `[[…]]` 之间是高亮片段（`.txt em`：青色 + 字重 650 + 12px 辉光；soft 台词里改成灰白无辉光）
///   · 点一下**整句立刻铺完**（原型 `Tap.next()` → `skip`）
///
///  实现要点：**未显形的字用 alpha=0 的 span 而不是不渲染** ——
///  这样换行位置从第一帧就是最终位置，不会越打越跳行。
/// ═══════════════════════════════════════════════════════════
class TypeText extends StatefulWidget {
  const TypeText({
    super.key,
    required this.text,
    this.soft = false,
    this.speed,
    this.skipToken = 0,
    this.style,
    this.onDone,
  });

  final String text;

  /// `soft` 台词：打字更慢、高亮片段改成灰白
  final bool soft;

  /// 覆盖每字毫秒数（原型 `o.speed`）
  final int? speed;

  /// 每 +1 就跳过打字，整句立刻铺完
  final int skipToken;

  final TextStyle? style;

  /// 打完时回调（原型随后按 `hold` 停留）
  final VoidCallback? onDone;

  @override
  State<TypeText> createState() => _TypeTextState();
}

class _Ch {
  _Ch(this.ch, this.em);

  final String ch;
  final bool em;

  /// 这个字**开始**显形的时刻（ms）
  double at = 0;
}

class _TypeTextState extends State<TypeText>
    with SingleTickerProviderStateMixin {
  late List<_Ch> _chars;
  late double _total;
  AnimationController? _c;
  bool _done = false;

  /// `richChars()`（util.js）—— 把 `[[…]]` 之间标成高亮
  static List<_Ch> richChars(String s) {
    final List<_Ch> out = <_Ch>[];
    final RegExp re = RegExp(r'\[\[(.+?)\]\]');
    int last = 0;
    for (final RegExpMatch m in re.allMatches(s)) {
      for (final String ch in s.substring(last, m.start).split('')) {
        out.add(_Ch(ch, false));
      }
      for (final String ch in m.group(1)!.split('')) {
        out.add(_Ch(ch, true));
      }
      last = m.end;
    }
    for (final String ch in s.substring(last).split('')) {
      out.add(_Ch(ch, false));
    }
    return out;
  }

  static double _delay(String ch, double speed) {
    if ('，、：'.contains(ch)) return speed + 120;
    if ('。！？'.contains(ch)) return speed + 240;
    if (ch == '…') return speed + 70;
    if (ch == '—') return speed + 40;
    return speed;
  }

  @override
  void initState() {
    super.initState();
    _build();
  }

  void _build() {
    final double speed = (widget.speed ?? (widget.soft ? 42 : 34)).toDouble();
    _chars = richChars(widget.text);
    double t = 0;
    for (final _Ch c in _chars) {
      c.at = t;
      t += _delay(c.ch, speed);
    }
    _total = t <= 0 ? 1 : t;
    _done = false;
    _c?.dispose();
    // 控制器多留 120ms 尾巴：最后一个字自己也要淡完，
    // 否则控制器停在 total 时它永远停在淡入中途
    _c =
        AnimationController(
          vsync: this,
          duration: Duration(microseconds: ((_total + 120) * 1000).round()),
        )..addListener(() {
          // 打字结束点（不含那 120ms 淡入尾巴）
          if (!_done && _c!.value * (_total + 120) >= _total) {
            _done = true;
            widget.onDone?.call();
          }
        });
    if (widget.skipToken == 0) {
      _c!.forward();
    } else {
      _c!.value = 1;
      _done = true;
    }
  }

  @override
  void didUpdateWidget(covariant TypeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.soft != widget.soft) {
      _build();
      setState(() {});
      return;
    }
    if (old.skipToken != widget.skipToken) {
      // 点一下：整句立刻铺完（原型 `skip = true` → 后面的字不再等）
      _c!.value = 1;
      if (!_done) {
        _done = true;
        widget.onDone?.call();
      }
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  /// 这个字当前的透明度：显形后 120ms 淡入
  double _alphaOf(_Ch c, double now) {
    final double d = now - c.at;
    if (d <= 0) return 0;
    if (d >= 120) return 1;
    return d / 120;
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle base =
        widget.style ??
        fs(
          family: F.cn,
          size: 17,
          wght: 500,
          ls: .34,
          height: 1.58,
          color: const Color(0xFFEEFCFF),
        );
    final TextStyle emStyle = widget.soft
        ? base.copyWith(
            color: const Color(0xFFD5E2F2),
            fontVariations: const <FontVariation>[FontVariation('wght', 400)],
            shadows: null,
          )
        : base.copyWith(
            color: C.blue,
            fontVariations: const <FontVariation>[FontVariation('wght', 650)],
            shadows: <Shadow>[
              const Shadow(color: Color(0x8038E1FF), blurRadius: 12),
            ],
          );

    return AnimatedBuilder(
      animation: _c!,
      builder: (BuildContext context, Widget? child) {
        final double now = _c!.value * (_total + 120);
        return Text.rich(
          TextSpan(
            children: <InlineSpan>[
              for (final _Ch c in _chars)
                TextSpan(
                  text: c.ch,
                  style: (c.em ? emStyle : base).copyWith(
                    color: (c.em ? emStyle.color : base.color)!.withAlpha(
                      (_alphaOf(c, now) * 255).round(),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
