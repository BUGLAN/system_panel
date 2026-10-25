import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'hold_button.dart';

import '../agent/llm_client.dart';
import '../agent/llm_telemetry.dart';
import '../agent/settings_store.dart';
import '../data/items.dart';
import '../state/haptics.dart';
import '../state/sfx.dart';
import '../data/rewards.dart';
import '../data/titles.dart';
import '../design/tokens.dart';
import '../state/host_state.dart';
import '../state/plan_failure.dart';
import '../stage/live2d_stage.dart';
import '../stage/perf_presets.dart';
import '../state/settings.dart';
import 'radar.dart';
import 'card_table.dart';
import 'stats_pane.dart';

/// ═══════════════════════════════════════════════════════════
///  投影面板（app.css L78-81 `#beam` + L436-498 `#sheet`）
///  她胸口打出一道光，光落在桌面上的那块投影上——档案/补给/系统共用这一层壳。
///
///  实测盒模型（390×844）：
///    sheet [0,321,390,523]（top 38%）
///    head [0,321,390,71] · kick [20,345,124,12] · h3 [20,364,124,22] · × [334,344,36,36]
///    body [0,392,390,452]（可滚）
///    arTop [20,400,350,47] · radar [45,488,300,245]
///    secs y = 465 / 751 / 849 / 1058（每个 margin-top 18）
///    beam 顶点 (195, .31173H)
/// ═══════════════════════════════════════════════════════════
class Sheet extends StatefulWidget {
  const Sheet({
    super.key,
    required this.host,
    this.settings = AppSettings.demo,
    this.kind = SheetKind.archive,
    this.visible = true,
    this.onClose,
    this.onWipe,
    this.onEquipTitle,
    this.onOpenTitles,
    this.onBuyItem,
    this.onSettingsChanged,
    this.onOpenPerfDebug,
    this.planError,
    this.planErrorGoal = '',
  });

  final HostState host;

  /// 系统页那几个开关的当前值
  final AppSettings settings;
  final SheetKind kind;
  final bool visible;
  final VoidCallback? onClose;

  /// 「按住 2 秒」重置存档 —— 原型重置后 `location.reload()`，未绑定就回到绑定仪式
  final VoidCallback? onWipe;

  /// D6：点已解锁称号挂上（规则在组件内侧守卫：未解锁忽略；
  /// 口头巨人生效中禁止换挂 —— store.js `equip`）。宿主侧接到 QuestFlow.equip。
  final ValueChanged<String>? onEquipTitle;

  final VoidCallback? onOpenTitles;

  /// D7：点购买（买得起才触发；买不起按钮已置灰）。宿主侧接到 QuestFlow.buy。
  final ValueChanged<String>? onBuyItem;

  /// D8/LLM：系统页任意设置变化回传（四开关 + 视觉校验组），
  /// 持久化由设置组自己经 SettingsStore 落盘，这里只是给宿主同步的机会。
  final ValueChanged<AgentSettings>? onSettingsChanged;

  /// 打开「表演调试台」（宿主 2026-10-11：调试预设/动作/表情；由 main.dart 挂叠层）
  final VoidCallback? onOpenPerfDebug;

  /// 最近一次**目标拆解失败**（2026-10-23：拆解不再有兜底，失败要可观测）。
  ///
  /// 只读回显在设置页「LLM」组底部，给开发者一眼看到失败类别与原因；
  /// null = 没失败过。它是**诊断仪表**，不参与任何业务判定。
  final PlanFailure? planError;
  final String planErrorGoal;

  static const Map<SheetKind, List<String>> _titles = <SheetKind, List<String>>{
    SheetKind.archive: <String>['ARCHIVE · 宿主档案', '档案'],
    SheetKind.supply: <String>['SUPPLY · 补给', '补给'],
    SheetKind.system: <String>['SYSTEM · 设置', '系统'],
  };

  @override
  State<Sheet> createState() => _SheetState();
}

class _SheetState extends State<Sheet> {
  /// 面板正文的滚动控制器。
  ///
  /// ⚠️ 它存在的唯一理由：档案页点「本周战绩与六维走势」切到回顾视图时，
  /// `SingleChildScrollView` 会**沿用上一屏的滚动偏移**，于是新视图一进来就停在
  /// 底部（宿主 2026-10-11 报的「跳过去确实底部，不符合样式」）。
  /// 换视图时把偏移归零，滚动位置就跟着视图走。
  final ScrollController _scroll = ScrollController();

  // 只读别名：这个类里 host / kind / visible / settings 出现得太多，
  // 每处都写 widget. 只会让 diff 变吵。别名只转发，不缓存。
  HostState get host => widget.host;
  SheetKind get kind => widget.kind;
  bool get visible => widget.visible;
  AppSettings get settings => widget.settings;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toTop() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final double h = MediaQuery.sizeOf(context).height;
    final List<String> t = Sheet._titles[kind]!;
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Positioned(
      left: 0,
      right: 0,
      top: h * .38,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !visible,
        // 减弱动态（apple-design §14）：不滑屏，只做 160ms 交叉淡入
        child: AnimatedSlide(
          offset: visible
              ? Offset.zero
              : Offset(0, reduce ? 0 : 1.04), // translateY(104%)
          duration: Duration(milliseconds: reduce ? 160 : 550),
          curve: kOut,
          child: AnimatedOpacity(
            opacity: reduce && !visible ? 0 : 1,
            duration: const Duration(milliseconds: 160),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0xE6061228), Color(0xF7030812)],
                  stops: <double>[0, .3],
                ),
              ),
              child: Stack(
                // `.sh-edge::after` 有一半探到面板上沿外面（CSS 里 #sheet 不裁），
                // Stack 默认 hardEdge 会把它切掉
                clipBehavior: Clip.none,
                children: <Widget>[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _head(t[0], t[1]),
                      Expanded(
                        child: SingleChildScrollView(
                          key: const Key('sheet.body'),
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 34),
                          child: _body(),
                        ),
                      ),
                    ],
                  ),
                  // docs/48 §2：面板上沿的「羽化」—— 原来面板在她胸口处一刀
                  // 硬切（宿主截图：上半是她、下半突然一块黑板）。往上探 36px
                  // 的渐变把切口溶进舞台；CustomPaint 而非 DecoratedBox，
                  // 不污染按类型查找装饰的测试。
                  const Positioned(
                    left: 0,
                    right: 0,
                    top: -36,
                    height: 36,
                    child: IgnorePointer(
                      child: CustomPaint(painter: _FeatherPainter()),
                    ),
                  ),
                  // .sh-edge —— 顶边那道光
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _EdgePainter(),
                        size: const Size(double.infinity, 1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// .sh-head
  Widget _head(String kicker, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // `.sh-k` 是 inline，行框被父级 16px strut 撑到 19.2、文字下沉 6px
                SizedBox(
                  height: 19.2,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      kicker,
                      key: const Key('sheet.kicker'),
                      style: fs(
                        family: F.mono,
                        size: 9.5,
                        wght: 600,
                        ls: 2.09,
                        height: 1,
                        color: C.blue,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  key: const Key('sheet.title'),
                  style: fs(
                    family: F.hd,
                    size: 22,
                    wght: 400,
                    ls: .88,
                    height: 1,
                    color: C.ice,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: widget.onClose,
            behavior: HitTestBehavior.opaque,
            child: Container(
              key: const Key('sheet.close'),
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: C.line, width: 1),
              ),
              child: Text(
                '×',
                style: fs(
                  family: F.cn,
                  size: 22,
                  wght: 400,
                  height: 1,
                  color: C.ice,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    switch (kind) {
      case SheetKind.archive:
        return _archive();
      case SheetKind.supply:
        return _supply();
      case SheetKind.system:
        return _system();
    }
  }

  /// ── 档案 ──────────────────────────────────────────────
  Widget _archive() {
    return _ArchiveSwitch(
      host: host,
      // 换视图（档案 ↔ 回顾）时把面板正文的滚动偏移归零 —— 否则回顾视图
      // 会沿用档案页的偏移、一进来就停在底部（宿主 2026-10-11 报的那个）。
      onViewChanged: _toTop,
      profileBuilder: (VoidCallback openReview) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _arTop(),
          _section(
            '六维 · 线性刻度 · 满值 50',
            // `.radar { width:100%; max-width:300px; margin:4px auto 0 }` —— 要居中，
            // 不能让它被 Column 的 stretch 拉满
            Center(
              child: Radar(attrs: host.attrs, weakKey: host.weakest.key),
            ),
          ),
          _section('战绩', _stats()),
          // 称号只有**一处**（宿主 2026-10-11：「这两个是同一个东西，保留下面的，
          // 但是重命名为称号」）—— 就是这一行入口，点它拉起悬浮的名牒册。
          _section('称号', _titlesEntry(), top: 12),
          // ⚠️ 「道具」那一段（两列格）**已按宿主指定删除**：宿主原话
          //    「此页面那个道具就不用显示了，因为主页面就已经有了这个道具了，
          //     显示是冗余的」。四件道具的持有数在**补给货架**上都有
          //    （`TableOverlay` / `_supply()` 的 `持有 ×N` 角标），信息不丢。
          _section('数据 · 本周回顾', _reviewEntry(openReview)),
        ],
      ),
    );
  }

  /// 回顾入口（A6）：档案 loot 格语言的一行，点进 StatsPane
  Widget _reviewEntry(VoidCallback onTap) {
    return GestureDetector(
      // 每一次有效交互都要有对应反馈（§3.3）
      onTap: () {
        Sfx.play('tap');
        Haptics.buzz('choose');
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        key: const Key('sheet.reviewEntry'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: C.blue.withAlpha(10), // rgba(56,225,255,.04)（道具格同款）
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: <Widget>[
            Text(
              '本周战绩与六维走势',
              style: fs(
                family: F.cn,
                size: 12.5,
                wght: 400,
                height: 1,
                color: C.ice,
              ),
            ),
            const Spacer(),
            Text(
              '›',
              style: fs(
                family: F.mono,
                size: 14,
                wght: 500,
                height: 1,
                color: C.mist,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// .ar-top —— 大等级 + 经验条 + 称号
  Widget _arTop() {
    return Row(
      key: const Key('sheet.arTop'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            // small：10px mono，vertical-align .9em（10×.9 = 9px）
            Transform.translate(
              offset: const Offset(0, -9),
              child: Text(
                'LV',
                style: fs(
                  family: F.mono,
                  size: 10,
                  wght: 600,
                  ls: 2,
                  height: 1,
                  color: C.mist,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${host.lv}',
              style: fs(
                family: F.num,
                size: 44,
                wght: 900,
                wdth: 80,
                height: 1,
                color: const Color(0xFFF3FDFF),
                shadows: <Shadow>[
                  Shadow(color: C.blue.withAlpha(128), blurRadius: 20),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 14), // .ar-top gap
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _arRow('EXP', <InlineSpan>[
                TextSpan(
                  text: '${host.exp}',
                  style: fs(
                    family: F.num,
                    size: 11,
                    wght: 700,
                    height: 1.3,
                    color: C.ice,
                  ),
                ),
                // t24：经验环分母 = 结算升级曲线（`Rewards.needFor`）唯一真源。
                // 旧版读 `HostState.need` 的 60+lv×40，LV7 显示 /340 而真实
                // need=54 —— 环常年在用户眼里几乎空着（docs/20 §2.2-2）。
                TextSpan(text: ' / ${Rewards.needFor(host.lv)}'),
              ]),
              const SizedBox(height: 6),
              _bar(host.expRatio),
              const SizedBox(height: 8),
              _arRow('称号', <InlineSpan>[
                TextSpan(
                  text: '「${HostTitle.nameOf(host.title)}」',
                  style: fs(
                    family: F.cn,
                    size: 10,
                    wght: 400,
                    ls: 0,
                    height: 1.3,
                    color: C.blue,
                  ),
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  /// .ar-exp p —— 左标题右读数
  Widget _arRow(String label, List<InlineSpan> right) {
    final TextStyle base = fs(
      family: F.mono,
      size: 10,
      wght: 600,
      ls: 1,
      height: 1.3,
      color: C.mist,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(label, style: base),
        Text.rich(TextSpan(children: right, style: base)),
      ],
    );
  }

  /// `.rs-bar`（档案里复用结算那条）
  Widget _bar(double frac) {
    return Container(
      key: const Key('sheet.bar'),
      height: 6,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: C.blue.withAlpha(26),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: frac.clamp(0.0, 1.0),
          heightFactor: 1,
          child: DecoratedBox(
            key: const Key('sheet.bar.fill'),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[C.blue2, C.blue, Color(0xFFDFFAFF)],
                stops: <double>[0, .7, 1],
              ),
              borderRadius: BorderRadius.circular(3),
              boxShadow: <BoxShadow>[BoxShadow(color: C.blue, blurRadius: 12)],
            ),
          ),
        ),
      ),
    );
  }

  /// .sec —— 一条 kicker + 后面拉满的细线，再挂内容
  Widget _section(String kicker, Widget child, {double top = 18}) {
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 13,
            child: Row(
              children: <Widget>[
                Text(
                  kicker,
                  style: fs(
                    family: F.mono,
                    size: 10,
                    wght: 400,
                    ls: 1.6,
                    height: 1,
                    color: C.mist,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Container(height: 1, color: C.line2)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  /// .stats —— 四个读数
  Widget _stats() {
    final List<List<String>> cells = <List<String>>[
      <String>['${host.doneCount}', '完成'],
      <String>['${host.critCount}', '暴击'],
      <String>['${host.failCount}', '认输'],
      <String>['${host.bestStreak}', '最长连击'],
    ];
    return Row(
      key: const Key('sheet.stats'),
      children: <Widget>[
        for (int i = 0; i < cells.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
              decoration: BoxDecoration(
                color: C.blue.withAlpha(13), // rgba(56,225,255,.05)
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: <Widget>[
                  Text(
                    cells[i][0],
                    style: fs(
                      family: F.num,
                      size: 20,
                      wght: 800,
                      height: 1,
                      color: C.ice,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cells[i][1],
                    style: fs(family: F.cn, size: 10, wght: 400, color: C.mist),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 面板里只留一枚入口（**只写册子，不重复称号名** —— 名字在上一段的 chip 上
  /// 已经有了，同一个名字出现两次是噪音）。点它拉起悬浮的名牒册。
  Widget _titlesEntry() {
    return GestureDetector(
      key: const Key('sheet.titles'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Sfx.play('tap');
        Haptics.buzz('choose');
        widget.onOpenTitles?.call();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: C.blue.withAlpha(10), // 与「道具格 / 回顾入口」同款
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: C.line2),
        ),
        child: Row(
          children: <Widget>[
            Text(
              '名牒册',
              style: fs(
                family: F.mono,
                size: 9,
                wght: 600,
                ls: 1.4,
                height: 1,
                color: C.blue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '整册浮在舞台上 · 挑一张挂上',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: fs(
                  family: F.cn,
                  size: 12.5,
                  wght: 400,
                  height: 1,
                  color: C.ice,
                ),
              ),
            ),
            Text(
              '${host.ownedTitles.length}/${HostTitle.all.length} 张',
              style: fs(
                family: F.num,
                size: 12,
                wght: 700,
                height: 1,
                color: C.mist,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '›',
              style: fs(
                family: F.mono,
                size: 14,
                wght: 500,
                height: 1,
                color: C.mist,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ── 补给（金币唯一去处） ────────────────────────────────
  ///
  /// docs/32 §13-4：四行列表 → **牌桌 · 货架**：四张牌摊开，
  /// 点侧牌送位、点领位落定购买；买不起 = 灰 + 价签红描边（点了不生效）。
  Widget _supply() {
    final List<Item> items = Item.all;
    // 领位落在**买得起的那一件**上：一进来就有一张牌可以立刻落定，
    // 而不是先看一张灰的、还得左右滑过去（docs/32 §5.1「任一时刻恰有一个领位」）。
    // 全买不起时退回中位（保持原型那套居中几何）。
    final int firstAfford = items.indexWhere(
      (Item it) => host.coins >= it.price,
    );
    final int lead = firstAfford >= 0 ? firstAfford : (items.length - 1) ~/ 2;
    return _section(
      '金币 ◈ ${host.coins} · 只能花在这',
      CardTable(
        key: const Key('sheet.shop'),
        size: CardTableSize.l,
        initialLead: lead,
        cards: <TableCard>[
          for (final Item it in items)
            TableCard(
              id: it.id,
              kicker: 'ITEM · ${it.id.toUpperCase()}',
              title: it.name,
              glyph: it.glyph,
              rule: it.desc,
              badge: '持有 ×${host.items[it.id] ?? 0}',
              price: it.price,
              enabled: host.coins >= it.price,
              sealWord: '买',
            ),
        ],
        onPick: (int i) {
          final Item it = items[i];
          if (host.coins < it.price) return; // 买不起：点了不生效
          widget.onBuyItem?.call(it.id);
        },
      ),
      top: 6, // 原型这处 `.sec` 带 inline style="margin-top:6px"
    );
  }

  /// ── 系统（四个开关 + LLM·视觉校验组 + 按住重置，D8） ────────
  /// 状态与持久化都在 [_SystemPane]：四开关与 LLM 组写
  /// `opus-v2/settings/v1`，重启保留。
  Widget _system() {
    return _SystemPane(
      // 一级菜单顶部那行实时读数要读宿主（LV/连击/道具数）——菜单即仪表
      host: host,
      settingsSeed: settings,
      // 位置/结构取 feat/ui（_SheetState 里一律走 widget.）；
      // onOpenPerfDebug 是 master 的「表演调试台」回调，保留
      onWipe: widget.onWipe,
      onSettingsChanged: widget.onSettingsChanged,
      onOpenPerfDebug: widget.onOpenPerfDebug,
      // 目标拆解失败（2026-10-23：拆解没有兜底，失败必须在设置页看得到）
      planError: widget.planError,
      planErrorGoal: widget.planErrorGoal,
      // 一级 ↔ 二级切换时把面板正文滚回顶部：一级清单比二级长，不归零的话
      // 进二级会沿用清单的滚动位置，看上去就是「先闪过一段内容才进二级」
      onViewChanged: _toTop,
    );
  }
}

/// ── 系统子面板（宿主指定：二级菜单）────────────────────────
///
/// 一级 = 模块清单（[_SetCat] 五类，每行回显当前值）；
/// 二级 = 分类子面板（表头常驻 + 内容独立滚动），控件沿用旧 ID 与回调。
///
/// 自己持有状态：所有开关与 LLM 组经 [SettingsStore]（`opus-v2/settings/v1`）
/// 持久化，重启保留；文本改动防抖 400ms 落盘，关面板时兜底写最后一笔。
/// [_cat] 只是一层视图状态，不落盘 —— 关面板/切底栏即时复位到一级。
/// 设置页的一级分类（宿主指定：二级菜单）。
///
/// 分类口径来自宿主 2026-10-11 原话：「菜单分别为，音效设置、level、
/// 2D 设置、LM 设置，其他关于这些的」——「2D」经宿主确认为 **Live2D 设置**。
/// 所以是这五类：音效 / 声音 / Live2D / LLM / 系统。
/// `name` 同时是控件 Key 的后缀（`sheet.setMenu.<name>` / `sheet.setPane.<name>`），
/// 改字等于改测试锚点，别随手改。
enum _SetCat {
  sound('音效', 'SOUND · 音效', '♪'),
  voice('声音', 'VOICE · 她的声音', '◍'),
  live2d('Live2D', 'LIVE2D · 角色', '◈'),
  llm('LLM', 'LLM · 视觉校验', '✦'),
  system('本机', 'SYSTEM · 控制台', '⚙');

  const _SetCat(this.label, this.kicker, this.glyph);

  /// 一级菜单上的名字
  final String label;

  /// mono kicker（一级的行内副标题，二级的表头 kicker）
  final String kicker;

  /// 图标框里的那个字形（**不用 emoji**：全是几何/音乐记号，字体一定有）
  final String glyph;
}

class _SystemPane extends StatefulWidget {
  const _SystemPane({
    required this.host,
    required this.settingsSeed,
    this.onWipe,
    this.onSettingsChanged,
    this.onOpenPerfDebug,
    this.onViewChanged,
    this.planError,
    this.planErrorGoal = '',
  });

  /// 最近一次目标拆解失败（只读诊断回显）
  final PlanFailure? planError;
  final String planErrorGoal;

  /// 一级菜单顶部那行实时读数用的宿主副本（LV / 连击 / 道具数）
  final HostState host;

  /// 存档加载完成前的初值（main.dart 未接 settings 时 = AppSettings.demo）
  final AppSettings settingsSeed;
  final VoidCallback? onWipe;
  final ValueChanged<AgentSettings>? onSettingsChanged;
  final VoidCallback? onOpenPerfDebug;

  /// 一级 ↔ 二级切换时回调（宿主拿它把面板正文滚回顶部）
  final VoidCallback? onViewChanged;

  @override
  State<_SystemPane> createState() => _SystemPaneState();
}

class _SystemPaneState extends State<_SystemPane> {
  final SettingsStore _store = SettingsStore();
  late AgentSettings _s;
  late final TextEditingController _baseC;
  late final TextEditingController _keyC;
  late final TextEditingController _modelC;
  Timer? _debounce;
  bool _testing = false;
  bool? _testOk;
  String _testStatus = '';

  /// 当前停在哪一级：null = 一级模块清单，非 null = 二级子面板。
  /// 面板每次重开都会重建 [_SystemPane]，所以「切底栏/关面板即时复位」是白拿的。
  _SetCat? _cat;

  @override
  void initState() {
    super.initState();
    final AppSettings seed = widget.settingsSeed;
    _s = AgentSettings(
      sound: seed.sound,
      haptic: seed.haptic,
      holo: seed.holo,
      voice: seed.voice,
      reasoningEffort: seed.reasoningEffort,
      strictMode: seed.strictMode,
      paceMs: seed.paceMs,
    );
    _baseC = TextEditingController(text: _s.baseUrl);
    _keyC = TextEditingController(text: _s.apiKey);
    _modelC = TextEditingController(text: _s.model);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // 关面板时把没等到防抖的最后一笔直接落盘
    _store.save(_s);
    _baseC.dispose();
    _keyC.dispose();
    _modelC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final AgentSettings s = await _store.load();
    if (!mounted) return;
    setState(() {
      _s = s;
      _baseC.text = s.baseUrl;
      _keyC.text = s.apiKey;
      _modelC.text = s.model;
    });
  }

  void _update(AgentSettings Function(AgentSettings) fn) {
    setState(() => _s = fn(_s));
    widget.onSettingsChanged?.call(_s);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _store.save(_s);
    });
  }

  void _onField(String key, String v) {
    switch (key) {
      case 'sheet.llm.base':
        _update((AgentSettings s) => s.copyWith(baseUrl: v));
      case 'sheet.llm.key':
        _update((AgentSettings s) => s.copyWith(apiKey: v));
      case 'sheet.llm.model':
        _update((AgentSettings s) => s.copyWith(model: v));
    }
  }

  /// 「测试连接」：按当前输入（含未落盘的）发一条**与聊天同形状**的请求
  /// （同一思考档位、同一 max_tokens），回显成败与原因。
  /// LlmClient 不抛异常，这里永远能落到一行结论。
  ///
  /// 验收 F-2 修的两点：① 判成功不能只看 `ok` —— 端点是推理模型，
  /// 「HTTP 200 + 正文为空」曾被显示成「连接成功」，正是宿主抱怨的
  /// 「测连接通了、聊天却兜底」的来源；② 思考档位要跟着设置走，别用默认值探。
  Future<void> _testConn() async {
    if (_testing) return;
    final LlmConfig config = LlmConfig(
      baseUrl: _s.baseUrl,
      apiKey: _s.apiKey,
      model: _s.model,
      reasoningEffort: _s.reasoningEffort,
    );
    setState(() {
      _testing = true;
      _testOk = null;
      _testStatus = '测试中…';
    });
    final LlmReply r = await LlmClient(config: config).ping();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = r.hasText;
      if (r.hasText) {
        _testStatus = config.modelWasNormalized
            ? '连接成功 · ${config.model}→${config.normalizedModel}'
            : '连接成功 · ${config.normalizedModel}';
      } else if (r.ok) {
        // 连上了但没吐字 = 隐性失败，必须说清楚，不许打勾
        _testStatus =
            '连上了但没吐字（HTTP 200、正文为空——多半是思考把 '
            'max_tokens 用尽：把「思考档位」调低，或别把上限设太小）';
      } else {
        _testStatus = '失败 · ${_failureText(r.failure, r.detail)}';
      }
    });
  }

  static String _failureText(LlmFailure? kind, String? detail) {
    switch (kind) {
      case LlmFailure.noKey:
        return '未配置 API Key';
      case LlmFailure.timeout:
      case LlmFailure.network:
        return detail ?? '网络不可达';
      case LlmFailure.httpError:
      case LlmFailure.badResponse:
      case null:
        return detail ?? '未知原因';
    }
  }

  /// ── 一级 · 模块清单（宿主指定：二级菜单）────────────────────
  ///
  /// 宿主原话：「系统此处分为二级菜单，再从这个二级菜单点进去，才是里面的
  /// 具体的这种细节……分类显示，这也符合 APP 的设计规则」。
  ///
  /// 一级只回答「有哪些模块、各自现在是什么值」——它本身就是一块仪表；
  /// 二级才放控件。**控件 ID 与回调一律沿用旧键**（`sheet.seg.*` /
  /// `sheet.llm.*` / `sheet.danger`），功能零改动，只是搬了家。
  ///
  /// ⚠️ master 的「表演调试台」（`sheet.perfDebug`）原在一个扁平列表里，
  ///    feat/ui 拆二级后它归入 **Live2D · 角色** 子面板（见 [_paneBody]）。
  Widget _menu() {
    return Column(
      key: const Key('sheet.set'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _menuBrand(),
        const SizedBox(height: 14),
        for (int i = 0; i < _SetCat.values.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: 2),
          _menuRow(_SetCat.values[i]),
        ],
        const SizedBox(height: 18),
        _sysAbout(),
      ],
    );
  }

  /// 菜单顶部：品牌块 + 一行实时读数（菜单即仪表）
  Widget _menuBrand() {
    final String state =
        'LV${widget.host.lv} · 连击 ${widget.host.bestStreak} · 道具 ${widget.host.items.values.fold<int>(0, (int a, int b) => a + b)}';
    return Container(
      key: const Key('sheet.setBrand'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: C.blue.withAlpha(10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: C.line2, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'SYSTEM CONSOLE',
            style: fs(
              family: F.mono,
              size: 10,
              wght: 600,
              ls: 2,
              height: 1,
              color: C.blue,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            state,
            style: fs(
              family: F.num,
              size: 12,
              wght: 700,
              height: 1,
              color: C.ice,
            ),
          ),
        ],
      ),
    );
  }

  /// 一级的一行：图标框 + 名称/kicker + 当前值回显 + ›
  Widget _menuRow(_SetCat c) {
    return GestureDetector(
      key: Key('sheet.setMenu.${c.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _cat = c);
        widget.onViewChanged?.call();
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: C.line2, width: 1)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: C.blue.withAlpha(15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: C.line, width: 1),
              ),
              child: Text(
                c.glyph,
                style: fs(
                  family: F.cn,
                  size: 13,
                  wght: 500,
                  height: 1,
                  color: C.blue,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    c.label,
                    style: fs(family: F.cn, size: 14, wght: 400, color: C.ice),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    c.kicker,
                    style: fs(
                      family: F.mono,
                      size: 9,
                      wght: 400,
                      ls: 1.6,
                      height: 1,
                      color: C.mist,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _summary(c),
              key: Key('sheet.setSum.${c.name}'),
              style: fs(
                family: F.num,
                size: 11,
                wght: 700,
                height: 1,
                color: C.blue,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '›',
              style: fs(
                family: F.mono,
                size: 14,
                wght: 500,
                height: 1,
                color: C.mist,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 二级 · 子面板（表头常驻 + 内容独立滚动）
  Widget _pane(_SetCat c) {
    return Column(
      key: Key('sheet.setPane.${c.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[_subHead(c), _paneBody(c)],
    );
  }

  /// 子面板表头：返回键 + 分类 kicker/标题（表头常驻，不随内容滚）
  Widget _subHead(_SetCat c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          GestureDetector(
            key: const Key('sheet.setBack'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() => _cat = null);
              widget.onViewChanged?.call();
            },
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: C.line, width: 1),
              ),
              child: Text(
                '‹',
                style: fs(
                  family: F.mono,
                  size: 16,
                  wght: 500,
                  height: 1,
                  color: C.ice,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  c.kicker,
                  style: fs(
                    family: F.mono,
                    size: 9,
                    wght: 600,
                    ls: 1.8,
                    height: 1,
                    color: C.blue,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  c.label,
                  style: fs(
                    family: F.hd,
                    size: 18,
                    wght: 400,
                    ls: .64,
                    height: 1,
                    color: C.ice,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 子面板正文：每一类各自的分组（控件沿用旧键，功能零改动）
  Widget _paneBody(_SetCat c) {
    switch (c) {
      case _SetCat.sound:
        return _rows(<Widget>[
          _setRow(
            '音效',
            Sfx.failCount == 0 && Sfx.dropCount == 0
                ? '离线音效包（76 件）· 单发音效正常；逐字电子音已知限制（见下）'
                : '离线音效包（76 件）·'
                      '${Sfx.failCount > 0 ? ' ⚠️ 播放失败 ${Sfx.failCount} 次：${Sfx.lastError ?? ''}' : ''}'
                      '${Sfx.dropCount > 0 ? ' ⚠️ 起播超时丢弃 ${Sfx.dropCount} 发（最近 ${Sfx.lastDrop ?? ''}）' : ''}',
            _seg(
              'sound',
              const <List<String>>[
                <String>['1', '开'],
                <String>['0', '关'],
              ],
              _s.sound ? '1' : '0',
              (String v) {
                _update((AgentSettings s) => s.copyWith(sound: v == '1'));
              },
            ),
          ),
          // docs/48 §4：音效要「克制」—— 三档音量，过程音再按规则打折
          _setRow(
            '界面音量',
            '按键 / 翻牌 / 落定的音量；过程音自动更轻、连点自动节流',
            _seg(
              'sfxVol',
              const <List<String>>[
                <String>['lo', '低'],
                <String>['mid', '中'],
                <String>['hi', '高'],
              ],
              _s.sfxVol,
              (String v) {
                _update((AgentSettings s) => s.copyWith(sfxVol: v));
              },
            ),
          ),
        ]);
      case _SetCat.voice:
        return _rows(<Widget>[
          _setRow(
            '她的声音',
            '人声用浏览器自带中文语音，效果看设备',
            _seg('voice', AppSettings.voiceOptions, _s.voice, (String v) {
              _update((AgentSettings s) => s.copyWith(voice: v));
            }),
          ),
          _setRow(
            '对白节奏',
            '她每个字蹦出来的速度：慢 42 / 标准 34 / 快 24 毫秒；点一句可立刻铺完',
            _seg('pace', AppSettings.paceOptions, '${_s.paceMs}', (String v) {
              _update(
                (AgentSettings s) => s.copyWith(
                  paceMs: int.tryParse(v) ?? AgentSettings.kDefaultPaceMs,
                ),
              );
            }),
          ),
        ]);
      case _SetCat.live2d:
        return _rows(<Widget>[
          // master 的「表演调试台」（宿主 2026-10-11）：二级菜单重构后它归到
          // Live2D · 角色 这一格 —— 它本来就是预设/动作/表情的调试入口。
          _setRow(
            '表演调试台',
            '预设 ${PerfPresets.all.length} 条（动作 × 表情）、18 个动作组、'
                '${Live2DStage.expressions.length} 个表情 —— 点一下就地演给你看',
            GestureDetector(
              key: const Key('sheet.perfDebug'),
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onOpenPerfDebug?.call(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: C.line),
                ),
                child: Text(
                  '打开',
                  style: fs(family: F.cn, size: 12, wght: 700, color: C.ice),
                ),
              ),
            ),
          ),
          _setRow(
            '全息描边',
            '她身上的电光轮廓；低端机可关',
            _seg(
              'holo',
              const <List<String>>[
                <String>['1', '开'],
                <String>['0', '关'],
              ],
              _s.holo ? '1' : '0',
              (String v) {
                _update((AgentSettings s) => s.copyWith(holo: v == '1'));
              },
            ),
          ),
          // docs/48 §5：低性能模式 —— 舞台光静态、去粒子、卡面箔不漂移
          _setRow(
            '舞台特效',
            '舞台光呼吸 / 浮尘 / 卡面全息箔；省电档只保留一次性反馈',
            _seg(
              'fidelity',
              const <List<String>>[
                <String>['high', '高'],
                <String>['low', '省电'],
              ],
              _s.fidelity,
              (String v) {
                _update((AgentSettings s) => s.copyWith(fidelity: v));
              },
            ),
          ),
          // ⚠️ 模型地址（原型设置页的 `#l2dUrl`）在 Flutter 端**还没有落点**，
          //    所以这里如实写出来，不放一个假的输入框：
          //    「说得出在哪改」比「看起来能改」重要。
          _setRow(
            '角色模型',
            '现在读的是随包发的那一份；换 model3.json 地址这一步还没接',
            Text(
              '随包',
              style: fs(
                family: F.mono,
                size: 10,
                wght: 600,
                height: 1,
                color: C.mist,
              ),
            ),
          ),
        ]);
      case _SetCat.llm:
        return _llmSection();
      case _SetCat.system:
        return _rows(<Widget>[
          // docs/22 §R1-2：思考档位（请求体 reasoning_effort，默认 low）
          _setRow(
            '思考档位',
            '低（默认）；档位越高想得越久、拆得越细',
            _seg('effort', AppSettings.reasoningOptions, _s.reasoningEffort, (
              String v,
            ) {
              _update((AgentSettings s) => s.copyWith(reasoningEffort: v));
            }),
          ),
          // docs/22 §2.0：严格模式（自动＝按构建切，可手动覆盖）
          _setRow(
            '严格模式',
            '自动＝debug/profile 构建下失败直接报错、不产兜底台词；release 仍兜底但标注原因',
            _seg('strict', AppSettings.strictOptions, _s.strictMode, (
              String v,
            ) {
              _update((AgentSettings s) => s.copyWith(strictMode: v));
            }),
          ),
          _setRow(
            '震动',
            '真波形震动（15 处节奏）· 模拟器不震，真机才有手感',
            _seg(
              'haptic',
              const <List<String>>[
                <String>['1', '开'],
                <String>['0', '关'],
              ],
              _s.haptic ? '1' : '0',
              (String v) {
                _update((AgentSettings s) => s.copyWith(haptic: v == '1'));
              },
            ),
          ),
          _setRow('重置存档', '一切从绑定重新开始', _danger()),
        ]);
    }
  }

  /// `.set` 的行距（原来那份一长条的排法，原样保留）
  Widget _rows(List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < rows.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: 2),
          rows[i],
        ],
      ],
    );
  }

  /// 一级菜单里每一行的「当前值」回显 —— 菜单本身就是仪表
  String _summary(_SetCat c) {
    switch (c) {
      case _SetCat.sound:
        return _s.sound ? '开' : '关';
      case _SetCat.voice:
        final String name = AppSettings.voiceOptions
            .where((List<String> o) => o[0] == _s.voice)
            .map((List<String> o) => o[1])
            .join();
        return '${name.isEmpty ? _s.voice : name} · ${_s.paceMs}ms';
      case _SetCat.live2d:
        return _s.holo ? '描边 开' : '描边 关';
      case _SetCat.llm:
        return _s.visionEnabled ? '校验 开' : '校验 关';
      case _SetCat.system:
        return _s.haptic ? '震动 开' : '震动 关';
    }
  }

  /// 菜单底部：控制台状态条（只读回显，可观测）
  Widget _sysAbout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _kicker('SYSTEM · 本机'),
        Text(
          '存档 key opus-v2/widget.settings/v1 · 角色模型随包 · 音效 ${_s.sound ? '开' : '关'} · 语音 ${_s.voice}\n她派任务，你去现实里做，拍下证据，她结算。',
          style: fs(
            family: F.cn,
            size: 11.5,
            wght: 400,
            height: 1.7,
            color: const Color(0xFF5F7190),
          ),
        ),
      ],
    );
  }

  /// LLM·视觉校验组（docs/18 §2.4）：开关 + BaseURL + Key(掩码) + 模型名 + 测试连接
  ///
  /// 现在它整组就是「LLM」那个二级子面板的正文 —— 分类标题由子面板表头承担，
  /// 所以这里不再挂 `_kicker`（同一个名字出现两次是噪音）。
  Widget _llmSection() {
    return _rows(<Widget>[
      _setRow(
        '视觉校验',
        '拍照后交她核一眼；关=纯信任，全按未校验计',
        _seg(
          'vision',
          const <List<String>>[
            <String>['1', '开'],
            <String>['0', '关'],
          ],
          _s.visionEnabled ? '1' : '0',
          (String v) {
            _update((AgentSettings s) => s.copyWith(visionEnabled: v == '1'));
          },
        ),
      ),
      _llmField('接口地址', 'OpenAI 兼容端点，默认官方 DeepSeek', _baseC, 'sheet.llm.base'),
      _llmField(
        'API Key',
        '只存本机；留空=不校验，证据标「未校验」',
        _keyC,
        'sheet.llm.key',
        obscure: true,
      ),
      _llmField(
        '模型名',
        '默认 deepseek-v4.1flash（请求前自动归一）',
        _modelC,
        'sheet.llm.model',
      ),
      const SizedBox(height: 10),
      Row(
        children: <Widget>[
          _testButton(),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _testStatus,
              key: const Key('sheet.llm.status'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: fs(
                family: F.mono,
                size: 10.5,
                wght: 500,
                color: _testOk == null
                    ? C.mist
                    : (_testOk! ? C.blue : const Color(0xFFFF8F99)),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        'Key 只存在本机；照片仅在开启校验时上行。校验失败不阻塞提交。',
        style: fs(
          family: F.cn,
          size: 10.5,
          wght: 400,
          height: 1.6,
          color: const Color(0xFF5F7190),
        ),
      ),
      const SizedBox(height: 12),
      // 组底部只读回显（docs/22 §2.0「兜底要可观测」）：
      // 读 LlmTelemetry 内存态仪表，不落盘、不可点；每次 build 现读，
      // 切档/测连接/重挂都会跟着刷新。
      // 目标拆解失败（2026-10-23）：拆解**没有兜底**，失败必须可观测。
      // 这一行就是开发者看"为什么没生成出计划"的地方。
      _setRow(
        '最近一次拆解失败',
        widget.planError == null
            ? '—'
            : '${widget.planError!.code.name}'
                  '${widget.planErrorGoal.isEmpty ? '' : ' · 「${widget.planErrorGoal}」'}',
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(
            widget.planError?.detail ?? '—',
            key: const Key('sheet.plan.lastFail'),
            maxLines: 3,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: fs(
              family: F.mono,
              size: 10.5,
              wght: 500,
              color: widget.planError != null
                  ? const Color(0xFFFF8F99)
                  : C.mist,
            ),
          ),
        ),
      ),
      _setRow(
        '最近一次 LLM 失败',
        '${LlmTelemetry.summary} · ${LlmTelemetry.kindSummary}',
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(
            LlmTelemetry.lastDetail ?? '—',
            key: const Key('sheet.llm.lastFail'),
            maxLines: 2,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: fs(
              family: F.mono,
              size: 10.5,
              wght: 500,
              color: LlmTelemetry.failures > 0
                  ? const Color(0xFFFF8F99)
                  : C.mist,
            ),
          ),
        ),
      ),
    ]);
  }

  /// 与档案/补给页 `.sec` 同款的小节头
  Widget _kicker(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 10),
      child: SizedBox(
        height: 13,
        child: Row(
          children: <Widget>[
            Text(
              text,
              style: fs(
                family: F.mono,
                size: 10,
                wght: 400,
                ls: 1.6,
                height: 1,
                color: C.mist,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 1, color: C.line2)),
          ],
        ),
      ),
    );
  }

  /// `.set .row`
  Widget _setRow(String label, String hint, Widget trailing) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: C.line2, width: 1)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: fs(family: F.cn, size: 14, wght: 400, color: C.ice),
                ),
                const SizedBox(height: 3),
                Text(
                  hint,
                  style: fs(family: F.cn, size: 11, wght: 400, color: C.mist),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing,
        ],
      ),
    );
  }

  /// `.seg` —— 分段开关（D8：可点了，段值变化经 onPick 落盘）
  Widget _seg(
    String key,
    List<List<String>> options,
    String current,
    ValueChanged<String> onPick,
  ) {
    return Container(
      padding: const EdgeInsets.all(2), // CSS 3，Border 占 1
      decoration: BoxDecoration(
        color: C.blue.withAlpha(15), // rgba(56,225,255,.06)
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.line2, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final List<String> o in options)
            GestureDetector(
              key: Key('sheet.seg.$key.${o[0]}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onPick(o[0]),
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: o[0] == current ? C.blue : null,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  o[1],
                  style: fs(
                    family: F.cn,
                    size: 12,
                    wght: o[0] == current ? 650 : 400,
                    color: o[0] == current ? C.deep : C.mist,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 「测试连接」按钮（测试中禁点）
  Widget _testButton() {
    return GestureDetector(
      key: const Key('sheet.llm.test'),
      behavior: HitTestBehavior.opaque,
      onTap: _testing ? null : _testConn,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _testing ? C.blue.withAlpha(15) : C.blue.withAlpha(26),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: C.line, width: 1),
        ),
        child: Text(
          _testing ? '测试中…' : '测试连接',
          style: fs(
            family: F.cn,
            size: 12.5,
            wght: 500,
            height: 1,
            color: _testing ? C.mist : C.ice,
          ),
        ),
      ),
    );
  }

  /// 设置组的一行「标签 + 提示 + 输入框」
  Widget _llmField(
    String label,
    String hint,
    TextEditingController c,
    String key, {
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                label,
                style: fs(family: F.cn, size: 14, wght: 400, color: C.ice),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: fs(family: F.cn, size: 10, wght: 400, color: C.mist),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            key: Key(key),
            controller: c,
            obscureText: obscure,
            style: fs(family: F.mono, size: 12.5, wght: 500, color: C.ice),
            cursorColor: C.blue,
            onChanged: (String v) => _onField(key, v),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: C.blue.withAlpha(10),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 9,
              ),
              enabledBorder: _fieldBorder(C.line2),
              focusedBorder: _fieldBorder(C.blue),
            ),
          ),
        ],
      ),
    );
  }

  OutlineInputBorder _fieldBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: color, width: 1),
  );

  @override
  Widget build(BuildContext context) {
    final _SetCat? c = _cat;

    // ── 一级 ↔ 二级的切换（宿主 2026-10-12 报「点进去中间闪一下、十分突兀」）──
    //
    // ⚠️ 病灶在 `AnimatedSwitcher` 的**默认 layoutBuilder**：它把新老两个子节点
    //    放进一个 Stack，**按最大的那个定高、并让子节点互相居中** —— Flutter
    //    源码原话 "The children are centered on each other"
    //    （`widgets/animated_switcher.dart` 的 `defaultLayoutBuilder`）。
    //    一级清单（5 行 + 品牌块）比二级面板高得多，于是**二级会被垂直居中**
    //    在那块高盒子里：先出现在中间偏下，等清单被摘掉整块塌缩，它再"跳"回顶部；
    //    这一段时间里两张脸还叠在一起。宿主看到的"中间闪过一下"就是它。
    //    （前一轮只改了水平方向 + `_toTop()`，没碰这个垂直根因，所以没治好。）
    //
    // 两处一起改：
    //   ① **顶端对齐**：二级从第一帧就落在它最终的位置上，末尾不再有塌缩跳动；
    //   ② **把两段淡入淡出错开**（Interval）：旧的先退干净、新的再上来，
    //      不再出现「新的压在旧的上」那一下叠影。总时长仍是 260ms。
    final int curDepth = c == null ? 0 : 1; // 一级 = 0，二级 = 1
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      // 旧的：到 45% 时已经退干净（Interval(.55,1) 在反向动画上作用在 t 上）
      switchOutCurve: const Interval(.55, 1, curve: kOut),
      // 新的：30% 才开始上来 → 两段只重叠约 15%（≈39ms），是"交接"不是"叠影"
      switchInCurve: const Interval(.30, 1, curve: kOut),
      layoutBuilder: (Widget? current, List<Widget> previous) => Stack(
        alignment: Alignment.topCenter,
        children: <Widget>[...previous, ?current],
      ),
      transitionBuilder: (Widget child, Animation<double> a) {
        // 有向滑动：往深处走 = 内容整体左移（新的从右边来），返回时反过来。
        // 方向 = 「这个子节点是不是当前这一层」×「现在是进还是退」。
        // ⚠️ 别再用 `a.status` 猜进出：两条分支会算成同一边（旧写法就是这样，
        //    于是新旧一起往左跑）。
        final bool isMenu = (child.key as ValueKey<String>?)?.value == 'menu';
        final bool incoming = (isMenu ? 0 : 1) == curDepth;
        final bool deeper = curDepth == 1;
        final double from =
            (incoming ? .12 : .08) * (incoming == deeper ? 1 : -1);
        return SlideTransition(
          position: Tween<Offset>(
            begin: Offset(from, 0),
            end: Offset.zero,
          ).animate(a),
          child: FadeTransition(opacity: a, child: child),
        );
      },
      child: c == null
          ? KeyedSubtree(key: const ValueKey<String>('menu'), child: _menu())
          : KeyedSubtree(key: const ValueKey<String>('pane'), child: _pane(c)),
    );
  }

  /// `.danger` —— 按住 2 秒重置（ui.js L624）

  ///
  /// **按满 2.0s**，松手以 1.0s 退回（三处按压件里退得最慢的一处）。
  /// 按满 → `Store.wipe()` + `location.reload()`；我们这里是回到绑定仪式。
  Widget _danger() {
    return HoldButton(
      duration: const Duration(seconds: 2),
      decay: const Duration(seconds: 1),
      onComplete: () => widget.onWipe?.call(),
      builder: (BuildContext context, double p) => Container(
        key: const Key('sheet.danger'),
        height: 36,
        // `.danger { position:relative; overflow:hidden }` —— 进度条被圆角裁掉
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x59FF4D5E), width: 1), // .35
        ),
        child: Stack(
          children: <Widget>[
            // `.danger i { left:0; top:0; bottom:0; width:p*100% }` —— 整高的一条
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: p,
                  heightFactor: 1,
                  child: const ColoredBox(color: Color(0x40FF4D5E)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              child: Center(
                child: Text(
                  '按住 2 秒',
                  style: fs(
                    family: F.cn,
                    size: 12.5,
                    wght: 400,
                    color: const Color(0xFFFF8F99),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 档案页内部的「档案 ↔ 回顾」切换（A6 · t21）：
/// 入口在档案段尾（_reviewEntry），回顾由 [StatsPane] 呈现。
/// 用内部状态而非 SheetKind，main.dart 的装配零改动。
class _ArchiveSwitch extends StatefulWidget {
  const _ArchiveSwitch({
    required this.host,
    required this.profileBuilder,
    this.onViewChanged,
  });

  final HostState host;

  /// 档案内容（openReview 由本组件提供：点入口切到回顾）
  final Widget Function(VoidCallback openReview) profileBuilder;

  /// 换视图时回调（档案 ↔ 回顾）：宿主拿它把面板正文的滚动偏移归零。
  /// 没有这一下，回顾视图会沿用档案页的偏移、一进来就停在底部。
  final VoidCallback? onViewChanged;

  @override
  State<_ArchiveSwitch> createState() => _ArchiveSwitchState();
}

class _ArchiveSwitchState extends State<_ArchiveSwitch> {
  bool _review = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: kOut,
      switchOutCurve: kOut.flipped,
      transitionBuilder: (Widget child, Animation<double> a) {
        final Animation<double> ease = CurvedAnimation(
          parent: a,
          curve: Curves.easeOut,
        );
        return FadeTransition(
          opacity: ease,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, .08),
              end: Offset.zero,
            ).animate(ease),
            child: child,
          ),
        );
      },
      child: _review
          ? Column(
              key: const Key('sheet.review'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // 返回条（与入口同一行语言）
                GestureDetector(
                  key: const Key('sheet.reviewBack'),
                  onTap: () {
                    setState(() => _review = false);
                    widget.onViewChanged?.call();
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: <Widget>[
                        Text(
                          '‹',
                          style: fs(
                            family: F.mono,
                            size: 14,
                            wght: 500,
                            height: 1,
                            color: C.blue,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '数据回顾',
                          style: fs(
                            family: F.hd,
                            size: 16,
                            wght: 400,
                            ls: .64,
                            height: 1,
                            color: C.ice,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '回档案',
                          style: fs(
                            family: F.cn,
                            size: 11,
                            wght: 400,
                            height: 1,
                            color: C.mist,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                StatsPane(attrs: widget.host.attrs),
              ],
            )
          : widget.profileBuilder(() {
              setState(() => _review = true);
              // 换视图 → 正文回顶部（否则沿用档案页的偏移，一进来就停在底部）
              widget.onViewChanged?.call();
            }),
    );
  }
}

enum SheetKind { archive, supply, system }

/// `#beam` —— 从她胸口打到面板上沿的两条边 + 一个渐变三角
/// 面板上沿的羽化渐变（透明 → 面板顶色）
class _FeatherPainter extends CustomPainter {
  const _FeatherPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final Rect r = Offset.zero & s;
    canvas.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0x00061228), Color(0x66061228), Color(0xCC061228)],
          stops: <double>[0, .6, 1],
        ).createShader(r),
    );
  }

  @override
  bool shouldRepaint(_FeatherPainter old) => false;
}

class SheetBeam extends StatelessWidget {
  const SheetBeam({super.key, this.visible = true});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final Size s = MediaQuery.sizeOf(context);
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 350),
          child: CustomPaint(painter: _BeamPainter(size: s)),
        ),
      ),
    );
  }
}

class _BeamPainter extends CustomPainter {
  const _BeamPainter({required this.size});

  final Size size;

  /// `Stage.toScreen(0, NY.chest + .02)` 在 panel 相机下 =
  ///   sy + (ay − chest − .02) × S，其中 sy = .34H、S = .88·H/1.95、chest = −.10737
  ///   → (.34 − .06263 × .45128)H = **.31173H**
  static double apexY(double h) => h * .31173;

  @override
  void paint(Canvas canvas, Size s) {
    final Offset apex = Offset(s.width / 2, apexY(s.height));
    final double top = s.height * .38;
    const double inset = 10;
    final Offset left = Offset(inset, top);
    final Offset right = Offset(s.width - inset, top);

    // #beamG：从 #9ff0ff@.34 到 #38e1ff@.02 的竖向渐变
    final Path tri = Path()
      ..moveTo(apex.dx, apex.dy)
      ..lineTo(right.dx, right.dy)
      ..lineTo(left.dx, left.dy)
      ..close();
    canvas.drawPath(
      tri,
      Paint()
        ..shader = ui.Gradient.linear(apex, Offset(apex.dx, top), <Color>[
          const Color(0x579FF0FF),
          const Color(0x0538E1FF),
        ]),
    );

    // #beam line：rgba(159,240,255,.55) 1px
    final Paint line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x8C9FF0FF);
    canvas.drawLine(apex, left, line);
    canvas.drawLine(apex, right, line);
  }

  @override
  bool shouldRepaint(covariant _BeamPainter o) => o.size != size;
}

/// `.sh-edge` —— 顶边一道光：中间白、两侧青，外加一层向上的辉光
class _EdgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final Rect line = Rect.fromLTWH(0, 0, s.width, 1);
    canvas.drawRect(
      line,
      Paint()
        ..shader = ui.Gradient.linear(
          line.centerLeft,
          line.centerRight,
          <Color>[
            const Color(0x0038E1FF),
            C.blue,
            Colors.white,
            C.blue,
            const Color(0x0038E1FF),
          ],
          <double>[0, .3, .5, .7, 1],
        ),
    );
    // box-shadow: 0 0 18px var(--blue)
    canvas.drawRect(
      line,
      Paint()
        ..color = C.blue
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    // ::after —— 240×60 的辉光盒子，`top:-30` 让它**以边线为中心**（上下各 30）
    final Offset c = Offset(s.width / 2, 0);
    final double r = math.min(240, 60) / 2;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(240 / 60, 1);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(c, r, <Color>[
          C.blue.withAlpha(82), // rgba(56,225,255,.32)
          C.blue.withAlpha(0),
        ]),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
