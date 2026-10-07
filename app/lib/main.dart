import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design/tokens.dart';
import 'screens/boot_screen.dart';
import 'state/host_state.dart';
import 'state/quest.dart';
import 'widgets/bg_layer.dart';
import 'widgets/dock.dart';
import 'widgets/hud.dart';
import 'widgets/line_layer.dart';
import 'widgets/plate.dart';

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

/// 所有页面的共同外壳，对应原型的 `#app` + `#shake`：
///   天幕（#bg）→ 舞台（#stage）→ 界面（#ui）→ 覆盖层
///
/// 每一步复刻一页。当前已复刻：开机自检、大厅（HUD / 字幕 / 底栏）。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// 行为逻辑未定，先用与原型「老宿主 · 第 23 天」一致的演示档
  static const HostState _host = HostState.demo;
  static const Quest _quest = Quest.demo;

  /// 开机自检是否已过（原型的 #app.booting）
  bool _booted = false;

  /// 是否在看派单板（原型的 dispatch 时刻：HUD/底栏收走、天幕压暗到 .35）
  bool _dispatching = false;

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    // lineAt('lobby') = H * .6；lineAt('dispatch') = H - 448 - 120（flows.js L23）
    final double lineY = _dispatching ? size.height - 568 : size.height * .6;
    final bool lobby = _booted && !_dispatching;

    return Scaffold(
      backgroundColor: C.voidBg,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // 0 · 天幕（她身后的世界）
          //   开机时写 SYSTEM，进大厅后写宿主的目标（flows.js `setWord`）
          AnimatedOpacity(
            opacity: _dispatching ? .35 : 1, // #app.dim #bg
            duration: const Duration(milliseconds: 800),
            child: BgLayer(word: _booted ? '半马' : 'SYSTEM', latin: !_booted),
          ),
          // TODO(step4+): 1 · 舞台 —— Live2D 角色 + 套在她身上的主线环 + 环挂签/环标签
          // 2 · 界面
          Hud(state: _host, visible: lobby),
          LineLayer(
            text: _dispatching ? '接不接？' : '我手里有 5 单。都是给你的。',
            mood: _dispatching ? '监视' : '尚可',
            y: lineY,
            visible: _booted,
          ),
          Dock(
            state: _host,
            visible: lobby,
            onCta: () => setState(() => _dispatching = true),
          ),
          // 派单板
          Plate(quest: _quest, host: _host, visible: _dispatching),
          PlateAlt(labels: const <String>['换一个', '等会儿'], visible: _dispatching),
          // 3 · 覆盖层：开机自检（她醒来之前压在最上面）
          if (!_booted)
            BootScreen(
              host: '${_host.name} · LV${_host.lv}',
              onWake: () => setState(() => _booted = true),
            ),
        ],
      ),
    );
  }
}
