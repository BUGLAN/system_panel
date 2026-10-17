import 'dart:async';

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
///
///  ── docs/39 §5.5 性能收口（P2，2026-10-17）────────────────────
///  原实现：一条 **60fps Ticker 常驻**（只有 `enabled=false` 才停）。哪怕她
///  一个字都没说，也每帧 setState 重建五根 2px 的条 —— 这排条在**每一页**都
///  挂着（字幕层常驻），是典型的"看起来静态、实则满帧刷"。
///
///  现在：**只在真有东西可动时才跑 60fps**。
///   · 说话中（`target > 0` 或 `mouth > 阈值`）→ Ticker 跑，公式逐字照抄原型；
///   · 说完 / 没台词 → Ticker **停**，换一条 **20Hz 探针 Timer**；
///   · 探针只做一件事：`mouth` 继续按公式衰减 + 看目标是否又抬起来
///     （下一个字由 `VoiceEnvelope.syllable` 写进去，这里没有回调可订阅，
///     又不想为这一处去改 `state/voice.dart` 的接口）。探针 **不产帧、
///     不重建 widget**，与原来那种 60fps 的无效重建不是一个量级。
///   · 静止时画面与旧版**逐像素相同**（m = 0 → 五根条都是 .14 定值）。
///  ⚠️ 探针在 dispose 里取消；Ticker 也先停再 dispose（`dispose` 之后不再跑）。
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

  /// 空闲探针（见类注释）：没在说话时以 20Hz 看两眼，不重建。
  Timer? _idle;

  /// 探针周期：**50ms（20Hz）**。
  ///
  /// 为什么是 50 而不是 100：探针还在负责"发现下一个字开始了"——`syllable` 由
  /// 打字机逐字写进包络，VoiceBars 这边没有回调可订阅（改那层的接口不在本批
  /// 写入面），只能轮询。50ms ≈ 3 帧，字一冒出来就点回 60fps，肉眼接得上；
  /// 100ms 会看见波形条"卡一下才动"。
  /// 而且探针**不产帧、不 setState**——和原来那条常驻 60fps Ticker 不是一个量级。
  static const Duration _idlePeriod = Duration(milliseconds: 50);

  /// 低于这个开口度就当闭嘴（静止时是 0；取 .002 避免浮点永远差一点）
  static const double _mouthEps = .002;

  /// 现在有没有东西可动：目标抬起来了，或者还没落回去
  bool get _speaking =>
      widget.voice.target > 0 || widget.voice.mouth > _mouthEps;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant VoiceBars old) {
    super.didUpdateWidget(old);
    if (widget.enabled != old.enabled) {
      if (!widget.enabled) widget.voice.reset();
      _syncTicker();
    }
  }

  /// 统一收口 Ticker / 探针的起停（只在状态真的变了才动，避免每帧重排）
  void _syncTicker() {
    final bool want = widget.enabled && _speaking;
    // ⚠️ 早退的判据必须把「探针该在不在」也算进去：只看 Ticker 的话，
    //    `want == false && ticker 不在跑` 会直接 return，探针永远起不来，
    //    于是"没台词时怎么发现下一个字"这条路是死的（这里第一版就踩了）。
    final bool probeWant = widget.enabled && !want;
    if (want == _ticker.isActive && probeWant == (_idle != null)) return;
    if (want) {
      _idle?.cancel();
      _idle = null;
      _last = Duration.zero; // 相位从 0 起，delta 用 1/60 兜第一拍
      _ticker.start();
    } else {
      if (_ticker.isActive) _ticker.stop();
      if (!widget.enabled) {
        _idle?.cancel();
        _idle = null;
      } else {
        // 没台词 ≠ 永远没台词：20Hz 探针等下一个字（不产帧、不 setState）
        _idle ??= Timer.periodic(_idlePeriod, (Timer _) => _onProbe());
      }
    }
  }

  /// 空闲探针：把包络按探针周期推一下（让它落回去），有动静再点回 60fps
  void _onProbe() {
    if (!mounted) return;
    widget.voice.tick(_idlePeriod.inMicroseconds / 1e6);
    if (_speaking) {
      _syncTicker(); // 目标抬起来了 → 换 Ticker
    } else if (widget.voice.mouth != 0) {
      // 已经落到底：清成精确 0，与旧版静止态（scaleY(.14) 定值）对齐
      widget.voice.mouth = 0;
    }
  }

  void _onTick(Duration now) {
    final double dt = _last == Duration.zero
        ? 1 / 60
        : (now - _last).inMicroseconds / 1e6;
    _last = now;
    widget.voice.tick(dt);
    if (!_speaking) {
      // 说完了：这一拍照旧落画面（回到 .14），下一拍起换成探针
      setState(() {});
      _syncTicker();
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _idle?.cancel();
    _idle = null;
    if (_ticker.isActive) _ticker.stop();
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
