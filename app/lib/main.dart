import 'dart:async';
import 'dart:math' as math;

import 'package:image_picker/image_picker.dart';

import 'package:flutter/foundation.dart' show kDebugMode, kProfileMode;
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'agent/copy.dart';
import 'design/ref.dart';
import 'agent/context_adapter.dart';
import 'agent/goal_match_agent.dart';
import 'agent/mainline_tool.dart';
import 'agent/llm_client.dart';
import 'agent/llm_gateway.dart';
import 'agent/memory.dart';
import 'agent/plan_agent.dart';
import 'agent/plan_brief.dart';
import 'agent/settings_store.dart';
import 'agent/tools.dart';
import 'agent/vision.dart';
import 'agent/vision_platform.dart';
import 'chat/chat_history.dart';
import 'chat/chat_panel.dart';
import 'chat/chat_service.dart';
import 'data/attrs.dart';
import 'data/content.dart';
import 'data/titles.dart';
import 'data/format.dart';
import 'data/items.dart';
import 'design/tokens.dart';
import 'state/host_state.dart';
import 'state/goal.dart';
import 'state/goal_gen.dart';
import 'state/plan_failure.dart';
import 'design/fidelity.dart';
import 'state/app_clock.dart';
import 'state/away.dart';
import 'state/haptics.dart';
import 'state/sfx.dart';
import 'state/voice.dart';
import 'state/save_file.dart';
import 'state/quest.dart';
import 'state/quest_flow.dart';
import 'state/result.dart';
import 'ui/ref/ref_bg.dart';
import 'ui/ref/ref_board.dart';
import 'ui/ref/ref_core.dart';
import 'ui/ref/ref_boot.dart';
import 'ui/ref/ref_motion.dart';
import 'ui/ref/ref_exec.dart';
import 'ui/ref/ref_goal_swap.dart';
import 'ui/ref/ref_loading.dart';
import 'ui/ref/ref_home.dart';
import 'ui/ref/ref_device.dart';
import 'ui/ref/ref_hud.dart';
import 'ui/ref/ref_ach.dart';
import 'ui/ref/ref_archive.dart';
import 'ui/ref/ref_llm_settings.dart';
import 'ui/ref/ref_main.dart';
import 'ui/ref/ref_onboard.dart';
import 'ui/ref/ref_sheet.dart';
import 'ui/ref/ref_shop.dart';
import 'ui/ref/ref_tray.dart';
import 'ui/ref/ref_overlays.dart';
import 'ui/ref/ref_verdict.dart';
import 'widgets/fail_layer.dart';
import 'widgets/fx_layer.dart';
import 'widgets/fx_particles.dart';
import 'widgets/hud.dart';
import 'widgets/line_layer.dart';
import 'widgets/rail_base.dart' show railReduceMotion;
import 'widgets/table_overlay.dart';
import 'dev/agent_bridge.dart';

/// 宿主 SYSTEM —— Flutter 客户端。
/// 设计真源：prototype/opus-v2-dir（原型即规格）。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  // 原型是全屏手机，没有系统栏
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // Agent 桥接：debug 构建下全局开语义树，让 uiautomator dump 读得到中文标签
  AgentBridge.enableSemantics();
  runApp(const SysApp());
  // 首帧后把组件树打到日志（logcat 可抓：adb logcat -s flutter）
  if (AgentBridge.enabled) {
    WidgetsBinding.instance.addPostFrameCallback((_) => AgentBridge.logTree());
  }
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

/// 投影面板/整页的口子。参考稿把「档案 / 补给」做成独立场景，
/// 「系统设置」做成底部抽屉（#sheet）—— 这里用同一个枚举分流。
enum SheetKind { system, archive, supply }

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
  /// t16/B3：读档恢复了执行中单据 → 唤醒后直接回执行页（计时按 startAt 推导）
  bool _resumedExec = false;

  /// 行为逻辑未定，先用与原型「老宿主 · 第 23 天」一致的演示档
  /// （启动时会被存档覆盖 —— 见 SaveFile）
  HostState _host = HostState.demo;

  /// 业务唯一真源：队列 / 接单 / 道具 / 结算 / 认输（store.js 移植，quest_flow.dart）。
  /// 「提交卡死」根因①②的修复点：提交不再只是切页面，而是经 `_flow.settle()`
  /// 产出真实结算并落到档案 / 主线 / 队列。
  late QuestFlow _flow = _demoFlow();

  /// 演示档的 Flow —— 声明式字段初始化器里不能调实例方法，
  /// 所以包一层：既拿 demo 队列，也把收官钩子接上（钩子走 Agent，非静态）。
  QuestFlow _demoFlow() {
    final QuestFlow f = QuestFlow.demo();
    _wireFlow(f);
    return f;
  }

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

  /// 接上「收官 → 下一条主线」的钩子（TODO-01）。
  /// **每一个** QuestFlow 实例都要过这一道 —— 读档/重置/重新绑定都会换实例，
  /// 漏一个就会出现「这条主线走完就没单了」。
  void _wireFlow(QuestFlow f) {
    // ⚠️ 2026-10-23：钩子改 async 且**不许返回 null**。
    //   旧版是同步 `buildNextGoal(...)` 走类别模板 —— 收官后的下一份计划
    //   永远是模板。现在走同一条 Agent 链路（匹配 + 拆解 + 规则校验），
    //   失败会从这里抛到 `settle()` 的调用方。
    f.nextGoalHook = (Goal prev, int cleared, int total, int level) =>
        _buildGoalWithAgent(
          text: prev.text,
          // O-2 裁决（宿主 2026-10-10）：「立目标时刻」**沿用**上一目标 ——
          // goal.at 代表「这条主线是什么时候立的」，走完一条再续一条时
          // 把它改成"现在"会让「主线已立 N 天」这类读数跳变。
          at: prev.at,
          answers: prev.interview,
        );
  }

  /// 存档（store.js L34-52）
  final SaveFile _save = SaveFile();

  /// 口型包络（audio.js L180-230）—— 打字机逐字喂它，波形条读它。
  final VoiceEnvelope _voice = VoiceEnvelope();

  /// 主线全景里展开的是哪一环（null = 没展开，只有抬头）
  int? _pickedTask;

  /// 绑定仪式的输入框
  final TextEditingController _ask = TextEditingController();

  /// ── 绑定流多幕（docs/18 §2.1 · t8 装配）────────────────────────
  ///
  /// 第 0 幕 = 问目标（AskField）；[_interviewCat] 非空 = 第 1 幕访谈卡
  /// （t4 的 InterviewDeck，按目标类型出 3~5 张）；答完 → `_buildGoalWithAgent`
  /// 落 3 天 3 环 E/D/C + 见面礼双倍卡 → 大厅（首单已在队列）。
  GoalCategory? _interviewCat;

  /// 访谈要定的那句话（第 0 幕收进来的目标原文）
  String _pendingGoalText = '';

  /// ── 换目标（TODO-01 · 主线页入口）──────────────────────────────
  ///
  /// 主线页「换目标」→ 这一层问一句新目标 → `QuestFlow.newGoal` 落库
  /// （旧主线单移除、新主线钉队首）。换目标**不动等级/金币/六维**，
  /// 只换那条路 —— 她认账，但不重开。
  bool _goalChangeOn = false;
  final TextEditingController _goalAsk = TextEditingController();

  /// 换目标页 sysbox 里她的那句（页内常驻，不随 `_aside` 到点收掉）；
  /// token 每变一次重播打字机
  String? _swapLine;
  int _swapLineTok = 0;

  void _swapSay(String text) => setState(() {
    _swapLine = text;
    _swapLineTok++;
  });

  /// ── 拆解加载态（docs/49 D）────────────────────────────────────
  ///
  /// 正在等 LLM 的那一件事（null = 没在等）。同一时刻只有一件：绑定页 /
  /// 换目标页 / 收官结算的加载卡都读它；它也是「防连点」的闸门。
  /// 完成后**按身份**清（`identical(_planJob, job)`）——中途被取消 / 重置时，
  /// 迟到的回包不会把新的那件事清掉。
  _PlanJob? _planJob;

  /// [_buildGoalWithAgent] 每进一步调一次：加载卡的分步进度跟着真实阶段走
  void _planStageTo(int n) {
    final _PlanJob? j = _planJob;
    if (!mounted || j == null || j.stage == n) return;
    setState(() => j.stage = n);
  }

  /// 分段拆解的进度（加载卡第 2 步显示「3/8 段」）
  void _planSegTo(int done, int total) {
    final _PlanJob? j = _planJob;
    if (!mounted || j == null) return;
    setState(() {
      j.segDone = done;
      j.segTotal = total;
    });
  }

  /// 给某几类任务出加载卡（不是这几类 → null，页面照常显示表单）
  Widget? _planLoadingFor(Set<_PlanJobKind> kinds, {Color accent = Ref.acid}) {
    final _PlanJob? j = _planJob;
    if (j == null || !kinds.contains(j.kind)) return null;
    return RefPlanLoading(
      key: ObjectKey(j), // 新的一件事 = 新的计时
      steps: j.steps,
      stage: j.stage,
      title: j.title,
      goal: j.goal,
      startedAt: j.at,
      accent: accent,
    );
  }

  /// 换日游标：上次补发日常的那一天（原型 `S.day`；清晨首次进入补发）
  DateTime? _lastRollDay;

  /// 亮帧：白 16% / 180ms ease-out（docs/08 逐帧里的「亮帧」）
  late final AnimationController _flashC = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  /// 屏幕空间特效（#fx 画布）
  final FxController _fx = FxController();

  /// 认输按住的进度（原型用它驱动 #veil 的暗度：p × .75）。
  ///
  /// ⚠️ 用 ValueNotifier 而不是 setState：按住期间**每帧**都在变，setState
  ///    会让整个 AppShell（天幕 / HUD / 执行页…）每帧重建（docs/49 E5）。
  ///    现在只有暗幕那一小块跟着重建。
  final ValueNotifier<double> _quitP = ValueNotifier<double>(0);

  /// 点一下跳过打字机（原型 Tap.next()）
  int _tap = 0;

  /// 震屏
  int _shake = 0;
  double _shakePx = 4;

  /// 亮帧的颜色与峰值强度（按事件不同）
  Color _flashColor = Colors.white;
  double _flashA = .16;

  /// 横幅（称号/道具到手时从顶上滑下来）

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

  /// 每说一句 +1（主线 sysbox 据此覆盖台词）
  int _asideToken = 0;
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

  /// 临时台词的情绪（喂给 RefCore / 气泡的逐字音节）

  /// 文案接管后的 LLM 台词（null = 还没接到/回退原句）

  /// 最近一次拆解失败（null = 没失败过）。
  ///
  /// 2026-10-23：拆解**不再有兜底**，失败必须看得见 —— 这个字段是给
  /// 诊断横幅 / 设置页 / 测试读的唯一入口。它**不影响**游戏状态：
  /// 失败时目标、队列、存档一律不动。
  PlanFailure? _planError;

  /// 聊天消息 id（会话内唯一即可）
  int _chatSeq = 0;
  String _chatId() => 'm${DateTime.now().microsecondsSinceEpoch}_${_chatSeq++}';

  /// LLM 网关 + 文案/聊天服务（initState 异步装配；没配 Key 也能跑，全走兜底）
  SystemCopyProvider? _copy;

  /// 立主线的 agent 循环（docs/34）：她 get_status → set_plan → 解释。
  /// 没配 Key / 她没交 / 循环用尽 → **抛**（不再退回类别模板）
  PlanAgent? _planAgent;
  GoalMatchAgent? _matchAgent;
  ChatService? _chatService;

  /// 当前 LLM 客户端（TODO-07 网关热更：设置变更时关旧建新，连接池不泄漏）
  LlmClient? _llmClient;

  /// agent 工具（docs/19 §A3）：真实适配器 + 注册表——聊天 function calling
  /// 与快捷 chip 共用这一份；配了 Key 走 LLM 工具循环，没配 Key 只走 chip。
  AgentToolRegistry? _agentTools;

  /// 对白节奏（docs/22 §R4）：设置页三档（慢 42 / 标准 34 / 快 24）→
  /// [LineLayer] 字幕与 [ChatPanel] 气泡的打字机共用这一个值。
  int _paceMs = AgentSettings.kDefaultPaceMs;

  /// 小祥的长期记忆（访谈答案写这里 —— 访谈即第一批记忆，docs/18 §2.1③）
  MemoryStore? _memory;

  /// 小祥装配：设置 → LLM 网关 → 文案/聊天服务 + 聊天历史读档。
  /// 装配本身只跑一次，但网关不装死（TODO-07，docs/20 遗留观察①）：
  /// [_onSettingsChanged] 订阅 SettingsStore 类级广播，设置页改
  /// Key/BaseURL/模型名后**当场重建**客户端与两个服务，免重启。
  Future<void> _initAgent() async {
    final AgentSettings s = await SettingsStore().load();
    await _chat.load();
    if (!mounted) return;
    _applyAgentSettings(s);
    // 热更订阅：设置页 save()（文本防抖 400ms、开关即时、关面板兜底写
    // 最后一笔）→ 广播到这里 → [_applyAgentSettings] 按需重建。退订在 dispose。
    SettingsStore.addListener(_onSettingsChanged);
  }

  /// 设置变更入口（SettingsStore 广播）→ 重建网关/客户端/聊天与文案服务。
  /// 记忆与工具注册表跟 LLM 配置无关，原样沿用——改 Key 不让访谈记忆蒸发。
  void _onSettingsChanged(AgentSettings s) {
    if (!mounted) return;
    _applyAgentSettings(s);
  }

  /// 用一份 [AgentSettings] 装（或重装）LLM 三件套，**并落地非 LLM 设置**。
  ///
  /// ⚠️ 早退守卫只对 LLM 三要素 + 严格模式生效（那些变更才需要重建网关）。
  /// 音效/震动/思考档位这类**非 LLM 设置必须每次都落地**——docs/22 R3 记着
  /// 这个坑：以前 `sound/haptic` 能存能显但没人消费，就是被这个早退吞掉的。
  void _applyAgentSettings(AgentSettings s) {
    _agentSettings = s;
    // ① 非 LLM 设置：先落地（幂等，重复调用无害）
    Sfx.enabled = s.sound;
    Haptics.enabled = s.haptic;
    // docs/48 §5：画质档 / 界面音量 —— 与 sound/haptic 同理，每次都落地
    Fidelity.lowPower.value = s.fidelity == 'low';
    Sfx.userGain = AgentSettings.gainOf(s.sfxVol);
    // 对白节奏（docs/22 §R4）与 sound/haptic 同理：**必须在下面的 LLM 早退守卫之前落地**，
    // 否则"只改节奏"会被整段吞掉（正是 R3 记的「能存能显没人消费」那个坑）
    if (_paceMs != s.paceMs) setState(() => _paceMs = s.paceMs);
    // 底噪跟随「音效」总开关（docs/22 R3 的化简：原型按时刻 duck，本批只做在/不在）
    unawaited(Sfx.ambient(s.sound));
    // ② LLM 设置：没变就不重建（避免打断在途请求）
    final bool strict = _strictOf(s);
    final LlmClient? old = _llmClient;
    if (old != null &&
        old.config.baseUrl == s.baseUrl &&
        old.config.apiKey == s.apiKey &&
        old.config.model == s.model &&
        old.config.reasoningEffort == s.reasoningEffort &&
        old.config.strict == strict &&
        _chatService?.strict == strict) {
      return;
    }
    final LlmClient client = LlmClient(
      config: LlmConfig(
        baseUrl: s.baseUrl,
        apiKey: s.apiKey,
        model: s.model,
        reasoningEffort: s.reasoningEffort,
        strict: strict,
      ),
    );
    final LlmGateway gw = LlmGateway(client);
    final MemoryStore mem = _memory ?? MemoryStore();
    // 工具读的是「当前那份」QuestFlow——绑定/读档会换实例，必须传取流回调
    final AgentToolRegistry reg =
        _agentTools ??
        defaultAgentTools(
          context: QuestFlowAdapter(
            flowOf: () => _flow,
            onChanged: _onAgentMutated,
          ),
          memory: mem,
        );
    old?.close(); // 在途请求被中断 → LlmClient 折叠成 failure → 调用方兜底
    setState(() {
      _llmClient = client;
      _memory = mem;
      _copy = SystemCopyProvider(llm: gw, memory: mem);
      _planAgent = PlanAgent(client: client, memory: mem);
      _matchAgent = GoalMatchAgent(client: client, memory: mem);
      _agentTools = reg;
      _chatService = ChatService(
        gateway: gw,
        memory: mem,
        client: client,
        tools: reg,
        strict: strict,
      );
    });
  }

  /// 严格模式（docs/22 §2.0，宿主 2026-10-10 拍板）：
  /// - `auto`（默认）：**debug / profile 构建**下失败直接报错、不产假台词；
  ///   release 仍走兜底（无 Key / 断网不得阻塞使用），但会标注原因。

  /// 严格模式（docs/22 §2.0，宿主 2026-10-10 拍板）：
  /// - `auto`（默认）：**debug / profile 构建**下失败直接报错、不产假台词；
  ///   release 仍走兜底（无 Key / 断网不得阻塞使用），但会标注原因。
  /// - `on` / `off`：设置页手动覆盖（便于在 release 上验证严格模式）。
  static bool _strictOf(AgentSettings s) => switch (s.strictMode) {
    'on' => true,
    'off' => false,
    _ => kDebugMode || kProfileMode,
  };

  /// 工具改了队列/计划之后：同步档案副本 + 存档（QuestFlowAdapter.onChanged）
  void _onAgentMutated() {
    if (!mounted) return;
    setState(() {
      _host = _flow.host;
      _goal = _flow.goal;
    });
    _persist();
  }

  /// 打开对话层。[scenario] 传场合上下文（结算复盘 / 换目标），只影响她接下来的回复
  void _openChat({String? scenario}) {
    setState(() {
      _chatScenario = scenario;
      _chatOpen = true;
    });
  }

  /// 发送一条：宿主气泡立刻上屏 → 思考中 → 她的回复（LLM/兜底；配了 Key
  /// 且接了工具时走 function calling，〔工具〕系统条目逐条上屏）→ mood 联动
  Future<void> _sendChat(String text) async {
    final ChatService? svc = _chatService;
    if (svc == null || _chatThinking) return;
    await _chat.append(ChatMessage.host(_chatId(), text));
    setState(() => _chatThinking = true);
    final List<ChatMessage> entries = await svc.respond(
      text,
      history: _chat.messages,
      scenario: _chatScenario,
      statusLine: ChatService.statusLineOf(
        name: _host.name,
        lv: _host.lv,
        streak: _host.streak,
        queue: _host.queue,
        goalShort: _goal.short,
        // 环进度喂给她（验收 F-3）：不喂她会从旧工具回执里捡过期数字
        planDone: _goal.doneCount,
        planTotal: _goal.plan.length,
      ),
    );
    if (!mounted) return;
    setState(() => _chatThinking = false);
    for (final ChatMessage m in entries) {
      await _chat.append(m);
    }
    if (!mounted) return;
    setState(() {});
    // emotion 标签 → 舞台 mood（docs/18 §2.6 演出联动）
    // docs/24 #18：情绪强烈的连带一个兜底动作（react），不再只换脸
  }

  /// 快捷 chip 直调工具（docs/19 §A3）：不经 LLM、全部本地可用；
  /// 结果以〔工具〕系统条目写入聊天历史（UI 可见），改动随 onChanged 落档。
  Future<void> _onQuickTool(String tool) async {
    final AgentToolRegistry? reg = _agentTools;
    if (reg == null || _chatThinking) return;
    setState(() => _chatThinking = true);
    final ToolOutcome oc = await reg.execute(tool);
    await _chat.append(
      ChatMessage.sys(_chatId(), '${ChatService.toolTag}${oc.message}'),
    );
    if (!mounted) return;
    setState(() => _chatThinking = false);
    setState(() {});
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

  /// 追问：绑定仪式的问目标（LLM 回了才顶掉 LINES.askGoal）
  Future<void> _takeProbeLine(String topic) async {
    final SystemCopyProvider? copy = _copy;
    if (copy == null) return;
    // docs/24 #2/#13 追问：歪头疑问（question + exp_serious02）
    final CopyLine line = await copy.probeLine(
      CopyContext.fromState(host: _host, goal: _goal),
      topic: topic,
    );
    if (!mounted || _moment != Moment.onboard) return;
    if (line.source == CopySource.llm) {
      setState(() => _probeLine = line.text);
    }
  }

  /// 「换目标」的场合上下文（docs/18 §2.7：旧主线环清空、队列主线单撤下
  /// 的确认语义由换目标流程负责，这里先让对话带着这个话题开起来）。
  /// 带上当前主线与进度 —— 她追问「为什么换」时要引用真实数据。
  String get _newGoalScenario =>
      '换目标：宿主在主线页按了「换目标」。他现在的目标是「${_goal.text}」'
      '（${_goal.doneCount}/${_goal.plan.length} 单）。先追问为什么换、'
      '新目标是什么；提醒他：旧主线环会清空、队列里的主线单会撤下，想清楚再动。';

  /// ── 换目标（TODO-01 · 主线页入口）──────────────────────────────

  /// 点「换目标」→ 斜切进换目标页（旧主线单先不动，说清楚再动）。
  void _beginGoalChange() {
    if (_busy || _goalChangeOn) return;
    unawaited(
      _go('swap', () {
        setState(() {
          _goalChangeOn = true;
          _pickedTask = null;
          _planError = null;
          _goalAsk.clear();
        });
        // docs/24 #17 换目标：她先琢磨一下
        _swapSay('要换？那就说清楚换成什么。[旧的那条]，说换就换。');
      }),
    );
  }

  /// 换目标输入框里那颗「先问小祥」的暗号（她接管追问，落库仍走 [newGoal]）
  static const String _kAskXiangPreset = '先问小祥';

  // ⚠️ 2026-10-23 删除：`kPlanWaitOnConsume`(4s) / `kPlanWaitOnChangeGoal`(15s)。
  //    这两个"等待上限"就是静默降级的闸门：到点没等到就退回类别模板。
  //    现在没有模板可退，所以也没有等待上限 —— 请求慢就慢，失败就报。

  /// 「先问小祥 ›」：带场合上下文开对话（**不填输入框、不落库**）。
  /// 换目标页留在原地 —— 聊完关掉对话层，回来接着填。
  void _enterAskXiang() {
    FocusScope.of(context).unfocus();
    _openChat(scenario: _newGoalScenario);
  }

  /// 新目标提交 —— **全程 fail fast**。
  ///
  /// 2026-10-23 宿主定调：这里原来有「预取 + 等 15 秒 + 取不到就退回类别模板」
  /// 三层降级，正是「两周内骑自行车 10 次」被铸成模板清单的原因。
  /// 现在：
  ///   ① 空泛 → 前置校验拦下（输入侧规则，不是生成兜底）
  ///   ② 匹配类别/短字/期限 → `GoalMatchAgent` 调 `set_goal_category`
  ///   ③ 拆解任务 → `PlanAgent` 调 `set_plan`
  ///   ④ 规则校验 → `buildGoalFromPlan`（不合格就抛）
  /// 任何一步失败都走 [_failPlan]：**不落库、不改目标**，把原因摆在屏幕上。
  ///
  /// docs/49 C/D：等待期间换目标页整块换成加载卡（三步进度跟着真实阶段走）；
  /// 宿主中途点 × 走掉 → 这一件作废，迟到的回包直接丢弃。
  Future<void> _onGoalChangeSubmitted() async {
    if (_planJob != null) return; // 正在拆：不收第二次
    FocusScope.of(context).unfocus();
    final String typed = _goalAsk.text.trim();
    // 「先问小祥」不是目标，是入口：带场合上下文开对话（D5 的入口保留）
    if (typed == _kAskXiangPreset) {
      _enterAskXiang();
      return;
    }
    if (isVagueGoal(typed)) {
      unawaited(Sfx.play('error'));
      _swapSay('太空了。说点具体的——[一句话]。');
      return;
    }
    final Goal prev = _flow.goal;
    final _PlanJob job = _PlanJob(_PlanJobKind.swap, typed);
    // 新的尝试开始 → 上一次的失败读数清掉（成功时不至于挂着旧错误）
    setState(() {
      _planError = null;
      _planJob = job;
    });
    unawaited(Sfx.cue('ui.open'));
    _swapSay('……行，让我把这条拆开。[别催]。');
    try {
      final Goal next = await _buildGoalWithAgent(
        text: typed,
        // ⚠️ 2026-10-23 真机修正：**换目标 = 新的一条路**，期限从今天起算。
        //
        // 旧口径沿用了 O-2 的「立目标时刻沿用上一目标」，于是刚建好的
        // 14 天计划一出生就写着「已过 11/14 天 · 剩 3 天」——目标不可执行
        // 的观感有一半来自这里。O-2 要保的是**同一条主线的读数不跳变**，
        // 换了一句话就不是同一条线了。
        at: DateTime.now(),
      );
      // 等待期间宿主可能取消了 / 又换了目标 / 重置了存档 —— 对不上就整件事作废
      if (!mounted ||
          !identical(_planJob, job) ||
          !identical(_flow.goal, prev)) {
        return;
      }
      _flow.newGoal(next);
      setState(() {
        _planJob = null;
        _host = _flow.host;
        _goal = _flow.goal;
        _pickedTask = null;
      });
      _persist();
      unawaited(Sfx.play('unlock'));
      // 斜切回主线页：新清单按 goal.id 换 key → 发牌入场
      unawaited(
        _goOrNow('main', () {
          setState(() {
            _goalChangeOn = false;
            _goalAsk.clear();
            _boardOn = false;
            _mainJustDone = null;
            _moment = Moment.main;
          });
          // docs/24 #17 换目标落库：正色点头（nod + exp_serious02）
          _sayAside(
            '行。旧的撤了，新清单 [[${_goal.plan.length} 单]] 已经在你手上。'
            '「$typed」——别又三天热度。',
            holdMs: 3000,
          );
        }),
      );
    } catch (e) {
      if (!mounted || !identical(_planJob, job)) return;
      setState(() => _planJob = null);
      unawaited(Sfx.play('error'));
      _failPlan(_asPlanFailure(e), goalText: typed);
      _swapSay('拆不动。[换个说法]再来，或者先问问我。');
    }
  }

  /// 拆解链路上**任何**异常都要落成可见的失败（docs/49 F）。
  ///
  /// 原来只 `on PlanFailure`：链路里冒出别的异常（StateError / 类型错 / 插件异常）
  /// 时 catch 不住，加载卡会永远挂在屏幕上 —— 看起来就是「拆解一直不结束」。
  static PlanFailure _asPlanFailure(Object e) => e is PlanFailure
      ? e
      : PlanGenerationError(PlanFailureCode.badResponse, '意外异常：$e');

  /// 匹配 + 拆解 = 一次完整的目标铸造。**失败一律抛**，由调用方决定怎么显示。
  ///
  /// 两步都是 Agent 调 tool：
  ///   · `GoalMatchAgent` → `set_goal_category`（类别 / 短字 / 期限）
  ///   · `PlanAgent`     → `set_plan`（任务池，schema 固定）
  /// 最后 `buildGoalFromPlan` 跑规则校验（条数/档位/时限），不合格同样抛。
  Future<Goal> _buildGoalWithAgent({
    required String text,
    required DateTime at,
    bool firstGoal = false,
    Map<String, String> answers = const <String, String>{},
  }) async {
    final PlanAgent? planner0 = _planAgent;
    final GoalMatchAgent? matcher0 = _matchAgent;
    if (planner0 == null || matcher0 == null) {
      throw const PlanGenerationError(
        PlanFailureCode.noKey,
        'Agent 还没装配好（_initAgent 未完成 / 没配 Key）',
      );
    }
    final String? status = firstGoal ? null : _statusLineForAgent();

    // ① 匹配：类别 / 天幕短字 / 期限
    //
    // ⚠️ 2026-10-28（docs/49 F）：两步都**只挂交卷工具**，不再挂 get_status /
    //    recall。宿主档案（[status]）与相关记忆（MemoryStore.digest）本来就写进
    //    了系统提示，查询工具只会多出一整轮「先查档案」的往返 —— 推理模型一轮
    //    10~40s，换目标原来至少 4 轮串行，真机实测 2 分钟还没拆完。
    _planStageTo(0);
    final GoalMatchDraft matchDraft = GoalMatchDraft();
    final StrictAgentToolRegistry matchTools = StrictAgentToolRegistry();
    matchTools.register(setGoalCategoryTool(goalText: text, draft: matchDraft));
    final GoalMatch m = await matcher0.match(
      goalText: text,
      tools: matchTools,
      draft: matchDraft,
      statusLine: status,
    );

    // ② 拆解：按匹配出的**期限或次数配额**要任务（规则在 goal_gen）
    //
    // ⚠️ 2026-10-23 真机事故：原来只按「期限天数」要任务，于是
    // 「两周内骑自行车 10 次」要了 14 张，模型只能写成「第1..14次骑行」，
    // 末张还自相矛盾地写「第14次骑满120分钟并交全部10次轨迹」。
    // ⚠️ 首目标的期限**由规则定死**（`kFirstGoalDays` = 3，docs/05），不该
    //    跟着模型的 `set_goal_category.days` 走 —— 真机实测模型会给 30 天，
    //    于是提示词里出现自相矛盾的两句话（「期限 30 天，清单要正好 30 张」
    //    与「这是首目标：3 张」），`validatePlan` 必然抛 badPlan。
    //    非首目标仍按模型给的期限/配额。
    final int days = firstGoal ? kFirstGoalDays : m.days;
    final int need = planTaskCountFor(days, quota: m.quota);
    _planStageTo(1);
    // docs/49 F3：长清单（条数 = 天数，三个月就是 90 张）分段并行拆，
    // 每段一套独立的 set_plan；拼回后下面的 buildGoalFromPlan 仍全量复核。
    final List<TaskSpec> tasks = await planner0.generateTasks(
      brief: PlanBrief(
        goalText: text,
        days: days,
        taskCount: need,
        cat: m.cat,
        interview: answers,
        statusLine: status,
        firstGoal: firstGoal,
      ),
      quota: m.quota,
      onProgress: _planSegTo,
    );

    // ③ 规则校验 + 铸计划（校验不过会抛 PlanRuleError）
    _planStageTo(2);
    return buildGoalFromPlan(
      text: text,
      short: m.short,
      cat: m.cat,
      days: days,
      quota: m.quota,
      tasks: tasks,
      answers: answers,
      at: at,
      firstGoal: firstGoal,
    );
  }

  /// 拆解失败的**唯一出口**：不落库、不改目标，把原因直接摆到屏幕上。
  ///
  /// 旧版这里什么都不做（`return null` → 走模板），于是失败不可见。
  /// 现在：横幅（开发者一眼看到 code）+ 字幕（人可读原因）+ debugPrint。
  void _failPlan(PlanFailure e, {String goalText = ''}) {
    debugPrint(
      '[plan] ❌ ${e.code.name} · ${e.detail}'
      '${goalText.isEmpty ? '' : ' · goal=「$goalText」'}',
    );
    setState(() {
      _planError = e;
    });
    _sayAside('拆解失败：${e.code.name}。${_clip(e.detail, 60)}', holdMs: 6000);
  }

  /// 换目标中途算了：什么都不动，斜切回主线页。
  /// 拆解还在等也照样能走 —— 那一件作废（[_onGoalChangeSubmitted] 按身份丢弃回包）。
  void _cancelGoalChange() {
    if (!_goalChangeOn) return;
    FocusScope.of(context).unfocus(); // 键盘一并收起（宿主验收）
    unawaited(
      _goOrNow('main', () {
        setState(() {
          _goalChangeOn = false;
          _goalAsk.clear();
          _planError = null;
          if (_planJob?.kind == _PlanJobKind.swap) _planJob = null;
        });
        _sayAside('没换。……明智。', holdMs: 1600);
      }, back: true),
    );
  }

  /// 上一次宿主操作（原型 `App.lastAct`）
  DateTime _lastAct = DateTime.now();

  /// 进执行态时把计时归零重算（原型 `Store.accept()` 里记 startAt）
  void _beginExec() {
    // 参考稿 startTask → go('exec')：接单这一拍走斜切转场
    unawaited(_go('exec', _beginExecNow));
  }

  void _beginExecNow() {
    // 真实接单：队首出队 + 记 startAt（原型 `Store.accept`；D12 修复
    // —— 计时不再写死"已执行 7 分钟"）
    final Quest? head = _flow.head;
    if (head != null) _flow.accept(head);
    // 原型 `App.dispatch()` 接单那一拍：Stage.motion('nod')
    // （docs/24 #4：nod 现在自带 exp_serious02 正色脸）
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
    // docs/24 #5 执行中：落进思考脸一次（低频、不打扰；之后交给待机池）
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
      // 参考稿 renderTray：装上之后托盘不收，卡片抬起转正（再点暗幕收起）
    });
    if (say != null) unawaited(Sfx.play('coin'));
    if (say != null) _sayAside(say, holdMs: 1800);
  }

  /// 她插一句（`hold` 之后自己收）
  ///
  /// [busy] 对应原型的 `App.run()`：她说「回来那几句」是**多拍演出**，
  /// 整段持有 `busy`，期间点别处一律没反应（flows.js L26 / L171）。碎碎念不持有。
  /// [holdMs] 不给就按原型的默认算（`clamp(420 + 字数*42, 900, 2400)`，见 `LINES.defaultHold`）。
  /// ⚠️ 原型每个调用点几乎都显式给了 hold，而且都很短（200~900ms）；
  ///    只有"回来的那几句"不给 —— 那几句就必须走这个默认。
  ///
  /// [emotion] 只给「戳她」这类需要逐字音节情绪的行用（原型
  /// `Line.say(text, {emo})`：情绪同时喂表情与电子音节）。
  void _sayAside(
    String text, {
    int? holdMs,
    bool busy = false,
    String? emotion,
    VoidCallback? onDone,
  }) {
    final int hold = holdMs ?? LINES.defaultHold(text);
    setState(() {
      _aside = text;
      _asideToken++;
      _asideUntil = DateTime.now().add(Duration(milliseconds: hold));
      if (busy) _busy = true;
    });
    if (onDone != null) {
      _asideDone?.cancel();
      _asideDone = Timer(Duration(milliseconds: hold), onDone);
    }
  }

  /// 当前临时台词的情绪（喂 [LineLayer.emotion] 的逐字音节）

  /// 换目标输入框的焦点（弹键盘用；临时调试扩展 ext.sys.goalchange 也用它）
  final FocusNode _goalAskFocus = FocusNode();

  /// 临时台词结束后的回调（原型 `Line.say(...).then(...)`）
  Timer? _asideDone;

  /// ═══ 戳她（原型 flows.js L646-654 `poke()`）═══════════════════════
  ///
  /// 点在大厅那颗系统核心上 → 越戳越恼：第 1~3 戳 tsun，
  /// 第 4 戳 annoyed，第 5 戳起 cold；台词是 content.js L319 那五句。
  /// 第 5 戳起 cold 且动作换 `fluster`；台词是 content.js L319 那五句。
  /// 20 秒不戳，连戳计数归零（原型的 `_pokeReset`）。
  /// ⚠️ 只留「连戳」计数（决定台词/动作档位）；原型另存过一个累计数
  /// `S.pokes`，但界面从未展示 —— 不留死数据。
  int _pokeN = 0;
  Timer? _pokeReset;

  /// 大厅核心的脸（参考稿 setMood）：戳到第 4 下转 angry，3.2s 后回 neutral。
  CoreMood _coreMood = CoreMood.neutral;
  Timer? _coreMoodReset;

  void _poke() {
    final int i = math.min(LINES.poke.length - 1, ++_pokeN - 1);
    unawaited(
      Sfx.play('boop', variant: math.min(_pokeN, 8)),
    ); // 参考稿 boop(min(pokes,8))：越戳越尖
    unawaited(Haptics.buzz('poke'));
    final String emo = i >= 4
        ? 'cold'
        : i >= 2
        ? 'annoyed'
        : 'tsun';
    // 越戳越恼：第 4 下起红眼（.core.angry，L123）
    setState(() => _coreMood = i >= 3 ? CoreMood.angry : CoreMood.neutral);
    _coreMoodReset?.cancel();
    _coreMoodReset = Timer(const Duration(milliseconds: 3200), () {
      if (mounted) setState(() => _coreMood = CoreMood.neutral);
    });
    // 说完把那句情绪收回去（原型 `.then`: 大厅里回 mood 或 neutral）
    _sayAside(
      LINES.poke[i],
      holdMs: 1500,
      emotion: emo,
      onDone: () {
        if (!mounted || _moment != Moment.lobby) return;
      },
    );
    _pokeReset?.cancel();
    _pokeReset = Timer(const Duration(seconds: 20), () {
      _pokeN = 0;
      if (mounted) setState(() => _coreMood = CoreMood.neutral);
    });
  }

  void _onSecond() {
    final DateTime now = DateTime.now();
    // docs/24 #15 打瞌睡：大厅里 80s 没人理 → 睡（`ChatterScheduler.dozeAfter`；
    // 原型 `App.doze()`。睡姿 = speed 0 + exp_sys_sleep，任意触碰唤醒）
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
    final bool lobby = _moment == Moment.lobby;
    final bool dispatch = _moment == Moment.dispatch;
    final bool exec = _moment == Moment.exec;
    final bool result = _moment == Moment.result;
    final bool fail = _moment == Moment.fail;
    final bool sheet = _moment == Moment.sheet;
    final bool onboard = _moment == Moment.onboard;

    final bool main = _moment == Moment.main;
    final bool boot = _moment == Moment.boot;
    // focus+dim：派单与结算都会把 HUD/底栏收走、天幕压暗
    final bool dim = dispatch || result;

    // docs/39 §5.5：减弱动态效果 —— **一次读、两处传**。
    // 这条读取原先只在牌桌/滑轨/牌屉/ask 层内部各读一遍，FX 两层的
    // `reduceMotion` 形参于是从来没有人喂（组件写好了降级，调用点漏了）。
    // 口径统一用 rail_base 的 railReduceMotion（= maybeDisableAnimationsOf），
    // 读一次放在 build 顶部：AnimatedBuilder 的 builder 里那个 context 也能读，
    // 但一层层传容易再度漏掉，而且每帧多读一次没意义。
    final bool reduce = railReduceMotion(context);

    return Scaffold(
      backgroundColor: C.voidBg,
      // ⚠️ **不能让整屏随键盘缩**（默认 true 就会缩）。原因：
      //   · 舞台的矩形是按 LayoutBuilder 的可用高度算的 —— 键盘一弹，
      //     矩形尺寸就变 → 插件 iOS 侧重建设 FBO（排空渲染队列）+ 她整条位移；
      //   · 环场/命中层用的是 `MediaQuery.sizeOf`（整窗高），跟舞台对不上，
      //     于是"她"和"环"会错位（宿主截图里那种错乱）。
      // 代价：输入框要自己抬到键盘上面（`AskField.bottomInset`）。
      resizeToAvoidBottomInset: false,
      // v3 设备壳（参考稿 L38-39）：手机全屏；窗口变宽时钳成 430×920
      // 的「手机比例」并加 44 圆角外框 —— 这样宽窗下不是把 UI 拉扁，
      // 而是保持稿子的比例居中。
      body: RefDeviceFrame(
        accent: _sceneAccent,
        // 参考稿 L1667-1668：任意按下 → 场景色小爆点 + 28px 光环。
        // 挂在祖先上（不是 Stack 里的兄弟）：兄弟节点只收得到空白处的点。
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: reduce ? null : _tapFx,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // ⚠️ 系统返回键 = **逐级返回**（docs/39 M-04；2026-10-17 前全库只有
              //    失败页接得住它，其余时候 Android 返回键直接退出 App）。
              //    优先级写死在 [_popScopeTarget]：失败页 > 牌屉 > 主线 > 默认。
              //
              //    失败页那一档的来历：「永远有补救」不能只押在那两张铭牌上：
              //    2026-10-11 的死局恰恰是铭牌自己把自己拆了（见 `_onChoice` 与
              //    `Choices._confirm` 的注释）—— 返回键是最后一道门，跟演出闸门、
              //    跟任何锁都无关。
              //
              //    形态说明：`PopScope` 只要挂在**这一条路由里**就会生效（它向
              //    `ModalRoute` 注册一个 pop entry），不需要包住任何东西 ——
              //    所以这里用一颗 0×0 的空壳当挂点：整棵 build 树**一行缩进都不动**
              //    （包住 Scaffold 的话，`dart format` 会把 600+ 行全部重排）。
              //
              //    ⚠️ 只此一颗：`canPop` 为真时系统自己 pop（退到桌面），为假时
              //    回调进来由 [_onSystemBack] 分层消费 —— 两颗嵌套会各响一次。
              PopScope(
                canPop: _popScopeTarget() == null,
                onPopInvokedWithResult: (bool didPop, Object? result) {
                  if (didPop) return; // 正常 pop（没有可消费的层）：什么都不做
                  _onSystemBack();
                },
                child: const SizedBox.shrink(),
              ),
              // `#shake` 包住 `#bg` 到 `#flash` 的全部内容（`#boot` 在它外面，不跟着抖）
              ShakeLayer(
                token: _shake,
                px: _shakePx,
                // LLM 设置是不透明整页：盖住时冻结下层全部动画（docs/49 E6）
                ticking: !_llmPaneOn,
                // docs/39 §5.5：reduce 时组件内部直接不抖（震屏整个跳过）
                reduceMotion: reduce,
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
                        builder: (BuildContext _, double t, Widget? child) =>
                            t <= 0
                            ? child!
                            : ColorFiltered(
                                colorFilter: ColorFilter.matrix(
                                  _lerpMatrix(_identity, kFailColorMatrix, t),
                                ),
                                child: child,
                              ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            // v3 天幕（参考稿 L40-53）：紫雾 + 描边大字 + 地平线 +
                            // 透视地板 + 扫描线 + 抖动噪点 + 暗角。旧 BgLayer 在下一层
                            // 兜底（它自带 ComfyUI 底图）；RefBackground 的底是不透明的
                            // ColoredBox(var(--bg))，所以视觉以新层为准。
                            // 旧 BgLayer 已撤：它整层被 RefBackground 的不透明底盖住，
                            // 却仍逐帧作画（白耗 GPU），边缘还漏出一道暗带。
                            RefBackground(
                              accent: _sceneAccent,
                              ghost: _sceneGhost,
                              // 天幕走 Timer 不走 Ticker，TickerMode 管不到 → 单独关
                              animate: !reduce && !_llmPaneOn,
                            ),
                            // 参考稿 #bgfx 浮尘层（46 颗尘上浮 + 偶发流星，z 1：
                            // 天幕之上、界面之下）。组件早就写了却从没挂上 —— docs/49 G
                            RefAmbient(
                              accent: _sceneAccent,
                              animate: !reduce && !_llmPaneOn,
                            ),
                          ],
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
                          // ⚠️ 不进 setState：只有每秒的 `_onSecond` 读它，
                          //    setState 会让整个 AppShell 跟着每次触屏重建（docs/49 E5）
                          _lastAct = DateTime.now();
                          // docs/24 #15：瞌睡中被戳醒（惊一下 → 回情绪）
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
                    RefHud(
                      // 结算时 HUD 的晶核先停在结算前的数，等晶核飞到再滚上去
                      state: _hudCoinsHold == null
                          ? _host
                          : _host.copyWith(coins: _hudCoinsHold),
                      coinKey: _coinKey,
                      // 参考稿 SC.hud：home/main(否)/board/exec/archive(否)/shop。
                      // 验收浮层（.ovl z70）盖在 HUD（z40）上，HUD 本身不收。
                      visible:
                          lobby ||
                          exec ||
                          result ||
                          (main && _boardOn) ||
                          (sheet && _sheetKind == SheetKind.supply),
                      onMenu: () => _openSheet(SheetKind.system),
                      onMenuLongPress: _openLlmPane,
                      onLevelTap: () => _toast(
                        'EXP ${_host.exp} / ${HostState.need(_host.lv)} · '
                        '距 LV${_host.lv + 1} 还差 '
                        '${HostState.need(_host.lv) - _host.exp}',
                      ),
                      onCoinTap: () => _toast(
                        '晶核 ◈${_host.coins}。'
                        '${_host.coins < 45 ? '穷，但是干净。' : '有点小钱了，别乱花。'}',
                      ),
                      onStreakTap: () => _toast(
                        '连胜 ${_host.streak} 天。'
                        '${_host.streak > 0 ? '今天已打卡。' : '今天还没完成任何一单。'}',
                      ),
                    ),
                    // 连击药丸（宿主 2026-10-11：从左上角那个小方块里摘出来，
                    // 贴到顶栏下沿居中 —— 位置落在委托卡上方，不再和称号挤在一起）
                    // 连击药丸 —— 宿主 2026-10-11：「连击 隐藏」（先不显示，组件留着，
                    // 要接回来把 visible 改回 lobby || exec 即可）
                    StreakPill(streak: _host.streak, visible: false),
                    // docs/39 H-15 · 主 CTA 三态状态机（P0）：
                    //   执行中 → 回执行面板（**不是开派单板**，这是"执行中再从大厅接单"的堵口）
                    //   队列空 → 她说一句，不进派单板
                    //   否则   → 派单板
                    //
                    // ⚠️ 包一层 ListenableBuilder 订阅秒时钟：H-15 的底注是**真实换日
                    //    倒计时**（原来写死「换日还有 0 小时」），不订的话一秒都不动。
                    //    ListenableBuilder 不含 RenderObject，builder 直接返回 Positioned
                    //    在 Stack 下是合法的。。
                    // v3 大厅（参考稿 L696-717）：home-tag / 她的气泡 / 主线卡 /
                    // active-pill / 三颗侧键 + 128 委托球。
                    if (lobby)
                      Positioned.fill(
                        child: RefHome(
                          host: _host,
                          goal: _goal,
                          quip:
                              _aside ??
                              LINES.holding.replaceFirst(
                                '[[{n}]]',
                                _host.queue.toString(),
                              ),
                          activeElapsed: _active
                              ? _clockText(_execReadout().elapsed)
                              : null,
                          active: _active,
                          queue: _host.queue,
                          day: _goal.days <= 0
                              ? 1
                              : (_goal.days - _goal.remainingDays(_clock.now)),
                          days: _goal.days <= 0 ? 14 : _goal.days,
                          mood: _coreMood,
                          poke: _pokeN,
                          skipToken: _tap,
                          onQuestTap: () => _go(
                            'main',
                            () => setState(() {
                              _pickedTask = null;
                              _boardOn = false;
                              _mainJustDone = null;
                              _moment = Moment.main;
                            }),
                          ),
                          onCoreTap: _poke,
                          onActivePill: _resumeExec,
                          onOrb: _enterLobbyCta,
                          onSide: (int i) {
                            if (i == 0) {
                              _go(
                                'main',
                                () => setState(() {
                                  _pickedTask = null;
                                  _boardOn = false;
                                  _mainJustDone = null;
                                  _moment = Moment.main;
                                }),
                              );
                            } else if (i == 1) {
                              _openSheet(SheetKind.archive);
                            } else if (i == 2) {
                              _openSheet(SheetKind.supply);
                            }
                          },
                        ),
                      ),
                    // 执行面板
                    // ⚠️ 必须包一层 ListenableBuilder 订阅时钟 —— 否则 `_clock` 每 250ms
                    //    通知了没人听，计时器会一直停在进页面那一刻（实机踩过：等了 12 秒还是 07:00）
                    // v3 执行页（参考稿 L265-329）：104px 计时 / 8 高进度 / 82 证据槽
                    // / 62 高主键。/ 按住 1600ms 认输。旧 ExecPanel 保留树（历史测试锚点），
                    // 视觉由 RefExec 接管。
                    if (exec)
                      Positioned.fill(
                        child: ListenableBuilder(
                          listenable: _clock,
                          builder: (BuildContext _, Widget? _) => RefExec(
                            quest: _execQuest,
                            elapsed: _execReadout().elapsed,
                            critChance: _flow.critBase(),
                            itemCount: Item.execCount(_host.items),
                            equipped: _usedItems.length,
                            tray: RefItemTray(
                              embedded: true,
                              items: Item.all,
                              owned: _host.items,
                              open: _drawerOn,
                              equipped: _usedItems,
                              onPick: _useItem,
                              onClose: () => setState(() => _drawerOn = false),
                              onEmpty: (Item it) {
                                unawaited(Sfx.play('error'));
                                _toast('${it.name} 持有 ×0。补给站在大厅。', bad: true);
                              },
                            ),
                            evidenceThumbs: _evidenceThumbs(),
                            evidenceBusy: _evidenceBusy,
                            onAddEvidence: _addEvidence,
                            onDemoEvidence: _demoEvidence,
                            onRemoveEvidence: _removeEvidence,
                            onSubmit: () => unawaited(_submitQuest()),
                            onQuit: () {
                              if (_busy) return;
                              setState(() {
                                _drawerOn = false;
                                _active = false;
                              });
                              _beginFail();
                            },
                            onQuitProgress: (double p) => _quitP.value = p,
                            onItems: () =>
                                setState(() => _drawerOn = !_drawerOn),
                            onCollapse: () {
                              _toast('任务在后台继续计时。她还在看着。');
                              _go(
                                'home',
                                () => setState(() {
                                  _drawerOn = false;
                                  _moment = Moment.lobby;
                                }),
                                back: true,
                              );
                            },
                          ),
                        ),
                      ),
                    // 结算
                    // v3 验收（参考稿 L421-449）：扫描 → 结果两阶段。
                    // 旧 ResultPanel 保留树（历史测试锚点），视觉由 RefVerdict 接管。
                    if (result &&
                        !_verdictClosing &&
                        _levelUpFrom ==
                            null) // 参考稿：先 closeOvl(verdict) 再 levelUp
                      Positioned.fill(
                        child: RefVerdict(
                          rank: _verdictRank(_result),
                          crit: _result.crit,
                          line: _verdictLine(_result),
                          rows: _verdictRows(_result),
                          xpFrom: _result.beforeExp,
                          xpTo:
                              _result.endExp ??
                              (_result.beforeExp + _result.exp),
                          xpNeed: _result.afterNeed ?? _result.beforeNeed,
                          lv: _result.lvAfter,
                          photo: _verdictPhoto(),
                          onAccept: _acceptVerdict,
                        ),
                      ),
                    // 失败 / 补救（在 veil 之下）—— 记录时间与补救单来自真实认输
                    // v3 失败页（参考稿 L461-474）：glitch 大字 + MISSION FAILED +
                    // 补救框 + 回大厅。旧 FailLayer 保留树（历史测试锚点）。
                    if (fail)
                      Positioned.fill(
                        child: RefFail(
                          title: _failTimeout ? '任务超时' : '任务失败',
                          sub: 'MISSION FAILED',
                          onBack: _backToLobbyFromFail,
                          box: _failBox(),
                        ),
                      ),
                    // 参考稿 coinFly：结算收下后晶核从屏心飞向 HUD 晶核
                    Positioned.fill(
                      child: SizedBox.expand(
                        key: _stackKey,
                        child: RefCoinFly(
                          token: _coinFlyTok,
                          from: Offset(
                            MediaQuery.sizeOf(context).width / 2,
                            MediaQuery.sizeOf(context).height / 2,
                          ),
                          to: _coinFlyTo,
                          onLand: () {
                            setState(() => _hudCoinsHold = null);
                            unawaited(Sfx.play('tick'));
                            _fx.ripple(
                              _coinFlyTo.dx,
                              _coinFlyTo.dy,
                              r0: 0,
                              r1: 36,
                              ms: 500,
                              color: Ref.cyan,
                              w: 2,
                            );
                          },
                        ),
                      ),
                    ),
                    // 认输按住时屏幕跟着暗下去（最多 75%），认输后停在 60%
                    ValueListenableBuilder<double>(
                      valueListenable: _quitP,
                      builder: (BuildContext _, double q, Widget? _) => Veil(
                        opacity: fail ? .6 : q * .75,
                        instant: q > 0, // 按住期间跟手，松手才回到 900ms 过渡
                      ),
                    ),
                    // 亮帧（`#flash` 在 DOM 里排在 veil 之后；正 z 的那些会盖在它上面）
                    // ⚠️ 必须判 isAnimating —— 控制器停在 0 时 `1 - easeOut(0) = 1`，
                    // 会让亮帧**一直开着**（整屏被垫一层 16% 白，一路比对下来才发现）
                    AnimatedBuilder(
                      animation: _flashC,
                      builder: (BuildContext context, Widget? child) =>
                          FlashLayer(
                            color: _flashColor,
                            alpha: _flashC.isAnimating
                                ? _flashA *
                                      (1 -
                                          Curves.easeOut.transform(
                                            _flashC.value,
                                          ))
                                : 0,
                            // docs/39 §5.5：reduce 时亮帧 alpha 砍半（组件内部实现）
                            reduceMotion: reduce,
                          ),
                    ),
                    // 绑定仪式（设计稿未覆盖，按参考稿语言补成独立整页）：
                    // 第 0 幕问目标，第 1 幕 3~5 张访谈卡。
                    if (onboard)
                      Positioned.fill(
                        child: RefOnboard(
                          controller: _ask,
                          probe: switch (_planJob?.kind) {
                            _PlanJobKind.interview => '先让我读懂这句。……[别催]。',
                            _PlanJobKind.bind => '答案收到。我在排[三天]——别走开。',
                            _ =>
                              _interviewCat != null
                                  ? '答完这几张，我给你排三天。'
                                  : (_probeLine ?? LINES.askGoal),
                          },
                          probeToken: _tap,
                          presets: const <String>[
                            '三个月跑完半马',
                            '一个月早睡早起',
                            '考研上岸',
                            '半年减重 10 斤',
                            '学会画画',
                            '变优秀',
                          ],
                          onSubmit: _onGoalSubmitted,
                          cards: _interviewCat == null
                              ? null
                              : interviewCardsFor(
                                  _interviewCat!,
                                  level: _host.lv,
                                ),
                          onDone: _completeOnboarding,
                          onSkip: _planError == null ? null : _skipLlmAndStart,
                          loading: _planLoadingFor(const <_PlanJobKind>{
                            _PlanJobKind.interview,
                            _PlanJobKind.bind,
                          }, accent: Ref.cyan),
                          planError: _planError == null
                              ? null
                              : _planError!.code.name +
                                    ' · ' +
                                    _clip(_planError!.detail, 60),
                        ),
                      ),
                    // v3 档案（参考稿 L767-787）：独立整页，不再是投影面板
                    if (sheet && _sheetKind == SheetKind.archive)
                      Positioned.fill(
                        child: RefArchive(
                          host: _host,
                          ownedCount: _host.ownedTitles.length,
                          totalTitles: HostTitle.all.length,
                          history: _archiveHistory,
                          fx: _fx,
                          onToast: (String m, {bool bad = false}) =>
                              _toast(m, bad: bad),
                          onBack: () => _go(
                            _sheetFrom == Moment.exec ? 'exec' : 'home',
                            () => setState(() => _moment = _sheetFrom),
                            back: true,
                          ),
                          onEquip: (String id) {
                            if (!_flow.equip(id)) return false;
                            setState(() => _host = _flow.host);
                            _persist();
                            return true;
                          },
                        ),
                      ),
                    // v3 补给（参考稿 L789-799）：独立整页
                    if (sheet && _sheetKind == SheetKind.supply)
                      Positioned.fill(
                        child: RefShop(
                          items: Item.all,
                          owned: _host.items,
                          coins: _host.coins,
                          lv: _host.lv,
                          fx: _fx,
                          onBack: () => _go(
                            _sheetFrom == Moment.exec ? 'exec' : 'home',
                            () => setState(() => _moment = _sheetFrom),
                            back: true,
                          ),
                          onBuy: (Item it) {
                            if (!_flow.buy(it.id)) return false;
                            setState(() => _host = _flow.host);
                            _persist();
                            return true;
                          },
                          onUse: (Item it) {
                            if (it.id != 'patch' || !_flow.usePatch()) {
                              return false;
                            }
                            setState(() => _host = _flow.host);
                            _persist();
                            return true;
                          },
                          onToast: (String m, {bool bad = false}) =>
                              _toast(m, bad: bad),
                        ),
                      ),
                    // 主线全景：环挂签挂在环上（位置由相机数学给出），面板压在上面
                    // ⚠️ 换目标时**整层退场**（`_goalChangeOn`）：原来她问新目标时
                    //    主线全景还留在屏上，于是「新目标」输入框的预设词/确定钮
                    //    正好压在底部的【让她派这一环】【换目标】上、字幕压在预设词上
                    //    —— 宿主截图里的"UI 重合"就是这两处（原型 `MainV.hide()`
                    //    也是整层收掉，只留她说话 + 输入）。
                    // v3 主线页（参考稿 L719-731）：抬头 / meta / daybar / 大牌 /
                    // 刻度 / sysbox / 去委托板 + 换目标。
                    if (main && !_boardOn && !_goalChangeOn)
                      Positioned.fill(
                        child: RefMain(
                          key: ValueKey<String>(
                            'main.${_goal.id}.${_mainJustDone ?? -1}',
                          ),
                          goal: _goal,
                          justDone: _mainJustDone,
                          line: _aside,
                          mood: _aside == null ? null : '尚可',
                          lineToken: _asideToken,
                          activeIndex: _activeMainIndex,
                          fx: _fx,
                          elapsed: _active
                              ? _clockText(_execReadout().elapsed)
                              : null,
                          onBack: () => _go(
                            'home',
                            () => setState(() {
                              _boardOn = false;
                              _moment = Moment.lobby;
                            }),
                            back: true,
                          ),
                          onTake: _takeMainTask,
                          onDispatch: () => _go(
                            'board',
                            () => setState(() {
                              _boardFrom = Moment.main;
                              _boardOn = true;
                              _boardFilter = 'all';
                            }),
                          ),
                          onSwapGoal: _beginGoalChange,
                        ),
                      ),
                    // v3 换目标（docs/49 C 重写）：独立场景，斜切转场进出。
                    // 旧版 AskField + 左上取消圆是上一代视觉，已撤。
                    if (main && _goalChangeOn)
                      Positioned.fill(
                        child: RefGoalSwap(
                          goal: _goal,
                          controller: _goalAsk,
                          focusNode: _goalAskFocus,
                          presets: const <String>[
                            '半年减重 10 斤',
                            '三个月跑完半马',
                            '一个月早睡早起',
                            '考研上岸',
                          ],
                          line: _swapLine,
                          lineToken: _swapLineTok,
                          error: _planError == null
                              ? null
                              : '${_planError!.code.name} · '
                                    '${_clip(_planError!.detail, 60)}',
                          loading: _planLoadingFor(const <_PlanJobKind>{
                            _PlanJobKind.swap,
                          }, accent: Ref.gold),
                          onBack: _cancelGoalChange,
                          onSubmit: () => unawaited(_onGoalChangeSubmitted()),
                          onAskXiang: _enterAskXiang,
                        ),
                      ),
                    // v3 委托板（参考稿 L237-264）：tabs + ticket 列表。
                    // ⚠️ 旧的 MainView 仍在下面、`visible: false`：它承载了
                    //    746 条历史测试里的 `main.rail` / `main.title` 等锚点，
                    //    视觉由 RefBoard 接管。
                    if (main && _boardOn)
                      Positioned.fill(
                        child: RefBoard(
                          quests: _boardQuests(),
                          filter: _boardFilter,
                          onFilter: (String f) =>
                              setState(() => _boardFilter = f),
                          active: _flow.active?.task,
                          onBack: () => _go(
                            _boardFrom == Moment.main ? 'main' : 'home',
                            () => setState(() {
                              _boardOn = false;
                              _mainJustDone = null;
                              _moment = _boardFrom;
                            }),
                            back: true,
                          ),
                          onTap: _onBoardTap,
                          onRefill: _refillBoard,
                        ),
                      ),
                    // 「执行中」药丸（`ui.js` L60）：**执行页自己不显示它**，点它回执行页。
                    // 收起执行面板后就靠它回去。
                    // docs/39 H-16 / M-02：**主线页不再浮这颗药丸** —— 主线页的计时读数
                    // 归抬头里的 status chip（由 P0-B 在 main_view 里做）。这里是同一个
                    // 计时数据的第二处呈现，两处并存就是走查 §0 里"药丸压着抬头读数"的来源。
                    // 对话层（docs/18 §2.6）：叠加，不替换；她仍在背景可见
                    // ——层序在 、亮帧与横幅之下
                    // v3 系统设置（参考稿 #sheet L481-491 / L837-843）：
                    // 底部抽屉 + 音效开关 + 秘籍 + 彩蛋提示 + 重置存档。
                    // APP 原有的「和她聊聊」「LLM 连接」按同一行样式补在中间。
                    // 它是盖在**当前场景**上的浮层（#sheet 是 .ovl，不是场景）：
                    // 不改 _moment，关掉就回到原处（委托板/补给里点 ☰ 也一样）。
                    // 常驻挂载、visible 驱动：进出都有滑动（docs/49 B2）
                    Positioned.fill(
                      child: RefSheet(
                        visible: _sysSheetOn,
                        sound: _agentSettings.sound,
                        onSound: (bool v) {
                          if (v != _agentSettings.sound) _toggleSound();
                        },
                        onClose: () => setState(() => _sysSheetOn = false),
                        onHint: () {
                          setState(() => _sysSheetOn = false);
                          _toast('戳大厅的「她」7 次 · 长按她 · 连点计时器 5 次', bad: false);
                        },
                        onChat: () {
                          setState(() => _sysSheetOn = false);
                          _openChat();
                        },
                        onLlm: () {
                          setState(() => _sysSheetOn = false);
                          _openLlmPane();
                        },
                        onReset: () {
                          setState(() => _sysSheetOn = false);
                          _askWipe();
                        },
                      ),
                    ),
                    ChatPanel(
                      visible: _chatOpen,
                      messages: _chat.messages,
                      thinking: _chatThinking,
                      onSend: _sendChat,
                      onClose: () => setState(() => _chatOpen = false),
                      onVoiceTap: _onVoiceTap,
                      onQuickTool: _onQuickTool,
                      paceMs: _paceMs, // docs/22 §R4：同一档位喂聊天气泡的打字机
                    ),
                    // 收官结算在等下一份计划（docs/49 D3）：超过 400ms 才挂，普通结算不闪
                    if (_settleShown && _planJob?.kind == _PlanJobKind.settle)
                      Positioned.fill(
                        child: ColoredBox(
                          key: const Key('ref.settleLoading'),
                          color: Ref.a(Ref.bg, .82),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Ref.gutter,
                              ),
                              child: RefReveal(
                                index: 0,
                                base: 0,
                                child: _planLoadingFor(const <_PlanJobKind>{
                                  _PlanJobKind.settle,
                                }, accent: Ref.mint)!,
                              ),
                            ),
                          ),
                        ),
                      ),
                    // 横幅（z 5，压在所有东西上面）。
                    // ① 拆解失败优先：失败必须**看得见**（旧版失败时屏幕上什么都不发生）。
                    // ② 否则是绑定见面礼（数值语义在 goal_gen 的 kBindGift*）。
                    // v3 顶部提示（参考稿 L409-413 / L1117-1122）
                    if (_toasts.isNotEmpty)
                      Positioned(
                        left: 14,
                        right: 14,
                        top: MediaQuery.paddingOf(context).top + 14,
                        child: IgnorePointer(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              for (final _Toast t in _toasts)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: RefToast(
                                    key: ValueKey<int>(t.id),
                                    message: t.text,
                                    kind: t.bad
                                        ? RefToastKind.err
                                        : RefToastKind.ok,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    // v3 升级过场（参考稿 L450-460）：HUD 在后台跨级时补播
                    if (_levelUpFrom != null)
                      Positioned.fill(
                        child: RefLevelUp(
                          from: _levelUpFrom!,
                          to: _levelUpTo ?? _host.lv,
                          perk: _levelUpPerk(_levelUpTo ?? _host.lv),
                          onTap: () {
                            if (_moment == Moment.result) {
                              _finishVerdict();
                            } else {
                              setState(() {
                                _levelUpFrom = null;
                                _levelUpTo = null;
                                _moment = Moment.lobby;
                              });
                            }
                          },
                        ),
                      ),
                    // 屏幕空间特效（参考稿 #fx z-index 92：压在结算 / 升级等浮层之上 ——
                    // 升级的彩带、结算的爆散都要盖在幕上才看得见；docs/49 G）。
                    // GlobalKey 钉身份：挪位置不重建、在飞的粒子不丢。
                    FxField(key: _fxKey, controller: _fx),
                    // v3 确认弹窗（参考稿 #modal L476-480）：重置存档前先问一句
                    // RefModal 自带渐入暗幕 + 居中；外面不再包一层瞬显的暗幕（docs/49 B3）
                    if (_modalOn)
                      Positioned.fill(
                        child: RefModal(
                          title: '重置存档？',
                          body: '一切从「开机成功」重新开始。等级、晶核、名牒、主线、她记住的你 —— 全部清空。这项操作不可撤销。',
                          yes: '确定重置',
                          no: '再想想',
                          onPick: (bool yes) {
                            setState(() => _modalOn = false);
                            if (yes) unawaited(_wipe());
                          },
                        ),
                      ),
                  ],
                ),
              ),
              // v3 LLM 设置（参考稿未覆盖，按「补全缺失组件」要求新增）：
              // Base URL / ApiKey / 模型 / 温度 / 上下文 / 流式 / 测试 / 保存。
              // 进出走斜切转场（docs/49 B1）；挂在 ShakeLayer **外面**：
              // 它打开时下层整棵树的 Ticker 被冻结（ShakeLayer.ticking），
              // 它自己的显影 / 扫光 / 扫描条不能跟着被冻住。
              if (_llmPaneOn)
                Positioned.fill(
                  child: ColoredBox(
                    // ⚠️ 必须**不**透明：`.96` 让底下的「LLM 设置」入口按钮
                    //    透到面板上（实测遮在「连接 · ENDPOINT」那一栏）。
                    color: Ref.bg,
                    child: SafeArea(
                      child: LlmSettingsPane(
                        initial: _agentSettings,
                        onClose: _closeLlmPane,
                        onSaved: (AgentSettings s) {
                          setState(() => _agentSettings = s);
                          _closeLlmPane();
                        },
                      ),
                    ),
                  ),
                ),
              // 3 · 覆盖层：开机自检（z 20，压在所有东西上面）
              // v3 开机屏（参考稿 #boot L850-857）：170 核心 + HOST//SYSTEM 字标 +
              // 日志 + 3 高渐变条 + 唤醒键。旧的 BootScreen 保留树（它的 42 条测试
              // 锚在 `boot.bar` 等 Key 上），视觉由 RefBoot 接管。
              if (boot)
                Positioned.fill(
                  child: RefBoot(
                    lines: _bootLines,
                    progress: _bootProgress,
                    ready: _bootReady,
                    onWake: _wake,
                  ),
                ),
              // 4 · v3 斜切 wipe 转场（参考稿 L493-499 / L1172-1183）：
              //     三道斜带 + 中央大字，盖住整次换页。
              Positioned.fill(
                child: IgnorePointer(
                  child: RefWipe(
                    key: _wipeKey,
                    accent: _wipeAccent,
                    title: _wipeTitle,
                    sub: _wipeSub,
                    onCovered: _runWipeCovered,
                    onDone: _runWipeDone,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _tapFx(PointerDownEvent e) {
    final Offset p = e.localPosition;
    final Color acc = _sceneAccent;
    _fx.burst(
      p.dx,
      p.dy,
      n: 7,
      cols: <Color>[acc, Colors.white],
      min: 60,
      max: 240,
      life: .27,
      size: 1.3,
      shards: 0,
      g: 0,
    );
    _fx.ripple(p.dx, p.dy, r0: 0, r1: 28, ms: 500, color: acc, w: 2);
  }

  /// 绑定 · 第 0 幕收卷（原型 `makeGoal` 的空泛判定）：
  /// 空泛/太短 → 她追问到具体为止（不进访谈）；具体 → 进访谈卡。
  ///
  /// ⚠️ 2026-10-23：这里原来「趁访谈先把拆解预取跑起来」，类别却是**正则表**
  /// 猜的。现在类别也走 LLM（`GoalMatchAgent`），所以匹配挪到这一步现取：
  /// 拿不到类别就**不进访谈**，把原因摆出来 —— 不再用正则硬猜一个。
  void _onGoalSubmitted() {
    if (_planJob != null) return; // 正在读上一句：不收第二次（防连点）
    FocusScope.of(context).unfocus();
    final String typed = _ask.text.trim();
    if (isVagueGoal(typed)) {
      unawaited(Sfx.play('error'));
      _takeProbeLine(typed.isEmpty ? '目标' : typed); // 追问文案接管（兜底=askGoal）
      _sayAside('太空了。说点具体的。', holdMs: 1800);
      return;
    }
    _takeProbeLine(typed);
    setState(() {
      _planError = null;
    });
    unawaited(_startInterview(typed));
  }

  /// 第 0 幕 → 第 1 幕：先让 Agent 判类别（访谈卡组由类别决定）。
  /// 失败就**不进访谈**、把原因摆出来（旧版会用正则猜一个类别硬走）。
  Future<void> _startInterview(String typed) async {
    final GoalMatchAgent? matcher = _matchAgent;
    if (matcher == null) {
      unawaited(Sfx.play('error'));
      _failPlan(
        const PlanGenerationError(
          PlanFailureCode.noKey,
          'Agent 还没装配好（_initAgent 未完成 / 没配 Key）',
        ),
        goalText: typed,
      );
      return;
    }
    // docs/49 D1：匹配要等 LLM —— 加载卡顶上（原来这段毫无反馈，像卡死）
    final _PlanJob job = _PlanJob(_PlanJobKind.interview, typed);
    setState(() => _planJob = job);
    unawaited(Sfx.cue('ui.open'));
    try {
      final GoalMatchDraft draft = GoalMatchDraft();
      final StrictAgentToolRegistry tools = StrictAgentToolRegistry();
      tools.register(setGoalCategoryTool(goalText: typed, draft: draft));
      final GoalMatch m = await matcher.match(
        goalText: typed,
        tools: tools,
        draft: draft,
        // 绑定期还没有真档案：不给 statusLine（旧版的 withStatus: false 同理）
        statusLine: null,
      );
      if (!mounted || !identical(_planJob, job)) return;
      _planStageTo(1);
      setState(() {
        _planJob = null;
        _pendingGoalText = typed;
        _interviewCat = m.cat;
      });
      unawaited(Sfx.play('deal'));
    } catch (e) {
      if (!mounted || !identical(_planJob, job)) return;
      setState(() => _planJob = null);
      unawaited(Sfx.play('error'));
      _failPlan(_asPlanFailure(e), goalText: typed);
    }
  }

  /// 截断一段文案（诊断条 / 字幕用）
  static String _clip(String s, int max) {
    final String t = s.trim().replaceAll('\n', ' ');
    return t.length <= max ? t : '${t.substring(0, max)}…';
  }

  /// 给她的「宿主档案」一行（`Persona.buildConversation` 的 statusLine 位）
  String _statusLineForAgent() {
    final Goal g = _goal;
    return '${_host.name} · LV${_host.lv} · 连击 ${_host.streak}（最好 ${_host.bestStreak}）· '
        '◈${_host.coins} · 完成 ${_host.doneCount} · 战败 ${_host.failCount} · '
        '最弱维 ${_host.weakest.key}${_host.weakest.value}\n'
        '现主线：${g.text.isEmpty ? '（无）' : '「${g.text}」完成 ${g.doneCount}/${g.plan.length} 单'}';
  }

  /// 绑定 · 第 1 幕收卷（原型 `Store.bind(name, plan)` 的新政版）：
  /// 访谈答案 → 3 天 3 张 E/D/C 落档 → 队列 = 计划前几张 + 当日日常 1~2
  /// → 见面礼双倍卡 ×1 → 大厅（首单已在队列）。
  void _completeOnboarding(Map<String, String> answers) {
    unawaited(_bindWithPlan(answers));
  }

  /// 绑定收卷（异步）：**内容全部来自 Agent 拆解**，失败直接摆到屏幕上。
  ///
  /// 旧版这里是「先取预取的拆解，取不到就用类别模板」——首目标 100% 走模板
  /// 的那条路就是这么来的（绑定期还没有设置入口，没 Key 时必然模板）。
  /// 现在拿不到拆解就不落库：目标仍然空着，宿主看得到失败原因。
  Future<void> _bindWithPlan(Map<String, String> answers) async {
    final GoalCategory? cat = _interviewCat;
    if (cat == null || _planJob != null) return;
    final String text = _pendingGoalText;
    // docs/49 D1：「开始计划」之后要等完整拆解（匹配 + 拆解 + 校验，常见几十秒）
    final _PlanJob job = _PlanJob(_PlanJobKind.bind, text);
    setState(() {
      _planError = null;
      _planJob = job;
    });
    unawaited(Sfx.cue('ui.open'));
    try {
      final Goal goal = await _buildGoalWithAgent(
        text: text,
        at: DateTime.now(),
        firstGoal: true,
        answers: answers,
      );
      // 这中间被重置/换目标了
      if (!mounted || _interviewCat != cat || !identical(_planJob, job)) return;
      // ⚠️ 重置存档会冻结存储（原型靠随后的 location.reload() 解冻，我们没有重载），
      //    所以重新绑定这一刻要显式解冻，否则这次存盘会被静默跳过。
      _save.unfreeze();
      setState(() {
        _goal = goal;
        _flow = QuestFlow(host: _host, goal: _goal);
        _wireFlow(_flow);
        // 绑定即建队列：计划前几张 + 当日日常（store.js bind() 的 L165-167；
        // 每日 1~2 个走 §2.2 新政，不再用 seedForCurrentGoal 的固定 3 张）
        _flow.publishPlanTasks(); // 计划前几张（在手窗口）
        _flow.queue.addAll(_genTodaysDailies());
        _resyncQueueCount();
        // 见面礼：双倍卡 ×1（原型 bind() 的 `S.items.dbl += 1`，
        // 数值语义钉在 kBindGift*；Banner 演出在 build 里挂着）
        _flow.host = _flow.host.copyWith(
          items: applyBindGift(_flow.host.items),
        );
        _host = _flow.host;
        _lastRollDay = startOfDay(DateTime.now());
        job.stage = 3; // 三步全部打勾，留到转场盖住再撤
      });
      _persist();
      _rememberInterview(cat, answers);
      unawaited(Sfx.play('unlock'));
      // 斜切进大厅（原来是硬切）：加载卡留到被盖住那一拍才撤
      unawaited(
        _goOrNow('home', () {
          setState(() {
            _planJob = null;
            _interviewCat = null;
            _moment = Moment.lobby;
          });
          _sayAside('排好了。三天，一天一张。', holdMs: 2200);
          _toast('${kBindGiftKicker}：${kBindGiftText}');
        }),
      );
    } catch (e) {
      // 拆不出首目标就不落库：目标仍空着，原因摆在屏幕上（不退回模板）
      if (!mounted || !identical(_planJob, job)) return;
      setState(() => _planJob = null);
      unawaited(Sfx.play('error'));
      _failPlan(_asPlanFailure(e), goalText: text);
    }
  }

  /// 访谈答案 → 小祥的长期记忆（答案三用之三）。
  ///
  /// ⚠️ 2026-10-23：这里原来 `catch (_) { return; }` —— 写记忆失败**静默吞掉**。
  /// 现在失败会原样抛出，由 [_bindWithPlan] 的 catch 报到屏幕上：
  /// 访谈答案是她后续拆解的唯一上下文来源，写不进去就等于丢了他的话。
  Future<void> _rememberInterview(
    GoalCategory cat,
    Map<String, String> answers,
  ) async {
    final MemoryStore? mem = _memory;
    if (mem == null) {
      throw const PlanGenerationError(
        PlanFailureCode.noKey,
        'MemoryStore 还没装配好：访谈答案无处落库',
      );
    }
    for (final String text in memoriesFromInterview(
      cat: cat,
      answers: answers,
      goalText: _pendingGoalText,
      days: _goal.days,
    )) {
      await mem.add(text, source: MemorySource.interview, weight: 2);
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
      // 主线单统一由 publishPlanTasks 补发（保持"在手窗口"那几张）
      mainTask: null,
      activeIsMain: _flow.active?.task.kind == 'main',
      remedyDeadline: _flow.remedyDeadline,
      now: t0,
    );
    setState(() {
      _flow.queue
        ..clear()
        ..addAll(next);
      _flow.publishPlanTasks(); // 换日重钉计划单（幂等）
      _resyncQueueCount();
      _lastRollDay = startOfDay(t0);
    });
    _persist();
  }

  /// 重置存档（`Store.wipe()`）：删档 + 冻结 + 回绑定仪式
  /// （t19/A1：wipe 落**空白档**——重置后是真·新宿主，不是 demo 老宿主还魂）
  Future<void> _wipe() async {
    final SaveData d = await _save.wipe(fallback: SaveData.fresh());
    if (!mounted) return;
    unawaited(Sfx.play('fail'));
    // 斜切进绑定仪式（docs/49 B4：原来是硬切）。数据在被盖住的那一拍换
    await _goOrNow('onboard', () {
      setState(() {
        _flow = QuestFlow.fromSave(host: d.host, goal: d.goal, queue: d.queue);
        _wireFlow(_flow);
        _host = _flow.host;
        _goal = d.goal;
        _moment = Moment.onboard;
        // 回到绑定仪式第 0 幕（访谈进行到一半被重置的也收回来）
        _interviewCat = null;
        _pendingGoalText = '';
        _lastRollDay = null;
        _planJob = null; // 在途的拆解一律作废（按身份丢弃回包）
        _planError = null;
        _goalChangeOn = false;
        _boardOn = false;
        _active = false;
        _ask.clear();
      });
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
  void initState() {
    super.initState();
    // 原型 document.visibilitychange —— 记下你什么时候走的
    WidgetsBinding.instance.addObserver(this);
    _clock.startSeconds(_onSecond); // 原型 setInterval(App.second, 1000)
    _runBootScript(); // v3 开机屏的日志节拍（参考稿 #boot）
    _restore();
    _initAgent(); // 小祥：设置→LLM 网关→文案/聊天服务 + 聊天历史读档
    _maybeRunShot();
  }

  /// **模拟器截图调度**（`--dart-define=SHOT=<场景>`）。
  ///
  /// 为什么要有它：iOS 模拟器上没法点（`simctl` 不支持注入触摸，idb 缺
  /// companion）—— 想核对某一页的视觉，就得**跳过开机屏、直接停在那一页**，
  ///
  /// 场景值：`lobby` / `main` / `drawer` / `goal` / `deck` / `sheet`
  ///          `supply` / `titles` / `evidence` / `result` / `onboard`
  ///
  /// ⚠️ 只在给了 `SHOT` 时跑；**真机与本机日常开发不给这个 define**，
  /// 行为与这条函数不存在时完全一致。
  Future<void> _maybeRunShot() async {
    const String shot = String.fromEnvironment('SHOT');
    if (shot.isEmpty) return;
    // 等首帧落定 + 存档读完后，再一次性把状态摆到目标页
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() {
      _moment = switch (shot) {
        'main' || 'drawer' => Moment.main,
        'goal' => Moment.main,
        'sheet' || 'supply' || 'titles' => Moment.lobby,
        'result' => Moment.result,
        'onboard' => Moment.onboard,
        _ => Moment.lobby,
      };
      if (shot == 'drawer') _pickedTask = _goal.firstOpenIndex;
      if (shot == 'goal') _goalChangeOn = true;
    });
    if (shot == 'sheet') _openSheet(SheetKind.archive);
    if (shot == 'supply') _openTable(TableScene.supply);
    if (shot == 'titles') _openTable(TableScene.titles);
    debugPrint('[shot] 已摆到 $shot');
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
    // docs/24 #16 回来：她转头看一眼（look + exp_idle02）
    // 原型这几句**不给 hold**（flows.js L189）→ 走按字数算的默认值
    _sayAside(line, busy: true);
  }

  /// 本单已经挂上生效的道具（原型 `A.dbl / A.crit / A.shield`）
  final Set<String> _usedItems = <String>{};

  /// 道具抽屉开着没（原型 `#exDrawer.on`）；再点一次「道具」收起
  bool _drawerOn = false;

  /// 有没有一单正在执行（原型 `S.active`）—— 收起后它仍然为真，
  /// 所以大厅里那颗「执行中」药丸会一直挂着（`ui.js` L60）
  bool _active = false;

  /// 投影面板是从哪开出来的（原型 `App._sheetFrom`）—— 关掉要回原处：
  /// 从执行页开的就得回执行页，不能一律回大厅
  Moment _sheetFrom = Moment.lobby;

  /// 表演调试台开着没（宿主 2026-10-11：调试预设/动作/表情的设施）
  /// 悬浮牌局开着没（名牒册 / 补给 / 证据来源）。
  ///
  /// ⚠️ 2026-10-12 宿主截图④：名牒册整桌牌**盖在六维雷达上**（层级打架）。
  /// 解法不是改牌，是**让面板退场** —— 牌桌浮起时投影面板与光束一起收掉，
  /// 关掉牌桌再回来。牌本身一个字都不改。
  bool _tableOpen = false;

  /// 开投影面板（原型 `App.sheet(kind)`）
  void _openSheet(SheetKind kind) {
    FocusScope.of(context).unfocus(); // 键盘别压在面板上（宿主验收）
    if (kind != SheetKind.system) {
      // 档案 / 补给是参考稿里的整页场景：go('archive' | 'shop')
      final Moment from = _moment == Moment.exec ? Moment.exec : Moment.lobby;
      unawaited(
        _go(kind == SheetKind.archive ? 'archive' : 'shop', () {
          setState(() {
            _sheetFrom = from;
            _sheetKind = kind;
            if (kind == SheetKind.archive) {
              _archiveHistory = _flow.historyLog.entries();
            }
            _moment = Moment.sheet;
            _drawerOn = false;
          });
        }),
      );
      return;
    }
    setState(() {
      _sysSheetOn = true;
      _drawerOn = false;
    });
  }

  /// 系统设置抽屉（浮层，不占场景）
  bool _sysSheetOn = false;

  /// 打开**悬浮牌局**（docs/32 §3）—— 牌直接浮在舞台上，不开面板、不开弹层壳。
  ///
  /// 三个场景（补给 / 称号 / 证据）共用 [TableOverlay] 这一层壳，
  /// 但牌面皮肤完全不同（货架 / 名牒 / 取景窗）。
  /// 收起由 overlay 自己的幕接管（点幕 / 点出口铭牌），所以 barrier 不拦点击。
  Future<void> _openTable(TableScene scene) async {
    if (_tableOpen) return;
    FocusScope.of(context).unfocus();
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    setState(() => _tableOpen = true);
    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.transparent,
        transitionDuration: Duration(milliseconds: reduce ? 120 : 280),
        // 牌桌浮起：淡入 + 轻微上移。退场比进场快（apple-design §7 / §3.2）。
        transitionBuilder:
            (
              BuildContext ctx,
              Animation<double> a,
              Animation<double> b,
              Widget child,
            ) {
              final Animation<double> eased = a.drive(CurveTween(curve: kOut));
              return FadeTransition(
                opacity: eased,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(0, reduce ? 0 : .02),
                    end: Offset.zero,
                  ).animate(eased),
                  child: child,
                ),
              );
            },
        pageBuilder:
            (BuildContext ctx, Animation<double> a, Animation<double> b) =>
                TableOverlay(
                  scene: scene,
                  host: _host,
                  onClose: () => Navigator.of(ctx).pop(),
                  onBuy: (String id) {
                    if (!_flow.buy(id)) return null;
                    setState(() => _host = _flow.host);
                    _persist();
                    return _flow.host;
                  },
                  onEquip: (String id) {
                    if (!_flow.equip(id)) return null;
                    setState(() => _host = _flow.host);
                    _persist();
                    return _flow.host;
                  },
                ),
      );
    } finally {
      // 牌桌收起 → 投影面板与光束回来（§2 ④ 的"让位"是双向的）
      if (mounted) setState(() => _tableOpen = false);
    }
  }

  /// 进入失败态（认输与超时共用）：原型 `_fail()` 的视觉前几下
  void _beginFail({String how = 'quit'}) {
    _clock.stopFast();
    // 参考稿 giveUp()：SFX.fail()（L1559）—— 原来认输 / 超时判负都是哑的
    unawaited(Sfx.play('fail'));
    unawaited(Haptics.buzz('fail'));
    // 原型 `_fail()` L529：`Stage.setCam('fail'); Stage.emote('sad'); Stage.motion('down')`
    // —— 原生/WebView 桥已接通（T7），这里恢复当时的"暂时拿掉"：
    // docs/24 #11：认输垂头（exp_sad01）；**超时**另换惨白脸（exp_pale02）
    // 真实判负（store.js fail）：failCount 记账、主线单回队首、生成补救单
    // —— 失败页不再是死局：补救单可接可弃（见 _onChoice）
    final FailOutcome? fo = _flow.fail(how: how);
    setState(() {
      _moment = Moment.fail;
      _quitP.value = 0;
      _resultChoicesOn = false;
      // 终态优先：进失败页 = 这一段演出到此为止，顺手把「她正在说回来那几句」
      // 的演出闸门放掉（`_greetAfter` / `_wakeSequence` 会把它举起来 ~1~3 秒）。
      // 不放的话，宿主在这段窗口里点【……接。】会被闸门挡掉（`_onChoice` 旧版
      // 就是 `if (_busy) return`），2026-10-11 实机死局见 `_onChoice` 的注释。
      _busy = false;
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
  }

  // ── 结算页 / 失败页的出口（「提交卡死」根因③④的修复）──────────────

  /// 提交任务 → 真实结算。**fail fast**：结算/收官拆解失败都当场报。
  ///
  /// 旧版是内联的 `_result = _flow.settle() ?? _result`：settle 返回 null 时
  /// 悄悄沿用上一单的结算数据（看着像结算成功，其实什么都没发生）。
  /// 现在 settle 要么给结果、要么抛，失败走 [_failPlan]（目标/队列都不动）。
  /// 结算闸门（docs/49 D3）：settle 在途时不收第二次提交
  bool _settling = false;

  /// 结算超过 400ms 还没回来（收官那单在等下一份计划的拆解）才挂加载层 ——
  /// 普通结算是瞬时的，不能让加载层闪一下
  Timer? _settleSlow;
  bool _settleShown = false;

  Future<void> _submitQuest() async {
    if (_busy || _settling) return; // 原型 `App.submit()` → `run()`
    // 参考稿 JS L1469-1471：**没有证据她不收**。原来这里直接进结算，
    // 等于允许空手交差（真机实测：点提交就结算，证据槽还是三个「+」）。
    if ((_flow.active?.evidence ?? const <EvidenceShot>[]).isEmpty) {
      unawaited(Sfx.play('fail'));
      unawaited(Haptics.buzz('fail'));
      _toast('没有证据，她不收。先上传截图。', bad: true);
      _sayAside('空手来交差？先[上传截图]。', holdMs: 2400);
      return;
    }
    _settling = true;
    final _PlanJob job = _PlanJob(_PlanJobKind.settle, _goal.text);
    _planJob ??= job; // 收官拆解的分步进度要从第一拍就记上（显示另由 _settleShown 管）
    _settleSlow?.cancel();
    _settleSlow = Timer(const Duration(milliseconds: 400), () {
      if (mounted && _settling) setState(() => _settleShown = true);
    });
    _clock.stopFast();
    _verdictShots = List<EvidenceShot>.of(_flow.active!.evidence);
    _active = false; // 交出去了，药丸该消失
    // docs/24 #7 提交任务：交单前满意地点个头
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
    try {
      // 真实结算（store.js settle 的移植）：经验/金币/六维/连击/升级/
      // 主线/称号全部落账。收官那一单还会在这里 await 下一份计划的拆解。
      final QuestResult r = await _flow.settle();
      if (!mounted) return;
      setState(() {
        _result = r;
        _hudCoinsHold = _flow.host.coins - r.coin;
        _resultChoicesOn = false;
        _moment = Moment.result;
        _host = _flow.host;
        _goal = _flow.goal;
      });
      // 原型 settle() L372：结算时她专注读单
      _persist();
    } on PlanFailure catch (e) {
      // 收官时拆不出下一份计划：结算已经落账，但计划没拿到 —— 说出来。
      if (!mounted) return;
      setState(() {
        _host = _flow.host;
        _goal = _flow.goal;
        _resultChoicesOn = false;
        _moment = Moment.result;
      });
      _failPlan(e, goalText: _goal.text);
      _persist();
    } finally {
      _settling = false;
      _settleSlow?.cancel();
      if (mounted) {
        setState(() {
          _settleShown = false;
          if (identical(_planJob, job)) _planJob = null;
        });
      }
    }
  }

  /// 结算演出播完（原型 `choose()` 前的那一刻）：弹选项 + 她按档位说一句
  /// （flows.js L442-447 的 tier 台词，t10 已由 SystemCopyProvider 接管：
  /// LLM 回了顶掉下面这句，兜底保持原句）
  void _onResultDone() {
    if (!mounted || _moment != Moment.result || _resultChoicesOn) return;
    _resultChoicesOn = true;
    // v3 升级过场（参考稿 L1539-1549）：先演 LEVEL UP，点掉后再落到目标页。
    final List<int> ups = _result.ups;
    if (ups.isNotEmpty && _levelUpFrom == null) {
      setState(() {
        _levelUpFrom = _result.beforeLv;
        _levelUpTo = ups.last;
      });
      // 参考稿 levelUp()：flash(acid .6, 600) + FX.confetti() + shake(10)（L1549）
      _pulse(color: Ref.acid, a: .6, ms: 600, shakePx: 10);
      if (!railReduceMotion(context)) _fx.confetti(MediaQuery.sizeOf(context));
      return;
    }
    _finishVerdict();
  }

  /// 「收下」之后去哪（参考稿 JS L1536-1537）：
  /// 主线单 → 主线页（停在这一环）；支线/日常 → 委托板。
  void _finishVerdict() {
    final QuestResult r = _result;
    final int idx = r.planClear;
    if (r.finale) _onFinale(r);
    setState(() {
      _levelUpFrom = null;
      _levelUpTo = null;
      _resultChoicesOn = false;
    });
    // 参考稿 L1536-1537：主线单 → go('main',{justDone})；其余 → go('board')
    unawaited(
      _go(idx >= 0 ? 'main' : 'board', () {
        setState(() {
          _boardFrom = Moment.lobby;
          _pickedTask = null;
          _moment = Moment.main;
          _boardOn = idx < 0;
          _boardFilter = 'all';
          _mainJustDone = idx >= 0 ? idx : null;
        });
      }),
    );
  }

  /// 「收下」：关掉验收浮层 → 晶核飞向 HUD（JS L1531-1533）→ 950ms 后
  /// 再走升级 / 换页。
  bool _verdictClosing = false;
  int? _hudCoinsHold;
  int _coinFlyTok = 0;
  Offset _coinFlyTo = Offset.zero;
  final GlobalKey _coinKey = GlobalKey();
  final GlobalKey _stackKey = GlobalKey();

  Future<void> _acceptVerdict() async {
    if (_verdictClosing) return;
    final RenderBox? chip =
        _coinKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? root =
        _stackKey.currentContext?.findRenderObject() as RenderBox?;
    setState(() {
      _verdictClosing = true;
      if (chip != null && root != null) {
        _coinFlyTo = root.globalToLocal(
          chip.localToGlobal(chip.size.center(Offset.zero)),
        );
        _coinFlyTok++;
      }
    });
    await Future<void>.delayed(const Duration(milliseconds: 950));
    if (!mounted) return;
    setState(() {
      _verdictClosing = false;
      _hudCoinsHold = null;
    });
    _onResultDone();
  }

  /// 刚验收完的主线单序号（主线页播压印 + 解封）
  int? _mainJustDone;

  /// 正在执行的主线单在清单里的序号
  int? get _activeMainIndex {
    final Quest? a = _flow.active?.task;
    if (a == null || a.kind != 'main' || a.goalId != _goal.id) return null;
    return a.planIndex;
  }

  /// 主线页点当前卡（JS mainTap → startTask('m')）：
  /// 已在执行 → 回执行页；手上有别的单 → 她拦；否则把这一环发到队首并接单。
  void _takeMainTask(int i) {
    if (_busy) return;
    final Quest? act = _flow.active?.task;
    if (act != null) {
      if (_activeMainIndex == i) {
        _resumeExec();
      } else {
        unawaited(Sfx.play('error'));
        _toast('你手上还有一单没交差。', bad: true);
        _resumeExec();
      }
      return;
    }
    Quest? q;
    for (final Quest x in _flow.queue) {
      if (x.kind == 'main' && x.goalId == _goal.id && x.planIndex == i) {
        q = x;
        break;
      }
    }
    q ??= _flow.planTask(i);
    unawaited(Sfx.play('stamp'));
    _onBoardTap(q);
  }

  /// 收官出口（TODO-01）：第 N 环 CLEAR 时下一条主线**已经在 settle 里落库**
  /// （`QuestFlow._applyFinale`），这里只负责把这件事说出来 + 落盘。
  ///
  /// 她不会说「你完成了，再见」—— 叙事没有终点：
  /// 环数变了、题目变了，路还长。
  void _onFinale(QuestResult r) {
    // docs/24 #19 收官：定格亮相（kime + exp_bsmile02，强制优先级盖过结算动作）
    final FinaleOutcome? o = _flow.lastFinale;
    if (o == null || o.goal == null) {
      _sayAside('这条主线，你走完了。……接下来看你自己的。', holdMs: 2800);
      return;
    }
    // 结算已经改过 host / goal（升级、六维、新主线），这里同步界面副本
    setState(() {
      _host = _flow.host;
      _goal = _flow.goal;
      _pickedTask = null;
    });
    _persist();
    final int n = o.goal!.plan.length;
    _sayAside(
      '${o.total} 单走完了。下一份计划 [[$n 单]]，已经在你手上——'
      '「${o.newGoalText}」。别以为能歇。',
      holdMs: 3200,
    );
    // 收官不占用 _resultChoicesOn：选项还是【再来一单。/先歇会儿。】，
    // 队首就是新主线的首环单（settle 里钉的），点「再来一单」直接接得上。
  }

  /// 系统返回键要消费哪一层（docs/39 M-04）。null = 交给系统（退到桌面）。
  ///
  /// 优先级：**失败页 > 牌屉 > 主线 > 默认**。
  /// 原来只有失败页那一档，所以 Android 返回键在牌屉/主线里都会直接退出 App；
  /// 现在与 × 同语义：牌屉先收牌屉，再退主线，再回大厅。
  ///
  /// ⚠️ 别把别的层（派单板 / 投影面板 / 对话层）顺手加进来 —— 它们各自的
  ///    关闭语义还不一样（对话层要落「聊到一半」的上下文），这一轮不动。
  _BackTarget? _popScopeTarget() {
    if (!mounted) return null;
    // v3 层优先：LLM 设置是模态，返回键先关它
    if (_llmPaneOn) return _BackTarget.sheet;
    if (_modalOn) return _BackTarget.modal;
    if (_sysSheetOn) return _BackTarget.sysSheet;
    if (_chatOpen) return _BackTarget.chat;
    if (_moment == Moment.fail) return _BackTarget.fail;
    if (_moment == Moment.main && _goalChangeOn) return _BackTarget.swap;
    if (_moment == Moment.main && _pickedTask != null) {
      return _BackTarget.drawer;
    }
    // 参考稿 Esc：exec → 收起；其余非大厅场景 → back()
    if (_moment == Moment.main ||
        _moment == Moment.sheet ||
        _moment == Moment.exec) {
      return _BackTarget.main;
    }
    return null;
  }

  /// 返回键真正落地（与 × 同语义）
  void _onSystemBack() {
    switch (_popScopeTarget()) {
      case _BackTarget.sheet:
        _closeLlmPane();
      case _BackTarget.swap:
        _cancelGoalChange();
      case _BackTarget.fail:
        _backToLobbyFromFail(); // 失败页接住了返回键 = 回到大厅
      case _BackTarget.drawer:
        setState(() => _pickedTask = null);
      case _BackTarget.main:
        _sceneBack();
      case _BackTarget.modal:
        setState(() => _modalOn = false);
      case _BackTarget.sysSheet:
        setState(() => _sysSheetOn = false);
      case _BackTarget.chat:
        setState(() => _chatOpen = false);
      case null:
        break;
    }
  }

  /// 参考稿 `back()`：逐级退一层（与各页 ✕ / ‹ 同一条路）
  void _sceneBack() {
    switch (_moment) {
      case Moment.main when _boardOn:
        unawaited(
          _go(
            _boardFrom == Moment.main ? 'main' : 'home',
            () => setState(() {
              _boardOn = false;
              _mainJustDone = null;
              _moment = _boardFrom;
            }),
            back: true,
          ),
        );
      case Moment.main:
        unawaited(
          _go('home', () => setState(() => _moment = Moment.lobby), back: true),
        );
      case Moment.sheet:
        unawaited(
          _go(
            _sheetFrom == Moment.exec ? 'exec' : 'home',
            () => setState(() => _moment = _sheetFrom),
            back: true,
          ),
        );
      case Moment.exec:
        _toast('任务在后台继续计时。她还在看着。');
        unawaited(
          _go(
            'home',
            () => setState(() {
              _drawerOn = false;
              _moment = Moment.lobby;
            }),
            back: true,
          ),
        );
      default:
        break;
    }
  }

  /// 回执行面板（主线页「继续执行」/ 牌屉里执行中那张的 CTA）
  void _resumeExec() {
    if (_busy) return;
    unawaited(_go('exec', () => setState(() => _moment = Moment.exec)));
  }

  /// 大厅主 CTA 的三态分派（docs/39 H-15）—— **唯一主行动状态机**：
  ///   执行中 → 回执行面板（堵住"执行中再从大厅接单"那条二次接单老坑）
  ///   队列空 → 她说一句，不进派单板（交给 [_enterDispatchOrRest]）
  ///   否则   → 派单板
  /// 原先 Dock 里 `running` 写死 false，这三态只有"待接"一条真正可达。
  void _enterLobbyCta() {
    if (_active) {
      _resumeExec(); // 与主线页「继续执行」同一条路（状态机只有一份）
      return;
    }
    _enterDispatchOrRest();
  }

  /// 大厅那颗委托球 = 参考稿的 `taskOrb` → `go('board')`（JS L1645）。
  /// 面板式派单板（旧 Plate）已按设计稿删除：委托板本身就能接单。
  void _enterDispatchOrRest() {
    if (_busy) return;
    if (_flow.queueEmpty) {
      _sayAside('今天的单，清干净了。明天再来。', holdMs: 2200);
      return;
    }
    unawaited(Haptics.buzz('publish'));
    unawaited(
      _go('board', () {
        setState(() {
          _boardFrom = Moment.lobby;
          _moment = Moment.main;
          _boardOn = true;
          _boardFilter = 'all';
          _pickedTask = null;
        });
      }),
    );
  }

  /// 执行中那张的计时读数（`12:04`）
  static String _clockText(Duration d) {
    // 参考稿 fmt()：mm:ss 两位补零
    final String m = d.inMinutes.toString().padLeft(2, '0');
    final String ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  /// 原型 `hhmm(Clock.now())`
  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// 当前场景的主强调色 —— 参考稿 L1177 的 --accent（SC[name].acc）。
  /// 每个页面一个色：home acid / main cyan / board gold / exec hot /
  /// archive violet / shop mint。
  Color get _sceneAccent => switch (_moment) {
    Moment.main => _boardOn || _goalChangeOn ? Ref.gold : Ref.cyan,
    Moment.dispatch => Ref.gold,
    Moment.exec => Ref.hot,
    Moment.result => Ref.mint,
    Moment.sheet => switch (_sheetKind) {
      SheetKind.archive => Ref.violet,
      SheetKind.supply => Ref.mint,
      SheetKind.system => Ref.acid,
    },
    Moment.fail => Ref.hot,
    _ => Ref.acid,
  };

  /// 天幕上那枚 200px 描边大字（参考稿 L1178 的 SC[name].ghost）。
  String get _sceneGhost {
    if (_moment == Moment.boot || _moment == Moment.onboard) return '系统';
    if (_moment == Moment.main) {
      return _goalChangeOn ? '换线' : (_boardOn ? '委托' : '骑行');
    }
    if (_moment == Moment.exec) return '执行';
    if (_moment == Moment.sheet) {
      return switch (_sheetKind) {
        SheetKind.archive => '档案',
        SheetKind.supply => '补给',
        SheetKind.system => '系统',
      };
    }
    return '系统';
  }

  /// 顶部提示条（参考稿 L1117-1122 的 toast）：2.6s 后自动收起。
  /// 同一时刻最多 3 条，多了挤掉最旧的。
  void _toast(String message, {bool bad = false}) {
    if (!mounted) return;
    setState(() {
      _toasts.add(_Toast(id: _toastSeq++, text: message, bad: bad));
      while (_toasts.length > 3) {
        _toasts.removeAt(0);
      }
    });
    final int id = _toastSeq - 1;
    Timer(const Duration(milliseconds: 2600), () {
      if (!mounted) return;
      setState(() => _toasts.removeWhere((_Toast t) => t.id == id));
    });
  }

  int _toastSeq = 0;
  final List<_Toast> _toasts = <_Toast>[];

  /// .fail-box（参考稿 L470-473）：连胜损失 + 一句 + 补救单
  Widget _failBox() {
    final Remedy remedy = _failRemedy ?? Remedy.demo;
    final int streak = _host.streak;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Ref.a(Ref.hot, .3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                // 参考稿 failSk：`🔥 <s>旧</s> → <hot>0</hot>`
                TextSpan(
                  text: '🔥 ',
                  style: refText(size: 28, wght: 400, height: 1),
                ),
                TextSpan(
                  text: streak.toString(),
                  style: refText(
                    family: Ref.fd,
                    size: 34,
                    wght: 700,
                    height: 1,
                    color: Ref.dim2,
                  ).copyWith(decoration: TextDecoration.lineThrough),
                ),
                TextSpan(
                  text: ' → ',
                  style: refText(
                    family: Ref.fd,
                    size: 34,
                    wght: 700,
                    height: 1,
                    color: Ref.txt,
                  ),
                ),
                TextSpan(
                  text: '0',
                  style: refText(
                    family: Ref.fd,
                    size: 34,
                    wght: 700,
                    height: 1,
                    color: Ref.hot,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '认输也是一种勇气。不过，别养成习惯。',
            textAlign: TextAlign.center,
            style: refText(
              family: Ref.fc,
              size: 14,
              wght: 500,
              height: 1.6,
              color: const Color(0xFFE9DBE3),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '补救 · ${remedy.name}（做一半）· ${remedy.minutesText}'
            ' · 截止 ${remedy.deadline}',
            textAlign: TextAlign.center,
            style: refText(
              family: Ref.fc,
              size: 12,
              wght: 400,
              height: 1.5,
              color: const Color(0xFF9FB3CC),
            ),
          ),
        ],
      ),
    );
  }

  /// 失败页「回到大厅」（参考稿 L1558 的 failOk）
  void _backToLobbyFromFail() {
    unawaited(
      _go('home', () {
        setState(() {
          _failRemedy = null;
          _moment = Moment.lobby;
        });
      }, back: true),
    );
    _persist();
  }

  // ── v3 斜切 wipe 转场（参考稿 L1172-1183）───────────────────────
  final GlobalKey<RefWipeState> _wipeKey = GlobalKey<RefWipeState>();
  String _wipeTitle = '';
  String _wipeSub = '';
  VoidCallback? _wipeCovered;
  VoidCallback? _wipeDone;

  /// 跑一次转场（与清档 _wipe 区分）：盖住时执行 swap，整段结束后执行 after。
  /// 减弱动态 / 已有转场在跑 → 直接执行 swap（不拖时间）。
  /// 参考稿 SC 表（JS L1158-1165）：场景 → 转场大字 / 副标题 / 强调色
  static const Map<String, (String, String, Color)> _sc =
      <String, (String, String, Color)>{
        'home': ('大厅', 'LOBBY', Ref.acid),
        'main': ('主线', 'MAINLINE', Ref.cyan),
        'board': ('委托板', 'COMMISSION BOARD', Ref.gold),
        'exec': ('任务开始', 'MISSION START', Ref.hot),
        'archive': ('档案', 'ARCHIVE', Ref.violet),
        'shop': ('补给站', 'SUPPLY', Ref.mint),
        // docs/49：原来没走转场的几处，补成同一套斜切
        'llm': ('LLM 设置', 'NEURAL LINK', Ref.acid),
        'swap': ('换目标', 'REWRITE', Ref.gold),
        'onboard': ('绑定', 'BINDING', Ref.cyan),
        'resume': ('执行中', 'IN PROGRESS', Ref.hot),
      };

  /// 当前场景在 [_sc] 里的名字（从浮层整页退回原处时，转场写回这一页的名字）
  String get _sceneKey => switch (_moment) {
    Moment.main when _goalChangeOn => 'swap',
    Moment.main when _boardOn => 'board',
    Moment.main => 'main',
    Moment.exec => 'resume',
    Moment.sheet => _sheetKind == SheetKind.supply ? 'shop' : 'archive',
    Moment.onboard => 'onboard',
    _ => 'home',
  };

  /// LLM 设置：斜切推入（docs/49 B1；原来是瞬间挂上）
  void _openLlmPane() {
    if (_llmPaneOn) return;
    FocusScope.of(context).unfocus();
    unawaited(_go('llm', () => setState(() => _llmPaneOn = true)));
  }

  /// LLM 设置：斜切退回原来那一页
  void _closeLlmPane() {
    if (!_llmPaneOn) return;
    FocusScope.of(context).unfocus();
    unawaited(
      _go(_sceneKey, () => setState(() => _llmPaneOn = false), back: true),
    );
  }

  bool _going = false;

  /// 程序性换页（拆解完成 / 清档 / 取消）：**必须落地**。
  /// [_go] 在转场进行中会忽略新请求（防连点），这里改为直接换、不演转场 ——
  /// 否则「拆解成功但正好撞上一段转场」会把加载卡永远留在屏幕上。
  Future<void> _goOrNow(String scene, VoidCallback swap, {bool back = false}) {
    if (_going) {
      swap();
      return Future<void>.value();
    }
    return _go(scene, swap, back: back);
  }

  /// FX 层的稳定身份：它前面的场景节点随 moment 增减，不给 key 会被重建
  final GlobalKey _fxKey = GlobalKey();

  /// 档案页的结算流水（每次进档案重读一次）
  Future<List<HistoryEntry>>? _archiveHistory;
  Color _wipeAccent = Ref.acid;

  /// 参考稿 `go(name, {back})`：whoosh → 三道斜带推入 → 盖住时换页 →
  /// swipe → 推走（返回时方向相反）。转场进行中再点 = 忽略（JS `busy`）。
  Future<void> _go(String scene, VoidCallback swap, {bool back = false}) async {
    if (_going) return;
    _going = true;
    final (String, String, Color) m = _sc[scene]!;
    unawaited(Sfx.play('whoosh'));
    setState(() => _wipeAccent = m.$3);
    try {
      await _runWipe(
        title: m.$1,
        sub: '${m.$2} · LOADING',
        back: back,
        swap: () {
          swap();
          unawaited(Sfx.play('swipe'));
        },
      );
    } finally {
      _going = false;
    }
  }

  Future<void> _runWipe({
    required String title,
    required String sub,
    VoidCallback? swap,
    VoidCallback? after,
    bool back = false,
  }) async {
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final RefWipeState? st = _wipeKey.currentState;
    if (reduce || st == null) {
      swap?.call();
      after?.call();
      return;
    }
    setState(() {
      _wipeTitle = title;
      _wipeSub = sub;
      _wipeCovered = swap;
      _wipeDone = after;
    });
    // 等一帧让 RefWipe 拿到新标题再开播
    await Future<void>.delayed(Duration.zero);
    await _wipeKey.currentState?.play(back: back);
  }

  void _runWipeCovered() {
    final VoidCallback? f = _wipeCovered;
    _wipeCovered = null;
    f?.call();
  }

  void _runWipeDone() {
    final VoidCallback? f = _wipeDone;
    _wipeDone = null;
    f?.call();
  }

  /// LLM 设置面板开关 + 当前设置副本（保存后由 `SettingsStore` 广播重建网关）
  bool _llmPaneOn = false;
  AgentSettings _agentSettings = const AgentSettings();

  /// 升级过场的起止级（null = 不演）；结算里 `res.ups` 非空时赋值
  int? _levelUpFrom;
  int? _levelUpTo;

  /// `.lu-p` 的特权文案（参考稿 JS L1541-1542 的 perks）
  String _levelUpPerk(int n) => switch (n) {
    2 => '解锁护盾购买权限。她对你的评价：从「废」升级为「不算太废」。',
    3 => '每日委托上限 +1。她开始记住你的名字了（大概）。',
    4 => '暴击率基础值 +2%。「别得意。」',
    5 => '解锁名牒「宿主·觉醒」。她承认你了 —— 只承认一点点。',
    _ => '全属性成长潜力 +1。「继续。我在看。」',
  };

  /// 验收评级（参考稿 JS L1490）：时长比 ≥1 = A，≥.5 = B，否则 C；
  /// 暴击且 A → S。
  String _verdictRank(QuestResult r) {
    final int limit = r.quest.minutes * 60;
    final double ratio = limit <= 0 ? 1 : r.held.inSeconds / limit;
    String rank = ratio >= 1 ? 'A' : (ratio >= .5 ? 'B' : 'C');
    if (r.crit && rank == 'A') rank = 'S';
    return rank;
  }

  /// .vline：她的验收评语（参考稿 JS L1519 四档 + 暴击）
  String _verdictLine(QuestResult r) {
    if (r.crit) return '暴击？！……咳，数据异常，我会复核的。（偷偷记下了）';
    return switch (_verdictRank(r)) {
      'S' => '……我无话可说。这次算你狠。',
      'A' => '……行吧，挑不出毛病。[我没有在夸你]。',
      'B' => '差一口气，下次把那口气骑完。',
      _ => '这叫「到此一游」。勉强收下。',
    };
  }

  /// .rw 的三行（经验 / 晶核 / 属性），带 CRIT / ×2 小标
  List<RefRewardRow> _verdictRows(QuestResult r) {
    final String tag = r.dbl ? '×2' : (r.crit ? '×1.5' : '');
    final MapEntry<String, int>? first = r.attrs.entries.isEmpty
        ? null
        : r.attrs.entries.first;
    return <RefRewardRow>[
      RefRewardRow(label: 'EXP', value: r.exp, tag: tag),
      // ⚠️ 不要写 '晶核 ◈'：Chakra / JetBrains / NotoSansSC 都没有 ◈ 字形，
      //    离屏出图实测渲染成豆腐块。HUD 那边用的是六边形图标，这里保持纯文字。
      RefRewardRow(label: '晶核', value: r.coin, tag: tag),
      if (first != null)
        RefRewardRow(
          label: Attr.nameOf(first.key),
          value: first.value,
          tag: r.crit ? 'CRIT' : '',
        ),
      if (r.streakUp) const RefRewardRow(label: '连胜天数', value: 1, tag: 'TODAY'),
    ];
  }

  /// 执行页证据缩略图（参考稿 82 蚂蚁线槽）：按已拍份数给 Widget。
  ///
  /// 会话内的图直接读内存字节；重启后从文档目录回读（IO）。
  /// Web 只活在本次会话里 —— 没有字节时给空槽，不画假图。
  /// 交单那一刻的证据（结算后 active 就清了，取景框要用它）
  List<EvidenceShot> _verdictShots = const <EvidenceShot>[];

  /// 验收取景框里的照片（参考稿 #vdImg = 本单证据）
  Widget? _verdictPhoto() {
    if (_verdictShots.isEmpty) return null;
    // 取景框 220×150pt：按 3x 屏解到 720px 宽足够清楚
    return _evidenceThumb(_verdictShots.first, decodeW: 720);
  }

  List<Widget> _evidenceThumbs() {
    final List<EvidenceShot> shots =
        _flow.active?.evidence ?? const <EvidenceShot>[];
    return <Widget>[for (final EvidenceShot s in shots) _evidenceThumb(s)];
  }

  /// 证据图读盘缓存（docs/49 E3）：路径 → 字节。
  /// ⚠️ 原来 `FutureBuilder(future: visionReadBytes(abs))` 在 build 里现建
  ///    Future —— 执行页的时钟 250ms 重建一次，等于每秒 4 次读盘 + 4 张新字节
  ///    （MemoryImage 按字节身份做缓存键 → 每次都是一次全新的原图解码）。
  final Map<String, Future<Uint8List?>> _evidenceBytes =
      <String, Future<Uint8List?>>{};

  /// [decodeW]：按显示尺寸降采样解码（docs/49 E4）。1200 万像素原图全解是
  /// ~48MB 位图，塞进 82pt 的证据槽只需要 ~360px。
  Widget _evidenceThumb(EvidenceShot s, {int decodeW = 360}) {
    if (s.bytes != null) {
      return Image.memory(
        s.bytes!,
        fit: BoxFit.cover,
        cacheWidth: decodeW,
        gaplessPlayback: true,
      );
    }
    final String? abs = s.absPath;
    if (abs == null || abs.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<Uint8List?>(
      future: _evidenceBytes.putIfAbsent(abs, () => visionReadBytes(abs)),
      builder: (BuildContext context, AsyncSnapshot<Uint8List?> snap) {
        final Uint8List? data = snap.data;
        if (data == null) return const SizedBox.shrink();
        return Image.memory(
          data,
          fit: BoxFit.cover,
          cacheWidth: decodeW,
          gaplessPlayback: true,
        );
      },
    );
  }

  /// 正在取图 / 视觉校验（docs/49 D4）：证据槽转圈 + 防连点
  bool _evidenceBusy = false;

  /// 证据入槽：走内置 VisionService 管线（相册 → 落盘 → 可选校验）。
  /// 参考稿的执行页只有一个「+」上传口（L754），点它直接开相册。
  Future<void> _addEvidence() async {
    final ActiveQuest? a = _flow.active;
    if (a == null || _evidenceBusy) return;
    if (a.evidence.length >= QuestFlow.kMaxEvidence) return;
    setState(() => _evidenceBusy = true);
    EvidenceShot? shot;
    try {
      shot = await VisionService().capture(
        quest: a.task,
        source: ImageSource.gallery,
      );
    } finally {
      if (mounted) setState(() => _evidenceBusy = false);
    }
    if (shot == null || !mounted) return;
    unawaited(Sfx.play('success'));
    setState(() {
      a.evidence.add(shot!);
    });
    _persist();
  }

  /// 参考稿 JS L1425-1440 的 `demoShot()`：**不是 mock 数据**，而是把本次
  /// 执行的真实读数（用时 / 目标时长 / 任务名）画成一张「骑行记录」样式的
  /// 证据图，用来在没有相机 / 无法选图的设备上验证整条验收链路。
  Future<void> _demoEvidence() async {
    final ActiveQuest? a = _flow.active;
    if (a == null || _evidenceBusy) return;
    if (a.evidence.length >= QuestFlow.kMaxEvidence) return;
    setState(() => _evidenceBusy = true);
    EvidenceShot? shot;
    try {
      shot = await VisionService().captureDemo(
        quest: a.task,
        elapsed: _execReadout().elapsed,
      );
    } finally {
      if (mounted) setState(() => _evidenceBusy = false);
    }
    if (shot == null || !mounted) return;
    unawaited(Sfx.play('success'));
    setState(() => a.evidence.add(shot!));
    _persist();
  }

  void _removeEvidence(int i) {
    final ActiveQuest? a = _flow.active;
    if (a == null || i < 0 || i >= a.evidence.length) return;
    setState(() => a.evidence.removeAt(i));
    _persist();
  }

  // ── v3 开机屏的驱动（参考稿 #boot）──────────────────────────────
  // 日志内容与节奏照 data/content.dart 的 LINES.bootLog；只留最近 5 行。
  final List<String> _bootLines = <String>[];
  double _bootProgress = 0;
  bool _bootReady = false;
  Timer? _bootTimer;
  int _bootIx = 0;

  void _runBootScript() {
    _bootTimer?.cancel();
    _bootIx = 0;
    _bootLines.clear();
    _bootProgress = 0;
    _bootReady = false;
    const int n = 5; // 与旧屏一致：最多 5 行
    _bootTimer = Timer.periodic(const Duration(milliseconds: 360), (Timer t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_bootIx < LINES.bootLog.length) {
          _bootLines.add(_bootLine(_bootIx));
          while (_bootLines.length > n) {
            _bootLines.removeAt(0);
          }
          _bootIx++;
          _bootProgress = (_bootIx / LINES.bootLog.length).clamp(0.0, 1.0);
        } else {
          _bootReady = true;
          t.cancel();
        }
      });
    });
  }

  /// 一行日志：占位 `{host}` 换成真实的宿主名 + 等级，`[OK]` 换成 ✓
  String _bootLine(int i) {
    final String raw = LINES.bootLog[i];
    return raw
        .replaceAll('{host}', '${_host.name} · LV${_host.lv}')
        .replaceAll('[OK]', '✓');
  }

  /// 「暂时跳过，先用模板」—— 引导态没配 Key 时的唯一出口。
  ///
  /// 语义不是「假装拆解成功」：目标老老实实留空，人先进大厅。这样
  ///   · 大厅会显示「还没有目标」，不骗人；
  ///   · 长按 HUD 菜单键就能补 LLM 设置（大厅有 HUD）；
  ///   · 配好 Key 后点委托球/立目标，正常走 Agent 拆解。
  ///
  /// ⚠️ 为什么不做「类别模板兜底」：`goal_gen.dart:13` 写明目标拆解只有
  ///    LLM 一条路，旧的模板兜底是刻意删掉的（首目标 100% 走模板的坑）。
  ///    这里不把它请回来。
  /// 绑定仪式里的「稍后再立」：**不伪造计划**（拆解没有模板兜底），
  /// 只是先放宿主进大厅看看；目标仍是空的，下次唤醒会回到绑定仪式。
  void _skipLlmAndStart() {
    unawaited(
      _go('home', () {
        setState(() {
          _planError = null;
          _planJob = null;
          _interviewCat = null;
          _pendingGoalText = '';
          _moment = Moment.lobby;
        });
        _sayAside('先这样。等你把脑子（Key）配好，再谈拆解。', holdMs: 2800);
      }),
    );
  }

  /// 重置存档的确认弹窗（参考稿 #modal L476-480：340 宽 / r22 / 两键 52）。
  /// 原来点「重置存档」直接清档 —— 参考稿是「按住 2 秒 → 弹确认 → 确定」。
  void _askWipe() {
    setState(() => _modalOn = true);
  }

  /// 系统设置 · 音效开关（参考稿 JS L1653 toggleSound）。
  /// 写回 SettingsStore → 类级广播 → [_applyAgentSettings] 落地 Sfx.enabled。
  void _toggleSound() {
    final AgentSettings next = _agentSettings.copyWith(
      sound: !_agentSettings.sound,
    );
    setState(() => _agentSettings = next);
    _applyAgentSettings(next);
    unawaited(SettingsStore().save(next));
    if (next.sound) unawaited(Sfx.play('tap'));
    _toast(next.sound ? '音效已开启。' : '音效已关闭。她的毒舌不受影响。');
  }

  /// 确认弹窗开关（参考稿 #modal.on）
  bool _modalOn = false;

  /// 主线页当前领位（参考稿 `mainFocus(i)` 的 i）

  /// 主线页 → 委托板：参考稿是**两个独立 scene**（#sc-main / #sc-board），
  /// 用 `on` 类切换。这里用同一个布尔表达（Moment.main 下再分一层）。
  bool _boardOn = false;

  /// 委托板是从哪进来的（大厅委托球 / 主线「去委托板」）—— 返回时回原处
  Moment _boardFrom = Moment.lobby;

  /// 委托板当前筛选（参考稿 `boardF`，L1369）
  String _boardFilter = 'all';

  /// 委托板上的单：队列里全部 + 正在执行的那张（参考稿 `boardTasks()`，L1088）
  List<Quest> _boardQuests() {
    final List<Quest> out = <Quest>[];
    final Quest? act = _flow.active?.task;
    if (act != null) out.add(act);
    for (final Quest q in _flow.queue) {
      if (out.every((Quest x) => x.serial != q.serial)) out.add(q);
    }
    return switch (_boardFilter) {
      'MAIN' => out.where((Quest q) => q.kind == 'main').toList(),
      'SIDE' =>
        out.where((Quest q) => q.kind != 'main' && q.kind != 'remedy').toList(),
      'DAILY' => out.where((Quest q) => q.kind == 'daily').toList(),
      _ => out,
    };
  }

  /// 空板「再要一批委托」（参考稿 JS L1374）：补当天日常 + 重钉主线窗口。
  void _refillBoard() {
    setState(() {
      _flow.queue.addAll(_genTodaysDailies(n: 2));
      _flow.publishPlanTasks();
      _resyncQueueCount();
      _host = _flow.host;
    });
    _persist();
    _toast('她叹了口气，又塞给你几单。', bad: false);
  }

  /// 委托板上点一张：已在执行就回执行页，否则接这张
  void _onBoardTap(Quest q) {
    if (_busy) return;
    final Quest? act = _flow.active?.task;
    if (act != null && act.serial == q.serial) {
      _resumeExec();
      return;
    }
    if (act != null) {
      _sayAside('手上还有一张没交。先把它了了。', holdMs: 1800);
      return;
    }
    _flow.queue.removeWhere((Quest t) => t.serial == q.serial);
    _flow.queue.insert(0, q);
    setState(() {
      _host = _flow.host;
      _goal = _flow.goal;
    });
    _beginExec();
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
  /// ⚠️ t16/B3：若存档恢复了执行中单据，唤醒后直接回执行页（不落大厅）
  /// ⚠️ t19/A1：未绑定（空白档/无环）→ 唤醒后进**绑定仪式**，真实新用户由此可达
  void _wake() {
    _wakeSequence();
  }

  /// 唤醒这一拍（原型 `flows.js:71-99` 的 `wake()`）：
  /// `Sound.play('boot')` → `buzz([10,60,20])` → `FX.flash('#9ff0ff',.26,520)`
  /// → **她的睁眼编排**（闭眼抬头 450ms → 眼皮 .35 停 140ms → .05 停 120ms →
  ///   睁眼看向宿主 —— R5「Mac 轮验收项」，2026-10-11 补完）
  /// → 相机 `setCam(bound?'lobby':'talk')`（推镜头由 `_moment` 驱动）
  /// → **逐环点亮**（每环 `showRing`，非 lock 环 `igniteRing` + `Sound.play('ignite',i)`
  ///   + `buzz(6)`；每环停 **140ms**、lock 环只停 **50ms**）→ 再等 **500ms** 才开口
  ///   → **欢迎手势**（`act('present')` → kime 组，R5 验收项）+ 问候台词
  ///   带情绪（原型 `_greet`：back10m→smug，其余 neutral）。
  Future<void> _wakeSequence() async {
    _pulse(color: const Color(0xFF9FF0FF), a: .26, ms: 520, shakePx: 0);
    unawaited(Sfx.play('boot'));
    unawaited(Haptics.buzz('boot'));

    // 转场这一拍（宿主验收：「从唤醒到主界面转场太过突兀, 像是直接切换」）。
    // 参考稿的做法是斜切 wipe（`#wipe` 三道斜带 + 中央大字，JS L1172），
    // 这里对应地再补一拍青蓝过渡，盖住「开机屏 → 大厅」的换页。
    _pulse(color: const Color(0xFF9FF0FF), a: .14, ms: 320, shakePx: 0);

    if (_goal.isEmpty && !_resumedExec) {
      setState(() => _moment = Moment.onboard);
      return; // 绑定仪式的问话走 LineLayer（askGoal），不叠离开问候
    }
    // 小景别（boot .64）→ 正常大小（lobby .92）：这一段要**看得见地放大**
    setState(() => _moment = _resumedExec ? Moment.exec : Moment.lobby);

    // 逐环点亮（原型在这段之后还有 500ms 留白，才轮到 greet）
    await Future<void>.delayed(const Duration(milliseconds: 420));

    final DateTime? seen = _prevSeen;
    final Duration away = seen == null
        ? Duration.zero
        : DateTime.now().difference(seen);
    // `fromBoot` 会强制开口，所以 null（离开太短）也要退回默认那一档
    final AwayKind k = AwayGreeting.kindFor(away) ?? AwayKind.back10m;
    if (!mounted) return;
    // 欢迎手势 + 问候情绪（原型 _greet：睁眼后亮个相再开口）
    debugPrint(
      '[stage] 欢迎手势 act(present) + mood'
      '=${k == AwayKind.back10m ? 'smug' : 'neutral'}',
    );
    _sayAside(AwayGreeting.text(k, away), holdMs: 3200, busy: true);
  }

  /// 读档（store.js L34）—— 没有档就用**空白档**（t19/A1：真新档直达绑定仪式，
  /// 不再被 demo 老宿主冒名）；顺带跑一次存储自检：实机曾经静默不落盘，这里让它出声
  Future<void> _restore() async {
    final SaveData d = await _save.load(fallback: SaveData.fresh());
    // 存储自检 —— 通过就不吭声，不通过就把原因喊出来（别静默失败）
    final String? err = await _save.selfTest();
    if (err != null) debugPrint('[save] ⚠️ 存储不可用：$err');
    if (!mounted) return;
    // 老档没有队列 → QuestFlow 按现状补种子（合并式迁移，不清档）
    final bool seeded = d.queue.isEmpty;
    setState(() {
      _flow = QuestFlow.fromSave(host: d.host, goal: d.goal, queue: d.queue);
      _wireFlow(_flow);
      // t16/B3：执行中单据随档恢复（任务/计时起点/道具标记/证据）——
      // 杀进程重启后回到执行页，计时按 startAt 推导不归零
      _flow.restoreActiveFromJson(d.activeJson);
      _resumedExec = _flow.active != null;
      if (_resumedExec) {
        _execStart = _flow.active!.startAt;
        _active = true; // 「执行中」药丸照挂
      }
      _host = _flow.host;
      _goal = _flow.goal;
      // 原型 `load()` 里的 `S.prevSeen = S.lastSeen` —— 冷启动算"你走了多久"用
      _prevSeen = d.lastSeen;
    });
    // 补出来的种子要落一次盘，重启后队列还在
    if (seeded && _flow.queue.isNotEmpty) _persist();
    // 存档里这条主线**已经走完**（收官发生在「自动续主线」之前的老档）→
    // 补铸下一条并钉队首。⚠️ 现在这一步会真的调 LLM 拆解，失败会抛
    // （旧版是同步模板，永远不会失败）——所以读档时也要接住并报出来。
    try {
      if (await _flow.applyFinaleOutcome()) {
        if (!mounted) return;
        setState(() {
          _host = _flow.host;
          _goal = _flow.goal;
        });
        _persist();
      }
    } on PlanFailure catch (e) {
      _failPlan(e, goalText: _flow.goal.text);
    }
    // 换日（store.js rollDay）：隔夜日常作废、主线单重钉、补发当日日常。
    // 「清晨首次进入」= 存档 lastSeen 的日子不是今天（同日重进不重发）
    _rollDayIfNeeded(fromSeen: d.lastSeen);
  }

  /// 存盘（store.js L43）—— 档案 + 主线 + 她手里的队列 + 执行中单据（t16/B3）
  ///
  /// 启动时的自检（`SaveFile.selfTest`）是**通过**的，但这里写完整存档后回读是空的
  /// —— 所以下面多打一行原始串长度，用来区分「没写进去」和「写进去了解析不出来」。
  Future<void> _persist() async {
    await _save.save(
      SaveData(
        host: _host,
        goal: _goal,
        queue: _flow.queue,
        activeJson: _flow.activeToSaveJson(),
      ),
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
    _bootTimer?.cancel();
    // TODO-07 网关热更：退订设置广播，State 卸载后不再收回调
    SettingsStore.removeListener(_onSettingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    _flashC.dispose();
    _fx.dispose();
    _ask.dispose();
    _goalAsk.dispose();
    _goalAskFocus.dispose();
    _quitP.dispose();
    _asideDone?.cancel();
    _pokeReset?.cancel();
    _coreMoodReset?.cancel();
    _settleSlow?.cancel();
    super.dispose();
  }
}

/// 系统返回键要消费的那一层（docs/39 M-04）。
///
/// 顺序即优先级：失败页 > 牌屉 > 主线；null = 交给系统（退到桌面）。
enum _BackTarget { fail, drawer, main, sheet, modal, sysSheet, chat, swap }

/// 正在等 LLM 的那一件事属于哪一页（加载卡按它分发）
enum _PlanJobKind {
  /// 绑定第 0 幕 → 第 1 幕：匹配类别、挑访谈卡
  interview,

  /// 绑定收卷：拆首目标
  bind,

  /// 换目标：拆新主线
  swap,

  /// 收官结算：拆下一条主线
  settle,
}

/// 一次拆解等待（docs/49 D）：加载卡的数据源 + 防连点闸门
class _PlanJob {
  _PlanJob(this.kind, this.goal) : at = DateTime.now();

  final _PlanJobKind kind;
  final String goal;
  final DateTime at;

  /// 进行到第几步（[_AppShellState._planStageTo] 推进）
  int stage = 0;

  /// 分段拆解进度（总段数 ≤ 1 = 没分段，不显示）
  int segDone = 0;
  int segTotal = 0;

  List<String> get steps => switch (kind) {
    _PlanJobKind.interview => const <String>['读懂你的目标', '挑出访谈卡'],
    _ => <String>[
      '匹配类别与期限',
      segTotal > 1 ? '拆解任务清单 · $segDone/$segTotal 段并行' : '拆解任务清单',
      '规则校验',
    ],
  };

  String get title => switch (kind) {
    _PlanJobKind.interview => 'SYSTEM 正在读你的目标',
    _PlanJobKind.bind => 'SYSTEM 正在排你的三天',
    _PlanJobKind.swap => 'SYSTEM 正在拆新主线',
    _PlanJobKind.settle => '收官 · 正在拆下一条主线',
  };
}

/// 一条顶部提示（参考稿 L1117-1122 的 toast 队列项）
class _Toast {
  const _Toast({required this.id, required this.text, this.bad = false});

  final int id;
  final String text;
  final bool bad;
}
