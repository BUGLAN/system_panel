import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../agent/vision.dart' show EvidenceShot;
import '../data/format.dart';
import '../data/rarity.dart';
import '../data/rewards.dart';
import '../design/tokens.dart';
import '../state/goal.dart';
import '../state/haptics.dart';
import '../state/sfx.dart';
import 'card_table.dart';
import 'game_button.dart';
import 'press_scale.dart';
import 'rail_base.dart';

/// ═══════════════════════════════════════════════════════════
///  主线页（2026-10-12 重设计）—— 竖牌扇 + 牌屉
///
///  ⚠️ **第一优先级：不许挡住她的脸。**
///  她的头 / 脸落在屏高 **20%~42%**（`StageAnchors.eyes` = 27%），
///  所以整页 UI 只允许出现在 **45%~86% 的安全带**里：
///    · 抬头（目标名 / 进度读数）在她头顶之上 —— 安全，不动
///    · 牌扇 + 刻度轨在安全带里左右滑动
///    · 详情 = 从底部升起的**牌屉**（不是居中大牌 —— 那正是原来挡脸的元凶）
///
///  手感全部走既有真源：牌扇 = [CardTable]（拖拽跟手 / 动量投影 / 档位咬合
///  `rung` + 轻震 / 落定 `seal` + 压印），本页**不自己实现任何手势**。
///
///  ── docs/39 真机走查后的施工（2026-10-17）──────────────────
///    M-01 标题 22→24 / maxLines 2 / maxWidth = W-40-56
///    M-02 读数 11→12 + 状态 chip（剩 N 天 / 已到期 / 执行中 12:04）
///    M-03 关闭 × 命中 48 + 按下 .94 + tap
///    M-10 点侧位=送位；点领位=打开牌屉（**全五态**）
///    M-15 牌屉重排成三段式单卡（头部 / 证据带 / 批注），不再有整片空板
///    M-16 证据带按五态给内容（原来是无标签、无数据、无点击的五个虚线圈）
///    M-17 抽屉内单一主 CTA；抽屉打开时页面底部两颗淡出（不再两个实心青）
///    M-18 开 420 / 关 260 / scrim 200（morph 是近似，见 [_DetailStage]）
///    M-20 底部主 CTA 语义化（去委托板 / 继续执行）+ cut-corner 14 / 高 56 / 底边 34
///    M-21 队列空：主 CTA 只留占位 + 一句「今日已清」，ghost 固定在右
///    M-22 空计划：主体 14pt + 一个 48 高的主按钮【立目标】
///
///  ── P1-C（task-3）叠加：手感与层级 ────────────────────────
///    M-05 牌扇 148×220 / stride 104 / 侧位 .84 / 最多 5 张
///    M-06 领位青色外辉 α.45 blur 22（换领位 200ms 淡入）
///    M-07 侧位摘要（±2 位只留档位 + 状态线）
///    M-08 卡面排版（档位 26 / 标题 17 / 规则行 11.5）
///    M-09 状态线五态双编码 + 执行中 12px 光包 1.6s 走（15fps ticker）
///    M-12 刻度轨可视化（轨道 / 端帽 / 窗口亮带 / 菱形头）
///    M-13 刻度轨交互分离（拖动=移领位 / 点=跳段 / 开牌屉只由点牌触发）
///    M-14 轨道「脚下」= 当前领位
///    §5.2 进页编排（0/40/120/200/320ms 的先后，≤800ms）
/// ═══════════════════════════════════════════════════════════
class MainView extends StatefulWidget {
  const MainView({
    super.key,
    required this.goal,
    this.published = const <int>{},
    this.activeIndex,
    this.selected,
    this.elapsed,
    this.canDispatch = false,
    this.visible = true,
    this.now,
    this.evidence,
    this.cta,
    this.enter,
    this.onClose,
    this.onDispatch,
    this.onResume,
    this.onNewGoal,
    this.onSelect,
    this.onAccept,
  });

  final Goal goal;

  /// 队列里已经有单的计划序号（可接）；不在里面的未完成单 = 待发布
  final Set<int> published;

  /// 正在执行的那一张（null = 没有）
  final int? activeIndex;

  /// 展开的那一张（牌屉态）
  final int? selected;

  /// 执行中那张的计时读数（`12:04`），由 main 侧每秒推进
  final String? elapsed;

  /// 队列里还有没有单（底部主 CTA 的状态机读它）
  final bool canDispatch;

  final bool visible;

  final DateTime? now;

  /// 执行中那张已经拍到的证据（docs/39 M-16）。
  ///
  /// 本轮牌屉只读**份数 + 占位**（缩略图要接存档里的相对路径 + 会话里的
  /// absPath，超出这一轮的写入面）；参数先留好，接真图时不用再改调用点。
  final List<EvidenceShot>? evidence;

  /// 底部主 CTA 的语义（docs/39 M-20）。不传就按本页信号推（见 [ctaAction]）——
  /// 与首页 Dock 那颗委托球是**同一个状态机**，以后要一处算就显式传。
  final MainCtaAction? cta;

  /// 进页编排的挂点（docs/39 M-01 / §5.2「抬头 40ms 延迟、320ms 下落 10px」）。
  ///
  /// null = 直接就位（不挂任何动画）；P1-C 的进页编排把整段的进度从这里灌进来，
  /// 抬头的位移/透明度就跟着它走。默认 null 意味着**行为与以前完全一致**。
  final Animation<double>? enter;

  final VoidCallback? onClose;
  final VoidCallback? onDispatch;

  /// 回执行面板（执行中态的主行动 = 继续执行）
  final VoidCallback? onResume;

  final VoidCallback? onNewGoal;
  final ValueChanged<int>? onSelect;
  final ValueChanged<int>? onAccept;

  // ── 安全带（屏高比例）────────────────────────────────────
  //
  // 这两个数是本页的**核心约束**，不是审美偏好：脸在 20%~42%，
  // 45% 起才允许放东西；86% 以下留给底部两颗键。
  static const double kSafeTop = .45;
  static const double kSafeBottom = .86;

  /// 刻度轨最多分几格（再长就分组 —— 单格只有几像素，靠擦洗而不是靠点准）
  static const int kScaleSlots = 40;

  /// 空计划的进页时长（docs/39 M-22「进页 240ms」）。
  static const int kEmptyInMs = 240;

  /// 轨上显示的序号：**全部 N 张**。
  ///
  /// ⚠️ 2026-10-23 真机定案（宿主裁定）：这里原先是「从第一张没做完的
  /// 往前带一张、往后最多 5 张」的窗口 —— 于是 10 张清单只挂 5 张，
  /// 宿主滑了几下数到 7 张，与「1/10 单」对不上，报成「卡片数不一致」。
  ///
  /// 当时的补丁是「加一行窗口读数」，**被宿主否掉了** —— 那是给「被裁」写说明，
  /// 而不是不裁。正解：清单有几张就挂几张，牌扇自己负责滚动/收窄间距。
  ///
  /// 牌扇本身（`CardTable._stack`）对 N 无上限：它按 `_n` 全量排序绘制，
  /// 只有这里在砍。所以「180 张铺满屏」的担心落在间距与滚动上，不靠丢牌解决。
  List<int> railIndices() {
    final int n = goal.plan.length;
    if (n == 0) return const <int>[];
    return <int>[for (int i = 0; i < n; i++) i];
  }

  /// 牌扇步距缩放：张数一多就压窄相邻间距，让**全部 N 张**都留在桌面可拖范围内。
  ///
  /// 口径：≤ [kRailComfort] 张时原样（1.0，视觉一点不变）；超了就按反比收窄，
  /// 下限 [kRailMinStrideScale]（再窄就叠成一摞、点不中）。
  /// 这是「不裁牌」的配套代价 —— 靠间距解决，不靠丢数据解决。
  static const int kRailComfort = 6;
  static const double kRailMinStrideScale = .34;

  double get railStrideScale {
    final int n = goal.plan.length;
    if (n <= kRailComfort) return 1;
    return math.max(kRailMinStrideScale, kRailComfort / n);
  }

  DutyState stateOf(int i) {
    final PlanTask t = goal.plan[i];
    if (t.state == PlanState.done) return DutyState.done;
    if (t.state == PlanState.abandoned) return DutyState.abandoned;
    if (activeIndex == i || t.state == PlanState.active) {
      return DutyState.active;
    }
    return published.contains(i) ? DutyState.open : DutyState.sealed;
  }

  TableCard cardOf(int i, {bool lead = false}) {
    final PlanTask t = goal.plan[i];
    final DutyState st = stateOf(i);
    return TableCard(
      id: 'duty.$i',
      kicker: 'MAIN · ${(i + 1).toString().padLeft(2, '0')}',
      title: t.title,
      glyph: t.attrs.isEmpty ? null : t.attrs.keys.first,
      rank: t.rank,
      accent: Rarity.of(t.rank).color,
      loot: lootOf(t),
      dutyState: st,
      dutyMeta: '${fmtMin(t.minutes)} · ${t.proof}',
      elapsed: st == DutyState.active ? elapsed : null,
      // ⑩ 证据带（docs/39 M-16）：执行中那张读真实份数，其余态本轮只给占位
      evidenceCount: st == DutyState.active ? (evidence?.length ?? 0) : 0,
      sealWord: st == DutyState.done ? '已完成' : null,
      // `enabled` 现在只回答「这单现在能不能接」（docs/39 M-10）：
      // 能不能**点开看**不再由它决定 —— 五态都开，接单只发生在牌屉的按钮上。
      enabled: st == DutyState.open,
      locked: st == DutyState.sealed,
      index: i + 1,
      note: _noteOf(st),
    );
  }

  /// ⑧ 她的批注（按五态给她的一句话 —— 不是状态文字）
  static String _noteOf(DutyState s) => switch (s) {
    DutyState.open => '接了就开计时。',
    DutyState.active => '计时中。别磨蹭。',
    DutyState.sealed => '还没派到你手上。',
    DutyState.done => '这单已经记在账上了。',
    DutyState.abandoned => '这单作废了。',
  };

  static List<String> lootOf(PlanTask t) {
    final Payout p = Rewards.payout(rank: t.rank, crit: false, dbl: false);
    return <String>[
      'EXP ${p.exp}',
      '◈ ${p.coin}',
      for (final MapEntry<String, int> e in t.attrs.entries)
        '${e.key}+${e.value}',
    ];
  }

  /// 清单全部走完（docs/39 M-23「全部完成」）。
  ///
  /// 判据与 `QuestFlow` 的收官判定同源：清单非空 + 没有「还没做完」的那张。
  /// ⚠️ 正常流程里收官会在结算当场铸下一条主线（`_applyFinale`），所以这个态
  ///    通常只在一瞬/老存档里出现 —— 但**它必须成立**：宿主走完一整条主线时
  ///    界面不能什么表示都没有（走查 §4.5 M-23：代码推算下根本没有「达成」态）。
  bool get allDone => goal.plan.isNotEmpty && goal.firstOpenIndex < 0;

  /// 底部主 CTA 的语义（docs/39 M-20 / §3.1 H-15 的**同一个状态机**）。
  ///
  /// 优先级：没有计划 → 立目标；**全部走完 → 立新目标**（M-23）；
  /// 执行中 → 继续执行；队列有单 → 去委托板；都没有 → 今日已清。
  /// 原来那颗【去执行】是**假的**：没有执行中时它其实在开派单板。
  MainCtaAction get ctaAction =>
      cta ??
      (goal.plan.isEmpty
          ? MainCtaAction.newGoal
          : allDone
          ? MainCtaAction.renew
          : activeIndex != null
          ? MainCtaAction.resume
          : (canDispatch ? MainCtaAction.dispatch : MainCtaAction.rest));

  @override
  State<MainView> createState() => _MainViewState();
}

class _MainViewState extends State<MainView> with TickerProviderStateMixin {
  // ── 数据速记（State 里少写一屏 widget.）────────────────────
  Goal get goal => widget.goal;
  Set<int> get published => widget.published;
  int? get activeIndex => widget.activeIndex;
  int? get selected => widget.selected;
  String? get elapsed => widget.elapsed;
  bool get canDispatch => widget.canDispatch;
  bool get visible => widget.visible;
  DateTime? get now => widget.now;
  List<EvidenceShot>? get evidence => widget.evidence;
  MainCtaAction? get cta => widget.cta;
  Animation<double>? get enter => widget.enter;
  VoidCallback? get onClose => widget.onClose;
  VoidCallback? get onDispatch => widget.onDispatch;
  VoidCallback? get onResume => widget.onResume;
  VoidCallback? get onNewGoal => widget.onNewGoal;
  ValueChanged<int>? get onSelect => widget.onSelect;
  ValueChanged<int>? get onAccept => widget.onAccept;
  bool get allDone => widget.allDone;

  // 安全带的两条边界（唯一真源在 [MainView]，这里只是少写几个字）
  static const double _safeTop = MainView.kSafeTop;
  static const double _safeBottom = MainView.kSafeBottom;

  // ── 牌扇状态（M-05 / M-09 / M-13 / M-14）──────────────────

  /// 当前领位（**牌扇窗口内的下标**）。它是唯一真源：CardTable 的 `lead`
  /// 受控于它，刻度轨的「脚下」也读它。点牌开屉不改它 ——
  /// 点侧位时 CardTable 自己先送位，再经 `onLeadReport` 上报回来。
  int _lead = -1;

  /// 执行中状态线光包的相位 0~1（M-09「12px 光包 1.6s 走」）。
  ///
  /// 用 **15fps** 推（docs/39 §5.5：新增动画一律 15–20fps，不要 60fps）；
  /// 只有在「确有执行中任务」时才跑，其余时候一帧都不刷。`< 0` = 不画。
  double _run = -1;
  Timer? _runTimer;

  // ── 接任务三拍（docs/41 §3.7 · 本轮唯一「一做就立刻感觉得到」的改动）──
  //
  //  真机上现在接单是**同一帧硬切**：点【接任务】→ `onAccept` → `_beginExec`
  //  → 立刻换页。牌桌上那股「捏着一张牌」的手感，在最有分量的那一下消失了。
  //
  //  改成三拍（合计 360ms）：
  //    ① 0..120ms   压印：卡缩到 .96 再弹回 1.02（`_acceptP` 驱动）
  //    ② 120..360ms 卡被抽走：向上位移 + 淡出 + 轻微放大（像被系统抽走）
  //    ③ 360ms      才真正 `onAccept()`，切到执行面板
  //
  //  ⚠️ 只作用于 `main_view` 这一处；`main.dart` 一行不用改（docs/41 §7 的
  //     落地判断）。reduced-motion 下直接落终态（跳过 ①②，立即 onAccept）。
  late final AnimationController _accept = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );

  /// 正在被抽走的那张（-1 = 没有）。它是**预案序号**（不是窗口下标）。
  int _accepting = -1;

  /// 接单编排：压印 → 抽走 → 回调。见 [_accept] 上方那段说明。
  void _takeTask(int planIndex) {
    if (_accepting >= 0) return; // 已有一次在播
    if (railReduceMotion(context)) {
      onAccept?.call(planIndex);
      return;
    }
    setState(() => _accepting = planIndex);
    // ⚠️ 用 status listener 而不是 `whenComplete`：后者走 Future 微任务，
    //    在 widget 测试里会比动画多等一帧（实测 t+400 尚未回调、t+700 才到），
    //    于是「360ms 三拍」这条断言没法钉准。listener 在动画到达 completed 的
    //    **同一次 pump** 里触发，时序与设计值一致。
    void onDone(AnimationStatus s) {
      if (s != AnimationStatus.completed) return;
      _accept.removeStatusListener(onDone);
      if (!mounted) return;
      setState(() => _accepting = -1);
      onAccept?.call(planIndex);
    }

    _accept.addStatusListener(onDone);
    _accept.forward(from: 0);
  }

  /// 这一张此刻的接单变换（只对 [_accepting] 那张生效）。
  /// 返回 `(scale, dy, opacity)`：`null` = 不作用。
  (double, double, double)? _acceptFx(int planIndex) {
    if (_accepting != planIndex) return null;
    final double t = _accept.value; // 0..1（360ms）
    if (t <= .333) {
      // ① 压印：.96 → 1.02（120ms，`t=.333` 时到峰值）
      final double p = t / .333;
      final double s = .96 + .06 * Curves.easeOut.transform(p);
      return (s, 0, 1);
    }
    // ② 被抽走：向上 -28、缩到 .9、淡出（240ms）
    final double p = (t - .333) / .667;
    final double e = Curves.easeInCubic.transform(p);
    return (1.02 - .18 * e, -34 * e, (1 - e).clamp(0.0, 1.0));
  }

  // ── 进页编排（docs/39 §5.2）──────────────────────────────

  /// 整段编排 0~1（0ms 起、760ms 到 1）。下面每一件的**延迟**都由它算。
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  );

  bool _enterStarted = false;

  @override
  void didUpdateWidget(covariant MainView old) {
    super.didUpdateWidget(old);
    _syncLead();
    _syncEnter(old);
    _syncRun();
    _syncDone(); // M-23：进/出完成态
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLead();
    if (!_enterStarted) {
      _enterStarted = true;
      if (railReduceMotion(context)) {
        _enter.value = 1; // 减弱动态：直接落终态（§5.5）
      } else if (visible) {
        _enter.forward(from: 0);
      }
    }
    _syncRun();
    _syncDone(); // M-23：首帧就落位（不补播）
  }

  @override
  void dispose() {
    _runTimer?.cancel();
    _enter.dispose();
    _doneCtl.dispose();
    // ⚠️ 漏了它会在单测里抛「disposed with an active Ticker」——
    //    接单三拍正播着的时候换页（恰恰是最常见的路径：接完就进执行面板）。
    _accept.dispose();
    super.dispose();
  }

  /// 领位与牌扇窗口的口径对不齐时复位（换计划 / 换窗口 / 首次挂上）。
  void _syncLead() {
    final List<int> idx = railIndices();
    if (idx.isEmpty) {
      _lead = -1;
    } else if (_lead < 0 || _lead >= idx.length) {
      _lead = _initialLead(idx);
    }
  }

  /// 初始领位：第一张没做完的（和旧口径一致）；全完成时停在最后一张。
  ///
  /// M-14：firstOpen **只**用来定这个初始值 —— 之后「脚下」跟着真实领位走。
  int _initialLead(List<int> idx) {
    final int open = goal.firstOpenIndex;
    if (open < 0) return idx.length - 1;
    final int at = idx.indexOf(open);
    return at < 0 ? idx.length - 1 : at;
  }

  // ── 完成态仪式（docs/39 M-23）────────────────────────────
  // 600ms 满环 + 280ms 金印落定。只在「真的有收官」时播一次，播完定格。
  late final AnimationController _doneCtl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: Motion.harvestMs + Motion.stampMs),
  );
  bool _doneOnce = false;

  /// 进页 / 变完成态时触发（reduce 直接落终态）
  void _syncDone() {
    final bool want = allDone && selected == null && visible;
    if (!want) {
      _doneOnce = false;
      _doneCtl.value = 0;
      return;
    }
    if (_doneOnce) return;
    _doneOnce = true;
    if (railReduceMotion(context)) {
      _doneCtl.value = 1;
      return;
    }
    // docs/39 M-23「600ms 满环 + seal」：满环那一拍压一声 seal（与接单/提交同档），
    // 轻震一下 —— 「兑现」是这一条主线的最后一拍，不该是静音的。
    _doneCtl.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      Sfx.play('seal');
      Haptics.buzz('seal');
    });
  }

  /// 进页编排触发：`visible` 从 false 翻到 true 时重播（§5.2「大厅 → 主线」）。
  void _syncEnter(MainView old) {
    if (old.visible == widget.visible) return;
    if (!widget.visible) return;
    if (railReduceMotion(context)) {
      _enter.value = 1;
      return;
    }
    _enter.forward(from: 0);
  }

  /// M-09：只有「执行中那张在牌扇窗口里」时才跑光包 ticker，15fps。
  void _syncRun() {
    final bool want =
        !railReduceMotion(context) &&
        activeIndex != null &&
        visible &&
        railIndices().contains(activeIndex);
    if (want == (_runTimer != null)) return;
    if (!want) {
      _runTimer?.cancel();
      _runTimer = null;
      _run = -1;
      return;
    }
    _run = 0;
    const int frameMs = 67; // ≈15fps
    const int periodMs = 1600; // M-09「1.6s 走一圈」
    _runTimer = Timer.periodic(const Duration(milliseconds: frameMs), (
      Timer _,
    ) {
      if (!mounted) return;
      setState(() => _run = (_run + frameMs / periodMs) % 1);
    });
  }

  // 纯读数据的方法都留在 [MainView] 上（单测直接 `MainView.railIndices()`），
  // 这里只做转发 —— 状态机本身不依赖任何 State 字段。
  List<int> railIndices() => widget.railIndices();
  double get railStrideScale => widget.railStrideScale;
  DutyState stateOf(int i) => widget.stateOf(i);
  TableCard cardOf(int i, {bool lead = false}) => widget.cardOf(i, lead: lead);
  MainCtaAction get ctaAction => widget.ctaAction;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          // docs/39 §5.5：减弱动态时进/出页退化成 **120–160ms 交叉淡化**
          // （原来 400ms；reduce 下不要"整页慢慢浮"，只要状态切换被看见）。
          duration: Duration(
            milliseconds: railReduceMotion(context) ? Motion.respondMs : 400,
          ),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              final double top = box.maxHeight * _safeTop;
              final double band = box.maxHeight * (_safeBottom - _safeTop);
              final double w = box.maxWidth;
              final bool detail =
                  selected != null && goal.taskAt(selected!) != null;
              final bool empty = goal.plan.isEmpty;
              return Stack(
                children: <Widget>[
                  // §5.2「40ms 抬头下落 10px / 320ms」——外层编排通过 `enter`
                  // 传进来的进度优先；没传就由本页自己的 `_enter` 兜（同一段时间表）。
                  _top(w, enter ?? _enter),
                  if (empty)
                    _empty(top)
                  else if (allDone && selected == null)
                    // docs/39 M-23：全部走完 → 完成态仪式（满环 + 金色压印「兑现」）
                    _done(top, band)
                  else if (detail)
                    _drawer(selected!, top, band, w - 32)
                  else
                    _fan(top, band),
                  // M-17：抽屉打开时页面底部两颗**淡出**（不是移除 ——
                  // AnimatedOpacity + IgnorePointer，否则看不见的按钮还在挨点）。
                  _low(hide: detail || empty),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// 抬头：目标一句 + 期限内进度（在她头顶之上，安全区，形态不动）
  ///
  /// [drive] = 进页编排的进度（§5.2「40ms 延迟、320ms 下落 10px」）。
  Widget _top(double w, Animation<double> drive) {
    final DateTime t0 = now ?? DateTime.now();
    // M-01：标题的可用宽度 = 屏宽 - 左右 20 - 右侧关闭区 56
    final double titleMax = math.max(120, w - 40 - 56);
    final Widget content = Row(
      key: const Key('main.top'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                height: 19.2,
                child: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    'MAINLINE · 主线',
                    key: const Key('main.kicker'),
                    style: fs(
                      family: F.mono,
                      size: 10,
                      wght: 400,
                      ls: 1.6,
                      color: C.blue,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: titleMax),
                child: Text(
                  goal.text,
                  key: const Key('main.title'),
                  // M-01：22 → 24（ShuHei 只有 Bold 一档，wght 写 700 与 400
                  //     渲染结果一样，但语义上是标题 —— 按 Bold 设计）。
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: fs(
                    family: F.hd,
                    size: 24,
                    wght: 700,
                    ls: .44,
                    height: 1.25,
                    color: C.ice,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _readout(t0),
            ],
          ),
        ),
        // M-01 的账号：间距 8 + 关闭区 48 = 56 —— 与「maxWidth = W-40-56」同一口径
        const SizedBox(width: 8),
        _closeButton(),
      ],
    );
    // §5.2「40ms 延迟、320ms 下落 10px」：延迟由 `drive` 的总时长算 ——
    // 外层灌进来时按它自己的 760ms 计，否则按本页 `_enter`（同样 760ms）。
    // 只对**这一小块抬头**做 Opacity（不是整屏、不是玻璃卡，不碰 §5.5 红线）。
    return Positioned(
      left: 20,
      right: 20,
      top: 22,
      child: AnimatedBuilder(
        animation: drive,
        child: content,
        builder: (BuildContext _, Widget? child) {
          final double t = kOut.transform(
            ((drive.value - 40 / 760) / (320 / 760)).clamp(0.0, 1.0),
          );
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, 10 * (1 - t)),
              child: child,
            ),
          );
        },
      ),
    );
  }

  /// 关闭 ×（docs/39 M-03）：视觉 44 / 命中 48（每边透明外扩 2）、按下 .94 + tap。
  ///
  /// ⚠️ 命中要做大只能**外层就大**：`RenderBox.hitTest` 只认自己的 size，
  ///    OverflowBox 溢出父边界的那一圈收不到点击（踩过）。
  ///    所以这里是 48 的外框、44 的视觉圆 —— 多出来的 2px 每边纯透明。
  ///    命名与位置都不动（top 22 / right 20）。
  Widget _closeButton() {
    // docs/39 §5.6：纯图标按钮补 Semantics 标签（屏读只念「按钮」是走查点名的坑）
    return Semantics(
      button: true,
      label: '关闭主线',
      child: SizedBox(
        width: 48,
        height: 48,
        child: PressScale(
          scale: .94,
          onTap: onClose == null
              ? null
              : () {
                  Sfx.play('tap');
                  onClose!();
                },
          behavior: HitTestBehavior.translucent,
          child: Center(
            child: Container(
              key: const Key('main.close'),
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x99040E20),
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
        ),
      ),
    );
  }

  /// M-02：读数行 11 → 12pt，拆成「天数读数 + 状态 chip」。
  ///
  /// chip 只回答**期限 / 执行**这一件事，不表达进度带的状态 ——
  /// docs/17 那条「禁止状态文字」管的是环与刻度轨，chip 是她给的一句读数。
  Widget _readout(DateTime t0) {
    // 读数口径：`已过 N/M 天 · 完成 X 单`（docs/33 §7.5）
    final String text = goal.days <= 0
        ? '完成 ${goal.doneCount} 单'
        : goal.progressText(t0);
    final Widget? chip = _statusChip(t0);
    return Row(
      children: <Widget>[
        Flexible(
          child: Text(
            text,
            key: const Key('main.progress'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: fs(
              family: F.mono,
              size: 12,
              wght: 600,
              ls: 1.1,
              color: C.mist,
            ),
          ),
        ),
        if (chip != null) ...<Widget>[
          const SizedBox(width: 8),
          // 状态切换 160ms（M-02）
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: chip,
          ),
        ],
      ],
    );
  }

  Widget? _statusChip(DateTime t0) {
    // M-23：全部走完 = 目标状态写进抬头 chip（与「剩 N 天 / 已到期」同一套）。
    // 金线 = 完成（与牌面已完成状态线同色），文案与压印呼应。
    if (allDone) return _chip('已兑现', C.rB, keyName: 'main.chip.done');
    if (activeIndex != null && elapsed != null) {
      return _chip('执行中 $elapsed', C.blue, keyName: 'main.chip.active');
    }
    if (goal.days <= 0) return null;
    final int left = goal.remainingDays(t0);
    if (left <= 0) return _chip('已到期', C.rS, keyName: 'main.chip.due');
    return _chip('剩 $left 天', C.mist, keyName: 'main.chip.left');
  }

  /// 状态 chip：线框 + 极淡底（到期用 C.rS 的线，M-02）
  Widget _chip(String label, Color color, {required String keyName}) {
    return Container(
      key: Key(keyName),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withAlpha(150)),
        color: color.withAlpha(18),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: fs(
          family: F.mono,
          size: 10.5,
          wght: 600,
          ls: .6,
          height: 1.1,
          color: color,
        ),
      ),
    );
  }

  /// 牌扇 + **竖向刻度轨** —— 全部落在安全带（45%~86%）里
  ///
  /// 这一层也承担 §5.2 的「牌扇逐张发出 / 刻度轨 scaleY 长出来」：
  /// 编排只**动这一块**的 transform，不碰 CardTable 的公共入场
  /// （`kEnterMs` 是补给/称号/证据/换目标共用的，改常量会波及那四处）。
  Widget _fan(double top, double band) {
    final List<int> idx = railIndices();
    if (idx.isEmpty) return const SizedBox.shrink();
    if (_lead < 0 || _lead >= idx.length) _lead = _initialLead(idx);
    return AnimatedBuilder(
      animation: _enter,
      builder: (BuildContext context, Widget? _) {
        // §5.2 时间表（整段 760ms）：120ms 牌扇起（200ms 走完）、
        // 200ms 刻度轨 scaleY（260ms 走完）
        final double fanT = _phase(120, 200);
        final double scaleT = _phase(200, 260);
        return Stack(
          children: <Widget>[
            Positioned(
              left: 0,
              right: 0,
              top: top,
              height: band,
              // §5.2「牌扇逐张发出：初始 scale .94 / 外倾 ∓4°」——
              // 逐张由 CardTable 自己的入场做（它已经错峰 26ms）；这一层只给
              // 整块补一个 8px 的落下 + 轻微缩放，让「发牌」在页级也能看见。
              child: Transform.translate(
                offset: Offset(0, 8 * (1 - fanT)),
                child: Transform.scale(
                  scale: .94 + .06 * fanT,
                  child: CardTable(
                    key: const Key('main.rail'),
                    cards: <TableCard>[for (final int i in idx) cardOf(i)],
                    skin: CardSkin.duty,
                    size: CardTableSize.m,
                    // 全部 N 张都在桌上 —— 张数多时压窄间距（见 railStrideScale）
                    strideScale: railStrideScale,
                    initialLead: _lead,
                    tapLeadAlways: true,
                    // M-13/M-14：受控领位 —— 刻度轨拖动/轻点改 `_lead` 就跟着走
                    lead: _lead,
                    onLeadReport: (int k) {
                      if (k == _lead) return;
                      setState(() => _lead = k);
                    },
                    run: _run,
                    onPick: (int k) => onSelect?.call(idx[k]),
                  ),
                ),
              ),
            ),
            // 竖向刻度轨：贴左边缘，与牌扇同高
            Positioned(
              left: 0,
              top: top,
              height: band,
              width: _MissionScrubber.hitWidth,
              child: Transform.scale(
                alignment: Alignment.centerLeft,
                scaleY: scaleT,
                child: _MissionScrubber(
                  key: const Key('main.scale'),
                  total: goal.plan.length,
                  leadIndex: idx[math.min(_lead, idx.length - 1)],
                  passedCount: goal.doneCount,
                  // M-13：拖动/轻点**只换领位**，开牌屉只由点牌触发
                  onScrub: (int planIndex) {
                    final int at = idx.indexOf(planIndex);
                    if (at >= 0 && at != _lead) setState(() => _lead = at);
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// §5.2 的相位：`delayMs` 起、`durMs` 走完，返回 0~1（kOut 收口）。
  double _phase(int delayMs, int durMs) {
    const int total = 760; // `_enter` 的总时长；两边改要一起改
    final double t = (_enter.value * total - delayMs) / durMs;
    return kOut.transform(t.clamp(0.0, 1.0));
  }

  /// 详情 = 从底部升起的牌屉（docs/39 §4.4）
  ///
  /// 三段式**单卡**（M-15）：头部 / 证据带 / 批注都在卡里，卡外只剩动作区。
  /// 卡高约 250（390 屏安全带 346 够放；屏更矮时按安全带收缩，绝不越过 45%）。
  Widget _drawer(int i, double top, double band, double width) {
    final DutyState st = stateOf(i);
    const double gap = 12;
    const double actionH = 48;
    final double cardH = math.max(120, math.min(250, band - gap - actionH));
    final Widget stage = _DetailStage(
      key: const Key('main.detail'),
      top: top,
      band: band,
      onClose: () => onSelect?.call(-1),
      card: SizedBox(
        height: cardH,
        child: CardFace(
          skin: CardSkin.duty,
          card: cardOf(i, lead: true),
          size: CardTableSize.l,
          lead: true,
          dims: Dims(width, cardH),
        ),
      ),
      actions: (VoidCallback close) => _actionRow(i, st, close),
    );
    // docs/41 §3.7：接任务三拍（压印 .96→1.02 → 被抽走 ↑34/缩.9/淡出）。
    //
    // ⚠️ 变换必须交给 [_DetailStage] **在它内部**应用：它的顶层是 `Positioned`
    //    （ParentDataWidget），在外面包 Transform/Opacity 会直接抛
    //    「Incorrect use of ParentDataWidget」—— 仓库 2026-10-11 踩过一次，
    //    lobby_test 第一条用例就是防它的。
    //    没在接单时 `fx` 为 null；[_DetailStage] 内部即**零变换**，
    //    默认路径的渲染与不做这件事时逐像素一致。
    if (_accepting != i) return stage;
    return _DetailStage(
      key: const Key('main.detail'),
      top: top,
      band: band,
      onClose: () => onSelect?.call(-1),
      acceptFx: _accept,
      acceptFxOf: () => _acceptFx(i),
      card: SizedBox(
        height: cardH,
        child: CardFace(
          skin: CardSkin.duty,
          card: cardOf(i, lead: true),
          size: CardTableSize.l,
          lead: true,
          dims: Dims(width, cardH),
        ),
      ),
      actions: (VoidCallback close) => _actionRow(i, st, close),
    );
  }

  /// 牌屉动作区（M-17）：单一主 CTA（124×48 切角 12）+【收起】48×48 ghost。
  ///
  /// 状态动作：可接=接任务 / 执行中=继续执行 / 待发布=现在派给我 /
  ///           已完成·已放弃=只读（只剩收起）。
  Widget _actionRow(int i, DutyState st, VoidCallback close) {
    final Widget? cta = _drawerCta(i, st);
    return Row(
      key: const Key('main.actions'),
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        if (cta != null) ...<Widget>[cta, const SizedBox(width: 8)],
        _collapse(close),
      ],
    );
  }

  Widget? _drawerCta(int i, DutyState st) {
    final String label = switch (st) {
      DutyState.open => '接任务',
      DutyState.active => '继续执行',
      DutyState.sealed => '现在派给我',
      _ => '',
    };
    final String keyName = switch (st) {
      DutyState.open => 'main.take',
      DutyState.active => 'main.resume',
      DutyState.sealed => 'main.publish',
      _ => 'main.none',
    };
    final VoidCallback? fire = switch (st) {
      DutyState.open || DutyState.sealed =>
        onAccept == null
            ? null
            : () {
                // 接单才 seal（docs/39 §5.4：看详情是 tap，接单才是 seal）
                Sfx.play('seal');
                Haptics.buzz('seal');
                // docs/41 §3.7 三拍：压印 120 → 抽走 240 → 才切页（共 360ms）
                _takeTask(i);
              },
      DutyState.active => onResume,
      _ => null,
    };
    if (label.isEmpty) return null;
    return PressScale(
      onTap: fire == null
          ? null
          : () {
              if (st == DutyState.active) Sfx.play('tap');
              fire();
            },
      child: Container(
        key: Key(keyName),
        width: 124,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: C.blue,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(color: C.blue.withAlpha(110), blurRadius: 24),
          ],
        ),
        child: Text(
          label,
          style: fs(
            family: F.cn,
            size: 15,
            wght: 700,
            ls: .9,
            height: 1,
            color: C.deep,
          ),
        ),
      ),
    );
  }

  /// 收起牌屉（48×48 ghost，M-17）。关 260ms 反向（[_DetailStage]）。
  Widget _collapse(VoidCallback close) {
    return PressScale(
      onTap: onSelect == null
          ? null
          : () {
              Sfx.play('tap');
              close();
            },
      child: Container(
        key: const Key('main.back'),
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xB3040E20),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
          border: Border.all(color: C.line),
        ),
        child: Text(
          '收起',
          style: fs(family: F.cn, size: 12, wght: 600, height: 1, color: C.ice),
        ),
      ),
    );
  }

  /// 空计划（M-22 / 2026-10-17 收口）
  ///
  /// 走查的原始描述是「只有一行 13pt」+ 按钮仍叫「换目标」+ 依赖右下角。
  /// 现在整块是**本页的主 CTA 区**：
  ///  · 主体 **14pt**（原来 13，「立目标」这件事是这一屏唯一的内容）；
  ///  · 主按钮 **48 高**、文案 **【立目标】**（P0-B 已改文案，本轮钉住尺寸与层级）；
  ///  · **不再依赖右下角**：空态里 [_low] 整排收掉，按钮只在这里；
  ///  · 进页 **240ms**（M-22）—— 淡 + 8px 上浮；reduce 直接落终态。
  Widget _empty(double top) {
    return Positioned(
      left: 20,
      right: 20,
      top: top,
      child: AnimatedBuilder(
        animation: _enter,
        builder: (BuildContext _, Widget? child) {
          final bool reduce = railReduceMotion(context);
          // 复用进页编排的时间基（760ms 总长）：空态在自己的 240ms 窗口里走完。
          final double at = reduce
              ? 1
              : ((_enter.value * 760) / MainView.kEmptyInMs).clamp(0.0, 1.0);
          final double k = kOut.transform(at);
          return Opacity(
            opacity: k,
            child: Transform.translate(
              offset: Offset(0, 8 * (1 - k)),
              child: child,
            ),
          );
        },
        child: Column(
          key: const Key('main.emptyBody'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '还没有计划。说一句你想变成什么样。',
              key: const Key('main.empty'),
              style: fs(
                family: F.cn,
                size: 14,
                wght: 400,
                height: 1.6,
                color: C.mist,
              ),
            ),
            const SizedBox(height: 16),
            // 主 CTA（48 高 / 斜切 / 全宽）：空态里它就是这一屏唯一的动作
            SizedBox(
              width: double.infinity,
              child: PressScale(
                onTap: onNewGoal == null
                    ? null
                    : () {
                        Sfx.play('tap');
                        onNewGoal!();
                      },
                child: Container(
                  key: const Key('main.emptyGoal'),
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: C.blue,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(color: C.blue.withAlpha(110), blurRadius: 24),
                    ],
                  ),
                  child: Text(
                    '立目标',
                    style: fs(
                      family: F.cn,
                      size: 15,
                      wght: 700,
                      ls: .9,
                      height: 1,
                      color: C.deep,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 全部走完（docs/39 M-23）—— **本页唯一的「目标达成」仪式**。
  ///
  /// 骨架照方案表：**进度带满环 + 金色压印「兑现」+ 她一句 + 【立新目标】**。
  ///  · 满环：主线页没有进度带（H-10 把它藏了 —— 牌扇与她的脸都在那块），
  ///    所以这里用一条**页内的环**表达「满」：暗轨常驻 + 亮弧按 [finale]
  ///    从 0 长到整圈（600ms，`Motion.harvestMs`，与进度收割同一个节拍）。
  ///  · 压印：600ms 走满之后金印（C.rB）落定，`seal` 一声（在 main 侧那一拍）。
  ///  · 她一句：走查要求有一句，这里写在本页的一行读数里（字幕层在 main 侧）
  ///  · 【立新目标】：主 CTA 在 M-23 态换成 `MainCtaAction.renew`。
  ///
  /// ⚠️ 减弱动态：满环直接落 1、压印直接落终态（§5.5「reduce 落终态」）。
  Widget _done(double top, double band) {
    final double h = math.min(band * .62, 240);
    return Positioned(
      left: 20,
      right: 20,
      top: top,
      height: h,
      child: AnimatedBuilder(
        // 仪式进度：本页自持（600ms 满环 + 280ms 压印 = 880ms 总长）。
        // M-23 的「600ms 满环 + seal」是一次性演出，没有 main 侧的驱动依赖 ——
        // 页面一进完成态就播（_doneOnce），播完定格。
        animation: _doneCtl,
        builder: (BuildContext context, Widget? _) {
          final bool reduce = railReduceMotion(context);
          final double raw = _doneCtl.value;
          // 600ms 满环（harvestMs）+ 之后 280ms 压印（stampMs）
          final double ringT = reduce
              ? 1
              : kOut.transform((raw / .68).clamp(0.0, 1.0));
          final double sealT = reduce
              ? 1
              : kOut.transform(((raw - .68) / .32).clamp(0.0, 1.0));
          final double d = math.min(h * .52, 150);
          return Stack(
            alignment: Alignment.topCenter,
            children: <Widget>[
              // 满环（自绘，不建 saveLayer）
              Positioned(
                top: 0,
                child: SizedBox(
                  width: d,
                  height: d,
                  child: CustomPaint(
                    key: const Key('main.doneRing'),
                    painter: _DoneRingPainter(t: ringT, full: ringT >= .999),
                  ),
                ),
              ),
              // 金色压印「兑现」：600ms 后落定
              Positioned(
                top: d * .5 - 18,
                child: Opacity(
                  opacity: sealT,
                  child: Transform.scale(
                    scale: reduce ? 1 : 1 + .12 * (1 - sealT),
                    child: Container(
                      key: const Key('main.doneSeal'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: C.rB, width: 1.5),
                        borderRadius: BorderRadius.circular(3),
                        color: C.rB.withAlpha(28),
                        boxShadow: <BoxShadow>[
                          BoxShadow(color: C.rB.withAlpha(90), blurRadius: 18),
                        ],
                      ),
                      child: Text(
                        '兑现',
                        style: fs(
                          family: F.cn,
                          size: 20,
                          wght: 700,
                          ls: 4,
                          height: 1.1,
                          color: C.rB,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 她一句
              Positioned(
                top: d + 14,
                left: 0,
                right: 0,
                child: Text(
                  '清单走完了。这条线，兑现了。',
                  key: const Key('main.doneLine'),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: fs(
                    family: F.cn,
                    size: 14,
                    wght: 400,
                    height: 1.6,
                    color: C.ice,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 底排：拇指区（M-20 / M-21）
  ///
  /// · 主 CTA：cut-corner 14 / 高 56 / 底边 34；文案随状态（去委托板 / 继续执行）
  /// · 队列空：主 CTA 只留占位 + 一句「今日已清」，ghost 固定在右（不再左跳）
  /// · 抽屉打开 / 空计划：整排淡出（200ms，M-17）
  Widget _low({required bool hide}) {
    final MainCtaAction a = ctaAction;
    return Positioned(
      left: 20,
      right: 20,
      bottom: 34,
      child: AnimatedOpacity(
        key: const Key('main.lowFade'),
        opacity: hide ? 0 : 1,
        duration: const Duration(milliseconds: Motion.scrimMs),
        child: IgnorePointer(
          ignoring: hide,
          // §5.2「320ms 底部两键上浮 16px / 240ms」。
          // ⚠️ 必须在 AnimatedBuilder 里读 `_enter`：直接调用 `_phase` 只会拿到
          //    构建那一刻的值，编排永远停在 0（实机踩过）。
          child: AnimatedBuilder(
            animation: _enter,
            child: Row(
              key: const Key('main.low'),
              children: <Widget>[
                // M-21：主 CTA 的位置**永远在**（占位），所以 ghost 不会在
                // 空态里从右端跳到左端、也不会在队列清空那一拍闪一下。
                Expanded(
                  child: a == MainCtaAction.rest
                      ? const SizedBox(
                          height: 56,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '今日已清',
                              key: Key('main.cleared'),
                              style: TextStyle(
                                fontFamily: F.mono,
                                fontSize: 11.5,
                                height: 1.2,
                                letterSpacing: 1.2,
                                color: C.dim,
                              ),
                            ),
                          ),
                        )
                      : _mainButton(a),
                ),
                const SizedBox(width: 10),
                _ghostButton(),
              ],
            ),
            builder: (BuildContext _, Widget? child) {
              final double up = _phase(320, 240);
              return Transform.translate(
                offset: Offset(0, 16 * (1 - up)),
                child: child,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _mainButton(MainCtaAction a) {
    final String label = mainCtaLabel(a);
    final VoidCallback? fire = switch (a) {
      MainCtaAction.dispatch => onDispatch,
      MainCtaAction.resume => onResume,
      // M-23：走完了 → 立新目标（与空计划同一颗按钮，同一条回调）
      MainCtaAction.newGoal || MainCtaAction.renew => onNewGoal,
      MainCtaAction.rest => null,
    };
    // docs/48 §4：主 CTA = 一颗有厚度的实体键（GameButton）。
    // key / 高 56 / 斜切语言（M-20）不变；按下下沉 + 轻震、抬起弹回、落定出声。
    return GameButton(
      key: const Key('main.dispatch'),
      label: label,
      height: 56,
      // 全部走完后立新目标是「兑现」那一拍的收尾：seal + 震（docs/39 §5.4）
      cue: a == MainCtaAction.renew ? 'reward.seal' : 'ui.tap',
      accent: a == MainCtaAction.renew ? Pal.gold : C.blue,
      onTap: fire == null
          ? null
          : () {
              if (a == MainCtaAction.renew) Haptics.buzz('seal');
              fire();
            },
    );
  }

  Widget _ghostButton() {
    return GameButton(
      key: const Key('main.newGoal'),
      label: '换目标',
      primary: false,
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 19),
      onTap: onNewGoal,
    );
  }
}

/// 完成态的「满环」（docs/39 M-23）。
///
/// 与 [ProgressBand] 是**同一个语义**（整圈 = 兑现），但画在主线页页内：
/// 主线的全景进度带被 H-10 藏了（那块是她的脸与牌扇），完成态需要一个"看得见
/// 走满"的东西。三条同半径描边叠加照搬进度带的辉光语汇（宽 / 中 / 芯），
/// 只多了"从 0 长到整圈"的进度参数。
class _DoneRingPainter extends CustomPainter {
  const _DoneRingPainter({required this.t, required this.full});

  /// 0~1：亮弧长到哪
  final double t;

  /// 走满（亮弧闭合成整圈 → 提亮成冰色）
  final bool full;

  static const int _blue = 0x38E1FF;
  static const int _ice = 0xE9FBFF;

  @override
  void paint(Canvas canvas, Size s) {
    final Offset c = Offset(s.width / 2, s.height / 2);
    final double r = s.width / 2 - 3;
    final double w = s.width / 42; // 与进度带同一档线宽比例（1/S 的近似）

    // ① 暗轨：整圈细虚线（走满之后就收掉，亮弧接管）
    if (!full) {
      final Paint dash = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, w * .7)
        ..color = Color(0x5938E1FF);
      const int segs = 48;
      for (int i = 0; i < segs; i++) {
        final double a = i * 2 * math.pi / segs;
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r),
          a,
          2 * math.pi / segs * .42,
          false,
          dash,
        );
      }
    }

    // ② 亮弧：从 12 点起顺时针长 t 圈
    if (t <= 0) return;
    final double sweep = 2 * math.pi * t.clamp(0.0, 1.0);
    final int col = full ? _ice : _blue;
    void arc(double width, double alpha, bool plus) {
      final Paint p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(.6, width)
        ..color = _hexa(col, alpha);
      if (plus) p.blendMode = BlendMode.plus;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        sweep,
        false,
        p,
      );
    }

    arc(w * 4.2, .07, true);
    arc(w * 2, .16, true);
    arc(w * .9, full ? .95 : .9, true);
  }

  static Color _hexa(int rgb, double a) =>
      Color(((a.clamp(0, 1) * 255).round() << 24) | (rgb & 0xFFFFFF));

  @override
  bool shouldRepaint(covariant _DoneRingPainter o) =>
      o.t != t || o.full != full;
}

/// 主线「主行动」的语义（docs/39 M-20 与 §3.1 H-15 的**同一个状态机**）。
///
/// ⚠️ 与首页 Dock 那颗委托球共用同一套语义：
///   无执行中 = 去委托板（接单只发生在牌屉里）；执行中 = 继续执行；
///   队列空 = 今日已清（不动作，她说一句）；没有计划 = 立目标。
enum MainCtaAction { dispatch, resume, rest, newGoal, renew }

/// 底部主 CTA 的文案（docs/39 M-20）。牌屉里的动作键另有自己的文案（M-17）。
String mainCtaLabel(MainCtaAction a) => switch (a) {
  MainCtaAction.dispatch => '去委托板',
  MainCtaAction.resume => '继续执行',
  MainCtaAction.rest => '今日已清',
  MainCtaAction.newGoal => '立目标',
  MainCtaAction.renew => '立新目标',
};

/// 牌屉的入场 / 退场（docs/39 M-18）。
///
/// 开 420ms / 关 260ms / scrim 200ms，三条数值都是真源。

/// 牌屉（docs/39 M-18）—— 从安全带下沿升起，带一层舞台压暗（α .22 / 200ms）。
///
/// 为什么不是「卡片自己淡入」：抽屉是**换景**，需要一个前后景关系；
/// scrim 让她的脸保持亮、把安全带以下压下去，牌屉才像「被抽出来的一张」。
/// ⚠️ 不对整张玻璃卡做 Opacity（saveLayer）：透明度只作用在 scrim 与位移上。
class _DetailStage extends StatefulWidget {
  const _DetailStage({
    super.key,
    required this.top,
    required this.band,
    required this.card,
    required this.actions,
    this.onClose,
    this.acceptFx,
    this.acceptFxOf,
  });

  /// 安全带顶（45% 屏高）
  final double top;

  /// 安全带高
  final double band;

  /// 三段式单卡（头部 / 证据带 / 批注）
  final Widget card;

  /// 动作区（由父级按五态给：接任务 / 继续执行 / 现在派给我 / 只留收起）
  final Widget Function(VoidCallback close) actions;

  /// 下拉关闭（M-19，手势）与 scrim 点击都走它
  final VoidCallback? onClose;

  /// **接单三拍**的变换（docs/41 §3.7）：给一个动画 + 取值器，
  /// 本组件在**内部**把它应用到内容 Column 上。
  ///
  /// 为什么不从外面包：本组件顶层是 `Positioned`（ParentDataWidget），
  /// 外面套 Transform/Opacity 会抛 `Incorrect use of ParentDataWidget`。
  /// null = 没在接单 → 零变换（默认路径逐像素不变）。
  final Animation<double>? acceptFx;
  final (double, double, double)? Function()? acceptFxOf;

  @override
  State<_DetailStage> createState() => _DetailStageState();
}

class _DetailStageState extends State<_DetailStage>
    with TickerProviderStateMixin {
  /// 开 420ms（过冲 ≤1.06）/ 关 260ms（§5.1「退场 = 进场的 60%」≈252，取 260）
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: Motion.drawerOpenMs),
  );

  // ⚠️ M-19（下拉关闭）本轮**未做**：牌屉目前只能靠【收起】/×/返回键关。
  //    真机走查没覆盖这个手势（docs/39 §7 风险表），而它需要跟手弹簧 +
  //    与 BoxConstraints 的联动，不是这一批（收尾）该顺手加的东西 ——
  //    留作下一轮，别在这里埋半截实现。

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ⚠️ 不能放 initState：`railReduceMotion` 读 MediaQuery（InheritedWidget），
    //    initState 里 dependOnInheritedWidgetOfExactType 会直接断言失败。
    if (_started) return;
    _started = true;
    if (railReduceMotion(context)) {
      _open.value = 1;
    } else {
      _open.forward();
      // docs/41 §3.5：开牌屉 = 「翻开一张牌」，给一声 flip（0.10s / −27.5dBFS）
      // + 一次很轻的震动。原来这里只有视觉，没有「翻开」的触觉。
      Sfx.play('flip');
      Haptics.buzz('flip');
    }
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  void _close() {
    if (widget.onClose == null) return;
    if (railReduceMotion(context)) {
      widget.onClose!();
      return;
    }
    _open.duration = const Duration(milliseconds: Motion.drawerCloseMs);
    _open.reverse().whenComplete(() {
      if (mounted) widget.onClose!();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool reduce = railReduceMotion(context);
    return Positioned(
      left: 16,
      right: 16,
      top: widget.top,
      height: widget.band,
      child: AnimatedBuilder(
        animation: _open,
        builder: (BuildContext _, Widget? _) {
          // 过冲 1.06 再回弹（§5.1「过冲 ≤1.08」）
          final double t = reduce
              ? _open.value
              : Curves.easeOutBack.transform(_open.value);
          // docs/41 §3.5「翻开一张牌」：除了升起，还要有一点**掀起的旋转**。
          // 1.6° → 0（随 `_open` 收口，末帧严格为 0；reduce 下不转）。
          // 为什么是 1.6° 而不是 5°：牌屉是「从袖口抽出来摊在桌上」，
          // 不是「牌被甩到空中」—— 角度大了会像贴纸歪了。
          final double flutterRot = reduce
              ? 0
              : (1 - Curves.easeOutCubic.transform(_open.value)) *
                    1.6 *
                    math.pi /
                    180;
          Widget body = Column(
            children: <Widget>[
              Expanded(child: widget.card),
              const SizedBox(height: 12),
              SizedBox(height: 48, child: widget.actions(_close)),
            ],
          );
          // docs/41 §3.7 接单三拍：变换在这里应用（本组件顶层是 Positioned，
          // 外面包 Transform/Opacity 会抛 ParentDataWidget 冲突）。
          final (double, double, double)? fx = widget.acceptFxOf?.call();
          if (fx != null && widget.acceptFx != null && !reduce) {
            body = AnimatedBuilder(
              animation: widget.acceptFx!,
              builder: (BuildContext _, Widget? child) {
                final (double, double, double)? f = widget.acceptFxOf?.call();
                if (f == null) return child!;
                return Transform.translate(
                  offset: Offset(0, f.$2),
                  child: Transform.scale(
                    scale: f.$1,
                    child: Opacity(opacity: f.$3, child: child),
                  ),
                );
              },
              child: body,
            );
          }
          // 位移（升起）+ 掀起旋转（flutterRot 末帧严格为 0）
          return Transform.translate(
            offset: Offset(0, (1 - t) * 44),
            child: Transform.rotate(angle: flutterRot, child: body),
          );
        },
      ),
    );
  }
}

/// 任务刻度轨（**竖向**，贴屏幕左边缘）—— docs/39 M-12 / M-13。
///
/// 真机上原来只有一根 3~6px 的小青刻度：没有轨道、没有读数，也不知道能拖。
/// 现在：轨道 x=10 宽 1px α.18 + 上下端帽 6px + 当前窗口 3px 亮带 + 脚下菱形头 7px。
///
/// ⚠️ 交互纪律（M-13）：**拖动 = 移动牌扇领位；点 = 跳到那一段并移动领位**。
///   **打开牌屉只由点牌触发** —— 原来 `onTapDown` 立即 onJump 开屉，
///   拖拽分支永远不可达（走查 §4.3「擦洗说明名存实亡」）。
class _MissionScrubber extends StatefulWidget {
  const _MissionScrubber({
    super.key,
    required this.total,
    required this.leadIndex,
    required this.passedCount,
    required this.onScrub,
  });

  /// 通栏命中区宽度（视觉刻度只占左边 ~4..22px，剩下是手指余量）
  static const double hitWidth = 40;

  /// 最多分几格（再长就分组 —— 单格只有几像素）
  static const int kSlots = 40;

  /// 清单总条数
  final int total;

  /// 当前领位（计划序号）—— M-14：轨道「脚下」= 领位，不是 firstOpen
  final int leadIndex;

  /// 已完成多少单（按 doneCount 着色）
  final int passedCount;

  /// 擦洗到某个**计划序号**（只换领位，不开牌屉）
  final ValueChanged<int> onScrub;

  @override
  State<_MissionScrubber> createState() => _MissionScrubberState();
}

class _MissionScrubberState extends State<_MissionScrubber> {
  /// 拖拽中落在哪一格（null = 没在拖）
  int? _dragSlot;

  /// 最后一次擦洗之后多久淡出读数 chip（M-13：松手 400ms 后淡出）
  Timer? _chipTimer;
  bool _chipOn = false;

  int get _slots =>
      math.min(math.max(widget.total, 1), _MissionScrubber.kSlots);

  int get _per => _slots <= 0 ? 1 : (widget.total / _slots).ceil();

  int get _leadSlot {
    if (_slots <= 0) return 0;
    if (widget.leadIndex < 0) return _slots - 1;
    return (widget.leadIndex ~/ _per).clamp(0, _slots - 1);
  }

  /// 这一格覆盖的第一个计划序号
  int _indexOf(int slot) => math.min(widget.total - 1, slot * _per);

  int _slotAt(double dy, double h) {
    if (_slots <= 0 || h <= 0) return 0;
    return ((dy / h) * _slots).floor().clamp(0, _slots - 1);
  }

  /// 换格：响一声 + 轻震（同一帧）—— 档位咬合
  void _detent(int slot) {
    Sfx.play('rung', variant: slot % 5);
    Haptics.buzz('choose');
  }

  void _showChip() {
    _chipTimer?.cancel();
    if (!_chipOn) setState(() => _chipOn = true);
    // M-13：松手 400ms 后淡出
    _chipTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _chipOn = false);
    });
  }

  /// 擦洗（拖动）：只换领位，**不开牌屉**
  void _scrub(int slot) {
    if (widget.total <= 0) return;
    _showChip();
    widget.onScrub(_indexOf(slot));
  }

  @override
  void dispose() {
    _chipTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double h = c.maxHeight;
        final int active = _dragSlot ?? _leadSlot;
        final int slot = _dragSlot ?? _slotAt(0, h);
        final int shown = _dragSlot == null ? widget.leadIndex : _indexOf(slot);
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            // 拖拽/轻点：只移动领位（M-13 与「打开牌屉」彻底分开）
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (TapDownDetails d) {
                final int s = _slotAt(d.localPosition.dy, h);
                _detent(s);
                _showChip();
                widget.onScrub(_indexOf(s));
              },
              onVerticalDragStart: (DragStartDetails d) {
                final int s = _slotAt(d.localPosition.dy, h);
                setState(() => _dragSlot = s);
                _detent(s);
                _showChip();
              },
              onVerticalDragUpdate: (DragUpdateDetails d) {
                final int s = _slotAt(d.localPosition.dy, h);
                if (s == _dragSlot) return;
                setState(() => _dragSlot = s);
                _detent(s);
                _showChip();
                _scrub(s);
              },
              onVerticalDragEnd: (DragEndDetails d) {
                final int? s = _dragSlot;
                setState(() => _dragSlot = null);
                if (s != null) _scrub(s);
              },
              onVerticalDragCancel: () => setState(() => _dragSlot = null),
              child: SizedBox.expand(
                child: CustomPaint(
                  painter: _ScrubberPainter(
                    slots: _slots,
                    active: active,
                    leadSlot: _leadSlot,
                    passed: widget.passedCount,
                    total: widget.total,
                    dragging: _dragSlot != null,
                    reduce: railReduceMotion(context),
                  ),
                ),
              ),
            ),
            // M-13 读数：拖动时右侧显示 `03/21`（Tektur 12，深色 chip）
            if (_chipOn && widget.total > 0)
              Positioned(
                left: _MissionScrubber.hitWidth - 6,
                top: h * .5 - 11,
                child: AnimatedOpacity(
                  opacity: _chipOn ? 1 : 0,
                  duration: const Duration(milliseconds: 400),
                  child: IgnorePointer(
                    child: Container(
                      key: const Key('main.scaleChip'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xD9020610),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: C.line2),
                      ),
                      // ⚠️ 2026-10-23：原来是 ${NN}/${NN}（两个补零数字），
                      //     读起来分不清「张数/总数」还是「序号/总数」。改成明说。
                      child: Text(
                        '第 ${shown + 1} 张 · 共 ${widget.total} 单',
                        style: fs(
                          family: F.num,
                          size: 12,
                          wght: 700,
                          height: 1,
                          color: C.ice,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 刻度轨画笔（docs/39 M-12）。
///
/// 轨道 x=10、宽 1px α.18；上下端帽 6px α.35；当前牌扇窗口 3px 亮带；
/// 脚下菱形头 7px；已完成段实心、未完成暗刻度。
/// ⚠️ 状态一律用样式表达（docs/17 纪律）——这里一个字都不写。
class _ScrubberPainter extends CustomPainter {
  const _ScrubberPainter({
    required this.slots,
    required this.active,
    required this.leadSlot,
    required this.passed,
    required this.total,
    required this.dragging,
    required this.reduce,
  });

  final int slots;
  final int active;
  final int leadSlot;
  final int passed;
  final int total;
  final bool dragging;
  final bool reduce;

  /// 刻度的中心 x（M-12：轨道 x=10）
  static const double _cx = 10;

  @override
  void paint(Canvas canvas, Size s) {
    if (slots <= 0 || s.height <= 0) return;
    final double step = s.height / slots;
    // 轨道本体：1px α.18（原来根本没有轨道，只有一根小刻度）
    canvas.drawLine(
      Offset(_cx, 0),
      Offset(_cx, s.height),
      Paint()
        ..color = C.blue.withAlpha(46)
        ..strokeWidth = 1,
    );
    // 上下端帽 6px α.35
    final Paint cap = Paint()
      ..color = C.blue.withAlpha(89)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(_cx - 3, 0), Offset(_cx + 3, 0), cap);
    canvas.drawLine(Offset(_cx - 3, s.height), Offset(_cx + 3, s.height), cap);
    // 每一格：已完成实心、未完成暗刻度；脚下菱形头 7px
    for (int i = 0; i < slots; i++) {
      final double y = step * (i + .5);
      final bool here = i == active;
      // 这一格覆盖的区间是否已经走完（按 doneCount 与 total 的比例）
      final double frac = total <= 0 ? 0 : (passed / total).clamp(0.0, 1.0);
      final bool done = (i / slots) < frac;
      if (here) {
        if (!reduce) {
          canvas.drawCircle(
            Offset(_cx, y),
            5,
            Paint()
              ..color = C.blue.withAlpha(dragging ? 110 : 70)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
          );
        }
        // 菱形头（7px 对角的方块旋转 45°）
        final Path d = Path()
          ..moveTo(_cx, y - 3.5)
          ..lineTo(_cx + 3.5, y)
          ..lineTo(_cx, y + 3.5)
          ..lineTo(_cx - 3.5, y)
          ..close();
        canvas.drawPath(d, Paint()..color = C.blue);
        continue;
      }
      final double w = done ? 6 : 3;
      canvas.drawLine(
        Offset(_cx - w / 2, y),
        Offset(_cx + w / 2, y),
        Paint()
          ..color = done ? C.blue.withAlpha(200) : C.blue.withAlpha(60)
          ..strokeWidth = done ? 2 : 1.5
          ..strokeCap = StrokeCap.round,
      );
    }
    // 当前牌扇窗口：3px 亮带（M-12）
    final double wy = step * (leadSlot + .5);
    canvas.drawLine(
      Offset(_cx - 5, wy),
      Offset(_cx + 5, wy),
      Paint()
        ..color = C.ice.withAlpha(120)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ScrubberPainter o) =>
      o.slots != slots ||
      o.active != active ||
      o.leadSlot != leadSlot ||
      o.passed != passed ||
      o.total != total ||
      o.dragging != dragging ||
      o.reduce != reduce;
}
