import 'package:flutter/material.dart';

import '../data/format.dart';
import '../design/tokens.dart';
import '../state/sfx.dart';

/// ═══════════════════════════════════════════════════════════
///  「执行中」药丸（`index.html` L40 + `ui.js` L59-61 + `css` `.pill`）
///
///  ```html
///  <div id="execPill" class="pill"><i></i><span>执行中</span><b id="pillT">00:00</b></div>
///  ```
///  ```js
///  pill.classList.toggle('on', !!S.active && ['lobby','main','sheet'].includes(App.mode));
///  if (S.active) $('#pillT').textContent = fmtClock(Clock.now() - S.active.startAt);
///  ```
///  **执行页本身不显示它**（那边有面板里的大计时器），点它回到执行页。
///
///  `.pill`: top 80 居中 · 高 28 · 圆角 14 · `rgba(4,14,32,.78)` + inset 1px 线
///  进出：`opacity .3s` + `transform .4s --out`（从 `translate(-50%,-8px)` 落到 0）
///  `.pill i`: 7px 蓝点 + `blinkdot 1.2s steps(2) infinite`（后半个周期 opacity .25）
/// ═══════════════════════════════════════════════════════════
class ExecPill extends StatefulWidget {
  const ExecPill({
    super.key,
    required this.visible,
    required this.elapsed,
    this.onTap,
  });

  final bool visible;

  /// 已经执行了多久（原型 `Clock.now() - S.active.startAt`）
  final Duration elapsed;

  final VoidCallback? onTap;

  @override
  State<ExecPill> createState() => _ExecPillState();
}

class _ExecPillState extends State<ExecPill>
    with SingleTickerProviderStateMixin {
  /// `blinkdot 1.2s steps(2) infinite`
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 80,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(
              begin: widget.visible ? 1 : 0,
              end: widget.visible ? 1 : 0,
            ),
            duration: const Duration(milliseconds: 400),
            curve: const Cubic(.16, 1, .3, 1), // --out
            builder: (BuildContext _, double k, Widget? child) => Opacity(
              opacity: k.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, -8 * (1 - k)),
                child: child,
              ),
            ),
            child: GestureDetector(
              // 执行药丸：原型 `main.js:60` `$('#execPill')` → 只 `Sound.play('tap')`
              onTap: widget.onTap == null
                  ? null
                  : () {
                      Sfx.play('tap');
                      widget.onTap!();
                    },
              child: Container(
                key: const Key('exec.pill'),
                height: 28,
                padding: const EdgeInsets.fromLTRB(
                  9,
                  0,
                  14,
                  0,
                ), // CSS 0 14 0 10，Border 占 1
                decoration: BoxDecoration(
                  color: const Color(0xC7040E20), // rgba(4,14,32,.78)
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: C.line, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    AnimatedBuilder(
                      animation: _blink,
                      builder: (BuildContext _, Widget? _) => Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: C.blue.withAlpha(
                            _blink.value < .5 ? 255 : 64, // 50% 关键帧：opacity .25
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(color: C.blue, blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '执行中',
                      style: fs(
                        family: F.cn,
                        size: 11,
                        wght: 400,
                        height: 1,
                        color: C.mist,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      fmtClock(widget.elapsed),
                      style: fs(
                        family: F.num,
                        size: 14,
                        wght: 700,
                        ls: .56,
                        height: 1,
                        color: C.ice,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
