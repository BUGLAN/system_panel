import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design/tokens.dart';
import 'screens/boot_screen.dart';
import 'state/host_state.dart';
import 'widgets/bg_layer.dart';
import 'widgets/dock.dart';
import 'widgets/hud.dart';
import 'widgets/line_layer.dart';

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

  /// 开机自检是否已过（原型的 #app.booting）
  bool _booted = false;

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    // lineAt('lobby') = H * .6（flows.js L23）
    final double lineY = size.height * .6;

    return Scaffold(
      backgroundColor: C.voidBg,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // 0 · 天幕（她身后的世界）
          //   开机时写 SYSTEM，进大厅后写宿主的目标（flows.js `setWord`）
          BgLayer(word: _booted ? '半马' : 'SYSTEM', latin: !_booted),
          // TODO(step3+): 1 · 舞台 —— Live2D 角色 + 套在她身上的主线环 + 环挂签/环标签
          // 2 · 界面
          Hud(state: _host, visible: _booted),
          LineLayer(
            text: '我手里有 5 单。都是给你的。',
            mood: '尚可',
            y: lineY,
            visible: _booted,
          ),
          Dock(state: _host, visible: _booted),
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
