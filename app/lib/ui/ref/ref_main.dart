import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/ref.dart';
import '../../state/goal.dart';
import 'ref_inputs.dart';
import 'ref_kit.dart';

/// ═══════════════════════════════════════════════════════════
///  主线页 —— 参考稿 #sc-main（CSS L217-236，DOM L719-731）
///
///  .sh（eyebrow + h1 + xbtn）→ .meta（已过 3/14 天 · 完成 5 单 · 剩 11 天）
///  → .daybar（14 格 5 高）→ .car（3D 卡轮播）→ .ruler（横向刻度）
///  → .sysbox（46 核心 + SYSTEM + 情绪 + 她的话）→ .actions（去委托板 / 换目标）
///
///  ⚠️ 这是 nohud 场景：上边距取 30（不是 94），因为 HUD 在这一页是收起的。
/// ═══════════════════════════════════════════════════════════
class RefMain extends StatelessWidget {
  const RefMain({
    super.key,
    required this.goal,
    this.lead = 0,
    this.mood = '尚可',
    this.line = '',
    this.elapsed,
    this.onBack,
    this.onScrub,
    this.onDispatch,
    this.onSwapGoal,
  });

  final Goal goal;

  /// 当前领位（主线上第几张）
  final int lead;

  /// .sb-h span 的情绪词
  final String mood;

  /// .sysbox p 她的话
  final String line;

  /// 执行中那张的读数（null = 没有）
  final String? elapsed;

  final VoidCallback? onBack;
  final ValueChanged<int>? onScrub;
  final VoidCallback? onDispatch;
  final VoidCallback? onSwapGoal;

  /// 脸的下沿（见 RefHome 同名字段）

  @override
  Widget build(BuildContext context) {
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    final int total = goal.plan.length;
    final int done = goal.doneCount;
    // nohud 场景：参考稿 L59 是 safe + 30。
    final double top = safe.top + Ref.sceneTopNoHud;
    // 844 高的屏装得下「抬头 + meta + daybar + 330 卡 + 刻度 + sysbox + 两键」；
    // 低于这个高度就退回滚动版（见下面 if (_tall)）。
    final double avail =
        MediaQuery.sizeOf(context).height - top - safe.bottom - Ref.sceneBottom;
    final bool tall = avail >= 700;
    final Widget content = Padding(
      padding: EdgeInsets.fromLTRB(
        Ref.gutter,
        top,
        Ref.gutter,
        safe.bottom + Ref.sceneBottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _head(),
          _meta(total, done),
          _dayBar(),
          // 参考稿：.car 是 flex:1（L188）—— 它吃掉抬头以下、刻度以上的
          // **全部剩余高度**，卡片再按这个盒子等比缩（430×844 上是 240×330）。
          // 矮屏（320×640 / 分屏）装不下时退回滚动，别把 sysbox 与两键顶出屏。
          if (tall)
            Expanded(child: _carBox(context))
          else
            SizedBox(
              height: 250,
              child: SingleChildScrollView(child: _carBox(context)),
            ),
          _ruler(total),
          _sysbox(),
          const SizedBox(height: 14),
          _actions(),
        ],
      ),
    );
    return content;
  }

  /// .sh（L63）：左 eyebrow + h1，右 48 圆 xbtn
  Widget _head() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const RefEyebrow(text: 'MAINLINE · 主线', accent: Ref.cyan),
              const SizedBox(height: 8),
              Text(
                goal.text.isEmpty ? '（还没有目标）' : goal.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: RefType.h1,
              ),
            ],
          ),
        ),
        RefXButton(onTap: onBack, accent: Ref.cyan),
      ],
    );
  }

  /// .meta（L218-220）
  Widget _meta(int total, int done) {
    final int days = goal.days <= 0 ? 14 : goal.days;
    final int left = goal.remainingDays(DateTime.now()).clamp(0, days);
    final int passed = (days - left).clamp(0, days);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 4,
        children: <Widget>[
          Text('已过 ', style: RefType.meta),
          Text('$passed/$days', style: RefType.metaNum),
          Text(' 天 · 完成 ', style: RefType.meta),
          Text('$done', style: RefType.metaNum),
          Text(' 单', style: RefType.meta),
          const SizedBox(width: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0x40FFFFFF)),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              left <= 0 ? '已到期' : '剩 $left 天',
              style: refText(
                family: Ref.fc,
                size: 13,
                wght: 500,
                height: 1.3,
                color: Ref.txt,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// .daybar（L221-224）：14 格、3 间距、5 高、r1
  Widget _dayBar() {
    final int days = goal.days <= 0 ? 14 : goal.days;
    final int left = goal.remainingDays(DateTime.now()).clamp(0, days);
    final int today = (days - left).clamp(1, days);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < days; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  color: i + 1 < today
                      ? Ref.cyan
                      : (i + 1 == today ? Ref.acid : const Color(0x14FFFFFF)),
                  borderRadius: BorderRadius.circular(1),
                  boxShadow: i + 1 < today
                      ? <BoxShadow>[BoxShadow(color: Ref.cyan, blurRadius: 6)]
                      : (i + 1 == today
                            ? <BoxShadow>[
                                BoxShadow(color: Ref.acid, blurRadius: 6),
                              ]
                            : null),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// .car（L188）：flex 1 + min-height 250 + 左右 −22 出血；卡在其中居中，
  /// 由 [RefMainCard] 自己的 LayoutBuilder 按可用高度定宽高（ar .72）。
  Widget _carBox(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 250),
      margin: const EdgeInsets.only(top: 4),
      child: _car(),
    );
  }

  /// .car（L190-216 的 .gcard）
  Widget _car() {
    final int total = goal.plan.length;
    if (total == 0) {
      return Center(
        child: Text(
          '还没有清单。先去立一个目标。',
          style: refText(
            family: Ref.fc,
            size: 14,
            wght: 500,
            height: 1.8,
            color: Ref.dim,
          ),
        ),
      );
    }
    final int i = lead.clamp(0, total - 1);
    return Center(
      child: GestureDetector(
        onTap: onScrub == null ? null : () => onScrub!(i),
        child: RefMainCard(
          key: const Key('ref.main.card'),
          index: i,
          total: total,
          task: goal.taskAt(i),
          elapsed: elapsed,
        ),
      ),
    );
  }

  /// .ruler（L225-228）
  Widget _ruler(int total) {
    if (total <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 7,
        runSpacing: 6,
        children: <Widget>[
          for (int i = 0; i < total; i++)
            GestureDetector(
              onTap: onScrub == null ? null : () => onScrub!(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Ref.ease,
                width: i == lead ? 30 : 14,
                height: 4,
                decoration: BoxDecoration(
                  color: i < goal.firstOpenIndex
                      ? Ref.mix(Ref.cyan, Ref.bg, .4)
                      : (i == lead ? Ref.acid : const Color(0x1FFFFFFF)),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: i == lead
                      ? <BoxShadow>[BoxShadow(color: Ref.acid, blurRadius: 10)]
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// .sysbox（L229-234）
  Widget _sysbox() {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 0, 12),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Ref.cyan, width: 3)),
        gradient: LinearGradient(
          colors: <Color>[Color(0x143BE8FF), Color(0x003BE8FF)],
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 46,
            height: 46,
            child: CustomPaint(painter: const _TinyCorePainter()),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // ⚠️ 窄屏（320）上「SYSTEM + 五点 + 情绪」会挤爆 18px：
                //    情绪词让位（Flexible + 省略号），SYSTEM 那两段是定宽标识不动。
                Row(
                  children: <Widget>[
                    Text(
                      'SYSTEM',
                      style: refText(
                        family: Ref.fm,
                        size: 13,
                        wght: 700,
                        ls: 4,
                        height: 1,
                        color: Ref.cyan,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '·····',
                      style: refText(
                        family: Ref.fm,
                        size: 13,
                        wght: 700,
                        ls: 2,
                        height: 1,
                        color: Ref.dim2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        mood,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: refText(
                          family: Ref.fc,
                          size: 12,
                          wght: 500,
                          ls: 1,
                          height: 1,
                          color: Ref.dim,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 26),
                  child: Text(
                    line,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: refText(
                      family: Ref.fc,
                      size: 17,
                      wght: 500,
                      height: 1.5,
                      color: Ref.txt,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// .actions（L235-236）
  Widget _actions() {
    return Row(
      children: <Widget>[
        Expanded(
          child: RefButton(
            key: const Key('ref.main.toBoard'),
            label: '去委托板',
            trailingTriangle: true,
            onTap: onDispatch,
          ),
        ),
        const SizedBox(width: 12),
        RefButton(
          key: const Key('ref.main.swapGoal'),
          label: '换目标',
          primary: false,
          small: true,
          animateSheen: false,
          onTap: onSwapGoal,
        ),
      ],
    );
  }
}

/// .gcard（L191-216）大牌：22 圆角、155 度三段渐变、1.5px 档位色描边（α.35）、
/// 右下 170px 描边档位字、.grade 66px italic、.gc-t 20/1.35、.gc-r 报酬芯片
class RefMainCard extends StatefulWidget {
  const RefMainCard({
    super.key,
    required this.index,
    required this.total,
    required this.task,
    this.elapsed,
    this.onFlip,
  });

  final int index;
  final int total;
  final PlanTask? task;
  final String? elapsed;

  /// 已完成的卡：点一下翻面看战报（参考稿 mainTap / mainFlip，L1326-1329）
  final ValueChanged<bool>? onFlip;

  @override
  State<RefMainCard> createState() => _RefMainCardState();
}

class _RefMainCardState extends State<RefMainCard>
    with SingleTickerProviderStateMixin {
  bool _flipped = false;

  /// .tc{transition:transform .8s cubic-bezier(.3,1.3,.4,1)}
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
    value: 0,
  );

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  PlanTask? get task => widget.task;
  int get index => widget.index;
  int get total => widget.total;
  String? get elapsed => widget.elapsed;

  void _tap() {
    if (task?.state != PlanState.done) return;
    setState(() => _flipped = !_flipped);
    if (_flipped) {
      _flip.forward();
    } else {
      _flip.reverse();
    }
    widget.onFlip?.call(_flipped);
  }

  @override
  Widget build(BuildContext context) {
    final String rank = task?.rank ?? 'F';
    final Color gc = Ref.rankOf(rank);
    final bool locked = task == null;
    final bool done = task?.state == PlanState.done;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        // 参考稿是固定 240×330（.car 的自然尺寸），矮屏上按可用高度收
        final double h = math.min(330.0, box.maxHeight);
        final double w = math.min(240.0, h * .72);
        // 参考稿 #mainCar .gcard 是 3D 翻转：正面（卡面）/ 背面（战报）。
        // 点已完成的卡 → rotateY(180deg)，再点翻回（L524-526 / L1326-1329）。
        return SizedBox(
          width: w,
          height: h,
          // 参考稿 #mainCar .gcard.fd .tc 是**同一个容器**绕 Y 轴转 180°，
          // 正反两面 backface-visibility:hidden 各自显隐（L524-527）。
          // ⚠️ 别用 AnimatedSwitcher：它在交叉淡入时会把两张卡同时压到低透明度，
          //    屏上就是「点一下卡片整个消失」（真机截图确认）。
          child: GestureDetector(
            onTap: done ? _tap : null,
            behavior: HitTestBehavior.opaque,
            child: AnimatedBuilder(
              animation: _flip,
              builder: (BuildContext context, Widget? _) {
                final double k = Ref.flip.transform(_flip.value);
                final double ang = k * math.pi;
                final bool showBack = ang > math.pi / 2;
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, .0012)
                    ..rotateY(ang),
                  child: showBack
                      ? Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..rotateY(math.pi),
                          child: _record(gc),
                        )
                      : Stack(
                          // ⚠️ 必须 expand：默认 loose 下渐变 Container 只按内容
                          //    撑开，卡会比 SizedBox 矮一截（离屏出图看到卡底
                          //    一条空带、印章与卡框错位）。
                          fit: StackFit.expand,
                          children: <Widget>[
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                gradient: const LinearGradient(
                                  begin: Alignment(-.8, -.9),
                                  end: Alignment(.8, .9),
                                  colors: <Color>[
                                    Color(0xFF231E40),
                                    Color(0xFF131124),
                                    Color(0xFF0B0A15),
                                  ],
                                  stops: <double>[0, .52, 1],
                                ),
                                boxShadow: <BoxShadow>[
                                  const BoxShadow(
                                    color: Color(0xC0000000),
                                    offset: Offset(0, 30),
                                    blurRadius: 50,
                                    spreadRadius: -12,
                                  ),
                                  BoxShadow(
                                    color: Ref.a(gc, .35),
                                    blurRadius: 46,
                                    spreadRadius: -8,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(22),
                                child: Stack(
                                  children: <Widget>[
                                    // .deco：右下 170px 描边档位字
                                    Positioned(
                                      right: -30,
                                      bottom: -40,
                                      child: Text(
                                        rank,
                                        style: TextStyle(
                                          fontFamily: Ref.fd,
                                          fontSize: 170,
                                          height: 1,
                                          fontStyle: FontStyle.italic,
                                          fontVariations: const <FontVariation>[
                                            FontVariation('wght', 900),
                                          ],
                                          foreground: Paint()
                                            ..style = PaintingStyle.stroke
                                            ..strokeWidth = 1.5
                                            ..color = Ref.a(gc, .2),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(18),
                                      // ⚠️ 卡高在矮屏会被压到 210（320×640）：66px 档位字
                                      //    + 三行题面 + 报酬芯片装不下 → Column 溢出 71px。
                                      //    整列改成可滚（超出部分滚出来，不炸布局）。
                                      child: LayoutBuilder(
                                        builder: (BuildContext bc, BoxConstraints cb) {
                                          // ⚠️ 滚动区里的 Column 不能带 Spacer（无界高度下
                                          //    flex 子项会直接抛 "non-zero flex but unbounded"）。
                                          //    这里把「撑到底部的印章/报酬」改成按可用高度
                                          //    手动留白：够高才留，矮屏直接贴上去。
                                          final double gap = cb.maxHeight > 300
                                              ? 24
                                              : 0;
                                          return SingleChildScrollView(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: <Widget>[
                                                Row(
                                                  children: <Widget>[
                                                    Expanded(
                                                      child: Text(
                                                        _code(),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: refText(
                                                          family: Ref.fm,
                                                          size: 11,
                                                          wght: 700,
                                                          ls: 3,
                                                          height: 1,
                                                          color: gc,
                                                        ),
                                                      ),
                                                    ),
                                                    _cat(gc),
                                                  ],
                                                ),
                                                const SizedBox(height: 10),
                                                Text(
                                                  rank,
                                                  style: refText(
                                                    family: Ref.fd,
                                                    size: 66,
                                                    wght: 700,
                                                    italic: true,
                                                    height: .95,
                                                    color: gc,
                                                    shadows: <Shadow>[
                                                      Shadow(
                                                        color: gc,
                                                        blurRadius: 24,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  task?.title ?? '完成上一单解锁',
                                                  maxLines: 3,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: RefType.cardTitle,
                                                ),
                                                if (task != null) ...<Widget>[
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    _metaOf(task!),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: RefType.cardMeta,
                                                  ),
                                                ],
                                                // .gc-r{margin-top:auto}（L202）：报酬芯片
                                                // 贴卡底，**完成态也保留**（设计稿只额外叠
                                                // 一枚 .stamp，不替换报酬行）。
                                                // .lockv 同理贴底，但它自带底部渐变幕。
                                                SizedBox(height: gap),
                                                if (locked)
                                                  _lock()
                                                else
                                                  _loot(task!),
                                                if (elapsed != null &&
                                                    !done) ...<Widget>[
                                                  const SizedBox(height: 8),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 12,
                                                          vertical: 9,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Ref.acid,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10,
                                                          ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: <Widget>[
                                                        Text(
                                                          '执行中 ',
                                                          style: refText(
                                                            family: Ref.fc,
                                                            size: 13,
                                                            wght: 900,
                                                            ls: 1,
                                                            height: 1,
                                                            color: Ref.onAccent,
                                                          ),
                                                        ),
                                                        Text(
                                                          elapsed!,
                                                          style: refText(
                                                            family: Ref.fd,
                                                            size: 15,
                                                            wght: 700,
                                                            height: 1,
                                                            color: Ref.onAccent,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // #mainCar .gcard .stamp{top:26%;right:12px;z-index:12}
                            // （L590）：印章是**绝对定位**压在卡面右上，不占文档
                            // 流位置 —— 放进流里会把正文挤开、并在卡底留一条空带。
                            if (done)
                              Positioned(
                                right: 12,
                                top: h * .26,
                                child: IgnorePointer(child: _stamp()),
                              ),
                            // 1.5px 档位色描边（α .35）
                            Positioned.fill(
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: Ref.a(gc, .35),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// 参考稿 .tc-back.tcrec（L619-629）：战报背面。
  /// 评级大字 + 用时 / 奖励 / 完成日 + SYSTEM 批注。
  Widget _record(Color gc) {
    final PlanTask? t = task;
    final String rank = t?.rank ?? 'F';
    final Duration held = t?.held ?? Duration.zero;
    final String mmss =
        '${(held.inMinutes).toString().padLeft(2, '0')}:'
        '${(held.inSeconds % 60).toString().padLeft(2, '0')}';
    final String day = t?.doneAt == null
        ? '—'
        : 'DAY ${t!.doneAt!.month.toString().padLeft(2, '0')}.'
              '${t.doneAt!.day.toString().padLeft(2, '0')}';
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment(-.6, -.8),
          end: Alignment(.6, .9),
          colors: <Color>[Color(0xFF1D1838), Color(0xFF0A0914)],
        ),
        border: Border.all(color: Ref.a(gc, .45), width: 1.5),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'RECORD · 战报',
                style: refText(
                  family: Ref.fm,
                  size: 10,
                  wght: 700,
                  ls: 3,
                  height: 1,
                  color: gc,
                ),
              ),
              const SizedBox(width: 10),
              // ⚠️ 参考稿是 138 宽的牌，这里的卡在窄屏上会压到 240 以下：
              //    「RECORD · 战报」+「MAIN 01 / 03」并排会溢出（真机右边那条
              //    RIGHT OVERFLOWED）。让右侧那条可以被压缩并省略。
              Expanded(
                child: Text(
                  _code(),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: refText(
                    family: Ref.fm,
                    size: 10,
                    wght: 700,
                    ls: 2,
                    height: 1,
                    color: Ref.dim,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Center(
            child: Text(
              rank,
              style: refText(
                family: Ref.fd,
                size: 92,
                wght: 700,
                italic: true,
                height: 1,
                color: gc,
                shadows: <Shadow>[Shadow(color: gc, blurRadius: 30)],
              ),
            ),
          ),
          Center(
            child: Text(
              '验收评级 · GRADE',
              style: refText(
                family: Ref.fm,
                size: 9,
                wght: 700,
                ls: 4,
                height: 1,
                color: Ref.dim,
              ),
            ),
          ),
          const Spacer(),
          _recRow('用时', '$mmss / ${t?.minutes ?? 0}:00'),
          const SizedBox(height: 6),
          _recRow('完成于', day),
          const Spacer(),
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'SYSTEM 批注',
                  style: refText(
                    family: Ref.fm,
                    size: 9,
                    wght: 700,
                    ls: 2,
                    height: 1,
                    color: gc,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  rank == 'C'
                      ? '这也算？……算吧。'
                      : (rank == 'B' ? '及格线上蹭过去的。我看见了。' : '达标。别指望我夸你。'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: refText(
                    family: Ref.fc,
                    size: 12,
                    wght: 500,
                    height: 1.5,
                    color: const Color(0xCCFFFFFF),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recRow(String k, String v) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          k,
          style: refText(
            family: Ref.fc,
            size: 12,
            wght: 500,
            height: 1,
            color: Ref.dim,
          ),
        ),
        Text(
          v,
          style: refText(
            family: Ref.fd,
            size: 14,
            wght: 700,
            height: 1,
            color: Ref.txt,
          ),
        ),
      ],
    );
  }

  /// MAIN 03 / 10
  String _code() {
    final String a = (index + 1).toString().padLeft(2, '0');
    final String b = total.toString().padLeft(2, '0');
    return 'MAIN $a / $b';
  }

  /// 20 分钟 · 速度数据截图
  String _metaOf(PlanTask t) => '${t.minutes} 分钟 · ${t.proof}';

  /// .gc-top .cat（L198）：30 菱形 + 1.5 档位色边
  Widget _cat(Color gc) {
    return Transform.rotate(
      angle: math.pi / 4,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: gc, width: 1.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Transform.rotate(
          angle: -math.pi / 4,
          child: Text(
            '委',
            style: refText(
              family: Ref.fc,
              size: 15,
              wght: 900,
              height: 1,
              color: gc,
            ),
          ),
        ),
      ),
    );
  }

  /// .gc-r（L203-205）：报酬芯片
  Widget _loot(PlanTask t) {
    final String first = t.attrs.isEmpty ? '' : t.attrs.keys.first;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        _chip('EXP', '+${20 + t.index * 4}'),
        // ⚠️ 别用 '◈'：Chakra/JetBrains/NotoSansSC 都没有这个字形，
        //    离屏出图实测渲染成豆腐块。晶核统一写中文标签。
        _chip('晶核', (12 + t.index * 3).toString()),
        if (first.isNotEmpty) _chip(first, '+1'),
      ],
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: refText(
              family: Ref.fc,
              size: 10,
              wght: 500,
              height: 1,
              color: Ref.dim,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: refText(
              family: Ref.fd,
              size: 12,
              wght: 700,
              height: 1,
              color: Ref.txt,
            ),
          ),
        ],
      ),
    );
  }

  /// .stamp（L206-207）：3px 双线 hot 框、18px 900、rotate -14
  Widget _stamp() {
    return Transform.rotate(
      angle: -14 * math.pi / 180,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Ref.hot, width: 3),
          borderRadius: BorderRadius.circular(8),
          color: const Color(0x0FFF3B7A),
          boxShadow: <BoxShadow>[
            BoxShadow(color: Ref.a(Ref.hot, .3), blurRadius: 18),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '已完成',
              style: refText(
                family: Ref.fc,
                size: 18,
                wght: 900,
                ls: 3,
                height: 1,
                color: Ref.hot,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'CLEAR',
              style: refText(
                family: Ref.fm,
                size: 9,
                wght: 700,
                ls: 4,
                height: 1,
                color: Ref.hot,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// .lockv（L211-212）：锁图标 + 一行说明
  Widget _lock() {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 22,
          height: 22,
          child: CustomPaint(painter: const _LockPainter()),
        ),
        const SizedBox(width: 8),
        Text(
          '完成上一单解锁',
          style: refText(
            family: Ref.fc,
            size: 12,
            wght: 500,
            height: 1,
            color: Ref.dim,
          ),
        ),
      ],
    );
  }
}

/// .sysbox .core 的 46px 简化版（同心环 + 眼点）
class _TinyCorePainter extends CustomPainter {
  const _TinyCorePainter();

  @override
  void paint(Canvas canvas, Size s) {
    final Offset c = s.center(Offset.zero);
    final double r = s.width / 2 - 1;
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Ref.a(Ref.cyan, .75);
    canvas.drawCircle(c, r, ring);
    canvas.drawCircle(
      c,
      r * .62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = Ref.cyan,
    );
    canvas.drawCircle(c, r * .3, Paint()..color = Ref.a(Ref.cyan, .22));
    canvas.drawCircle(c, r * .16, Paint()..color = Ref.cyan);
    canvas.drawCircle(
      c + Offset(-r * .05, -r * .05),
      r * .05,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// .lockv svg（L212）：28×28、stroke 2、fill none
class _LockPainter extends CustomPainter {
  const _LockPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..color = Ref.dim;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, s.height * .42, s.width, s.height * .58),
        const Radius.circular(2),
      ),
      p,
    );
    canvas.drawArc(
      Rect.fromLTWH(s.width * .2, s.height * .06, s.width * .6, s.height * .8),
      math.pi,
      math.pi,
      false,
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
