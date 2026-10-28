import 'package:flutter/material.dart';

import '../../design/ref.dart';
import 'ref_core.dart';

/// 开机屏 —— 参考稿 #boot（CSS L501-512，DOM L850-857）
///
/// #boot：铺满、z100、padding 30、背景
///   radial-gradient(circle at 50% 38%, #1a1436, #06050c 65%)；
/// 170×170 的系统核心 → HOST // SYSTEM 字标（40 italic / 字距 3）→
/// 副标题（13 / 字距 6）→ 日志区（300 宽 / 11.5 mono / 1.75 行高 / 最少 110）
/// → 3 高渐变进度条 → 「点击唤醒系统 / TAP TO START」。
///
/// 参考稿是「点一下直接开始」；项目现状是异步铺日志 + 门禁。
/// 行为保留项目的，视觉照参考稿。
class RefBoot extends StatefulWidget {
  const RefBoot({
    super.key,
    required this.lines,
    required this.progress,
    required this.ready,
    required this.onWake,
    this.gone = false,
  });

  final List<String> lines;
  final double progress;
  final bool ready;
  final VoidCallback? onWake;
  final bool gone;

  @override
  State<RefBoot> createState() => _RefBootState();
}

class _RefBootState extends State<RefBoot> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _blink.stop();
    } else if (!_blink.isAnimating) {
      _blink.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: widget.gone,
      child: AnimatedOpacity(
        opacity: widget.gone ? 0 : 1,
        duration: const Duration(milliseconds: 600),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => widget.onWake?.call(),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -.24),
                radius: .95,
                colors: <Color>[Color(0xFF1A1436), Color(0xFF06050C)],
                stops: <double>[0, .65],
              ),
            ),
            child: SizedBox.expand(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const RefCore(size: 170, mood: CoreMood.neutral),
                    const SizedBox(height: 22),
                    _logo(),
                    const SizedBox(height: 10),
                    Text(
                      '宿 主 养 成 计 划',
                      style: refText(
                        family: Ref.fc,
                        size: 13,
                        wght: 500,
                        ls: 6,
                        height: 1.2,
                        color: Ref.dim,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _log(),
                    const SizedBox(height: 8),
                    _bar(),
                    const SizedBox(height: 30),
                    _go(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// .boot-logo（L503-504）：40px italic、字距 3；中间 // 是 acid + 20 辉光。
  ///
  /// ⚠️ 三段 40px + 字距 3 在参考稿里放得下（Chakra Petch 窄），但**字体没
  ///    加载时**回退到系统宽字体，实测撑出 `overflowed by 202 pixels`。
  ///    FittedBox 让它在窄环境里等比收，不做横向溢出。
  Widget _logo() {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'HOST',
            style: refText(
              family: Ref.fd,
              size: 40,
              wght: 700,
              italic: true,
              ls: 3,
              height: 1,
              color: Ref.txt,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '//',
            style: refText(
              family: Ref.fd,
              size: 40,
              wght: 700,
              italic: true,
              ls: 3,
              height: 1,
              color: Ref.acid,
              shadows: <Shadow>[Shadow(color: Ref.acid, blurRadius: 20)],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'SYSTEM',
            style: refText(
              family: Ref.fd,
              size: 40,
              wght: 700,
              italic: true,
              ls: 3,
              height: 1,
              color: Ref.txt,
            ),
          ),
        ],
      ),
    );
  }

  /// .boot-log（L506-507）
  Widget _log() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300, minHeight: 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final String line in widget.lines) _LogLine(text: line),
        ],
      ),
    );
  }

  /// .boot-bar（L508-509）：3 高、白 8%、r2、violet→acid + 12 辉光
  Widget _bar() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: SizedBox(
        height: 3,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Stack(
            children: <Widget>[
              const Positioned.fill(
                child: ColoredBox(color: Color(0x14FFFFFF)),
              ),
              // ⚠️ heightFactor 必须给 1：Stack 给的是松约束（0..3），
              //    不给就塌成 0 高 —— 进度条整条看不见。
              // .boot-bar i{transition:width .3s}
              AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 300),
                alignment: Alignment.centerLeft,
                widthFactor: widget.progress.clamp(0.0, 1.0),
                heightFactor: 1,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[Ref.violet, Ref.acid],
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(color: Ref.acid, blurRadius: 12),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// .boot-go（L510-512）：900 18 / 字距 6；.on 后呼吸
  Widget _go() {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 500),
      opacity: widget.ready ? 1 : 0,
      child: AnimatedBuilder(
        animation: _blink,
        builder: (BuildContext context, Widget? child) {
          final bool reduce =
              MediaQuery.maybeDisableAnimationsOf(context) ?? false;
          final double t = reduce ? 1 : 1 - .75 * _blink.value;
          return Opacity(opacity: widget.ready ? t : 0, child: child);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '点击唤醒系统',
              style: refText(
                family: Ref.fc,
                size: 18,
                wght: 900,
                ls: 6,
                height: 1.2,
                color: Ref.txt,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'TAP TO START',
              style: refText(
                family: Ref.fm,
                size: 10,
                wght: 700,
                ls: 6,
                height: 1,
                color: Ref.acid,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// .boot-log 的一行：> ...，其中 ✓ 转 acid
class _LogLine extends StatelessWidget {
  const _LogLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final TextStyle base = refText(
      family: Ref.fm,
      size: 11.5,
      wght: 400,
      height: 1.75,
      color: Ref.dim,
    );
    final TextStyle ok = refText(
      family: Ref.fm,
      size: 11.5,
      wght: 700,
      height: 1.75,
      color: Ref.acid,
    );
    final List<InlineSpan> spans = <InlineSpan>[
      TextSpan(text: '> ', style: base),
    ];
    final List<String> parts = text.split('✓');
    for (int i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) spans.add(TextSpan(text: parts[i], style: base));
      if (i < parts.length - 1) spans.add(TextSpan(text: '✓', style: ok));
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Ref.ease,
      builder: (BuildContext context, double v, Widget? child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(-12 * (1 - v), 0),
          child: child,
        ),
      ),
      // 必须允许换行：真字体下每条都塞得进 300，但字体没加载时
      // （离屏出图 / 裸 test 环境）会回退到更宽的系统字体，实测撑出
      // RenderFlex overflowed by 202 pixels —— 软换行兜住这一档。
      child: Text.rich(TextSpan(style: base, children: spans), softWrap: true),
    );
  }
}
