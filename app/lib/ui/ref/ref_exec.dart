import 'package:flutter/material.dart';

import '../../design/ref.dart';
import '../../state/quest.dart';
import 'ref_inputs.dart';
import 'ref_kit.dart';
import 'ref_orb.dart';

/// ═══════════════════════════════════════════════════════════
///  执行页 —— 参考稿 #sc-exec（CSS L265-329，DOM L742-765）
///
///  .ex-h（档位章 + 执行中 + 单号）→ .ex-t（26px 标题）→ .timer（104px 计时）
///  → .tbar（8 高进度 + 5 刻度 + 白端点）/ .tmeta → .watch（SYSTEM 在看你）
///  → .evi（82 证据槽 + 说明）→ 动作区（道具 / 提交 · 让她验收）
///  → 第二排（按住认输 1600ms / 收起）
/// ═══════════════════════════════════════════════════════════
class RefExec extends StatelessWidget {
  const RefExec({
    super.key,
    required this.quest,
    required this.elapsed,
    this.critChance = 0,
    this.evidenceThumbs = const <Widget>[],
    this.onAddEvidence,
    this.onDemoEvidence,
    this.onRemoveEvidence,
    this.onSubmit,
    this.onQuitProgress,
    this.onQuit,
    this.onCollapse,
    this.onItems,
    this.itemCount = 0,
    this.equipped = 0,
    this.tray,
    this.watchText = '正在看着你',
    this.watchAlert = false,
    this.speed = 1,
  });

  final Quest quest;
  final Duration elapsed;
  final double critChance;

  /// 已上传的证据缩略图（0~3 张）
  final List<Widget> evidenceThumbs;
  final VoidCallback? onAddEvidence;

  /// 参考稿 .link『⚡ 用演示截图 ›』（L755 / JS L1440）：没相机时也能验证流程
  final VoidCallback? onDemoEvidence;
  final ValueChanged<int>? onRemoveEvidence;
  final VoidCallback? onSubmit;
  final ValueChanged<double>? onQuitProgress;
  final VoidCallback? onQuit;
  final VoidCallback? onCollapse;
  final VoidCallback? onItems;
  final int itemCount;

  /// 本单已装载的道具件数（.eqn 徽标）
  final int equipped;

  /// 道具托盘（[RefItemTray]，嵌在正文与动作区之间）
  final Widget? tray;

  /// watch 那一句（她实时换）
  final String watchText;

  /// watch.alert → hot
  final bool watchAlert;

  /// 时间倍率（⏩ ×N）
  final int speed;

  /// 脸的下沿（屏幕 y）—— 见 RefHome 的同名字段；由 main.dart 用

  @override
  Widget build(BuildContext context) {
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    final Duration limit = Duration(minutes: quest.minutes);
    final double progress = limit.inMilliseconds <= 0
        ? 0
        : (elapsed.inMilliseconds / limit.inMilliseconds).clamp(0.0, 1.0);
    final Color gc = Ref.rankOf(quest.rank);
    // 参考稿 .scene 的 94 上边距（HUD 底下那一段）。
    final double top = safe.top + Ref.sceneTop;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Ref.gutter,
        top,
        Ref.gutter,
        safe.bottom + Ref.sceneBottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 中段可滚：脸的下沿会把内容起点往下推（不挡脸），矮屏上
          // 「抬头 + 标题 + 计时 + 条 + watch + 证据」不一定装得下 ——
          // 让它们滚，动作区永远钉在底部（提交键不许被挤出屏幕）。
          Expanded(
            // .tray 挂在这一层（z6），动作区是后一个兄弟（z7）—— 暗幕盖住
            // 正文但不盖按钮，与参考稿的层级一致。
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned.fill(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _head(gc),
                        const SizedBox(height: 10),
                        Text(
                          quest.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: refText(
                            family: Ref.fc,
                            size: 26,
                            wght: 900,
                            ls: .5,
                            height: 1.2,
                            color: Ref.txt,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _timer(context, progress),
                        const SizedBox(height: 10),
                        RefProgressBar(value: progress, ticks: 5),
                        const SizedBox(height: 10),
                        _tmeta(progress, limit),
                        const SizedBox(height: 16),
                        _watch(),
                        const SizedBox(height: 16),
                        _evi(),
                      ],
                    ),
                  ),
                ),
                if (tray != null) tray!,
              ],
            ),
          ),
          const SizedBox(height: 12),
          _actions(),
        ],
      ),
    );
  }

  /// .ex-h（L266-270）
  Widget _head(Color gc) {
    final String code = quest.kind == 'main'
        ? 'MAIN ${quest.planIndex + 1}/${quest.planTotal}'
        : (quest.kind == 'remedy'
              ? 'REMEDY · ${quest.serial}'
              : 'DAILY · ${quest.serial}');
    return Row(
      children: <Widget>[
        RefRankBadge(rank: quest.rank, size: 34, color: gc),
        const SizedBox(width: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _blinkDot(),
            const SizedBox(width: 6),
            Text(
              '执行中',
              style: refText(
                family: Ref.fc,
                size: 13,
                wght: 700,
                height: 1,
                color: Ref.hot,
              ),
            ),
          ],
        ),
        const SizedBox(width: 10),
        Text(
          '·',
          style: refText(family: Ref.fc, size: 13, height: 1, color: Ref.dim),
        ),
        const SizedBox(width: 10),
        Text(
          code,
          style: refText(
            family: Ref.fm,
            size: 11,
            wght: 500,
            ls: 2,
            height: 1,
            color: Ref.dim,
          ),
        ),
      ],
    );
  }

  Widget _blinkDot() {
    return const _Blink(
      child: SizedBox(
        width: 8,
        height: 8,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Ref.hot,
            boxShadow: <BoxShadow>[BoxShadow(color: Ref.hot, blurRadius: 8)],
          ),
        ),
      ),
    );
  }

  /// .timer .digits（L272-277）：clamp(70px, 23vw, 104px)，每字符 .6em
  Widget _timer(BuildContext context, double progress) {
    final double vw = MediaQuery.sizeOf(context).width;
    final double size = (vw * .23).clamp(70.0, 104.0);
    final bool hit = progress >= 1;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        _DigitClock(
          elapsed: elapsed,
          size: size,
          color: hit ? Ref.acid : Colors.white,
          glow: hit ? Ref.acid : null,
        ),
        const SizedBox(width: 10),
        if (speed > 1)
          Text(
            '×$speed',
            style: refText(
              family: Ref.fm,
              size: 12,
              wght: 700,
              ls: 2,
              height: 1,
              color: Ref.gold,
            ),
          ),
      ],
    );
  }

  /// .tmeta（L283）：12px mono，左百分比 / 右目标
  Widget _tmeta(double progress, Duration limit) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          '${(progress * 100).floor()}%',
          style: refText(
            family: Ref.fm,
            size: 12,
            wght: 500,
            height: 1,
            color: Ref.dim,
          ),
        ),
        Text(
          '目标 ${_mmss(limit)}',
          style: refText(
            family: Ref.fm,
            size: 12,
            wght: 500,
            height: 1,
            color: Ref.dim,
          ),
        ),
      ],
    );
  }

  /// .watch（L284-288）：34 的核 + SYSTEM 12px mono 字距 3 + 一句
  Widget _watch() {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 34,
          height: 34,
          child: CustomPaint(painter: const _EyeCorePainter()),
        ),
        const SizedBox(width: 10),
        Text(
          'SYSTEM',
          style: refText(
            family: Ref.fm,
            size: 12,
            wght: 700,
            ls: 3,
            height: 1,
            color: Ref.cyan,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            style: refText(
              family: Ref.fc,
              size: 13,
              wght: 500,
              height: 1.3,
              color: watchAlert ? Ref.hot : Ref.dim,
            ),
            child: Text(
              watchText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  /// .evi（L289-303）
  Widget _evi() {
    final List<Widget> slots = <Widget>[];
    for (int i = 0; i < 3; i++) {
      final bool filled = i < evidenceThumbs.length;
      slots.add(
        Padding(
          padding: EdgeInsets.only(right: i == 2 ? 0 : 10),
          child: RefEvidenceSlot(
            key: Key('ref.exec.slot.$i'),
            size: 82,
            image: filled ? evidenceThumbs[i] : null,
            onTap: filled
                ? (onRemoveEvidence == null ? null : () => onRemoveEvidence!(i))
                : onAddEvidence,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Ref.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: '证据 · ',
                  style: refText(
                    family: Ref.fc,
                    size: 13,
                    wght: 500,
                    height: 1.3,
                    color: Ref.dim,
                  ),
                ),
                TextSpan(
                  text: quest.proof,
                  style: refText(
                    family: Ref.fc,
                    size: 13,
                    wght: 700,
                    height: 1.3,
                    color: Ref.txt,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // 参考稿是「三槽 + 右侧说明」一行并排（它按 430 宽设计）。
          // 390/320 宽下右侧只剩 38px，文字必然横向溢出；所以窄屏改成
          // 「槽一排、说明在下面」，宽屏（>=392）保持参考稿的并排。
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints rowBox) {
              final bool side = rowBox.maxWidth >= 392;
              final Widget info = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    evidenceThumbs.isEmpty ? '上传截图。没有证据，她不认账。' : '收下了。她会盯着看。',
                    style: refText(
                      family: Ref.fc,
                      size: 14,
                      wght: 500,
                      height: 1.5,
                      color: evidenceThumbs.isEmpty ? Ref.txt : Ref.acid,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (evidenceThumbs.isEmpty && onDemoEvidence != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: GestureDetector(
                        onTap: onDemoEvidence,
                        child: Text(
                          '⚡ 用演示截图 ›',
                          style: refText(
                            family: Ref.fc,
                            size: 13,
                            wght: 500,
                            height: 1.3,
                            color: Ref.cyan,
                          ),
                        ),
                      ),
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '暴击率 ',
                        style: refText(
                          family: Ref.fc,
                          size: 12,
                          wght: 400,
                          height: 1,
                          color: Ref.dim,
                        ),
                      ),
                      Text(
                        '${(critChance * 100).round()}%',
                        style: refText(
                          family: Ref.fd,
                          size: 15,
                          wght: 700,
                          height: 1,
                          color: Ref.hot,
                        ),
                      ),
                    ],
                  ),
                ],
              );
              final Widget row = Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  ...slots,
                  if (side) ...<Widget>[
                    const SizedBox(width: 14),
                    Expanded(child: info),
                  ],
                ],
              );
              return side
                  ? row
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[row, const SizedBox(height: 10), info],
                    );
            },
          ),
        ],
      ),
    );
  }

  /// 动作区：actions（L235-236）第一排 + .ex-act .row2（L306）
  Widget _actions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            RefButton(
              key: const Key('ref.exec.items'),
              label: '道具',
              // .eqn：本单已装载件数（hot 胶囊，0 时隐藏）
              trailing: equipped > 0
                  ? Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Ref.hot,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$equipped',
                        style: refText(
                          family: Ref.fd,
                          size: 12,
                          wght: 700,
                          height: 1,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : null,
              primary: false,
              small: true,
              animateSheen: false,
              onTap: onItems,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: RefButton(
                key: const Key('ref.exec.submit'),
                label: '提交 · 让她验收',
                onTap: onSubmit,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            _HoldToQuit(onProgress: onQuitProgress, onComplete: onQuit),
            RefLink(label: '收起 ▾', onTap: onCollapse),
          ],
        ),
      ],
    );
  }

  static String _mmss(Duration d) {
    // JS fmt()：mm:ss 两位补零（00:03）
    final String m = d.inMinutes.toString().padLeft(2, '0');
    final String s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// .btn.hold（L307-309）：高 46 / 斜切 10 / 边 rgba(255,59,122,.4) /
/// 底 #170b17 / 文字 #ff9dbd / 按住时 fill 从 0 长到 100% 且转白。
///
/// 按满 1600ms（JS L1473 的 D = 1600），松手 300ms 回退（JS L1480）。
class _HoldToQuit extends StatefulWidget {
  const _HoldToQuit({this.onProgress, this.onComplete});

  final ValueChanged<double>? onProgress;
  final VoidCallback? onComplete;

  @override
  State<_HoldToQuit> createState() => _HoldToQuitState();
}

class _HoldToQuitState extends State<_HoldToQuit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  bool _on = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_report);
    _c.addStatusListener(_status);
  }

  void _report() => widget.onProgress?.call(_c.value);

  void _status(AnimationStatus s) {
    if (s != AnimationStatus.completed) return;
    _on = false;
    _c.value = 0;
    widget.onComplete?.call();
  }

  @override
  void dispose() {
    _c.removeListener(_report);
    _c.removeStatusListener(_status);
    _c.dispose();
    super.dispose();
  }

  void _down() {
    setState(() => _on = true);
    _c.forward(from: 0);
  }

  void _up() {
    if (!_on) return;
    setState(() => _on = false);
    _c.animateBack(0, duration: const Duration(milliseconds: 300));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _down(),
      onTapUp: (_) => _up(),
      onTapCancel: _up,
      child: AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, Widget? _) {
          final double p = _c.value;
          return CustomPaint(
            painter: _HoldPainter(progress: p),
            child: SizedBox(
              height: 46,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    p > 0 ? '松手还来得及' : '按住 · 认输',
                    style: refText(
                      family: Ref.fc,
                      size: 14,
                      wght: 700,
                      ls: 2,
                      height: 1,
                      color: p > .02 ? Colors.white : const Color(0xFFFF9DBD),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HoldPainter extends CustomPainter {
  const _HoldPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size s) {
    final Rect r = Offset.zero & s;
    canvas.drawPath(cutCornerPath(r, 10), Paint()..color = Ref.a(Ref.hot, .4));
    canvas.drawPath(
      cutCornerPath(r.deflate(1.5), 8.8),
      Paint()..color = const Color(0xFF170B17),
    );
    if (progress <= 0) return;
    canvas.save();
    canvas.clipPath(cutCornerPath(r.deflate(1.5), 8.8));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, s.width * progress, s.height),
      Paint()..color = Ref.hot,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HoldPainter o) => o.progress != progress;
}

/// .timer .digits 的逐字符：每字符 width .6em，冒号 .3em 且 1s 闪
class _DigitClock extends StatefulWidget {
  const _DigitClock({
    required this.elapsed,
    required this.size,
    required this.color,
    this.glow,
  });

  final Duration elapsed;
  final double size;
  final Color color;
  final Color? glow;

  @override
  State<_DigitClock> createState() => _DigitClockState();
}

class _DigitClockState extends State<_DigitClock> {
  static String _fmt(Duration d) {
    // JS fmt()：mm:ss 两位补零（00:03）
    final String m = d.inMinutes.toString().padLeft(2, '0');
    final String s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  late String _text = _fmt(widget.elapsed);

  @override
  void didUpdateWidget(_DigitClock old) {
    super.didUpdateWidget(old);
    final String next = _fmt(widget.elapsed);
    if (next != _text) setState(() => _text = next);
  }

  @override
  Widget build(BuildContext context) {
    final Color? glow = widget.glow;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        for (int i = 0; i < _text.length; i++)
          SizedBox(
            width: widget.size * (_text[i] == ':' ? .3 : .6),
            child: _text[i] == ':'
                ? _Blink(
                    child: Text(
                      ':',
                      textAlign: TextAlign.center,
                      style: refText(
                        family: Ref.fd,
                        size: widget.size,
                        wght: 700,
                        height: 1,
                        color: widget.color,
                        shadows: glow == null
                            ? null
                            : <Shadow>[Shadow(color: glow, blurRadius: 24)],
                      ),
                    ),
                  )
                : _CharSlide(
                    key: ValueKey<String>('$i-${_text[i]}'),
                    child: Text(
                      _text[i],
                      textAlign: TextAlign.center,
                      style: refText(
                        family: Ref.fd,
                        size: widget.size,
                        wght: 700,
                        height: 1,
                        color: widget.color,
                        shadows: <Shadow>[
                          Shadow(
                            color: (glow ?? Ref.hot).withAlpha(90),
                            blurRadius: 24,
                          ),
                          Shadow(color: Ref.hot.withAlpha(60), blurRadius: 60),
                        ],
                      ),
                    ),
                  ),
          ),
      ],
    );
  }
}

/// 逐字符下落（JS L1407：translateY(-40%) scale(1.15) blur(3) 280ms）
class _CharSlide extends StatefulWidget {
  const _CharSlide({super.key, required this.child});
  final Widget child;

  @override
  State<_CharSlide> createState() => _CharSlideState();
}

class _CharSlideState extends State<_CharSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  @override
  void initState() {
    super.initState();
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, Widget? child) {
        if (_c.value >= 1) return child!;
        final double t = Ref.pop.transform(_c.value);
        return Opacity(
          opacity: _c.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -10 * (1 - t)),
            child: Transform.scale(scale: .85 + .15 * t, child: child),
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// 1s steps(1) 的闪烁（.colon / .rec i）
class _Blink extends StatefulWidget {
  const _Blink({required this.child});
  final Widget child;

  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, Widget? child) =>
          Opacity(opacity: _c.value < .5 ? 1 : .15, child: child),
      child: widget.child,
    );
  }
}

/// .watch 的 34px 小核（同心环 + 眼点）
class _EyeCorePainter extends CustomPainter {
  const _EyeCorePainter();

  @override
  void paint(Canvas canvas, Size s) {
    final Offset c = s.center(Offset.zero);
    final double r = s.width / 2 - 1;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Ref.a(Ref.cyan, .8),
    );
    canvas.drawCircle(c, r * .55, Paint()..color = Ref.a(Ref.cyan, .18));
    canvas.drawCircle(c, r * .28, Paint()..color = Ref.cyan);
    canvas.drawCircle(
      c + Offset(-r * .1, -r * .1),
      r * .09,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
