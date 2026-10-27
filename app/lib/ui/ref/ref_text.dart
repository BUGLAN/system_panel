import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/ref.dart';

/// ═══════════════════════════════════════════════════════════
///  参考稿的类型机 —— \`typeTo()\`（JS L999-1004）
///
///  · 文案里的 \`[高亮]\` 片段 → 主强调色 + Chakra Petch 1.15em（L141）
///  · 标准节奏 34ms/字（\`AgentSettings.kPaceStandardMs\` 同一口径）
///  · 打字时句尾挂一个 \`▌\` 光标（L143）；打完消失
///  · 点背景（\`skipToken\` 变化）→ 一次显形
///  · 减弱动态 → 直接显形
/// ═══════════════════════════════════════════════════════════
class RefTypewriter extends StatefulWidget {
  const RefTypewriter({
    super.key,
    required this.text,
    required this.style,
    this.highlightStyle,
    this.speed = const Duration(milliseconds: 34),
    this.skipToken = 0,
    this.maxLines,
    this.textAlign,
    this.overflow = TextOverflow.clip,
    this.softWrap = true,
  });

  final String text;
  final TextStyle style;

  /// \`[高亮]\` 片段使用的样式；不传就用"主强调色 + Chakra Petch"
  final TextStyle? highlightStyle;

  final Duration speed;

  /// 外部「跳过」令牌：每变一次，立刻把整句显形
  final int skipToken;

  final int? maxLines;
  final TextAlign? textAlign;
  final TextOverflow overflow;
  final bool softWrap;

  @override
  State<RefTypewriter> createState() => _RefTypewriterState();
}

class _RefTypewriterState extends State<RefTypewriter> {
  late List<_Seg> _segs;
  int _shown = 0;
  Timer? _timer;
  bool _all = false;

  bool _started = false;

  @override
  void initState() {
    super.initState();
    _parse();
    // ⚠️ 不能在 initState 里读 MediaQuery（refText 的减弱动态判定）：
    //    InheritedWidget 只能等到 didChangeDependencies 才可依赖。
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _start();
    }
  }

  @override
  void didUpdateWidget(RefTypewriter old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _parse();
      _start();
    } else if (old.skipToken != widget.skipToken && !_all) {
      _skip();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _parse() {
    final List<_Seg> out = <_Seg>[];
    bool hl = false;
    for (final int r in widget.text.runes) {
      final String ch = String.fromCharCode(r);
      if (ch == '[') {
        hl = true;
        continue;
      }
      if (ch == ']') {
        hl = false;
        continue;
      }
      out.add(_Seg(ch, hl));
    }
    _segs = out;
    _shown = 0;
    _all = false;
  }

  void _start() {
    _timer?.cancel();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _all = true;
      _shown = _segs.length;
      return;
    }
    _timer = Timer.periodic(widget.speed, (Timer t) {
      if (!mounted) return;
      if (_shown >= _segs.length) {
        t.cancel();
        setState(() {});
        return;
      }
      setState(() => _shown++);
    });
  }

  void _skip() {
    _timer?.cancel();
    setState(() {
      _all = true;
      _shown = _segs.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool typing = !_all && _shown < _segs.length;
    final TextStyle hl =
        widget.highlightStyle ??
        widget.style.copyWith(
          fontFamily: Ref.fd,
          fontSize: (widget.style.fontSize ?? 15) * 1.15,
          color: Ref.acid,
          shadows: <Shadow>[
            Shadow(color: Ref.a(Ref.acid, .55), blurRadius: 12),
          ],
        );

    // 把已显形的字符按「是否高亮」合并成 span，避免一句话几百个 span
    final List<InlineSpan> spans = <InlineSpan>[];
    String buf = '';
    bool bufHl = false;
    void flush() {
      if (buf.isEmpty) return;
      spans.add(TextSpan(text: buf, style: bufHl ? hl : widget.style));
      buf = '';
    }

    for (int i = 0; i < _shown && i < _segs.length; i++) {
      final _Seg s = _segs[i];
      if (s.hl != bufHl) {
        flush();
        bufHl = s.hl;
      }
      buf += s.ch;
    }
    flush();
    if (typing) {
      spans.add(
        TextSpan(
          text: '▌',
          style: widget.style.copyWith(color: Ref.acid),
        ),
      );
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: widget.maxLines,
      textAlign: widget.textAlign,
      overflow: widget.overflow,
      softWrap: widget.softWrap,
    );
  }
}

class _Seg {
  const _Seg(this.ch, this.hl);
  final String ch;
  final bool hl;
}
