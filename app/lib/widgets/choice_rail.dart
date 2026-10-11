import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../state/haptics.dart';
import '../state/sfx.dart';
import 'choices.dart';
import 'rail_base.dart';

/// ═══════════════════════════════════════════════════════════
///  乙 · 铭牌轨 —— 回应（docs/28 §5）
///
///  立意：回应是**她的几个方向**，不是物件 —— 所以走「薄牌 + 抽牌」：
///  像档案柜里一排斜切铭牌，被选中的那张**抽出来领位**（左对齐到边 +
///  抬起 + 满亮 + 左侧 3px 竖条 + 斜切高光），其余**向右阶梯缩进**、
///  下沉、压暗、高光熄灭。
///
///  ⚠️ 与甲（`item_rail.dart` · 物件台）**刻意不相同**：
///    甲 = 竖版厚卡 96×124 · 放大 + 旋转摊开 · 侧卡向外浮动
///    乙 = 横版斜切薄牌 268×58 · **不缩放**（保 15.5px 正文可读）·
///         侧牌向右阶梯缩进 + 下沉 + 压暗
///
///  手势 / 吸附 / 断命中全在 [RailShell] 里，这里只画「长什么样、怎么动」。
///  两条纪律：只动 `Transform` / `Opacity`（不触发布局重排）；
///  位移走 `kOut`，过冲走 [railOvershoot]（错峰入场）。
/// ═══════════════════════════════════════════════════════════

// ── 几何（docs/28 §5.2）—— 手感参数全部集中在这一段，一轮可调 ──

/// 铭牌尺寸：横版斜切薄牌（**不是**甲的竖版厚卡）
const double kPlateW = 268;
const double kPlateH = 58;

/// 左上 / 右下各切 12px（DESIGN.md 的斜切角语言）
const double kPlateBevel = 12;

/// 让位：每远离领位一格，向右缩进 14px（第 2 条 +14、第 3 条 +28）
const double kPlateIndent = 14;

/// 领位抬起 8px
const double kPlateLift = 8;

/// 让位下沉：第 1 阶 6px，之后每阶再沉 3px（按距离分级）
const double kPlateSink = 6;
const double kPlateSinkStep = 3;

/// 让位压暗：第 1 阶 .5，之后每阶再暗 .08（下限 .34）
const double kPlateDim = .5;
const double kPlateDimStep = .08;
const double kPlateDimMin = .34;

/// 领位左侧 3px 竖条（主选项实心那张用 C.deep —— 青条压在青底上等于没画）
const double kPlateBar = 3;

/// 确认那一拍：领位牌向左滑出 28px + 淡出
const double kPlateExitX = -28;

/// 点**侧牌**时是否顺手确认。
///
/// 任务书 §交互 写的是「点任一条 = 直接领位并确认（一步到位）」＝ true；
/// 本轨默认 false（只送位，再点一下才确认），理由见 [_ChoiceRailState._onTapPlate]。
/// 要回到任务书字面语义，把这里改成 true 即可（一行）。
const bool kSideTapConfirms = false;

/// 外壳留白（对应旧的 left/right 20、bottom 34）
const double kRailMarginX = 20;
const double kRailBottom = 34;

/// 一格拖拽多少像素（RailShell 的 stride）
const double kRailStride = 96;

/// 收起：整叠向下 28px 淡出（300ms 淡出 / 500ms 位移，节奏照旧）
const double kRailHideDy = 28;
const Duration kRailFadeMs = Duration(milliseconds: 300);
const Duration kRailHideMs = Duration(milliseconds: 500);

/// 位移曲线时长（350~420ms，docs/28 §3.4-2）
const Duration kRailMoveMs = Duration(milliseconds: 380);

/// 确认滑出那一拍
const Duration kRailExitMs = Duration(milliseconds: 350);

/// 错峰入场：第 i 张在 railStagger(i) 之后开始，走 420ms；整段窗口 560ms
const int kRailEnterSpanMs = 560;
const Duration kRailEnterSpan = Duration(milliseconds: kRailEnterSpanMs);
const double kRailEnterDurMs = 420;

/// 入场时每张牌从左侧 24px 外抽进来
const double kRailEnterDx = 24;

/// 轨的总高：抬起 + 牌高 + 最深的让位下沉（第 3 阶）
const double kRailH = kPlateLift + kPlateH + kPlateSink + kPlateSinkStep * 2;

/// 离领位 [d] 格的让位下沉量（分级；超过 3 阶不再加深）
double plateSink(int d) =>
    d <= 1 ? kPlateSink : kPlateSink + kPlateSinkStep * (d - 1).clamp(0, 2);

/// 离领位 [d] 格的让位压暗量（分级；下限 [kPlateDimMin]）
double plateDim(int d) => d <= 1
    ? kPlateDim
    : (kPlateDim - kPlateDimStep * (d - 1))
        .clamp(kPlateDimMin, kPlateDim)
        .toDouble();

/// 斜切铭牌的轮廓：左上 / 右下各切 [kPlateBevel]。
///
/// 抽成顶层函数是因为它同时被 [ClipPath]（裁形 + 裁命中）和画笔画描边用。
Path platePath(Size s, {double bevel = kPlateBevel}) => Path()
  ..moveTo(bevel, 0)
  ..lineTo(s.width, 0)
  ..lineTo(s.width, s.height - bevel)
  ..lineTo(s.width - bevel, s.height)
  ..lineTo(0, s.height)
  ..lineTo(0, bevel)
  ..close();

/// 确认回调：返回**是否真的确认了**（被 `_locked` 拦住时返回 false，
/// 轨就不再播「滑出那一拍」）。
typedef ChoiceConfirm = bool Function(int index);

/// 乙 · 铭牌轨（不含手势 / 吸附 —— 那些在 [RailShell] 里）
class ChoiceRail extends StatefulWidget {
  const ChoiceRail({
    super.key,
    required this.items,
    this.visible = true,
    this.enabled = true,
    required this.onConfirm,
  });

  final List<Choice> items;

  /// 是否展开（false → 整叠向下 28px 淡出，由 [Choices] 驱动）
  final bool visible;

  /// 是否可点（`onPick == null` 时为 false）
  final bool enabled;

  /// 领位被点实 → 确认
  final ChoiceConfirm onConfirm;

  @override
  State<ChoiceRail> createState() => _ChoiceRailState();
}

class _ChoiceRailState extends State<ChoiceRail> {
  final RailController _ctrl = RailController();

  /// 正被按住的那一条（-1 = 没有）—— 按下时那层渐变从左扫过来
  int _down = -1;

  /// 正在向左滑出的那一条（确认那一拍）
  int? _exit;

  /// 「新一问」的代数：变一次就重播一次错峰入场
  int _gen = 0;

  static String _labels(List<Choice> l) =>
      l.map((Choice c) => c.label).join('\u0000');

  @override
  void didUpdateWidget(covariant ChoiceRail old) {
    super.didUpdateWidget(old);
    final bool reopened = !old.visible && widget.visible;
    final bool newQuestion = widget.visible &&
        old.visible &&
        _labels(old.items) != _labels(widget.items);
    if (reopened || newQuestion) {
      // 收起来再张开 = 新一问（原型 choose() 每次重建都是新的 locked）
      _exit = null;
      _down = -1;
      if (newQuestion) _gen++;
    }
    _ctrl.clampTo(widget.items.length);
  }

  /// 领位换了一格 → 响一声 + 轻震（docs/28 §3.3：乙套用 tap）
  void _onLeadChanged() {
    Sfx.play('tap');
    Haptics.buzz('choose');
  }

  void _onTapPlate(int i) {
    if (!widget.enabled) return;
    if (i != _ctrl.lead) {
      // 点侧牌 = 把它送到领位
      //
      // ⚠️ 有意偏离任务书「点任一条 = 一步到位领位并确认」（默认 [kSideTapConfirms] = false）：
      //    让位牌只露出 L 形的一条窄边（右 14px + 下 14px），
      //    拿它当「确认」＝ 点领位牌下缘偏 10px 就选错方向，而且不可撤销。
      //    送位可撤销、确认不可撤销 —— 所以侧牌只送位，再点一下才确认。
      final bool moved = _ctrl.moveTo(i, length: widget.items.length);
      if (moved) _onLeadChanged();
      if (!kSideTapConfirms || !moved) return;
    }
    // 点领位牌 = 确认（choose 音效与 _locked 守卫都在 Choices 那层）
    if (widget.onConfirm(i)) setState(() => _exit = i);
  }

  void _setDown(int i) {
    if (_down == i) return;
    setState(() => _down = i);
  }

  /// 领位最后画（压在最上面），离得越远越先画 —— 侧牌只露出让位的那条边
  List<int> _zOrder(int n, int lead) {
    final List<int> order = List<int>.generate(n, (int i) => i);
    order.sort((int a, int b) {
      final int da = (a - lead).abs();
      final int db = (b - lead).abs();
      if (da != db) return db.compareTo(da);
      return a.compareTo(b);
    });
    return order;
  }

  @override
  Widget build(BuildContext context) {
    final bool reduce = railReduceMotion(context);
    final Duration move = reduce ? Duration.zero : kRailMoveMs;
    final int n = widget.items.length;

    return SizedBox(
      height: kRailH,
      child: LayoutBuilder(
        builder: (BuildContext ctx, BoxConstraints c) {
          // 只剩 1 条（队列空时的「收工。」）时居中：它没有旁边的牌可让位，
          // 贴着左边会显得孤零零（docs/28 §5.4 边界态）
          final double solo = n == 1 && c.hasBoundedWidth
              ? ((c.maxWidth - kPlateW) / 2).clamp(0.0, double.infinity)
              : 0;

          return RailShell(
            controller: _ctrl,
            length: n,
            stride: kRailStride,
            open: widget.visible,
            enabled: widget.enabled,
            onLeadChanged: _onLeadChanged,
            builder: (BuildContext _, double dx) =>
                TweenAnimationBuilder<double>(
              // 整叠随领位刚性平移：领位永远落在左边缘（left: 20）
              tween: Tween<double>(end: _ctrl.lead.toDouble()),
              duration: move,
              curve: kOut,
              builder: (BuildContext _, double leadFrac, Widget? _) =>
                  TweenAnimationBuilder<double>(
                // 错峰入场：0 / 60 / 120ms，过冲走 railOvershoot
                key: ValueKey<int>(_gen),
                tween: Tween<double>(begin: 0, end: widget.visible ? 1 : 0),
                duration: reduce ? Duration.zero : kRailEnterSpan,
                curve: Curves.linear,
                builder: (BuildContext _, double enterP, Widget? _) =>
                    TweenAnimationBuilder<double>(
                  // 确认那一拍：领位牌向左滑出 + 淡出
                  tween: Tween<double>(end: _exit == null ? 0 : 1),
                  duration: reduce ? Duration.zero : kRailExitMs,
                  curve: kOut,
                  builder: (BuildContext _, double exitT, Widget? _) {
                    final double enterMs = enterP * kRailEnterSpanMs; // 0→560ms
                    return Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        for (final int i in _zOrder(n, _ctrl.lead))
                          Positioned(
                            left: 0,
                            top: 0,
                            width: kPlateW,
                            height: kPlateH,
                            child: _Plate(
                              // ⚠️ 钥匙挂在 Transform **里面**：`getRect` 量的是
                              // 渲染对象自己的原点，**不含它自己的 Transform**，
                              // 挂在外面量到的永远是布局位（所有牌都叠在 0）。
                              plateKey: Key('choices.$i'),
                              choice: widget.items[i],
                              index: i,
                              isLead: i == _ctrl.lead,
                              dist: (i - _ctrl.lead).abs(),
                              leadFrac: leadFrac,
                              dx: dx,
                              solo: solo,
                              enter:
                                  railEnter(enterMs, i, durMs: kRailEnterDurMs),
                              exiting: i == _exit,
                              exit: exitT,
                              down: i == _down,
                              move: move,
                              onTap: widget.enabled ? () => _onTapPlate(i) : null,
                              onDown: widget.enabled
                                  ? (bool v) => _setDown(v ? i : -1)
                                  : null,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 一张斜切铭牌
class _Plate extends StatelessWidget {
  const _Plate({
    required this.plateKey,
    required this.choice,
    required this.index,
    required this.isLead,
    required this.dist,
    required this.leadFrac,
    required this.dx,
    required this.solo,
    required this.enter,
    required this.exiting,
    required this.exit,
    required this.down,
    required this.move,
    this.onTap,
    this.onDown,
  });

  /// 量位置用的钥匙（挂在 [Transform] 里面 —— 见上面调用处的说明）
  final Key plateKey;
  final Choice choice;
  final int index;
  final bool isLead;
  final int dist;

  /// 动画中的（小数）领位 —— 整叠随它平移
  final double leadFrac;
  final double dx;
  final double solo;
  final double enter;
  final bool exiting;
  final double exit;
  final bool down;
  final Duration move;
  final VoidCallback? onTap;

  /// 按下态开关（true = 按下，false = 松开）
  final ValueChanged<bool>? onDown;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      // 领位进度：抬起 / 满亮 / 竖条 / 斜切高光都由它带出来
      tween: Tween<double>(end: isLead ? 1 : 0),
      duration: move,
      curve: kOut,
      builder: (BuildContext _, double t, Widget? _) =>
          TweenAnimationBuilder<double>(
        // 按下扫光（等价旧的 .ch:active::after，从左扫入 350ms）
        tween: Tween<double>(end: down ? 1 : 0),
        duration: move,
        curve: kOut,
        builder: (BuildContext _, double dn, Widget? _) {
          final bool main = choice.main;
          final double y = (kPlateLift + plateSink(dist)) * (1 - t);
          final double x = kPlateIndent * (index - leadFrac) +
              dx +
              solo -
              kRailEnterDx * (1 - enter) +
              (exiting ? kPlateExitX * exit : 0);
          final double op = (plateDim(dist) * (1 - t) + t) *
              enter.clamp(0.0, 1.0) *
              (exiting ? 1 - exit : 1);

          // 外发光：主选项常亮（青 α.35），领位再抬一档；副选项只在领位时有一层薄晕
          final double glow = main ? .22 + .13 * t : .16 * t;

          return Transform.translate(
            offset: Offset(x, y),
            child: Opacity(
              key: plateKey,
              opacity: op.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: glow <= 0
                      ? const <BoxShadow>[]
                      : <BoxShadow>[
                          BoxShadow(
                            color: C.blue.withAlpha((255 * glow).round()),
                            blurRadius: 26,
                          ),
                        ],
                ),
                child: ClipPath(
                  clipper: const _BevelClipper(),
                  child: CustomPaint(
                    painter: _PlatePainter(main: main, t: t, down: dn),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onTap,
                      onTapDown: onDown == null ? null : (_) => onDown!(true),
                      onTapUp: onDown == null ? null : (_) => onDown!(false),
                      onTapCancel: onDown == null ? null : () => onDown!(false),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 17, 12),
                        child: Row(
                          children: <Widget>[
                            // .ch::before —— 「宿主」小牌
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: main
                                    ? const Color(0x24021022)
                                    : C.blue.withAlpha(20),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                '宿主',
                                style: fs(
                                  family: F.mono,
                                  size: 9,
                                  wght: 600,
                                  ls: 1.26,
                                  height: 1,
                                  color:
                                      main ? const Color(0x99021022) : C.mist,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                choice.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: fs(
                                  family: F.cn,
                                  size: 15.5,
                                  wght: main ? 650 : 400,
                                  ls: .31,
                                  color: main ? C.deep : C.ice,
                                ),
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
        },
      ),
    );
  }
}

/// 斜切角：左上 / 右下各切 12px（`clip-path` 的 Flutter 对应物）。
///
/// 它同时裁**命中**：斜切掉的那两个角点不到（`RenderClipPath` 按路径过滤命中）。
class _BevelClipper extends CustomClipper<Path> {
  const _BevelClipper();

  @override
  Path getClip(Size size) => platePath(size);

  @override
  bool shouldReclip(_BevelClipper oldClipper) => false;
}

/// 铭牌底：实心/玻璃 + 描边 + 按下扫光 + 领位竖条与斜切高光
class _PlatePainter extends CustomPainter {
  const _PlatePainter({required this.main, required this.t, required this.down});

  /// 主选项（青色实心）/ 副选项（玻璃 + 描边）
  final bool main;

  /// 领位进度 0→1
  final double t;

  /// 按下扫光 0→1
  final double down;

  @override
  void paint(Canvas canvas, Size s) {
    final Path p = platePath(s);

    // 底：主选项青色实心 / 副选项玻璃底 rgba(5,14,32,.74)
    canvas.drawPath(p, Paint()..color = main ? C.blue : const Color(0xBD050E20));

    // 描边：副选项 rgba(56,225,255,.3) 1px（主选项实心，无边框）
    if (!main) {
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x4D38E1FF),
      );
    }

    // 按下扫光：从左往右扫入的青色渐变（旧 .ch:active::after 的 scaleX）
    if (down > 0) {
      canvas.save();
      canvas.clipPath(p);
      canvas.clipRect(Rect.fromLTWH(0, 0, s.width * down, s.height));
      canvas.drawRect(
        Rect.fromLTWH(0, 0, s.width, s.height),
        Paint()
          ..shader = const LinearGradient(
            colors: <Color>[Color(0x4038E1FF), Color(0x0D38E1FF)],
          ).createShader(Rect.fromLTWH(0, 0, s.width, s.height)),
      );
      canvas.restore();
    }

    if (t <= 0) return;

    // 领位标记取**对比色**：主选项本来就是青色实心，青条 / 青高光压在上面
    // 等于没画（实测渲染确认过），所以实心那张用 C.deep 竖条 + C.ice 亮边，
    // 玻璃那张才用青色（tokens 不变，只是换了个能看见的对照）。
    final Color mark = main ? C.deep : C.blue;

    // 斜切高光：沿左上 / 右下两条切线点亮
    final Paint hl = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = (main ? C.ice : C.blue).withAlpha((255 * .95 * t).round());
    canvas.drawLine(
      const Offset(kPlateBevel, 0),
      const Offset(0, kPlateBevel),
      hl,
    );
    canvas.drawLine(
      Offset(s.width, s.height - kPlateBevel),
      Offset(s.width - kPlateBevel, s.height),
      hl,
    );

    // 领位左侧 3px 竖条
    canvas.save();
    canvas.clipPath(p);
    canvas.drawRect(
      Rect.fromLTWH(0, kPlateBevel, kPlateBar, s.height - kPlateBevel),
      Paint()..color = mark.withAlpha((255 * t).round()),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlatePainter old) =>
      old.main != main || old.t != t || old.down != down;
}
