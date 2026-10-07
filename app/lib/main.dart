import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design/tokens.dart';
import 'screens/boot_screen.dart';
import 'widgets/bg_layer.dart';

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
///   天幕（#bg）→ 舞台（#stage，模型未移植，暂缺）→ 界面（#ui）→ 覆盖层
/// 每一步复刻一页，当前只有「开机」。
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: C.voidBg,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          BgLayer(),
          // TODO(step2+): 舞台层 —— Live2D 角色 + 套在她身上的主线环
          // TODO(step3+): 界面层 —— HUD / 台词区 / 底栏 / 各时刻面板
          BootScreen(),
        ],
      ),
    );
  }
}
