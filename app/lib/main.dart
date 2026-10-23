import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode, kProfileMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:flutter/services.dart';

import 'agent/copy.dart';
import 'agent/context_adapter.dart';
import 'agent/mainline_agent.dart';
import 'agent/mainline_tool.dart';
import 'agent/llm_client.dart';
import 'agent/llm_gateway.dart';
import 'agent/memory.dart';
import 'agent/settings_store.dart';
import 'agent/tools.dart';
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
import 'stage/progress_band.dart';
import 'state/host_state.dart';
import 'state/goal.dart';
import 'state/goal_gen.dart';
import 'stage/camera.dart';
import 'stage/live2d_stage.dart';
import 'stage/redraw_veil.dart';
import 'stage/stage_port.dart';
import 'state/app_clock.dart';
import 'state/away.dart';
import 'state/haptics.dart';
import 'state/sfx.dart';
import 'state/voice.dart';
import 'state/save_file.dart';
import 'state/quest.dart';
import 'state/quest_flow.dart';
import 'state/result.dart';
import 'widgets/bg_layer.dart';
import 'widgets/ask_field.dart';
import 'widgets/banner.dart';
import 'widgets/card_skins.dart';
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
import 'widgets/perf_debug.dart';
import 'widgets/plate.dart';
import 'widgets/plate_timeline.dart';
import 'widgets/press_scale.dart';
import 'widgets/rail_base.dart' show railReduceMotion;
import 'widgets/result_panel.dart';
import 'widgets/plan_tag.dart';
import 'widgets/sheet.dart';
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

  /// ⚠️ **诊断开关（T7 attempt 2）**：true = 裸舞台页（只有 Live2DStage，
  /// 无天幕/环场/任何 Flutter 层）——用来二分「原生不上屏」的责任方：
  /// 裸页能上屏 = 我们 App 的树有合成冲突（可修）；裸页也黑 = 再看加载与
  /// **shader 是否进包**（2026-10-12：当时的「也黑」就是缺 shader，不是插件/
  /// emugl 不兼容 —— 见 STAGE-OPTIONS「2026-10-12 复盘」）。平时保持 false。
  static const bool kStageBareProbe = false;

  /// **截图专用：跳过 Live2D 平台视图**（`--dart-define=NO_STAGE=1`）。
  ///
  /// 为什么要有它：**iOS 模拟器上原生 Live2D 必崩** —— `libCoreVMClient` 的
  /// `cvms_element_build_from_source` 在编译 Cubism 的 `#version 100` 着色器
  /// 时 SIGBUS（模拟器自带的 GL 转译层撑不住，与 App 代码无关；真机完全正常，
  /// 见 docs/39 §1 与 docs/35）。于是模拟器里看不到任何 Flutter 层。
  ///
  /// 打开它：平台视图整层不建，露出天幕下的**全息剪影**（这是 `Live2DStage`
  /// 加载失败时的既有降级），HUD / 环场 / 卡牌 / 字幕全部照常渲染 ——
  /// 用来在模拟器里截图核对**卡片与 UI 的视觉**，不用于验证角色。
  /// **真机与本机日常开发都别打开**（`flutter run` 不给 define 即为关）。
  static const bool kNoStage = bool.fromEnvironment('NO_STAGE');

  @override
  Widget build(BuildContext context) {
    // 五态陈列页（设计验收用）：`--dart-define=SHOT=states`
    if (const String.fromEnvironment('SHOT') == 'states') {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: CardStatesGallery(),
      );
    }
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
                onReady: (Live2DStageHandle h) => debugPrint('[bare] 裸舞台就绪'),
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
  /// ── 舞台渲染路线（docs/18 §1.5）────────────────────────────────
  ///
  /// **只有一条路线：原生 `flutter_live2d`**（[Live2DStage]，几何相机 = 布局
  /// 矩形复刻 `Cam`）。2026-10-12 宿主拍板删掉 WebView 降级路线（`live2d_web.dart`
  /// 及其 `WebStagePort`、`assets/stage/` 与 `vendor/` 的打包声明），原因见下。
  ///
  /// 为什么当年留了 WebView 兜底、现在又删掉：
  ///  · 旧结论（2026-10-09）把「loadModel=true 但不上屏 + 每帧 GL 0x501」判成
  ///    MuMu 的 emugl 转译层与插件不兼容 —— **这个归因是错的**。真因是
  ///    `flutter_live2d` 1.0.2 不打包 Android shader 资产，原生加载器要的
  ///    `assets/FrameworkShaders/*` 根本不在 APK 里 → shader program = 0 →
  ///    attribute location 查负值 → 每帧 GL_INVALID_VALUE。
  ///    补包见 `app/android/app/build.gradle.kts` 的 `syncLive2dShaders`
  ///    （构建期缺文件会直接报错，不会再退化成"静默黑屏"）。
  ///    结论留档 `app/STAGE-OPTIONS.md`「2026-10-12 复盘」、`docs/35`。
  ///  · 另一条删除理由：WebView 那条路线**触摸是断的** —— `Live2DWeb` 里
  ///    WebView 包在 `IgnorePointer` 内（免得它吃掉 UI 的手势），而
  ///    `assets/stage/stage.js` 从来没有把指针事件转发给播放器。于是"戳她"
  ///    没有跟随、拖动也没有反应 —— 2026-10-12 宿主实测发现。原生这条
  ///    （`Live2DStage` 里 `IgnorePointer(ignoring: false)`）才拿得到触摸：
  ///    插件的平台视图自带"眼睛/头跟着手指"。
  ///
  /// 加载失败时的降级：`Live2DStage` 自己收掉平台视图，露出天幕下的**全息剪影**
  /// （`onFailed` 只打日志、不再切任何路线）。
  ///
  /// ⚠️ 模型加载失败最常见的原因是「没跑转换器」：`app/assets/live2d/sakiko/`
  /// 不在仓库时（该目录在 `assets/live2d/.gitignore` 的旧规则里被屏蔽过），
  /// 跑 `python tools/l2d/convert.py` 重新生成即可。

  /// 她的把手（emote/motion 桥）
  StagePort? _stagePort;

  /// t16/B3：读档恢复了执行中单据 → 唤醒后直接回执行页（计时按 startAt 推导）
  bool _resumedExec = false;

  /// 行为逻辑未定，先用与原型「老宿主 · 第 23 天」一致的演示档
  /// （启动时会被存档覆盖 —— 见 SaveFile）
  HostState _host = HostState.demo;

  /// 业务唯一真源：队列 / 接单 / 道具 / 结算 / 认输（store.js 移植，quest_flow.dart）。
  /// 「提交卡死」根因①②的修复点：提交不再只是切页面，而是经 `_flow.settle()`
  /// 产出真实结算并落到档案 / 主线 / 队列。
  QuestFlow _flow = _demoFlow();

  /// 演示档的 Flow —— 声明式字段初始化器里 `_wireFlow` 还不可用（实例未建好），
  /// 所以包一层静态工厂：既拿 demo 队列，也把收官钩子接上。
  static QuestFlow _demoFlow() {
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
  static void _wireFlow(QuestFlow f) {
    f.nextGoalHook = (Goal prev, int cleared, int total, int level) =>
        buildNextGoal(
          prev: prev,
          cleared: cleared,
          total: total,
          level: level,
          // O-2 裁决（宿主 2026-10-10）：「立目标时刻」**沿用**上一目标 ——
          // goal.at 代表「这条主线是什么时候立的」，走完一条再续一条时
          // 把它改成"现在"会让「主线已立 N 天」这类读数跳变。
          at: prev.at,
        );
  }

  /// 存档（store.js L34-52）
  final SaveFile _save = SaveFile();

  /// 口型包络（audio.js L180-230）—— 打字机逐字喂它，波形条读它。
  /// **不需要 Live2D**：模型到位后 `ParamMouthOpenY` 直接读同一个 `mouth`。
  final VoiceEnvelope _voice = VoiceEnvelope();

  /// 主线全景里展开的是哪一环（null = 没展开，只有抬头）
  int? _pickedTask;

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

  /// ── 换目标（TODO-01 · 主线页入口）──────────────────────────────
  ///
  /// 主线页「换目标」→ 这一层问一句新目标 → `QuestFlow.newGoal` 落库
  /// （旧主线单移除、新主线钉队首）。换目标**不动等级/金币/六维**，
  /// 只换那条路 —— 她认账，但不重开。
  bool _goalChangeOn = false;
  final TextEditingController _goalAsk = TextEditingController();

  /// 换日游标：上次补发日常的那一天（原型 `S.day`；清晨首次进入补发）
  DateTime? _lastRollDay;

  /// 亮帧：白 16% / 180ms ease-out（docs/08 逐帧里的「亮帧」）
  late final AnimationController _flashC = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  /// 「唤醒过场」进度 0→1（2026-10-11 宿主验收：「从唤醒到主界面转场太过突兀,
  /// 像是直接切换一样」）。
  ///
  /// 原来开机态的几处是**布尔门控**、切页那一瞬间硬跳：
  ///   · `Hud` / `Dock`（底栏）/ 对话入口钮 —— 从"不显示"变"显示"（没有过渡）
  ///   · 环场亮度 `dim: boot ? .34 : 1` —— 从 34% 直接跳到 100%
  ///   · 相机是弹簧（`CamSpring`）本来就顺，她本人的睁眼编排也顺
  /// 现在这三处统一吃这条进度：唤醒那一刻从 0 起跑（900ms ease-out），
  /// 于是「被唤醒 → 环亮起 → 界面浮上来 → 落进待机」是一气呵成的推移，
  /// 而不是两次硬切。
  late final AnimationController _wakeFade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    value: 1, // 非开机态默认就是"已就位"
  );

  /// 环场亮度：开机 34% → 唤醒后 100%，**顺着 [_wakeFade] 推**（原来硬跳）
  double get _bandWakeDim =>
      .34 + .66 * Curves.easeOut.transform(_wakeFade.value);

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

  /// 立主线的预取态：[_planFor] 是它对应的那句话（换目标/重绑会换句，
  /// 只有对得上才采用，免得把上一句话的链安到新目标头上）。
  String? _planFor;
  Future<MainlineResult>? _planFuture;

  /// 聊天消息 id（会话内唯一即可）
  int _chatSeq = 0;
  String _chatId() => 'm${DateTime.now().microsecondsSinceEpoch}_${_chatSeq++}';

  /// LLM 网关 + 文案/聊天服务（initState 异步装配；没配 Key 也能跑，全走兜底）
  SystemCopyProvider? _copy;

  /// 立主线的 agent 循环（docs/06）：她 get_status → set_mainline → 解释。
  /// 没配 Key / 她没交 / 循环用尽 → 类别模板兜底
  MainlineAgent? _mainlineAgent;
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
    // ① 非 LLM 设置：先落地（幂等，重复调用无害）
    Sfx.enabled = s.sound;
    Haptics.enabled = s.haptic;
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
      _mainlineAgent = MainlineAgent(client: client, memory: mem);
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
    _stagePort?.react(entries.last.emotion);
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
      _stagePort?.react(line.emotion); // docs/24 #18：强烈情绪连带动作
    }
  }

  /// 毒舌：按到一半松手（waver 原句先行，LLM 毒舌到了再顶）
  void _onWaverRoast() {
    _sayAside(LINES.waver[_rnd.nextInt(LINES.waver.length)], holdMs: 1400);
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
    // docs/24 #2/#13 追问：歪头疑问（question + exp_serious02）
    _stagePort?.act('ask');
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
  /// 的确认语义由换目标流程负责，这里先让对话带着这个话题开起来）。
  /// 带上当前主线与进度 —— 她追问「为什么换」时要引用真实数据。
  String get _newGoalScenario =>
      '换目标：宿主在主线页按了「换目标」。他现在的目标是「${_goal.text}」'
      '（${_goal.doneCount}/${_goal.plan.length} 单）。先追问为什么换、'
      '新目标是什么；提醒他：旧主线环会清空、队列里的主线单会撤下，想清楚再动。';

  /// ── 换目标（TODO-01 · 主线页入口）──────────────────────────────

  /// 点「换目标」→ 先问一句新目标（旧主线单先不动，说清楚再动）。
  void _beginGoalChange() {
    if (_busy) return;
    // docs/24 #17 换目标：她先琢磨一下（thinking + exp_serious02）
    _stagePort?.act('think');
    setState(() {
      _goalChangeOn = true;
      _goalAsk.clear();
    });
    _sayAside('要换？那就说清楚换成什么。[[旧的那条]]，说换就换。', holdMs: 2600);
  }

  /// 换目标输入框里那颗「先问小祥」的暗号（她接管追问，落库仍走 [newGoal]）
  static const String _kAskXiangPreset = '先问小祥';

  /// 走到「该铸环了」时最多再等多久拆解结果 —— 预取通常已经好了，
  /// 这个上限只用于兜住「模型特别慢」。到点就按类别模板铸，绝不吊着宿主。
  static const Duration kPlanWaitOnConsume = Duration(seconds: 4);

  /// 换目标时的等待上限：这里是**冷启动**（没有访谈时间来掩盖网络），
  /// 宿主刚说完那句话、正看着「让我把这条拆开」，所以给得宽一点；
  /// 超时则退回类别模板 —— 迟到的好链不如准时的链。
  static const Duration kPlanWaitOnChangeGoal = Duration(seconds: 15);

  /// 入口牌「先问小祥」：带场合上下文开对话（**不填输入框、不落库**）
  void _enterAskXiang() {
    setState(() => _goalChangeOn = false);
    _openChat(scenario: _newGoalScenario);
  }

  /// 新目标提交（第 0 幕的空泛判定复用 `isVagueGoal`）：
  /// 具体 → `buildNextGoal`（按新那句话的时长词算**期限**、排出任务清单）
  /// → `flow.newGoal` 落库（旧主线单移除、新计划单补进队列）→ 存盘 → 回主线页。
  Future<void> _onGoalChangeSubmitted() async {
    FocusScope.of(context).unfocus();
    final String typed = _goalAsk.text.trim();
    // 「先问小祥」不是目标，是入口：带场合上下文开对话（D5 的入口保留）
    if (typed == _kAskXiangPreset) {
      setState(() => _goalChangeOn = false);
      _openChat(scenario: _newGoalScenario);
      return;
    }
    if (isVagueGoal(typed)) {
      _sayAside('太空了。说点具体的——[[一句话]]。', holdMs: 2000);
      return;
    }
    final Goal prev = _flow.goal;
    // 期限先按规则算（时长词 + 完成度提档）—— 拆解照这个期限要任务，
    // 免得「半年」只要 8 张而计划其实是 180 天。
    final int n =
        (goalDaysFor(typed) +
                completionDayBoost(
                  cleared: prev.doneCount,
                  total: prev.plan.length,
                  level: _host.lv,
                ))
            .clamp(kPlanMinTasks, kPlanMaxTasks)
            .toInt();
    final int need = planDraftCountFor(n);
    // 她先想一下：拆解是真网络请求，不能让界面看着像卡住
    setState(() => _goalChangeOn = false);
    _sayAside('……行，让我把这条拆开。', holdMs: 1400);
    _prefetchPlan(
      typed,
      detectCategory(typed),
      taskCount: need,
      days: n,
      withStatus: true, // 换目标时状态是真的：让她先看清再拆
    );
    final List<TaskSpec>? planned = await _takePlan(
      typed,
      taskCount: need,
      wait: kPlanWaitOnChangeGoal,
    );
    // 等待期间宿主可能又换了目标 / 重置了存档 —— 对不上就整件事作废
    if (!mounted || !identical(_flow.goal, prev)) return;
    final Goal next = buildNextGoal(
      prev: prev,
      // 换目标是宿主**主动**换（不是走完的）——按已走过的环数算完成度
      cleared: prev.doneCount,
      total: prev.plan.length,
      level: _host.lv,
      text: typed,
      // 同上 O-2：主动换目标也沿用原「立目标时刻」
      at: prev.at,
      // 内容来自 LLM 拆解；取不到就是 null → 类别模板兜底
      planned: planned,
    );
    final Quest? first = _flow.newGoal(next);
    if (first == null) return; // 新目标没排出单（不该发生）：不动任何状态
    setState(() {
      _host = _flow.host;
      _goal = _flow.goal;
      _goalChangeOn = false;
      _pickedTask = null;
      _moment = Moment.main;
    });
    _persist();
    // docs/24 #17 换目标落库：正色点头（nod + exp_serious02）
    _stagePort?.act('nod');
    _sayAside(
      '行。旧的撤了，新清单 [[${_goal.plan.length} 单]] 已经在你手上。'
      '「$typed」——别又三天热度。',
      holdMs: 3000,
    );
  }

  /// 换目标中途算了：什么都不动。
  void _cancelGoalChange() {
    FocusScope.of(context).unfocus(); // 键盘一并收起（宿主验收）
    setState(() {
      _goalChangeOn = false;
      _goalAsk.clear();
    });
    _sayAside('没换。……明智。', holdMs: 1600);
  }

  /// 上一次宿主操作（原型 `App.lastAct`）
  DateTime _lastAct = DateTime.now();

  /// 进执行态时把计时归零重算（原型 `Store.accept()` 里记 startAt）
  void _beginExec() {
    // 真实接单：队首出队 + 记 startAt（原型 `Store.accept`；D12 修复
    // —— 计时不再写死"已执行 7 分钟"）
    final Quest? head = _flow.head;
    if (head != null) _flow.accept(head);
    // 原型 `App.dispatch()` 接单那一拍：Stage.motion('nod')
    // （docs/24 #4：nod 现在自带 exp_serious02 正色脸）
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
    // docs/24 #5 执行中：落进思考脸一次（低频、不打扰；之后交给待机池）
    _stagePort?.perf('thinking', 'exp_idle02');
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
      _asideEmotion = emotion;
      _asideUntil = DateTime.now().add(Duration(milliseconds: hold));
      if (busy) _busy = true;
    });
    if (onDone != null) {
      _asideDone?.cancel();
      _asideDone = Timer(Duration(milliseconds: hold), onDone);
    }
  }

  /// 当前临时台词的情绪（喂 [LineLayer.emotion] 的逐字音节）
  String? _asideEmotion;

  /// 换目标输入框的焦点（弹键盘用；临时调试扩展 ext.sys.goalchange 也用它）
  final FocusNode _goalAskFocus = FocusNode();

  /// 临时台词结束后的回调（原型 `Line.say(...).then(...)`）
  Timer? _asideDone;

  /// ═══ 戳她（原型 flows.js L646-654 `poke()`）═══════════════════════
  ///
  /// 点在她身上（[Live2DStage.hitHer] 命中）→ 越戳越恼：
  /// 第 1~3 戳 tsun + 动作 `poke`（check 组 + exp_shy01）→ 第 4 戳 annoyed →
  /// 第 5 戳起 cold 且动作换 `fluster`；台词是 content.js L319 那五句。
  /// 20 秒不戳，连戳计数归零（原型的 `_pokeReset`）。
  /// ⚠️ 只留「连戳」计数（决定台词/动作档位）；原型另存过一个累计数
  /// `S.pokes`，但界面从未展示 —— 不留死数据。
  int _pokeN = 0;
  Timer? _pokeReset;

  void _poke() {
    final int i = math.min(LINES.poke.length - 1, ++_pokeN - 1);
    unawaited(Sfx.play('poke'));
    unawaited(Haptics.buzz('poke'));
    _stagePort?.act(i >= 3 ? 'fluster' : 'poke');
    final String emo = i >= 4
        ? 'cold'
        : i >= 2
        ? 'annoyed'
        : 'tsun';
    _stagePort?.mood(emo);
    // 说完把那句情绪收回去（原型 `.then`: 大厅里回 mood 或 neutral）
    _sayAside(
      LINES.poke[i],
      holdMs: 1500,
      emotion: emo,
      onDone: () {
        if (!mounted || _moment != Moment.lobby) return;
        _stagePort?.mood('neutral');
      },
    );
    _pokeReset?.cancel();
    _pokeReset = Timer(const Duration(seconds: 20), () => _pokeN = 0);
  }

  /// 舞台上的按下：**先走背景那一套**（记"宿主还在"、跳过打字机 —— 原型
  /// `app.addEventListener('pointerdown', …, true)` 捕获阶段就干了），
  /// 再看有没有戳在她身上（原型 `#stage` 的 pointerdown + `Stage.hit`）。
  /// 两者**可以同时发生** —— 原型就是两层监听，别做成互斥。
  void _onStageDown(Offset global, Rect rect) {
    _tap++;
    _voice.hush();
    _lastAct = DateTime.now();
    // ⚠️ 收起键盘：web 里点空白输入框自然失焦；Flutter 必须显式 unfocus
    //    （宿主验收：「换出键盘之后, 点击系统内应用, 键盘无法正常收缩回去」）
    FocusScope.of(context).unfocus();
    final bool hit = Live2DStage.hitHer(global, rect);
    debugPrint(
      '[stage] 舞台按下 (${global.dx.toStringAsFixed(0)},'
      '${global.dy.toStringAsFixed(0)}) 命中她=$hit',
    );
    if (hit) _poke();
  }

  // ── 打瞌睡整链（docs/24 #15，原型 `App.doze()/undoze()` 的 Flutter 接线）──
  bool _dozing = false;

  void _maybeDoze(DateTime now) {
    if (_dozing || _busy || _moment != Moment.lobby || _stagePort == null) {
      return;
    }
    if (now.difference(_lastAct) <= ChatterScheduler.dozeAfter) return;
    if (_aside != null) return; // 她正在说话，别睡
    _dozing = true;
    debugPrint('[stage] 没人理 → 打瞌睡（${ChatterScheduler.dozeAfter.inSeconds}s）');
    unawaited(_stagePort!.doze());
  }

  void _undozeIfNeeded() {
    if (!_dozing || _stagePort == null) return;
    _dozing = false;
    debugPrint('[stage] 瞌睡被戳醒');
    unawaited(_stagePort!.undoze());
  }

  /// 原型 `App.second()`：换日之外的那几件事
  void _onSecond() {
    final DateTime now = DateTime.now();
    // docs/24 #15 打瞌睡：大厅里 80s 没人理 → 睡（`ChatterScheduler.dozeAfter`；
    // 原型 `App.doze()`。睡姿 = speed 0 + exp_sys_sleep，任意触碰唤醒）
    _maybeDoze(now);
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
    //
    // 慢推（[_camGlideMs] > 0）：换景别这种**要看得见**的推镜头走缓动补间，
    // 而不是让弹簧自己冲过去 —— 弹簧约 0.5s 到位，配上亮帧/界面淡入就像"硬切"。
    if (_camSpring.name != camOf) {
      final int glideMs = _camGlideMs;
      _camGlideMs = 0; // 一次性的：只对这一拍生效
      if (glideMs > 0) {
        _camSpring.glideTo(camOf, MediaQuery.sizeOf(context), ms: glideMs);
      } else {
        _camSpring.set(camOf, MediaQuery.sizeOf(context));
      }
      if (!_camTicker.isActive) _camTicker.start();
    }
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

    // lineAt（flows.js L23）：
    //   lobby = H*.6，dispatch = H-568，fail = H*.47，sheet = H*.38 - 104，main = H-192
    //   result = H-230（flows.js L23 的 result 档 —— 结算页她的台词位）
    //
    // ⚠️ 换目标（[_goalChangeOn]）要**让开输入框**：main 档的 H-192 正好压在
    //    「新目标」输入框和预设词上（宿主截图：字幕压在预设词、确定钮压着「换目标」）。
    //    这一拍借 onboard 的档位（H*.55，屏幕中段），字幕就不跟输入区抢地方了。
    final double lineY = _goalChangeOn
        ? size.height * .55
        : dispatch
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
      // ⚠️ **不能让整屏随键盘缩**（默认 true 就会缩）。原因：
      //   · 舞台的矩形是按 LayoutBuilder 的可用高度算的 —— 键盘一弹，
      //     矩形尺寸就变 → 插件 iOS 侧重建设 FBO（排空渲染队列）+ 她整条位移；
      //   · 环场/命中层用的是 `MediaQuery.sizeOf`（整窗高），跟舞台对不上，
      //     于是"她"和"环"会错位（宿主截图里那种错乱）。
      // 代价：输入框要自己抬到键盘上面（`AskField.bottomInset`）。
      resizeToAvoidBottomInset: false,
      body: Stack(
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
                      word: (boot || onboard) ? 'SYSTEM' : _goal.short,
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
                      // docs/24 #15：瞌睡中被戳醒（惊一下 → 回情绪）
                      _undozeIfNeeded();
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
                // 2026-10-13 宿主裁定：「此页面名牒册悬浮在档案上就行哦」——
                // **不做让位**，牌桌就浮在投影面板之上（原来那版让面板退场是过度设计）
                SheetBeam(visible: sheet),
                // 她本人（`#stage`）—— 必须放在 Flutter UI **下面**：
                // 平台视图是 opaque 的，会吃掉触摸；更靠上的组件先命中，
                // 所以字幕/按钮/手势照样能点（原型里 `#stage` 也在 `#ui` 之前）。
                // ⚠️ **她的位置必须是这里** —— 天幕之后、环场/UI 之前。
                //    原型的层序就是 `#bg → #stage → #ui`，实测这个位置**层序完全正确**
                //    （字幕/环/HUD 都压在她之上，见 `.verify/_stageback.png`）。
                //
                // ── 渲染路线（docs/18 §1.5）────────────────────────────
                // **只有原生一条**（`Live2DStage`，几何相机 = 布局矩形复刻 Cam）。
                // WebView 降级路线 2026-10-12 已按宿主拍板删除（理由见
                // `_stagePort` 上方那段注释：触摸是断的 + 当年保留它的归因是错的）。
                // 相机随弹簧推镜头逐帧刷新（与下方环场同一数据源 _cam）。
                // docs/39 §1 / docs/35：**模拟器上原生 Live2D 必崩**（GL 转译层
                // 编不了 Cubism 的 shader → `cvms_element_build_from_source` SIGBUS）。
                // `--dart-define=NO_STAGE=1` 时整层不建，露出天幕下的全息剪影，
                // 其余 Flutter 层照常 —— 供模拟器截图核对 UI（真机不受影响）。
                if (SysApp.kNoStage)
                  const SizedBox.shrink()
                else
                  ValueListenableBuilder<Cam>(
                    valueListenable: _cam,
                    builder: (BuildContext _, Cam camNow, Widget? _) =>
                        Live2DStage(
                          visible: true,
                          cam: camNow,
                          onReady: (Live2DStageHandle handle) {
                            _stagePort = NativeStagePort(handle);
                            debugPrint('[stage] 原生舞台就绪（flutter_live2d）');
                            // 开机睡姿（docs/22 R5「Mac 轮验收项」）：boot 全程
                            // 闭眼低头睡着，等宿主触碰唤醒。舞台加载晚于唤醒
                            // （罕见）就跳过 —— 她已经醒了不必再睡。
                            if (_moment == Moment.boot) {
                              unawaited(_stagePort!.sleep());
                            }
                          },
                          // 加载失败：舞台自己收掉平台视图，下面是全息剪影。
                          // （不再切任何路线 —— 降级路线已删除。）
                          onFailed: () => debugPrint('[stage] 原生舞台加载失败 → 全息剪影'),
                        ),
                  ),
                // 「戳她」的命中层（原型 `main.js` L42-44：`#stage` 的 pointerdown
                // → `Stage.hit(x,y)` → `App.poke()`）。放在她**之上**、环场/UI **之下**：
                //   · 在她矩形外的点不受影响，照常落到背景那层（跳过打字机）
                //   · 在矩形内但没戳中她的点，[AppShellState._onStageDown] 会
                //     把背景那一套行为补齐（记"宿主还在" + 跳过打字机）
                //   · 按钮/底栏/选项都在更上层 → 它们先命中，不受影响
                ValueListenableBuilder<Cam>(
                  valueListenable: _cam,
                  builder: (BuildContext _, Cam camNow, Widget? _) {
                    final Rect r = Live2DStage.stageRect(
                      camNow,
                      MediaQuery.sizeOf(context),
                    );
                    return Positioned.fromRect(
                      rect: r,
                      // ⚠️ 必须是 **translucent 的 Listener**（不是 GestureDetector）：
                      //  · `Listener` 不参与手势竞技场 → 它和下层平台视图**都能收到**
                      //    这串 pointer 事件（平台视图那份驱动"眼睛/头跟着手指"）
                      //  · translucent → 事件继续往她下面的层走，不挡任何东西
                      //  · 原型是 pointerdown 就触发（按下即算，不等抬手）——
                      //    所以这里也只在 down 判命中，拖拽时头照样跟手
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        // ⚠️ 必须用 `e.position`（**全局**坐标）—— `hitHer` 内部
                        // 拿它和 `rect.top`/`rect.center.dx` 比；用 localPosition
                        // 会永远判定不中（2026-10-11 踩过：戳她毫无反应）。
                        onPointerDown: (PointerDownEvent e) =>
                            _onStageDown(e.position, r),
                        child: const SizedBox.expand(),
                      ),
                    );
                  },
                ),
                // 换族「重绘」过场（docs/37 §3.5）：平台视图改布局尺寸的那一帧起
                // （只有派单 talk 用 1.70 族），她有 2~3 帧是"小号/错位"渲染，用一层
                // 遮罩 + 一道扫线吃掉。
                // ⚠️ 层级：在**她之上、环场之下** —— 只把她压下去，环场/进度带/HUD/
                //    台词/底栏都留着，观感是"她重绘一拍"而不是"整屏黑一下"。
                ValueListenableBuilder<Cam>(
                  valueListenable: _cam,
                  builder: (BuildContext _, Cam camNow, Widget? _) =>
                      StageRedrawVeil(
                        family: Live2DStage.viewFamilyS(camNow.s),
                      ),
                ),
                // 环场：她脚下到头顶那 8 个环。**画在独立画布上，与 Live2D 无关**
                // （`stage.js` L127 `cv.id='ringCv'`），启动时 `App.boot()` 会把
                // 8 个环全部 showRing，所以之后一直可见。
                ValueListenableBuilder<Cam>(
                  valueListenable: _cam,
                  builder: (BuildContext _, Cam camNow, Widget? _) =>
                      ProgressBandLive(
                        done: _goal.doneCount,
                        total: _goal.totalTasks,
                        cam: camOf,
                        camObj: camNow, // 弹簧推出来的那一帧（切页是"推镜头"不是瞬移）
                        lit: _bandLitNow(),
                        // docs/39 H-10 / M-12：**主线页隐藏**（牌扇与她的脸都在这块）
                        visible: !main,
                        dim: boot
                            ? .34 // 开机态的全息参数
                            // 唤醒过场：34% → 100% 顺着 _wakeFade 推上去（原来是硬跳）
                            : fail
                            ? 1 -
                                  .4 *
                                      _ringDim
                                          .value // flows.js L530：holoTo({bright:.6}) 缓动过去
                            : _bandWakeDim,
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
                  // 唤醒过场：淡入（在组件内部套 Opacity —— 它顶层是 Positioned，
                  // 外面包带 RenderObject 的包装件会报 ParentDataWidget 错）
                  fade: _wakeFade,
                ),
                // 连击药丸（宿主 2026-10-11：从左上角那个小方块里摘出来，
                // 贴到顶栏下沿居中 —— 位置落在委托卡上方，不再和称号挤在一起）
                // 连击药丸 —— 宿主 2026-10-11：「连击 隐藏」（先不显示，组件留着，
                // 要接回来把 visible 改回 lobby || exec 即可）
                StreakPill(streak: _host.streak, visible: false),
                // 纪律在 t9，这颗玻璃圆钮由本文件挂载——HUD 行下方左上，
                // 在 Stack 里压着 Live2D 平台视图，触摸先命中它
                // 对话入口（docs/18 §2.6）：宿主 2026-10-11 指定从左上角搬走 ——
                // 「图2聊天框，移动到委托的上方，如图3位置」：现在挂在**右下、底栏之上**，
                // 也就是委托板 / 今日已清那一块的正上方。
                // 样式与底栏那几颗侧键同族（玻璃圆 + 1px 描边），只是大一号、贴右手拇指。
                if (lobby)
                  Positioned(
                    // docs/39 H-13：直径 56→52、right 18→20 / bottom 150→158
                    //（与 CTA 那颗 104 的环在同一列上让出安全区）
                    // docs/39 H-17：158 之上的**安全区增量**（今天恒 0）
                    // 唤醒过场取 master（外面这层 _WakeFade 必须保留）
                    right: 20,
                    bottom: 158 + _bottomExtra(context),
                    child: _WakeFade(
                      t: _wakeFade,
                      child: ChatEntryButton(
                        onTap: () => _openChat(),
                        size: 52,
                      ),
                    ),
                  ),
                // docs/39 H-15 · 主 CTA 三态状态机（P0）：
                //   执行中 → 回执行面板（**不是开派单板**，这是"执行中再从大厅接单"的堵口）
                //   队列空 → 她说一句，不进派单板
                //   否则   → 派单板
                //
                // ⚠️ 包一层 ListenableBuilder 订阅秒时钟：H-15 的底注是**真实换日
                //    倒计时**（原来写死「换日还有 0 小时」），不订的话一秒都不动。
                //    ListenableBuilder 不含 RenderObject，builder 直接返回 Positioned
                //    在 Stack 下是合法的（同 Live2DStage / ProgressBand 的 ValueListenableBuilder）。
                ListenableBuilder(
                  listenable: _clock,
                  builder: (BuildContext _, Widget? _) => Dock(
                    state: _host,
                    visible: lobby,
                    fade: _wakeFade,
                    // H-15：真状态（原先组件里写死 running=false）
                    running: _active,
                    elapsed: _execReadout().elapsed,
                    // H-09：主线侧键外圈进度弧 + 右上 0/8
                    planDone: _goal.doneCount,
                    planTotal: _goal.totalTasks,
                    // H-15 底注：执行中「点开 · 继续」；队列空走真实换日倒计时
                    capText: _active
                        ? '点开 · 继续'
                        : (_host.queue == 0 ? dockRollCap(_clock.now) : null),
                    onCta: _enterLobbyCta,
                    onSide: (int i) {
                      if (i == 0) {
                        setState(() {
                          _pickedTask = null;
                          _moment = Moment.main;
                        });
                      } else if (i == 1) {
                        _openSheet(SheetKind.archive);
                      } else if (i == 2) {
                        // 补给 → **悬浮货架**（docs/32：不开面板，牌直接浮在舞台上）
                        _openTable(TableScene.supply);
                      }
                    },
                  ),
                ),
                // 派单板
                Plate(
                  quest: _quest,
                  host: _host,
                  visible: dispatch,
                  // docs/41 §6.5：揭示可跳过（整屏 tap 的计数，见上方那个 
                  // GestureDetector；Plate 内部有 90ms 防误触窗口）
                  skipToken: _tap,
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
                    // 暴击率显示口径（t16/B4 单一真源）：底值由 QuestFlow.critBase 出，
                    // 证据加成由面板按手里的证据列表自己加 evidenceCritBonus——
                    // 这里若给全量 critChance，证据加成就算两遍（gate 实测双计）
                    critChance: _flow.critBase(),
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
                      // docs/24 #6 快照记录：证据进槽那一下，她抬眼确认一下
                      if (list.length > a.evidence.length) {
                        _stagePort?.act('check');
                      }
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
                      // docs/24 #7 提交任务：交单前满意地点个头
                      _stagePort?.perf('nod', 'exp_smile01');
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
                  // 「去补给」—— 直接开**悬浮货架**（docs/32：不开面板）
                  onShop: () => _openTable(TableScene.supply),
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
                    // docs/39 §5.5：reduce 时亮帧 alpha 砍半（组件内部实现）
                    reduceMotion: reduce,
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
                          ? _flow.queueEmpty
                                ? '收工？……明天见。'
                                : '还做吗？'
                          : fail
                          // `[[{dl}]]` 是补救单截止（真实认输时间 + 24h）
                          ? LINES.remedyLine.replaceFirst(
                              '[[{dl}]]',
                              '[[明天 ${_hhmm(_flow.remedyDeadline ?? _failAt)}]]',
                            )
                          : main
                          ? LINES.mainline(_goal.doneCount, _goal.plan.length)
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
                      // ⚠️ 只能用原型 MOOD_LABEL 的 12 个词（content.js:421）：
                      // 原来这里写的是自造的「专注」——既不在词表里（界面读数与原型不一致），
                      // 又让逐字音节的情绪反查退化成 neutral。focus 的原型词是「监视」。
                      ? '监视'
                      : dispatch
                      ? '监视'
                      : (fail ? '待机' : '尚可'),
                  y: lineY,
                  soft: fail,
                  fail: fail,
                  // 临时台词的情绪（戳她那几句要带 tsun/annoyed/cold 的音节）
                  emotion: _asideEmotion,
                  skipToken: _tap, // 点背景跳过打字机
                  paceMs: _paceMs, // docs/22 §R4：对白节奏三档（设置页「对白节奏」）
                  // 口型包络：打字机每显形一个字就把目标开口度设一下，
                  // SYSTEM 后面那排波形条跟着动（原型 ui.js L70-73 / L96）
                  voice: _voice,
                  onChar: _voice.syllable,
                  // docs/39 H-17：字幕带底边不许越过底部安全区（下限 34 + 8 呼吸）。
                  // 主线页再让开底部两键（56 + 底边 34 + 12）——H-12 的 3 行上限
                  // 会让字幕比原来高 ~1 行，走查图 02 里它已经快贴到【去执行】。
                  bottomFloor:
                      _safeBottom(context) +
                      8 +
                      (main ? 56 + 12 : 0) +
                      _bottomExtra(context),
                  // 原型里那句主线台词说完就 Line.hide()，点环展开详情时它已经不在——
                  // 两者都显示会叠在详情卡上。结算页只在「她说话」和「问还做吗」时出现
                  visible:
                      lobby ||
                      dispatch ||
                      fail ||
                      onboard ||
                      (result && (_aside != null || _resultChoicesOn)) ||
                      (main && _pickedTask == null),
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
                  // 键盘高度：Scaffold 不随键盘缩屏（见 resizeToAvoidBottomInset
                  // 的注释），所以输入框自己抬上去
                  bottomInset: MediaQuery.viewInsetsOf(context).bottom,
                  onPreset: (String v) => _ask.text = v,
                  onSubmit: _onGoalSubmitted,
                ),
                // docs/39 M-24 · 换目标输入幕的**常驻取消**（左上 44 圆 + 顶部 11pt
                // 上下文行）。两条都不依赖牌列 —— 键盘弹起、牌列退场、LLM 长句
                // 把字幕顶上去，取消都还在原地。进 240ms kOut（淡 + 8px 下落）。
                _GoalChangeChrome(
                  visible: _goalChangeOn,
                  onCancel: _cancelGoalChange,
                ),
                // 换目标 · 问新目标（TODO-01）：主线页「换目标」→ 这一层
                // （旧主线单先不动；确定才走 `flow.newGoal` 落库）
                AskField(
                  prompt: '新目标 ›',
                  placeholder: '比如：半年减重 10 斤',
                  presets: const <String>[
                    '半年减重 10 斤',
                    '三个月跑完半马',
                    '一个月早睡早起',
                    '考研上岸',
                  ],
                  controller: _goalAsk,
                  focusNode: _goalAskFocus,
                  visible: _goalChangeOn,
                  bottomInset: MediaQuery.viewInsetsOf(context).bottom,
                  onPreset: (String v) => _goalAsk.text = v,
                  onSubmit: _onGoalChangeSubmitted,
                  // docs/39 M-24：取消**不再走牌列**（原来在牌列最右、被屏宽裁掉一半，
                  // 键盘一弹整条牌列退场就彻底没有退路）。现在取消 = 输入幕左上那颗
                  // 常驻 44 圆（见下面 `ask.cancel` 的挂载），_cancelGoalChange 由它调。
                  // 「先问小祥」仍是**入口牌**：开对话、不填输入框（§4.B.2）
                  onEntry: _enterAskXiang,
                ),
                // 绑定仪式 · 第 1 幕：卡片式访谈（docs/18 §2.1，t4 组件 + t8 装配）
                // 答完 → buildFirstGoal 落 3 天 3 环 → 见面礼 → 大厅
                if (onboard && _interviewCat != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 96,
                    child: InterviewDeck(
                      cards: interviewCardsFor(_interviewCat!, level: _host.lv),
                      onDone: _completeOnboarding,
                    ),
                  ),
                // 投影面板（档案 / 补给 / 系统共用这一层壳）
                Sheet(
                  host: _host,
                  kind: _sheetKind,
                  // 2026-10-13 宿主裁定：**不让位** —— 名牒册悬浮在档案上就行
                  visible: sheet,
                  // 设置页「表演调试台」→ 收起投影面板，开调试设施（她仍在背景可见）
                  onOpenPerfDebug: () => setState(() {
                    _moment = _sheetFrom;
                    _perfDebugOn = true;
                  }),
                  // 关掉回**开它的那个页面**（原型 `App.closeSheet()` → `_sheetFrom`）
                  onClose: () => setState(() => _moment = _sheetFrom),
                  onWipe: _wipe,
                  // D6/D7 装配（t9 组件回调 + t14 flow 业务）：挂称号 / 购买
                  onOpenTitles: () => _openTable(TableScene.titles),
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
                // 挂签（大厅里挂在进度带右端）—— docs/39 H-08 整支重做：
                //  · 吃**逐帧** camObj（1.4s 推镜时挂签得跟着环走，只吃字符串会钉死）
                //  · 三档不透明度：常态 .78 / 她说话 .55 / 失败 .35（原来是恒 .18）
                //  · 左缘夹在 [16, W-16-112]，不再越出 430 屏宽被裁
                // ⚠️ ValueListenableBuilder 不含 RenderObject，builder 直接返回
                //    Positioned 在 Stack 下合法（同 _cam 的既有用法）。
                ValueListenableBuilder<Cam>(
                  valueListenable: _cam,
                  builder: (BuildContext _, Cam camNow, Widget? _) => PlanTag(
                    goal: _goal,
                    cam: camOf,
                    camObj: camNow,
                    // 失败页也留着（只是压到 .35）—— 目标还在那儿，这是 H-08 三档里
                    // 的第三档；只在派单/执行/结算这些「聚焦态」收掉。
                    visible: lobby || fail,
                    tone: fail
                        ? PlanTagTone.failed
                        : ((_aside != null || _busy)
                              ? PlanTagTone.speaking
                              : PlanTagTone.normal),
                    onTap: () => setState(() {
                      _pickedTask = null;
                      _moment = Moment.main;
                    }),
                  ),
                ),
                // 主线全景：环挂签挂在环上（位置由相机数学给出），面板压在上面
                // ⚠️ 换目标时**整层退场**（`_goalChangeOn`）：原来她问新目标时
                //    主线全景还留在屏上，于是「新目标」输入框的预设词/确定钮
                //    正好压在底部的【让她派这一环】【换目标】上、字幕压在预设词上
                //    —— 宿主截图里的"UI 重合"就是这两处（原型 `MainV.hide()`
                //    也是整层收掉，只留她说话 + 输入）。
                MainView(
                  goal: _goal,
                  published: _publishedPlanIndices(),
                  activeIndex: _activePlanIndex(),
                  selected: main ? _pickedTask : null,
                  elapsed: _active ? _clockText(_execReadout().elapsed) : null,
                  canDispatch: main && !_flow.queueEmpty,
                  visible: main && !_goalChangeOn,
                  // docs/39 M-16：执行中那张牌屉里的证据份数（只读）
                  evidence: _flow.active?.evidence,
                  onClose: () => setState(() => _moment = Moment.lobby),
                  onDispatch: _enterDispatchOrRest,
                  // docs/39 M-20：执行中态的主行动 = 继续执行（回执行面板）
                  onResume: _resumeExec,
                  onSelect: (int i) =>
                      setState(() => _pickedTask = i < 0 ? null : i),
                  onAccept: _acceptPlanTask,
                  // D5：换目标 → 问一句新目标 → `newGoal` 落库（TODO-01；
                  // 「先问小祥」那颗暗号仍带场合上下文开对话）
                  onNewGoal: _beginGoalChange,
                ),
                // 「执行中」药丸（`ui.js` L60）：**执行页自己不显示它**，点它回执行页。
                // 收起执行面板后就靠它回去。
                // docs/39 H-16 / M-02：**主线页不再浮这颗药丸** —— 主线页的计时读数
                // 归抬头里的 status chip（由 P0-B 在 main_view 里做）。这里是同一个
                // 计时数据的第二处呈现，两处并存就是走查 §0 里"药丸压着抬头读数"的来源。
                ListenableBuilder(
                  listenable: _clock,
                  builder: (BuildContext _, Widget? _) => ExecPill(
                    visible: _active && (lobby || sheet),
                    elapsed: _execReadout().elapsed,
                    onTap: () => setState(() {
                      if (_busy) return;
                      _moment = Moment.exec;
                    }),
                  ),
                ),
                // 表演调试台（宿主 2026-10-11）：贴底半屏，上面半屏留给她 ——
                // 点一条预设/动作/表情就地演，边看边调（不进底栏、不写存档）
                PerfDebugPanel(
                  visible: _perfDebugOn,
                  port: _stagePort,
                  onClose: () => setState(() => _perfDebugOn = false),
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
                  onQuickTool: _onQuickTool,
                  paceMs: _paceMs, // docs/22 §R4：同一档位喂聊天气泡的打字机
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
    // 趁她在答访谈卡（几秒到几十秒），**先把拆解跑起来** ——
    // 等访谈答完再发请求就白等一轮网络；这里预取，`_completeOnboarding`
    // 里直接取（答案通常是现成的，取不到才等 [kPlanWaitOnConsume]）。
    _prefetchPlan(
      typed,
      _interviewCat!,
      taskCount: kFirstGoalDays,
      days: kFirstGoalDays,
      withStatus: false, // 绑定期还没有真档案，别让她读演示档
    );
  }

  /// 预取「这一句话的计划」。失败静默（`hasPlan=false`）—— 组装时自然退回类别模板。
  ///
  /// [withStatus]：绑定仪式**不给** `get_status` —— 那一刻 `_flow` 还是演示档，
  /// 让她读会读出一份假档案；换目标时才给（那时状态是真的）。
  void _prefetchPlan(
    String text,
    GoalCategory cat, {
    required int taskCount,
    int? days,
    bool withStatus = false,
  }) {
    final MainlineAgent? agent = _mainlineAgent;
    _planFor = text;
    if (agent == null) {
      _planFuture = null;
      return;
    }
    final int d = days ?? goalDaysFor(text);
    final PlanDraft draft = PlanDraft();
    _planFuture = agent.run(
      goalText: text,
      taskCount: taskCount,
      tools: _mainlineTools(
        goalText: text,
        taskCount: taskCount,
        days: d,
        draft: draft,
        withStatus: withStatus,
      ),
      draft: draft,
      statusLine: withStatus ? _statusLineForAgent() : null,
    );
  }

  /// 立主线这一轮给她哪些工具。
  ///
  /// ⚠️ 只给「读状态 / 翻记忆 / 交主线」——**不给** `swap_quest` /
  ///    `adjust_plan`：换主线时的队列手术由 `_onGoalChangeSubmitted` 自己做，
  ///    让她同一轮里既换主线又动队列会打架（而且拉长这一轮的往返）。
  AgentToolRegistry _mainlineTools({
    required String goalText,
    required int taskCount,
    required int days,
    required PlanDraft draft,
    required bool withStatus,
  }) {
    final AgentToolRegistry reg = AgentToolRegistry();
    final AgentToolRegistry? base = _agentTools;
    if (withStatus && base != null) {
      for (final String name in <String>['get_status', 'recall', 'remember']) {
        final AgentTool? t = base.tool(name);
        if (t != null) reg.register(t);
      }
    }
    reg.register(
      setPlanTool(
        goalText: goalText,
        taskCount: taskCount,
        days: days,
        draft: draft,
      ),
    );
    return reg;
  }

  /// 给她的「宿主档案」一行（`Persona.buildConversation` 的 statusLine 位）
  String _statusLineForAgent() {
    final Goal g = _goal;
    return '${_host.name} · LV${_host.lv} · 连击 ${_host.streak}（最好 ${_host.bestStreak}）· '
        '◈${_host.coins} · 完成 ${_host.doneCount} · 战败 ${_host.failCount} · '
        '最弱维 ${_host.weakest.key}${_host.weakest.value}\n'
        '现主线：${g.text.isEmpty ? '（无）' : '「${g.text}」完成 ${g.doneCount}/${g.plan.length} 单'}';
  }

  /// 取预取的主线环。**最多等 [wait]** —— 宿主已经走到「该铸环了」，
  /// 不能为了好听让她多等一整轮工具循环的超时。
  Future<List<TaskSpec>?> _takePlan(
    String text, {
    int? taskCount,
    Duration wait = kPlanWaitOnConsume,
  }) async {
    if (_planFor != text || _planFuture == null) return null;
    try {
      final MainlineResult r = await _planFuture!.timeout(wait);
      final List<TaskSpec>? tasks = r.tasks;
      if (tasks == null || tasks.isEmpty) return null;
      if (taskCount != null && tasks.length != taskCount) return null;
      return tasks;
    } catch (_) {
      // 超时 / 失败：当没说（调用方走模板）
      return null;
    }
  }

  /// 绑定 · 第 1 幕收卷（原型 `Store.bind(name, plan)` 的新政版）：
  /// 访谈答案 → 3 天 3 张 E/D/C 落档 → 队列 = 计划前几张 + 当日日常 1~2
  /// → 见面礼双倍卡 ×1 → 大厅（首单已在队列）。
  void _completeOnboarding(Map<String, String> answers) {
    unawaited(_bindWithPlan(answers));
  }

  /// 绑定收卷（异步）：先取预取的 LLM 拆解（通常已就绪），取不到就用类别模板。
  /// 内容（拆成哪几环）听拆解；**档位仍是 E/D/C 三天阶梯**（docs/05 锁定）。
  Future<void> _bindWithPlan(Map<String, String> answers) async {
    final GoalCategory cat = _interviewCat!;
    final List<TaskSpec>? planned = await _takePlan(
      _pendingGoalText,
      taskCount: kFirstGoalDays,
    );
    if (!mounted || _interviewCat != cat) return; // 这中间被重置/换目标了
    // ⚠️ 重置存档会冻结存储（原型靠随后的 location.reload() 解冻，我们没有重载），
    //    所以重新绑定这一刻要显式解冻，否则这次存盘会被静默跳过。
    _save.unfreeze();
    setState(() {
      _goal = buildFirstGoal(
        text: _pendingGoalText,
        cat: cat,
        answers: answers,
        planned: planned,
      );
      _flow = QuestFlow(host: _host, goal: _goal);
      _wireFlow(_flow);
      // 绑定即建队列：首环 + 当日日常（store.js bind() 的 L165-167；
      // 每日 1~2 个走 §2.2 新政，不再用 seedForCurrentGoal 的固定 3 张）
      _flow.publishPlanTasks(); // 计划前几张（在手窗口）
      _flow.queue.addAll(_genTodaysDailies());
      _resyncQueueCount();
      // 见面礼：双倍卡 ×1（原型 bind() 的 `S.items.dbl += 1`，
      // 数值语义钉在 kBindGift*；Banner 演出在 build 里挂着）
      _flow.host = _flow.host.copyWith(items: applyBindGift(_flow.host.items));
      _host = _flow.host;
      _lastRollDay = startOfDay(DateTime.now());
      _interviewCat = null;
      // 绑定收卷 = 小景别（boot .64）→ 正常大小（lobby .92）：走慢推，
      // 别让"绑定完就跳到大厅"（宿主验收：要看得见的放大）
      _camGlideMs = 1400;
      _moment = Moment.lobby;
      _banner = true;
    });
    _persist();
    _rememberInterview(cat, answers);
    _sayAside('排好了。三天，一天一张。', holdMs: 2200);
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
    _restore();
    _initAgent(); // 小祥：设置→LLM 网关→文案/聊天服务 + 聊天历史读档
    _maybeRunShot();
  }

  /// **模拟器截图调度**（`--dart-define=SHOT=<场景>`）。
  ///
  /// 为什么要有它：iOS 模拟器上没法点（`simctl` 不支持注入触摸，idb 缺
  /// companion），而原生 Live2D 在模拟器上还会 SIGBUS —— 想核对卡片视觉
  /// 就得**跳过开机屏、直接停在某一页**，再用 `simctl io screenshot` 拍。
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
    _wakeFade.value = 1; // 跳过唤醒淡入，直接"已就位"
    _camSpring.set('lobby', MediaQuery.sizeOf(context), snap: true);
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
    _stagePort?.act('lookAway');
    // 原型这几句**不给 hold**（flows.js L189）→ 走按字数算的默认值
    _sayAside(line, busy: true);
  }

  /// 相机弹簧（`stage.js` L100-103）：切页时把镜头**推**过去，而不是瞬移。
  /// 只有环场与挂签吃这个相机（她本人还没接），所以这一改动只影响环的位置/缩放。
  final CamSpring _camSpring = CamSpring();

  /// 下一拍相机换景别时用**慢推**（毫秒）而不是弹簧直冲；0 = 走弹簧。
  /// 一次性的：`build` 里消费掉就归零（见那边的注释）。
  int _camGlideMs = 0;
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

  /// 失败时把进度带掐暗（原型 `Stage.dimRing` 三下：0 / 90 / 200ms）
  double? _bandMul;

  /// 唤醒时"点亮"进度带用的亮度系数（见 [_igniteBand]）；null = 这一路不参与
  double? _bandLit;

  /// 进度带亮度：**失败变暗** × **唤醒点亮**（两路相乘）
  double _bandLitNow() => (_bandMul ?? 1) * (_bandLit ?? 1);

  /// 道具抽屉开着没（原型 `#exDrawer.on`）；再点一次「道具」收起
  bool _drawerOn = false;

  /// 有没有一单正在执行（原型 `S.active`）—— 收起后它仍然为真，
  /// 所以大厅里那颗「执行中」药丸会一直挂着（`ui.js` L60）
  bool _active = false;

  /// 投影面板是从哪开出来的（原型 `App._sheetFrom`）—— 关掉要回原处：
  /// 从执行页开的就得回执行页，不能一律回大厅
  Moment _sheetFrom = Moment.lobby;

  /// 表演调试台开着没（宿主 2026-10-11：调试预设/动作/表情的设施）
  bool _perfDebugOn = false;

  /// 悬浮牌局开着没（名牒册 / 补给 / 证据来源）。
  ///
  /// ⚠️ 2026-10-12 宿主截图④：名牒册整桌牌**盖在六维雷达上**（层级打架）。
  /// 解法不是改牌，是**让面板退场** —— 牌桌浮起时投影面板与光束一起收掉，
  /// 关掉牌桌再回来。牌本身一个字都不改。
  bool _tableOpen = false;

  /// 开投影面板（原型 `App.sheet(kind)`）
  void _openSheet(SheetKind kind) {
    FocusScope.of(context).unfocus(); // 键盘别压在面板上（宿主验收）
    setState(() {
      _sheetFrom = _moment == Moment.exec ? Moment.exec : Moment.lobby;
      _sheetKind = kind;
      _moment = Moment.sheet;
      _drawerOn = false;
    });
  }

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
    // docs/24 #11：认输垂头（exp_sad01）；**超时**另换惨白脸（exp_pale02）
    _stagePort?.mood('sad');
    _stagePort?.perf('sad', how == 'timeout' ? 'exp_pale02' : 'exp_sad01');
    // 真实判负（store.js fail）：failCount 记账、主线单回队首、生成补救单
    // —— 失败页不再是死局：补救单可接可弃（见 _onChoice）
    final FailOutcome? fo = _flow.fail(how: how);
    setState(() {
      _moment = Moment.fail;
      _quitP = 0;
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
    // 进度带掐暗三下（原型 `Stage.dimRing` 的节奏：0 / 90 / 200ms）
    _ringDim.forward(from: 0);
    _setBandMul(.2);
    Future<void>.delayed(const Duration(milliseconds: 90), () {
      if (mounted) _setBandMul(.6);
    });
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _setBandMul(.15);
    });
  }

  // ── 结算页 / 失败页的出口（「提交卡死」根因③④的修复）──────────────

  /// 回应选项什么时候出现：结算演出播完，或失败页进场（原型是她说完话
  /// 再 `choose()`；失败页那几句插话的时长不阻塞选项）
  bool get _choicesOn =>
      _moment == Moment.fail || (_moment == Moment.result && _resultChoicesOn);

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
  ///
  /// 返回**这一下算不算数** —— `Choices` 据此决定要不要锁死、领位牌要不要
  /// 滑走（见 `widgets/choices.dart` 的 [ChoicePick]）。
  ///
  /// ⚠️ 这里**故意不看 `_busy`**：`_busy` 是"她正在说回来那几句"的演出闸门
  ///    （`_greetAfter` / `_wakeSequence` 两处），而失败页与结算页的回应是
  ///    那两个终态**唯一的出口**。闸门关着就 return 的话，宿主点【……接。】
  ///    没反应、牌却按"已确认"滑走 —— 2026-10-11 实机就是这么卡死的：
  ///    回前台打招呼那 1~3 秒里超时判负（`_onSecond` → `_beginFail`），
  ///    正好撞上宿主第一下点击，整页再无出路，只能杀进程重开。
  bool _onChoice(int i) {
    if (_moment == Moment.result) {
      final bool more = i == 0 && !_flow.queueEmpty;
      setState(() {
        _resultChoicesOn = false;
        _moment = more ? Moment.dispatch : Moment.lobby;
      });
      // docs/39 H-11：回大厅那一拍给「我变强了」的反馈 —— 进度带 600ms 涨
      // + 一声 `count`。进度带的数值本来就是 `_goal.doneCount`（结算已落账），
      // 这里给的是**亮度脉冲**：600ms 内点亮再回落；减免动态时整条不做
      // （§5.5「reduced-motion 只保留数字变化」）。
      if (!more) _harvestBand();
      return true;
    }
    if (_moment == Moment.fail) {
      if (i == 0) {
        _flow.takeRemedy(now: true);
        setState(() {
          _host = _flow.host;
          _moment = Moment.dispatch;
        });
        _persist();
        return true;
      }
      setState(() => _moment = Moment.lobby);
      return true;
    }
    // 不在可回应的时刻（理论上到不了）：不认这一下 —— 牌留在原地，可以再点
    return false;
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
      const List<String> later = <String>['它不会跑。我也不会。', '行，先放我这。别让我等太久。'];
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
    _sayAside(switch (info.count) {
      1 => '目标是你立的。……给你个台阶：[[降一档]]。',
      2 => '今天第 [[${info.count}]] 次退了。系统开始给你建档案了。',
      _ => '第 [[${info.count}]] 次。行，接下来的单，[[按幼儿档]]给你配。',
    }, holdMs: 1500);
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
    final String tier = switch (r.rarity.i) {
      <= 1 => 'smug',
      <= 3 => 'pleased',
      _ => 'tsun',
    };
    _stagePort?.mood(tier); // 基础脸（档位情绪）
    // docs/24 #8/#9/#10 结算表演（借的表情 3s 后回到上面的档位脸）：
    //   升级 > 暴击 > 档位动作 —— 一拍只演一件事（docs/14 表演预算）
    if (r.ups.isNotEmpty) {
      _stagePort?.perf('kime', 'exp_kime01', priority: 3); // #10 升级定格
    } else if (r.crit) {
      _stagePort?.mood('surprised');
      _stagePort?.perf('surprised', 'exp_surprised01', priority: 3); // #9 暴击
    } else {
      switch (tier) {
        case 'smug':
          _stagePort?.perf('smile', 'exp_bsmile01');
        case 'pleased':
          _stagePort?.perf('kime', 'exp_kime01');
        default:
          if (r.rarity.i >= 4) {
            _stagePort?.act('happy'); // 高级单：得意（原有行为）
          } else {
            _stagePort?.perf('denial', 'exp_shy01'); // tsun：嘴硬
          }
      }
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
    if (r.finale) _onFinale(r); // 收官：下一条主线已经钉好，得说一句
    _takeSettleLine(r); // 结算文案接管：LLM 回了顶掉上面这句兜底
  }

  /// 收官出口（TODO-01）：第 N 环 CLEAR 时下一条主线**已经在 settle 里落库**
  /// （`QuestFlow._applyFinale`），这里只负责把这件事说出来 + 落盘。
  ///
  /// 她不会说「你完成了，再见」—— 叙事没有终点：
  /// 环数变了、题目变了，路还长。
  void _onFinale(QuestResult r) {
    // docs/24 #19 收官：定格亮相（kime + exp_bsmile02，强制优先级盖过结算动作）
    _stagePort?.perf('kime', 'exp_bsmile02', priority: 3);
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

  /// docs/39 H-17 · 底部安全区下限（不叠加，只取下限）。
  ///
  /// 底栏那一条（padding 26→34、底注 8→14）归 `dock.dart`（P0-A 已做），
  /// 这里只管 main.dart 自己挂的贴底件。取 `math.max(34, padding.bottom)`：
  /// iPhone 的 Home Indicator 恰好 34 → 位置一点不变；MuMu / 无手势条 0 → 也
  /// 不变（宿主说的"不改 MuMu 观感"）；只有真正更大的底部安全区才抬起来。
  double _safeBottom(BuildContext context) =>
      math.max(34, MediaQuery.paddingOf(context).bottom);

  /// 比 34 这条基准多出来的那几 pt（今天恒为 0，给以后留的口径）
  double _bottomExtra(BuildContext context) => _safeBottom(context) - 34;

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
    if (_moment == Moment.fail) return _BackTarget.fail;
    if (_moment == Moment.main) {
      if (_pickedTask != null) return _BackTarget.drawer;
      return _BackTarget.main;
    }
    return null;
  }

  /// 返回键真正落地（与 × 同语义）
  void _onSystemBack() {
    switch (_popScopeTarget()) {
      case _BackTarget.fail:
        _onChoice(1); // 失败页接住了返回键 = 今天算了 → 大厅
      case _BackTarget.drawer:
        setState(() => _pickedTask = null);
      case _BackTarget.main:
        setState(() => _moment = Moment.lobby);
      case null:
        break;
    }
  }

  /// 回执行面板（主线页「继续执行」/ 牌屉里执行中那张的 CTA）
  void _resumeExec() {
    if (_busy) return;
    setState(() => _moment = Moment.exec);
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

  /// 进派单板的唯一入口：队列空就不进（换日补发已由 `_rollDayIfNeeded`
  /// 在启动/回前台时做过；真清空了就用一句插话接住，别让宿主接到幻影单）
  void _enterDispatchOrRest() {
    if (_busy) return;
    if (_flow.queueEmpty) {
      _sayAside('今天的单，清干净了。明天再来。', holdMs: 2200);
      return;
    }
    setState(() => _moment = Moment.dispatch);
    // 发布这一拍：原型 flows.js:237 `Sound.play('ding'); buzz(12)`
    // （和稍后单子落板的 `land` 是**两拍**：先"钉单"再"落板"，别合成一次）
    unawaited(Sfx.play('publish'));
    unawaited(Haptics.buzz('publish'));
    // docs/24 #3 发布任务：摆个定格（kime + kime 脸），表情 3s 后还给当前情绪
    _stagePort?.perf('kime', 'exp_kime01');
    _takeDispatchLine(); // 发布文案接管：LLM 回了顶掉「接不接？」
  }

  /// 执行中那张的计时读数（`12:04`）
  static String _clockText(Duration d) {
    final int m = d.inMinutes;
    final String ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  /// 原型 `hhmm(Clock.now())`
  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  void _setBandMul(double v) => setState(() => _bandMul = v);

  /// docs/39 H-11「进度收割」：结算回大厅那一拍，进度带 600ms 亮一下 + `count`。
  ///
  /// 真正的弧增长由 [ProgressBand] 按新的 `done/total` 重绘（值已经在 settle 里
  /// 落好），这里只补那一段**看得见的**亮度爬升；减免动态下什么都不做，
  /// 数字变化照旧（§5.5）。
  void _harvestBand() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    Sfx.play('count');
    _setBandMul(.35);
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      // 期间可能又结算了一次 / 页面已经走了：只在还挂着时回落
      if (!mounted || _moment != Moment.lobby) return;
      _setBandMul(1);
    });
  }

  /// 队列里已经有单的计划序号（主线页据此区分「可接 / 待发布」）
  Set<int> _publishedPlanIndices() => <int>{
    for (final Quest q in _flow.queue)
      if (q.kind == 'main' && q.goalId == _goal.id && q.planIndex >= 0)
        q.planIndex,
  };

  /// 正在执行的那张在清单里的序号（null = 没有）
  int? _activePlanIndex() {
    final Quest? a = _flow.active?.task;
    if (a == null || a.kind != 'main' || a.goalId != _goal.id) return null;
    return a.planIndex;
  }

  /// 主线页上按住那条 = 接这张（沿用「拔单 = 开始执行」的手感）：
  /// 先在队列里找出这张单（没派就现派一张），再走 [ _beginExec ] 那条老路。
  void _acceptPlanTask(int i) {
    if (_busy) return;
    if (_flow.active != null) {
      _sayAside('手上还有一张没交。先把它了了。', holdMs: 1800);
      return;
    }
    // 没派就现派这一张（「待发布」那条也能直接接 —— 宿主想先做哪张就做哪张）
    final Quest? q = _flow.publishPlanTask(i);
    if (q == null) return;
    // ⚠️ **只把这张挪到队首**，接单仍由 `_beginExec()` 那一条老路做（它 accept 的是
    //    队首）—— 这里若先 `accept` 一次，_beginExec 会再 accept 一张别的，
    //    刚点的那张就从队列里凭空消失（踩过）。
    _flow.queue.removeWhere((Quest t) => t.serial == q.serial);
    _flow.queue.insert(0, q);
    setState(() {
      _pickedTask = null;
      _host = _flow.host;
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

    // 她的睁眼编排（原型 wake() L77-84；未睡=降级路线时 no-op 直接过）
    await _stagePort?.wakeEyes();

    // ── 转场这一拍（2026-10-11 宿主验收：「从唤醒到主界面转场太过突兀, 像是
    //    直接切换」「live2d 是直接过去的, 应该有个转场动画」）──────────────
    // 两处一起改（2026-10-11 宿主第二次验收）：
    //  ① 平台视图改成**固定尺寸族 + Transform**（见 `Live2DStage.kViewFamilies`）
    //     —— 推镜头期间不再每帧重建 FBO，她**真的在动**了；
    //  ② 这一拍换景别走**慢推**（1.4s easeInOutCubic，`_camGlideMs`）——
    //     弹簧 0.5s 到位，配上亮帧/界面淡入就是"直接切过去"的观感。
    // 原型用 `Stage.glitch(420,1)` 把这一下盖住；我们对应地再补一拍青蓝过渡，
    // 同时把界面层/环场的淡入（_wakeFade）从这一刻起跑 —— 于是
    // 「睁眼 → 环亮起 → 界面浮上来 → 落进待机」是一段连续的推移，不是硬切。
    _pulse(color: const Color(0xFF9FF0FF), a: .14, ms: 320, shakePx: 0);
    _wakeFade.forward(from: 0);

    if (_goal.isEmpty && !_resumedExec) {
      setState(() => _moment = Moment.onboard);
      return; // 绑定仪式的问话走 LineLayer（askGoal），不叠离开问候
    }
    // 小景别（boot .64）→ 正常大小（lobby .92）：这一段要**看得见地放大**
    _camGlideMs = 1400;
    setState(() => _moment = _resumedExec ? Moment.exec : Moment.lobby);

    // 逐环点亮（原型在这段之后还有 500ms 留白，才轮到 greet）
    await _igniteBand();

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
    _stagePort?.act('present');
    _stagePort?.mood(k == AwayKind.back10m ? 'smug' : 'neutral');
    _stagePort?.idleMood('neutral');
    _sayAside(AwayGreeting.text(k, away), holdMs: 3200, busy: true);
  }

  /// 唤醒时点亮进度带的调度（原型 `flows.js:87-93` 的逐环点亮）。
  /// 环没了、只剩**一条**进度带，于是那 8 拍收敛成一拍：
  /// 0→1 爬 420ms，起手一声 `ignite` + 一次震动（原来每环各一次）。
  static const int _kIgniteRampMs = 420;

  /// 唤醒点亮的驱动器（懒建：没被唤醒过就不白占一个 ticker）
  AnimationController? _igniteC;

  Future<void> _igniteBand() async {
    if (_goal.plan.isEmpty) return;
    final AnimationController c = _igniteC ??= AnimationController(vsync: this);
    c.duration = const Duration(milliseconds: _kIgniteRampMs);
    unawaited(Sfx.play('ignite'));
    unawaited(Haptics.buzz('ignite'));

    void tick() =>
        setState(() => _bandLit = Curves.easeOutCubic.transform(c.value));

    c.addListener(tick);
    tick();
    try {
      await c.forward(from: 0).orCancel;
    } catch (_) {
      // 演出被切断（页面销毁/连续唤醒）：安静收场，别把异常抛给调用方
    }
    c.removeListener(tick);
    if (mounted) setState(() => _bandLit = null);
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
    // TODO-01 兜底：存档里这条主线**已经走完**（收官发生在「自动续主线」之前
    // 的老档）→ 补铸下一条并钉队首，别让认真用户重启后停在叙事终点。
    if (_flow.applyFinaleOutcome()) {
      setState(() {
        _host = _flow.host;
        _goal = _flow.goal;
      });
      _persist();
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
    // TODO-07 网关热更：退订设置广播，State 卸载后不再收回调
    SettingsStore.removeListener(_onSettingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    _camTicker.dispose();
    _cam.dispose();
    _ringDim.dispose();
    _igniteC?.dispose();
    _flashC.dispose();
    _fx.dispose();
    _ask.dispose();
    _asideDone?.cancel();
    _pokeReset?.cancel();
    _wakeFade.dispose();
    super.dispose();
  }
}

/// 进度带的**活相位**（docs/39 H-10）。
///
/// 原来 `t: 0` 是写死的 —— 虚线不转、彗星不动，真机上那一圈看着像贴纸。
/// 这里只做一件事：用一个 **20fps** 的定时器推 `t`（秒），交给既有
/// [ProgressBandPainter] 的 `shouldRepaint`（它本来就在比 `t`）。
///
/// ⚠️ 三条纪律：
///  1. **不要 60fps**：§5.5 要求新增动画一律 15–20fps；50ms 一拍足够
///     （这条带子只有虚线在爬，肉眼分辨不出 20 与 60）。
///  2. **只在「有待机循环」时才跑**：减弱动态 / 不可见 / 无清单 → 停表，
///     一帧都不刷。
///  3. **不要 setState 整屏**：这一层只重建自己（一个 CustomPaint）。
///
/// 说明：任务描述里的「完成弧 α .62 → .75」在 `progress_band.dart` 的画笔里，
/// 那个文件不在本任务的写入面 —— 已在完成备注里列为待收口项。
class ProgressBandLive extends StatefulWidget {
  const ProgressBandLive({
    super.key,
    required this.done,
    required this.total,
    required this.cam,
    this.camObj,
    this.lit = 1,
    this.dim = 1,
    this.scan = 0,
    this.visible = true,
  });

  final int done;
  final int total;
  final String cam;
  final Cam? camObj;
  final double lit;
  final double dim;
  final double scan;
  final bool visible;

  @override
  State<ProgressBandLive> createState() => _ProgressBandLiveState();
}

class _ProgressBandLiveState extends State<ProgressBandLive> {
  /// 相位（秒）。20fps = 每拍 +.05
  double _t = 0;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ProgressBandLive old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 该不该跑：可见 + 有清单 + 没开「减弱动态」
  void _sync() {
    final bool want =
        widget.visible &&
        widget.total > 0 &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (want == (_timer != null)) return;
    if (!want) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer = Timer.periodic(const Duration(milliseconds: 50), (Timer _) {
      if (!mounted) return;
      setState(() => _t = (_t + .05) % 1000);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ProgressBand(
      done: widget.done,
      total: widget.total,
      cam: widget.cam,
      camObj: widget.camObj,
      t: _t,
      lit: widget.lit,
      dim: widget.dim,
      scan: widget.scan,
      visible: widget.visible,
    );
  }
}

/// **五态陈列页**（只在 `--dart-define=SHOT=states` 时挂载）。
///
/// 为什么需要它：五态（可接 / 执行中 / 已完成 / 待发布 / 已放弃）在真实数据里
/// 不会同时出现，而它们**必须一起比对**才能判断「形状 + 颜色双编码是否成立」。
/// 这是设计验收页，不是产品页面 —— 真机与日常运行永远不会走到。
class CardStatesGallery extends StatelessWidget {
  const CardStatesGallery({super.key});

  static const List<(DutyState, String)> _states = <(DutyState, String)>[
    (DutyState.open, 'C'),
    (DutyState.active, 'B'),
    (DutyState.done, 'A'),
    (DutyState.sealed, 'E'),
    (DutyState.abandoned, 'F'),
  ];

  static const List<String> _titles = <String>[
    '跑完 5 公里',
    '早上空腹称重',
    '走满 8000 步',
    '今天不喝含糖饮料',
    '做 20 个俯卧撑',
  ];

  static const List<String> _metas = <String>[
    '45 分钟 · 跑步 App 截图',
    '7 分钟 · 体重秤照片',
    '30 分钟 · 步数截图',
    '1 天 · 饮料清单',
    '10 分钟 · 训练视频',
  ];

  static const List<String> _notes = <String>[
    '接了就开计时。',
    '计时中。别磨蹭。',
    '这单已经记在账上了。',
    '还没派到你手上。',
    '这单作废了。',
  ];

  static const List<String> _glyphs = <String>['力', '敏', '体', '智', '知'];

  TableCard _card(int i) {
    final (DutyState st, String rank) = _states[i];
    return TableCard(
      id: 'state.$i',
      kicker: 'MAIN · 0${i + 1}',
      title: _titles[i],
      glyph: _glyphs[i],
      rank: rank,
      accent: Rarity.of(rank).color,
      loot: <String>['EXP ${12 + i * 4}', '◈ ${6 + i * 2}'],
      dutyState: st,
      dutyMeta: _metas[i],
      elapsed: st == DutyState.active ? '12:04' : null,
      sealWord: st == DutyState.done ? '已完成' : null,
      enabled: st == DutyState.open,
      locked: st == DutyState.sealed,
      index: i + 1,
      note: _notes[i],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.voidBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 32, 12, 24),
          children: <Widget>[
            Text(
              'CARD STATES · 五态陈列',
              style: fs(
                family: F.mono,
                size: 11,
                wght: 600,
                ls: 1.8,
                color: C.blue,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '可接 / 执行中 / 已完成 / 待发布 / 已放弃',
              style: fs(family: F.cn, size: 12, wght: 400, color: C.mist),
            ),
            const SizedBox(height: 16),
            for (int i = 0; i < _states.length; i++) ...<Widget>[
              Center(
                child: SizedBox(
                  width: 148,
                  height: 240,
                  child: CardFace(
                    key: Key('gallery.$i'),
                    skin: CardSkin.duty,
                    card: _card(i),
                    size: CardTableSize.m,
                    lead: true,
                    dims: const Dims(148, 240),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

/// 系统返回键要消费的那一层（docs/39 M-04）。
///
/// 顺序即优先级：失败页 > 牌屉 > 主线；null = 交给系统（退到桌面）。
enum _BackTarget { fail, drawer, main }

/// 「换目标」输入幕左上那颗**常驻取消圆**（docs/39 M-24）。
///
/// 为什么要有它：原来取消是牌列最右一张「算了，不换」，真机上被 430 屏宽裁掉
/// 一半（走查图 04/08）；而键盘一弹，整条牌列连布局都不占（`ask_field.dart` 的
/// 布局纪律 2）—— 取消就彻底消失了，宿主只能硬着头皮换目标。现在它**不依赖
/// 牌列**：与 × 同一套语言（玻璃圆 + 1px 描边 + PressScale 按下 .94 + tap 音），
/// 44×44 命中，键盘弹不弹都在。
///
/// 位置：top = 安全区下限（math.max(18, padding.top)）+ 14，left 20 —— 与
/// HUD 的左边距（H-02 的 20）同轴；无刘海机型（padding.top = 0）落在 32，
/// 有刘海真机落在 `max(18, 59) + 14 = 73`，都在她的脸（10%~30% 屏高）之上。
class _GoalChangeChrome extends StatefulWidget {
  const _GoalChangeChrome({required this.visible, required this.onCancel});

  final bool visible;
  final VoidCallback onCancel;

  @override
  State<_GoalChangeChrome> createState() => _GoalChangeChromeState();
}

class _GoalChangeChromeState extends State<_GoalChangeChrome>
    with SingleTickerProviderStateMixin {
  /// 进 240ms kOut（§5.3「输入幕 240ms 进」）；出用同一个进度反着走。
  /// 首帧按 visible 落位：不可见时 0、可见时 1（不补播首屏入场）。
  late final AnimationController _c = AnimationController(
    vsync: this,
    value: widget.visible ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _GoalChangeChrome old) {
    super.didUpdateWidget(old);
    if (old.visible == widget.visible) return;
    // 减弱动态：直接落终态（§5.5）
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.value = widget.visible ? 1 : 0;
      return;
    }
    _c.duration = const Duration(milliseconds: 240);
    if (widget.visible) {
      _c.forward(from: 0);
    } else {
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 顶部安全区下限：无刘海 0 → 18，有刘海真机 → max(18, 59) = 59；
    // 再 +14 才是这颗圆的上缘（不压在状态栏/岛上，也与 HUD 的 20 左边距同轴）
    final double top = math.max(18, MediaQuery.paddingOf(context).top) + 14;
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext _, Widget? child) {
        // M-24「进 240ms kOut」
        final double k = kOut.transform(_c.value).clamp(0.0, 1.0);
        return Positioned(
          left: 20,
          right: 20,
          top: top,
          child: IgnorePointer(
            ignoring: k < .01,
            child: Opacity(
              opacity: k,
              child: Transform.translate(
                offset: Offset(
                  0,
                  _c.status == AnimationStatus.reverse
                      ? 8 *
                            (1 - k) // 出：往下沉 8
                      : -8 * (1 - k),
                ), // 进：从 -8 落到 0
                child: child,
              ),
            ),
          ),
        );
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 44,
            height: 44,
            child: PressScale(
              scale: .94,
              onTap: () {
                Sfx.play('tap');
                widget.onCancel();
              },
              // 视觉 44 = 命中 44（44 已达标，§5.6）
              child: Container(
                key: const Key('ask.cancel'),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x99040E20), // rgba(4,14,32,.60)
                  border: Border.all(color: C.line, width: 1),
                ),
                child: Text(
                  '←',
                  style: fs(
                    family: F.cn,
                    size: 20,
                    wght: 500,
                    height: 1,
                    color: C.ice,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 顶部 11pt 上下文行：「换目标 · 旧主线会清空」
          // （走查图 04：整屏只剩她的腿/牌列/输入条，没有一句"这一下会清掉旧主线"）
          Flexible(
            child: Text(
              '换目标 · 旧主线会清空',
              key: const Key('ask.context'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: fs(
                family: F.cn,
                size: 11,
                wght: 500,
                ls: .8,
                height: 1,
                color: C.mist,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 唤醒过场用：把界面层按 0→1 淡入（吃 [AppShellState._wakeFade]）。
/// 开机态这些层是**布尔门控**（`visible: lobby`）—— 切页那一瞬间硬出现，
/// 观感就是「直接切换」。包一层 Opacity 后它们随推镜头一起浮上来。
class _WakeFade extends StatelessWidget {
  const _WakeFade({required this.t, required this.child});

  final Animation<double> t;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      builder: (BuildContext _, Widget? c) => Opacity(
        opacity: Curves.easeOut.transform(t.value.clamp(0.0, 1.0)),
        child: c,
      ),
      child: child,
    );
  }
}
