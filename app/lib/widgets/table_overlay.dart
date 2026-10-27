import 'package:flutter/material.dart';

import '../data/items.dart';
import '../data/titles.dart';
import '../design/tokens.dart';
import '../state/host_state.dart';
import 'card_table.dart';
import 'rail_base.dart';

/// ═══════════════════════════════════════════════════════════
///  悬浮牌局（docs/32 §3）—— 牌**直接浮在主界面上**
///
///  宿主原话：「脱离传统的网页 UI 设计，直接让卡牌悬浮在主界面上」。
///  所以这里**没有面板、没有弹层壳、没有分节标题**：
///
///   · 一层幕（她还在后面，看得见），点幕 = 收起
///   · 从她胸口打下来的一道**光束**（牌就是从这条线里出来的）
///   · 悬浮的文字（kicker / 标题 / 一行说明）—— 没有框
///   · 悬浮的读数（补给=金币 / 称号=已得张数）—— 右上角，没有框
///   · **牌**：整桌浮在舞台下三分之一（`CardTable`，皮肤按场景给）
///   · 底部一枚悬浮的出口铭牌（斜切小键）
///
///  ── 材质口径（apple-design §12）────────────────────────────
///   · **materialize，不是干淡入**：幕进场时**模糊半径与不透明度一起长**
///     （0 → 14px），读起来是「一块材质落下来」，而不是「画面变暗了」。
///   · **幕是功能层**：她退到后面、牌浮在前面 —— 深度由材质给，不靠描边。
///   · **减弱透明度**（§14）：幕换实底，不做模糊。
///   · 出口铭牌：≥44pt 命中 + 按下 100ms 缩到 .97（§1 / §7）。
/// ═══════════════════════════════════════════════════════════

enum TableScene { supply, titles, evidence }

class TableOverlay extends StatefulWidget {
  const TableOverlay({
    super.key,
    required this.scene,
    this.host,
    this.onBuy,
    this.onEquip,
    this.onPick,
    this.onClose,
    this.initialLead,
  });

  final TableScene scene;

  /// 补给 / 称号需要宿主存档（金币 / 持有数 / 称号）
  final HostState? host;

  /// 买下（返回**新的**存档；返回 null = 没买成）
  final HostState? Function(String id)? onBuy;

  /// 挂上称号（返回**新的**存档；返回 null = 没换）
  final HostState? Function(String id)? onEquip;

  /// 取景窗选了一个来源（0 = 拍照 / 1 = 相册）
  final ValueChanged<int>? onPick;

  final VoidCallback? onClose;

  /// 开局把哪一张放在**领位**。不传时：称号场景落在**当前佩戴的那张**
  /// （打开名牒册，手指正好在她给你戴着的那张上），其余场景用牌桌的
  /// 默认（正中那张）。测试也用它把某张牌精确送到领位。
  final int? initialLead;

  @override
  State<TableOverlay> createState() => _TableOverlayState();
}

class _TableOverlayState extends State<TableOverlay>
    with SingleTickerProviderStateMixin {
  HostState? _host;

  /// 她的一句话（买下 / 换称号之后）
  String? _line;

  /// 幕与文字一起 materialize（220ms，ease-out，无过冲）
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  @override
  void initState() {
    super.initState();
    _host = widget.host;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 减弱动态：只做 160ms 淡入（不模糊、不位移）
    if (railReduceMotion(context)) {
      _enter.duration = const Duration(milliseconds: 160);
    }
    if (!_enter.isAnimating && _enter.value == 0) _enter.forward();
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  // ── 场景文案 ────────────────────────────────────────────────
  //
  // ⚠️ 这里**故意没有** kicker / 标题 / 一行说明，也**没有出口按钮**。
  //    宿主原话：用户已经点到了「补给」，他就知道这是补给 ——
  //    再挂一行「点侧牌翻到中间，再点一下买下」是废话；
  //    出口也不需要按钮，**点其他地方就是取消**。
  //    所以只剩：读数（数字，有用）+ 她的话（她开口，不是说明）。

  String? get _readout {
    final HostState? h = _host;
    if (h == null) return null;
    return switch (widget.scene) {
      // docs/48 §2：补给不再重复印余额 —— HUD 右上的金色货币胶囊就在
      // 同一屏（宿主截图里「26」和「◈26」同时出现，读两遍）。
      TableScene.supply => null,
      TableScene.titles =>
        '${h.ownedTitles.length.toString().padLeft(2, '0')} / '
            '${HostTitle.all.length.toString().padLeft(2, '0')}',
      TableScene.evidence => null,
    };
  }

  // ── 牌 ─────────────────────────────────────────────────────
  CardSkin get _skin => switch (widget.scene) {
    TableScene.supply => CardSkin.shelf,
    TableScene.titles => CardSkin.tag,
    TableScene.evidence => CardSkin.frame,
  };

  CardTableSize get _size => switch (widget.scene) {
    TableScene.supply => CardTableSize.l,
    TableScene.titles => CardTableSize.m,
    TableScene.evidence => CardTableSize.l,
  };

  List<TableCard> _cards() {
    final HostState? h = _host;
    switch (widget.scene) {
      case TableScene.supply:
        if (h == null) return const <TableCard>[];
        return <TableCard>[
          for (final Item it in Item.all)
            TableCard(
              id: it.id,
              kicker: 'ITEM · ${it.id.toUpperCase()}',
              title: it.name,
              glyph: it.glyph,
              rule: it.desc,
              badge: '持有 ×${h.items[it.id] ?? 0}',
              price: it.price,
              enabled: h.coins >= it.price,
              sealWord: '买',
            ),
        ];
      case TableScene.titles:
        if (h == null) return const <TableCard>[];
        return <TableCard>[
          for (int i = 0; i < HostTitle.all.length; i++)
            TableCard(
              id: HostTitle.all[i].id,
              index: i + 1,
              kicker: HostTitle.all[i].shame ? 'SHAME' : 'TITLE',
              title: h.ownedTitles.contains(HostTitle.all[i].id)
                  ? HostTitle.all[i].name
                  : '？？？',
              glyph: h.ownedTitles.contains(HostTitle.all[i].id) ? null : '?',
              rule: h.ownedTitles.contains(HostTitle.all[i].id)
                  ? null
                  : HostTitle.all[i].hint,
              badge: h.title == HostTitle.all[i].id ? '已佩戴' : null,
              accent: HostTitle.all[i].shame ? C.rS : null,
              locked: !h.ownedTitles.contains(HostTitle.all[i].id),
              shame: HostTitle.all[i].shame,
              enabled: h.ownedTitles.contains(HostTitle.all[i].id),
              sealWord: '佩',
            ),
        ];
      case TableScene.evidence:
        return const <TableCard>[
          TableCard(
            id: 'camera',
            kicker: 'SOURCE 01',
            title: '拍照',
            glyph: '◉',
            rule: '现场拍一张',
            sealWord: '拍',
          ),
          TableCard(
            id: 'gallery',
            kicker: 'SOURCE 02',
            title: '从相册选',
            glyph: '▣',
            rule: '挑一张现成的',
            sealWord: '选',
          ),
        ];
    }
  }

  /// 领位落在第几张：显式给了就用它；称号场景默认落在**当前佩戴的那张**
  /// （打开名牒册时她给你戴着的那张牌就在手指下，不用先滑过去找）。
  int? _leadIndex() {
    final int? forced = widget.initialLead;
    if (forced != null) return forced;
    final HostState? h = _host;
    if (h == null || widget.scene != TableScene.titles) return null;
    final int i = HostTitle.all.indexWhere((HostTitle t) => t.id == h.title);
    return i >= 0 ? i : null;
  }

  void _pick(int i) {
    switch (widget.scene) {
      case TableScene.supply:
        final HostState? next = widget.onBuy?.call(Item.all[i].id);
        if (next == null) return;
        setState(() {
          _host = next;
          _line = '钱货两讫。省着点用。';
        });
      case TableScene.titles:
        final HostState? next = widget.onEquip?.call(HostTitle.all[i].id);
        if (next == null) return;
        setState(() {
          _host = next;
          _line = '换上了。……还行。';
        });
      case TableScene.evidence:
        widget.onPick?.call(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool reduce = railReduceMotion(context);

    return Material(
      color: Colors.transparent,
      child: AnimatedBuilder(
        animation: _enter,
        builder: (BuildContext _, Widget? _) {
          final double t = reduce
              ? 1
              : kEnterCurve.transform(_enter.value.clamp(0.0, 1.0));
          return Stack(
            children: <Widget>[
              // ── 只有一层**看不见的**点击层：点空白处收起 ──
              //
              // ⚠️ 不做幕、不压暗、**不模糊**：宿主明确要求后面的界面
              //    必须清清楚楚（后续要拿它做角色口型），
              //    所以这里连 `BackdropFilter` 都不挂。
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onClose,
                ),
              ),
              // ── 她的话（她开口，不是说明文字）──
              if (_line != null)
                Positioned(
                  left: 24,
                  right: 24,
                  top: 96,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: t,
                      child: Text(
                        '» $_line',
                        style: fs(
                          family: F.cn,
                          size: 12.5,
                          wght: 500,
                          height: 1.35,
                          color: C.ice,
                        ),
                      ),
                    ),
                  ),
                ),
              // ── 悬浮读数（没有框）──
              if (_readout != null)
                Positioned(
                  right: 24,
                  top: 92,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: t,
                      child: Text(
                        _readout!,
                        style: fs(
                          family: F.num,
                          size: 20,
                          wght: 800,
                          ls: -.4,
                          height: 1,
                          color: C.blue,
                        ),
                      ),
                    ),
                  ),
                ),
              // ── 牌：整桌浮在舞台下三分之一 ──
              //
              // 没有出口按钮：**点其他地方就是取消**（上面那层全屏点击层）。
              Positioned(
                left: 0,
                right: 0,
                bottom: 104,
                child: CardTable(
                  cards: _cards(),
                  skin: _skin,
                  size: _size,
                  onPick: _pick,
                  initialLead: _leadIndex(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// ⚠️ 这里**故意没有任何压在她身上的装饰线**（曾经有一条「从她胸口打下来的光束」
/// + 一枚六边锚点）：宿主原话「这个背景的线给我删了」。
/// 牌局**只浮牌**，她身上一根线都不画。
