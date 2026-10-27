import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/ref.dart';
import '../../state/quest.dart';
import 'ref_inputs.dart';
import 'ref_kit.dart';

/// ═══════════════════════════════════════════════════════════
///  委托板 —— 参考稿 .board（CSS L237-264，DOM L733-741）
///
///  结构：抬头（eyebrow + h1 + 返回）→ tabs（金滑块）→ 票券列表。
///  票券 .ticket 的解剖（L244-260）：
///    ┌──────┬───────────────────────────────┬──────┐
///    │ 档位  │ 徽标 / 标题 / 规则行 / 报酬    │ 接单 │
///    │ 76px │ 拉伸                          │ 52px │
///    └──────┴───────────────────────────────┴──────┘
///   左侧 2px 虚线 + 上下各一枚 18px 的「撕口」圆
/// ═══════════════════════════════════════════════════════════
class RefBoard extends StatelessWidget {
  const RefBoard({
    super.key,
    required this.quests,
    required this.filter,
    required this.onFilter,
    required this.onTap,
    this.active,
    this.onBack,
    this.onRefill,
    this.emptyTitle = 'CLEAR!',
    this.emptyBody = '今日委托清空。她勉强承认：你今天不算太废。',
  });

  /// 空状态里的「再要一批委托」（参考稿 JS L1374）
  final VoidCallback? onRefill;

  /// 当前筛选下的单（调用方已按 filter 过滤）
  final List<Quest> quests;

  /// all / MAIN / SIDE / DAILY
  final String filter;
  final ValueChanged<String> onFilter;
  final ValueChanged<Quest> onTap;

  /// 正在执行的那张（右上角会写「继续」）
  final Quest? active;

  final VoidCallback? onBack;
  final String emptyTitle;
  final String emptyBody;

  @override
  Widget build(BuildContext context) {
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Ref.gutter,
        // ⚠️ 委托板是**有 HUD** 的场景（参考稿 SC.board.hud = 1），
        //    所以走 .scene 的 94 上边距；用 30 会让 HUD 直接压住抬头
        //    （真机截图：「BOARD·委托板」被等级环与晶核 chip 叠住）。
        safe.top + Ref.sceneTop,
        Ref.gutter,
        safe.bottom + Ref.sceneBottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _head(),
          const SizedBox(height: 12),
          RefTabsBar(
            labels: const <String>['全部', '主线', '支线', '日常'],
            index: _indexOf(filter),
            onChanged: (int i) => onFilter(_keyOf(i)),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: quests.isEmpty
                ? _empty()
                : ShaderMask(
                    shaderCallback: (Rect r) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Color(0x00FFFFFF),
                        Color(0xFFFFFFFF),
                        Color(0xFFFFFFFF),
                        Color(0x00FFFFFF),
                      ],
                      stops: <double>[0, .04, .92, 1],
                    ).createShader(r),
                    blendMode: BlendMode.dstIn,
                    child: ListView.builder(
                      key: const Key('ref.board.list'),
                      padding: const EdgeInsets.only(top: 4, bottom: 30),
                      itemCount: quests.length,
                      itemBuilder: (BuildContext context, int i) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: RefTicketCard(
                          key: ValueKey<String>('ticket.${quests[i].serial}'),
                          quest: quests[i],
                          running: active?.serial == quests[i].serial,
                          index: i,
                          onTap: () => onTap(quests[i]),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _head() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const RefEyebrow(text: 'BOARD · 委托板'),
              const SizedBox(height: 8),
              Text('今天，接哪一单？', style: RefType.h1),
            ],
          ),
        ),
        RefXButton(onTap: onBack, back: true, accent: Ref.gold),
      ],
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            emptyTitle,
            style: refText(
              family: Ref.fd,
              size: 44,
              wght: 900,
              height: 1,
              color: Ref.gold,
              shadows: <Shadow>[Shadow(color: Ref.gold, blurRadius: 20)],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            emptyBody,
            textAlign: TextAlign.center,
            style: refText(
              family: Ref.fc,
              size: 14,
              wght: 500,
              height: 1.8,
              color: Ref.dim,
            ),
          ),
          if (onRefill != null) ...<Widget>[
            const SizedBox(height: 22),
            RefButton(
              label: '再要一批委托',
              primary: false,
              small: true,
              animateSheen: false,
              onTap: onRefill,
            ),
          ],
        ],
      ),
    );
  }

  static int _indexOf(String f) => switch (f) {
    'MAIN' => 1,
    'SIDE' => 2,
    'DAILY' => 3,
    _ => 0,
  };

  static String _keyOf(int i) => switch (i) {
    1 => 'MAIN',
    2 => 'SIDE',
    3 => 'DAILY',
    _ => 'all',
  };
}

/// .tabs（L238-241）的参数化外壳：金滑块 + 四段文字
class RefTabsBar extends StatelessWidget {
  const RefTabsBar({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.accent,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44, // 36 + padding 4×2
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Ref.line),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final double seg = c.maxWidth / math.max(1, labels.length);
          final Color gold = accent ?? Ref.gold;
          return Stack(
            children: <Widget>[
              AnimatedPositioned(
                duration: const Duration(milliseconds: 400),
                curve: Ref.ease,
                left: seg * index,
                top: 0,
                bottom: 0,
                width: seg,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: gold,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: <BoxShadow>[
                      BoxShadow(color: Ref.a(gold, .5), blurRadius: 18),
                    ],
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  for (int i = 0; i < labels.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(i),
                        child: Center(
                          child: Text(
                            labels[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: refText(
                              family: Ref.fc,
                              size: 14,
                              wght: 700,
                              height: 1,
                              color: i == index ? Ref.onAccent : Ref.dim,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// .ticket（L244-260）单条
class RefTicketCard extends StatefulWidget {
  const RefTicketCard({
    super.key,
    required this.quest,
    this.onTap,
    this.running = false,
    this.index = 0,
  });

  final Quest quest;
  final VoidCallback? onTap;
  final bool running;

  /// 列表序号（错峰入场 80ms，L1382）
  final int index;

  @override
  State<RefTicketCard> createState() => _RefTicketCardState();
}

class _RefTicketCardState extends State<RefTicketCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  bool _down = false;
  bool _hover = false;
  bool _scheduled = false;
  Timer? _delay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _in.value = 1;
      return;
    }
    // ⚠️ 入场必须留一条**兜底**：原来只靠 `Future.delayed(0)` 起播，
    //    首帧没有 ticker 时（离屏出图 / 首帧卡顿）它会永远停在 opacity 0 ——
    //    .verify/v3-board.png 里票券整块是空的，就是这个坑。
    //    现在：延迟到点起播，同时在首帧后立刻补一次 forward（幂等）。
    final int delay = math.min(widget.index, 6) * 80;
    _delay = Timer(Duration(milliseconds: delay), () {
      if (mounted) _in.forward();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_in.value == 0 && !_in.isAnimating) _in.forward();
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Quest q = widget.quest;
    final Color gc = Ref.rankOf(q.rank);
    final bool main = q.kind == 'main';
    return AnimatedBuilder(
      animation: _in,
      builder: (BuildContext context, Widget? child) {
        final double t = Ref.ease.transform(_in.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 26 * (1 - t)),
            child: child,
          ),
        );
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Ref.ease,
            transform: _down
                ? (Matrix4.identity()..scaleByDouble(.98, .98, 1, 1))
                : (_hover
                      ? (Matrix4.identity()..translateByDouble(4, 0, 0, 1))
                      : Matrix4.identity()),
            constraints: const BoxConstraints(minHeight: 112),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  Ref.mix(gc, const Color(0xFF13111F), .85),
                  const Color(0xFF0F0D1A),
                ],
                stops: const <double>[0, .55],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _hover ? Ref.a(gc, .6) : const Color(0x12FFFFFF),
              ),
            ),
            // ⚠️ ListView 里高度是无界的：Row 的 stretch 会强制子项「无限高」
            // （实测直接抛 "BoxConstraints forces an infinite height"）。
            // IntrinsicHeight 先把这一行收成内容高度，stretch 才有意义。
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _grade(q, gc),
                  Expanded(child: _body(q, gc, main)),
                  _go(gc),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// .tk-g：宽 76、右侧 2px 虚线、上下各一枚 18 撕口
  Widget _grade(Quest q, Color gc) {
    return SizedBox(
      width: 76,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: Ref.a(Colors.white, .12), width: 2),
                ),
              ),
            ),
          ),
          Positioned(right: -9, top: -9, child: _notch()),
          Positioned(right: -9, bottom: -9, child: _notch()),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  q.rank,
                  style: refText(
                    family: Ref.fd,
                    size: 42,
                    wght: 700,
                    italic: true,
                    height: 1,
                    color: gc,
                    shadows: <Shadow>[Shadow(color: gc, blurRadius: 18)],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  q.kind == 'main'
                      ? 'MAIN·${(q.planIndex + 1).toString().padLeft(2, '0')}'
                      : '№ ${q.serial.toString().padLeft(4, '0')}',
                  style: refText(
                    family: Ref.fm,
                    size: 9,
                    wght: 700,
                    ls: 2,
                    height: 1,
                    color: Ref.dim,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _notch() => Container(
    width: 18,
    height: 18,
    decoration: BoxDecoration(shape: BoxShape.circle, color: Ref.bg),
  );

  Widget _body(Quest q, Color gc, bool main) {
    final String kindLabel = switch (q.kind) {
      'main' => '主线',
      'remedy' => '补救',
      _ => '日常',
    };
    // ⚠️ 上下各 13 的内边距 + 内容固有高度比 min-height 112 多 2px，
    //    IntrinsicHeight 收成内容高度后 Column 仍按 max 撑，就溢出 2px
    //    （控制台一直在刷 RenderFlex overflowed by 2.0 pixels）。
    //    参考稿 .tk-b 是 padding 13/12、没有 min-height 约束冲突，这里对齐它。
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: main ? Ref.acid : Ref.a(gc, .2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  kindLabel,
                  style: refText(
                    family: Ref.fm,
                    size: 9,
                    wght: 700,
                    ls: 2,
                    height: 1,
                    color: main ? Ref.onAccent : gc,
                  ),
                ),
              ),
              if (widget.running) ...<Widget>[
                const SizedBox(width: 6),
                Text(
                  '· 执行中',
                  style: refText(
                    family: Ref.fc,
                    size: 9,
                    wght: 700,
                    height: 1,
                    color: Ref.hot,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 5),
          Text(
            q.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: RefType.ticketTitle,
          ),
          const SizedBox(height: 4),
          Text(
            '${q.minutesText} · ${q.proof}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: RefType.ticketMeta,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: <Widget>[
              for (final String s in _loot(q))
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x0FFFFFFF),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    s,
                    style: refText(
                      family: Ref.fd,
                      size: 11,
                      wght: 700,
                      height: 1.2,
                      color: const Color(0xFFD9D6EE),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 「显示 = 结算」的唯一口径是 [Quest.lootText]，**不要改它的字面量**
  /// （agent 工具回执、聊天台词都读同一份）。字形问题只在渲染层修：
  /// Chakra / JetBrains / NotoSansSC 都没有 `◈`，直接画会是豆腐块，
  /// 这里换成同义的中文标签。
  static String _glyph(String s) => s.replaceAll('◈', '晶核');

  static List<String> _loot(Quest q) {
    // .tk-r 的三个标签（L257-258）：数值走项目真实收益表（lootText 是
    // 「显示 = 结算」的唯一口径），这里只按 · 拆开
    final List<String> out = <String>[];
    for (final String part in _glyph(q.lootText).split(' · ')) {
      if (part.trim().isNotEmpty) out.add(part.trim());
    }
    return out;
  }

  /// .tk-go：宽 52、竖排、900 16px、背景 gc、右侧圆角
  Widget _go(Color gc) {
    return Container(
      width: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: gc,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(17),
          bottomRight: Radius.circular(17),
        ),
      ),
      // .tk-go{writing-mode:vertical-rl; letter-spacing:8px; 16px}（L259）
      // ⚠️ 不能用 RotatedBox + 普通 Text：宽度不够时它会先折行再旋转，
      //    屏上就是两列「接/单」（真机截图）。这里逐字竖排，一个字符一行。
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final String ch in (widget.running ? '继续' : '接单').split(''))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                ch,
                maxLines: 1,
                softWrap: false,
                style: refText(
                  family: Ref.fc,
                  size: 16,
                  wght: 900,
                  height: 1,
                  color: Ref.onAccent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
