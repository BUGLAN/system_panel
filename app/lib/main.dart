import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'agent/copy.dart';
import 'agent/llm_client.dart';
import 'agent/llm_gateway.dart';
import 'agent/memory.dart';
import 'agent/settings_store.dart';
import 'agent/vision.dart';
import 'chat/chat_history.dart';
import 'chat/chat_panel.dart';
import 'chat/chat_service.dart';
import 'data/content.dart';
import 'data/rarity.dart';
import 'data/format.dart';
import 'data/items.dart';
import 'design/tokens.dart';
import 'screens/boot_screen.dart';
import 'stage/ring_painter.dart';
import 'state/host_state.dart';
import 'state/goal.dart';
import 'state/goal_gen.dart';
import 'stage/camera.dart';
import 'stage/live2d_stage.dart';
import 'stage/live2d_web.dart';
import 'stage/stage_port.dart';
import 'state/app_clock.dart';
import 'state/away.dart';
import 'state/voice.dart';
import 'state/save_file.dart';
import 'state/quest.dart';
import 'state/quest_flow.dart';
import 'state/result.dart';
import 'widgets/bg_layer.dart';
import 'widgets/ask_field.dart';
import 'widgets/banner.dart';
import 'widgets/chat_bar.dart';
import 'widgets/choices.dart';
import 'widgets/dock.dart';
import 'widgets/exec_panel.dart';
import 'widgets/exec_pill.dart';
import 'widgets/fail_layer.dart';
import 'widgets/fx_layer.dart';
import 'widgets/fx_particles.dart';
import 'widgets/hud.dart';
import 'widgets/interview_deck.dart';
import 'widgets/item_drawer.dart';
import 'widgets/line_layer.dart';
import 'widgets/main_view.dart';
import 'widgets/plate.dart';
import 'widgets/plate_timeline.dart';
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

  /// ⚠️ **诊断开关（T7 attempt 2）**：true = 裸舞台页（只有 Live2DStage，
  /// 无天幕/环场/任何 Flutter 层）——用来二分「原生不上屏」的责任方：
  /// 裸页能上屏 = 我们 App 的树有合成冲突（可修）；裸页也黑 = 插件/emugl
  /// 不兼容（scope 外，止损）。结论记 STAGE-OPTIONS；平时保持 false。
  static const bool kStageBareProbe = false;

  @override
  Widget build(BuildContext context) {
    if (kStageBareProbe) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF0A0E1A),
          body: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Live2DStage(
                visible: true,
                cam: Cam.byName('lobby'),
                onReady: (Live2DStageHandle h) =>
                    debugPrint('[bare] 裸舞台就绪'),
                onFailed: () => debugPrint('[bare] 裸舞台失败'),
              ),
              // 一块对照 Flutter 内容（左上角），确认 Flutter 层还在画
              const Positioned(
                left: 8,
                top: 8,
                child: Text(
                  'FLUTTER OVERLAY',
                  style: TextStyle(color: Colors.cyanAccent, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }
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
        // ⚠️ 必须用 TickerProviderStateMixin（不是 Single…）—— 主壳有 `_flashC`
        //    和 `_ringDim` 两个控制器。写错的症状是实机直接红屏：
        //    「_AppShellState is a SingleTickerProviderStateMixin but multiple tickers
        //      were created」——analyze 查不出来，只有跑起来才炸。
        with
        TickerProviderStateMixin,
        WidgetsBindingObserver {
  /// ── 舞台渲染路线（docs/18 §1.5；HANDOFF-LIVE2D-IOS）──────────────
  ///
  /// ⚠️ **2026-10-09 MuMu 实测：走止损线，默认 false（WebView）。**
  /// 原生在 MuMu 上「loadModel=true 但不上屏」复现旧 AVD 结论，且拿到新证据：
  /// Live2DTextureView 在树里（1080×1080，位置/尺寸正确）、loadModel 第 2 次
  /// true、但渲染线程每帧报 GL 0x501（INVALID_VALUE）于顶点提交——emugl 转译层
  /// 与插件的 shader/attrib 用法不兼容（旧 AVD 无此日志）。完整证据链见
  /// `app/STAGE-OPTIONS.md`「MuMu · 原生舞台复验」节。
  ///
  /// **翻回原生的条件**：flutter_live2d 插件升级（或换非模拟器 GPU 栈）后，
  /// 改回 `true` 跑一轮大厅截图 + gfxinfo 对照即可；桥接层（StagePort）两条
  /// 路线都已就绪，切换零成本。
  ///
  /// 运行期原生加载失败也会自动落到 WebView（`_stageFallback`）——
  /// WebView 版保留作降级与验收参照（HANDOFF 明示）。
  static const bool kNativeStage = false;

  /// 她的把手（emote/motion 桥）；原生失败落 WebView 后换成 WebStagePort
  StagePort? _stagePort;

  /// 原生舞台加载失败 → 运行期降级到 WebView
  bool _stageFallback = false;

  /// 行为逻辑未定，先用与原型「老宿主 · 第 23 天」一致的演示档
  /// （启动时会被存档覆盖 —— 见 SaveFile）
  HostState _host = HostState.demo;

  /// 业务唯一真源：队列 / 接单 / 道具 / 结算 / 认输（store.js 移植，quest_flow.dart）。
  /// 「提交卡死」根因①②的修复点：提交不再只是切页面，而是经 `_flow.settle()`
  /// 产出真实结算并落到档案 / 主线 / 队列。
  QuestFlow _flow = QuestFlow.demo();

  /// 最近一次结算（提交时由 QuestFlow.settle 产出；初值仅兜底显示）
  QuestResult _result = QuestResult.demo;

  /// 派单板显示的是队首（原型 `Store.head()`）
  Quest get _quest => _flow.head ?? Quest.demo;

  /// 执行面板显示的是"正在执行的那一单"—— 接单后队首已经换成下一张了
  Quest get _execQuest => _flow.active?.task ?? _quest;

  /// 结算演出播完后的岔路口开关（弹【再来一单。/先歇会儿。|收工。】）
  bool _resultChoicesOn = false;

  /// 失败页的记录（原型 `hhmm(Clock.now())` 与 `info.remedy`）
  DateTime _failAt = DateTime.now();
  bool _failTimeout = false;
  Remedy? _failRemedy;

  Moment _moment = Moment.boot;

  /// 主线（`Goal.demo()` 的起点是「今天」；启动时会被存档覆盖）
  Goal _goal = Goal.demo();

  /// 存档（store.js L34-52）
  final SaveFile _save = SaveFile();

  /// 口型包络（audio.js L180-230）—— 打字机逐字喂它，波形条读它。
  /// **不需要 Live2D**：模型到位后 `ParamMouthOpenY` 直接读同一个 `mouth`。
  final VoiceEnvelope _voice = VoiceEnvelope();

  /// 主线全景里展开的是哪一环（null = 没展开，只有抬头）
  int? _pickedRing;

  /// 绑定仪式的输入框
  final TextEditingController _ask = TextEditingController();

  /// ── 绑定流多幕（docs/18 §2.1 · t8 装配）────────────────────────
  ///
  /// 第 0 幕 = 问目标（AskField）；[_interviewCat] 非空 = 第 1 幕访谈卡
  /// （t4 的 InterviewDeck，按目标类型出 3~5 张）；答完 → `buildFirstGoal`
  /// 落 3 天 3 环 E/D/C + 见面礼双倍卡 → 大厅（首单已在队列）。
  GoalCategory? _interviewCat;

  /// 访谈要定的那句话（第 0 幕收进来的目标原文）
  String _pendingGoalText = '';

  /// 换日游标：上次补发日常的那一天（原型 `S.day`；清晨首次进入补发）
  DateTime? _lastRollDay;

  /// 亮帧：白 16% / 180ms ease-out（docs/08 逐帧里的「亮帧」）
  late final AnimationController _flashC = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  /// 屏幕空间特效（#fx 画布）
  final FxController _fx = FxController();

  /// 认输按住的进度（原型用它驱动 #veil 的暗度：p × .75）
  double _quitP = 0;

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

  // ── 小祥：文案接管 + 对话层（docs/18 §2.5/§2.6/§2.7，t10）────────
  //
  // SystemCopyProvider 四入口接 LLM（LlmGateway 包 t9 的 LlmClient）；
  // 断网/没配 Key 时 CopyLine.source == template → **保留现有原句逐字不动**
  // （发布='接不接？' / 结算=档位台词 / 毒舌=LINES.waver / 追问=LINES.askGoal），
  // 只有 LLM 真回了话才顶掉——兜底态与历史截图逐字节一致。

  /// 聊天历史（opus-v2/chat/v1，滚 200，重启仍在）
  final ChatHistory _chat = ChatHistory();

  /// LLM 忙时的占位锁
  bool _chatOpen = false;
  bool _chatThinking = false;

  /// 本轮对话的场合上下文（「找小祥说说 / 换目标」注入，docs/18 §2.7）
  String? _chatScenario;

  /// 文案接管后的 LLM 台词（null = 还没接到/回退原句）
  String? _probeLine; // 追问（绑定仪式）
  String? _dispatchLine; // 发布（派单板）

  /// 聊天消息 id（会话内唯一即可）
  int _chatSeq = 0;
  String _chatId() => 'm${DateTime.now().microsecondsSinceEpoch}_${_chatSeq++}';

  /// LLM 网关 + 文案/聊天服务（initState 异步装配；没配 Key 也能跑，全走兜底）
  SystemCopyProvider? _copy;
  ChatService? _chatService;

  /// 小祥的长期记忆（访谈答案写这里 —— 访谈即第一批记忆，docs/18 §2.1③）
  MemoryStore? _memory;

  Future<void> _initAgent() async {
    final AgentSettings s = await SettingsStore().load();
    await _chat.load();
    if (!mounted) return;
    final LlmGateway gw = LlmGateway(
      LlmClient(
        config: LlmConfig(
          baseUrl: s.baseUrl,
          apiKey: s.apiKey,
          model: s.model,
        ),
      ),
    );
    final MemoryStore mem = MemoryStore();
    setState(() {
      _memory = mem;
      _copy = SystemCopyProvider(llm: gw, memory: mem);
      _chatService = ChatService(gateway: gw, memory: mem);
    });
  }

  /// 打开对话层。[scenario] 传场合上下文（结算复盘 / 换目标），只影响她接下来的回复
  void _openChat({String? scenario}) {
    setState(() {
      _chatScenario = scenario;
      _chatOpen = true;
    });
  }

  /// 发送一条：宿主气泡立刻上屏 → 思考中 → 她的回复（LLM/兜底）→ mood 联动
  Future<void> _sendChat(String text) async {
    final ChatService? svc = _chatService;
    if (svc == null || _chatThinking) return;
    await _chat.append(ChatMessage.host(_chatId(), text));
    setState(() => _chatThinking = true);
    final ChatMessage reply = await svc.reply(
      text,
      history: _chat.messages,
      scenario: _chatScenario,
      statusLine: ChatService.statusLineOf(
        name: _host.name,
        lv: _host.lv,
        streak: _host.streak,
        queue: _host.queue,
        goalShort: _goal.short,
      ),
    );
    if (!mounted) return;
    setState(() => _chatThinking = false);
    await _chat.append(reply);
    if (!mounted) return;
    setState(() {});
    // emotion 标签 → 舞台 mood（docs/18 §2.6 演出联动）
    _stagePort?.mood(reply.emotion);
  }

  /// 语音入口（预留态）：点了不假装可用，她用气泡说明
  Future<void> _onVoiceTap() async {
    if (_chatThinking) return;
    await _chat.append(
      ChatMessage.sys(_chatId(), '语音模块还没装配，先用打的。入口给你留着。', emotion: 'neutral'),
    );
    if (mounted) setState(() {});
  }

  // ── 文案接管：发布 / 结算 / 毒舌 / 追问（docs/18 §2.5 四语气）────────

  /// 发布：进派单板时取一句（LLM 回了才顶掉「接不接？」）
  Future<void> _takeDispatchLine() async {
    final SystemCopyProvider? copy = _copy;
    if (copy == null) return;
    final CopyLine line = await copy.dispatchLine(
      CopyContext.fromState(host: _host, goal: _goal, quest: _quest),
    );
    if (!mounted || _moment != Moment.dispatch || _chatOpen) return;
    if (line.source == CopySource.llm) {
      setState(() => _dispatchLine = line.text);
    }
  }

  /// 结算：演出播完那句档位点评（LLM 回了才顶掉内置档位台词）
  Future<void> _takeSettleLine(QuestResult r) async {
    final SystemCopyProvider? copy = _copy;
    if (copy == null) return;
    final CopyLine line = await copy.settleLine(
      CopyContext.fromState(host: _host, goal: _goal, result: r),
    );
    if (!mounted || _moment != Moment.result || _chatOpen) return;
    if (line.source == CopySource.llm) {
      _sayAside(line.text, holdMs: 2600);
      _stagePort?.mood(line.emotion);
    }
  }

  /// 毒舌：按到一半松手（waver 原句先行，LLM 毒舌到了再顶）
  void _onWaverRoast() {
    _sayAside(
      LINES.waver[_rnd.nextInt(LINES.waver.length)],
      holdMs: 1400,
    );
    final SystemCopyProvider? copy = _copy;
    if (copy == null) return;
    copy
        .roastLine(
          CopyContext.fromState(host: _host, goal: _goal, quest: _quest),
          reason: '接单按到一半松了手',
        )
        .then((CopyLine line) {
      if (!mounted || _moment != Moment.dispatch) return;
      if (line.source == CopySource.llm) _sayAside(line.text, holdMs: 1600);
    });
  }

  /// 追问：绑定仪式的问目标（LLM 回了才顶掉 LINES.askGoal）
  Future<void> _takeProbeLine(String topic) async {
    final SystemCopyProvider? copy = _copy;
    if (copy == null) return;
    final CopyLine line = await copy.probeLine(
      CopyContext.fromState(host: _host, goal: _goal),
      topic: topic,
    );
    if (!mounted || _moment != Moment.onboard) return;
    if (line.source == CopySource.llm) {
      setState(() => _probeLine = line.text);
    }
  }

  /// 「找小祥说说」的场合上下文（docs/18 §2.7：当前任务+结算结果注入；
  /// 主线当前环拒换的钳制在工具层，这里只把事实告诉她）
  String get _resultTalkScenario {
    final QuestResult r = _result;
    return '结算后复盘：本单「${r.quest.name}」（${r.rarity.rank} 级，'
        'EXP+${r.exp}、◈+${r.coin}${r.crit ? '，暴击' : ''}）。'
        '宿主可能想聊聊下一单。换任务钳制：主线当前环不可换；日常走换单券。';
  }

  /// 「换目标」的场合上下文（docs/18 §2.7：旧主线环清空、队列主线单撤下
  /// 的确认语义由换目标流程负责，这里先让对话带着这个话题开起来）
  static const String _newGoalScenario =
      '换目标：宿主在主线页按了「换目标」。先追问为什么换、新目标是什么、'
      '打算给几天；提醒他：旧主线环会清空、队列里的主线单会撤下，想清楚再动。';

  /// 上一次宿主操作（原型 `App.lastAct`）
  DateTime _lastAct = DateTime.now();

  /// 进执行态时把计时归零重算（原型 `Store.accept()` 里记 startAt）
  void _beginExec() {
    // 真实接单：队首出队 + 记 startAt（原型 `Store.accept`；D12 修复
    // —— 计时不再写死"已执行 7 分钟"）
    final Quest? head = _flow.head;
    if (head != null) _flow.accept(head);
    // 原型 `App.dispatch()` 接单那一拍：Stage.motion('nod')
    _stagePort?.act('nod');
    setState(() {
      _execStart = _flow.active?.startAt ?? DateTime.now();
      _moment = Moment.exec;
      _chatter.resetExec(Duration.zero);
      // 新的一单：抽屉收起、上一单挂过的道具清掉（原型 `A.dbl/crit/shield` 随新单重建）
      _drawerOn = false;
      _usedItems.clear();
      _resultChoicesOn = false;
      _active = true; // 原型 `S.active` —— 收起后它仍然为真
      _host = _flow.host;
      _goal = _flow.goal;
    });
    _clock.startFast();
  }

  /// 用掉一个执行类道具（原型 `Store.useItem(k)`）
  ///
  /// 扣库存与"挂到本单"的标记都走 QuestFlow（结算的 ×2 / 暴击率 +25% /
  /// 免死全读它的 A.dbl / A.crit / A.shield）；插话与界面标签留在这层。
  void _useItem(String id) {
    final String? say = switch (id) {
      'dbl' => LINES.itemDbl,
      'crit' => LINES.itemCrit,
      'shield' => LINES.itemShield,
      _ => null,
    };
    setState(() {
      if (say != null && _flow.useItem(id)) {
        _usedItems.add(id);
        _host = _flow.host;
      }
      _drawerOn = false;
    });
    if (say != null) _sayAside(say, holdMs: 1800);
  }

  /// 她插一句（`hold` 之后自己收）
  ///
  /// [busy] 对应原型的 `App.run()`：她说「回来那几句」是**多拍演出**，
  /// 整段持有 `busy`，期间点别处一律没反应（flows.js L26 / L171）。碎碎念不持有。
  /// [holdMs] 不给就按原型的默认算（`clamp(420 + 字数*42, 900, 2400)`，见 `LINES.defaultHold`）。
  /// ⚠️ 原型每个调用点几乎都显式给了 hold，而且都很短（200~900ms）；
  ///    只有"回来的那几句"不给 —— 那几句就必须走这个默认。
  void _sayAside(String text, {int? holdMs, bool busy = false}) {
    final int hold = holdMs ?? LINES.defaultHold(text);
    setState(() {
      _aside = text;
      _asideUntil = DateTime.now().add(Duration(milliseconds: hold));
      if (busy) _busy = true;
    });
  }

  /// 原型 `App.second()`：换日之外的那几件事
  void _onSecond() {
    final DateTime now = DateTime.now();
    if (_asideUntil != null && now.isAfter(_asideUntil!)) {
      setState(() {
        _aside = null;
        _asideUntil = null;
        _busy = false; // 演出收场，恢复接客
        _voice.hush(); // 字幕收起 → 闭嘴（原型 `Line.hide()` 里也调了一次）
      });
    }
    // ⚠️ 原型这里是 `!$('#line').classList.contains('on')` —— 它的页面字幕
    //    说完就 hide 了，所以大部分时候是「关着的」。我们的演示档让页面字幕常驻，
    //    所以改成「她没有正在插话」（见 BEHAVIOR-GAPS.md D 组）
    // 超时判负（原型 Exec.tick() 末尾： >= lim → App.fail('timeout')）
    if (_moment == Moment.exec && _execReadout().timedOut) {
      _beginFail(how: 'timeout');
      return;
    }
    final bool lineQuiet = _aside == null && !_busy;
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
    limit: Duration(minutes: _execQuest.minutes),
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
    // 相机切页：只改弹簧的**目标**，每帧由 `_camTicker` 推过去（原型的 `setCam`）。
    // ⚠️ 这里不能碰 `_cam` 这个 ValueNotifier —— build 期间通知会触发
    //    "setState() or markNeedsBuild() called during build"；通知只放在 tick 里。
    if (_camSpring.name != camOf) {
      _camSpring.set(camOf, MediaQuery.sizeOf(context));
      if (!_camTicker.isActive) _camTicker.start();
    }
    final bool main = _moment == Moment.main;
    final bool boot = _moment == Moment.boot;
    // focus+dim：派单与结算都会把 HUD/底栏收走、天幕压暗
    final bool dim = dispatch || result;

    // lineAt（flows.js L23）：
    //   lobby = H*.6，dispatch = H-568，fail = H*.47，sheet = H*.38 - 104，main = H-192
    //   result = H-230（flows.js L23 的 result 档 —— 结算页她的台词位）
    final double lineY = dispatch
        ? size.height - 568
        : fail
        ? size.height * .47
        : result
        ? size.height - 230
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
                      // 绑定仪式还没立目标，天幕上写的还是 SYSTEM；
                      // 之后绑死 _goal.short（D10：绑定/换目标后自动跟随）
                      word: (boot || onboard)
                          ? 'SYSTEM'
                          : _goal.short,
                      latin: boot || onboard,
                    ),
                  ),
                ),
                // 任意按下都算「宿主还在」（原型 main.js L40 在整屏捕获阶段监听，
                // **不受 busy 影响** —— 演出期间也在记）
                // 同时：点背景 = 跳过打字机（原型 Tap 忽略 button/input/sheet/tag 上的点）
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (PointerDownEvent _) {
                      if (_lastAct.isBefore(
                        DateTime.now().subtract(const Duration(seconds: 1)),
                      )) {
                        setState(() => _lastAct = DateTime.now());
                      }
                    },
                  ),
                ),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() {
                      _tap++;
                      // 跳过打字机时闭嘴（原型 `ui.js` L106 `if (cut) Voice.hush()`）
                      _voice.hush();
                      _lastAct = DateTime.now();
                    }),
                  ),
                ),
                // 投影光束（在面板之下、天幕之上）
                SheetBeam(visible: sheet),
                // 她本人（`#stage`）—— 必须放在 Flutter UI **下面**：
                // 平台视图是 opaque 的，会吃掉触摸；更靠上的组件先命中，
                // 所以字幕/按钮/手势照样能点（原型里 `#stage` 也在 `#ui` 之前）。
                // ⚠️ **她的位置必须是这里** —— 天幕之后、环场/UI 之前。
                //    原型的层序就是 `#bg → #stage → #ui`，实测这个位置**层序完全正确**
                //    （字幕/环/HUD 都压在她之上，见 `.verify/_stageback.png`）。
                //
                // ── 渲染路线（docs/18 §1.5）────────────────────────────
                // 默认走**原生 flutter_live2d**（Live2DStage，几何相机=布局矩形
                // 复刻 Cam）；原生加载失败自动落到 WebView 降级（保留作验收参照）。
                // kNativeStage=false 可整条切回 WebView（A/B 对照开关）。
                // 相机随弹簧推镜头逐帧刷新（与下方环场同一数据源 _cam）。
                ValueListenableBuilder<Cam>(
                  valueListenable: _cam,
                  builder: (BuildContext _, Cam camNow, Widget? _) =>
                      kNativeStage && !_stageFallback
                      ? Live2DStage(
                          visible: true,
                          cam: camNow,
                          onReady: (Live2DStageHandle handle) {
                            _stagePort = NativeStagePort(handle);
                            debugPrint('[stage] 原生舞台就绪（flutter_live2d）');
                          },
                          onFailed: () {
                            debugPrint(
                              '[stage] 原生舞台加载失败 → WebView 降级',
                            );
                            if (mounted) setState(() => _stageFallback = true);
                          },
                        )
                      : Live2DWeb(
                          visible: true,
                          // ── 相机（大厅）─────────────────────────────
                          // WebView 路线的标定史（.verify/probe_cal.py / 大厅
                          // 92%）→ scale 1.132；只作降级，不再维护。
                          scale: 1.132,
                          offset: Offset.zero,
                          onReady: (Live2DWebState s) {
                            _stagePort = WebStagePort(s);
                            debugPrint('[stage-web] 播放器就绪（降级路线）');
                          },
                          onFailed: (String why) =>
                              debugPrint('[stage-web] 失败：$why'),
                        ),
                ),
                // 环场：她脚下到头顶那 8 个环。**画在独立画布上，与 Live2D 无关**
                // （`stage.js` L127 `cv.id='ringCv'`），启动时 `App.boot()` 会把
                // 8 个环全部 showRing，所以之后一直可见。
                ValueListenableBuilder<Cam>(
                  valueListenable: _cam,
                  builder: (BuildContext _, Cam camNow, Widget? _) => RingField(
                    goal: _goal,
                    cam: camOf,
                    camObj: camNow, // 弹簧推出来的那一帧（切页是"推镜头"不是瞬移）
                    t: 0,
                    ringMul: fail ? _ringMul : null,
                    dim: boot
                        ? .34 // 开机态的全息参数
                        : fail
                        ? 1 -
                              .4 *
                                  _ringDim
                                      .value // flows.js L530：holoTo({bright:.6}) 缓动过去
                        : 1,
                    scan: .2, // settings.holo → Stage.scanT
                  ),
                ),
                // TODO(step8+): 1 · 舞台 —— Live2D 角色 + 套在她身上的主线环 + 环挂签/环标签
                // 2 · 界面
                //    ⚠️ 原型的层级：`#veil` 是 z-auto（在 #ui 之后绘制），而 `.line` z=3、
                //    `#choices` z=4、`#plateAlt` z=2 —— 所以认输时 veil 压得住 failv，
                //    压不住字幕和选项。Stack 的先后顺序必须照这个 z 序排。
                Hud(
                  state: _host,
                  visible: lobby || exec,
                  onMenu: () => _openSheet(SheetKind.system),
                ),
                // 对话入口（docs/18 §2.6「HUD 对话按钮」）：hud.dart 的单写者
                // 纪律在 t9，这颗玻璃圆钮由本文件挂载——HUD 行下方左上，
                // 在 Stack 里压着 Live2D 平台视图，触摸先命中它
                if (lobby)
                  Positioned(
                    left: 16,
                    top: 78,
                    child: ChatEntryButton(onTap: () => _openChat()),
                  ),
                Dock(
                  state: _host,
                  visible: lobby,
                  // 队列空（今日已清）不再放行派单板 —— 免得接 到"幻影"演示单
                  onCta: _enterDispatchOrRest,
                  onSide: (int i) {
                    if (i == 0) {
                      setState(() {
                        _pickedRing = null;
                        _moment = Moment.main;
                      });
                    } else if (i == 1 || i == 2) {
                      _openSheet(i == 1 ? SheetKind.archive : SheetKind.supply);
                    }
                  },
                ),
                // 派单板
                Plate(
                  quest: _quest,
                  host: _host,
                  visible: dispatch,
                  // 稀有度滚完那一刻（原型 `Plate.rankRoll` 收尾）：
                  // `FX.flash(RARITY[r].c, target >= 4 ? .13 : .06, 280)`
                  // `if (target >= 5) FX.shake(6, 320)`（外加 Stage.glitch —— 那作用在
                  // Live2D 画布的滤镜上，等模型路线定了再接）
                  onRankFx: (int target) {
                    final Color rk = Rarity.of(kRanks[target]).color;
                    _pulse(
                      color: rk,
                      a: target >= 4 ? .13 : .06,
                      ms: 280,
                      shakePx: target >= 5 ? 6 : 0,
                    );
                    // `FX.burst(lr.cx, lr.cy, {n: 8+target*9, cols:[rk,蓝,冰],
                    //  min: 60, max: 150+target*55, life: .9, g: 60})`
                    // 骰子大字在屏幕上的位置（板 left16 / top396，骰子 right16 top34 86×104）
                    _fx.burst(
                      315,
                      469,
                      n: 8 + target * 9,
                      cols: <Color>[rk, C.blue, const Color(0xFFE9FBFF)],
                      min: 60,
                      max: 150 + target * 55,
                      life: .9,
                      g: 60,
                    );
                  },
                  // 指纹按到一半松手（原型 `Plate.hold()` 的 `up()`）
                  onWaver: _onWaverRoast,
                  onAccept: () {
                    // 原型 `App.dispatch()` → `App.run()`：忙的时候直接返回
                    if (_busy) return;
                    _beginExec();
                    _persist();
                  },
                ),
                // 执行面板
                // ⚠️ 必须包一层 ListenableBuilder 订阅时钟 —— 否则 `_clock` 每 250ms
                //    通知了没人听，计时器会一直停在进页面那一刻（实机踩过：等了 12 秒还是 07:00）
                ListenableBuilder(
                  listenable: _clock,
                  builder: (BuildContext context, Widget? child) => ExecPanel(
                    quest: _execQuest,
                    elapsed: _execReadout().elapsed,
                    // 暴击率不再是写死的 .12：证据/连击/暴击芯片联动（quest_flow）
                    critChance: _flow.critChance(),
                    // 原型是按持有数算的（`Exec.slots()` 末尾那个 reduce），
                    // 不是写死的 3 —— 用掉道具后这个数要跟着掉
                    itemCount: Item.execCount(_host.items),
                    tags: _usedItems,
                    evidenceCount: 0,
                    // D9 装配（t9 受控管线 + t14 档案口径）：证据进
                    // active.evidence，结算暴击率按 已校验7%/未校验4% 联动
                    evidence: _flow.active?.evidence,
                    onEvidenceChanged: (List<EvidenceShot> list) {
                      final ActiveQuest? a = _flow.active;
                      if (a == null) return;
                      setState(() {
                        a.evidence
                          ..clear()
                          ..addAll(list);
                      });
                    },
                    onRemoveEvidence: (int i) {
                      final List<EvidenceShot> ev =
                          _flow.active?.evidence ?? const <EvidenceShot>[];
                      if (i < 0 || i >= ev.length) return;
                      setState(() => _flow.removeEvidence(ev[i].id));
                    },
                    visible: exec,
                    // 指纹钤印那一下：原型 `Plate.seal()` 是
                    // `FX.flash('#bff6ff', .24, 280)` + `FX.shake(4, 220)`
                    onSubmit: () {
                      if (_busy) return; // 原型 `App.submit()` → `run()`
                      _clock.stopFast();
                      _active = false; // 交出去了，药丸该消失
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
                      // 真实结算（store.js settle 的移植）：经验/金币/六维/连击/
                      // 升级/主线环/称号全部落账，再进结算页 —— 卡死根因①②
                      setState(() {
                        _result = _flow.settle() ?? _result;
                        _resultChoicesOn = false;
                        _moment = Moment.result;
                        _host = _flow.host;
                        _goal = _flow.goal;
                      });
                      // 原型 settle() L372：结算时她专注读单
                      _stagePort?.mood('focus');
                      _persist();
                    },
                    onQuitProgress: (double p) => setState(() => _quitP = p),
                    onQuit: () {
                      if (_busy) return; // 原型 `App.fail()` → `run()`
                      setState(() {
                        _drawerOn = false;
                        _active = false; // 认输了，这一单不再是"执行中"
                      });
                      _beginFail();
                    },
                    // 点「道具」开合抽屉（原型 `#exItem` → `Exec.drawer()`，再点一次收起）
                    onItem: () => setState(() => _drawerOn = !_drawerOn),
                    // 收起 ▾（原型 `#exMin` → `App.lobby()`）：回大厅，**计时不停**
                    onCollapse: () => setState(() {
                      _drawerOn = false;
                      _moment = Moment.lobby;
                    }),
                  ),
                ),
                // 道具抽屉（`.drawer` z-index 5，压在执行面板之上）
                ItemDrawer(
                  open: exec && _drawerOn,
                  counts: _host.items,
                  used: _usedItems,
                  coins: _host.coins,
                  onUse: _useItem,
                  // 「去补给」—— 从执行页开的面板，关掉要回执行页（`_sheetFrom`）
                  onShop: () => _openSheet(SheetKind.supply),
                ),
                // 结算
                ResultPanel(
                  result: _result,
                  visible: result,
                  // 「保存战报」（D1）：结算数据 → 文本战报 → 剪贴板 + 插话确认
                  onSave: _saveReport,
                  // 演出播完 → 弹【再来一单。/先歇会儿。|收工。】（卡死根因④：
                  // 这是结算页唯一的退出路径，原型 flows.js L460-462）
                  onDone: _onResultDone,
                  // 「找小祥说说」（docs/18 §2.7 入口 A）：带结算上下文开对话层
                  onTalk: () => _openChat(scenario: _resultTalkScenario),
                  // 印章砸下那一刻（原型 `settle()` 的 ②）：
                  //   FX.flash('#ffffff', .16, 180)
                  //   FX.shake(ri >= 4 ? 7 : 4, 280)
                  //   FX.burst(g.cx, g.cy, {n: 36 + ri*16,
                  //     cols: [稀有度色, 蓝, 冰, 蓝, '#7fdcff'],
                  //     max: 300 + ri*70, life: 1.2 + ri*.08})
                  // 印章在屏幕上的位置：结算列底部锚定，136×136 的中心约 (195, 252)
                  onImpact: (int ri) {
                    final Color rk = Rarity.of(kRanks[ri]).color;
                    _pulse(
                      color: Colors.white,
                      a: .16,
                      ms: 180,
                      shakePx: ri >= 4 ? 7 : 4,
                    );
                    _fx.burst(
                      195,
                      252,
                      n: 36 + ri * 16,
                      cols: <Color>[
                        rk,
                        C.blue,
                        const Color(0xFFE9FBFF),
                        C.blue,
                        const Color(0xFF7FDCFF),
                      ],
                      max: 300 + ri * 70,
                      life: 1.2 + ri * .08,
                    );
                  },
                ),
                // 失败 / 补救（在 veil 之下）—— 记录时间与补救单来自真实认输
                FailLayer(
                  recordedAt: _hhmm(_failAt),
                  timeout: _failTimeout,
                  remedy: _failRemedy ?? Remedy.demo,
                  visible: fail,
                ),
                // 屏幕空间特效（#fx 在 DOM 里排在 #ui 之后、#veil 之前）
                FxField(controller: _fx),
                // 认输按住时屏幕跟着暗下去（最多 75%），认输后停在 60%
                Veil(
                  opacity: fail ? .6 : _quitP * .75,
                  instant: _quitP > 0, // 按住期间跟手，松手才回到 900ms 过渡
                ),
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
                  // D4 装配（t5 的回调 + t14 的 flow 业务）：
                  // 0=换一个→retreat（降一档/换 F/口头巨人）；1=等会儿→回大厅
                  onPick: _onPlateAlt,
                ),
                LineLayer(
                  // 文案真源：content.js L298 `holding` / L397 `mainline`
                  // 她主动开口时会临时顶掉页面字幕（原型是 Line.say().then(hide)）
                  text:
                      _aside ??
                      (dispatch
                          // 发布文案接管：LLM 回了顶掉原句，兜底保持「接不接？」
                          ? _dispatchLine ?? '接不接？'
                          : result && _resultChoicesOn
                          // 结算页的退出问话（原型 flows.js L462 的 choose()）
                          ? _flow.queueEmpty ? '收工？……明天见。' : '还做吗？'
                          : fail
                          // `[[{dl}]]` 是补救单截止（真实认输时间 + 24h）
                          ? LINES.remedyLine.replaceFirst(
                              '[[{dl}]]',
                              '[[明天 ${_hhmm(_flow.remedyDeadline ?? _failAt)}]]',
                            )
                          : main
                          ? LINES.mainline(_goal.doneCount, _goal.rings.length)
                          : onboard
                          // 访谈进行中换一句幕词；第 0 幕保持追问接管（兜底=askGoal 原句）
                          ? _interviewCat != null
                                ? '答完这几张，我给你排三天。'
                                : _probeLine ?? LINES.askGoal
                          : LINES.holding.replaceFirst(
                              '[[{n}]]',
                              '[[${_host.queue}]]',
                            )),
                  mood: onboard
                      ? '专注'
                      : dispatch
                      ? '监视'
                      : (fail ? '待机' : '尚可'),
                  y: lineY,
                  soft: fail,
                  fail: fail,
                  skipToken: _tap, // 点背景跳过打字机
                  // 口型包络：打字机每显形一个字就把目标开口度设一下，
                  // SYSTEM 后面那排波形条跟着动（原型 ui.js L70-73 / L96）
                  voice: _voice,
                  onChar: _voice.syllable,
                  // 原型里那句主线台词说完就 Line.hide()，点环展开详情时它已经不在——
                  // 两者都显示会叠在详情卡上。结算页只在「她说话」和「问还做吗」时出现
                  visible:
                      lobby ||
                      dispatch ||
                      fail ||
                      onboard ||
                      (result && (_aside != null || _resultChoicesOn)) ||
                      (main && _pickedRing == null),
                ),
                // 回应：结算收尾【再来一单。/先歇会儿。|收工。】
                // 失败页【……接。/今天算了。】（原型的 choose()，此前没接 onPick
                // 是「提交卡死」根因③④ —— 点了永远没反应）
                Choices(
                  items: _choices,
                  visible: _choicesOn,
                  onPick: _onChoice,
                ),
                // 绑定仪式 · 第 0 幕：她在上面问，宿主在这儿敲（z 4，在 veil 之上）
                // 提交后不直接绑定 —— 空泛的追问到具体为止，具体的进访谈卡
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
                  visible: onboard && _interviewCat == null,
                  onPreset: (String v) => _ask.text = v,
                  onSubmit: _onGoalSubmitted,
                ),
                // 绑定仪式 · 第 1 幕：卡片式访谈（docs/18 §2.1，t4 组件 + t8 装配）
                // 答完 → buildFirstGoal 落 3 天 3 环 → 见面礼 → 大厅
                if (onboard && _interviewCat != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 96,
                    child: InterviewDeck(
                      cards: interviewCardsFor(
                        _interviewCat!,
                        level: _host.lv,
                      ),
                      onDone: _completeOnboarding,
                    ),
                  ),
                // 投影面板（档案 / 补给 / 系统共用这一层壳）
                Sheet(
                  host: _host,
                  kind: _sheetKind,
                  visible: sheet,
                  // 关掉回**开它的那个页面**（原型 `App.closeSheet()` → `_sheetFrom`）
                  onClose: () => setState(() => _moment = _sheetFrom),
                  onWipe: _wipe,
                  // D6/D7 装配（t9 组件回调 + t14 flow 业务）：挂称号 / 购买
                  onEquipTitle: (String id) {
                    if (!_flow.equip(id)) return; // 未解锁/口头巨人期：组件已禁用，双保险
                    setState(() => _host = _flow.host);
                    _persist();
                    _sayAside('换上了。……还行。', holdMs: 1400);
                  },
                  onBuyItem: (String id) {
                    if (_flow.buy(id)) {
                      setState(() => _host = _flow.host);
                      _persist();
                      _sayAside('钱货两讫。省着点用。', holdMs: 1400);
                    } else {
                      // 组件在买不起时点不动；走到这里说明竞态扣空，接住即可
                      _sayAside('钱不够。……方向都给你指好了。', holdMs: 1400);
                    }
                  },
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
                  canDispatch: main && !_flow.queueEmpty,
                  visible: main,
                  onClose: () => setState(() => _moment = Moment.lobby),
                  onDispatch: _enterDispatchOrRest,
                  // D5：换目标 → 带场合上下文唤起小祥对话（docs/18 §2.7）
                  onNewGoal: () => _openChat(scenario: _newGoalScenario),
                ),
                // 「执行中」药丸（`ui.js` L60）：**执行页自己不显示它**，
                // 只在 大厅/主线/面板 上挂；点它回执行页。收起执行面板后就靠它回去。
                ListenableBuilder(
                  listenable: _clock,
                  builder: (BuildContext _, Widget? _) => ExecPill(
                    visible: _active && (lobby || main || sheet),
                    elapsed: _execReadout().elapsed,
                    onTap: () => setState(() {
                      if (_busy) return;
                      _moment = Moment.exec;
                    }),
                  ),
                ),
                // 对话层（docs/18 §2.6）：叠加，不替换；她仍在背景可见
                // ——层序在 Live2D/字幕之上、亮帧与横幅之下
                ChatPanel(
                  visible: _chatOpen,
                  messages: _chat.messages,
                  thinking: _chatThinking,
                  onSend: _sendChat,
                  onClose: () => setState(() => _chatOpen = false),
                  onVoiceTap: _onVoiceTap,
                ),
                // 横幅（z 5，压在所有东西上面）—— 绑定见面礼（数值语义在 goal_gen 的 kBindGift*）
                SysBanner(
                  kicker: kBindGiftKicker,
                  text: kBindGiftText,
                  glyph: '×2',
                  visible: _banner,
                ),
              ],
            ),
          ),
          // 3 · 覆盖层：开机自检（z 20，压在所有东西上面）
          if (boot)
            BootScreen(host: '${_host.name} · LV${_host.lv}', onWake: _wake),
        ],
      ),
    );
  }

  /// 绑定 · 第 0 幕收卷（原型 `makeGoal` 的空泛判定）：
  /// 空泛/太短 → 她追问到具体为止（不进访谈）；具体 → 进访谈卡。
  void _onGoalSubmitted() {
    final String typed = _ask.text.trim();
    if (isVagueGoal(typed)) {
      _takeProbeLine(typed.isEmpty ? '目标' : typed); // 追问文案接管（兜底=askGoal）
      _sayAside('太空了。说点具体的。', holdMs: 1800);
      return;
    }
    setState(() {
      _pendingGoalText = typed;
      _interviewCat = detectCategory(typed);
    });
    _takeProbeLine(typed);
  }

  /// 绑定 · 第 1 幕收卷（原型 `Store.bind(name, plan)` 的新政版）：
  /// 访谈答案 → 3 天 3 环 E/D/C 落档 → 队列 = 首环钉队首 + 当日日常 1~2
  /// → 见面礼双倍卡 ×1 → 大厅（首单已在队列）。
  void _completeOnboarding(Map<String, String> answers) {
    final GoalCategory cat = _interviewCat!;
    // ⚠️ 重置存档会冻结存储（原型靠随后的 location.reload() 解冻，我们没有重载），
    //    所以重新绑定这一刻要显式解冻，否则这次存盘会被静默跳过。
    _save.unfreeze();
    setState(() {
      _goal = buildFirstGoal(
        text: _pendingGoalText,
        cat: cat,
        answers: answers,
      );
      _flow = QuestFlow(host: _host, goal: _goal);
      // 绑定即建队列：首环 + 当日日常（store.js bind() 的 L165-167；
      // 每日 1~2 个走 §2.2 新政，不再用 seedForCurrentGoal 的固定 3 张）
      _flow.queue.add(_flow.ringTask(0));
      _flow.queue.addAll(_genTodaysDailies());
      _resyncQueueCount();
      // 见面礼：双倍卡 ×1（原型 bind() 的 `S.items.dbl += 1`，
      // 数值语义钉在 kBindGift*；Banner 演出在 build 里挂着）
      _flow.host = _flow.host.copyWith(items: applyBindGift(_flow.host.items));
      _host = _flow.host;
      _lastRollDay = startOfDay(DateTime.now());
      _interviewCat = null;
      _moment = Moment.lobby;
      _banner = true;
    });
    _persist();
    _rememberInterview(cat, answers);
    _sayAside('排好了。三天，每天一环。', holdMs: 2200);
    Future<void>.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _banner = false);
    });
  }

  /// 访谈答案 → 小祥的长期记忆（答案三用之三；记忆挂了不阻塞绑定）
  Future<void> _rememberInterview(
    GoalCategory cat,
    Map<String, String> answers,
  ) async {
    final MemoryStore? mem = _memory;
    if (mem == null) return;
    for (final String text in memoriesFromInterview(
      cat: cat,
      answers: answers,
      goalText: _pendingGoalText,
    )) {
      try {
        await mem.add(text, source: MemorySource.interview, weight: 2);
      } catch (_) {
        return;
      }
    }
  }

  /// 队列读数回同步（HUD 的 `[[{n}]]` 读 host.queue；
  /// main 直接做队列手术时 QuestFlow 的私有计数帮不上，手动对齐）
  void _resyncQueueCount() {
    _flow.host = _flow.host.copyWith(queue: _flow.queue.length);
    _host = _flow.host;
  }

  /// 当日日常（docs/18 §2.2）：类型池+通用池出候选 4~6 → 按
  /// 「最弱维/贴主线」挑 1~2（lv≥5 或连击≥3 为 2）。
  /// 单号经 [_flow.genDaily] 占位分配（合法单号，绝不与队列撞号 ——
  /// 占位单本身丢弃不入队）。
  List<Quest> _genTodaysDailies({int? n}) {
    final int count = n ?? dailyCountFor(level: _host.lv, streak: _host.streak);
    final String catId = _goal.cat.isEmpty ? 'gen' : _goal.cat;
    final List<DailyTemplate> picks = pickDailies(
      candidates: genDailyCandidates(catId: catId, rnd: _rnd),
      attrs: _host.attrs,
      goalCatId: catId,
      n: count,
      rnd: _rnd,
    );
    final List<Quest> slots = _flow.genDaily(picks.length);
    return <Quest>[
      for (int i = 0; i < picks.length && i < slots.length; i++)
        dailyQuestFrom(
          picks[i],
          serial: slots[i].serial,
          level: _host.lv,
          rnd: _rnd,
        ),
    ];
  }

  /// 换日（store.js `rollDay` L179-196 的装配）：隔夜日常作废、主线单重钉、
  /// 补发当日日常 1~2。「清晨首次进入」的判定：换日游标（[_lastRollDay]，
  /// 冷启动用存档 lastSeen 兜底）不是今天才动手 —— 同一天反复进出不重发。
  void _rollDayIfNeeded({DateTime? fromSeen, DateTime? now}) {
    final DateTime t0 = now ?? DateTime.now();
    final DateTime? anchor = _lastRollDay ?? fromSeen;
    if (anchor != null && isSameCalendarDay(anchor, t0)) return;
    if (_goal.isEmpty) {
      _lastRollDay = startOfDay(t0); // 没绑定就没日常可补
      return;
    }
    final List<Quest> next = rollDayQueue(
      overnight: _flow.queue,
      fresh: _genTodaysDailies(),
      mainTask: () {
        final int ci = _goal.currentIndex;
        return ci >= 0 ? _flow.ringTask(ci) : null;
      },
      activeIsMain: _flow.active?.task.kind == 'main',
      remedyDeadline: _flow.remedyDeadline,
      now: t0,
    );
    setState(() {
      _flow.queue
        ..clear()
        ..addAll(next);
      _resyncQueueCount();
      _lastRollDay = startOfDay(t0);
    });
    _persist();
  }

  /// 重置存档（`Store.wipe()`）：删档 + 冻结 + 回绑定仪式
  Future<void> _wipe() async {
    final SaveData d = await _save.wipe(
      fallback: SaveData(host: HostState.demo, goal: Goal.demo()),
    );
    if (!mounted) return;
    setState(() {
      _flow = QuestFlow.fromSave(host: d.host, goal: d.goal, queue: d.queue);
      _host = _flow.host;
      _goal = d.goal;
      _moment = Moment.onboard;
      // 回到绑定仪式第 0 幕（访谈进行到一半被重置的也收回来）
      _interviewCat = null;
      _pendingGoalText = '';
      _lastRollDay = null;
    });
    _takeProbeLine('绑定：宿主想变成什么样'); // 追问文案接管（兜底=askGoal 原句）
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
    // 原型 document.visibilitychange —— 记下你什么时候走的
    WidgetsBinding.instance.addObserver(this);
    _clock.startSeconds(_onSecond); // 原型 setInterval(App.second, 1000)
    _restore();
    _initAgent(); // 小祥：设置→LLM 网关→文案/聊天服务 + 聊天历史读档
  }

  /// ═══ 生命周期：她记得你走了多久（flows.js L186-193）═══
  ///
  /// 前台时用 _hiddenAt 算；冷启动用存档里的 lastSeen 算（跨进程也算数）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    switch (s) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _hiddenAt ??= DateTime.now();
        _persist(); // 走之前把 lastSeen 落下
      case AppLifecycleState.resumed:
        final DateTime? hid = _hiddenAt;
        _hiddenAt = null;
        if (hid == null) return;
        // 后台里跨了天 → 回前台先补发今日日常，再打招呼
        _rollDayIfNeeded(fromSeen: hid);
        _greetAfter(hid);
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// 离开太短就不吭声（way > 6e4）
  void _greetAfter(DateTime since) {
    final Duration away = DateTime.now().difference(since);
    final String? line = AwayGreeting.lineFor(away);
    if (line == null) return;
    // 演出还在跑就先不打断她
    if (_busy) return;
    // 原型这几句**不给 hold**（flows.js L189）→ 走按字数算的默认值
    _sayAside(line, busy: true);
  }

  /// 相机弹簧（`stage.js` L100-103）：切页时把镜头**推**过去，而不是瞬移。
  /// 只有环场与挂签吃这个相机（她本人还没接），所以这一改动只影响环的位置/缩放。
  final CamSpring _camSpring = CamSpring();
  final ValueNotifier<Cam> _cam = ValueNotifier<Cam>(Cam.byName('boot'));
  late final Ticker _camTicker = createTicker(_onCamTick);
  Duration _camLast = Duration.zero;

  void _onCamTick(Duration now) {
    final double dt = _camLast == Duration.zero
        ? 1 / 60
        : (now - _camLast).inMicroseconds / 1e6;
    _camLast = now;
    _camSpring.step(dt);
    _cam.value = _camSpring.cam;
    if (_camSpring.done) {
      _camTicker.stop();
      _camLast = Duration.zero;
    }
  }

  /// 失败时把当前那一环掐暗（原型 `Stage.dimRing(ci, …)` 三下：0 / 90 / 200ms）
  List<double>? _ringMul;

  /// 道具抽屉开着没（原型 `#exDrawer.on`）；再点一次「道具」收起
  bool _drawerOn = false;

  /// 有没有一单正在执行（原型 `S.active`）—— 收起后它仍然为真，
  /// 所以大厅里那颗「执行中」药丸会一直挂着（`ui.js` L60）
  bool _active = false;

  /// 投影面板是从哪开出来的（原型 `App._sheetFrom`）—— 关掉要回原处：
  /// 从执行页开的就得回执行页，不能一律回大厅
  Moment _sheetFrom = Moment.lobby;

  /// 开投影面板（原型 `App.sheet(kind)`）
  void _openSheet(SheetKind kind) {
    setState(() {
      _sheetFrom = _moment == Moment.exec ? Moment.exec : Moment.lobby;
      _sheetKind = kind;
      _moment = Moment.sheet;
      _drawerOn = false;
    });
  }

  /// 本单已经挂上生效的道具（原型 `A.dbl / A.crit / A.shield`）
  final Set<String> _usedItems = <String>{};

  /// `Stage.holoTo({bright: .6})` 是**缓动**过去的（每帧 `f += (target-f)*q`），
  /// 不是瞬变；这个控制器负责那 350ms
  late final AnimationController _ringDim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  )..addListener(() => setState(() {}));

  /// 进入失败态（认输与超时共用）：原型 `_fail()` 的视觉前几下
  void _beginFail({String how = 'quit'}) {
    _clock.stopFast();
    // 原型 `_fail()` L529：`Stage.setCam('fail'); Stage.emote('sad'); Stage.motion('down')`
    // —— 原生/WebView 桥已接通（T7），这里恢复当时的"暂时拿掉"：
    _stagePort?.mood('sad');
    _stagePort?.act('down');
    // 真实判负（store.js fail）：failCount 记账、主线单回队首、生成补救单
    // —— 失败页不再是死局：补救单可接可弃（见 _onChoice）
    final FailOutcome? fo = _flow.fail(how: how);
    setState(() {
      _moment = Moment.fail;
      _quitP = 0;
      _resultChoicesOn = false;
      _failAt = DateTime.now();
      _failTimeout = how == 'timeout';
      final Quest? r = fo?.remedy;
      _failRemedy = r == null
          ? null
          : Remedy(
              // FailLayer 自己会补「（做一半）」字样，这里给基础名
              name: fo!.task.name,
              minutes: r.minutes,
              rank: r.rank,
              deadline: '明天 ${_hhmm(fo.remedyDeadline ?? _failAt)}',
            );
      _host = _flow.host;
      _goal = _flow.goal;
    });
    _ringDim.forward(from: 0);
    final int ci = _goal.currentIndex;
    _setRingMul(ci, .2);
    Future<void>.delayed(const Duration(milliseconds: 90), () {
      if (mounted) _setRingMul(ci, .6);
    });
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _setRingMul(ci, .15);
    });
  }

  // ── 结算页 / 失败页的出口（「提交卡死」根因③④的修复）──────────────

  /// 回应选项什么时候出现：结算演出播完，或失败页进场（原型是她说完话
  /// 再 `choose()`；失败页那几句插话的时长不阻塞选项）
  bool get _choicesOn =>
      _moment == Moment.fail ||
      (_moment == Moment.result && _resultChoicesOn);

  /// 两套选项：队列空时只剩【收工。】（flows.js L462）
  List<Choice> get _choices {
    if (_moment == Moment.result && _resultChoicesOn) {
      return _flow.queueEmpty
          ? const <Choice>[Choice('收工。', main: true)]
          : const <Choice>[Choice('再来一单。', main: true), Choice('先歇会儿。')];
    }
    if (_moment == Moment.fail) {
      return const <Choice>[Choice('……接。', main: true), Choice('今天算了。')];
    }
    return const <Choice>[];
  }

  /// 选完的岔路（flows.js L464-465 / L554-558）：
  ///   再来一单 → 派单板 · 先歇会儿/收工 → 大厅
  ///   ……接 → 补救单插回队首 → 派单板 · 今天算了 → 大厅
  void _onChoice(int i) {
    if (_busy) return;
    if (_moment == Moment.result) {
      final bool more = i == 0 && !_flow.queueEmpty;
      setState(() {
        _resultChoicesOn = false;
        _moment = more ? Moment.dispatch : Moment.lobby;
      });
      return;
    }
    if (_moment == Moment.fail) {
      if (i == 0) {
        _flow.takeRemedy(now: true);
        setState(() {
          _host = _flow.host;
          _moment = Moment.dispatch;
        });
        _persist();
        return;
      }
      setState(() => _moment = Moment.lobby);
    }
  }

  /// 板下两颗按钮的岔路（原型 dispatch 循环，flows.js L250-321）：
  ///  · `labels[1]`「等会儿」= later：单子**原样留在她手里**（store.js:234
  ///    只 save），回大厅——`flows.js` L315 的 `this.lobby()`
  ///  · `labels[0]`「换一个」= retreat（store.js:235-250 全语义，t14 移植）：
  ///    非 F 降一档重刻 · F 还退休换一张别的 F · 累计 3 次强制戴「口头巨人」。
  ///    降档的 serial 不变 → 派单板不重播落板仪式，骰子静态换到新档
  ///    （原型 `Plate.reRank` 的换档动画是另一笔打磨账，这里先保证数据与可点）
  void _onPlateAlt(int i) {
    if (_busy) return;
    final Quest? head = _flow.head;
    if (head == null) return;
    if (i == 1) {
      // 「等会儿」台词（content.js L338 later 二选一）
      const List<String> later = <String>[
        '它不会跑。我也不会。',
        '行，先放我这。别让我等太久。',
      ];
      _sayAside(later[_rnd.nextInt(later.length)], holdMs: 1500);
      setState(() => _moment = Moment.lobby);
      _persist();
      return;
    }
    final RetreatOutcome? info = _flow.retreat(head);
    if (info == null) return; // 不在她手里（竞态）：忽略
    setState(() => _host = _flow.host);
    _persist();
    // retreat1/2/3（content.js L339-341，按当日第几次分档）
    _sayAside(
      switch (info.count) {
        1 => '目标是你立的。……给你个台阶：[[降一档]]。',
        2 => '今天第 [[${info.count}]] 次退了。系统开始给你建档案了。',
        _ => '第 [[${info.count}]] 次。行，接下来的单，[[按幼儿档]]给你配。',
      },
      holdMs: 1500,
    );
    if (info.shame) {
      // 口头巨人强制佩戴（flows.js L323-327 的 shame；横幅内容是写死的
      // 见面礼，这里用插话宣布——横幅通用化归横幅自己的任务）
      _sayAside('「口头巨人」。退缩满三次的勋章，[[摘不掉]]，完成一单再说。', holdMs: 2400);
    }
  }

  /// 结算演出播完（原型 `choose()` 前的那一刻）：弹选项 + 她按档位说一句
  /// （flows.js L442-447 的 tier 台词，t10 已由 SystemCopyProvider 接管：
  /// LLM 回了顶掉下面这句，兜底保持原句）
  void _onResultDone() {
    if (!mounted || _moment != Moment.result || _resultChoicesOn) return;
    setState(() => _resultChoicesOn = true);
    final QuestResult r = _result;
    // 原型 settle() L442-444 的 tier 情绪/动作（桥接通后恢复）
    _stagePort?.mood(switch (r.rarity.i) {
      <= 1 => 'smug',
      <= 3 => 'pleased',
      <= 5 => 'tsun',
      _ => 'tsun',
    });
    if (r.crit) {
      _stagePort?.mood('surprised');
      _stagePort?.act('surprise');
    } else if (r.rarity.i >= 4) {
      _stagePort?.act('happy');
    }
    final String line;
    if (r.tooFast) {
      line = '[[${r.held.inSeconds}]] 秒就交？做了吗你就交。';
    } else if (r.crit) {
      line = '暴击。手气不错——不过别指望每次都有。';
    } else {
      line = switch (r.rarity.i) {
        <= 1 => '收下了。小单也是单，积少成多。',
        <= 3 => 'C 级的活儿，干得像模像样。我认。',
        <= 5 => '这个完成度……勉强配得上这张单。',
        _ => 'S 级都敢接敢交。行，你有点东西。',
      };
    }
    _sayAside(line, holdMs: 2600);
    _takeSettleLine(r); // 结算文案接管：LLM 回了顶掉上面这句兜底
  }

  /// 「保存战报」（D1 最小可用版）：结算数据 → 文本 → 剪贴板 + 插话确认
  Future<void> _saveReport() async {
    final QuestResult r = _result;
    final String upsText = r.ups.isEmpty ? '' : ' · 升级 LV${r.ups.last}';
    final String report =
        'SYSTEM 战报\n'
        '${r.quest.serialText} ${r.quest.name}（${r.rarity.rank} 级）\n'
        'EXP +${r.exp} · 金币 +${r.coin}$upsText · 连击 ${r.streak} 天';
    try {
      await Clipboard.setData(ClipboardData(text: report));
      _sayAside('战报抄进剪贴板了。拿去炫耀吧。', holdMs: 1800);
    } catch (_) {
      _sayAside('战报没存上。……是设备的问题，不怪你。', holdMs: 1800);
    }
  }

  /// 进派单板的唯一入口：队列空就不进（换日补发已由 `_rollDayIfNeeded`
  /// 在启动/回前台时做过；真清空了就用一句插话接住，别让宿主接到幻影单）
  void _enterDispatchOrRest() {
    if (_busy) return;
    if (_flow.queueEmpty) {
      _sayAside('今天的单，清干净了。明天再来。', holdMs: 2200);
      return;
    }
    setState(() => _moment = Moment.dispatch);
    _takeDispatchLine(); // 发布文案接管：LLM 回了顶掉「接不接？」
  }

  /// 原型 `hhmm(Clock.now())`
  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  void _setRingMul(int i, double v) {
    if (i < 0) return;
    setState(() {
      final List<double> m = List<double>.filled(_goal.rings.length, 1);
      if (_ringMul != null) {
        for (int k = 0; k < m.length && k < _ringMul!.length; k++) {
          m[k] = _ringMul![k];
        }
      }
      if (i < m.length) m[i] = v;
      _ringMul = m;
    });
  }

  /// 什么时候被切到后台的（原型 `App.hiddenAt`）
  DateTime? _hiddenAt;

  /// 上次离开的时间（原型 `S.prevSeen`）—— 冷启动时从存档读出来
  DateTime? _prevSeen;

  /// 演出串行化（flows.js L26-29 `App.run`）：
  /// **忙的时候新的流程入口直接忽略**（不排队、不打断），原型就是这么写的。
  /// 目前只在「她正在说回来那几句」这种多拍演出里持有。
  bool _busy = false;

  /// 开机屏之后进大厅 —— 原型在这里跑 `App.greet(true)`：
  /// **冷启动一定会说一句**（`if (fromBoot || away > 6e4)`，默认档就是 back10m）
  void _wake() {
    setState(() => _moment = Moment.lobby);
    final DateTime? seen = _prevSeen;
    final Duration away = seen == null
        ? Duration.zero
        : DateTime.now().difference(seen);
    // `fromBoot` 会强制开口，所以 null（离开太短）也要退回默认那一档
    final AwayKind k = AwayGreeting.kindFor(away) ?? AwayKind.back10m;
    _sayAside(AwayGreeting.text(k, away), holdMs: 3200, busy: true);
  }

  /// 读档（store.js L34）—— 没有档就用演示档
  /// 顺带跑一次存储自检：实机曾经静默不落盘，这里让它出声
  Future<void> _restore() async {
    final SaveData d = await _save.load(
      fallback: SaveData(host: HostState.demo, goal: Goal.demo()),
    );
    // 存储自检 —— 通过就不吭声，不通过就把原因喊出来（别静默失败）
    final String? err = await _save.selfTest();
    if (err != null) debugPrint('[save] ⚠️ 存储不可用：$err');
    if (!mounted) return;
    // 老档没有队列 → QuestFlow 按现状补种子（合并式迁移，不清档）
    final bool seeded = d.queue.isEmpty;
    setState(() {
      _flow = QuestFlow.fromSave(host: d.host, goal: d.goal, queue: d.queue);
      _host = _flow.host;
      _goal = _flow.goal;
      // 原型 `load()` 里的 `S.prevSeen = S.lastSeen` —— 冷启动算"你走了多久"用
      _prevSeen = d.lastSeen;
    });
    // 补出来的种子要落一次盘，重启后队列还在
    if (seeded && _flow.queue.isNotEmpty) _persist();
    // 换日（store.js rollDay）：隔夜日常作废、主线单重钉、补发当日日常。
    // 「清晨首次进入」= 存档 lastSeen 的日子不是今天（同日重进不重发）
    _rollDayIfNeeded(fromSeen: d.lastSeen);
  }

  /// 存盘（store.js L43）—— 档案 + 主线 + 她手里的队列
  ///
  /// 启动时的自检（`SaveFile.selfTest`）是**通过**的，但这里写完整存档后回读是空的
  /// —— 所以下面多打一行原始串长度，用来区分「没写进去」和「写进去了解析不出来」。
  Future<void> _persist() async {
    await _save.save(
      SaveData(host: _host, goal: _goal, queue: _flow.queue),
    );
    final String? raw = await _save.rawRead();
    final SaveData back = await _save.load();
    if (back.goal.text != _goal.text) {
      final String head = raw == null
          ? 'null'
          : raw.substring(0, raw.length < 70 ? raw.length : 70);
      debugPrint(
        '[save] ⚠️ 回读不一致：wrote=[${_goal.text}] read=[${back.goal.text}] '
        'rawLen=${raw?.length} rawHead=$head',
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    _camTicker.dispose();
    _cam.dispose();
    _ringDim.dispose();
    _flashC.dispose();
    _fx.dispose();
    _ask.dispose();
    super.dispose();
  }
}
