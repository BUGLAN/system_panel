import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design/tokens.dart';
import 'screens/boot_screen.dart';
import 'state/host_state.dart';
import 'state/quest.dart';
import 'state/result.dart';
import 'widgets/bg_layer.dart';
import 'widgets/dock.dart';
import 'widgets/exec_panel.dart';
import 'widgets/hud.dart';
import 'widgets/line_layer.dart';
import 'widgets/plate.dart';
import 'widgets/result_panel.dart';

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
enum Moment { boot, lobby, dispatch, exec, result }

/// 所有页面的共同外壳，对应原型的 `#app` + `#shake`：
///   天幕（#bg）→ 舞台（#stage）→ 界面（#ui）→ 覆盖层
///
/// 每一步复刻一页。当前已复刻：开机自检、大厅、派单板、执行面板、结算。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// 行为逻辑未定，先用与原型「老宿主 · 第 23 天」一致的演示档
  static const HostState _host = HostState.demo;
  static const Quest _quest = Quest.demo;
  static const QuestResult _result = QuestResult.demo;

  Moment _moment = Moment.boot;

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    // lineAt：lobby = H*.6，dispatch = H-448-120（flows.js L23）
    final double lineY = _moment == Moment.dispatch
        ? size.height - 568
        : size.height * .6;

    final bool lobby = _moment == Moment.lobby;
    final bool dispatch = _moment == Moment.dispatch;
    final bool exec = _moment == Moment.exec;
    final bool result = _moment == Moment.result;
    final bool boot = _moment == Moment.boot;
    // focus+dim：派单与结算都会把 HUD/底栏收走、天幕压暗
    final bool dim = dispatch || result;

    return Scaffold(
      backgroundColor: C.voidBg,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // 0 · 天幕（她身后的世界）
          //   开机时写 SYSTEM，进大厅后写宿主的目标（flows.js `setWord`）
          AnimatedOpacity(
            opacity: dim ? .35 : 1, // #app.dim #bg
            duration: const Duration(milliseconds: 800),
            child: BgLayer(word: boot ? 'SYSTEM' : '半马', latin: boot),
          ),
          // TODO(step7+): 1 · 舞台 —— Live2D 角色 + 套在她身上的主线环 + 环挂签/环标签
          // 2 · 界面
          Hud(state: _host, visible: lobby || exec),
          LineLayer(
            text: dispatch ? '接不接？' : '我手里有 5 单。都是给你的。',
            mood: dispatch ? '监视' : '尚可',
            y: lineY,
            visible: lobby || dispatch,
          ),
          Dock(
            state: _host,
            visible: lobby,
            onCta: () => setState(() => _moment = Moment.dispatch),
          ),
          // 派单板
          Plate(
            quest: _quest,
            host: _host,
            visible: dispatch,
            onAccept: () => setState(() => _moment = Moment.exec),
          ),
          PlateAlt(labels: const <String>['换一个', '等会儿'], visible: dispatch),
          // 执行面板
          ExecPanel(
            quest: _quest,
            elapsed: const Duration(minutes: 7),
            critChance: .12,
            itemCount: 3,
            evidenceCount: 0,
            visible: exec,
            onSubmit: () => setState(() => _moment = Moment.result),
          ),
          // 结算
          ResultPanel(result: _result, visible: result, onSave: () {}),
          // 3 · 覆盖层：开机自检（她醒来之前压在最上面）
          if (boot)
            BootScreen(
              host: '${_host.name} · LV${_host.lv}',
              onWake: () => setState(() => _moment = Moment.lobby),
            ),
        ],
      ),
    );
  }
}
