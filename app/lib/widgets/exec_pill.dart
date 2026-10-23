import 'package:flutter/material.dart';

import '../data/format.dart';
import '../design/tokens.dart';
import '../dev/agent_bridge.dart';
import '../state/sfx.dart';
import 'rail_base.dart';

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
///
///  ── docs/39 H-16（2026-10-17 走查 · P1）──────────────────────
///  真机上这颗药丸**从不播入场**：原来写的是 `TweenAnimationBuilder(tween:
///  Tween(begin: visible ? 1 : 0, end: visible ? 1 : 0))` —— begin 与 end 是
///  **同一个表达式**，于是 400ms 那条动画只是「从终态走到终态」，一帧都不动
///  （走查 §0.4「执行药丸的 400ms 入场是死代码」）。
///
///  改成显式的 `AnimationController` 边沿驱动（`AnimatedVisibility` 语义）：
///   · 进：**200ms** 淡入 + **8px 下落**（从 `translateY(-8)` 落到 0）
///   · 出：**160ms** 淡出（不再有位移，先没再落 —— 出场不该抢戏）
///   · 减弱动态效果：直接落终态，不挂任何动画（railReduceMotion）
///   · 闪烁 1.2s → **2.4s**（`Motion.heartMs`，与 CTA 呼吸 / 进度带弧头同相位）
///
///  ⚠️ 性能（§5.5）：只对**这一颗 28 高的小药丸**做 Opacity，不是整屏、不是
///     玻璃卡；没有新增常驻 saveLayer。
/// ═══════════════════════════════════════════════════════════

/// docs/39 H-16：入场 200ms / 出场 160ms（§5.1「退场 = 进场的 60%」≈ 120ms，
/// 这里按方案表取 160ms —— 药丸太小，120 会显得"啪"地没了）
const int kExecPillInMs = 200;
const int kExecPillOutMs = 160;

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

class _ExecPillState extends State<ExecPill> with TickerProviderStateMixin {
  /// `.pill i` 的闪烁：docs/39 H-16 → `blinkdot 2.4s steps(2) infinite`
  /// （原来 1200ms；2.4s 与 `Motion.heartMs` 同相位，全屏可感知循环只剩
  ///  「她 + 心跳」两条 —— §5.1 的硬约束）
  ///
  /// ⚠️ **不可见时不跑**（§5.5 性能纪律）：药丸绝大多数时间是不显示的，
  ///    让它常驻一个 60fps 的 repeat 只是为了在 opacity 0 下面闪一个看不见的点。
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: Motion.heartMs),
  );

  /// 进出场（0 = 完全收起，1 = 完全展开）。
  /// 首帧就按 [ExecPill.visible] 落位：不可见时 0，可见时 1（**不播首屏入场**，
  /// 进页面硬切的那一帧不该再补一个动画 —— 与 Hud/Dock 的 fade 同纪律）。
  late final AnimationController _fade = AnimationController(
    vsync: this,
    value: widget.visible ? 1 : 0,
    duration: const Duration(milliseconds: kExecPillInMs),
  );

  @override
  void initState() {
    super.initState();
    if (widget.visible) _blink.repeat();
  }

  @override
  void didUpdateWidget(covariant ExecPill old) {
    super.didUpdateWidget(old);
    // 闪烁只在"看得见"的时候跑（见 _blink 的注释）
    if (widget.visible != old.visible) {
      if (widget.visible) {
        _blink.repeat();
      } else {
        _blink.stop();
      }
    }
    if (old.visible == widget.visible) return;
    // 减弱动态：直接落终态（§5.5「reduceMotion 要落终态」）
    if (railReduceMotion(context)) {
      _fade.value = widget.visible ? 1 : 0;
      return;
    }
    if (widget.visible) {
      _fade.duration = const Duration(milliseconds: kExecPillInMs);
      _fade.forward(from: 0);
    } else {
      _fade.duration = const Duration(milliseconds: kExecPillOutMs);
      _fade.reverse();
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ 用 Positioned 之外再套一层：本组件挂在 Stack 里，顶层必须是 Positioned
    //    （与 Hud/Dock 同一铁律 —— 外面再包带 RenderObject 的件会报 ParentDataWidget）
    return Positioned(
      top: 80,
      left: 0,
      right: 0,
      child: IgnorePointer(
        // 收起途中（还没到 0）也别吃点击：fade 结束时才放开
        ignoring: !widget.visible,
        child: AnimatedBuilder(
          animation: _fade,
          builder: (BuildContext _, Widget? child) {
            // 原型 `.pill` 的 transform 走 `--out`（= [kOut]）：进场带一点冲刺感，
            // 出场同一条曲线反向（不另配 easeIn，CSS 里也只有一条 transition）
            final double k = kOut.transform(_fade.value);
            // 出场走的是 reverse，k 从 1 → 0；位移只在**进场**那一段参与
            // （k 从 0 → 1 时 8px 下落；出场时不再挪，避免"先上飘再消失"）
            final double dy = widget.visible ? -8 * (1 - k) : 0;
            return Opacity(
              opacity: k.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, dy),
                child: child,
              ),
            );
          },
          child: Center(
            child: AgentTag(
              id: 'exec.pill',
              label: '执行中计时',
              button: true,
              role: '状态胶囊',
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
      ),
    );
  }
}
