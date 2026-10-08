import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../state/voice.dart';

/// ═══════════════════════════════════════════════════════════
///  SYSTEM 后面那排跳动的波形条（`ui.js` L70-73）
///
///  ```js
///  Stage.onTick.push(() => {
///    const m = Voice.mouth, t = performance.now() / 85;
///    bars.forEach((b, i) => b.style.transform =
///      `scaleY(${clamp(.14 + m * (.55 + .45 * Math.sin(t + i * 1.7)), .12, 1)})`);
///  });
///  ```
///
///  静止时 `m = 0` → `scaleY(.14)`，与 CSS 的 `.line .wave i { transform: scaleY(.15) }`
///  几乎一致 —— 所以"没在说话"时它跟静态版看起来一样，**不会破坏任何既有截图**。
/// ═══════════════════════════════════════════════════════════
class VoiceBars extends StatefulWidget {
  const VoiceBars({
    super.key,
    required this.voice,
    required this.color,
    this.count = 5,
    this.enabled = true,
  });

  final VoiceEnvelope voice;
  final Color color;
  final int count;

  /// 关掉时退化成静态高度（例如 `prefers-reduced-motion` 之类的场合）
  final bool enabled;

  @override
  State<VoiceBars> createState() => _VoiceBarsState();
}

class _VoiceBarsState extends State<VoiceBars>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _ticker.start();
  }

  @override
  void didUpdateWidget(covariant VoiceBars old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!widget.enabled && _ticker.isActive) {
      _ticker.stop();
      widget.voice.reset();
    }
  }

  void _onTick(Duration now) {
    final double dt = _last == Duration.zero
        ? 1 / 60
        : (now - _last).inMicroseconds / 1e6;
    _last = now;
    widget.voice.tick(dt);
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 原型的时间基：performance.now() / 85
    final double t = _last.inMicroseconds / 1000 / 85;
    return SizedBox(
      height: 12,
      child: Row(
        children: List<Widget>.generate(widget.count, (int i) {
          final double k = widget.enabled
              ? VoiceEnvelope.barScale(i, widget.voice.mouth, t)
              : .15;
          return Padding(
            padding: EdgeInsets.only(right: i == widget.count - 1 ? 0 : 2),
            child: SizedBox(
              width: 2,
              height: 12,
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  width: 2,
                  // 12 * scaleY，origin 是 center（CSS `transform-origin: center`）
                  height: 12 * k,
                  decoration: BoxDecoration(
                    color: widget.color.withAlpha(
                      (widget.color.a * 255 * .9).round(),
                    ),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
