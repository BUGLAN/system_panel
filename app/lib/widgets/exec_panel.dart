import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'hold_button.dart';

import '../data/format.dart';
import '../design/tokens.dart';
import '../state/quest.dart';

/// ═══════════════════════════════════════════════════════════
///  执行面板（app.css L305-356 `#exec` · ui.js `Exec.show`）
///  左边一列：等级章 + 「执行中 · RING 5/8」→ 任务名 → 巨字计时器
///  → 时限进度条 → 「SYSTEM 正在看着你」→ 证据槽 + 暴击率；
///  底部：道具 / 提交 · 让她验收；最下：按住 · 认输 / 收起 ▾。
///
///  实测盒模型（390×844，C 级主线第 5 环）：
///    col [22,92,242,349] · rk [22,92,22,22] · kick [52,97,118,13]
///    name [22,124,242,27] · t [22,175,242,63] · lim [22,248,242,14]
///    bar [22,254,190,3] · limSmall [222,248,42,14]
///    watch [22,280,242,10] · eye [22,281,16,9]
///    evi [22,320,242,121] · eviKick [22,325,130,13] · row [22,349,242,58]
///    slots x=22/88/154 各 58×58 · crit [22,419,242,22]
///    act [20,708,350,54] · item [20,708,88,54] · go [118,708,252,54]
///    low [20,778,350,40] · quit [20,778,98,40] · min [304,778,66,40]
///
///  计时/暴击率/道具/认输都是行为，由宿主后续约束；这里渲染的是
///  「跑了一段时间、还没交证据」的静态样子。
/// ═══════════════════════════════════════════════════════════
class ExecPanel extends StatelessWidget {
  const ExecPanel({
    super.key,
    required this.quest,
    required this.elapsed,
    required this.critChance,
    required this.itemCount,
    required this.evidenceCount,
    this.visible = true,
    this.onSubmit,
    this.onQuit,
    this.onQuitProgress,
  });

  final Quest quest;

  /// 已经executed了多久
  final Duration elapsed;

  /// 暴击率 0~1
  final double critChance;

  /// 可用的执行类道具总数（原型 `#exItemN`）
  final int itemCount;

  /// 已上传证据张数
  final int evidenceCount;

  final bool visible;

  /// 点「提交 · 让她验收」（原型的验收演出是行为，先只留入口）
  final VoidCallback? onSubmit;

  /// 按住「认输」（ui.js L449 quitHold，按满 1.2s）
  final VoidCallback? onQuit;

  /// 认输进度 —— 原型用它驱动 #veil 的暗度（p×.75）
  final ValueChanged<double>? onQuitProgress;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final Color rk = quest.rarity.color;
    final Duration limit = Duration(minutes: quest.minutes);
    final double progress = (elapsed.inMilliseconds / limit.inMilliseconds)
        .clamp(0.0, 1.0);
    final bool warn = elapsed.inMilliseconds > limit.inMilliseconds * .85;

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (BuildContext _, BoxConstraints c) => Stack(
          children: <Widget>[
            // .ex-col
            Positioned(
              left: 22,
              top: 92,
              width: c.maxWidth * .62,
              child: Column(
                key: const Key('exec.col'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _kindRow(rk),
                  const SizedBox(height: 10),
                  Text(
                    quest.name,
                    style: fs(
                      family: F.hd,
                      size: 21,
                      wght: 400,
                      ls: .42,
                      height: 1.3,
                      color: C.ice,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    fmtClock(elapsed),
                    // 计时器永远不许折行（窄屏上 07:00 会被挤成两行）
                    maxLines: 1,
                    style: fs(
                      family: F.num,
                      size: 70,
                      wght: 800,
                      wdth: 78,
                      ls: .7,
                      height: .9,
                      color: warn ? Colors.white : const Color(0xFFF3FDFF),
                      shadows: <Shadow>[
                        Shadow(color: C.blue.withAlpha(128), blurRadius: 26),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _limitRow(progress),
                  const SizedBox(height: 18),
                  _watchRow(),
                  const SizedBox(height: 30),
                  _evidence(),
                ],
              ),
            ),
            // .ex-act
            Positioned(
              left: 20,
              right: 20,
              bottom: 82,
              child: Row(
                key: const Key('exec.act'),
                children: <Widget>[
                  _itemButton(),
                  const SizedBox(width: 10),
                  _submitButton(),
                ],
              ),
            ),
            // .ex-low
            Positioned(
              left: 20,
              right: 20,
              bottom: 26,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[_quitButton(), _miniButton()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// .ex-k —— 稀有度章 + 「执行中 · RING 5/8」
  Widget _kindRow(Color rk) {
    final String kindTxt = quest.kind == 'main'
        ? 'RING ${quest.ring + 1}/${quest.ringTotal}'
        : quest.kind == 'remedy'
        ? 'REMEDY'
        : 'DAILY';
    return Row(
      children: <Widget>[
        Container(
          key: const Key('exec.rk'),
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: rk, width: 1.5),
          ),
          child: Text(
            quest.rank,
            style: fs(family: F.num, size: 13, wght: 900, height: 1, color: rk),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '执行中 · $kindTxt',
          style: fs(
            family: F.mono,
            size: 10,
            wght: 400,
            ls: 1.6,
            height: 1,
            color: C.mist,
          ),
        ),
      ],
    );
  }

  /// .ex-lim —— 时限进度条 + `/ 45:00`
  Widget _limitRow(double progress) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Container(
            key: const Key('exec.bar'),
            height: 3,
            decoration: BoxDecoration(
              color: C.blue.withAlpha(31), // rgba(56,225,255,.12)
              borderRadius: BorderRadius.circular(2),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: progress,
                // heightFactor 不给的话，无子元素的 DecoratedBox 会被量成 0 高（条就没了）
                heightFactor: 1,
                child: DecoratedBox(
                  key: const Key('exec.bar.fill'),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: <Color>[C.blue2, C.blue],
                    ),
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: <BoxShadow>[
                      BoxShadow(color: C.blue, blurRadius: 10),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '/ ${fmtClock(Duration(minutes: quest.minutes))}',
          style: fs(family: F.num, size: 11, wght: 600, ls: .44, color: C.mist),
        ),
      ],
    );
  }

  /// .ex-watch —— 一只眼睛 + 「SYSTEM 正在看着你」
  Widget _watchRow() {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 16,
          height: 9,
          child: CustomPaint(painter: const _EyePainter()),
        ),
        const SizedBox(width: 8),
        Text(
          'SYSTEM 正在看着你',
          style: fs(
            family: F.mono,
            size: 10,
            wght: 500,
            ls: 1,
            height: 1,
            color: C.mist,
          ),
        ),
      ],
    );
  }

  /// .ex-evi —— 证据槽 + 暴击率
  Widget _evidence() {
    final List<Widget> slots = <Widget>[];
    for (int i = 0; i < 3; i++) {
      final bool filled = i < evidenceCount;
      final bool isAdd = i == evidenceCount;
      slots.add(
        Padding(
          padding: EdgeInsets.only(right: i == 2 ? 0 : 8),
          child: Container(
            key: Key('exec.slot.$i'),
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0x80061024), // rgba(6,16,36,.5)
              borderRadius: BorderRadius.circular(6),
              // .slot 空槽 line2 / .slot.add line / .slot.full 青色 + 外发光
              border: Border.all(
                color: filled ? C.blue : (isAdd ? C.line : C.line2),
                width: 1,
              ),
              boxShadow: filled
                  ? <BoxShadow>[
                      BoxShadow(color: C.blue.withAlpha(77), blurRadius: 12),
                    ]
                  : null,
            ),
            child: isAdd ? const Center(child: _Plus()) : null,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // CSS 里这行 kick 是 inline，行框由父级 16px 的 strut 撑到 19.2，
        // 文字因此下沉 5px —— 这里用 padding 复刻同样的落点
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            // `.kick` 有 text-transform: uppercase —— 原型的「跑步 App 截图」在这里印成「跑步 APP 截图」
            '证据 · ${quest.proof.toUpperCase()}',
            style: fs(
              family: F.mono,
              size: 10,
              wght: 400,
              ls: 1.6,
              height: 1.28,
              color: C.mist,
            ),
          ),
        ),
        const SizedBox(height: 11),
        Row(children: slots),
        const SizedBox(height: 12),
        // `.ex-crit` 的行框由里面 17px 的 b 撑到 22
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: '暴击率',
                style: fs(family: F.cn, size: 12, wght: 400, color: C.mist),
              ),
              TextSpan(
                text: '${(critChance * 100).round()}%',
                style: fs(
                  family: F.num,
                  size: 17,
                  wght: 800,
                  ls: .34,
                  color: C.blue,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// .btn.ghost —— 道具
  Widget _itemButton() {
    return Container(
      key: const Key('exec.item'),
      height: 54,
      // Border 占布局、CSS 的 inset 阴影不占 → padding 各减 1px 才与原型同宽
      padding: const EdgeInsets.symmetric(horizontal: 19),
      decoration: BoxDecoration(
        color: const Color(0xB3040E20), // rgba(4,14,32,.7)
        borderRadius: BorderRadius.circular(27),
        border: Border.all(color: C.line, width: 1),
      ),
      child: Row(
        children: <Widget>[
          Text(
            '道具',
            style: fs(
              family: F.cn,
              size: 15,
              wght: 600,
              ls: .9,
              height: 1,
              color: C.ice,
            ),
          ),
          if (itemCount > 0) ...<Widget>[
            const SizedBox(width: 8),
            Text(
              '$itemCount',
              style: fs(
                family: F.num,
                size: 11,
                wght: 700,
                height: 1,
                color: C.blue,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// .btn.main —— 提交 · 让她验收
  Widget _submitButton() {
    return Expanded(
      child: GestureDetector(
        onTap: onSubmit,
        behavior: HitTestBehavior.opaque,
        child: Container(
          key: const Key('exec.go'),
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: C.blue,
            borderRadius: BorderRadius.circular(27),
            boxShadow: <BoxShadow>[
              BoxShadow(color: C.blue.withAlpha(102), blurRadius: 28),
            ],
          ),
          child: Stack(
            children: <Widget>[
              // inset 0 1px 0 rgba(255,255,255,.6)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.white.withAlpha(153)),
                ),
              ),
              Text(
                '提交 · 让她验收',
                style: fs(
                  family: F.cn,
                  size: 15,
                  wght: 600,
                  ls: .9,
                  height: 1,
                  color: C.deep,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// .quit —— 按住 · 认输（ui.js L449 `quitHold`）
  ///
  /// **按满 1.2s**，松手以 0.3s 退回。按住期间：
  ///  · 按钮里的 `i` 宽度 = p×100%
  ///  · **`#veil` 的不透明度 = p×.75**（屏幕随着按住越来越暗）
  ///  · 文案从「按住 · 认输」变「松手还来得及」
  Widget _quitButton() {
    return HoldButton(
      duration: const Duration(milliseconds: 1200),
      decay: const Duration(milliseconds: 300),
      onProgress: onQuitProgress,
      onComplete: () => onQuit?.call(),
      builder: (BuildContext context, double p) => Container(
        key: const Key('exec.quit'),
        height: 40,
        // `.quit { position:relative; overflow:hidden }` —— 进度条被圆角裁掉
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0x407D8CA5),
            width: 1,
          ), // rgba(125,140,165,.25)
        ),
        child: Stack(
          children: <Widget>[
            // `.quit i { position:absolute; left:0; top:0; bottom:0; width:p*100% }`
            // —— **整高**的一条，从左边长出来
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: p,
                  heightFactor: 1,
                  child: const ColoredBox(color: Color(0x387D8CA5)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 17),
              child: Center(
                child: Text(
                  p > 0 ? '松手还来得及' : '按住 · 认输',
                  style: fs(
                    family: F.cn,
                    size: 12.5,
                    wght: 400,
                    color: const Color(0xFF7D8CA5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// .mini —— 收起 ▾
  Widget _miniButton() {
    return Container(
      key: const Key('exec.min'),
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      child: Text(
        '收起 ▾',
        style: fs(family: F.cn, size: 12, wght: 400, height: 1, color: C.mist),
      ),
    );
  }
}

/// `.ex-watch .eye` —— 一只扁圆眼睛 + 中间那颗会看人的点
/// CSS 是 `inset 0 0 0 1.2px` 的一圈描边 + `::after` 4×4 圆点带 `0 0 5px` 辉光；
/// 辉光用 MaskFilter 会糊过头（实测墨量到 262%），改用收敛的径向渐变。
class _EyePainter extends CustomPainter {
  const _EyePainter();

  @override
  void paint(Canvas canvas, Size s) {
    final Rect r = Offset.zero & s;
    // `.eye { width:16px; height:9px; box-shadow: inset 0 0 0 1.2px }`
    // ⚠️ 之前我把它画扁了（以为 Chrome 对 border-radius:50% 的 inset 环渲染得更扁）——
    // 那是错的：原型在 `#exEye` 上挂了个 `transform: scaleY(.7)` 的眨眼/口型动画，
    // 我清掉 onTick 后它冻在了半截。CSS 本来就是 16×9，照画即可。
    canvas.drawOval(
      r.deflate(.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = C.blue,
    );
    final Offset c = Offset(s.width / 2, s.height / 2);
    canvas.drawCircle(
      c,
      4.5,
      Paint()
        ..shader = ui.Gradient.radial(c, 4.5, <Color>[
          C.blue.withAlpha(110),
          C.blue.withAlpha(0),
        ]),
    );
    canvas.drawCircle(c, 2, Paint()..color = C.blue);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// `.ex-evi .slot.add` 的加号（16×1.5 两根，一根转 90°）
class _Plus extends StatelessWidget {
  const _Plus();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(width: 16, height: 1.5, color: C.blue),
          Transform.rotate(
            angle: 1.5707963267948966,
            child: Container(width: 16, height: 1.5, color: C.blue),
          ),
        ],
      ),
    );
  }
}
