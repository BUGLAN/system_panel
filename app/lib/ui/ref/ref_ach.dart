import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../design/ref.dart';

/// ═══════════════════════════════════════════════════════════
///  顶部提示条 + 名牒解锁卡
///
///  唯一基准：宿主养成系统_重设计.html
///    · RefToast   CSS L409-413 / JS L1117-1122
///    · RefAchCard CSS L414-419 / DOM L1131-1136
///
///  【布局契约】两者都是**普通 Widget**，顶层没有 Positioned —— 摆位由调用方
///  决定。参考稿里它们挂在 #toasts 这个绝对定位栈上（L409）：
///
///      Stack(children: <Widget>[
///        page,
///        Positioned(
///          top: MediaQuery.paddingOf(context).top + 14,      // safe + 14
///          left: 14,                                         // L409
///          right: 14,
///          child: Column(children: <Widget>[ ...toasts ]),    // gap 8
///        ),
///      ])
///
///  【动效契约】RefToast 自带进场（JS L1120 的 400ms 弹入），RefAchCard 自带
///  两次斜向高光（L415）。控制器都在 State 里、dispose 释放；MediaQuery
///  .maybeDisableAnimationsOf 为真时直接落终态、一次都不 repeat。
/// ═══════════════════════════════════════════════════════════

/// .toast 的三档（L410-413）：normal 青点 / ok 酸绿点 / err 品红点
enum RefToastKind { normal, ok, err }

/// .toast（L410）：padding 11 16 / r14 / rgba(16,14,30,.94) / 1px line /
/// 500 14px/1.45 / 0 14px 40px rgba(0,0,0,.6) / blur 10
const double _kToastR = 14;
const double _kToastPadH = 16;
const double _kToastPadV = 11;
const double _kToastDot = 8;
const double _kToastGap = 10; // .toast{gap:10px}（L410）

/// .ach（L414）：padding 12 16 / r16 / gap 14 / 1.5px gold
const double _kAchR = 16;
const double _kAchMedal = 44;
const double _kAchMedalR = 12;

/// @keyframes holo（L366）：左上 150% → 右下 -100%，1.6s linear ×2 次（L415）
const int _kHoloMs = 1600;
const int _kHoloPasses = 2;

Color _dotOf(RefToastKind k) => switch (k) {
  RefToastKind.normal => Ref.cyan, // .toast i{background:var(--cyan)}（L411）
  RefToastKind.ok => Ref.acid, // .toast.ok i（L413）
  RefToastKind.err => Ref.hot, // .toast.err i（L412）
};

Color _borderOf(RefToastKind k) => switch (k) {
  RefToastKind.normal => Ref.line, // border:1px solid var(--line)（L410）
  RefToastKind.ok => Ref.a(Ref.acid, .45), // rgba(214,255,61,.45)（L413）
  RefToastKind.err => Ref.a(Ref.hot, .5), // rgba(255,59,122,.5)（L412）
};

/// ═══════════════════════════════════════════════════════════════
///  RefToast —— 顶部提示条（L409-413）
///
///  进场照 JS L1120：`opacity 0 + translateY(-30px) scale(.9)` → none，
///  400ms `cubic-bezier(.2,1.4,.4,1)`。退场（JS L1121 的 2600ms 后淡出）属于
///  消息队列的编排，由调用方删掉本 Widget 即可，不在这里抢。
/// ═══════════════════════════════════════════════════════════════
class RefToast extends StatefulWidget {
  const RefToast({
    super.key,
    required this.message,
    this.kind = RefToastKind.normal,
  });

  final String message;
  final RefToastKind kind;

  @override
  State<RefToast> createState() => _RefToastState();
}

class _RefToastState extends State<RefToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400), // JS L1120
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _in.value = 1;
    } else {
      _in.forward();
    }
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color dot = _dotOf(widget.kind);
    return AnimatedBuilder(
      animation: _in,
      builder: (BuildContext context, Widget? child) {
        final double k = Ref.pop.transform(_in.value);
        return Opacity(
          opacity: _in.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -30 * (1 - k)), // translateY(-30px)
            child: Transform.scale(
              scale: .9 + .1 * k, // scale(.9) → 1
              child: child,
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_kToastR),
        child: BackdropFilter(
          // .toast{backdrop-filter:blur(10px)}（L410）
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: _kToastPadH,
              vertical: _kToastPadV,
            ),
            decoration: BoxDecoration(
              color: const Color(0xF0100E1E), // rgba(16,14,30,.94)（L410）
              borderRadius: BorderRadius.circular(_kToastR),
              border: Border.all(color: _borderOf(widget.kind)),
              boxShadow: const <BoxShadow>[
                // box-shadow:0 14px 40px rgba(0,0,0,.6)（L410）
                BoxShadow(
                  color: Color(0x99000000),
                  offset: Offset(0, 14),
                  blurRadius: 40,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // .toast i：8×8 圆 + 0 0 10px 同色辉光（L411-413）
                Container(
                  width: _kToastDot,
                  height: _kToastDot,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dot,
                    boxShadow: <BoxShadow>[
                      BoxShadow(color: dot, blurRadius: 10),
                    ],
                  ),
                ),
                const SizedBox(width: _kToastGap),
                Flexible(
                  child: Text(
                    widget.message,
                    style: refText(
                      size: 14, // L410 font:500 14px/1.45
                      wght: 500,
                      height: 1.45,
                      color: Ref.txt,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ═══════════════════════════════════════════════════════════════
///  RefAchCard —— 名牒解锁卡（CSS L414-419 / DOM L1131-1136）
///
///  · 底：`linear-gradient(110deg,#3a2a08,#1a1424 60%)`
///  · 边：1.5px gold；光：`0 0 34px rgba(255,204,77,.35)` +
///        `0 14px 40px rgba(0,0,0,.6)`
///  · padding 12 16 / r16 / gap 14
///  · 左：44×44 rotate45 的 gold 方块（内底 r12、外光 0 0 18px），
///        内部反旋 -45 的序号 `900 18px`，字色 #1a1200
///  · 文：small `700 10px` mono 字距 3 gold / b `900 17px` /
///        p `400 12px` #cfc6a8
///  · ::after 一道 `linear-gradient(110deg,transparent 30%,#fff .35 45%,
///    transparent 60%)` 的 250% 斜向高光，1.6s linear 跑 2 次（L415/L366）
/// ═══════════════════════════════════════════════════════════════
class RefAchCard extends StatefulWidget {
  const RefAchCard({
    super.key,
    required this.index,
    required this.name,
    required this.hint,
  });

  /// 名牒序号（DOM L1132 的 `pad(id)` 是两位补零，这里收 int）
  final int index;

  /// 「名牒标题」
  final String name;

  /// 一行说明（JS L1132 拼的是 `${T.h} · 去档案佩戴`）
  final String hint;

  @override
  State<RefAchCard> createState() => _RefAchCardState();
}

class _RefAchCardState extends State<RefAchCard>
    with SingleTickerProviderStateMixin {
  /// `.ach::after{animation:holo 1.6s linear 2}`（L415）
  late final AnimationController _holo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _kHoloMs),
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _holo.value = 1; // 终态：高光走完、不再重播
    } else {
      _holo.repeat(count: _kHoloPasses);
    }
  }

  @override
  void dispose() {
    _holo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String no = widget.index.toString().padLeft(2, '0');
    return ClipRRect(
      borderRadius: BorderRadius.circular(_kAchR),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          // linear-gradient(110deg,#3a2a08,#1a1424 60%)（L414）
          gradient: const LinearGradient(
            begin: Alignment(-.94, -.34), // 110deg
            end: Alignment(.94, .34),
            colors: <Color>[Color(0xFF3A2A08), Color(0xFF1A1424)],
            stops: <double>[0, .6],
          ),
          borderRadius: BorderRadius.circular(_kAchR),
          border: Border.all(color: Ref.gold, width: 1.5), // 1.5px gold（L414）
          boxShadow: <BoxShadow>[
            BoxShadow(color: Ref.a(Ref.gold, .35), blurRadius: 34), // L414
            const BoxShadow(
              color: Color(0x99000000), // rgba(0,0,0,.6)
              offset: Offset(0, 14),
              blurRadius: 40,
            ),
          ],
        ),
        child: Stack(
          children: <Widget>[
            Row(
              children: <Widget>[
                // .medal（L416-417）：44×44 rotate45 / r12 / gold / 0 0 18px
                Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(
                    width: _kAchMedal,
                    height: _kAchMedal,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Ref.gold,
                      borderRadius: BorderRadius.circular(_kAchMedalR),
                      boxShadow: <BoxShadow>[
                        BoxShadow(color: Ref.gold, blurRadius: 18),
                      ],
                    ),
                    child: Transform.rotate(
                      angle: -math.pi / 4, // 内部反旋 -45（L417）
                      child: Text(
                        no,
                        style: refText(
                          size: 18, // L417 font:900 18px
                          wght: 900,
                          height: 1,
                          color: const Color(0xFF1A1200),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14), // gap:14（L414）
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // .ach small（L418）：700 10px mono / ls 3 / gold
                      Text(
                        '名牒解锁 · NEW TITLE',
                        style: refText(
                          family: Ref.fm,
                          size: 10,
                          wght: 700,
                          ls: 3,
                          height: 1.4,
                          color: Ref.gold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // .ach b（L419）：900 17px
                      Text(
                        '「${widget.name}」',
                        style: refText(
                          size: 17,
                          wght: 900,
                          height: 1.3,
                          color: Ref.txt,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // .ach p（L420）：400 12px / #cfc6a8
                      Text(
                        widget.hint,
                        style: refText(
                          size: 12,
                          wght: 400,
                          height: 1.4,
                          color: const Color(0xFFCFC6A8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // ::after（L415）：250% 宽的斜向高光，1.6s linear ×2
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _holo,
                  builder: (BuildContext context, Widget? _) {
                    return CustomPaint(
                      painter: _HoloPainter(phase: _holo.value),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.ach::after`（L415）+ `@keyframes holo`（L366）
///
/// `from{background-position:150% 0} to{background-position:-100% 0}`，
/// `background-size:250% 100%`；斜向 110deg 的 30%/45%/60% 三点白带。
class _HoloPainter extends CustomPainter {
  const _HoloPainter({required this.phase});

  final double phase;

  @override
  void paint(Canvas canvas, Size s) {
    // background-size 250% → 高光带总宽 2.5w；位移 150% → -100% 共 2.5w
    final double bandW = s.width * 2.5;
    final double x = s.width * 1.5 - phase * s.width * 2.5;
    final Rect band = Rect.fromLTWH(x, -s.height, bandW, s.height * 3);
    if (!band.overlaps(Offset.zero & s)) return;
    canvas.save();
    canvas.clipRect(Offset.zero & s);
    canvas.save();
    // 110deg 的斜切：把画布转 -20deg（CSS 的 110deg = 从左上往右下偏 20）
    canvas.translate(s.width / 2, s.height / 2);
    canvas.rotate(-20 * math.pi / 180);
    canvas.translate(-s.width / 2, -s.height / 2);
    canvas.drawRect(
      band.inflate(s.height),
      Paint()
        ..shader = const LinearGradient(
          colors: <Color>[
            Color(0x00FFFFFF),
            Color(0x59FFFFFF), // rgba(255,255,255,.35)
            Color(0x00FFFFFF),
          ],
          stops: <double>[.3, .45, .6],
        ).createShader(band.inflate(s.height)),
    );
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HoloPainter old) => old.phase != phase;
}
