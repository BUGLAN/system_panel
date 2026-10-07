import 'package:flutter/material.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'data/content.dart';
import 'data/format.dart';
import 'design/tokens.dart';
import 'screens/boot_screen.dart';
import 'stage/ring_painter.dart';
import 'state/host_state.dart';
import 'state/goal.dart';
import 'state/app_clock.dart';
import 'state/quest.dart';
import 'state/result.dart';
import 'widgets/bg_layer.dart';
import 'widgets/ask_field.dart';
import 'widgets/banner.dart';
import 'widgets/choices.dart';
import 'widgets/dock.dart';
import 'widgets/exec_panel.dart';
import 'widgets/fail_layer.dart';
import 'widgets/fx_layer.dart';
import 'widgets/fx_particles.dart';
import 'widgets/hud.dart';
import 'widgets/line_layer.dart';
import 'widgets/main_view.dart';
import 'widgets/plate.dart';
import 'widgets/result_panel.dart';
import 'widgets/ring_labels.dart';
import 'widgets/ring_tag.dart';
import 'widgets/sheet.dart';

/// 宿主 SYSTEM —— Flutter 客户端。
/// 设计真源：prototype/opus-v2-dir（原型即规格）。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  // 原型是全屏手机，没有系统栏
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const SysApp());
}

class SysApp extends StatelessWidget {
  const SysApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SYSTEM · 宿主',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: C.voidBg,
      ),
      home: const AppShell(),
    );
  }
}

/// 时刻 —— 对应原型 `App.setMode()` 的那几个状态。
/// 每个状态叠加在 `#app` 上的类名决定谁出现谁消失（flows.js L15）：
///   boot → booting（HUD/底栏收走）· lobby → 无
///   dispatch → focus+dim（HUD/底栏收走、天幕压暗）
///   exec → panel（只收底栏）· result → focus+dim
///   fail → focus+fail（HUD/底栏收走、天幕抽色压暗 + veil）
///   sheet → focus（投影面板升起）· main → focus（主线全景 + 环挂签）
enum Moment { boot, lobby, onboard, dispatch, exec, result, fail, sheet, main }

/// 所有页面的共同外壳，对应原型的 `#app` + `#shake`：
///   天幕（#bg）→ 舞台（#stage）→ 界面（#ui）→ 覆盖层
///
/// 每一步复刻一页。当前已复刻：开机自检、大厅、派单板、执行面板、结算、失败/补救。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  /// 行为逻辑未定，先用与原型「老宿主 · 第 23 天」一致的演示档
  static const HostState _host = HostState.demo;
  static const Quest _quest = Quest.demo;
  static const QuestResult _result = QuestResult.demo;

  Moment _moment = Moment.boot;

  /// 主线（`Goal.demo()` 的起点是「今天」，只取一次）
  late final Goal _goal = Goal.demo();

  /// 主线全景里展开的是哪一环（null = 没展开，只有抬头）
  int? _pickedRing;

  /// 绑定仪式的输入框
  final TextEditingController _ask = TextEditingController();

  /// 亮帧：白 16% / 180ms ease-out（docs/08 逐帧里的「亮帧」）
  late final AnimationController _flashC = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  /// 屏幕空间特效（#fx 画布）
  final FxController _fx = FxController();

  /// 点一下跳过打字机（原型 Tap.next()）
  int _tap = 0;

  /// 震屏
  int _shake = 0;
  double _shakePx = 4;

  /// 亮帧的颜色与峰值强度（按事件不同）
  Color _flashColor = Colors.white;
  double _flashA = .16;

  /// 横幅（称号/道具到手时从顶上滑下来）
  bool _banner = false;

  /// 投影面板当前停在哪一页
  SheetKind _sheetKind = SheetKind.archive;

  /// ⏱ 每秒时钟（原型 `setInterval(App.second, 1000)`）
  final AppClock _clock = AppClock();

  /// 她主动开口的排期（原型 `App.nextIdle` / `nextComment`）
  final ChatterScheduler _chatter = ChatterScheduler();

  /// 这一单是什么时候接的 —— 计时**由它推导**，不是累加
  /// （原型 `Clock.now() - A.startAt`，息屏回来照样对）
  late DateTime _execStart = DateTime.now();

  /// 她插话时临时顶掉页面字幕（原型是 `Line.say().then(hide)`，
  /// 我们是状态驱动的，所以用一个带截止时间的覆盖）
  String? _aside;
  DateTime? _asideUntil;

  /// 上一次宿主操作（原型 `App.lastAct`）
  DateTime _lastAct = DateTime.now();

  /// 进执行态时把计时归零重算（原型 `Store.accept()` 里记 startAt）
  void _beginExec() {
    setState(() {
      _execStart = DateTime.now().subtract(
        const Duration(minutes: 7),
      ); // 演示档：已执行 7 分钟
      _moment = Moment.exec;
      _chatter.resetExec(Duration.zero);
    });
    _clock.startFast();
  }

  /// 她插一句（`hold` 之后自己收）
  void _sayAside(String text, {int holdMs = 3200}) {
    setState(() {
      _aside = text;
      _asideUntil = DateTime.now().add(Duration(milliseconds: holdMs));
    });
  }

  /// 原型 `App.second()`：换日之外的那几件事
  void _onSecond() {
    final DateTime now = DateTime.now();
    if (_asideUntil != null && now.isAfter(_asideUntil!)) {
      setState(() {
        _aside = null;
        _asideUntil = null;
      });
    }
    // ⚠️ 原型这里是 `!$('#line').classList.contains('on')` —— 它的页面字幕
    //    说完就 hide 了，所以大部分时候是「关着的」。我们的演示档让页面字幕常驻，
    //    所以改成「她没有正在插话」（见 BEHAVIOR-GAPS.md D 组）
    // 超时判负（原型 Exec.tick() 末尾： >= lim → App.fail('timeout')）
    if (_moment == Moment.exec && _execReadout().timedOut) {
      _clock.stopFast();
      setState(() => _moment = Moment.fail);
      return;
    }
    final bool lineQuiet = _aside == null;
    if (_moment == Moment.lobby &&
        now.difference(_lastAct) > ChatterScheduler.quietAfterAction &&
        lineQuiet) {
      final Duration up = now.difference(_sessionStart);
      if (up >= _chatter.idleNextAt) {
        final int h = now.hour;
        final String text = (h >= 23 || h < 5)
            ? LINES.idleNight
            : (h < 10 && _rnd.nextDouble() < .4)
            ? LINES.idleMorning
            : LINES.idle.first;
        _chatter.resetIdle(up);
        _sayAside(text, holdMs: 3200);
      }
    }
    if (_moment == Moment.exec) {
      final Duration up = now.difference(_sessionStart);
      if (up >= _chatter.execNextAt && lineQuiet) {
        _chatter.resetExec(up);
        final ExecReadout r = _execReadout();
        _sayAside(
          r.remaining.inMinutes < 3 && !r.remaining.isNegative
              ? LINES.execNear.replaceFirst('[[{t}]]', fmtDur(r.remaining))
              : LINES.exec.first,
          holdMs: 2600,
        );
      }
    }
  }

  ExecReadout _execReadout() => ExecReadout.of(
    startAt: _execStart,
    now: _clock.now,
    limit: Duration(minutes: _quest.minutes),
  );

  late final DateTime _sessionStart = DateTime.now();
  final math.Random _rnd = math.Random();

  /// 单位矩阵（fail 滤镜动画的起点）
  static const List<double> _identity = <double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  static List<double> _lerpMatrix(List<double> a, List<double> b, double t) =>
      List<double>.generate(20, (int i) => a[i] + (b[i] - a[i]) * t);

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final bool lobby = _moment == Moment.lobby;
    final bool dispatch = _moment == Moment.dispatch;
    final bool exec = _moment == Moment.exec;
    final bool result = _moment == Moment.result;
    final bool fail = _moment == Moment.fail;
    final bool sheet = _moment == Moment.sheet;
    final bool onboard = _moment == Moment.onboard;

    /// 各状态用的相机预设（flows.js 里各流程自己调的 `Stage.setCam`）
    final String camOf = switch (_moment) {
      Moment.boot => 'boot',
      Moment.lobby => 'lobby',
      Moment.onboard => 'boot',
      Moment.dispatch => 'talk',
      Moment.exec => 'exec',
      Moment.result => 'result',
      Moment.fail => 'fail',
      Moment.sheet => 'panel',
      Moment.main => 'full',
    };
    final bool main = _moment == Moment.main;
    final bool boot = _moment == Moment.boot;
    // focus+dim：派单与结算都会把 HUD/底栏收走、天幕压暗
    final bool dim = dispatch || result;

    // lineAt（flows.js L23）：
    //   lobby = H*.6，dispatch = H-568，fail = H*.47，sheet = H*.38 - 104，main = H-192
    final double lineY = dispatch
        ? size.height - 568
        : fail
        ? size.height * .47
        : sheet
        ? size.height * .38 - 104
        : main
        ? size.height - 192
        : onboard
        ? size.height * .55
        : size.height * .6;

    return Scaffold(
      backgroundColor: C.voidBg,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // `#shake` 包住 `#bg` 到 `#flash` 的全部内容（`#boot` 在它外面，不跟着抖）
          ShakeLayer(
            token: _shake,
            px: _shakePx,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // 0 · 天幕（她身后的世界）
                //   开机时写 SYSTEM，进大厅后写宿主的目标（flows.js `setWord`）
                AnimatedOpacity(
                  opacity: dim ? .35 : 1, // #app.dim #bg
                  duration: const Duration(milliseconds: 800),
                  child: TweenAnimationBuilder<double>(
                    // #bg { transition: opacity .8s, filter .8s } —— 认输抽色压暗也是渐变的
                    tween: Tween<double>(begin: 0, end: fail ? 1 : 0),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeInOut,
                    builder: (BuildContext _, double t, Widget? child) => t <= 0
                        ? child!
                        : ColorFiltered(
                            colorFilter: ColorFilter.matrix(
                              _lerpMatrix(_identity, kFailColorMatrix, t),
                            ),
                            child: child,
                          ),
                    child: BgLayer(
                      // 绑定仪式还没立目标，天幕上写的还是 SYSTEM
                      word: (boot || onboard) ? 'SYSTEM' : '半马',
                      latin: boot || onboard,
                    ),
                  ),
                ),
                // 任意按下都算「宿主还在」（原型 main.js L40 的捕获阶段监听）
                // 同时：点背景 = 跳过打字机（原型 Tap 忽略 button/input/sheet/tag 上的点）
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() {
                      _tap++;
                      _lastAct = DateTime.now();
                    }),
                  ),
                ),
                // 投影光束（在面板之下、天幕之上）
                SheetBeam(visible: sheet),
                // 环场：她脚下到头顶那 8 个环。**画在独立画布上，与 Live2D 无关**
                // （`stage.js` L127 `cv.id='ringCv'`），启动时 `App.boot()` 会把
                // 8 个环全部 showRing，所以之后一直可见。
                RingField(
                  goal: _goal,
                  cam: camOf,
                  t: 0,
                  dim: boot
                      ? .34 // 开机态的全息参数
                      : fail
                      ? .6 // flows.js L530
                      : 1,
                  scan: .2, // settings.holo → Stage.scanT
                ),
                // TODO(step8+): 1 · 舞台 —— Live2D 角色 + 套在她身上的主线环 + 环挂签/环标签
                // 2 · 界面
                //    ⚠️ 原型的层级：`#veil` 是 z-auto（在 #ui 之后绘制），而 `.line` z=3、
                //    `#choices` z=4、`#plateAlt` z=2 —— 所以认输时 veil 压得住 failv，
                //    压不住字幕和选项。Stack 的先后顺序必须照这个 z 序排。
                Hud(
                  state: _host,
                  visible: lobby || exec,
                  onMenu: () => setState(() {
                    _sheetKind = SheetKind.system;
                    _moment = Moment.sheet;
                  }),
                ),
                Dock(
                  state: _host,
                  visible: lobby,
                  onCta: () => setState(() => _moment = Moment.dispatch),
                  onSide: (int i) {
                    if (i == 0) {
                      setState(() {
                        _pickedRing = null;
                        _moment = Moment.main;
                      });
                    } else if (i == 1 || i == 2) {
                      setState(() {
                        _sheetKind = i == 1
                            ? SheetKind.archive
                            : SheetKind.supply;
                        _moment = Moment.sheet;
                      });
                    }
                  },
                ),
                // 派单板
                Plate(
                  quest: _quest,
                  host: _host,
                  visible: dispatch,
                  onAccept: _beginExec,
                ),
                // 执行面板
                // ⚠️ 必须包一层 ListenableBuilder 订阅时钟 —— 否则 `_clock` 每 250ms
                //    通知了没人听，计时器会一直停在进页面那一刻（实机踩过：等了 12 秒还是 07:00）
                ListenableBuilder(
                  listenable: _clock,
                  builder: (BuildContext context, Widget? child) => ExecPanel(
                    quest: _quest,
                    elapsed: _execReadout().elapsed,
                    critChance: .12,
                    itemCount: 3,
                    evidenceCount: 0,
                    visible: exec,
                    // 指纹钤印那一下：原型 `Plate.seal()` 是
                    // `FX.flash('#bff6ff', .24, 280)` + `FX.shake(4, 220)`
                    onSubmit: () {
                      _clock.stopFast();
                      _pulse(color: const Color(0xFFBFF6FF), a: .24, ms: 280);
                      // 钤印那一下：涟漪 + 火花 + 爆散（ui.js L346-347 / L358）
                      _fx.ripple(
                        195,
                        726,
                        r1: 300,
                        flat: .38,
                        color: const Color(0xFFBFF6FF),
                        w: 3,
                        ms: 700,
                      );
                      _fx.spark(195, 726, n: 18);
                      _fx.burst(195, 540, n: 60);
                      setState(() => _moment = Moment.result);
                    },
                    onQuit: () => setState(() {
                      _clock.stopFast();
                      _moment = Moment.fail;
                    }),
                  ),
                ),
                // 结算
                ResultPanel(result: _result, visible: result, onSave: () {}),
                // 失败 / 补救（在 veil 之下）
                FailLayer(
                  recordedAt: '20:02',
                  remedy: Remedy.demo,
                  visible: fail,
                ),
                // 屏幕空间特效（#fx 在 DOM 里排在 #ui 之后、#veil 之前）
                FxField(controller: _fx),
                Veil(opacity: fail ? .6 : 0),
                // 亮帧（`#flash` 在 DOM 里排在 veil 之后；正 z 的那些会盖在它上面）
                // ⚠️ 必须判 isAnimating —— 控制器停在 0 时 `1 - easeOut(0) = 1`，
                // 会让亮帧**一直开着**（整屏被垫一层 16% 白，一路比对下来才发现）
                AnimatedBuilder(
                  animation: _flashC,
                  builder: (BuildContext context, Widget? child) => FlashLayer(
                    color: _flashColor,
                    alpha: _flashC.isAnimating
                        ? _flashA *
                              (1 - Curves.easeOut.transform(_flashC.value))
                        : 0,
                  ),
                ),
                // 以下三件在 veil 之上（z 2 / 3 / 4）
                PlateAlt(
                  labels: const <String>['换一个', '等会儿'],
                  visible: dispatch,
                ),
                LineLayer(
                  // 文案真源：content.js L298 `holding` / L397 `mainline`
                  // 她主动开口时会临时顶掉页面字幕（原型是 Line.say().then(hide)）
                  text:
                      _aside ??
                      (dispatch
                          ? '接不接？'
                          : fail
                          ? '补救的路，我给你留着：明天 20:02 前，做一半。做到了，这次不算。'
                          : main
                          ? '${_goal.doneCount}/${_goal.rings.length} 环。顶上那个，是你的目标。'
                          : onboard
                          ? '说吧。你想变成什么样？一句话。'
                          : '我手里有 ${_host.queue} 单。都是给你的。'),
                  mood: onboard
                      ? '专注'
                      : dispatch
                      ? '监视'
                      : (fail ? '待机' : '尚可'),
                  y: lineY,
                  soft: fail,
                  fail: fail,
                  skipToken: _tap, // 点背景跳过打字机
                  // 原型里那句主线台词说完就 Line.hide()，点环展开详情时它已经不在——
                  // 两者都显示会叠在详情卡上
                  visible:
                      lobby ||
                      dispatch ||
                      fail ||
                      onboard ||
                      (main && _pickedRing == null),
                ),
                Choices(
                  items: const <Choice>[
                    Choice('……接。', main: true),
                    Choice('今天算了。'),
                  ],
                  visible: fail,
                ),
                // 绑定仪式：她在上面问，宿主在这儿敲（z 4，在 veil 之上）
                AskField(
                  prompt: '目标 ›',
                  placeholder: '比如：三个月跑完半马',
                  presets: const <String>[
                    '三个月跑完半马',
                    '一个月早睡早起',
                    '考研上岸',
                    '半年减重 10 斤',
                    '学会画画',
                    '变优秀',
                  ],
                  controller: _ask,
                  visible: onboard,
                  onPreset: (String v) => _ask.text = v,
                  onSubmit: _bind,
                ),
                // 投影面板（档案 / 补给 / 系统共用这一层壳）
                Sheet(
                  host: _host,
                  kind: _sheetKind,
                  visible: sheet,
                  onClose: () => setState(() => _moment = Moment.lobby),
                  onWipe: () => setState(() => _moment = Moment.onboard),
                ),
                // 当前环的挂签（大厅里挂在她脚下那一环的右端）
                RingTag(
                  goal: _goal,
                  visible: lobby,
                  dimmed: true, // 字幕在 → 原型把它压到 18%
                  onTap: () => setState(() {
                    _pickedRing = null;
                    _moment = Moment.main;
                  }),
                ),
                // 主线全景：环挂签挂在环上（位置由相机数学给出），面板压在上面
                RingLabels(
                  goal: _goal,
                  visible: main,
                  onPick: (int i) => setState(() => _pickedRing = i),
                ),
                MainView(
                  goal: _goal,
                  selected: main ? _pickedRing : null,
                  // 原型 `canGo = !S.active && cur >= 0 && 队列里有主线单`——
                  // veteran 档三条都成立，所以那颗蓝色主按钮是显示的
                  canDispatch: main,
                  visible: main,
                  onClose: () => setState(() => _moment = Moment.lobby),
                  onDispatch: () => setState(() => _moment = Moment.dispatch),
                ),
                // 横幅（z 5，压在所有东西上面）
                SysBanner(
                  kicker: '见面礼',
                  text: '双倍卡 ×1',
                  glyph: '×2',
                  visible: _banner,
                ),
              ],
            ),
          ),
          // 3 · 覆盖层：开机自检（z 20，压在所有东西上面）
          if (boot)
            BootScreen(
              host: '${_host.name} · LV${_host.lv}',
              onWake: () => setState(() => _moment = Moment.lobby),
            ),
        ],
      ),
    );
  }

  /// 绑定：收起输入框 → 回大厅 → 报一个「见面礼」
  /// （原型 `Store.bind()` 之后 `Banner.show('见面礼','双倍卡 ×1','×2')`，2200ms 后自己收）
  void _bind() {
    setState(() {
      _moment = Moment.lobby;
      _banner = true;
    });
    Future<void>.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _banner = false);
    });
  }

  /// 打一帧亮帧 + 抖一下 —— 原型里这两件事总是成对出现，参数按事件给。
  /// 调用点的原参数（`ui.js` / `flows.js`）：
  ///   玻璃板落定 `#9ff0ff .10 160ms` · 稀有度揭晓 `#ffffff .16 180ms`
  ///   暴击 `#e9fbff .14 200ms` · 指纹钤印 `#bff6ff .24 280ms`
  /// ⚠️ 各事件的具体时机还没等到宿主约束，这里先把签名备好。
  void _pulse({
    Color color = Colors.white,
    double a = .16,
    int ms = 180,
    double shakePx = 4,
  }) {
    setState(() {
      _flashColor = color;
      _flashA = a;
      _shakePx = shakePx;
      _flashC.duration = Duration(milliseconds: ms);
      _shake++;
    });
    _flashC.forward(from: 0);
  }

  @override
  @override
  void initState() {
    super.initState();
    _clock.startSeconds(_onSecond); // 原型 setInterval(App.second, 1000)
  }

  @override
  void dispose() {
    _clock.dispose();
    _flashC.dispose();
    _fx.dispose();
    _ask.dispose();
    super.dispose();
  }
}
