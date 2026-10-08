import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;

import 'hold_button.dart';
import 'press_scale.dart';

import '../agent/vision.dart';
import '../data/format.dart';
import '../data/items.dart';
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
    this.tags = const <String>{},
    required this.evidenceCount,
    this.evidence,
    this.onAddEvidence,
    this.onEvidenceChanged,
    this.onRemoveEvidence,
    this.vision,
    this.visible = true,
    this.onSubmit,
    this.onQuit,
    this.onQuitProgress,
    this.onItem,
    this.onCollapse,
  });

  final Quest quest;

  /// 已经executed了多久
  final Duration elapsed;

  /// 暴击率 0~1
  final double critChance;

  /// 可用的执行类道具总数（原型 `#exItemN`）
  final int itemCount;

  /// 本单已经挂上生效的道具 id（原型 `A.dbl / A.crit / A.shield`）——
  /// 会显示成暴击率右边那串小标签
  final Set<String> tags;

  /// 已上传证据张数。
  /// ⚠️ legacy：旧调用（demo 链路）传的占位数；新链路改传 [evidence]
  /// 列表（受控）或不传（面板内置管线自持），这个数就不再参与渲染。
  final int evidenceCount;

  /// D9：证据列表（受控模式）。给了它，槽位/暴击率就按它算，
  /// [evidenceCount] 被忽略；不给则面板自己持有会话内证据（内部流），
  /// 拍照/选图 → 可选 LLM 校验 → 缩略图入槽，全程不经宿主也能用。
  final List<EvidenceShot>? evidence;

  /// D9：点「+」槽。给了就全权交给宿主（自管管线）；不给走面板内置
  /// 拍照/相册选择 + VisionService 管线。
  final VoidCallback? onAddEvidence;

  /// D9：内置管线增删证据后回传（宿主可拿去存档/结算）
  final ValueChanged<List<EvidenceShot>>? onEvidenceChanged;

  /// D9：长按已填槽移除（受控模式下交给宿主处理）
  final ValueChanged<int>? onRemoveEvidence;

  /// D9：证据管线（默认 VisionService()：真 picker + 真设置；测试可注入假件）
  final VisionService? vision;

  final bool visible;

  /// 点「提交 · 让她验收」（原型的验收演出是行为，先只留入口）
  final VoidCallback? onSubmit;

  /// 按住「认输」（ui.js L449 quitHold，按满 1.2s）
  final VoidCallback? onQuit;

  /// 认输进度 —— 原型用它驱动 #veil 的暗度（p×.75）
  final ValueChanged<double>? onQuitProgress;

  /// 点「道具」开合抽屉
  final VoidCallback? onItem;

  /// 收起 ▾（回大厅，计时继续）
  final VoidCallback? onCollapse;

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

  /// .ex-evi —— 证据槽 + 暴击率（D9：槽位可拍照/选图，标记与暴击率联动）
  Widget _evidence() {
    return _EvidenceBlock(
      quest: quest,
      critBase: critChance,
      tags: tags,
      evidence: evidence,
      onAddEvidence: onAddEvidence,
      onEvidenceChanged: onEvidenceChanged,
      onRemoveEvidence: onRemoveEvidence,
      vision: vision,
    );
  }

  /// .btn.ghost —— 道具（点它开合抽屉，原型 `#exItem` → `Exec.drawer()`）
  Widget _itemButton() {
    return GestureDetector(
      onTap: onItem,
      child: Container(
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
      ),
    );
  }

  /// .btn.main —— 提交 · 让她验收（`.btn:active { scale(.96) }`）
  Widget _submitButton() {
    return Expanded(
      child: PressScale(
        onTap: onSubmit,
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

  /// .mini —— 收起 ▾（原型 `#exMin` → `App.lobby()`：回大厅，**计时不停**）
  Widget _miniButton() {
    return GestureDetector(
      onTap: onCollapse,
      behavior: HitTestBehavior.opaque,
      child: Container(
        key: const Key('exec.min'),
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        child: Text(
          '收起 ▾',
          style: fs(
            family: F.cn,
            size: 12,
            wght: 400,
            height: 1,
            color: C.mist,
          ),
        ),
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

/// ═══════════════════════════════════════════════════════════
///  D9 · 证据区（槽位 + 暴击率），docs/18 §2.4
///
///  · 点「+」→ 拍照/相册（没有 onAddEvidence 时走内置
///    VisionService 管线：picker ≤1280px JPEG q80 → 落盘 → 可选 LLM
///    校验 → 缩略图入槽；无 Key/断网/超时/坏 JSON 一律标「未校验」）
///  · 长按已填槽 → 移除（受控模式交给 onRemoveEvidence）
///  · 暴击率 = critBase + 已校验×7% + 未校验×4%，封顶 .85
///    （critBase 是宿主传入的基础值；无证据时原样显示，保持旧语义）
///  · 受控：evidence 列表由宿主给；非受控：块内自己持有会话内证据
/// ═══════════════════════════════════════════════════════════
class _EvidenceBlock extends StatefulWidget {
  const _EvidenceBlock({
    required this.quest,
    required this.critBase,
    this.tags = const <String>{},
    this.evidence,
    this.onAddEvidence,
    this.onEvidenceChanged,
    this.onRemoveEvidence,
    this.vision,
  });

  final Quest quest;
  final double critBase;
  final Set<String> tags;
  final List<EvidenceShot>? evidence;
  final VoidCallback? onAddEvidence;
  final ValueChanged<List<EvidenceShot>>? onEvidenceChanged;
  final ValueChanged<int>? onRemoveEvidence;
  final VisionService? vision;

  @override
  State<_EvidenceBlock> createState() => _EvidenceBlockState();
}

class _EvidenceBlockState extends State<_EvidenceBlock> {
  /// 非受控模式的会话内证据（受控时不用它）
  List<EvidenceShot> _internal = const <EvidenceShot>[];
  bool _busy = false;

  VisionService get _vision => widget.vision ?? VisionService();

  List<EvidenceShot> get _shots => widget.evidence ?? _internal;

  @override
  Widget build(BuildContext context) {
    final List<EvidenceShot> shots = _shots;
    final int count = shots.length;

    final List<Widget> slots = <Widget>[];
    for (int i = 0; i < 3; i++) {
      final bool filled = i < count;
      final bool isAdd = i == count;
      slots.add(
        Padding(
          padding: EdgeInsets.only(right: i == 2 ? 0 : 8),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: isAdd ? _onAdd : null,
            onLongPress: filled ? () => _onRemove(i) : null,
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
              child: filled
                  ? _thumb(shots[i])
                  : (isAdd ? const Center(child: _Plus()) : null),
            ),
          ),
        ),
      );
    }

    // 暴击率：无证据时原样显示基础值（旧语义）；有证据则 7%/4% 联动封顶 .85
    final int verified = shots
        .where((EvidenceShot s) => s.status == EvidenceStatus.verified)
        .length;
    final int unverified = count - verified;
    final double displayCrit = count == 0
        ? widget.critBase
        : math.min(.85, widget.critBase + evidenceCritBonus(
            verified: verified,
            unverified: unverified,
          ));

    // 最新一条存疑的 note（验收要求「存疑+note」可见）；
    // 没有存疑时退而显示最新一条「未校验」的原因（无 Key/断网/超时…）
    String? noteLine;
    for (final EvidenceShot s in shots.reversed) {
      if (s.status == EvidenceStatus.suspect && s.note.isNotEmpty) {
        noteLine = '存疑 · ${s.note}';
        break;
      }
    }
    if (noteLine == null) {
      for (final EvidenceShot s in shots.reversed) {
        if (s.status == EvidenceStatus.unverified && s.note.isNotEmpty) {
          noteLine = '未校验 · ${s.note}';
          break;
        }
      }
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
            '证据 · ${widget.quest.proof.toUpperCase()}',
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
        if (noteLine != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              noteLine,
              key: const Key('exec.evi.note'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: fs(
                family: F.mono,
                size: 10,
                wght: 500,
                height: 1.2,
                color: const Color(0xFFFF8F99),
              ),
            ),
          ),
        const SizedBox(height: 12),
        // `.ex-crit` 的行框由里面 17px 的 b 撑到 22
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Text.rich(
              key: const Key('exec.crit.value'),
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: '暴击率',
                    style: fs(family: F.cn, size: 12, wght: 400, color: C.mist),
                  ),
                  TextSpan(
                    text: '${(displayCrit * 100).round()}%',
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
            // `.tags`：本单已经挂上生效的道具（原型 `Exec.crit()` 里按
            // `['dbl','crit','shield'].filter(k => A[k])` 拼出来的那串 `<i>`）
            if (widget.tags.isNotEmpty) const SizedBox(width: 8),
            // ⚠️ 顺序照原型写死（`['dbl','crit','shield'].filter(k => A[k])`）——
            //    传进来的是 Set，无序，直接遍历会时对时错
            for (final String k in Item.execIds)
              if (widget.tags.contains(k)) _tag(k),
          ],
        ),
      ],
    );
  }

  /// 58×58 缩略图 + 右下角状态角标（照片丢了降级「已丢失」）
  Widget _thumb(EvidenceShot s) {
    final String? abs = s.absPath;
    final Widget photo = (abs == null || abs.isEmpty)
        ? _lostGlyph()
        : Image.file(
            File(abs),
            fit: BoxFit.cover,
            width: 56,
            height: 56,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
                _lostGlyph(),
          );
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: photo,
          ),
        ),
        Positioned(right: 2, bottom: 2, child: _badge(s.status)),
      ],
    );
  }

  Widget _badge(EvidenceStatus status) {
    final (Color bg, Color fg) = switch (status) {
      EvidenceStatus.verified => (C.blue, C.deep),
      EvidenceStatus.suspect => (const Color(0xFFFF4D5E), Colors.white),
      EvidenceStatus.unverified => (const Color(0xEE04122A), C.mist),
    };
    return Container(
      key: Key('exec.evi.badge.${status.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        status.badge,
        style: fs(family: F.mono, size: 8, wght: 700, height: 1.2, color: fg),
      ),
    );
  }

  /// 照片读不到/没存下：证据计数照旧，图标降级
  Widget _lostGlyph() {
    return Container(
      key: const Key('exec.evi.lost'),
      color: const Color(0x14060F20),
      alignment: Alignment.center,
      child: Text(
        '已丢失',
        style: fs(family: F.cn, size: 9, wght: 400, height: 1, color: C.dim),
      ),
    );
  }

  /// `.ex-crit .tags i` —— 10px 等宽、实心青底、深色字
  Widget _tag(String id) {
    final Item? it = Item.byId(id);
    if (it == null) return const SizedBox.shrink();
    return Container(
      key: Key('exec.tag.$id'),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: C.blue,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        '${it.glyph} ${it.name}',
        style: fs(
          family: F.mono,
          size: 10,
          wght: 700,
          height: 1,
          color: C.deep,
        ),
      ),
    );
  }

  Future<void> _onAdd() async {
    // 宿主自管管线（main.dart 后续接线入口）
    final VoidCallback? ext = widget.onAddEvidence;
    if (ext != null) {
      ext();
      return;
    }
    if (_busy) return;
    if (_shots.length >= 3) return; // 双保险：槽位只有 3 格
    setState(() => _busy = true);
    try {
      final ImageSource? src = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: const Color(0xEE061228),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        ),
        builder: (BuildContext sheetCtx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final (ImageSource, String, String) opt in const <(ImageSource, String, String)>[
                (ImageSource.camera, '拍照', '现场拍一张'),
                (ImageSource.gallery, '从相册选', '挑一张现成的'),
              ])
                ListTile(
                  leading: Text(
                    opt.$1 == ImageSource.camera ? '◉' : '▣',
                    style: fs(family: F.num, size: 16, wght: 700, color: C.blue),
                  ),
                  title: Text(
                    opt.$2,
                    style: fs(family: F.cn, size: 14, wght: 400, color: C.ice),
                  ),
                  subtitle: Text(
                    opt.$3,
                    style: fs(family: F.cn, size: 10.5, wght: 400, color: C.mist),
                  ),
                  onTap: () => Navigator.of(sheetCtx).pop(opt.$1),
                ),
            ],
          ),
        ),
      );
      if (src == null || !mounted) return;
      if (_shots.length >= 3) return;
      final EvidenceShot? shot = await _vision.capture(
        quest: widget.quest,
        source: src,
      );
      if (shot == null || !mounted) return; // 取消/失败都不进槽
      if (widget.evidence != null) {
        // 受控模式：内置管线产出的新列表回传宿主
        widget.onEvidenceChanged?.call(
          List<EvidenceShot>.unmodifiable(<EvidenceShot>[..._shots, shot]),
        );
        return;
      }
      setState(() {
        _internal = List<EvidenceShot>.unmodifiable(<EvidenceShot>[
          ..._internal,
          shot,
        ]);
      });
      widget.onEvidenceChanged?.call(_internal);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onRemove(int i) {
    if (widget.evidence != null) {
      widget.onRemoveEvidence?.call(i);
      return;
    }
    if (i < 0 || i >= _internal.length) return;
    setState(() {
      _internal = List<EvidenceShot>.unmodifiable(<EvidenceShot>[
        for (int j = 0; j < _internal.length; j++)
          if (j != i) _internal[j],
      ]);
    });
    widget.onEvidenceChanged?.call(_internal);
  }
}
